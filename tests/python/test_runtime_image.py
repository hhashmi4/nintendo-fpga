import pytest

from verification.runtime_image import (
    CHR_ROM_BYTES,
    PRG_NROM128_BYTES,
    PRG_NROM256_BYTES,
    ImageError,
    ImageManifest,
    Mirroring,
    RuntimeImageModel,
    State,
    Target,
    validate_manifest,
)


def manifest128(*, chr_is_ram=False, mirroring=Mirroring.HORIZONTAL):
    return ImageManifest(
        prg_bytes=PRG_NROM128_BYTES,
        chr_bytes=0 if chr_is_ram else CHR_ROM_BYTES,
        chr_is_ram=chr_is_ram,
        mirroring=mirroring,
    )


def write_range(model, target, count):
    for address in range(count):
        assert model.write(target, address)


@pytest.mark.parametrize("prg_bytes", [PRG_NROM128_BYTES, PRG_NROM256_BYTES])
def test_valid_nrom_manifest_sizes(prg_bytes):
    assert validate_manifest(
        ImageManifest(prg_bytes=prg_bytes)
    ) is ImageError.NONE


def test_valid_chr_rom_configuration():
    assert validate_manifest(manifest128()) is ImageError.NONE


def test_valid_chr_ram_configuration_has_no_rom_payload():
    assert validate_manifest(manifest128(chr_is_ram=True)) is ImageError.NONE


def test_unsupported_mapper():
    manifest = ImageManifest(mapper=2)
    assert validate_manifest(manifest) is ImageError.UNSUPPORTED_MAPPER


@pytest.mark.parametrize("prg_bytes", [0, 8192, 16383, 16385, 65535])
def test_invalid_prg_size(prg_bytes):
    manifest = ImageManifest(prg_bytes=prg_bytes)
    assert validate_manifest(manifest) is ImageError.UNSUPPORTED_PRG


@pytest.mark.parametrize(
    ("chr_bytes", "chr_is_ram"),
    [(0, False), (1, True), (CHR_ROM_BYTES, True), (4096, False)],
)
def test_invalid_or_contradictory_chr_configuration(chr_bytes, chr_is_ram):
    manifest = ImageManifest(chr_bytes=chr_bytes, chr_is_ram=chr_is_ram)
    assert validate_manifest(manifest) is ImageError.UNSUPPORTED_CHR


@pytest.mark.parametrize(
    "kwargs",
    [
        {"manifest_valid": False},
        {"begin_target": Target.PRG},
        {"begin_address": 1},
        {"begin_data": 1},
    ],
)
def test_missing_or_noncanonical_manifest(kwargs):
    assert validate_manifest(manifest128(), **kwargs) is ImageError.INVALID_MANIFEST


@pytest.mark.parametrize(
    "mirroring", [Mirroring.VERTICAL, Mirroring.HORIZONTAL]
)
def test_supported_mirroring(mirroring):
    assert validate_manifest(
        manifest128(mirroring=mirroring)
    ) is ImageError.NONE


@pytest.mark.parametrize(
    "mirroring", [Mirroring.RESERVED_2, Mirroring.RESERVED_3]
)
def test_reserved_mirroring(mirroring):
    assert validate_manifest(
        manifest128(mirroring=mirroring)
    ) is ImageError.INVALID_MANIFEST


def test_empty_prg_commit_is_incomplete():
    model = RuntimeImageModel()
    assert model.begin(manifest128())
    assert not model.commit()
    assert model.error_code is ImageError.PRG_INCOMPLETE


def test_partially_loaded_prg_is_incomplete():
    model = RuntimeImageModel()
    model.begin(manifest128())
    write_range(model, Target.PRG, 37)
    assert not model.commit()
    assert model.error_code is ImageError.PRG_INCOMPLETE


def test_complete_prg_then_partial_chr_reports_chr_incomplete():
    model = RuntimeImageModel()
    model.begin(manifest128())
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    write_range(model, Target.CHR, 19)
    assert not model.commit()
    assert model.error_code is ImageError.CHR_INCOMPLETE


def test_complete_chr_may_be_interleaved_with_prg():
    model = RuntimeImageModel()
    model.begin(manifest128())
    for address in range(CHR_ROM_BYTES):
        assert model.write(Target.CHR, address)
        if address < PRG_NROM128_BYTES:
            assert model.write(Target.PRG, address)
    write_range_from = CHR_ROM_BYTES
    for address in range(write_range_from, PRG_NROM128_BYTES):
        assert model.write(Target.PRG, address)
    assert model.commit() and model.image_valid


def test_duplicate_write_is_rejected_without_advancing_coverage():
    model = RuntimeImageModel()
    model.begin(manifest128())
    assert model.write(Target.PRG, 0)
    assert not model.write(Target.PRG, 0)
    assert model.next_prg_address == 1
    assert model.error_code is ImageError.UNEXPECTED_ADDRESS


def test_out_of_order_write_is_rejected_without_advancing_coverage():
    model = RuntimeImageModel()
    model.begin(manifest128())
    assert not model.write(Target.PRG, 1)
    assert model.next_prg_address == 0
    assert model.error_code is ImageError.UNEXPECTED_ADDRESS


def test_exact_final_byte_completes_prg_only_after_acceptance():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES - 1)
    assert not model.prg_complete
    assert model.write(Target.PRG, PRG_NROM128_BYTES - 1)
    assert model.prg_complete and model.commit()


def test_one_byte_short_prg():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES - 1)
    assert not model.commit()
    assert model.error_code is ImageError.PRG_INCOMPLETE


def test_one_byte_short_chr():
    model = RuntimeImageModel()
    model.begin(manifest128())
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    write_range(model, Target.CHR, CHR_ROM_BYTES - 1)
    assert not model.commit()
    assert model.error_code is ImageError.CHR_INCOMPLETE


def test_successful_nrom128_commit():
    model = RuntimeImageModel()
    model.begin(manifest128())
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    write_range(model, Target.CHR, CHR_ROM_BYTES)
    assert model.commit()
    assert model.state is State.READY and model.image_valid


def test_successful_nrom256_commit():
    model = RuntimeImageModel()
    model.begin(ImageManifest(prg_bytes=PRG_NROM256_BYTES))
    write_range(model, Target.PRG, PRG_NROM256_BYTES)
    write_range(model, Target.CHR, CHR_ROM_BYTES)
    assert model.commit() and model.image_valid


def test_chr_ram_rejects_chr_payload_and_needs_only_prg():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    assert not model.write(Target.CHR, 0)
    assert model.error_code is ImageError.BAD_TARGET

    assert model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    assert model.commit() and model.image_valid


def test_declared_boundary_rejects_extra_prg_byte():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    assert not model.write(Target.PRG, PRG_NROM128_BYTES)
    assert model.error_code is ImageError.BAD_ADDRESS


def test_reset_mid_transfer_clears_manifest_coverage_and_validity():
    model = RuntimeImageModel()
    model.begin(manifest128())
    write_range(model, Target.PRG, 123)
    model.reset()
    assert model.state is State.IDLE
    assert model.manifest is None
    assert model.next_prg_address == 0 and not model.image_valid


def test_error_new_begin_complete_transfer_recovers():
    model = RuntimeImageModel()
    model.begin(manifest128())
    assert not model.write(Target.PRG, 7)
    assert model.state is State.ERROR
    assert model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    assert model.commit() and model.image_valid


def test_new_begin_after_valid_image_invalidates_old_result():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    assert model.commit() and model.image_valid
    assert model.begin(manifest128())
    assert not model.image_valid and model.state is State.LOADING


def test_stale_coverage_cannot_leak_between_sessions():
    model = RuntimeImageModel()
    model.begin(manifest128(chr_is_ram=True))
    write_range(model, Target.PRG, PRG_NROM128_BYTES)
    assert model.commit()
    assert model.begin(manifest128(chr_is_ram=True))
    assert model.next_prg_address == 0
    assert not model.commit()
    assert model.error_code is ImageError.PRG_INCOMPLETE


def test_first_error_latches_until_new_begin():
    model = RuntimeImageModel()
    model.begin(manifest128())
    assert not model.write(Target.PRG, 2)
    assert model.error_code is ImageError.UNEXPECTED_ADDRESS
    assert not model.write(Target.RESERVED, 0)
    assert model.error_code is ImageError.UNEXPECTED_ADDRESS
