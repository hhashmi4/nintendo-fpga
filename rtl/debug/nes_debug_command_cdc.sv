`timescale 1ns/1ps

// One outstanding command, bundled-data request/acknowledge CDC. Both domains
// must be reset together. A valid level consumes at most one token and must
// return low before rearming, including after reset. Payload and response
// banks remain stable until the opposite domain has sampled them.
module nes_debug_command_cdc (
    input  logic        source_clk,
    input  logic        source_reset,
    input  logic        source_valid,
    input  logic [2:0]  source_command,
    output logic        source_ready,
    output logic        source_busy,
    output logic        source_ack,
    output logic [15:0] source_ack_sequence,
    output logic [2:0]  source_ack_state,
    output logic [1:0]  source_ack_result,

    input  logic        destination_clk,
    input  logic        destination_reset,
    output logic        destination_valid,
    output logic [2:0]  destination_command,
    output logic [15:0] destination_sequence,
    input  logic        destination_done,
    input  logic [2:0]  destination_state,
    input  logic [1:0]  destination_result
);
    logic armed;
    logic request_toggle;
    logic acknowledge_toggle;
    logic [15:0] next_sequence;
    (* preserve *) logic [2:0] command_bank;
    (* preserve *) logic [15:0] sequence_bank;
    (* preserve *) logic [2:0] response_state_bank;
    (* preserve *) logic [1:0] response_result_bank;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] acknowledge_sync;

    assign source_ready = armed && !source_busy && !source_reset;

    always_ff @(posedge source_clk) begin
        if (source_reset) begin
            armed <= 1'b0;
            request_toggle <= 1'b0;
            acknowledge_sync <= 3'b000;
            next_sequence <= 16'd1;
            command_bank <= 3'd0;
            sequence_bank <= 16'd0;
            source_busy <= 1'b0;
            source_ack <= 1'b0;
            source_ack_sequence <= 16'd0;
            source_ack_state <= 3'd0;
            source_ack_result <= 2'd0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[1:0], acknowledge_toggle};
            source_ack <= 1'b0;
            if (!source_valid)
                armed <= 1'b1;
            if (source_valid && source_ready) begin
                armed <= 1'b0;
                command_bank <= source_command;
                sequence_bank <= next_sequence;
                next_sequence <= next_sequence + 16'd1;
                request_toggle <= !request_toggle;
                source_busy <= 1'b1;
            end
            if (source_busy && acknowledge_sync[2] == request_toggle) begin
                source_ack_sequence <= sequence_bank;
                source_ack_state <= response_state_bank;
                source_ack_result <= response_result_bank;
                source_ack <= 1'b1;
                source_busy <= 1'b0;
            end
        end
    end

    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            request_sync <= 3'b000;
            acknowledge_toggle <= 1'b0;
            destination_valid <= 1'b0;
            destination_command <= 3'd0;
            destination_sequence <= 16'd0;
            response_state_bank <= 3'd0;
            response_result_bank <= 2'd0;
        end else begin
            request_sync <= {request_sync[1:0], request_toggle};
            if (!destination_valid && request_sync[2] != acknowledge_toggle) begin
                destination_command <= command_bank;
                destination_sequence <= sequence_bank;
                destination_valid <= 1'b1;
            end
            if (destination_valid && destination_done) begin
                response_state_bank <= destination_state;
                response_result_bank <= destination_result;
                acknowledge_toggle <= request_sync[2];
                destination_valid <= 1'b0;
            end
        end
    end
endmodule
