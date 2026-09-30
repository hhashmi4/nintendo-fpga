"""Raw 32-bit MMIO access, separated from loader transport semantics."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
import mmap
import os
import struct


class RawMmio(ABC):
    """Minimal little-endian, aligned 32-bit MMIO region."""

    def __init__(self, span_bytes: int) -> None:
        if span_bytes <= 0 or span_bytes % 4:
            raise ValueError("MMIO span must be a positive multiple of four")
        self.span_bytes = span_bytes

    def _check_offset(self, offset: int) -> None:
        if offset < 0 or offset % 4 or offset + 4 > self.span_bytes:
            raise ValueError(f"invalid 32-bit MMIO offset 0x{offset:x}")

    @abstractmethod
    def read32(self, offset: int) -> int:
        """Read one aligned little-endian word."""

    @abstractmethod
    def write32(self, offset: int, value: int) -> None:
        """Write one aligned little-endian word."""

    @abstractmethod
    def close(self) -> None:
        """Release backing resources."""

    def __enter__(self) -> RawMmio:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class DevMemMmio(RawMmio):
    """Page-correct mapping of only the selected bridge region."""

    def __init__(
        self,
        physical_base: int,
        span_bytes: int,
        *,
        device: str = "/dev/mem",
    ) -> None:
        super().__init__(span_bytes)
        if physical_base < 0:
            raise ValueError("physical MMIO base must be non-negative")
        page_size = mmap.PAGESIZE
        page_base = physical_base & ~(page_size - 1)
        self._page_offset = physical_base - page_base
        mapping_bytes = self._page_offset + span_bytes
        self._fd = os.open(device, os.O_RDWR | os.O_SYNC)
        try:
            self._mapping = mmap.mmap(
                self._fd,
                mapping_bytes,
                flags=mmap.MAP_SHARED,
                prot=mmap.PROT_READ | mmap.PROT_WRITE,
                offset=page_base,
            )
        except BaseException:
            os.close(self._fd)
            self._fd = -1
            raise

    def read32(self, offset: int) -> int:
        self._check_offset(offset)
        if self._fd < 0:
            raise ValueError("MMIO mapping is closed")
        return struct.unpack_from("<I", self._mapping, self._page_offset + offset)[0]

    def write32(self, offset: int, value: int) -> None:
        self._check_offset(offset)
        if self._fd < 0:
            raise ValueError("MMIO mapping is closed")
        if value < 0 or value > 0xFFFFFFFF:
            raise ValueError("MMIO word must fit in 32 bits")
        struct.pack_into("<I", self._mapping, self._page_offset + offset, value)

    def close(self) -> None:
        if self._fd >= 0:
            self._mapping.close()
            os.close(self._fd)
            self._fd = -1


ReadHook = Callable[[int, int], int]
WriteHook = Callable[[int, int], None]


class FakeMmio(RawMmio):
    """In-memory region with optional device-model hooks for unit tests."""

    def __init__(
        self,
        span_bytes: int,
        *,
        read_hook: ReadHook | None = None,
        write_hook: WriteHook | None = None,
    ) -> None:
        super().__init__(span_bytes)
        self.words = [0] * (span_bytes // 4)
        self.read_hook = read_hook
        self.write_hook = write_hook
        self.closed = False

    def read32(self, offset: int) -> int:
        self._check_offset(offset)
        if self.closed:
            raise ValueError("MMIO mapping is closed")
        value = self.words[offset // 4]
        if self.read_hook is not None:
            value = self.read_hook(offset, value)
        return value & 0xFFFFFFFF

    def write32(self, offset: int, value: int) -> None:
        self._check_offset(offset)
        if self.closed:
            raise ValueError("MMIO mapping is closed")
        if value < 0 or value > 0xFFFFFFFF:
            raise ValueError("MMIO word must fit in 32 bits")
        self.words[offset // 4] = value
        if self.write_hook is not None:
            self.write_hook(offset, value)

    def close(self) -> None:
        self.closed = True
