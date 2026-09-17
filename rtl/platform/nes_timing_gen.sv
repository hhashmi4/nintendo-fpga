`timescale 1ns/1ps

module nes_timing_gen (
    input  logic clk,
    input  logic reset,
    output logic nes_master_ce = 1'b0,
    output logic ppu_ce = 1'b0,
    output logic cpu_ce = 1'b0,
    output logic apu_ce = 1'b0
);
    import platform_config_pkg::*;

    localparam int unsigned ACCUMULATOR_WIDTH = $clog2(MASTER_CE_DENOMINATOR);
    localparam int unsigned PPU_PHASE_WIDTH = $clog2(NTSC_PPU_MASTER_DIVISOR);
    localparam int unsigned CPU_PHASE_WIDTH = $clog2(
        NTSC_PPU_MASTER_DIVISOR * PPU_TICKS_PER_CPU_TICK
    );

    logic [ACCUMULATOR_WIDTH-1:0] master_accumulator = '0;
    logic [PPU_PHASE_WIDTH-1:0] ppu_master_phase = '0;
    logic [CPU_PHASE_WIDTH-1:0] cpu_master_phase = '0;
    logic [ACCUMULATOR_WIDTH:0] accumulator_sum;
    logic [ACCUMULATOR_WIDTH-1:0] accumulator_remainder;

    assign accumulator_sum =
        {1'b0, master_accumulator} +
        (ACCUMULATOR_WIDTH + 1)'(MASTER_CE_NUMERATOR);
    assign accumulator_remainder =
        accumulator_sum[ACCUMULATOR_WIDTH-1:0] -
        ACCUMULATOR_WIDTH'(MASTER_CE_DENOMINATOR);

    always_ff @(posedge clk) begin
        if (reset) begin
            master_accumulator <= '0;
            ppu_master_phase   <= '0;
            cpu_master_phase   <= '0;
            nes_master_ce      <= 1'b0;
            ppu_ce             <= 1'b0;
            cpu_ce             <= 1'b0;
            apu_ce             <= 1'b0;
        end else begin
            nes_master_ce <= 1'b0;
            ppu_ce <= 1'b0;
            cpu_ce <= 1'b0;
            apu_ce <= 1'b0;

            if (accumulator_sum >=
                (ACCUMULATOR_WIDTH + 1)'(MASTER_CE_DENOMINATOR)) begin
                master_accumulator <= accumulator_remainder;
                nes_master_ce      <= 1'b1;

                if (ppu_master_phase ==
                    PPU_PHASE_WIDTH'(NTSC_PPU_MASTER_DIVISOR - 1)) begin
                    ppu_master_phase <= '0;
                    ppu_ce           <= 1'b1;
                end else begin
                    ppu_master_phase <= ppu_master_phase + 1'b1;
                end

                if (cpu_master_phase ==
                    CPU_PHASE_WIDTH'(
                        NTSC_PPU_MASTER_DIVISOR * PPU_TICKS_PER_CPU_TICK - 1
                    )) begin
                    cpu_master_phase <= '0;
                    cpu_ce           <= 1'b1;
                    apu_ce           <= 1'b1;
                end else begin
                    cpu_master_phase <= cpu_master_phase + 1'b1;
                end
            end else begin
                master_accumulator <=
                    accumulator_sum[ACCUMULATOR_WIDTH-1:0];
            end
        end
    end
endmodule
