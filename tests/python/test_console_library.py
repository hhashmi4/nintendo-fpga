from dataclasses import replace
import json
import os
from pathlib import Path

import pytest

from software.nes_loader.library import GameLibrary, GameLibraryError, GameNotLoadableError, UnsafeGameSelection
from software.nes_loader.ines import load_runtime_image, INESError
from software.nes_loader.transport import MockRuntimeLoaderTransport, TransportError, TransportProtocolError
from software.nes_loader.protocol import Command as LoaderOperation, LoaderState
from software.nes_loader.loader import LoadPlan
from software.nes_console.protocol import Status, State, Source, Command
from software.nes_console.transport import ConsoleError
from software.nes_console.library_protocol import (
    LibraryTransport, LibraryStatus, Operation, Stage, page_words, display_title,
    MAGIC, VERSION, LIMITS, GLYPHS,
)
from software.nes_console.library_service import LibraryService, read_titles
from verification.runtime_loader_fixtures import make_ines


def test_bounded_discovery_inspects_only_retained_headers(tmp_path, monkeypatch):
    import software.nes_loader.library as module
    for n in reversed(range(300)):
        (tmp_path / f'Game {n:03}.nes').write_bytes(make_ines())
    calls = []
    original = module.inspect_ines_file
    def inspect(path, **kwargs):
        calls.append(path)
        assert kwargs['dir_fd'] is not None
        return original(path, **kwargs)
    monkeypatch.setattr(module, 'inspect_ines_file', inspect)
    library = GameLibrary(tmp_path)
    entries = library.scan(limit=256)
    assert len(entries) == len(calls) == 256 and library.truncated
    assert entries[0].game_id == 'Game 000.nes' and entries[-1].game_id == 'Game 255.nes'


@pytest.mark.parametrize('limit', [0, -1, 1.5, True, '4'])
def test_invalid_discovery_limits(tmp_path, limit):
    with pytest.raises(ValueError): GameLibrary(tmp_path).scan(limit=limit)


@pytest.mark.parametrize('change', ['replace', 'mutate', 'symlink', 'root'])
def test_snapshot_rejects_replacement_and_mutation(tmp_path, change):
    root = tmp_path / 'games'; root.mkdir()
    path = root / 'Same name.nes'; path.write_bytes(make_ines())
    library = GameLibrary(root); entry = library.scan()[0]
    if change == 'replace':
        path.unlink(); path.write_bytes(make_ines())
    elif change == 'mutate':
        with path.open('r+b') as stream: stream.seek(20); stream.write(b'Z')
    elif change == 'symlink':
        outside = tmp_path / 'outside.nes'; outside.write_bytes(make_ines())
        path.unlink(); path.symlink_to(outside)
    else:
        root.rename(tmp_path / 'old'); root.mkdir(); (root / path.name).write_bytes(make_ines())
    with pytest.raises((GameNotLoadableError, UnsafeGameSelection)):
        library.load_entry(entry)


def test_sparse_oversize_file_rejected_without_payload_read(tmp_path):
    path = tmp_path / 'huge.nes'
    with path.open('wb') as stream:
        stream.write(make_ines()[:16]); stream.truncate(1 << 30)
    with pytest.raises(INESError, match='trailing'): load_runtime_image(path)


@pytest.mark.parametrize('name', ['Game With Spaces', '星のゲーム', 'Éclair', 'A\nB\x00C', 'a'*100, 'Duplicate'])
def test_titles_are_bounded_font_safe_without_changing_identity(name):
    encoded = display_title(name)
    assert len(encoded) == 24 and set(encoded.decode()) <= GLYPHS
    if len(name) > 24: assert encoded.endswith(b'...')


@pytest.mark.parametrize('mapper', [0, 1, 2, 3, 4, 255])
@pytest.mark.parametrize('prg,chr_', [(1, 0), (1, 1), (2, 0), (2, 1), (3, 1), (1, 2)])
def test_metadata_matches_real_capacity_policy(tmp_path, mapper, prg, chr_):
    (tmp_path / 'test.nes').write_bytes(make_ines(prg_banks=prg, chr_banks=chr_,
        flags6=(mapper & 15)<<4, flags7=mapper & 240))
    entries = GameLibrary(tmp_path).scan(); words = page_words(entries, 0)
    meta = words[6]
    assert meta & 255 == mapper and (meta >> 8) & 255 == prg and (meta >> 16) & 255 == chr_
    assert (meta >> 24) & 3 == (2 if mapper == 0 and prg in (1,2) and chr_ in (0,1) else 1)
    assert len(words) == 28 and words[13] == words[20] == words[27] == 0


def test_nes2_never_claims_classic_mapper_or_sizes(tmp_path):
    (tmp_path / 'nes2.nes').write_bytes(make_ines(flags7=8))
    assert page_words(GameLibrary(tmp_path).scan(), 0)[6] == 0x05000000


@pytest.mark.parametrize('data', [[], {'x.nes': 3}, {'x.nes': ''}, {'../x.nes': 'X'}, {'x.nes':'a'*129}])
def test_invalid_optional_metadata(tmp_path, data):
    path=tmp_path/'titles.json';path.write_text(json.dumps(data))
    with pytest.raises((ValueError, UnsafeGameSelection)):read_titles(path)


def test_metadata_is_optional_and_presentation_only(tmp_path):
    (tmp_path/'One.nes').write_bytes(make_ines())
    path=tmp_path/'titles.json';path.write_text('{"One.nes":"Optional title"}')
    entries=GameLibrary(tmp_path).scan()
    words=page_words(entries,0,read_titles(path))
    assert b''.join(w.to_bytes(4,'little') for w in words)[:24] == b'OPTIONAL TITLE          '
    assert entries[0].game_id=='One.nes' and read_titles(None)=={}
    path.write_bytes(b' '*65537)
    with pytest.raises(ValueError):read_titles(path)


class Console:
    def __init__(self):
        self.value=Status(State.MENU,Source.SYSTEM,Source.SYSTEM,True,False,0,0,10)
        self.commands=[]
    def status(self):return self.value
    def set(self,state,epoch=None):
        self.value=replace(self.value,state=state,epoch=self.value.epoch+1 if epoch is None else epoch,
                           video_source=Source.GAME if state==State.GAME else Source.SYSTEM)
    def menu(self):self.set(State.MENU);return self.value
    def exchange(self,command,epoch):
        if epoch!=self.value.epoch:raise ConsoleError('stale')
        self.commands.append(command)
        self.set(State.GAME if command==Command.LAUNCH else State.ERROR)
    def wait_state(self,state,*,epoch=None):
        if self.value.state!=state or (epoch is not None and epoch!=self.value.epoch):raise ConsoleError('superseded')
        return self.value


class Library:
    def __init__(self,console):
        self.console=console;self.stages=[];self.published=[];self.enabled=False
        self.opened=True;self.revision=1
    def status(self):return LibraryStatus(self.console.status(),(int(self.enabled)<<19)|(int(self.opened)<<20),self.revision)
    def exchange(self,op,status):
        if op==Operation.CLAIM:self.stages.append(Stage.VALIDATING)
        if op==Operation.DISABLE:self.enabled=False
        self.revision+=1
    def publish(self,entries,status,**kwargs):self.published.append(tuple(entries));self.enabled=True
    def stage(self,stage,*,epoch=None):
        if epoch is not None and epoch!=self.console.status().epoch:raise ConsoleError('stale stage')
        self.stages.append(stage)
        self.revision+=1


class Loader(MockRuntimeLoaderTransport):
    def __init__(self,console,interrupt=None):
        super().__init__();self.console=console;self.interrupt=interrupt;self.count=0
    def send(self,item,*,timeout_s):
        self.count+=1
        if self.interrupt=='failure' and self.count==20:raise TransportError('injected transfer failure')
        try:
            result=super().send(item,timeout_s=timeout_s)
        except TransportProtocolError:
            if self.read_status().state==LoaderState.ERROR:self.console.set(State.ERROR)
            raise
        if item.stage=='BEGIN':self.console.set(State.LOADING)
        if item.stage=='ACTIVATE':
            self.console.set(State.MENU)
            self.console.value=replace(self.console.value,runtime_active=True)
        if self.interrupt=='cancel' and self.count==20:self.console.menu()
        return result


def service(tmp_path, *, interrupt=None):
    (tmp_path/'Legal game.nes').write_bytes(make_ines())
    c=Console();lib=Library(c);loader=Loader(c,interrupt)
    svc=LibraryService(c,lib,loader,tmp_path);svc.initialize()
    c.set(State.LOADING)
    request=LibraryStatus(c.status(),(1<<19)|(2<<17),2)
    return svc,c,lib,loader,request


def test_complete_library_service_reuses_loader_and_repeated_launch(tmp_path):
    svc,c,lib,loader,req=service(tmp_path)
    result=svc.launch(req)
    assert result and result.status.runtime_active and c.status().state==State.GAME
    assert lib.stages==[Stage.VALIDATING,Stage.PREPARING,Stage.LOADING,Stage.READY]
    assert c.commands==[Command.LAUNCH] and bytes(loader.prg[:16384])==make_ines()[16:16400]
    c.menu();c.set(State.LOADING)
    assert svc.launch(replace(req,console=c.status()))
    assert c.commands==[Command.LAUNCH,Command.LAUNCH]


@pytest.mark.parametrize('change,stage',[('missing',Stage.MISSING),('changed',Stage.INVALID),('failure',Stage.FAILED),('cancel',Stage.INTERRUPTED)])
def test_launch_failure_and_cancellation_do_not_activate(tmp_path,change,stage):
    svc,c,lib,loader,req=service(tmp_path,interrupt=change)
    if change=='missing':(tmp_path/'Legal game.nes').unlink()
    if change=='changed':(tmp_path/'Legal game.nes').write_bytes(make_ines(flags6=32))
    assert svc.launch(req) is None
    assert lib.stages[-1]==(Stage.LOADING if change=='cancel' else stage)
    assert Command.LAUNCH not in c.commands
    assert not loader.read_status().runtime_active
    if change in ('missing','changed'):assert loader.count==0
    if change=='cancel':assert loader.count<=257 and c.commands==[] and c.status().state==State.MENU


def test_empty_missing_and_reset_reinitialize_service(tmp_path):
    c=Console();lib=Library(c);svc=LibraryService(c,lib,Loader(c),tmp_path/'missing')
    svc.step();assert lib.published==[()] and lib.stages[-1]==Stage.MISSING
    (tmp_path/'missing').mkdir();lib.enabled=False;svc.step()
    assert lib.published==[(),()] and svc.last_error is None


class Mmio:
    def __init__(self,result=0):
        self.words={0:MAGIC,4:VERSION,8:LIMITS,12:1,24:0,28:0x10001,32:0,36:5,20:result};self.writes=[]
    def read32(self,n):return self.words.get(n,0)
    def write32(self,n,v):
        self.writes.append((n,v))
        if n==16:self.words[24]=(self.words[24]+1)&0xffffffff


def test_transport_wire_ownership_and_counter_wrap():
    mmio=Mmio();transport=LibraryTransport(mmio);status=transport.status()
    mmio.words[24]=0xffffffff
    transport.exchange(Operation.WORD,status,index=27,data=0x12345678)
    assert mmio.writes[-3:]==[(40,0x12345678),(44,5),(16,0x11b02)]
    assert mmio.words[24]==0


@pytest.mark.parametrize('offset',[0,4,8])
def test_transport_rejects_incompatible_identity(offset):
    mmio=Mmio();mmio.words[offset]^=1
    with pytest.raises(ConsoleError):LibraryTransport(mmio)


@pytest.mark.parametrize('result',[1,2,3])
def test_transport_never_retries_rejected_mutation(result):
    mmio=Mmio(result);transport=LibraryTransport(mmio)
    with pytest.raises(ConsoleError):transport.exchange(Operation.CLAIM,LibraryStatus(Status.decode(0x10002),0,5))
    assert len([n for n,v in mmio.writes if n==16])==1


def test_service_does_not_take_menu_from_developer_or_game(tmp_path):
    c=Console();lib=Library(c);svc=LibraryService(c,lib,Loader(c),tmp_path)
    for state in (State.DEVELOPER,State.GAME,State.INITIALIZING):
        c.set(state);before=c.status();svc.step()
        assert c.status()==before and not lib.published


def test_stale_claim_is_discarded_without_replaying_mutation(tmp_path):
    svc,c,lib,loader,req=service(tmp_path)
    attempts=[]
    lib.status=lambda:req
    def reject(op,status):attempts.append(op);raise ConsoleError('stale claim')
    lib.exchange=reject
    svc.step()
    assert attempts==[Operation.CLAIM] and loader.count==0 and svc.last_error=='stale claim'


def test_transport_timeout_and_reset_stop_without_resubmit():
    mmio=Mmio();mmio.words[12]=0
    ticks=iter([0,2])
    transport=LibraryTransport(mmio,timeout_s=1,clock=lambda:next(ticks),sleep=lambda _:None)
    with pytest.raises(ConsoleError,match='timeout'):transport.status()
    assert mmio.writes==[]
    mmio=Mmio();mmio.words[24]=10
    original=mmio.write32
    def reset(n,v):
        original(n,v)
        if n==16:mmio.words[24]=0
    mmio.write32=reset
    with pytest.raises(ConsoleError,match='reset'):LibraryTransport(mmio).status()
    assert len([n for n,v in mmio.writes if n==16])==1


def test_contract_and_existing_apertures_are_disjoint():
    import xml.etree.ElementTree as ET
    config=json.loads(Path('config/library_mmio.json').read_text())
    assert int(config['magic'],0)==MAGIC and int(config['limits'],0)==LIMITS
    apertures=[]
    for name in ('runtime_loader','diagnostic','console','library'):
        c=json.loads(Path(f'config/{name}_mmio.json').read_text())
        start=int(c['slave_offset'],0);end=start+c['span_bytes']
        assert all(end<=a or start>=b for a,b in apertures)
        apertures.append((start,end))
    qsys=ET.parse('quartus/nes_hps_loader_system.qsys').getroot()
    connection=qsys.find("./connection[@end='library_mmio_bridge.s0']")
    assert int(connection.find("./parameter[@name='baseAddress']").attrib['value'],0)==0x3000


def test_page_preflight_rejects_bad_titles_before_mmio(tmp_path):
    (tmp_path/'game.nes').write_bytes(make_ines())
    entries=GameLibrary(tmp_path).scan();mmio=Mmio();transport=LibraryTransport(mmio)
    status=LibraryStatus(Status.decode(0x10001),0,5)
    with pytest.raises(ValueError):transport.publish(entries,status,titles={'game.nes':False})
    assert mmio.writes==[]
    with pytest.raises(ValueError):transport.publish(entries*257,status)
    assert mmio.writes==[]


def test_failed_rescan_clears_old_truncation(tmp_path):
    root=tmp_path/'games';root.mkdir()
    for name in ['a.nes','b.nes']:(root/name).write_bytes(make_ines())
    library=GameLibrary(root);library.scan(limit=1);assert library.truncated
    root.rename(tmp_path/'removed')
    with pytest.raises(GameLibraryError):library.scan(limit=1)
    assert not library.truncated


def test_stage_does_not_refresh_superseded_launch_authorization():
    mmio = Mmio()
    transport = LibraryTransport(mmio)
    with pytest.raises(ConsoleError, match='superseded'):
        transport.stage(Stage.READY, epoch=2)
    assert all(offset != 16 or value & 255 == Operation.STATUS
               for offset, value in mmio.writes)


def test_cancelled_launch_cannot_report_into_new_request(tmp_path):
    svc, console, library, loader, request = service(tmp_path, interrupt='cancel')
    original = loader.send
    def send(item, *, timeout_s):
        result = original(item, timeout_s=timeout_s)
        if loader.count == 20:
            console.set(State.LOADING)
        return result
    loader.send = send
    assert svc.launch(request) is None
    assert console.status().state == State.LOADING
    assert library.stages == [Stage.VALIDATING, Stage.PREPARING, Stage.LOADING]
    assert console.commands == [] and not loader.read_status().runtime_active


@pytest.mark.parametrize('reopen', [False, True])
def test_cancel_on_activation_cannot_relaunch_at_same_console_epoch(tmp_path, reopen):
    svc, console, library, loader, request = service(tmp_path)
    original = loader.send
    def send(item, *, timeout_s):
        result = original(item, timeout_s=timeout_s)
        if item.stage == 'ACTIVATE':
            # Real supervisor arbitration gives ACTIVATE and same-clock B
            # one epoch increment and the same RETURNING -> MENU path.
            library.opened = reopen
            library.revision += 2 if reopen else 1
        return result
    loader.send = send
    assert svc.launch(request) is None
    assert loader.read_status().runtime_active  # storage activated, NES stays in menu
    assert console.status().state == State.MENU and console.commands == []
    assert Stage.READY not in library.stages
    assert 'cancelled during activation' in svc.last_error


@pytest.mark.parametrize('complete_payload', [False, True])
def test_abandoned_transfer_recovery_never_activates_then_full_reload(tmp_path, complete_payload):
    svc, console, library, loader, request = service(tmp_path)
    plan = LoadPlan.from_image(svc.library.load_entry(svc.entries[0]))
    for index, item in enumerate(plan.iter_transfer_commands()):
        if item.command == LoaderOperation.COMMIT or (not complete_payload and index == 20):
            break
        loader.send(item, timeout_s=3)
    console.menu(); console.set(State.LOADING)
    before = len(loader.commands)
    assert svc.launch(replace(request, console=console.status())) is None
    assert len(loader.commands) == before + 1
    assert loader.commands[-1].command == LoaderOperation.COMMIT
    assert not loader.read_status().runtime_active
    assert library.stages[-1] == Stage.RECOVERY and console.status().state == State.ERROR
    console.menu(); console.set(State.LOADING)
    result = svc.launch(replace(request, console=console.status()))
    assert result and result.status.runtime_active and console.status().state == State.GAME
