`timescale 1ns/1ps

// Independent v1.0 aperture at 0xff202000 (32 bytes). One HPS issuer.
module nes_console_mmio #(
    parameter bit ENABLED = 1'b1
) (
    input logic clk, reset,
    input logic [4:0] avs_address,
    input logic avs_read, avs_write,
    input logic [31:0] avs_writedata,
    input logic [3:0] avs_byteenable,
    output logic avs_waitrequest, avs_readdatavalid,
    output logic [31:0] avs_readdata,
    output logic submit,
    output logic [31:0] request_word,
    input logic channel_ready, channel_ack,
    input logic [33:0] channel_response
);
    logic pending, rejected;
    logic [31:0] response_status, completed_count;
    logic [1:0] response_result;
    logic [31:0] read_word;
    assign avs_waitrequest = 0;
    always_comb begin
        read_word = 0;
        case (avs_address)
            5'h00: read_word = ENABLED ? 32'h4e455343 : 32'd0;
            5'h04: read_word = ENABLED ? 32'h00010000 : 32'd0;
            5'h08: read_word = ENABLED ? 32'h00000007 : 32'd0; // epoch, frame ack, local input
            5'h0c: read_word = {29'd0, rejected, pending,
                                ENABLED && !reset && !pending && channel_ready};
            5'h14: read_word = response_status;
            5'h18: read_word = {30'd0, response_result};
            5'h1c: read_word = completed_count;
            default: read_word = 0;
        endcase
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            avs_readdatavalid <= 0; avs_readdata <= 0;
            submit <= 0; request_word <= 0; pending <= 0; rejected <= 0;
            response_status <= 0; response_result <= 0; completed_count <= 0;
        end else begin
            avs_readdatavalid <= avs_read;
            if (avs_read) avs_readdata <= read_word;
            submit <= 0;
            if (channel_ack) begin
                pending <= 0;
                response_status <= channel_response[31:0];
                response_result <= channel_response[33:32];
                completed_count <= completed_count + 32'd1;
            end
            if (avs_write && avs_address == 5'h10) begin
                if (ENABLED && !pending && channel_ready && avs_byteenable == 4'hf) begin
                    request_word <= avs_writedata;
                    submit <= 1;
                    pending <= 1;
                    rejected <= 0;
                end else rejected <= 1;
            end
        end
    end
endmodule
