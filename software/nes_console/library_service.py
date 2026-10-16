"""HPS policy above the existing library, console and single cartridge loader."""
import json
from pathlib import Path

from software.nes_loader.library import GameLibrary, GameLibraryError, GameNotLoadableError
from software.nes_loader.ines import INESError
from software.nes_loader.loader import LoadPlan, execute_load_plan, RuntimeLoadError
from software.nes_loader.transport import TransportError
from software.nes_loader.protocol import LoaderCommand, LoaderState
from .protocol import Command, State
from .transport import ConsoleError
from .library_protocol import MAX_ENTRIES, Operation, Stage


def read_titles(path):
    """Optional presentation-only JSON: exact filename -> display title."""
    if path is None:
        return {}
    with Path(path).open('rb') as stream:
        data = stream.read(65537)
    if len(data) > 65536:
        raise ValueError('title metadata exceeds 64 KiB')
    value = json.loads(data)
    if not isinstance(value, dict) or len(value) > MAX_ENTRIES:
        raise ValueError('title metadata must map at most 256 filenames to titles')
    for key, title in value.items():
        if not isinstance(key, str):
            raise ValueError("metadata identity must be a filename")
        GameLibrary._validate_game_id(key)
        if not isinstance(title, str) or not 1 <= len(title) <= 128:
            raise ValueError('each optional title must contain 1..128 characters')
    return value


class LaunchInterrupted(TransportError):
    pass


class GuardedLoader:
    """Observe ownership around the existing transport; never generate a load."""
    def __init__(self, loader, console, epoch):
        self.loader, self.console, self.epoch = loader, console, epoch
        self.writes = 0

    def check(self):
        status = self.console.status()
        if status.state != State.LOADING or status.epoch != self.epoch:
            raise LaunchInterrupted('load cancelled or ownership reset; full reload required')

    def send(self, item, *, timeout_s):
        # BEGIN/COMMIT/ACTIVATE and at most 256 payload writes between checks.
        if item.command.value != 1 or self.writes % 256 == 0:
            self.check()
        self.loader.send(item, timeout_s=timeout_s)
        self.writes += 1
        if item.stage == 'BEGIN':
            self.epoch = (self.epoch + 1) & 65535
            self.check()
        if item.stage == 'ACTIVATE':
            self.epoch = (self.epoch + 1) & 65535

    def wait_for_image_valid(self, *, timeout_s):
        self.check()
        return self.loader.wait_for_image_valid(timeout_s=timeout_s)

    def wait_for_active(self, *, timeout_s):
        result = self.loader.wait_for_active(timeout_s=timeout_s)
        self.console.wait_state(State.MENU, epoch=self.epoch)
        return result


class LibraryService:
    def __init__(self, console, library_transport, loader, root, *, titles=None):
        self.console, self.transport, self.loader = console, library_transport, loader
        self.library = GameLibrary(root)
        self.titles = titles or {}
        self.entries = ()
        self.last_error = None
        self.initialized = False

    def initialize(self):
        status = self.transport.status()
        if status.console.state != State.MENU:
            return
        self.transport.exchange(Operation.DISABLE, status)
        self.last_error = None
        try:
            self.entries = self.library.scan(limit=MAX_ENTRIES)
        except GameLibraryError as error:
            self.entries = ()
            self.last_error = str(error)
        self.transport.publish(self.entries, self.transport.status(),
                               truncated=self.library.truncated, titles=self.titles)
        if self.last_error:
            self.transport.stage(Stage.MISSING)
        self.initialized = True

    def step(self):
        try:
            status = self.transport.status()
            if not self.initialized or not status.enabled:
                if status.console.state == State.MENU:
                    self.initialize()
                return
            if status.event == 1 and status.console.state == State.MENU:
                self.transport.publish(self.entries, status,
                                       truncated=self.library.truncated, titles=self.titles)
            elif status.event == 2 and status.console.state == State.LOADING:
                self.launch(status)
        except ConsoleError as error:
            # Discard this request. A later poll observes a new user request or
            # disabled reset binding; no stale mutation is retried here.
            self.last_error = str(error)

    def launch(self, request):
        """Claim once, revalidate, transfer, activate, then await existing GAME ack."""
        self.transport.exchange(Operation.CLAIM, request)
        guard = GuardedLoader(self.loader, self.console, request.console.epoch)
        failure_stage = None
        try:
            guard.check()
            if request.selected >= len(self.entries):
                raise GameNotLoadableError('selection is outside the current snapshot')
            entry = self.entries[request.selected]
            if not entry.supported:
                failure_stage = Stage.UNSUPPORTED if entry.valid else Stage.INVALID
                raise GameNotLoadableError('selected cartridge is not supported')
            image = self.library.load_entry(entry)
            guard.check()
            self.transport.stage(Stage.PREPARING, epoch=guard.epoch)
            plan = LoadPlan.from_image(image)
            if self.loader.read_status().state == LoaderState.LOADING:
                # Loader v1.0 has no ABORT; BEGIN while LOADING is BEGIN_BUSY.
                # COMMIT safely closes an abandoned session (ERROR if partial,
                # READY if complete), without activation or any payload writes.
                # Require a new user selection after this explicit recovery.
                failure_stage = Stage.RECOVERY
                self.transport.stage(Stage.RECOVERY, epoch=guard.epoch)
                guard.send(LoaderCommand.commit(), timeout_s=3.0)
                raise RuntimeLoadError('abandoned transfer closed; press B and select again for a complete reload')
            self.transport.stage(Stage.LOADING, epoch=guard.epoch)
            launch_revision = self.transport.status().revision
            result = execute_load_plan(plan, guard)
            ready = self.transport.status()
            # B concurrent with ACTIVATE shares its single console epoch
            # increment. The library revision still records cancellation,
            # even if the user reopens the library before this poll.
            if (ready.revision != launch_revision or not ready.enabled or
                    not ready.opened or ready.console.epoch != guard.epoch):
                raise LaunchInterrupted('library selection cancelled during activation')
            self.transport.stage(Stage.READY, epoch=guard.epoch)
            # B/SELECT/system intentions advance the supervisor epoch even in
            # the ready-to-launch menu window. Never refresh that authorization.
            self.console.exchange(Command.LAUNCH, guard.epoch)
            self.console.wait_state(State.GAME, epoch=(guard.epoch + 1) & 65535)
            self.last_error = None
            return result
        except (GameLibraryError, INESError, OSError, RuntimeLoadError, ConsoleError, TransportError) as error:
            self.last_error = str(error)
            try:
                current = self.console.status()
            except ConsoleError:
                return None  # Unconfirmed ownership: stop writes, retain independent UI.
            interrupted = (isinstance(error, LaunchInterrupted) or
                           isinstance(error.__cause__, LaunchInterrupted) or
                           current.epoch != guard.epoch or current.state not in (State.LOADING, State.ERROR))
            if interrupted:
                stage = Stage.INTERRUPTED
            elif isinstance(error, (GameLibraryError, INESError, OSError)):
                missing = isinstance(error, FileNotFoundError) or isinstance(error.__cause__, FileNotFoundError)
                stage = failure_stage or (Stage.MISSING if missing else Stage.INVALID)
            else:
                stage = failure_stage or Stage.FAILED
            if current.epoch != guard.epoch:
                # FPGA owns cancellation feedback. A new intention must not
                # receive status from the superseded launch, even after polling.
                return None
            try:
                self.transport.stage(stage, epoch=guard.epoch)
                if not interrupted and current.state == State.LOADING:
                    self.console.exchange(Command.REPORT_ERROR, guard.epoch)
            except ConsoleError:
                pass  # Reporting cannot steal ownership or hide the cause.
            return None
