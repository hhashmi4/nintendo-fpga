"""Streaming runtime load-plan construction and execution."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterator

from .ines import RuntimeImage
from .protocol import LoaderCommand, Manifest, RuntimeStatus, Target
from .transport import RuntimeLoaderTransport, TransportError


class RuntimeLoadError(RuntimeError):
    """A load stopped at a named protocol stage."""


@dataclass(frozen=True)
class RuntimeLoaderTimeouts:
    command_s: float = 1.0
    image_validation_s: float = 1.0
    activation_s: float = 1.0

    def __post_init__(self) -> None:
        if min(self.command_s, self.image_validation_s, self.activation_s) < 0:
            raise ValueError("loader timeouts must be non-negative")


@dataclass(frozen=True)
class LoadPlan:
    """Compact image-backed plan; byte-write commands are generated lazily."""

    manifest: Manifest
    prg_bytes: bytes
    chr_bytes: bytes

    @classmethod
    def from_image(cls, image: RuntimeImage) -> LoadPlan:
        return cls(image.manifest(), image.prg_bytes, image.chr_bytes)

    @property
    def transfer_command_count(self) -> int:
        return 2 + len(self.prg_bytes) + len(self.chr_bytes)

    def iter_transfer_commands(self) -> Iterator[LoaderCommand]:
        yield LoaderCommand.begin(self.manifest)
        for address, value in enumerate(self.prg_bytes):
            yield LoaderCommand.write(Target.PRG, address, value)
        for address, value in enumerate(self.chr_bytes):
            yield LoaderCommand.write(Target.CHR, address, value)
        yield LoaderCommand.commit()


@dataclass(frozen=True)
class LoadResult:
    manifest: Manifest
    prg_bytes_written: int
    chr_bytes_written: int
    commands_accepted: int
    status: RuntimeStatus


def execute_load_plan(
    plan: LoadPlan,
    transport: RuntimeLoaderTransport,
    *,
    timeouts: RuntimeLoaderTimeouts = RuntimeLoaderTimeouts(),
) -> LoadResult:
    """Execute BEGIN, sequential payloads, COMMIT, validate, and ACTIVATE."""

    accepted = 0
    stage = "BEGIN"
    try:
        for item in plan.iter_transfer_commands():
            stage = item.stage
            transport.send(item, timeout_s=timeouts.command_s)
            accepted += 1
        stage = "image validation"
        transport.wait_for_image_valid(timeout_s=timeouts.image_validation_s)
        stage = "ACTIVATE"
        transport.send(LoaderCommand.activate(), timeout_s=timeouts.command_s)
        accepted += 1
        stage = "activation"
        status = transport.wait_for_active(timeout_s=timeouts.activation_s)
    except TransportError as error:
        raise RuntimeLoadError(f"{stage} failed: {error}") from error

    return LoadResult(
        manifest=plan.manifest,
        prg_bytes_written=len(plan.prg_bytes),
        chr_bytes_written=len(plan.chr_bytes),
        commands_accepted=accepted,
        status=status,
    )
