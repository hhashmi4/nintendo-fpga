import pytest

from verification.runtime_activation import (
    ActivationError,
    RuntimeActivationModel,
)
from verification.runtime_image import (
    CHR_ROM_BYTES,
    PRG_NROM128_BYTES,
    PRG_NROM256_BYTES,
    ImageManifest,
    Mirroring,
)


def manifest128(*, chr_is_ram=False, mirroring=Mirroring.HORIZONTAL):
    return ImageManifest(
        prg_bytes=PRG_NROM128_BYTES,
        chr_bytes=0 if chr_is_ram else CHR_ROM_BYTES,
        chr_is_ram=chr_is_ram,
        mirroring=mirroring,
    )


def manifest256(*, chr_is_ram=False, mirroring=Mirroring.VERTICAL):
    return ImageManifest(
        prg_bytes=PRG_NROM256_BYTES,
        chr_bytes=0 if chr_is_ram else CHR_ROM_BYTES,
        chr_is_ram=chr_is_ram,
        mirroring=mirroring,
    )


def stage(model, manifest):
    assert model.begin_load()
    assert model.complete_load(manifest)


def release(model):
    for _ in range(model.reset_cycles):
        assert model.hold_reset
        model.tick()
    assert not model.hold_reset


def test_no_runtime_image_preserves_legacy_execution():
    model = RuntimeActivationModel()
    assert model.legacy_selected
    assert not model.hold_reset
    assert model.execution_allowed()


def test_begin_asserts_safety_hold_without_deselecting_legacy():
    model = RuntimeActivationModel()
    assert model.begin_load()
    assert model.hold_reset and model.legacy_selected
    assert not model.execution_allowed()


def test_valid_staged_image_does_not_activate_implicitly():
    model = RuntimeActivationModel()
    stage(model, manifest128())
    assert model.staged_valid
    assert model.legacy_selected
    assert model.hold_reset


@pytest.mark.parametrize("manifest", [manifest128(), manifest256()])
def test_explicit_activation_atomically_selects_metadata(manifest):
    model = RuntimeActivationModel()
    stage(model, manifest)
    assert model.activate()
    assert model.runtime_active
    assert model.active_manifest == manifest
    assert model.activation_in_progress and model.hold_reset
    release(model)
    assert model.execution_allowed()


def test_activate_before_valid_is_deterministic_error():
    model = RuntimeActivationModel()
    assert not model.activate()
    assert model.error is ActivationError.ACTIVATE_INVALID
    assert model.legacy_selected and not model.hold_reset


def test_noncanonical_activate_cannot_publish_staged_image():
    model = RuntimeActivationModel()
    stage(model, manifest128())
    assert not model.activate(canonical_request=False)
    assert model.error is ActivationError.ACTIVATE_INVALID
    assert model.legacy_selected and model.hold_reset


def test_invalid_or_incomplete_load_never_releases_hold():
    model = RuntimeActivationModel()
    assert not model.begin_load(manifest_accepted=False)
    assert not model.activate()
    assert model.legacy_selected and model.hold_reset

    assert model.begin_load()
    model.fail_load()
    assert not model.activate()
    assert model.legacy_selected and model.hold_reset


def test_repeated_activate_is_an_idempotent_reboot():
    model = RuntimeActivationModel()
    image = manifest128()
    stage(model, image)
    assert model.activate()
    release(model)
    assert model.activate()
    assert model.runtime_active and model.active_manifest == image
    assert model.reset_cycles_remaining == model.reset_cycles


def test_second_runtime_image_replaces_first_without_stale_metadata():
    model = RuntimeActivationModel()
    first = manifest128(mirroring=Mirroring.HORIZONTAL)
    second = manifest256(chr_is_ram=True, mirroring=Mirroring.VERTICAL)
    stage(model, first)
    assert model.activate()
    release(model)

    assert model.begin_load()
    assert model.runtime_active and model.active_manifest == first
    assert model.hold_reset
    assert model.complete_load(second)
    assert model.active_manifest == first
    assert model.activate()
    assert model.active_manifest == second


def test_debugger_run_pause_and_steps_cannot_bypass_loader_hold():
    model = RuntimeActivationModel()
    assert model.execution_allowed(debugger_authorized=True)
    assert not model.execution_allowed(debugger_authorized=False)
    model.begin_load()
    assert not model.execution_allowed(debugger_authorized=True)
    assert not model.execution_allowed(debugger_authorized=False)


def test_activation_clears_old_dma_and_pending_nmi():
    model = RuntimeActivationModel()
    assert model.start_dma()
    assert model.request_nmi()
    stage(model, manifest128())
    assert model.activate()
    assert not model.dma_active and not model.nmi_pending
    assert not model.start_dma() and not model.request_nmi()
    release(model)
    assert model.start_dma() and model.request_nmi()


def test_physical_reset_mid_transfer_restores_legacy_mode():
    model = RuntimeActivationModel()
    model.begin_load()
    model.set_physical_reset(True)
    assert model.legacy_selected and model.hold_reset
    assert not model.staged_valid and not model.load_in_progress
    model.set_physical_reset(False)
    assert model.legacy_selected and not model.hold_reset


def test_physical_reset_drops_an_active_runtime_selection():
    model = RuntimeActivationModel()
    stage(model, manifest128())
    model.activate()
    model.set_physical_reset(True)
    assert model.legacy_selected
    assert model.active_manifest is None


def test_reset_length_must_be_positive():
    with pytest.raises(ValueError):
        RuntimeActivationModel(reset_cycles=0)
