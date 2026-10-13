"""Phase 6F feasibility arithmetic and normalized policy, never a PD/DP PHY.

Events represent reports from a future qualified controller. No wire messages,
AUX transactions, training patterns, hardware access or real-time guarantees.
"""
from dataclasses import dataclass
from fractions import Fraction
from math import ceil
from datetime import date
from pathlib import Path
from urllib.parse import urlparse
import json

from verification.usbc_power import available_power


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError("expected integer in range")
    return value


@dataclass(frozen=True)
class Mode:
    width: int
    height: int
    total_width: int
    total_height: int
    pixel_clock_hz: int
    bits_per_pixel: int = 24

    def __post_init__(self):
        for value in self.__dict__.values():
            integer(value, 1)
        if self.width > self.total_width or self.height > self.total_height:
            raise ValueError("active raster exceeds total")

    @property
    def refresh_hz(self):
        return Fraction(self.pixel_clock_hz, self.total_width * self.total_height)

    @property
    def active_pixels_s(self):
        return self.width * self.height * self.refresh_hz

    @property
    def raster_bits_s(self):
        return self.pixel_clock_hz * self.bits_per_pixel

    @property
    def blanking_fraction(self):
        return 1 - Fraction(self.width * self.height, self.total_width * self.total_height)


def lane_capacity(lanes, rate_mbps):
    """RBR/HBR/HBR2/HBR3 only; capacity after 8b/10b, before packet overhead."""
    integer(lanes, 1)
    integer(rate_mbps, 1)
    if lanes not in (1, 2, 4) or rate_mbps not in (1620, 2700, 5400, 8100):
        raise ValueError("unsupported lane count/link rate")
    return lanes * rate_mbps * 1_000_000 * 8 // 10


def bandwidth_requirement(mode, reserve_ppm=30000, audio_bits_s=1536000):
    """Conservative raster-clock screen, NOT an exact DP transport scheduler.

    3% is a project screening reserve, not a VESA requirement. DP does not
    transmit blank pixels as RGB; raster budgeting screens peak delivery.
    """
    integer(reserve_ppm)
    integer(audio_bits_s)
    if reserve_ppm >= 1_000_000:
        raise ValueError("invalid reserve")
    return ceil(Fraction((mode.raster_bits_s + audio_bits_s) * 1_000_000,
                         1_000_000 - reserve_ppm))


@dataclass(frozen=True)
class Capability:
    modes: frozenset[str]
    max_pixel_clock_hz: int
    lanes: int
    rate_mbps: int
    audio: bool = False

    def __post_init__(self):
        integer(self.max_pixel_clock_hz, 1)
        lane_capacity(self.lanes, self.rate_mbps)
        if not isinstance(self.modes, frozenset) or not all(isinstance(x, str) for x in self.modes):
            raise ValueError("mode set")
        if type(self.audio) is not bool:
            raise ValueError("audio capability")


def mode_feasibility(name, modes, source, sink, cable, hardware_supported=False):
    if name not in modes:
        return "INVALID_MODE"
    if not hardware_supported:
        return "UNSUPPORTED_HARDWARE"
    if any(x is None for x in (source, sink, cable)):
        return "MISSING_CAPABILITY"
    mode = modes[name]
    if any(name not in x.modes or mode.pixel_clock_hz > x.max_pixel_clock_hz
           for x in (source, sink)):
        return "UNSUPPORTED_MODE"
    # Cable tuple is the independently qualified (lane count, link rate).
    lane_capacity(*cable)
    capacity = lane_capacity(min(source.lanes, sink.lanes, cable[0]),
                             min(source.rate_mbps, sink.rate_mbps, cable[1]))
    return "BANDWIDTH_SCREEN_PASS" if bandwidth_requirement(mode) <= capacity else "INSUFFICIENT_BANDWIDTH"


def compare_power(incremental_input_mw, mv=9000, ma=3000, baseline_mw=18894):
    """Increment includes losses/margin, VCONN and any display power at INPUT.

    None propagates unknown data; typical chip power must not be passed as a
    complete worst-case increment. This does not change Phase 6E contract policy.
    """
    integer(baseline_mw)
    capacity = available_power(mv, ma)
    if incremental_input_mw is None:
        return dict(status="UNKNOWN", required_mw=None, headroom_mw=None)
    integer(incremental_input_mw)
    required = baseline_mw + incremental_input_mw
    return dict(status="SUFFICIENT" if required <= capacity else "INSUFFICIENT",
                required_mw=required, headroom_mw=capacity - required)


STAGES = ("DETACHED", "ATTACHED", "PD_READY", "IDENTIFIED", "SVID_FOUND",
          "MODES_FOUND", "ENTERED", "STATUS_VALID", "CONFIGURED", "READY")
ADVANCE = dict(zip(("attach", "pd_ready", "identity", "svid", "modes",
                    "enter", "status", "configure", "link_ready"), STAGES[1:]))
FAULT_EVENTS = {"timeout", "reject", "link_loss", "power_loss", "stale_status"}


@dataclass
class AltModePolicy:
    """Abstract policy simulation. Every report carries MODEL_ONLY provenance.

    simulation_hardware=True injects hypothetical qualified capabilities for
    tests. It NEVER makes a claim about the production build or attached board.
    A new cable/reset epoch invalidates all old capabilities and link results.
    """
    simulation_hardware: bool = False
    state: str = "DETACHED"
    hpd: bool = False
    lanes: int = 0
    rate_mbps: int = 0
    fault: str = "NONE"
    epoch: int = 0
    mode_valid: bool = False
    attached: bool = False

    def _invalidate(self):
        self.hpd = False
        self.lanes = self.rate_mbps = 0
        self.mode_valid = False

    def event(self, event, *, epoch=None, lanes=0, rate_mbps=0, mode_valid=False):
        if event in ("reset", "detach"):
            self._invalidate()
            self.state = "DETACHED"
            self.attached = False
            self.epoch += 1
            if event == "reset":
                self.fault = "NONE"
            return
        if not self.simulation_hardware:
            self.state = "DETACHED"
            self.attached = False
            self._invalidate()
            self.fault = "UNSUPPORTED_HARDWARE"
            return
        if epoch != self.epoch:
            # Late completion from an old attachment cannot enable an output.
            return
        if event == "clear":
            # Explicit recovery always restarts discovery, never resumes READY.
            self._invalidate()
            self.state = "DETACHED"
            self.attached = False
            self.fault = "NONE"
            self.epoch += 1
            return
        if event in FAULT_EVENTS:
            self._invalidate()
            self.state = "FAULT"
            self.fault = event.upper()
            return
        if self.state == "FAULT":
            return
        if event in ("hpd_low", "hpd_high", "hpd_irq", "mode_change"):
            if self.state not in ("CONFIGURED", "READY"):
                self.fault = "INVALID_ORDER"
                self.state = "FAULT"
                self._invalidate()
                return
            if event == "hpd_high":
                self.hpd = True
            else:
                if event == "hpd_low":
                    self.hpd = False
                self.state = "CONFIGURED"
                self.mode_valid = False
                self.lanes = self.rate_mbps = 0
                self.epoch += 1
            return
        expected = STAGES.index(self.state) if self.state in STAGES else -1
        if event not in ADVANCE or expected < 0 or expected + 1 >= len(STAGES) or ADVANCE[event] != STAGES[expected + 1]:
            self.fault = "INVALID_ORDER"
            self.state = "FAULT"
            self._invalidate()
            return
        if event == "link_ready":
            try:
                lane_capacity(lanes, rate_mbps)
            except ValueError:
                self.fault = "INVALID_LINK"
                self.state = "FAULT"
                self._invalidate()
                return
            if not self.hpd or mode_valid is not True:
                self.fault = "UNQUALIFIED_MODE"
                self.state = "FAULT"
                self._invalidate()
                return
            self.lanes, self.rate_mbps, self.mode_valid = lanes, rate_mbps, True
        self.state = ADVANCE[event]
        if event == "attach":
            self.attached = True

    @property
    def ready(self):
        return self.simulation_hardware and self.state == "READY" and self.hpd and self.mode_valid

    def diagnostics(self):
        return dict(provenance="MODEL_ONLY", schema_version=1,
                    USBC_VIDEO_SUPPORTED=self.simulation_hardware,
                    USBC_VIDEO_AVAILABLE=self.simulation_hardware,
                    USBC_VIDEO_CONNECTED=self.simulation_hardware and self.attached,
                    USBC_ALT_MODE_ACTIVE=self.state in ("ENTERED", "STATUS_VALID", "CONFIGURED", "READY"),
                    USBC_DP_LINK_READY=self.ready,
                    USBC_DP_LANE_COUNT=self.lanes if self.ready else 0,
                    USBC_DP_LINK_RATE=self.rate_mbps if self.ready else 0,
                    USBC_VIDEO_FAULT=self.fault,
                    USBC_VIDEO_QUALIFICATION="SIMULATED" if self.simulation_hardware else "UNSUPPORTED")


@dataclass
class OutputSelection:
    selected: str = "NONE"
    audio: str = "MUTE"

    def update(self, request, *, hdmi_ready=False, dp_ready=False, vga_ready=False,
               hdmi_audio=False, dp_audio=False, muted=False, frame_boundary=False):
        if request not in ("AUTO", "HDMI", "USBC_DP", "VGA", "NONE"):
            raise ValueError("invalid output request")
        ready = {"HDMI": hdmi_ready, "USBC_DP": dp_ready, "VGA": vga_ready, "NONE": False}
        # Loss disables immediately; enabling or switching waits for a boundary.
        if not ready[self.selected] or request == "NONE":
            self.selected = "NONE"
        order = ["HDMI", "USBC_DP", "VGA"]
        if request in order:
            order = [request] + [x for x in order if x != request]
        target = next((x for x in order if ready[x]), "NONE") if request != "NONE" else "NONE"
        if frame_boundary:
            self.selected = target
        audio_ready = {"HDMI": hdmi_audio, "USBC_DP": dp_audio, "VGA": False, "NONE": False}
        self.audio = self.selected if audio_ready[self.selected] and not muted else "MUTE"
        return self.selected, self.audio


QUALIFICATIONS = {"VERIFIED", "PROVISIONAL", "DOCUMENTATION RESTRICTED", "UNAVAILABLE", "REJECTED"}
DIAGNOSTIC_FIELDS = {
    "USBC_VIDEO_SUPPORTED", "USBC_VIDEO_AVAILABLE", "USBC_VIDEO_CONNECTED",
    "USBC_ALT_MODE_ACTIVE", "USBC_DP_LINK_READY", "USBC_DP_LANE_COUNT",
    "USBC_DP_LINK_RATE", "USBC_VIDEO_FAULT", "USBC_VIDEO_QUALIFICATION",
}


def _validate_architecture(data):
    """Version-1 executable schema and semantic checks, as in Phase 6E.

    Reject missing/unknown fields, stale arithmetic, dangling evidence, promoted
    assumptions and fictitious production capability. No external dependencies.
    """
    def require(ok, message):
        if not ok:
            raise ValueError(message)

    def keys(obj, names):
        require(isinstance(obj, dict) and set(obj) == set(names.split()), "schema fields")

    keys(data, "schema_version phase physical_implementation decision primary_output sources components architectures modes units fpga bandwidth power connector_policy diagnostics decision_criteria unresolved")
    require(type(data['schema_version']) is int and data['schema_version'] == 1 and data['phase'] == '6F', 'schema version')
    require(data['physical_implementation'] is False and data['decision'] == 'DEFER' and data['primary_output'] == 'HDMI', 'qualification boundary')
    require(data['units'] == dict(pixel_clock='Hz', bandwidth='bit/s', link_rate='Mbit/s per lane', power='mW', cost='USD', time='s'), 'units')
    for group in ('sources', 'components', 'architectures', 'modes'):
        require(isinstance(data[group], list) and bool(data[group]), 'empty group')
        ids = [x['id'] for x in data[group]]
        require(len(set(ids)) == len(ids), 'duplicate ID')
    sources = {x['id'] for x in data['sources']}
    for s in data['sources']:
        keys(s, 'id title revision locator url access reviewed')
        require(all(isinstance(v, str) and v.strip() for v in s.values()), 'source metadata')
        u = urlparse(s['url'])
        require(u.scheme == 'https' and u.hostname is not None and u.username is None, 'source URL')
        require(s['access'] in ('REVIEWED_PUBLIC', 'PUBLICATION_ONLY', 'RESTRICTED_SPECIFICATION'), 'source access')
        require(date.fromisoformat(s['reviewed']) == date(2026, 10, 13), 'source review date')
    def refs(items):
        require(isinstance(items, list) and bool(items) and set(items) <= sources, 'source reference')
    for c in data['components']:
        keys(c, 'id manufacturer part_number function inputs outputs video_limit audio power control package reference_clock qualification sources availability cost_usd cost_basis unresolved')
        require(c['qualification'] in QUALIFICATIONS, 'qualification enum')
        require(c['qualification'] != 'VERIFIED', 'unqualified component chain')
        refs(c['sources'])
        require(c['cost_usd'] is None and bool(c['cost_basis']), 'unquoted component cost')
        for k in ('manufacturer', 'part_number', 'function', 'video_limit', 'audio', 'power', 'control', 'package', 'reference_clock', 'availability'):
            require(isinstance(c[k], str) and bool(c[k].strip()), 'component metadata')
        for k in ('inputs', 'outputs', 'unresolved'):
            require(isinstance(c[k], list) and bool(c[k]) and all(isinstance(v, str) and v for v in c[k]), 'component interface/gaps')
    component_ids = {c['id'] for c in data['components']}
    require({a['id'] for a in data['architectures']} == set('ABCDE'), 'architecture coverage')
    for a in data['architectures']:
        keys(a, 'id name decision qualification required_components interfaces incremental_input_peak_mw incremental_bom_usd cost_basis risk risks')
        require(a['decision'] in ('GO', 'CONDITIONAL GO', 'NO-GO', 'DEFER') and a['qualification'] in QUALIFICATIONS, 'architecture decision')
        require(set(a['required_components']) <= component_ids, 'component reference')
        require(a['risk'] in ('LOW', 'MEDIUM', 'HIGH') and bool(a['risks']) and bool(a['interfaces']), 'risk/interfaces')
        for key in ('incremental_input_peak_mw', 'incremental_bom_usd'):
            require(a[key] is None if a['id'] in 'BCD' else type(a[key]) is int and a[key] == 0, 'unknown architecture budget')
    require({m['id'] for m in data['modes']} == {'720p60', '1080p60', '1200p60rb', '2160p30', '2160p60'}, 'mode coverage')
    for m in data['modes']:
        keys(m, 'id width height total_width total_height pixel_clock_hz bits_per_pixel timing source implemented_scanout raster_bits_s active_pixels_s blanking_fraction')
        refs([m['source']])
        mode = Mode(**{k: m[k] for k in Mode.__dataclass_fields__})
        require(m['raster_bits_s'] == mode.raster_bits_s, 'raster bandwidth')
        require(abs(m['active_pixels_s'] - float(mode.active_pixels_s)) < 0.001, 'active bandwidth')
        require(abs(m['blanking_fraction'] - float(mode.blanking_fraction)) < 1e-12, 'blanking arithmetic')
        require(m['implemented_scanout'] is (m['id'] == '720p60'), 'implemented modes')
    f = data['fpga']
    keys(f, 'production_candidate existing_quartus_device hssi_lanes native_dp sources')
    refs(f['sources'])
    require(f['production_candidate'] == '5CSEMA5F31C6N' and f['existing_quartus_device'] == '5CSEMA5F31C6' and type(f['hssi_lanes']) is int and f['hssi_lanes'] == 0 and f['native_dp'] is False, 'FPGA capability')
    b = data['bandwidth']
    keys(b, 'encoding efficiency_num efficiency_den screening_reserve_ppm reserve_status audio_payload_bits_s i2s_wire_bits_s lane_rates_mbps nes_source')
    require((b['encoding'], b['efficiency_num'], b['efficiency_den']) == ('8b10b', 8, 10), 'encoding')
    require(b['screening_reserve_ppm'] == 30000 and b['reserve_status'] == 'PROJECT_ASSUMPTION_NOT_PROTOCOL_REQUIREMENT', 'reserve')
    require(b['audio_payload_bits_s'] == 48000*2*16 and b['i2s_wire_bits_s'] == 48000*2*32, 'audio arithmetic')
    require(b['lane_rates_mbps'] == [1620, 2700, 5400, 8100], 'lane rates')
    require(b['nes_source'] == dict(width=256, height=240, ppu_clock_hz_num=59062500, ppu_clock_hz_den=11, dots_per_line=341, lines_per_frame=262, odd_rendered_frame_dots_skipped=1, status='INTERNAL_INDEXED_STREAM_NOT_DISPLAY_MODE'), 'NES source contract')
    p = data['power']
    keys(p, 'baseline_input_design_mw preferred_mv preferred_ma derated_capacity_mw remaining_mw status complete_dp_increment_mw complete_dp_budget_mw known_component_points')
    require(p['baseline_input_design_mw'] == 18894 and (p['preferred_mv'], p['preferred_ma']) == (9000, 3000), 'Phase 6E baseline')
    require(p['derated_capacity_mw'] == available_power(9000, 3000) and p['remaining_mw'] == p['derated_capacity_mw'] - 18894, 'power arithmetic')
    require(p['complete_dp_increment_mw'] is None and p['complete_dp_budget_mw'] is None and p['status'] == 'ESTIMATED_PHASE6E', 'unknown power')
    require(len(p['known_component_points']) == 4, 'power point coverage')
    expected = {'hdmi_dp': 1000, 'rgb_dp': 210, 'mux': 1.98, 'pd': 125}
    require({x['component']: x['mw'] for x in p['known_component_points']} == expected, 'component power points')
    for x in p['known_component_points']:
        keys(x, 'component mw basis')
        require(bool(x['basis']), 'power basis')
    require(data['connector_policy'] == dict(selected_option=3, power_inlet='UNCHANGED_PHASE6E_SINK_ONLY', future_video_option=1, combined_port='DEFER_REQUIRES_NEW_POWER_POLICY', monitor_power_guaranteed=False), 'connector policy')
    d = data['diagnostics']
    keys(d, 'schema_version storage existing_mmio_version fields')
    require(d['schema_version'] == 1 and d['storage'] == 'MODEL_ONLY_NO_MMIO_ALLOCATION' and d['existing_mmio_version'] == '1.3', 'diagnostic schema')
    require(set(d['fields']) == DIAGNOSTIC_FIELDS and all(d['fields'].values()), 'diagnostic fields')
    for k in ('decision_criteria', 'unresolved'):
        require(isinstance(data[k], list) and bool(data[k]) and all(isinstance(x, str) and x for x in data[k]), 'decision metadata')


def validate_architecture(data):
    """Validate schema v1, raising ValueError for malformed structure or content."""
    try:
        _validate_architecture(data)
    except (KeyError, TypeError, AttributeError, OverflowError) as exc:
        raise ValueError('malformed architecture schema') from exc


def load_architecture():
    path = Path(__file__).resolve().parents[1] / 'config/phase6f_usbc_video.json'
    data = json.loads(path.read_text())
    validate_architecture(data)
    return data


if __name__ == '__main__':
    architecture = load_architecture()
    print('Phase 6F schema validated; decision=DEFER; physical USB-C video=NOT TESTED')
