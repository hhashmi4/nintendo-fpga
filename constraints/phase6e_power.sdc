# Logical controller/status port budgets, not physical USB-C specifications.
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
create_clock -name STATUS_CLK -period 40.000 [get_ports STATUS_CLK]
derive_clock_uncertainty
set_input_delay -clock STATUS_CLK -max 5.000 [get_ports {STATUS_VALID STATUS_DATA[*]}]
set_input_delay -clock STATUS_CLK -min 0.000 [get_ports {STATUS_VALID STATUS_DATA[*]}]
set_input_delay -clock CLOCK_50 -max 5.000 [get_ports FAULT_CLEAR]
set_input_delay -clock CLOCK_50 -min 0.000 [get_ports FAULT_CLEAR]
set_output_delay -clock STATUS_CLK -max 5.000 [get_ports STATUS_READY]
set_output_delay -clock STATUS_CLK -min 0.000 [get_ports STATUS_READY]
set observed_outputs [get_ports {STARTUP_STATE[*] SYSTEM_READY VIDEO_POWER_PERMIT AUDIO_POWER_PERMIT DOWNSTREAM_DISABLE_REQUEST DIAGNOSTICS[*]}]
set_output_delay -clock CLOCK_50 -max 5.000 $observed_outputs
set_output_delay -clock CLOCK_50 -min 0.000 $observed_outputs
# Only the asynchronous assertion source and metastability-catching stages.
set_false_path -from [get_ports RESET_N]
set first_stages [get_registers {*status_mailbox|request_sync[0] *status_mailbox|acknowledge_sync[0]}]
if {[get_collection_size $first_stages] != 2} {post_message -type error "Power CDC first stages missing"}
set_false_path -to $first_stages
# Held bundle gets four destination edges before capture. No blanket clock cut.
set held [get_registers {*status_mailbox|held_data[*]}]
set captured [get_registers {*status_mailbox|destination_data[*]}]
if {[get_collection_size $held] != 64 || [get_collection_size $captured] != 64} {post_message -type error "Power CDC payload bounds missing"}
set_max_delay 20.000 -from $held -to $captured
set_min_delay 0.000 -from $held -to $captured
