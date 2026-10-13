package require ::quartus::project
package require ::quartus::sta

project_open phase6e_power
create_timing_netlist
read_sdc
set corner 0
foreach_in_collection conditions [get_available_operating_conditions] {
    set_operating_conditions $conditions
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path \
        -file ../build/quartus_phase6e_power/critical_setup_corner${corner}.txt
    report_timing -hold -npaths 20 -detail full_path \
        -file ../build/quartus_phase6e_power/critical_hold_corner${corner}.txt
    incr corner
}
delete_timing_netlist
project_close
