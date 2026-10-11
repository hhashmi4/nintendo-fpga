package require ::quartus::project
package require ::quartus::sta

project_open phase6b_video
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path \
    -file ../build/quartus_phase6b_video/critical_setup_paths.txt
delete_timing_netlist
project_close
