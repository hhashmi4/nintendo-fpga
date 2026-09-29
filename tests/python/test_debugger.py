import pytest
from verification.debugger import Debugger, State, TokenSource


@pytest.mark.parametrize("state", list(State))
@pytest.mark.parametrize("command", range(8))
def test_command_disposition(state, command):
    model = Debugger(state=state)
    returned, result = model.submit(command, 17)
    expected = (3 if command > 3 else 2 if state not in
                (State.RUNNING, State.PAUSED) else 1 if command >= 2 and
                state != State.PAUSED else 0)
    assert result == expected
    assert returned == model.state
    assert model.sequence == 17
    if expected:
        assert model.state == state
        assert model.last_command == 0


def test_reset_pause_resume_and_repeated_commands():
    d = Debugger()
    assert d.state == State.RUNNING and d.sequence == 0
    assert d.submit(0, 1) == (State.RUNNING, 0)
    d.submit(1, 2)
    d.advance(safe=False)
    assert d.state == State.PAUSE_PENDING
    d.advance(safe=True, pc=0x8000)
    assert d.state == State.PAUSED and d.after == 0x8000
    assert d.submit(1, 3) == (State.PAUSED, 0)
    assert d.submit(0, 4) == (State.RUNNING, 0)


def test_steps_retirement_interrupt_entry_dma_and_repeated_tokens():
    d = Debugger(state=State.PAUSED)
    for i in range(1, 33):
        d.submit(2, i, pc=0x8000+i)
        # Completing interrupt entry does not retire a normal instruction.
        d.advance(safe=True, retired=False)
        assert d.state == State.STEP_I
        # A retired $4014 instruction still owes an entire DMA transfer.
        d.advance(safe=False, retired=True)
        assert d.instruction_steps == i-1
        d.advance(safe=True, pc=0x9000+i)
        assert d.state == State.PAUSED and d.instruction_steps == i
        assert d.before == 0x8000+i and d.after == 0x9000+i
        assert d.boundary == 2


def test_frame_boundary_and_completion_overrun():
    d = Debugger(state=State.PAUSED)
    for i in range(1, 9):
        d.submit(3, i)
        d.advance(safe=True, ppu_tick=True)
        assert d.state == State.STEP_F
        d.advance(safe=False, frame=True, ppu_tick=True)
        for _ in range(i):
            d.advance(safe=False, ppu_tick=True)
        d.advance(safe=True)
        assert d.state == State.PAUSED
        assert d.frame_steps == i and d.overrun == i and d.boundary == 3


def test_held_request_reset_rearm_busy_and_sequence_wrap():
    s = TokenSource()
    assert s.sample(True, True, 2) is None
    s.sample(False, True, 2)
    assert s.sample(True, False, 2) is None
    assert s.sample(True, True, 2) == (2, 1)
    for _ in range(10):
        assert s.sample(True, True, 2) is None
    s.sequence = 0xFFFF
    s.sample(False, True, 3)
    assert s.sample(True, True, 3) == (3, 0)
