package require ::quartus::project
package require ::quartus::sta

project_open phase6d_hdmi_audio
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path \
    -file ../build/quartus_phase6d_hdmi_audio/critical_setup_paths.txt
# Explicit console pixel logic report, in addition to unconstrained/all-path gates.
set console_pixels [get_registers {*nes_console_renderer*rgb*}]
if {[get_collection_size $console_pixels] == 0} { error "Missing console RGB registers" }
report_timing -setup -to $console_pixels -npaths 20 -detail full_path \
    -file ../build/quartus_phase6d_hdmi_audio/renderer_setup_paths.txt
set console_rows [get_registers {*nes_console_renderer*line_*}]
if {[get_collection_size $console_rows] > 0} {
    report_timing -setup -to $console_rows -npaths 20 -detail full_path \
        -file ../build/quartus_phase6d_hdmi_audio/renderer_row_paths.txt
}
report_timing -hold -npaths 20 -detail full_path \
    -file ../build/quartus_phase6d_hdmi_audio/critical_hold_paths.txt
set_operating_conditions -model fast -temperature 0 -voltage 1100
update_timing_netlist
report_timing -hold -npaths 20 -detail full_path \
    -file ../build/quartus_phase6d_hdmi_audio/critical_fast_hold_paths.txt
delete_timing_netlist
project_close
