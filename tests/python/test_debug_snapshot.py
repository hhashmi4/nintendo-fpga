import pytest

from verification.debug_snapshot import (
    FIELD_WIDTHS,
    GROUP_WIDTHS,
    SNAPSHOT_WIDTH,
    SnapshotCounters,
    empty_snapshot,
    pack_snapshot,
    unpack_snapshot,
)


def test_snapshot_group_and_total_widths_match_rtl() -> None:
    assert GROUP_WIDTHS == {
        "cpu": 102,
        "ppu": 92,
        "cartridge": 61,
        "controller": 46,
        "dma": 90,
        "system": 320,
        "debugger": 107,
    }
    assert SNAPSHOT_WIDTH == 818


def test_snapshot_pack_round_trip_and_boundaries() -> None:
    snapshot = empty_snapshot()
    for group, fields in FIELD_WIDTHS.items():
        for index, (field, width) in enumerate(fields.items()):
            snapshot[group][field] = ((index + 1) * 0x15) & ((1 << width) - 1)
    snapshot["cpu"].update(pc=0x8123, a=0x11, x=0x22, y=0x33, sp=0xF8)
    snapshot["ppu"].update(scanline=0, dot=0, ctrl=0x80, mask=0x1E)
    snapshot["cartridge"].update(present=1, mapper_number=0, prg_data=0xAD)
    snapshot["controller"].update(live1=0xA5, live2=0x5A)
    snapshot["dma"].update(source_address=0x02A6, source_data=0xC3)
    snapshot["system"].update(snapshot_id=7, source_frame_number=7)

    packed = pack_snapshot(snapshot)
    assert packed.bit_length() <= SNAPSHOT_WIDTH
    assert unpack_snapshot(packed) == snapshot

    snapshot["cpu"]["a"] = 0x100
    with pytest.raises(ValueError, match="cpu.a"):
        pack_snapshot(snapshot)


def test_snapshot_sequence_and_counter_cadence() -> None:
    counters = SnapshotCounters()
    snapshots = []
    for frame in range(1, 301):
        counters.observe(
            frame=True,
            nmi=frame > 3,
            dma=frame > 3,
            controller_poll=frame > 3,
            cpu_slot=True,
            ppu_cycle=True,
            prg_read=True,
            chr_read=True,
        )
        captured = counters.capture()
        assert captured is not None
        snapshots.append(captured)

    assert [snapshot["snapshot_id"] for snapshot in snapshots] == list(
        range(1, 301)
    )
    assert snapshots[-1] == {
        "snapshot_id": 300,
        "source_frame_number": 300,
        "nmi_count": 297,
        "dma_count": 297,
        "controller_poll_count": 297,
        "cpu_slot_count": 300,
        "ppu_cycle_count": 300,
        "prg_read_count": 300,
        "chr_read_count": 300,
        "missed_capture_count": 0,
    }


def test_rejected_capture_is_counted_without_advancing_snapshot_id() -> None:
    counters = SnapshotCounters(snapshot_id=9, source_frame_number=12)
    assert counters.capture(accepted=False) is None
    assert counters.snapshot_id == 9
    assert counters.source_frame_number == 12
    assert counters.missed_capture_count == 1
