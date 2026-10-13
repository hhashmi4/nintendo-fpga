#!/usr/bin/env python3
"""Independent expected snapshots for directed and deterministic random RTL tests."""
import json
from pathlib import Path
import random
from verification.usbc_power import PowerModel, STATES, packet


def scenarios():
    good = packet()
    yield 'no_cable', [(0, True, False, True)] + [(0, True, False, False)] * 8
    cases = {
        'standard_5v_attach': packet(5000, 0, 3),
        'cc_1p5a': packet(5000, 1500, 0xffeb),
        'cc_3a': packet(5000, 3000, 0xffdb),
        'pd_5v3a': packet(5000),
        'valid_9v': good,
        'insufficient_9v': packet(ma=2000),
        'pd_timeout': packet(flags=3),
        'pd_rejected': packet(faults=256),
        'invalid_voltage': packet(12000),
        'invalid_current_zero': packet(ma=0),
        'invalid_current_high': packet(ma=5000),
        'invalid_current_units': packet(ma=2999),
        'invalid_reserved_status': good | (1 << 26),
        'startup_timeout': good & ~(15 << 12),
    }
    for name, value in cases.items():
        yield name, [(0, True, False, True)] + [(value, True, False, False)] * 60
    for bit in range(10):
        bad = good | (1 << (16 + bit))
        yield f'external_fault_{bit}_clear_relatch_recovery', (
            [(0, True, False, True)] + [(good, True, False, False)] * 16 +
            [(bad, True, False, False)] * 3 + [(bad, True, True, False)] +
            [(bad, True, False, False)] * 24 + [(good, True, True, False)] +
            [(good, True, False, False)] * 30)
    for name, bad in [('detach', 0), ('power_good_loss', good & ~(1 << 6)),
                      ('rail_loss', good & ~(1 << 12)), ('fpga_not_ready', good & ~(1 << 7)),
                      ('hps_reset', good & ~(1 << 8)), ('ddr_loss', good & ~(1 << 9)),
                      ('contract_change', packet(5000)), ('pd_lost', good & ~(1 << 3)),
                      ('video_gating', good & ~(1 << 10)), ('audio_gating', good & ~(1 << 11))]:
        yield name, ([(0, True, False, True)] + [(good, True, False, False)] * 16 +
                     [(bad, True, False, False)] * 5 + [(good, True, True, False)] +
                     [(good, True, False, False)] * 30)
    yield 'pd_deadline_refresh', ([(0, True, False, True)] + [(packet(flags=3), True, False, False)] * 13 + [(good, True, False, False)] * 20)
    yield 'delayed_rails', ([(0, True, False, True)] +
        [(good & ~(15 << 12), True, False, False)] * 8 +
        [(good & ~(14 << 12), True, False, False)] * 5 +
        [(good & ~(12 << 12), True, False, False)] * 5 +
        [(good, True, False, False)] * 20)
    yield 'stale_status', ([(0, True, False, True)] + [(good, True, False, False)] * 16 +
        [(0, False, False, False)] * 25 + [(good, True, True, False)] +
        [(good, True, False, False)] * 30)
    yield 'reset_startup_and_running', ([(0, True, False, True)] +
        [(good, True, False, False)] * 5 + [(good, True, False, True)] +
        [(good, True, False, False)] * 16 + [(good, True, False, True)])
    yield 'all_current_encodings', [row for ma in range(65536) for row in ((0, True, False, True), (packet(ma=ma), True, False, False))]
    # Reduced counter maximum exercises the exact saturation datapath in RTL.
    yield 'counter_saturation', ([(0, True, False, True)] +
        ([(good, True, False, False)] * 12 + [(packet(faults=1), True, False, False)] +
         [(good, True, True, False)] + [(good, True, False, False)] * 24 +
         [(0, True, False, False)] * 2) * 300)


def generate(destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    metadata = []
    with destination.open('w') as output:
        def emit(name, rows, seed=None):
            model = PowerModel()
            transitions = faults = recoveries = 0
            visited = set()
            count = 0
            for data, valid, clear, reset in rows:
                previous = model.state
                old_faults, old_recoveries = model.fault_count, model.recovery_count
                diag, ready, video, audio = model.step(data, valid, clear, reset)
                transitions += previous != model.state
                faults += max(0, model.fault_count - old_faults)
                recoveries += max(0, model.recovery_count - old_recoveries)
                visited.add(model.state)
                output.write(f'{int(reset):x} {int(valid):x} {int(clear):x} {data:016x} {diag:0104x} {ready:x} {video:x} {audio:x}\n')
                count += 1
            metadata.append(dict(name=name, seed=seed, cycles=count, transitions=transitions,
                                 fault_events=faults, recovery_attempts=recoveries,
                                 states=sorted(visited), expected_mismatches=0))
        for name, rows in scenarios():
            emit(name, rows)
        for seed in (0x6e202601, 0x6e202602, 0x6e202603):
            rng = random.Random(seed)
            rows = [(0, True, False, True)]
            for _ in range(1000):
                kind = rng.randrange(10)
                value = packet()
                if kind == 0: value = 0
                if kind == 1: value = packet(rng.choice((5000, 9000, 12000)), rng.choice((0, 1500, 2000, 2999, 3000, 4000)))
                if kind == 2: value |= rng.randrange(1024) << 16
                if kind == 3: value &= ~(rng.randrange(16) << 12)
                if kind == 4: value &= ~(1 << rng.randrange(6, 12))
                for j in range(rng.randrange(1, 65)):
                    rows.append((value, kind != 5 and rng.random() < .8,
                                 j == 0 or rng.random() < .03, rng.random() < .002))
            emit('random', rows, seed)
    states = {s for item in metadata for s in item['states']}
    assert states == set(STATES), states
    summary = dict(total_cycles=sum(x['cycles'] for x in metadata), cases=metadata)
    destination.with_suffix('.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f'Phase 6E vectors: {summary["total_cycles"]} cycles, {len(metadata)} cases, all 12 states, 3 seeds')

if __name__ == '__main__':
    generate('build/sim/phase6e_power_vectors.txt')
