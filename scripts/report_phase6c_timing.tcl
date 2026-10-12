package require ::quartus::project
package require ::quartus::sta

project_open phase6c_hdmi
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path \
    -file ../build/quartus_phase6c_hdmi/critical_setup_paths.txt
report_timing -hold -npaths 20 -detail full_path \
    -file ../build/quartus_phase6c_hdmi/critical_hold_paths.txt
delete_timing_netlist
project_close
