from copy import deepcopy
from fractions import Fraction
import pytest
from verification.usbc_power import (PowerModel, STATES, architecture, available_power,
    capacitor_inrush, contract_valid, enabled_rails, full_power, packet, power_budget,
    select_contract, validate_architecture)


def test_architecture_and_budget():
    data = architecture()
    validate_architecture(data)
    assert power_budget(data['loads'], data['budget']) == dict(output_typical_mw=6900,
        output_peak_mw=12550, input_typical_mw=7817, input_peak_mw=15115, input_design_mw=18894)
    assert available_power(5000, 3000) == 12750 < 18894 < available_power(9000, 3000) == 24150
    # Phase 6A's rounded totals: 7.15W, 11.25W, and 14.0625W.
    assert sum((6000,1500,450,800,700,300,1500)) * Fraction(5,4) == Fraction(56250,4)


@pytest.mark.parametrize('offers,result', [([],None), ([(5000,1500)],None),
    ([(5000,3000)],(5000,3000)), ([(9000,2000)],None),
    ([(5000,3000),(9000,3000)],(9000,3000)), ([(20000,5000)],None)])
def test_contract_selection(offers,result):
    assert select_contract(offers) == result


@pytest.mark.parametrize('mv,ma,flags,valid,full', [
    (9000,3000,0xffcf,True,True),(5000,3000,0xffcf,True,False),
    (5000,3000,0xffdb,True,False),(5000,1500,0xffeb,True,False),
    (5000,3000,0xfffb,False,False),(5000,0,3,False,False),
    (9000,3000,0xffcb,False,False),(12000,3000,0xffcf,False,False),
    (9000,0,0xffcf,False,False),(9000,4000,0xffcf,False,False),
    (9000,2999,0xffcf,False,False),(9000,2000,0xffcf,True,False)])
def test_contract_rules(mv,ma,flags,valid,full):
    data=packet(mv,ma,flags)
    assert contract_valid(data) == valid
    assert full_power(data) == full


def test_inrush_is_separate_from_steady_state():
    assert capacitor_inrush(470,9000,20) == (Fraction(423,2), Fraction(3807,2), Fraction(3807,200))
    with pytest.raises(ValueError): capacitor_inrush(470,9000,0)
    with pytest.raises(ValueError): available_power(12000,3000)


@pytest.mark.parametrize('group,key,value', [
    ('units','voltage','V'),('budget','input_design_mw',14100),
    ('budget','efficiency_peak_ppm',0),('budget','margin_ppm',-1),
    ('policy','role','source'),('policy','adc_telemetry',True),
    ('policy','full_operation_contract','pd_5v3a'),
    ('validation_status','physical','PASS'),('validation_status','rtl','UNKNOWN'),
    ('timeouts','pd_cycles',0),('controller','nvm_required',False),
    ('inrush','silicon_startup_peak_mw',5000),('inrush','input_power_mw',1)])
def test_invalid_scalar_contract(group,key,value):
    data=deepcopy(architecture());data[group][key]=value
    with pytest.raises(ValueError): validate_architecture(data)


@pytest.mark.parametrize('group,key,value', [
    ('sources','url','http://unverified.example'),('sources','title',''),
    ('sources','reviewed',''),('contracts','mv',12000),('contracts','ma',5000),
    ('contracts','derated_mw',27000),('contracts','full_operation',False),
    ('loads','typical_mw',-1),('loads','peak_mw',0),('loads','source','missing'),
    ('rails','nominal_mv',0),('rails','min_mv',9999),('rails','peak_ma',0),
    ('rails','depends_on',['missing']),('rails','depends_on',['fpga_core']),
    ('states','value',15),('faults','bit',31)])
def test_invalid_list_contract(group,key,value):
    data=deepcopy(architecture());data[group][0][key]=value
    with pytest.raises(ValueError): validate_architecture(data)


@pytest.mark.parametrize('group',['sources','contracts','loads','rails','faults','states'])
def test_duplicate_identifiers(group):
    data=deepcopy(architecture());data[group].append(deepcopy(data[group][0]))
    with pytest.raises(ValueError): validate_architecture(data)


@pytest.mark.parametrize('field',['sources','contracts','rails','budget','states','faults','known_unknowns'])
def test_missing_required_fields(field):
    data=deepcopy(architecture());del data[field]
    with pytest.raises((KeyError,ValueError)): validate_architecture(data)


def test_external_rail_dependencies():
    rails=architecture()['rails']
    assert not enabled_rails(rails,set(),False)
    assert 'ddr_1v5' not in enabled_rails(rails,set(),True)
    assert 'ddr_1v5' in enabled_rails(rails,{'aux_2v5'},True)
    assert 'ddr_vtt' not in enabled_rails(rails,{'aux_2v5'},True)
    assert 'ddr_vtt' in enabled_rails(rails,{'aux_2v5','ddr_1v5'},True)


def run(model,value,count=16,**kwargs):
    for _ in range(count): result=model.step(value,**kwargs)
    return result


@pytest.mark.parametrize('fault_bit',range(10))
def test_active_fault_clear_cannot_enable(fault_bit):
    m=PowerModel();assert run(m,packet())[1]
    bad=packet(faults=1<<fault_bit)
    m.step(bad); assert m.state=='FAULT' and m.sticky & (1<<fault_bit)
    run(m,bad,25,clear=True)
    assert not m.encode()[1] and m.sticky & (1<<fault_bit)
    m.step(packet(),clear=True);run(m,packet(),40)
    # Depending on the explicit-clear edge, it may already be in recovery.
    assert m.state=='SYSTEM_READY'


def test_timeouts_stale_and_recovery():
    m=PowerModel();run(m,packet(flags=3),14)
    assert m.sticky & (1<<13)
    m.step(packet(),clear=True);assert run(m,packet(),20)[1]
    run(m,0,16,valid=False)
    assert m.sticky & (1<<16) and not m.encode()[1]
    m.step(packet(faults=1),clear=True);run(m,packet(faults=1),21)
    assert m.sticky & (1<<15)


def test_startup_timeout_and_reset():
    m=PowerModel();run(m,packet(flags=0x0fcf),42)
    assert m.sticky & (1<<14)
    m.step(reset=True)
    assert m.state=='POWER_OFF' and m.sticky==m.fault_count==0


def test_saturating_counts_and_reattach():
    m=PowerModel(counter_max=3)
    for _ in range(5):
        run(m,packet());m.step(0)
    assert m.detach_count==3 and m.fault_count==3
    assert run(m,packet())[1]


def test_no_false_ready_and_av_gating():
    m=PowerModel();run(m,packet(flags=0xf3cf))
    assert m.encode()[1:] == (1,0,0)
    m.step(packet(flags=0xf2cf))
    assert not m.encode()[1] and m.sticky & (1<<19)


def test_diagnostic_unavailable_and_simulated_provenance():
    from software.nes_debug.backend import OfflineDiagnosticBackend
    from software.nes_debug.client import DiagnosticClient
    from software.nes_debug import mmio_registers as r
    backend=OfflineDiagnosticBackend()
    client=DiagnosticClient(backend)
    status=client.interpreted_status(client.snapshot())['usbc_power']
    assert not status['available'] and status['negotiated_mv'] is None
    backend.words[r.REG_AVAILABILITY] |= r.AVAILABLE_USBC_POWER
    backend.words[r.REG_USBC_PROVENANCE]=7
    backend.words[r.REG_USBC_NEGOTIATED_MV]=9000
    status=client.interpreted_status(client.snapshot())['usbc_power']
    assert status['provenance']=='SIMULATED_CONFIGURED_ESTIMATED'
    assert status['negotiated_mv']==9000 and status['measured_voltage_mv'] is None


def test_contract_ready_at_pending_deadline():
    m=PowerModel()
    run(m,packet(flags=3),13)
    assert m.state=='CONTRACT_PENDING'
    m.step(packet())
    assert m.state=='CONTRACT_VALID' and not m.sticky


def test_status_refresh_at_watchdog_deadline():
    m=PowerModel();run(m,packet())
    run(m,0,14,valid=False)
    assert m.encode()[1]
    m.step(packet())
    assert m.encode()[1] and not m.sticky
