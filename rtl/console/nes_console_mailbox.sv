`timescale 1ns/1ps

// One outstanding bundled-data transaction. Same held-bank/three-flop
// handshake as the existing debugger command channel, with parameterized
// payloads. Both reset endpoints MUST share the same assertion epoch.
module nes_console_mailbox #(
    parameter int REQUEST_BITS = 32,
    parameter int RESPONSE_BITS = 32
) (
    input logic source_clk, source_reset, source_valid,
    input logic [REQUEST_BITS-1:0] source_data,
    output logic source_ready, source_ack,
    output logic [RESPONSE_BITS-1:0] source_response,
    input logic destination_clk, destination_reset,
    output logic destination_valid,
    output logic [REQUEST_BITS-1:0] destination_data,
    input logic destination_done,
    input logic [RESPONSE_BITS-1:0] destination_response
);
    logic busy, request_toggle, acknowledge_toggle;
    (* preserve *) logic [REQUEST_BITS-1:0] request_bank;
    (* preserve *) logic [RESPONSE_BITS-1:0] response_bank;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync, acknowledge_sync;
    assign source_ready = !source_reset && !busy;
    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            busy <= 0; request_toggle <= 0; acknowledge_sync <= 0;
            request_bank <= 0; source_ack <= 0; source_response <= 0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[1:0], acknowledge_toggle};
            source_ack <= 0;
            if (source_valid && source_ready) begin
                request_bank <= source_data;
                request_toggle <= !request_toggle;
                busy <= 1;
            end
            if (busy && acknowledge_sync[2] == request_toggle) begin
                source_response <= response_bank;
                source_ack <= 1;
                busy <= 0;
            end
        end
    end
    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            request_sync <= 0; acknowledge_toggle <= 0;
            destination_valid <= 0; destination_data <= 0; response_bank <= 0;
        end else begin
            request_sync <= {request_sync[1:0], request_toggle};
            if (!destination_valid && request_sync[2] != acknowledge_toggle) begin
                destination_data <= request_bank;
                destination_valid <= 1;
            end
            if (destination_valid && destination_done) begin
                response_bank <= destination_response;
                acknowledge_toggle <= request_sync[2];
                destination_valid <= 0;
            end
        end
    end
endmodule
