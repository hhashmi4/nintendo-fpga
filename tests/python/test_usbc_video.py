"""Independent arithmetic, adversarial policy sequences and evidence validation."""
from copy import deepcopy
from fractions import Fraction
import random

import pytest

from verification.usbc_video import (
    AltModePolicy, Capability, Mode, OutputSelection, bandwidth_requirement,
    compare_power, lane_capacity, load_architecture, mode_feasibility,
    validate_architecture,
)


def modes():
    return {x['id']: Mode(**{k: x[k] for k in Mode.__dataclass_fields__})
            for x in load_architecture()['modes']}


def configured():
    p = AltModePolicy(simulation_hardware=True)
    for event in ('attach', 'pd_ready', 'identity', 'svid', 'modes', 'enter', 'status', 'configure'):
        p.event(event, epoch=p.epoch)
    assert p.state == 'CONFIGURED'
    return p


def ready():
    p = configured()
    p.event('hpd_high', epoch=p.epoch)
    p.event('link_ready', epoch=p.epoch, lanes=2, rate_mbps=1620, mode_valid=True)
    assert p.ready
    return p


@pytest.mark.parametrize('name,clock,raw,active', [
    ('720p60', 74250000, 1782000000, 55296000),
    ('1080p60', 148500000, 3564000000, 124416000),
    ('1200p60rb', 154000000, 3696000000, Fraction(154000000*1920*1200,2080*1235)),
    ('2160p30', 297000000, 7128000000, 248832000),
    ('2160p60', 594000000, 14256000000, 497664000),
])
def test_standard_mode_arithmetic(name, clock, raw, active):
    m = modes()[name]
    assert m.pixel_clock_hz == clock
    assert m.raster_bits_s == raw
    assert m.active_pixels_s == active
    assert m.blanking_fraction == 1-Fraction(active,clock)


@pytest.mark.parametrize('lanes', [1, 2, 4])
@pytest.mark.parametrize('rate,payload', [(1620,1296000000), (2700,2160000000), (5400,4320000000), (8100,6480000000)])
def test_lane_encoding(lanes, rate, payload):
    assert lane_capacity(lanes, rate) == payload*lanes


@pytest.mark.parametrize('lanes,rate', [(0,1620),(3,2700),(8,5400),(2,6000),(True,1620),(2,2700.0)])
def test_invalid_links(lanes,rate):
    with pytest.raises(ValueError):
        lane_capacity(lanes,rate)


def test_random_independent_bandwidth_oracle():
    rng = random.Random(0x6F2026)
    for _ in range(1000):
        w,h = rng.randint(1,3840),rng.randint(1,2160)
        tw,th = w+rng.randint(1,600),h+rng.randint(1,100)
        hz,bpp = rng.choice((30,60,75)),rng.choice((18,24,30))
        m = Mode(w,h,tw,th,tw*th*hz,bpp)
        reserve = rng.randrange(100000)
        numerator = (tw*th*hz*bpp+1536000)*1000000
        expected = (numerator+1000000-reserve-1)//(1000000-reserve)
        assert bandwidth_requirement(m,reserve) == expected
        assert m.active_pixels_s == w*h*hz


def test_raster_screen_not_active_only_or_support_claim():
    m = modes()['720p60']
    assert m.active_pixels_s*24 == 1327104000
    assert bandwidth_requirement(m) > 1782000000
    assert bandwidth_requirement(m) > lane_capacity(1,1620)
    assert bandwidth_requirement(m) < lane_capacity(2,1620)


@pytest.mark.parametrize('args', [(0,240,341,262,5369318),(256,240,200,262,5369318),(256,240,341,200,5369318),(256,240,341,262,-1)])
def test_invalid_modes(args):
    with pytest.raises(ValueError):
        Mode(*args)


@pytest.mark.parametrize('mode_name,hardware,missing,lanes,expected', [
    ('bad',False,False,4,'INVALID_MODE'),
    ('720p60',False,False,4,'UNSUPPORTED_HARDWARE'),
    ('720p60',True,True,4,'MISSING_CAPABILITY'),
    ('1080p60',True,False,4,'UNSUPPORTED_MODE'),
    ('720p60',True,False,1,'INSUFFICIENT_BANDWIDTH'),
    ('720p60',True,False,2,'BANDWIDTH_SCREEN_PASS'),
])
def test_mode_feasibility(mode_name,hardware,missing,lanes,expected):
    c = Capability(frozenset({'720p60'}),74250000,4,5400)
    assert mode_feasibility(mode_name,modes(),c,None if missing else c,(lanes,1620),hardware) == expected


def test_component_clock_and_cable_limits():
    all_modes=frozenset(modes())
    source=Capability(all_modes,165000000,4,5400)
    sink=Capability(all_modes,600000000,4,8100)
    assert mode_feasibility('2160p60',modes(),source,sink,(4,8100),True)=='UNSUPPORTED_MODE'
    assert mode_feasibility('1080p60',modes(),source,sink,(2,1620),True)=='INSUFFICIENT_BANDWIDTH'
    assert mode_feasibility('720p60',modes(),source,sink,None,True)=='MISSING_CAPABILITY'


@pytest.mark.parametrize('increment,voltage,expected', [(None,9000,'UNKNOWN'),(0,9000,'SUFFICIENT'),(5256,9000,'SUFFICIENT'),(5257,9000,'INSUFFICIENT'),(0,5000,'INSUFFICIENT'),(7500,9000,'INSUFFICIENT')])
def test_power_budget(increment,voltage,expected):
    result=compare_power(increment,voltage)
    assert result['status']==expected
    if increment is None:
        assert result['required_mw'] is None and result['headroom_mw'] is None
    else:
        capacity=(Fraction(voltage*95,100)-500)*3
        assert result['headroom_mw']==capacity-18894-increment


def test_power_invalid_values():
    for value in (-1,True,1.1):
        with pytest.raises(ValueError):
            compare_power(value)


def test_unsupported_default_never_connects():
    p=AltModePolicy()
    for event in ('attach','pd_ready','identity','svid','modes','enter','status','configure','hpd_high','link_ready'):
        p.event(event,epoch=p.epoch,lanes=4,rate_mbps=5400,mode_valid=True)
        d=p.diagnostics()
        assert not p.ready and not d['USBC_VIDEO_CONNECTED']
        assert not d['USBC_VIDEO_AVAILABLE'] and not d['USBC_ALT_MODE_ACTIVE']
        assert d['USBC_DP_LINK_RATE']==d['USBC_DP_LANE_COUNT']==0
        assert d['provenance']=='MODEL_ONLY'


@pytest.mark.parametrize('event', ['timeout','reject','link_loss','power_loss','stale_status'])
def test_fault_requires_discovery_recovery(event):
    p=ready()
    p.event(event,epoch=p.epoch)
    assert not p.ready and p.state=='FAULT'
    assert p.diagnostics()['USBC_VIDEO_CONNECTED']  # fault is not a cable-detach observation
    p.event('link_ready',epoch=p.epoch,lanes=2,rate_mbps=1620,mode_valid=True)
    assert not p.ready
    p.event('clear',epoch=p.epoch)
    assert p.state=='DETACHED' and p.fault=='NONE'
    for event in ('attach','pd_ready','identity','svid','modes','enter','status','configure','hpd_high'):
        p.event(event,epoch=p.epoch)
    p.event('link_ready',epoch=p.epoch,lanes=2,rate_mbps=1620,mode_valid=True)
    assert p.ready


@pytest.mark.parametrize('event', ['detach','reset','hpd_low','hpd_irq','mode_change'])
def test_invalidation_and_stale_completions(event):
    p=ready()
    old_epoch=p.epoch
    p.event(event,epoch=p.epoch)
    assert not p.ready and p.lanes==p.rate_mbps==0
    if event in ('detach','reset'):
        p.event('link_ready',epoch=old_epoch,lanes=2,rate_mbps=1620,mode_valid=True)
        assert not p.ready and p.state=='DETACHED'
    else:
        p.event('link_ready',epoch=old_epoch,lanes=2,rate_mbps=1620,mode_valid=True)
        assert not p.ready
        p.event('hpd_high',epoch=p.epoch)
        p.event('link_ready',epoch=p.epoch,lanes=2,rate_mbps=1620,mode_valid=True)
        assert p.ready


@pytest.mark.parametrize('event', ['pd_ready','enter','configure','link_ready','hpd_high','nonsense'])
def test_out_of_order_reports_fail_closed(event):
    p=AltModePolicy(simulation_hardware=True)
    p.event(event,epoch=p.epoch,lanes=2,rate_mbps=1620,mode_valid=True)
    assert p.state=='FAULT' and not p.ready


@pytest.mark.parametrize('hpd,mode_valid,lanes', [(False,True,2),(True,False,2),(True,True,3)])
def test_link_ready_requires_all_prerequisites(hpd,mode_valid,lanes):
    p=configured()
    if hpd:
        p.event('hpd_high',epoch=p.epoch)
    p.event('link_ready',epoch=p.epoch,lanes=lanes,rate_mbps=1620,mode_valid=mode_valid)
    assert not p.ready


def test_output_boundary_fallback_audio():
    s=OutputSelection()
    assert s.update('AUTO',hdmi_ready=True,dp_ready=True)==('NONE','MUTE')
    assert s.update('AUTO',hdmi_ready=True,dp_ready=True,hdmi_audio=True,frame_boundary=True)==('HDMI','HDMI')
    assert s.update('USBC_DP',hdmi_ready=True,dp_ready=True,hdmi_audio=True)==('HDMI','HDMI')
    assert s.update('USBC_DP',hdmi_ready=True,dp_ready=True,dp_audio=False,frame_boundary=True)==('USBC_DP','MUTE')
    assert s.update('USBC_DP',hdmi_ready=True,dp_ready=False)==('NONE','MUTE')
    assert s.update('USBC_DP',hdmi_ready=True,dp_ready=False,hdmi_audio=True,frame_boundary=True)==('HDMI','HDMI')
    assert s.update('VGA',vga_ready=True,frame_boundary=True)==('VGA','MUTE')
    assert s.update('NONE',hdmi_ready=True,frame_boundary=True)==('NONE','MUTE')
    with pytest.raises(ValueError):
        s.update('4K')


def test_random_selection_truth_table():
    rng=random.Random(0xF006)
    for _ in range(1000):
        values=[bool(rng.getrandbits(1)) for _ in range(6)]
        h,d,v,ha,da,mute=values
        s=OutputSelection()
        selected,audio=s.update('AUTO',hdmi_ready=h,dp_ready=d,vga_ready=v,hdmi_audio=ha,dp_audio=da,muted=mute,frame_boundary=True)
        expected='HDMI' if h else 'USBC_DP' if d else 'VGA' if v else 'NONE'
        assert selected==expected
        permitted=(selected=='HDMI' and ha) or (selected=='USBC_DP' and da)
        assert audio==(selected if permitted and not mute else 'MUTE')


def test_diagnostic_consistency_random_events():
    rng=random.Random(0xD1A6)
    p=ready()
    for _ in range(3000):
        event=rng.choice(['attach','pd_ready','identity','svid','modes','enter','status','configure','link_ready','hpd_high','hpd_low','hpd_irq','detach','reset','clear','timeout'])
        p.event(event,epoch=p.epoch,lanes=2,rate_mbps=1620,mode_valid=True)
        d=p.diagnostics()
        if d['USBC_DP_LINK_READY']:
            assert d['USBC_ALT_MODE_ACTIVE'] and d['USBC_VIDEO_CONNECTED'] and p.hpd
            assert d['USBC_DP_LANE_COUNT']==2
        else:
            assert d['USBC_DP_LANE_COUNT']==d['USBC_DP_LINK_RATE']==0
        assert d['USBC_VIDEO_QUALIFICATION']=='SIMULATED'


def test_schema_and_preserved_power_mmio():
    from pathlib import Path
    import json
    d=load_architecture()
    validate_architecture(d)
    root=Path(__file__).resolve().parents[2]
    power=json.loads((root/'config/phase6e_power_architecture.json').read_text())
    mmio=json.loads((root/'config/diagnostic_mmio.json').read_text())
    assert d['power']['baseline_input_design_mw']==power['budget']['input_design_mw']
    assert f"{mmio['version_major']}.{mmio['version_minor']}"==d['diagnostics']['existing_mmio_version']
    assert not any(k.startswith('USBC_VIDEO') for k in mmio['registers'])


@pytest.mark.parametrize('path,value', [
    (('schema_version',),2), (('physical_implementation',),True), (('primary_output',),'USBC_DP'),
    (('units','power'),'W'), (('sources',0,'url'),'http://example.com'),
    (('sources',0,'revision'),''), (('sources',0,'locator'),''), (('sources',0,'reviewed'),'2020-01-01'),
    (('sources',0,'access'),'VERIFIED'), (('components',0,'sources'),['missing']),
    (('components',0,'qualification'),'APPROVED'), (('components',0,'cost_usd'),5),
    (('components',0,'audio'),''), (('architectures',1,'required_components'),['ghost']),
    (('architectures',1,'incremental_input_peak_mw'),1000),
    (('architectures',1,'incremental_bom_usd'),10), (('architectures',1,'risk'),'NONE'),
    (('modes',0,'raster_bits_s'),100), (('modes',0,'active_pixels_s'),1),
    (('modes',0,'blanking_fraction'),0), (('modes',1,'implemented_scanout'),True),
    (('fpga','hssi_lanes'),4), (('fpga','native_dp'),True),
    (('bandwidth','encoding'),'128b132b'), (('bandwidth','audio_payload_bits_s'),3072000),
    (('bandwidth','screening_reserve_ppm'),0), (('power','remaining_mw'),8106),
    (('power','complete_dp_budget_mw'),20000), (('power','baseline_input_design_mw'),18000),
    (('connector_policy','selected_option'),2), (('diagnostics','storage'),'MMIO'),
    (('decision_criteria',),[]), (('unresolved',),[]),
])
def test_schema_rejects_corrupt_metadata(path,value):
    d=deepcopy(load_architecture())
    obj=d
    for k in path[:-1]:
        obj=obj[k]
    obj[path[-1]]=value
    with pytest.raises(ValueError):
        validate_architecture(d)


def test_schema_missing_unknown_and_duplicate():
    for alteration in ('missing','extra','duplicate'):
        d=deepcopy(load_architecture())
        if alteration=='missing':
            del d['power']['remaining_mw']
        elif alteration=='extra':
            d['production_dp_pins']=['FAKE']
        else:
            d['sources'].append(deepcopy(d['sources'][0]))
        with pytest.raises(ValueError):
            validate_architecture(d)
