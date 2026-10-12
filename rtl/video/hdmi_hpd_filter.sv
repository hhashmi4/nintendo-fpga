`timescale 1ns/1ps

// Synchronize and qualify both HPD edges.  The candidate value must remain
// unchanged for STABLE_CYCLES before the public level changes; short bounces
// are visible only in hpd_state and cannot restart the transmitter.
module hdmi_hpd_filter #(
    parameter integer STABLE_CYCLES = 250_000
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       hpd_async,
    output logic       hpd_stable,
    output logic [1:0] hpd_state,
    output logic       connected_pulse,
    output logic       disconnected_pulse
);
    localparam integer COUNTER_WIDTH =
        STABLE_CYCLES <= 1 ? 1 : $clog2(STABLE_CYCLES);

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] hpd_sync;
    logic [COUNTER_WIDTH-1:0] stable_counter;

    always_comb begin
        if (hpd_sync[1] == hpd_stable)
            hpd_state = hpd_stable ? 2'd2 : 2'd0;
        else
            hpd_state = hpd_sync[1] ? 2'd1 : 2'd3;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            hpd_sync <= 2'b00;
            hpd_stable <= 1'b0;
            stable_counter <= '0;
            connected_pulse <= 1'b0;
            disconnected_pulse <= 1'b0;
        end else begin
            hpd_sync <= {hpd_sync[0], hpd_async};
            connected_pulse <= 1'b0;
            disconnected_pulse <= 1'b0;
            if (hpd_sync[1] == hpd_stable) begin
                stable_counter <= '0;
            end else if (STABLE_CYCLES <= 1 ||
                         stable_counter ==
                         COUNTER_WIDTH'(STABLE_CYCLES - 1)) begin
                hpd_stable <= hpd_sync[1];
                stable_counter <= '0;
                connected_pulse <= hpd_sync[1];
                disconnected_pulse <= !hpd_sync[1];
            end else begin
                stable_counter <= stable_counter + 1'b1;
            end
        end
    end
endmodule
