"""Independent Phase 4F-D runtime-cartridge activation model."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

from verification.runtime_image import ImageManifest


class ActivationError(IntEnum):
    NONE = 0
    LOAD_INVALID = 1
    ACTIVATE_INVALID = 2


@dataclass
class RuntimeActivationModel:
    """Policy model for staging, atomic selection, and NES reset safety.

    Payload completeness remains the responsibility of the Phase 4F-C image
    model. This model starts at the point where a load session is accepted and
    treats ``complete_load`` as the validator's successful COMMIT result.
    """

    reset_cycles: int = 4
    physical_reset: bool = False
    load_in_progress: bool = False
    staged_valid: bool = False
    staged_manifest: ImageManifest | None = None
    activation_required: bool = False
    runtime_active: bool = False
    active_manifest: ImageManifest | None = None
    reset_cycles_remaining: int = 0
    error: ActivationError = ActivationError.NONE
    dma_active: bool = False
    nmi_pending: bool = False

    def __post_init__(self) -> None:
        if self.reset_cycles < 1:
            raise ValueError("activation reset must last at least one cycle")

    @property
    def hold_reset(self) -> bool:
        return (
            self.physical_reset
            or self.activation_required
            or self.reset_cycles_remaining > 0
        )

    @property
    def legacy_selected(self) -> bool:
        return not self.runtime_active

    @property
    def activation_in_progress(self) -> bool:
        return self.reset_cycles_remaining > 0

    def execution_allowed(self, *, debugger_authorized: bool = True) -> bool:
        """The loader hold dominates normal run, pause, and step controls."""

        return debugger_authorized and not self.hold_reset

    def begin_load(self, *, manifest_accepted: bool = True) -> bool:
        """Start replacing the single runtime store while holding the NES."""

        self.activation_required = True
        self.staged_valid = False
        self.staged_manifest = None
        self.error = ActivationError.NONE
        if not manifest_accepted:
            self.load_in_progress = False
            self.error = ActivationError.LOAD_INVALID
            return False
        self.load_in_progress = True
        return True

    def complete_load(self, manifest: ImageManifest) -> bool:
        if not self.load_in_progress:
            self.error = ActivationError.LOAD_INVALID
            return False
        self.load_in_progress = False
        self.staged_manifest = manifest
        self.staged_valid = True
        self.error = ActivationError.NONE
        return True

    def fail_load(self) -> None:
        self.load_in_progress = False
        self.staged_valid = False
        self.staged_manifest = None
        self.error = ActivationError.LOAD_INVALID

    def activate(self, *, canonical_request: bool = True) -> bool:
        """Atomically publish staged metadata and start the reset window."""

        if not canonical_request or not self.staged_valid:
            self.error = ActivationError.ACTIVATE_INVALID
            return False

        self.runtime_active = True
        self.active_manifest = self.staged_manifest
        self.activation_required = False
        self.reset_cycles_remaining = self.reset_cycles
        self.error = ActivationError.NONE
        self.dma_active = False
        self.nmi_pending = False
        return True

    def tick(self) -> None:
        if self.hold_reset:
            self.dma_active = False
            self.nmi_pending = False
        if not self.physical_reset and self.reset_cycles_remaining > 0:
            self.reset_cycles_remaining -= 1

    def set_physical_reset(self, asserted: bool) -> None:
        self.physical_reset = asserted
        if asserted:
            self.load_in_progress = False
            self.staged_valid = False
            self.staged_manifest = None
            self.activation_required = False
            self.runtime_active = False
            self.active_manifest = None
            self.reset_cycles_remaining = 0
            self.error = ActivationError.NONE
            self.dma_active = False
            self.nmi_pending = False

    def start_dma(self) -> bool:
        if not self.execution_allowed():
            return False
        self.dma_active = True
        return True

    def request_nmi(self) -> bool:
        if not self.execution_allowed():
            return False
        self.nmi_pending = True
        return True
