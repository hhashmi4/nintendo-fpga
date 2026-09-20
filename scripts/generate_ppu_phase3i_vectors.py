#!/usr/bin/env python3
"""Generate deterministic integrated Phase 3I timing/register/NMI vectors."""

from argparse import ArgumentParser
from pathlib import Path
import sys
from typing import TextIO


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from verification.ppu_nmi import PpuNmiInputs, PpuNmiModel  # noqa: E402
from verification.ppu_timing import PpuTimingModel  # noqa: E402


RANDOM_SEED = 0x3912_0260
FRAME_COUNT = 10


class XorShift32:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFF_FFFF

    def next(self) -> int:
        value = self.state
        value ^= (value << 13) & 0xFFFF_FFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFF_FFFF
        self.state = value & 0xFFFF_FFFF
        return self.state


def action_for(frame: int, scanline: int, dot: int) -> tuple[int, bool, int] | None:
    """Return (kind, write, data) for deterministic accepted accesses."""

    start_enable = {
        0: True,
        1: False,
        2: False,
        3: True,
        4: True,
        5: True,
        6: True,
        7: True,
        8: False,
        9: True,
    }[frame]
    if (scanline, dot) == (0, 5):
        return 1, True, 0x80 if start_enable else 0x00

    boundary_coordinate = {
        3: (240, 340),
        4: (241, 0),
        5: (241, 1),
        6: (241, 2),
        7: (241, 3),
    }.get(frame)
    if boundary_coordinate == (scanline, dot):
        return 2, False, 0

    if frame == 2 and scanline == 241:
        dynamic = {
            10: 0x80,
            20: 0x00,
            30: 0x80,
            40: 0x00,
            50: 0x80,
            60: None,
            70: 0x00,
            80: 0x80,
        }
        if dot in dynamic:
            value = dynamic[dot]
            return (4, False, 0) if value is None else (3, True, value)

    # Same-edge policy: writing bit 7 at the 241:1 set coordinate participates
    # in the ordinary qualified activation rather than an independent event.
    if frame == 8 and (scanline, dot) == (241, 1):
        return 3, True, 0x80
    # The pre-render clear wins over a same-edge enable write: PPUCTRL stores
    # the new value, but the cleared VBlank latch cannot activate NMI.
    if frame == 9 and (scanline, dot) == (261, 1):
        return 3, True, 0x80
    return None


def generate(vector_path: Path, stats_path: Path) -> None:
    timing = PpuTimingModel()
    nmi = PpuNmiModel()
    rng = XorShift32(RANDOM_SEED)
    consumed_actions: set[tuple[int, int, int]] = set()

    ppuctrl = 0
    sprite_zero = False
    sprite_overflow = False
    frame = 0
    fabric_cycles = 0
    enabled_ticks = 0
    stalls = 0
    frame_boundaries = 0
    vblank_sets = 0
    vblank_clears = 0
    status_reads = 0
    control_writes = 0
    condition_activations = 0
    nmi_events = 0
    suppressed_nmis = 0

    vector_path.parent.mkdir(parents=True, exist_ok=True)
    with vector_path.open("w", encoding="ascii", newline="\n") as stream:
        # Reset edges are part of the machine-checked stream but excluded from
        # frame/event counters in the same way as the RTL testbench.
        for _ in range(3):
            pre = timing.snapshot()
            observed = nmi.clock(PpuNmiInputs(reset=True))
            timing.clock(reset=True, ppu_enable=False, rendering_enabled=False)
            post = timing.snapshot()
            values = (
                1, 0, 0, 0, 0, 0, 0, 0, 0,
                pre.scanline, pre.dot, int(pre.frame_odd), int(pre.vblank),
                0, 0, 0,
                post.scanline, post.dot, int(post.frame_odd),
                int(observed.status_vblank), 0, 0, ppuctrl,
                int(observed.nmi_enable), int(observed.nmi_level),
                int(observed.nmi_event), int(observed.nmi_suppressed),
                int(post.vblank), 0, frame, 0,
            )
            stream.write(" ".join(str(value) for value in values) + "\n")
            fabric_cycles += 1

        while frame < FRAME_COUNT:
            pre = timing.snapshot()
            key = (frame, pre.scanline, pre.dot)
            scheduled = action_for(frame, pre.scanline, pre.dot)
            action = scheduled if scheduled is not None and key not in consumed_actions else None

            random_word = rng.next()
            ppu_enable = (random_word & 7) != 0
            # Deterministic accesses consume their named coordinate. Force the
            # PPU tick so offsets retain their precise meaning despite stalls.
            if action is not None:
                ppu_enable = True

            cpu_enable = False
            cpu_valid = False
            cpu_write = False
            cpu_address = 0
            cpu_data = 0
            action_kind = 0

            if action is not None:
                action_kind, cpu_write, cpu_data = action
                cpu_enable = True
                cpu_valid = True
                cpu_address = 0x2000 if cpu_write else 0x2002
                consumed_actions.add(key)
            elif frame == 9 and pre.scanline >= 241 and (random_word % 97) == 0:
                # Random NMI-control and status traffic during the final frame's
                # VBlank exercises arbitrary repeated condition transitions.
                cpu_enable = True
                cpu_valid = True
                if random_word & 0x100:
                    cpu_write = True
                    cpu_address = 0x2000
                    cpu_data = 0x80 if random_word & 0x200 else 0
                    action_kind = 6
                else:
                    cpu_address = 0x2002
                    action_kind = 7
            elif (random_word % 251) == 0:
                # Ordinary mirrored register traffic must have no NMI effect.
                register = (1, 3, 4, 5, 6, 7)[(random_word >> 8) % 6]
                cpu_enable = bool(random_word & 0x400)
                cpu_valid = bool(random_word & 0x800)
                cpu_write = bool(random_word & 0x1000)
                cpu_address = 0x2000 + (((random_word >> 16) & 0x3FF) << 3) + register
                cpu_data = (random_word >> 24) & 0xFF
                if register == 1:
                    cpu_data = 0
                action_kind = 8

            accepted = cpu_enable and cpu_valid and 0x2000 <= cpu_address <= 0x3FFF
            status_read = accepted and not cpu_write and (cpu_address & 7) == 2
            control_write = accepted and cpu_write and (cpu_address & 7) == 0
            vblank_start = timing.vblank_start(ppu_enable)
            status_clear = timing.vblank_end(ppu_enable)
            frame_end = timing.frame_end(False, ppu_enable)

            # Directed sprite status activity proves that $2002/NMI logic does
            # not clear or source either independent sprite flag.
            sprite_zero_set = ppu_enable and frame == 2 and (pre.scanline, pre.dot) == (20, 100)
            sprite_overflow_set = ppu_enable and frame == 2 and (pre.scanline, pre.dot) == (30, 120)
            old_vblank = nmi.status_vblank
            old_level = nmi.nmi_level
            returned_status = old_vblank

            observed = nmi.clock(
                PpuNmiInputs(
                    ppu_enable=ppu_enable,
                    scanline=pre.scanline,
                    dot=pre.dot,
                    vblank_start=vblank_start,
                    status_clear=status_clear,
                    status_read=status_read,
                    control_write=control_write,
                    control_nmi_enable=bool(cpu_data & 0x80),
                )
            )

            if status_clear:
                sprite_zero = False
                sprite_overflow = False
            else:
                sprite_zero |= sprite_zero_set
                sprite_overflow |= sprite_overflow_set
            if control_write:
                ppuctrl = cpu_data & 0xFF

            timing.clock(ppu_enable=ppu_enable, rendering_enabled=False)
            post = timing.snapshot()

            values = (
                0,
                int(ppu_enable),
                int(cpu_enable),
                int(cpu_valid),
                int(cpu_write),
                cpu_address,
                cpu_data,
                int(sprite_zero_set),
                int(sprite_overflow_set),
                pre.scanline,
                pre.dot,
                int(pre.frame_odd),
                int(pre.vblank),
                int(vblank_start),
                int(status_clear),
                int(returned_status),
                post.scanline,
                post.dot,
                int(post.frame_odd),
                int(observed.status_vblank),
                int(sprite_zero),
                int(sprite_overflow),
                ppuctrl,
                int(observed.nmi_enable),
                int(observed.nmi_level),
                int(observed.nmi_event),
                int(observed.nmi_suppressed),
                int(post.vblank),
                int(accepted),
                frame,
                action_kind,
            )
            stream.write(" ".join(str(value) for value in values) + "\n")

            fabric_cycles += 1
            enabled_ticks += int(ppu_enable)
            stalls += int(not ppu_enable)
            frame_boundaries += int(frame_end)
            vblank_sets += int(not old_vblank and observed.status_vblank)
            vblank_clears += int(old_vblank and not observed.status_vblank)
            status_reads += int(status_read)
            control_writes += int(control_write)
            condition_activations += int(not old_level and observed.nmi_level)
            nmi_events += int(observed.nmi_event)
            suppressed_nmis += int(observed.nmi_suppressed)

            if frame_end:
                frame += 1

    stats = (
        RANDOM_SEED,
        fabric_cycles,
        enabled_ticks,
        stalls,
        frame_boundaries,
        vblank_sets,
        vblank_clears,
        status_reads,
        control_writes,
        condition_activations,
        nmi_events,
        suppressed_nmis,
    )
    stats_path.write_text(" ".join(str(value) for value in stats) + "\n", encoding="ascii")
    print(
        "Phase 3I reference: "
        f"seed=0x{RANDOM_SEED:08X} fabric={fabric_cycles} "
        f"ticks={enabled_ticks} stalls={stalls} frames={frame_boundaries} "
        f"vblank_sets={vblank_sets} clears={vblank_clears} "
        f"status_reads={status_reads} control_writes={control_writes} "
        f"activations={condition_activations} events={nmi_events} "
        f"suppressed={suppressed_nmis}"
    )


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("vector_output", type=Path)
    parser.add_argument("stats_output", type=Path)
    args = parser.parse_args()
    generate(args.vector_output, args.stats_output)


if __name__ == "__main__":
    main()
