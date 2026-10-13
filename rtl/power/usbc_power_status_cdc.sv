`timescale 1ns/1ps

// One-entry held-data mailbox. Both domains MUST share the reset epoch.
// Producer holds valid/data until ready; it must latch short hardware events
// upstream. This mailbox transports reports, never electrical protection.
module usbc_power_status_cdc (
    input logic source_clk, destination_clk, reset_n,
    input logic source_valid,
    input logic [63:0] source_data,
    output logic source_ready,
    output logic destination_reset, destination_valid,
    output logic [63:0] destination_data
);
    logic source_reset;
    logic request_toggle, acknowledge_toggle;
    logic [63:0] held_data;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync, acknowledge_sync;
    reset_sync source_reset_sync(.clk(source_clk), .async_reset_n(reset_n),
                                 .reset(source_reset));
    reset_sync destination_reset_sync(.clk(destination_clk), .async_reset_n(reset_n),
                                      .reset(destination_reset));
    assign source_ready = !source_reset && request_toggle == acknowledge_sync[2];
    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            request_toggle <= 1'b0;
            acknowledge_sync <= '0;
            held_data <= '0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[1:0], acknowledge_toggle};
            if (source_valid && source_ready) begin
                held_data <= source_data;
                request_toggle <= !request_toggle;
            end
        end
    end
    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            request_sync <= '0;
            acknowledge_toggle <= 1'b0;
            destination_valid <= 1'b0;
            destination_data <= '0;
        end else begin
            request_sync <= {request_sync[1:0], request_toggle};
            destination_valid <= 1'b0;
            if (request_sync[2] != acknowledge_toggle) begin
                destination_data <= held_data;
                destination_valid <= 1'b1;
                acknowledge_toggle <= request_sync[2];
            end
        end
    end
endmodule
