"""Independent Phase 4E-A debug-snapshot layout and counter model."""

from __future__ import annotations

from dataclasses import dataclass


FIELD_WIDTHS: dict[str, dict[str, int]] = {
    "cpu": {
        "pc": 16, "a": 8, "x": 8, "y": 8, "sp": 8, "status": 8,
        "opcode": 8, "address": 16, "read_data": 8, "write_data": 8,
        "read": 1, "write": 1, "bus_valid": 1, "stalled": 1,
        "bus_owner": 2,
    },
    "ppu": {
        "scanline": 9, "dot": 9, "frame_odd": 1, "ctrl": 8,
        "mask": 8, "status": 8, "pixel_x": 8, "pixel_y": 8,
        "palette_address": 14, "pixel_color": 6, "pixel_emphasis": 3,
        "pixel_source": 2, "pixel_valid": 1, "nmi_enabled": 1,
        "nmi_level": 1, "nmi_event": 1, "nmi_suppressed": 1,
        "vblank": 1, "sprite_zero_hit": 1, "sprite_overflow": 1,
    },
    "cartridge": {
        "present": 1, "mapper_number": 8, "nrom_256": 1,
        "prg_address": 15, "prg_data": 8, "prg_read": 1,
        "prg_write": 1, "chr_address": 13, "chr_data": 8,
        "chr_read": 1, "chr_write": 1, "chr_is_ram": 1,
        "mirroring": 2,
    },
    "controller": {
        "live1": 8, "live2": 8, "shift1": 8, "shift2": 8,
        "index1": 4, "index2": 4, "strobe": 1, "serial1": 1,
        "serial2": 1, "read_4016": 1, "read_4017": 1,
        "latch_event": 1,
    },
    "dma": {
        "active": 1, "source_page": 8, "source_address": 16,
        "source_data": 8, "byte_index": 8, "oam_data": 8, "phase": 3,
        "started_odd": 1, "elapsed_slots": 10, "read_count": 9,
        "write_count": 9, "cpu_stall": 1, "bus_owner": 2,
        "start_event": 1, "read_event": 1, "write_event": 1,
        "complete_event": 1, "dummy_cycle": 1, "alignment_cycle": 1,
    },
    "system": {
        "snapshot_id": 32, "source_frame_number": 32, "nmi_count": 32,
        "dma_count": 32, "controller_poll_count": 32,
        "cpu_slot_count": 32, "ppu_cycle_count": 32,
        "prg_read_count": 32, "chr_read_count": 32,
        "missed_capture_count": 32,
    },
}

GROUP_WIDTHS = {
    group: sum(fields.values()) for group, fields in FIELD_WIDTHS.items()
}
SNAPSHOT_WIDTH = sum(GROUP_WIDTHS.values())


def empty_snapshot() -> dict[str, dict[str, int]]:
    return {
        group: {field: 0 for field in fields}
        for group, fields in FIELD_WIDTHS.items()
    }


def pack_snapshot(snapshot: dict[str, dict[str, int]]) -> int:
    """Pack in SystemVerilog packed-struct declaration order, MSB first."""
    packed = 0
    for group, fields in FIELD_WIDTHS.items():
        for field, width in fields.items():
            value = snapshot[group][field]
            if value < 0 or value >= 1 << width:
                raise ValueError(f"{group}.{field} does not fit {width} bits")
            packed = (packed << width) | value
    return packed


def unpack_snapshot(packed: int) -> dict[str, dict[str, int]]:
    if packed < 0 or packed >= 1 << SNAPSHOT_WIDTH:
        raise ValueError(f"snapshot does not fit {SNAPSHOT_WIDTH} bits")
    result = empty_snapshot()
    for group, fields in reversed(FIELD_WIDTHS.items()):
        for field, width in reversed(fields.items()):
            result[group][field] = packed & ((1 << width) - 1)
            packed >>= width
    return result


@dataclass
class SnapshotCounters:
    snapshot_id: int = 0
    source_frame_number: int = 0
    nmi_count: int = 0
    dma_count: int = 0
    controller_poll_count: int = 0
    cpu_slot_count: int = 0
    ppu_cycle_count: int = 0
    prg_read_count: int = 0
    chr_read_count: int = 0
    missed_capture_count: int = 0

    def observe(
        self,
        *,
        frame: bool = False,
        nmi: bool = False,
        dma: bool = False,
        controller_poll: bool = False,
        cpu_slot: bool = False,
        ppu_cycle: bool = False,
        prg_read: bool = False,
        chr_read: bool = False,
    ) -> None:
        mask = (1 << 32) - 1
        self.source_frame_number = (
            self.source_frame_number + int(frame)
        ) & mask
        self.nmi_count = (self.nmi_count + int(nmi)) & mask
        self.dma_count = (self.dma_count + int(dma)) & mask
        self.controller_poll_count = (
            self.controller_poll_count + int(controller_poll)
        ) & mask
        self.cpu_slot_count = (self.cpu_slot_count + int(cpu_slot)) & mask
        self.ppu_cycle_count = (self.ppu_cycle_count + int(ppu_cycle)) & mask
        self.prg_read_count = (self.prg_read_count + int(prg_read)) & mask
        self.chr_read_count = (self.chr_read_count + int(chr_read)) & mask

    def capture(self, *, accepted: bool = True) -> dict[str, int] | None:
        mask = (1 << 32) - 1
        if not accepted:
            self.missed_capture_count = (self.missed_capture_count + 1) & mask
            return None
        self.snapshot_id = (self.snapshot_id + 1) & mask
        return vars(self).copy()
