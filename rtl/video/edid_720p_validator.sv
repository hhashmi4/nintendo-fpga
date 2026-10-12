`timescale 1ns/1ps

// Streaming EDID collector with an independent parse pass.  It validates the
// base header/checksum, validates the first CTA extension when present, and
// accepts 720p60 either as a 1280x720/1650x750/74.25 MHz detailed timing or
// CTA short-video descriptor VIC 4.
module edid_720p_validator (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    input  logic       byte_valid,
    input  logic [7:0] byte_index,
    input  logic [7:0] byte_data,
    input  logic       finish,
    output logic       busy,
    output logic       done,
    output logic       edid_valid,
    output logic       mode_supported
);
    typedef enum logic [2:0] {
        VALIDATOR_IDLE,
        VALIDATOR_CAPTURE,
        VALIDATOR_SCAN_BASE,
        VALIDATOR_CTA_HEADER,
        VALIDATOR_CTA_PAYLOAD,
        VALIDATOR_DONE
    } validator_state_t;

    validator_state_t state;
    logic [7:0] edid [0:255];
    logic [7:0] base_sum, extension_sum, extension_count;
    logic header_matches;
    logic [1:0] detailed_index;
    logic [7:0] cta_pointer, cta_end, cta_dtd_offset;
    logic [2:0] cta_tag;
    integer index;

    function automatic logic dtd_is_720p(input logic [63:0] header);
        logic [15:0] pixel_clock_10khz;
        logic [11:0] horizontal_active, horizontal_blank;
        logic [11:0] vertical_active, vertical_blank;
        begin
            pixel_clock_10khz = header[15:0];
            horizontal_active = {header[39:36], header[23:16]};
            horizontal_blank = {header[35:32], header[31:24]};
            vertical_active = {header[63:60], header[47:40]};
            vertical_blank = {header[59:56], header[55:48]};
            dtd_is_720p = pixel_clock_10khz == 16'd7425 &&
                           horizontal_active == 12'd1280 &&
                           horizontal_active + horizontal_blank == 12'd1650 &&
                           vertical_active == 12'd720 &&
                           vertical_active + vertical_blank == 12'd750;
        end
    endfunction

    assign busy = state != VALIDATOR_IDLE && state != VALIDATOR_DONE;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= VALIDATOR_IDLE;
            base_sum <= '0;
            extension_sum <= '0;
            extension_count <= '0;
            header_matches <= 1'b0;
            detailed_index <= '0;
            cta_pointer <= '0;
            cta_end <= '0;
            cta_dtd_offset <= '0;
            cta_tag <= '0;
            done <= 1'b0;
            edid_valid <= 1'b0;
            mode_supported <= 1'b0;
            for (index = 0; index < 256; index = index + 1)
                edid[index] <= '0;
        end else begin
            done <= 1'b0;
            unique case (state)
                VALIDATOR_IDLE: begin
                    if (start) begin
                        base_sum <= '0;
                        extension_sum <= '0;
                        extension_count <= '0;
                        header_matches <= 1'b1;
                        detailed_index <= '0;
                        edid_valid <= 1'b0;
                        mode_supported <= 1'b0;
                        state <= VALIDATOR_CAPTURE;
                    end
                end
                VALIDATOR_CAPTURE: begin
                    if (byte_valid) begin
                        edid[byte_index] <= byte_data;
                        if (byte_index < 8'd128)
                            base_sum <= base_sum + byte_data;
                        else
                            extension_sum <= extension_sum + byte_data;
                        if (byte_index == 8'd126)
                            extension_count <= byte_data;
                        if ((byte_index == 8'd0 && byte_data != 8'h00) ||
                            (byte_index >= 8'd1 && byte_index <= 8'd6 &&
                             byte_data != 8'hff) ||
                            (byte_index == 8'd7 && byte_data != 8'h00))
                            header_matches <= 1'b0;
                    end
                    if (finish) begin
                        if (!header_matches || base_sum != 0 ||
                            (extension_count != 0 &&
                             (extension_sum != 0 || edid[128] != 8'h02))) begin
                            edid_valid <= 1'b0;
                            state <= VALIDATOR_DONE;
                        end else begin
                            edid_valid <= 1'b1;
                            detailed_index <= 2'd0;
                            state <= VALIDATOR_SCAN_BASE;
                        end
                    end
                end
                VALIDATOR_SCAN_BASE: begin
                    unique case (detailed_index)
                        2'd0: if (dtd_is_720p({edid[61], edid[60],
                                              edid[59], edid[58],
                                              edid[57], edid[56],
                                              edid[55], edid[54]}))
                            mode_supported <= 1'b1;
                        2'd1: if (dtd_is_720p({edid[79], edid[78],
                                              edid[77], edid[76],
                                              edid[75], edid[74],
                                              edid[73], edid[72]}))
                            mode_supported <= 1'b1;
                        2'd2: if (dtd_is_720p({edid[97], edid[96],
                                              edid[95], edid[94],
                                              edid[93], edid[92],
                                              edid[91], edid[90]}))
                            mode_supported <= 1'b1;
                        2'd3: if (dtd_is_720p({edid[115], edid[114],
                                              edid[113], edid[112],
                                              edid[111], edid[110],
                                              edid[109], edid[108]}))
                            mode_supported <= 1'b1;
                        default: begin end
                    endcase
                    if (detailed_index == 2'd3) begin
                        if (extension_count != 0) begin
                            cta_pointer <= 8'd132;
                            cta_dtd_offset <= edid[130] == 0 ?
                                              8'd255 : 8'(128 + edid[130]);
                            state <= VALIDATOR_CTA_HEADER;
                        end else begin
                            state <= VALIDATOR_DONE;
                        end
                    end else begin
                        detailed_index <= detailed_index + 1'b1;
                    end
                end
                VALIDATOR_CTA_HEADER: begin
                    if (cta_pointer >= cta_dtd_offset ||
                        cta_pointer >= 8'd255) begin
                        state <= VALIDATOR_DONE;
                    end else begin
                        cta_tag <= edid[cta_pointer][7:5];
                        cta_end <= cta_pointer +
                                   {3'd0, edid[cta_pointer][4:0]};
                        cta_pointer <= cta_pointer + 1'b1;
                        state <= VALIDATOR_CTA_PAYLOAD;
                    end
                end
                VALIDATOR_CTA_PAYLOAD: begin
                    if (cta_pointer > cta_end ||
                        cta_pointer >= cta_dtd_offset) begin
                        state <= VALIDATOR_CTA_HEADER;
                    end else begin
                        if (cta_tag == 3'd2 &&
                            edid[cta_pointer][6:0] == 7'd4)
                            mode_supported <= 1'b1;
                        cta_pointer <= cta_pointer + 1'b1;
                    end
                end
                VALIDATOR_DONE: begin
                    done <= 1'b1;
                    state <= VALIDATOR_IDLE;
                end
                default: state <= VALIDATOR_IDLE;
            endcase
        end
    end
endmodule
