`timescale 1ns/1ps

module de1_soc_top (
    input  logic CLOCK_50,
    input  logic KEY0,
    output logic LEDR0,
    output logic LEDR1,
    output logic LEDR2
);
    logic sys_clk;
    logic reset;
    logic nes_master_ce;
    logic ppu_ce;
    logic cpu_ce;
    logic apu_ce;

    platform_core platform (
        .ref_clk     (CLOCK_50),
        .ext_reset_n (KEY0),
        .sys_clk     (sys_clk),
        .reset       (reset),
        .nes_master_ce (nes_master_ce),
        .ppu_ce      (ppu_ce),
        .cpu_ce      (cpu_ce),
        .apu_ce      (apu_ce)
    );

    platform_diagnostic diagnostic (
        .clk           (sys_clk),
        .reset         (reset),
        .nes_master_ce (nes_master_ce),
        .ppu_ce        (ppu_ce),
        .cpu_ce        (cpu_ce),
        .apu_ce        (apu_ce),
        .ppu_heartbeat (LEDR0),
        .cpu_heartbeat (LEDR2)
    );

    // KEY0 is active-low. LEDR1 is illuminated while internal reset is active.
    assign LEDR1 = reset;

    // Future NES logic will connect at the platform boundary, not in the
    // removable diagnostic block.
endmodule
