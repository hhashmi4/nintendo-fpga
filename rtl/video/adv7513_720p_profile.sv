`timescale 1ns/1ps

// ADV7513 Rev. B Programming Guide qualification profile for RGB888 720p60.
// Every entry is a documented masked register update.  The transport performs
// read/modify/write and a separate readback pass, so reserved bits are never
// guessed.  This is a qualification profile, not a production-approved BOM.
module adv7513_720p_profile (
    input  logic [4:0] index,
    output logic [7:0] register_address,
    output logic [7:0] write_mask,
    output logic [7:0] write_value,
    output logic       verify_enable,
    output logic       valid
);
    localparam logic [4:0] ENTRY_COUNT = 5'd24;

    always_comb begin
        register_address = 8'h00;
        write_mask = 8'h00;
        write_value = 8'h00;
        verify_enable = 1'b1;
        valid = index < ENTRY_COUNT;
        unique case (index)
            // Power-up is permitted only after qualified HPD.
            5'd0:  begin register_address = 8'h41; write_mask = 8'h40; write_value = 8'h00; end
            // Fixed power-up values from Section 3 of the programming guide.
            5'd1:  begin register_address = 8'h98; write_mask = 8'hff; write_value = 8'h03; end
            5'd2:  begin register_address = 8'h9a; write_mask = 8'he0; write_value = 8'he0; end
            5'd3:  begin register_address = 8'h9c; write_mask = 8'hff; write_value = 8'h30; end
            5'd4:  begin register_address = 8'h9d; write_mask = 8'h03; write_value = 8'h01; end
            5'd5:  begin register_address = 8'ha2; write_mask = 8'hff; write_value = 8'ha4; end
            5'd6:  begin register_address = 8'ha3; write_mask = 8'hff; write_value = 8'ha4; end
            5'd7:  begin register_address = 8'he0; write_mask = 8'hff; write_value = 8'hd0; end
            5'd8:  begin register_address = 8'hf9; write_mask = 8'hff; write_value = 8'h00; end
            // 24-bit RGB 4:4:4, separate positive syncs, no CSC or audio.
            5'd9:  begin register_address = 8'h0b; write_mask = 8'h80; write_value = 8'h00; end
            5'd10: begin register_address = 8'h0c; write_mask = 8'h3c; write_value = 8'h00; end
            5'd11: begin register_address = 8'h15; write_mask = 8'h0f; write_value = 8'h00; end
            5'd12: begin register_address = 8'h16; write_mask = 8'hc1; write_value = 8'h00; end
            5'd13: begin register_address = 8'h17; write_mask = 8'h62; write_value = 8'h02; end
            5'd14: begin register_address = 8'h18; write_mask = 8'h80; write_value = 8'h00; end
            // Manual x1 pixel repetition with CTA VIC 4 (1280x720p60).
            5'd15: begin register_address = 8'h3b; write_mask = 8'h7e; write_value = 8'h40; end
            5'd16: begin register_address = 8'h3c; write_mask = 8'h3f; write_value = 8'h04; end
            // HDMI mode with HDCP explicitly disabled in this phase.
            5'd17: begin register_address = 8'haf; write_mask = 8'h82; write_value = 8'h02; end
            // Atomically describe RGB, BT.709, 16:9 raster with centered 4:3
            // active content.  The actual pillar bars remain real pixels.
            5'd18: begin register_address = 8'h4a; write_mask = 8'hc0; write_value = 8'hc0; verify_enable = 1'b0; end
            5'd19: begin register_address = 8'h55; write_mask = 8'h7f; write_value = 8'h11; end
            5'd20: begin register_address = 8'h56; write_mask = 8'hff; write_value = 8'ha9; end
            5'd21: begin register_address = 8'h57; write_mask = 8'h0f; write_value = 8'h00; end
            5'd22: begin register_address = 8'h44; write_mask = 8'h10; write_value = 8'h10; end
            5'd23: begin register_address = 8'h4a; write_mask = 8'hc0; write_value = 8'h80; end
            default: valid = 1'b0;
        endcase
    end
endmodule
