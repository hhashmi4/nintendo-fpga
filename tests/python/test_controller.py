import pytest

from verification.controller import Button, ControllerPortModel, serial_bits


def latch(model: ControllerPortModel) -> None:
    model.write_4016(1)
    model.write_4016(0)


def test_button_bit_contract_and_order() -> None:
    assert [button.name for button in Button] == [
        "A",
        "B",
        "SELECT",
        "START",
        "UP",
        "DOWN",
        "LEFT",
        "RIGHT",
    ]
    for button in Button:
        expected = [0] * 8
        expected[int(button)] = 1
        assert serial_bits(1 << int(button)) == expected


@pytest.mark.parametrize("state", range(256))
def test_exhaustive_controller1_protocol(state: int) -> None:
    model = ControllerPortModel(state, state ^ 0xFF)
    latch(model)
    assert [model.read_4016() for _ in range(8)] == serial_bits(state)
    assert [model.read_4016() for _ in range(8)] == [1] * 8
    assert model.controller1_index == 8
    assert model.controller2_index == 0


@pytest.mark.parametrize("state", range(256))
def test_exhaustive_controller2_protocol(state: int) -> None:
    model = ControllerPortModel(state ^ 0xA5, state)
    latch(model)
    assert [model.read_4017() for _ in range(8)] == serial_bits(state)
    assert [model.read_4017() for _ in range(4)] == [1] * 4
    assert model.controller1_index == 0
    assert model.controller2_index == 8


def test_strobe_high_tracks_live_a_without_shifting() -> None:
    model = ControllerPortModel()
    model.write_4016(1)
    for controller1, controller2 in ((0x00, 0x01), (0x01, 0x00), (0xFE, 0xFF)):
        model.set_buttons(controller1, controller2)
        assert model.read_4016() == (controller1 & 1)
        assert model.read_4017() == (controller2 & 1)
        assert model.controller1_index == model.controller2_index == 0


def test_falling_edge_latches_both_and_live_changes_wait_for_next_latch() -> None:
    model = ControllerPortModel(0xA5, 0x5A)
    latch(model)
    model.set_buttons(0x3C, 0xC3)
    assert [model.read_4016() for _ in range(8)] == serial_bits(0xA5)
    assert [model.read_4017() for _ in range(8)] == serial_bits(0x5A)
    latch(model)
    assert [model.read_4016() for _ in range(8)] == serial_bits(0x3C)
    assert [model.read_4017() for _ in range(8)] == serial_bits(0xC3)


def test_ports_shift_independently_when_reads_are_interleaved() -> None:
    model = ControllerPortModel(0x81, 0x42)
    latch(model)
    controller1 = []
    controller2 = []
    for index in range(8):
        controller1.append(model.read_4016())
        assert model.controller1_index == index + 1
        assert model.controller2_index == index
        controller2.append(model.read_4017())
    assert controller1 == serial_bits(0x81)
    assert controller2 == serial_bits(0x42)


def test_reset_and_invalid_port_are_deterministic() -> None:
    model = ControllerPortModel(0xFF, 0xFF)
    latch(model)
    model.read_4016()
    model.read_4017()
    model.reset()
    assert not model.strobe
    assert model.controller1_shift == model.controller2_shift == 0
    assert model.controller1_index == model.controller2_index == 0
    assert model.read_4016() == model.read_4017() == 0
    with pytest.raises(ValueError, match="controller port"):
        model.read(2)
