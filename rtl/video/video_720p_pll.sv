`timescale 1ns/1ps

// 50.000 MHz -> 74.250 MHz clock source for CTA-861 720p60. Detailed video
// simulations drive the scan pipeline directly; the non-Altera model only
// supplies a deterministic clock and lock indication for top-level lint/smoke
// tests.
module video_720p_pll (
    input  logic ref_clk,
    input  logic reset_n,
    output logic pixel_clk,
    output logic locked
);
`ifdef ALTERA_SYNTHESIS
    wire [4:0] pll_clocks;

    altpll #(
        .bandwidth_type("AUTO"),
        .clk0_divide_by(200),
        .clk0_duty_cycle(50),
        .clk0_multiply_by(297),
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
    ) pixel_clock_720p_pll (
        .areset(!reset_n),
        .inclk({1'b0, ref_clk}),
        .clk(pll_clocks),
        .locked(locked)
    );

    assign pixel_clk = pll_clocks[0];
`else
    logic divider;
    logic [3:0] lock_count;

    always_ff @(posedge ref_clk or negedge reset_n) begin
        if (!reset_n) begin
            divider <= 1'b0;
            lock_count <= 4'd0;
            locked <= 1'b0;
        end else begin
            divider <= !divider;
            if (!locked) begin
                lock_count <= lock_count + 4'd1;
                if (&lock_count)
                    locked <= 1'b1;
            end
        end
    end

    assign pixel_clk = divider;
`endif
endmodule
