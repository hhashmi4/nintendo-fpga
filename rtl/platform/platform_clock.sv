`timescale 1ns/1ps

module platform_clock (
    input  logic ref_clk,
    output logic sys_clk,
    output logic locked
);
    // Phase 1 deliberately uses the board oscillator directly. A future PLL
    // can replace this implementation without changing platform_core.
    assign sys_clk = ref_clk;
    assign locked  = 1'b1;
endmodule
