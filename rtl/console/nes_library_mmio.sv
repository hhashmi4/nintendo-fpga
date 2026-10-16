`timescale 1ns/1ps
// Separate library v1.0 aperture. One serialized HPS issuer, full words only.
module nes_library_mmio #(parameter bit ENABLED=1) (
    input logic clk, reset,
    input logic [5:0] avs_address,
    input logic avs_read, avs_write,
    input logic [31:0] avs_writedata,
    input logic [3:0] avs_byteenable,
    output logic avs_waitrequest, avs_readdatavalid,
    output logic [31:0] avs_readdata,
    output logic submit,
    output logic [95:0] request_word,
    input logic channel_ready, channel_ack,
    input logic [127:0] channel_response
);
    logic pending, rejected;
    logic [31:0] data_word, token, completed, read_word;
    logic [127:0] response;
    assign avs_waitrequest=0;
    always_comb begin
        read_word=0;
        case(avs_address)
            0: read_word=ENABLED ? 32'h4e45534c : 0;
            4: read_word=ENABLED ? 32'h00010000 : 0;
            8: read_word=ENABLED ? 32'h18040100 : 0;
            12: read_word={29'd0,rejected,pending,ENABLED && !reset && !pending && channel_ready};
            20: read_word=response[31:0];
            24: read_word=completed;
            28: read_word=response[63:32];
            32: read_word=response[95:64];
            36: read_word=response[127:96];
            default: read_word=0;
        endcase
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            pending<=0; rejected<=0; data_word<=0; token<=0; completed<=0;
            response<=0; submit<=0; request_word<=0;
            avs_readdata<=0; avs_readdatavalid<=0;
        end else begin
            submit<=0; avs_readdatavalid<=avs_read;
            if(avs_read) avs_readdata<=read_word;
            if(channel_ack) begin pending<=0; response<=channel_response; completed<=completed+1'b1; end
            if(avs_write && (avs_address==16 || avs_address==40 || avs_address==44)) begin
                if(!ENABLED || pending || !channel_ready || avs_byteenable!=4'hf) rejected<=1;
                else case(avs_address)
                    40: data_word<=avs_writedata;
                    44: token<=avs_writedata;
                    16: begin
                        request_word<={data_word,token,avs_writedata};
                        submit<=1; pending<=1; rejected<=0;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
