`timescale 1ns/1ps

// 50 MHz board reference to the WM8731's exact 12 MHz USB-mode MCLK.  This
// integer-ratio PLL avoids the small frequency quantization error of the
// Terasic demonstration's nominal 18.432 MHz fractional clock.
module audio_pll (
    input  logic ref_clk,
    input  logic reset,
    output logic audio_clk,
    output logic locked
);
`ifdef ALTERA_SYNTHESIS
    wire [4:0] pll_clocks;

    altpll #(
        .bandwidth_type("AUTO"),
        .clk0_divide_by(25),
        .clk0_duty_cycle(50),
        .clk0_multiply_by(6),
        .clk0_phase_shift("0"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(20000),
        .intended_device_family("Cyclone V"),
        .operation_mode("NORMAL"),
        .pll_type("AUTO"),
        .port_areset("PORT_USED"),
        .port_inclk0("PORT_USED"),
        .port_locked("PORT_USED"),
        .width_clock(5)
    ) audio_clock_pll (
        .areset(reset),
        .inclk({1'b0, ref_clk}),
        .clk(pll_clocks),
        .locked(locked)
    );

    assign audio_clk = pll_clocks[0];
`else
    // Average-exact 50-to-12 MHz behavioral clock for integration simulation.
    // Its 40/60 ns half-period jitter is not a physical PLL model, but the
    // rational 24/50 half-edge schedule preserves the exact long-run rate.
    logic [5:0] divider_phase;
    logic simulated_audio_clk;
    logic [3:0] lock_counter;

    always_ff @(posedge ref_clk) begin
        if (reset) begin
            divider_phase <= '0;
            simulated_audio_clk <= 1'b0;
            lock_counter <= '0;
            locked <= 1'b0;
        end else begin
            if (({1'b0, divider_phase} + 7'd24) >= 7'd50) begin
                divider_phase <= 6'({1'b0, divider_phase} +
                                    7'd24 - 7'd50);
                simulated_audio_clk <= !simulated_audio_clk;
            end else begin
                divider_phase <= divider_phase + 6'd24;
            end
            if (!locked) begin
                lock_counter <= lock_counter + 1'b1;
                if (&lock_counter)
                    locked <= 1'b1;
            end
        end
    end

    assign audio_clk = simulated_audio_clk;
`endif
endmodule
