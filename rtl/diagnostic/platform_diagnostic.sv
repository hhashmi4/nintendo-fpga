`timescale 1ns/1ps

module platform_diagnostic (
    input  logic clk,
    input  logic reset,
    input  logic nes_master_ce,
    input  logic ppu_ce,
    input  logic cpu_ce,
    input  logic apu_ce,
    output logic ppu_heartbeat,
    output logic cpu_heartbeat
);
    // This block is intentionally outside the future NES system boundary.
    // Its counters advance only on the generated clock enables.
    logic [21:0] ppu_counter = '0;
    logic [19:0] cpu_counter = '0;

    always_ff @(posedge clk) begin
        if (reset) begin
            ppu_counter <= '0;
            cpu_counter <= '0;
        end else begin
            if (nes_master_ce && ppu_ce) begin
                ppu_counter <= ppu_counter + 1'b1;
            end
            if (cpu_ce && apu_ce) begin
                cpu_counter <= cpu_counter + 1'b1;
            end
        end
    end

    assign ppu_heartbeat = ppu_counter[21];
    assign cpu_heartbeat = cpu_counter[19];
endmodule
