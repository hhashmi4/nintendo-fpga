"""Production-side iNES parsing and runtime-loader orchestration."""

from .ines import (
    CHR_BANK_SIZE,
    INES_HEADER_SIZE,
    PRG_BANK_SIZE,
    INESFormatError,
    ParsedINES,
    RuntimeImage,
    UnsupportedINESImage,
    inspect_ines,
    load_runtime_image,
    parse_ines,
    validate_runtime_image,
)
from .loader import (
    LoadPlan,
    LoadResult,
    RuntimeLoadError,
    RuntimeLoaderTimeouts,
    execute_load_plan,
)
from .mmio import DevMemMmio, FakeMmio, RawMmio
from .protocol import Manifest, Mirroring
from .transport import (
    MmioRuntimeLoaderTransport,
    MockRuntimeLoaderTransport,
    RuntimeLoaderTransport,
    TransportError,
    TransportIdentityError,
    TransportTimeout,
)

__all__ = [
    "CHR_BANK_SIZE",
    "INES_HEADER_SIZE",
    "PRG_BANK_SIZE",
    "INESFormatError",
    "DevMemMmio",
    "FakeMmio",
    "LoadPlan",
    "LoadResult",
    "Manifest",
    "Mirroring",
    "MmioRuntimeLoaderTransport",
    "MockRuntimeLoaderTransport",
    "ParsedINES",
    "RuntimeImage",
    "RuntimeLoadError",
    "RuntimeLoaderTimeouts",
    "RuntimeLoaderTransport",
    "RawMmio",
    "TransportError",
    "TransportIdentityError",
    "TransportTimeout",
    "UnsupportedINESImage",
    "execute_load_plan",
    "inspect_ines",
    "load_runtime_image",
    "parse_ines",
    "validate_runtime_image",
]
