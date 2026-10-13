"""Phase 6E: independent arithmetic and deadline-based power observation model.

The model consumes normalized reports, not physical USB packets or voltages.
"""
from dataclasses import dataclass
from fractions import Fraction
from math import ceil
from pathlib import Path
import json
from urllib.parse import urlparse

STATES = ('POWER_OFF', 'ATTACHED', 'CONTRACT_PENDING', 'CONTRACT_VALID',
          'INPUT_PROTECTED', 'RAILS_STARTING', 'RAILS_STABLE', 'FPGA_RELEASE',
          'SYSTEM_READY', 'FAULT', 'SHUTDOWN', 'RECOVERY')
FAULTS = ('VBUS_OVERVOLTAGE', 'VBUS_UNDERVOLTAGE', 'INPUT_OVERCURRENT',
          'SHORT_CIRCUIT', 'REVERSE_CURRENT', 'THERMAL_SHUTDOWN', 'REGULATOR_FAULT',
          'RAIL_POWER_GOOD_LOSS', 'PD_REJECTED', 'BROWNOUT', 'UNEXPECTED_DETACH',
          'INVALID_CONTRACT', 'INSUFFICIENT_POWER', 'PD_TIMEOUT', 'STARTUP_TIMEOUT',
          'RECOVERY_TIMEOUT', 'STALE_STATUS', 'INVALID_STATUS', 'CONFIGURATION_LOSS',
          'HPS_NOT_READY', 'DDR_NOT_READY', 'INVALID_STATE')


def contract_valid(packet):
    mv, ma = (packet >> 32) & 65535, packet >> 48
    if not packet & 8:
        return False
    if packet & 4:
        return mv in (5000, 9000) and 10 <= ma <= 3000 and ma % 10 == 0
    return mv == 5000 and ((packet & 48, ma) in ((16, 3000), (32, 1500)))


def full_power(packet):
    return contract_valid(packet) and bool(packet & 4) and packet >> 32 == (3000 << 16 | 9000)


def select_contract(source_pdos):
    """Policy selection, not a PD protocol emulator. No offer implies no 9V."""
    for mv, wanted_ma in ((9000, 3000), (5000, 3000)):
        if any(v == mv and a >= wanted_ma for v, a in source_pdos):
            return mv, wanted_ma
    return None


def available_power(mv, ma, factor_ppm=950000, cable_drop_mv=500):
    if not 0 <= ma <= 3000 or mv not in (5000, 9000):
        raise ValueError('unsupported input contract')
    return Fraction(max(0, mv * factor_ppm - cable_drop_mv * 1000000) * ma, 10**9)


def power_budget(loads, budget):
    totals = {mode: sum(x[f'{mode}_mw'] for x in loads) for mode in ('typical', 'peak')}
    input_power = {mode: Fraction(totals[mode] * 1000000, budget[f'efficiency_{mode}_ppm'])
                   + budget[f'protection_{mode}_mw'] for mode in totals}
    return dict(output_typical_mw=totals['typical'], output_peak_mw=totals['peak'],
                input_typical_mw=ceil(input_power['typical']),
                input_peak_mw=ceil(input_power['peak']),
                input_design_mw=ceil(input_power['peak'] * Fraction(1000000 + budget['margin_ppm'], 1000000)))


def capacitor_inrush(capacitance_uf, voltage_mv, ramp_ms):
    if min(capacitance_uf, voltage_mv, ramp_ms) <= 0:
        raise ValueError('inrush inputs must be positive')
    current_ma = Fraction(capacitance_uf * voltage_mv, ramp_ms * 1000)
    return current_ma, current_ma * voltage_mv / 1000, Fraction(capacitance_uf * voltage_mv**2, 2 * 10**9)


def enabled_rails(rails, good, input_qualified):
    """External dependency policy; never an FPGA-controlled initial startup."""
    return {r['id'] for r in rails if input_qualified and set(r['depends_on']) <= good}


def validate_architecture(data):
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    require(data['schema_version'] == 1 and data['phase'] == '6E', 'schema/phase')
    require(data['units'] == dict(voltage='mV', current='mA', power='mW', time='cycles', capacitance='uF'), 'units')
    require(data['physical_implementation'] is False, 'physical qualification')
    for group in ('sources', 'contracts', 'loads', 'rails', 'faults', 'states'):
        ids = [item['id'] for item in data[group]]
        require(len(ids) == len(set(ids)) and len(ids) > 0, f'duplicate/empty {group}')
    sources = {x['id'] for x in data['sources']}
    for s in data['sources']:
        require(urlparse(s['url']).scheme == 'https' and bool(urlparse(s['url']).netloc), 'source URL')
        require(bool(s['title']) and s['reviewed'] == '2026-10-13' and s['status'] == 'REVIEWED' and bool(s['scope']) and bool(s['revision']) and bool(s['sections']), 'source metadata')
    for x in data['loads']:
        require(x['source'] in sources and x['status'] == 'ESTIMATED' and bool(x['basis']), 'estimate source')
        require(0 <= x['typical_mw'] <= x['peak_mw'] < 100000, 'load range')
    b = data['budget']
    for mode in ('typical', 'peak'):
        require(0 < b[f'efficiency_{mode}_ppm'] <= 1000000, 'efficiency')
        require(0 <= b[f'protection_{mode}_mw'] < 10000, 'protection loss')
    require(0 <= b['margin_ppm'] <= 1000000, 'margin')
    require(all(b[k] == v for k, v in power_budget(data['loads'], b).items()), 'power calculation')
    require(data['policy']['role'] == 'sink_only' and data['policy']['adc_telemetry'] is False, 'policy')
    require(data['policy']['source_voltage_factor_ppm'] == 950000 and data['policy']['cable_drop_mv'] == 500, 'derating policy')
    for c in data['contracts']:
        require(c['mv'] in (5000, 9000) and c['ma'] == 3000, 'contract range')
        require(c['nominal_mw'] == c['mv'] * c['ma'] // 1000, 'nominal power')
        require(c['derated_mw'] == available_power(c['mv'], c['ma']), 'derated power')
        require(c['full_operation'] == (c['derated_mw'] >= b['input_design_mw']), 'contract consistency')
        require(bool(c['requires']), 'contract prerequisite')
    require(data['policy']['full_operation_contract'] in {c['id'] for c in data['contracts'] if c['full_operation']}, 'selected contract')
    rail_map = {r['id']: r for r in data['rails']}
    for r in data['rails']:
        require(r['source'] in sources and r['status'] == 'PROVISIONAL', 'rail source')
        require(0 < r['nominal_mv'] <= 5000, 'rail voltage')
        for key in ('startup', 'enable', 'power_good', 'monitor', 'current_basis'):
            require(bool(r[key]), 'rail requirement')
        require((r['min_mv'] is None) == (r['max_mv'] is None), 'rail tolerance pair')
        if r['min_mv'] is not None:
            require(0 < r['min_mv'] <= r['nominal_mv'] <= r['max_mv'], 'rail tolerance')
        require((r['typical_ma'] is None) == (r['peak_ma'] is None), 'rail current pair')
        if r['typical_ma'] is not None:
            require(0 <= r['typical_ma'] <= r['peak_ma'] <= 10000, 'rail current')
        require(len(r['depends_on']) == len(set(r['depends_on'])) and set(r['depends_on']) <= rail_map.keys(), 'rail dependency')
    def visit(name, path):
        require(name not in path, 'cyclic dependency')
        for dependency in rail_map[name]['depends_on']:
            visit(dependency, path | {name})
    for name in rail_map:
        visit(name, set())
    require(data['states'] == [dict(id=s, value=i) for i, s in enumerate(STATES)], 'invalid states')
    require(data['faults'] == [dict(id=s, bit=i, source='external_hardware' if i < 10 else 'logical_observation') for i, s in enumerate(FAULTS)], 'fault definitions')
    require(all(0 < n < 2**31 for n in data['timeouts'].values()), 'timeout range')
    require(data['controller']['nvm_required'] and data['controller']['register_document'] in sources, 'controller qualification')
    require(data['validation_status']['physical'] == 'NOT_TESTED' and all(v in ('PENDING', 'PASS', 'NOT_TESTED') for v in data['validation_status'].values()), 'validation state')
    require(len(data['known_unknowns']) >= 5, 'unknowns')
    i = data['inrush']
    require(i['silicon_startup_peak_mw'] is None and i['status'] == 'ILLUSTRATIVE_NOT_A_LIMIT', 'inrush qualification')
    values = capacitor_inrush(i['switched_capacitance_uf'], i['voltage_mv'], i['ramp_ms'])
    require([float(v) for v in values] == [i[k] for k in ('capacitor_current_ma', 'input_power_mw', 'stored_energy_mj')], 'inrush arithmetic')


@dataclass
class PowerModel:
    pd_cycles: int = 12
    startup_cycles: int = 40
    recovery_cycles: int = 20
    stable_cycles: int = 3
    stale_cycles: int = 15
    counter_max: int = 255

    def __post_init__(self):
        self.reset()

    def reset(self):
        self.now = 0
        self.packet = 0
        self.last_packet = None
        self.state = 'POWER_OFF'
        self.entered = 0
        self.start = None
        self.stable_since = None
        self.previous_faults = self.sticky = 0
        self.fault_count = self.detach_count = self.recovery_count = 0
        self.attached = False

    def step(self, packet=0, valid=True, clear=False, reset=False):
        if reset:
            self.reset()
            return self.encode()
        self.now += 1
        if valid:
            self.packet, self.last_packet = packet, self.now
        p = self.packet
        attached = bool(p & 1)
        fresh = self.last_packet is not None and self.now - self.last_packet < self.stale_cycles
        sufficient = full_power(p)
        protected = p & 66 == 66
        rails = p & 0xf000 == 0xf000
        prerequisites = attached and sufficient and protected and rails and p & 896 == 896 and fresh
        faults = (p >> 16) & 1023
        conditions = {
            10: self.attached and not attached,
            11: attached and ((bool(p & 8) and not contract_valid(p)) or (self.state == 'SYSTEM_READY' and not sufficient)),
            12: attached and contract_valid(p) and not sufficient,
            13: self.state == 'CONTRACT_PENDING' and not sufficient and self.now - self.entered >= self.pd_cycles,
            14: self.start is not None and self.state in STATES[1:8] and self.now - self.start >= self.startup_cycles,
            16: attached and not fresh,
            17: bool(p & (63 << 26)),
        }
        if self.state == 'SYSTEM_READY':
            conditions.update({7: not protected or not rails, 18: not bool(p & 128),
                               19: not bool(p & 256), 20: not bool(p & 512)})
        for bit, condition in conditions.items():
            if condition:
                faults |= 1 << bit
        healthy = prerequisites and faults == 0
        if self.state in ('RAILS_STABLE', 'RECOVERY') and healthy:
            if self.stable_since is None:
                self.stable_since = self.now
        else:
            self.stable_since = None
        stable = self.stable_since is not None and self.now - self.stable_since + 1 >= self.stable_cycles
        if self.state == 'RECOVERY' and self.now - self.entered >= self.recovery_cycles and not (healthy and stable):
            faults |= 1 << 15
        self.sticky = (0 if clear else self.sticky) | faults
        if faults & ~self.previous_faults:
            self.fault_count = min(self.counter_max, self.fault_count + 1)
        self.previous_faults = faults
        if self.attached and not attached:
            self.detach_count = min(self.counter_max, self.detach_count + 1)
        target = self.state
        if not attached:
            target = 'SHUTDOWN' if self.attached else 'POWER_OFF'
        elif self.state == 'FAULT':
            if clear:
                target = 'RECOVERY'
        elif self.state == 'RECOVERY':
            if faults & (1 << 15):
                target = 'FAULT'
            elif healthy and stable:
                target = 'ATTACHED'
        elif faults:
            target = 'FAULT'
        else:
            # Ordered prerequisite milestones, independent of RTL case encoding.
            milestone = {'POWER_OFF': ('ATTACHED', True), 'SHUTDOWN': ('ATTACHED', True),
                'ATTACHED': ('CONTRACT_PENDING', True),
                'CONTRACT_PENDING': ('CONTRACT_VALID', sufficient),
                'CONTRACT_VALID': ('INPUT_PROTECTED', protected),
                'INPUT_PROTECTED': ('RAILS_STARTING', True),
                'RAILS_STARTING': ('RAILS_STABLE', rails),
                'RAILS_STABLE': ('FPGA_RELEASE', healthy and stable),
                'FPGA_RELEASE': ('SYSTEM_READY', healthy)}
            if self.state in milestone:
                destination, qualified = milestone[self.state]
                if qualified:
                    target = destination
            if self.state == 'RAILS_STABLE' and not (rails and protected):
                target = 'RAILS_STARTING'
            if self.state == 'FPGA_RELEASE' and not healthy:
                target = 'RAILS_STARTING'
        if target != self.state:
            if target == 'RECOVERY':
                self.recovery_count = min(self.counter_max, self.recovery_count + 1)
            self.entered = self.now
            self.stable_since = None
        if target in STATES[1:8] and self.state not in STATES[1:8]:
            self.start = self.now
        elif target not in STATES[1:8]:
            self.start = None
        self.state, self.attached = target, attached
        return self.encode()

    def encode(self):
        p = self.packet
        fresh = self.last_packet is not None and self.now - self.last_packet < self.stale_cycles
        ready = self.state == 'SYSTEM_READY' and fresh and full_power(p) and p & 0xf3c3 == 0xf3c3 and (p >> 16) & 65535 == 0
        mv, ma = (p >> 32) & 65535, p >> 48
        known = p & 9 == 9
        words = [int(bool(p & 1)), int(p & 13 == 13), mv if known else 0, ma if known else 0,
                 mv * ma // 1000 if known and mv in (5000, 9000) else 0,
                 int(p & 66 == 66), int(p & 0xf000 == 0xf000), STATES.index(self.state),
                 self.sticky, self.fault_count, self.detach_count, self.recovery_count, 7]
        encoded = sum(word << (32 * i) for i, word in enumerate(words))
        return encoded, int(ready), int(ready and bool(p & 1024)), int(ready and bool(p & 2048))


def packet(mv=9000, ma=3000, flags=0xffcf, faults=0):
    return (ma << 48) | (mv << 32) | (faults << 16) | flags


def architecture():
    return json.loads((Path(__file__).resolve().parents[1] / 'config/phase6e_power_architecture.json').read_text())
