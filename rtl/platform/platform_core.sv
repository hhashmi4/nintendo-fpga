`timescale 1ns/1ps

module platform_core (
    input  logic ref_clk,
    input  logic ext_reset_n,
    output logic sys_clk,
    output logic reset,
    output logic nes_master_ce,
    output logic ppu_ce,
    output logic cpu_ce,
    output logic apu_ce
);
    logic clock_locked;
    logic reset_request_n;

    platform_clock clock_source (
        .ref_clk (ref_clk),
        .sys_clk (sys_clk),
        .locked  (clock_locked)
    );

    assign reset_request_n = ext_reset_n && clock_locked;

    reset_sync reset_generator (
        .clk           (sys_clk),
        .async_reset_n (reset_request_n),
        .reset         (reset)
    );

    nes_timing_gen timing_generator (
        .clk    (sys_clk),
        .reset  (reset),
        .nes_master_ce (nes_master_ce),
        .ppu_ce (ppu_ce),
        .cpu_ce (cpu_ce),
        .apu_ce (apu_ce)
    );
endmodule
