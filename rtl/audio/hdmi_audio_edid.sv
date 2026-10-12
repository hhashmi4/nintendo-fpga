`timescale 1ns/1ps

// Streaming inspection of the first CTA extension already read by Phase 6C.
// Use only together with its validated checksum/HDMI video capability. Basic
// Audio guarantees stereo 16-bit 32/44.1/48 kHz LPCM; otherwise require a SAD
// explicitly advertising at least two LPCM channels, 48 kHz and 16-bit words.
module hdmi_audio_edid (
    input logic clk, reset, start,
    input logic byte_valid,
    input logic [7:0] byte_index, byte_data,
    output logic supports_pcm
);
    logic cta;
    logic [7:0] data_end;
    logic [4:0] remaining;
    logic audio_block;
    logic [1:0] sad_position;
    logic sad_pcm, sad_48k;
    always_ff @(posedge clk) begin
        if (reset || start) begin
            supports_pcm <= 1'b0;
            cta <= 1'b0;
            data_end <= 8'd0;
            remaining <= '0;
            audio_block <= 1'b0;
            sad_position <= '0;
            sad_pcm <= 1'b0;
            sad_48k <= 1'b0;
        end else if (byte_valid) begin
            if (byte_index == 128) cta <= byte_data == 8'h02;
            if (byte_index == 130)
                data_end <= byte_data == 0 ? 8'd4 :
                            (byte_data > 127 ? 8'd127 : byte_data);
            if (byte_index == 131 && cta && byte_data[6])
                supports_pcm <= 1'b1;
            if (cta && byte_index >= 132 &&
                {1'b0, byte_index[6:0]} < data_end) begin
                if (remaining == 0) begin
                    remaining <= byte_data[4:0];
                    audio_block <= byte_data[7:5] == 3'd1;
                    sad_position <= '0;
                end else begin
                    remaining <= remaining - 1'b1;
                    if (audio_block) begin
                        case (sad_position)
                            0: sad_pcm <= byte_data[6:3] == 4'd1 &&
                                           byte_data[2:0] >= 3'd1;
                            1: sad_48k <= byte_data[2];
                            2: if (sad_pcm && sad_48k && byte_data[0])
                                   supports_pcm <= 1'b1;
                            default: ;
                        endcase
                        sad_position <= sad_position == 2 ? 2'd0 :
                                        sad_position + 1'b1;
                    end
                end
            end
        end
    end
endmodule
