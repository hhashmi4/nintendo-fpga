"""Independent Phase 4F-C runtime-image validation oracle."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


MAPPER_0 = 0
PRG_NROM128_BYTES = 16 * 1024
PRG_NROM256_BYTES = 32 * 1024
CHR_ROM_BYTES = 8 * 1024
PRG_STORAGE_BYTES = PRG_NROM256_BYTES
CHR_STORAGE_BYTES = CHR_ROM_BYTES


class Target(IntEnum):
    NONE = 0
    PRG = 1
    CHR = 2
    RESERVED = 3


class Mirroring(IntEnum):
    VERTICAL = 0
    HORIZONTAL = 1
    RESERVED_2 = 2
    RESERVED_3 = 3


class State(IntEnum):
    IDLE = 0
    LOADING = 1
    READY = 2
    ERROR = 3


class ImageError(IntEnum):
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


@dataclass(frozen=True)
class ImageManifest:
    mapper: int = MAPPER_0
    prg_bytes: int = PRG_NROM128_BYTES
    chr_bytes: int = CHR_ROM_BYTES
    chr_is_ram: bool = False
    mirroring: int = Mirroring.HORIZONTAL


def validate_manifest(
    manifest: ImageManifest,
    *,
    manifest_valid: bool = True,
    begin_target: int = Target.NONE,
    begin_address: int = 0,
    begin_data: int = 0,
) -> ImageError:
    """Return the first manifest error using the RTL's public precedence."""

    canonical_begin = (
        begin_target == Target.NONE
        and begin_address == 0
        and begin_data == 0
    )
    if (
        not manifest_valid
        or not canonical_begin
        or manifest.mirroring
        not in (Mirroring.VERTICAL, Mirroring.HORIZONTAL)
    ):
        return ImageError.INVALID_MANIFEST
    if manifest.mapper != MAPPER_0:
        return ImageError.UNSUPPORTED_MAPPER
    if manifest.prg_bytes not in (
        PRG_NROM128_BYTES,
        PRG_NROM256_BYTES,
    ):
        return ImageError.UNSUPPORTED_PRG
    chr_supported = (
        manifest.chr_is_ram and manifest.chr_bytes == 0
    ) or (
        not manifest.chr_is_ram and manifest.chr_bytes == CHR_ROM_BYTES
    )
    if not chr_supported:
        return ImageError.UNSUPPORTED_CHR
    return ImageError.NONE


@dataclass
class RuntimeImageModel:
    """Transaction-level model of one staged runtime-image session.

    Coverage is represented independently as the next required byte for each
    target. Writes may interleave across PRG and CHR, but each target must
    begin at zero and advance by exactly one. A duplicate, gap, or reversed
    address therefore cannot advance completeness.
    """

    state: State = State.IDLE
    error_code: ImageError = ImageError.NONE
    manifest: ImageManifest | None = None
    next_prg_address: int = 0
    next_chr_address: int = 0

    @property
    def image_valid(self) -> bool:
        return self.state is State.READY

    @property
    def prg_complete(self) -> bool:
        return (
            self.manifest is not None
            and self.next_prg_address == self.manifest.prg_bytes
        )

    @property
    def chr_complete(self) -> bool:
        return (
            self.manifest is not None
            and self.next_chr_address == self.manifest.chr_bytes
        )

    def reset(self) -> None:
        self.state = State.IDLE
        self.error_code = ImageError.NONE
        self.manifest = None
        self.next_prg_address = 0
        self.next_chr_address = 0

    def begin(
        self,
        manifest: ImageManifest,
        *,
        manifest_valid: bool = True,
        begin_target: int = Target.NONE,
        begin_address: int = 0,
        begin_data: int = 0,
    ) -> bool:
        if self.state is State.LOADING:
            self.state = State.ERROR
            self.error_code = ImageError.BEGIN_BUSY
            return False

        # Every accepted BEGIN supersedes prior staged validity and coverage,
        # even when its replacement manifest is rejected.
        self.manifest = None
        self.next_prg_address = 0
        self.next_chr_address = 0
        error = validate_manifest(
            manifest,
            manifest_valid=manifest_valid,
            begin_target=begin_target,
            begin_address=begin_address,
            begin_data=begin_data,
        )
        if error is not ImageError.NONE:
            self.state = State.ERROR
            self.error_code = error
            return False

        self.manifest = manifest
        self.state = State.LOADING
        self.error_code = ImageError.NONE
        return True

    def write(self, target: int, address: int) -> bool:
        if self.state is State.ERROR:
            return False
        if self.state is not State.LOADING:
            self.state = State.ERROR
            self.error_code = ImageError.WRONG_STATE
            return False
        if target not in (Target.PRG, Target.CHR):
            self.state = State.ERROR
            self.error_code = ImageError.BAD_TARGET
            return False

        physical_limit = (
            PRG_STORAGE_BYTES if target == Target.PRG else CHR_STORAGE_BYTES
        )
        if not 0 <= address < physical_limit:
            self.state = State.ERROR
            self.error_code = ImageError.BAD_ADDRESS
            return False
        if self.manifest is None:
            self.state = State.ERROR
            self.error_code = ImageError.INVALID_MANIFEST
            return False
        if target == Target.CHR and self.manifest.chr_is_ram:
            self.state = State.ERROR
            self.error_code = ImageError.BAD_TARGET
            return False

        declared_limit = (
            self.manifest.prg_bytes
            if target == Target.PRG
            else self.manifest.chr_bytes
        )
        if address >= declared_limit:
            self.state = State.ERROR
            self.error_code = ImageError.BAD_ADDRESS
            return False

        expected = (
            self.next_prg_address
            if target == Target.PRG
            else self.next_chr_address
        )
        if address != expected:
            self.state = State.ERROR
            self.error_code = ImageError.UNEXPECTED_ADDRESS
            return False

        if target == Target.PRG:
            self.next_prg_address += 1
        else:
            self.next_chr_address += 1
        return True

    def commit(self) -> bool:
        if self.state is State.ERROR:
            return False
        if self.state is not State.LOADING:
            self.state = State.ERROR
            self.error_code = ImageError.WRONG_STATE
            return False
        if self.manifest is None:
            self.state = State.ERROR
            self.error_code = ImageError.INVALID_MANIFEST
            return False
        if not self.prg_complete:
            self.state = State.ERROR
            self.error_code = ImageError.PRG_INCOMPLETE
            return False
        if not self.chr_complete:
            self.state = State.ERROR
            self.error_code = ImageError.CHR_INCOMPLETE
            return False

        self.state = State.READY
        self.error_code = ImageError.NONE
        return True
