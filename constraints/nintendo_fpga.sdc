# The DE1-SoC FPGA_CLK1_50 oscillator is the only Phase 1 fabric clock.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# KEY0 is asynchronous by construction. It asserts reset asynchronously into
# reset_sync; reset removal is synchronized before reaching platform logic.
set_false_path -from [get_ports {KEY0}]

# LEDs have no external synchronous receiver or interface timing requirement.
# Exclude these human-visible diagnostic paths explicitly rather than inventing
# an output-delay requirement.
set_false_path -to [get_ports {LEDR0 LEDR1 LEDR2}]

derive_clock_uncertainty
