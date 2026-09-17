`timescale 1ns/1ps

package platform_config_pkg;
    // DE1-SoC oscillator used by the FPGA fabric.
    localparam int unsigned BOARD_CLOCK_HZ = 50_000_000;

    // Provisional NTSC timing target: 945/44 MHz master timing, with the
    // PPU and CPU/APU rates at master/4 and master/12 respectively.
    // These values centralize the Phase 1 timing model; they are not a claim
    // that the 50 MHz clock reproduces the original console edge placement.
    localparam int unsigned NTSC_MASTER_HZ_NUMERATOR   = 945_000_000;
    localparam int unsigned NTSC_MASTER_HZ_DENOMINATOR = 44;
    localparam int unsigned NTSC_PPU_MASTER_DIVISOR    = 4;
    localparam int unsigned NTSC_CPU_MASTER_DIVISOR    = 12;

    // Reduced ratio of nominal NES master ticks to 50 MHz FPGA clock cycles:
    // (945_000_000 / 44) / 50_000_000 = 189 / 440. The common reduction
    // factor keeps the derived integers small for hardware.
    localparam int unsigned TIMING_REDUCTION_HZ = 5_000_000;
    localparam int unsigned MASTER_CE_NUMERATOR =
        NTSC_MASTER_HZ_NUMERATOR / TIMING_REDUCTION_HZ;
    localparam int unsigned MASTER_CE_DENOMINATOR =
        NTSC_MASTER_HZ_DENOMINATOR *
        (BOARD_CLOCK_HZ / TIMING_REDUCTION_HZ);

    localparam int unsigned PPU_TICKS_PER_CPU_TICK =
        NTSC_CPU_MASTER_DIVISOR / NTSC_PPU_MASTER_DIVISOR;
endpackage
