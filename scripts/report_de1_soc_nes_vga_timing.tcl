package require ::quartus::project
package require ::quartus::sta

project_open de1_soc_nes_vga
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path \
    -file ../build/quartus_de1_soc_nes_vga/critical_setup_paths.txt
report_timing -hold -npaths 20 -detail full_path \
    -file ../build/quartus_de1_soc_nes_vga/critical_hold_paths.txt
# Keep the original slow-corner report and also identify the worst fast-corner
# hold endpoints reported by the all-corners summary.
set_operating_conditions -model fast -temperature 0 -voltage 1100
update_timing_netlist
report_timing -hold -npaths 20 -detail full_path \
    -file ../build/quartus_de1_soc_nes_vga/critical_fast_hold_paths.txt
delete_timing_netlist
project_close
