"""Software-visible constants from ``nes_runtime_loader_pkg.sv``.

This module describes the logical Phase 4F-A through 4F-D interface. It does
not assign registers, addresses, or a physical HPS/FPGA transport.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


MAPPER_0 = 0
SUPPORTED_MAPPERS = frozenset({MAPPER_0})
PRG_NROM128_BYTES = 0x4000
PRG_NROM256_BYTES = 0x8000
CHR_ROM_BYTES = 0x2000
PRG_LAST_ADDRESS = 0x7FFF
CHR_LAST_ADDRESS = 0x1FFF


class Command(IntEnum):
    BEGIN = 0
    WRITE = 1
    COMMIT = 2
    ACTIVATE = 3


class Target(IntEnum):
    NONE = 0
    PRG = 1
    CHR = 2
    RESERVED = 3


class LoaderState(IntEnum):
    IDLE = 0
    LOADING = 1
    READY = 2
    ERROR = 3


class LoaderErrorCode(IntEnum):
    NONE = 0
    WRONG_STATE = 1
    BEGIN_BUSY = 2
    BAD_COMMAND = 3
    BAD_TARGET = 4
    BAD_ADDRESS = 5
    EMPTY_LOAD = 6
    INVALID_MANIFEST = 7
    UNSUPPORTED_MAPPER = 8
    UNSUPPORTED_PRG = 9
    UNSUPPORTED_CHR = 10
    UNEXPECTED_ADDRESS = 11
    PRG_INCOMPLETE = 12
    CHR_INCOMPLETE = 13
    ACTIVATE_INVALID = 14


class Mirroring(IntEnum):
    VERTICAL = 0
    HORIZONTAL = 1

    @property
    def label(self) -> str:
        return "Vertical" if self is Mirroring.VERTICAL else "Horizontal"


@dataclass(frozen=True)
class Manifest:
    """Manifest sampled by the FPGA with an accepted ``BEGIN`` command."""

    mapper: int
    prg_bytes: int
    chr_bytes: int
    chr_is_ram: bool
    mirroring: Mirroring


def manifest_error(manifest: Manifest) -> LoaderErrorCode:
    """Apply the RTL manifest rules in their public error-priority order."""

    if manifest.mirroring not in (Mirroring.VERTICAL, Mirroring.HORIZONTAL):
        return LoaderErrorCode.INVALID_MANIFEST
    if manifest.mapper not in SUPPORTED_MAPPERS:
        return LoaderErrorCode.UNSUPPORTED_MAPPER
    if manifest.prg_bytes not in (PRG_NROM128_BYTES, PRG_NROM256_BYTES):
        return LoaderErrorCode.UNSUPPORTED_PRG
    chr_supported = (
        manifest.chr_is_ram and manifest.chr_bytes == 0
    ) or (
        not manifest.chr_is_ram and manifest.chr_bytes == CHR_ROM_BYTES
    )
    if not chr_supported:
        return LoaderErrorCode.UNSUPPORTED_CHR
    return LoaderErrorCode.NONE


@dataclass(frozen=True)
class LoaderCommand:
    """One complete logical ready/valid command payload."""

    command: Command
    target: Target = Target.NONE
    address: int = 0
    data: int = 0
    manifest: Manifest | None = None

    @classmethod
    def begin(cls, manifest: Manifest) -> LoaderCommand:
        return cls(Command.BEGIN, manifest=manifest)

    @classmethod
    def write(cls, target: Target, address: int, data: int) -> LoaderCommand:
        return cls(Command.WRITE, target=target, address=address, data=data)

    @classmethod
    def commit(cls) -> LoaderCommand:
        return cls(Command.COMMIT)

    @classmethod
    def activate(cls) -> LoaderCommand:
        return cls(Command.ACTIVATE)

    @property
    def stage(self) -> str:
        if self.command is Command.WRITE:
            return f"{self.target.name} write at address {self.address}"
        return self.command.name


@dataclass(frozen=True)
class RuntimeStatus:
    state: LoaderState
    error_code: LoaderErrorCode = LoaderErrorCode.NONE
    image_valid: bool = False
    runtime_active: bool = False
    activation_in_progress: bool = False
    nes_hold_reset: bool = False
    staged_manifest: Manifest | None = None
    active_manifest: Manifest | None = None
