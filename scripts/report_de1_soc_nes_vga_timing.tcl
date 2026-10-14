package require ::quartus::project
package require ::quartus::sta

project_open de1_soc_nes_vga
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path \
    -file ../build/quartus_de1_soc_nes_vga/critical_setup_paths.txt
# Explicit console pixel logic report, in addition to unconstrained/all-path gates.
set console_pixels [get_registers {*nes_console_renderer*rgb*}]
if {[get_collection_size $console_pixels] == 0} { error "Missing console RGB registers" }
report_timing -setup -to $console_pixels -npaths 20 -detail full_path \
    -file ../build/quartus_de1_soc_nes_vga/renderer_setup_paths.txt
set console_rows [get_registers {*nes_console_renderer*line_*}]
if {[get_collection_size $console_rows] > 0} {
    report_timing -setup -to $console_rows -npaths 20 -detail full_path \
        -file ../build/quartus_de1_soc_nes_vga/renderer_row_paths.txt
}
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
