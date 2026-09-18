# CLOCK_50 remains the only fabric clock in the Phase 2K image.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# KEY0 asserts the existing reset synchronizer asynchronously. SW0 enters a
# dedicated two-flop level synchronizer before selecting a clock-enable mode.
set_false_path -from [get_ports {KEY0 SW0}]

# Human-visible LEDs and seven-segment displays have no synchronous receiver.
set_false_path -to [get_ports {LEDR* HEX0* HEX1* HEX2* HEX3* HEX4* HEX5*}]

derive_clock_uncertainty
