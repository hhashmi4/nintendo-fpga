"""Separate, bounded library v1.0 protocol; existing MMIO maps are unchanged."""
from dataclasses import dataclass
from enum import IntEnum
import time
import unicodedata

from .protocol import Status
from .transport import ConsoleError

PHYSICAL_BASE, SPAN_BYTES = 0xFF203000, 64
MAGIC, VERSION, LIMITS = 0x4E45534C, 0x10000, 0x18040100
MAX_ENTRIES, PAGE_ENTRIES, TITLE_BYTES = 256, 4, 24
GLYPHS = frozenset(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-/:=[]")


class Operation(IntEnum):
    STATUS = 0
    BEGIN_PAGE = 1
    WORD = 2
    COMMIT = 3
    CLAIM = 4
    STAGE = 5
    DISABLE = 6


class Stage(IntEnum):
    IDLE = 0
    VALIDATING = 1
    PREPARING = 2
    LOADING = 3
    READY = 4
    UNSUPPORTED = 5
    INVALID = 6
    MISSING = 7
    FAILED = 8
    INTERRUPTED = 9
    RECOVERY = 10
    ADMITTED = 11


@dataclass(frozen=True)
class LibraryStatus:
    console: Status
    word: int
    revision: int

    @property
    def selected(self): return self.word & 255
    @property
    def total(self): return (self.word >> 8) & 511
    @property
    def event(self): return (self.word >> 17) & 3
    @property
    def enabled(self): return bool(self.word & (1 << 19))
    @property
    def opened(self): return bool(self.word & (1 << 20))
    @property
    def page_valid(self): return bool(self.word & (1 << 21))
    @property
    def stage(self): return Stage((self.word >> 22) & 15)


def display_title(value: str) -> bytes:
    # Preserve exact Unicode identities elsewhere. This is font presentation only.
    normalized = unicodedata.normalize("NFKD", value.upper())
    title = ''.join(c if c in GLYPHS else '.' for c in normalized
                    if not unicodedata.combining(c))
    if len(title) > TITLE_BYTES:
        title = title[:TITLE_BYTES - 3] + '...'
    return title.ljust(TITLE_BYTES).encode('ascii')


def page_words(entries, start: int, titles=None) -> tuple[int, ...]:
    if start % 4 or not 0 <= start < MAX_ENTRIES:
        raise ValueError("invalid page start")
    data = bytearray()
    for index in range(start, start + PAGE_ENTRIES):
        if index >= len(entries):
            data.extend(b' ' * TITLE_BYTES + bytes(4))
            continue
        entry = entries[index]
        title = (titles or {}).get(entry.game_id, entry.display_name)
        if not isinstance(title, str):
            raise ValueError("display title must be text")
        data.extend(display_title(title))
        meta = 0
        if entry.valid:
            header = entry.header
            if header.nes2:
                meta = (1 << 24) | (1 << 26)
            else:
                meta = (header.mapper | header.prg_banks << 8 |
                        header.chr_banks << 16 | (2 if entry.supported else 1) << 24)
        data.extend(meta.to_bytes(4, 'little'))
    return tuple(int.from_bytes(data[n:n+4], 'little') for n in range(0, 112, 4))


class LibraryTransport:
    def __init__(self, mmio, *, timeout_s=3.0, clock=time.monotonic, sleep=time.sleep):
        if timeout_s <= 0:
            raise ValueError("timeout must be positive")
        self.mmio, self.timeout_s, self.clock, self.sleep = mmio, timeout_s, clock, sleep
        if tuple(mmio.read32(n) for n in (0, 4, 8)) != (MAGIC, VERSION, LIMITS):
            raise ConsoleError("library MMIO identity/limits mismatch")

    def exchange(self, operation=Operation.STATUS, status=None, *, index=0, data=0):
        if not isinstance(operation, Operation) or not 0 <= index <= 255 or not 0 <= data <= 0xFFFFFFFF:
            raise ValueError("invalid library request")
        if operation and status is None:
            raise ValueError("mutation requires observed ownership")
        deadline = self.clock() + self.timeout_s
        def wait(predicate):
            while not predicate():
                if self.clock() >= deadline:
                    raise ConsoleError("library timeout; ownership unconfirmed")
                self.sleep(0.001)
        wait(lambda: self.mmio.read32(12) & 1)
        count = self.mmio.read32(24)
        self.mmio.write32(40, data)
        self.mmio.write32(44, status.revision if status else 0)
        self.mmio.write32(16, ((status.console.epoch if status else 0) << 16) |
                          index << 8 | operation)
        expected = (count + 1) & 0xFFFFFFFF
        def completed():
            observed = self.mmio.read32(24)
            if observed not in (count, expected):
                raise ConsoleError("library reset or concurrent issuer")
            return observed == expected
        wait(completed)
        if self.mmio.read32(20):
            raise ConsoleError(f"library request rejected: {self.mmio.read32(20)}")
        return LibraryStatus(Status.decode(self.mmio.read32(28)),
                             self.mmio.read32(32), self.mmio.read32(36))

    def status(self): return self.exchange()

    def publish(self, entries, status, *, truncated=False, titles=None):
        if len(entries) > MAX_ENTRIES:
            raise ValueError("library snapshot exceeds 256 entries")
        words = page_words(entries, status.selected & 252, titles)
        self.exchange(Operation.BEGIN_PAGE, status,
                      data=len(entries) | int(truncated) << 9)
        for index, data in enumerate(words):
            self.exchange(Operation.WORD, status, index=index, data=data)
        self.exchange(Operation.COMMIT, status)

    def stage(self, stage, *, epoch=None):
        status = self.status()
        if epoch is not None and status.console.epoch != epoch:
            raise ConsoleError("library stage superseded by an ownership change")
        self.exchange(Operation.STAGE, status, data=int(stage))
