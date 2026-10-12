import pytest

from verification.hdmi_transmitter import (
    ADV7513_720P_PROFILE,
    ADV7513_EDID_ADDRESS,
    ADV7513_MAIN_ADDRESS,
    HdmiError,
    HpdDebouncer,
    StartupModel,
    StartupState,
    apply_profile,
    i2c_register_events,
    measure_720p_frame,
    transmitter_samples,
    validate_edid,
    verify_profile,
)
from verification.shared_video import H_ACTIVE, H_SYNC, V_ACTIVE, V_SYNC


def make_edid(*, vic4: bool = True, extension: bool = True) -> bytes:
    base = bytearray(128)
    base[:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
    base[18:20] = bytes((1, 4))
    base[126] = int(extension)
    base[127] = (-sum(base[:127])) & 0xFF
    if not extension:
        return bytes(base)
    cta = bytearray(128)
    cta[0:4] = bytes((0x02, 0x03, 0x06, 0x00))
    cta[4] = 0x41
    cta[5] = 0x84 if vic4 else 0x90
    cta[127] = (-sum(cta[:127])) & 0xFF
    return bytes(base + cta)


def test_documented_i2c_addresses_are_seven_bit_forms() -> None:
    assert ADV7513_MAIN_ADDRESS == 0x72 >> 1
    assert ADV7513_EDID_ADDRESS == 0x7E >> 1


def test_i2c_write_transaction_has_start_ack_and_stop() -> None:
    events = i2c_register_events(0x39, 0x98, read=False, data=0x03)
    assert events[0] == ("START", None)
    assert events[-1] == ("STOP", None)
    assert ("WRITE", 0x72) in events
    assert ("REPEATED_START", None) not in events


def test_i2c_read_uses_repeated_start_and_master_nack() -> None:
    events = i2c_register_events(0x39, 0x42, read=True)
    assert ("REPEATED_START", None) in events
    assert ("WRITE", 0x73) in events
    assert events[-2:] == (("NACK", None), ("STOP", None))


def test_profile_preserves_unmasked_bits_and_order() -> None:
    configured, writes = apply_profile({0x41: 0xBF, 0x9A: 0x1B})
    assert configured[0x41] == 0xBF & ~0x40
    assert configured[0x9A] == 0xFB
    assert writes[0][0] == 0x41
    assert [address for address, _ in writes].count(0x4A) == 2
    assert verify_profile(configured)


def test_profile_is_video_only_and_selects_vic4() -> None:
    configured, _ = apply_profile({})
    assert configured[0x0B] & 0x80 == 0
    assert configured[0x0C] & 0x3C == 0
    assert configured[0x3C] & 0x3F == 4
    assert configured[0xAF] & 0x82 == 0x02


def test_profile_readback_detects_corruption() -> None:
    configured, _ = apply_profile({})
    configured[0x98] ^= 1
    assert not verify_profile(configured)


def test_hpd_connect_disconnect_and_bounce() -> None:
    debounce = HpdDebouncer(4)
    assert [debounce.sample(value) for value in (0, 1, 0, 1, 1, 1)] == [
        False,
        False,
        False,
        False,
        False,
        False,
    ]
    assert debounce.sample(True)
    for value in (False, True, False, True):
        assert debounce.sample(value)
    assert [debounce.sample(False) for _ in range(4)] == [True, True, True, False]


def test_hpd_rejects_invalid_policy() -> None:
    with pytest.raises(ValueError):
        HpdDebouncer(0)


def test_valid_cta_edid_supports_720p() -> None:
    result = validate_edid(make_edid())
    assert result.available and result.valid and result.supports_720p60


def test_edid_availability_is_distinct_from_validity() -> None:
    assert not validate_edid(None).available
    result = validate_edid(b"short")
    assert result.available and not result.valid


def test_edid_header_validation() -> None:
    image = bytearray(make_edid())
    image[0] = 1
    assert validate_edid(bytes(image)).reason == "invalid header"


def test_edid_base_checksum_validation() -> None:
    image = bytearray(make_edid())
    image[20] ^= 1
    assert validate_edid(bytes(image)).reason == "invalid base checksum"


def test_edid_extension_checksum_validation() -> None:
    image = bytearray(make_edid())
    image[150] ^= 1
    assert validate_edid(bytes(image)).reason == "invalid extension checksum"


def test_valid_edid_can_reject_unsupported_mode() -> None:
    result = validate_edid(make_edid(vic4=False))
    assert result.valid and not result.supports_720p60


def test_base_detailed_timing_identifies_720p() -> None:
    image = bytearray(make_edid(extension=False))
    dtd = bytearray(18)
    dtd[0:2] = (7425).to_bytes(2, "little")
    dtd[2], dtd[3], dtd[4] = 0x00, 0x72, 0x51
    dtd[5], dtd[6], dtd[7] = 0xD0, 0x1E, 0x20
    image[54:72] = dtd
    image[127] = (-sum(image[:127])) & 0xFF
    result = validate_edid(bytes(image))
    assert result.valid and result.supports_720p60


def test_720p_measurements_are_exact() -> None:
    measured = measure_720p_frame()
    assert measured.line_pixels == 1650
    assert measured.frame_pixels == 1_237_500
    assert measured.active_pixels == H_ACTIVE * V_ACTIVE
    assert measured.hsync_pixels == H_SYNC * 750
    assert measured.vsync_lines == V_SYNC
    assert measured.frames_per_second == 60.0


def test_rgb_and_sync_are_sampled_as_one_aligned_tuple() -> None:
    launched = ((0x123456, True, False, True), (0xABCDEF, False, True, False))
    assert transmitter_samples(launched, enabled=True) == (
        launched[0],
        (0, False, True, False),
    )
    assert all(sample[0] == 0 and not sample[3] for sample in
               transmitter_samples(launched, enabled=False))


def run_successful_startup(model: StartupModel) -> None:
    valid = validate_edid(make_edid())
    expected = (
        StartupState.WAIT_CLOCK,
        StartupState.WAIT_HPD,
        StartupState.CONFIGURE,
        StartupState.VERIFY_CONFIG,
        StartupState.CHECK_DISPLAY_CAPABILITY,
        StartupState.ENABLE_VIDEO,
        StartupState.RUNNING,
    )
    observed = (
        model.advance(),
        model.advance(),
        model.advance(),
        model.advance(),
        model.advance(),
        model.advance(edid=valid),
        model.advance(),
    )
    assert observed == expected


def test_startup_sequence_enables_only_after_edid() -> None:
    model = StartupModel()
    run_successful_startup(model)
    assert model.video_enabled


@pytest.mark.parametrize(
    ("stage", "kwargs", "error"),
    (
        (StartupState.WAIT_CLOCK, {"clock_locked": False}, HdmiError.HDMI_PIXEL_CLOCK_UNLOCKED),
        (StartupState.CONFIGURE, {"config_ok": False}, HdmiError.HDMI_TX_I2C_NACK),
        (StartupState.VERIFY_CONFIG, {"verify_ok": False}, HdmiError.HDMI_CONFIG_VERIFY_FAILED),
        (StartupState.CHECK_DISPLAY_CAPABILITY, {"edid": validate_edid(b"bad")}, HdmiError.HDMI_EDID_INVALID),
        (StartupState.CHECK_DISPLAY_CAPABILITY, {"edid": validate_edid(make_edid(vic4=False))}, HdmiError.HDMI_MODE_UNSUPPORTED),
    ),
)
def test_startup_faults_fail_closed(stage: StartupState, kwargs: dict, error: HdmiError) -> None:
    model = StartupModel()
    while model.state != stage:
        model.advance()
    model.advance(**kwargs)
    assert model.state is StartupState.FAULT
    assert model.error is error
    assert not model.video_enabled


def test_disconnect_and_reconnect_reconfigure() -> None:
    model = StartupModel()
    run_successful_startup(model)
    assert model.advance(hpd=False) is StartupState.RECOVERY
    assert model.advance() is StartupState.WAIT_CLOCK
    assert not model.video_enabled


def test_recovery_is_bounded() -> None:
    model = StartupModel(max_recoveries=2)
    model.state = StartupState.FAULT
    assert model.advance() is StartupState.RECOVERY
    model.state = StartupState.FAULT
    assert model.advance() is StartupState.RECOVERY
    model.state = StartupState.FAULT
    assert model.advance() is StartupState.FAULT
    assert model.error is HdmiError.HDMI_RECOVERY_FAILED
    assert model.recoveries == 2
    assert model.recovery_attempts == 2


def test_profile_has_no_undocumented_wildcard_writes() -> None:
    assert len(ADV7513_720P_PROFILE) == 24
    assert all(0 <= item.address <= 0xFF and item.mask for item in ADV7513_720P_PROFILE)
