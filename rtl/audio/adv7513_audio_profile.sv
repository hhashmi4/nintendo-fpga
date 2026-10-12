`timescale 1ns/1ps

// Documented ADV7513 Rev. B stereo LPCM profile.  The profile is deliberately
// separate from the Phase 6C video profile.  Every update is masked and is
// read back by adv7513_audio_config_engine; packets are enabled only after all
// format/channel-status fields have been installed and the InfoFrame update
// latch is then released.
module adv7513_audio_profile (
    input  logic [4:0] index,
    output logic [7:0] register_address,
    output logic [7:0] write_mask,
    output logic [7:0] write_value,
    output logic       verify_enable,
    output logic       valid
);
    localparam logic [4:0] ENTRY_COUNT = 5'd19;

    always_comb begin
        register_address = 8'h00;
        write_mask = 8'h00;
        write_value = 8'h00;
        verify_enable = 1'b1;
        valid = index < ENTRY_COUNT;
        unique case (index)
            // Hold ACR, Audio Sample, and Audio InfoFrame packets disabled.
            5'd0:  begin register_address = 8'h44; write_mask = 8'h68; write_value = 8'h00; verify_enable = 1'b0; end
            // N=6144 for 48 kHz; CTS remains automatic for independent clocks.
            5'd1:  begin register_address = 8'h01; write_mask = 8'h0f; write_value = 8'h00; end
            5'd2:  begin register_address = 8'h02; write_mask = 8'hff; write_value = 8'h18; end
            5'd3:  begin register_address = 8'h03; write_mask = 8'hff; write_value = 8'h00; end
            5'd4:  begin register_address = 8'h0a; write_mask = 8'hfc; write_value = 8'h00; end
            // SPDIF off, latch on rising SCLK, no external MCLK supplied.
            5'd5:  begin register_address = 8'h0b; write_mask = 8'he0; write_value = 8'h00; end
            // Register-sourced 48 kHz/channel status, I2S0 only, standard I2S.
            5'd6:  begin register_address = 8'h0c; write_mask = 8'hff; write_value = 8'hc4; end
            // Default direct routing: I2S0 left/right to packet channel 0 L/R.
            5'd7:  begin register_address = 8'h0e; write_mask = 8'h3f; write_value = 8'h01; end
            // Consumer LPCM, no pre-emphasis, normal clock accuracy.
            5'd8:  begin register_address = 8'h12; write_mask = 8'hff; write_value = 8'h00; end
            // IEC 60958 channel status: 16-bit word and 48 kHz.
            5'd9:  begin register_address = 8'h14; write_mask = 8'h0f; write_value = 8'h02; end
            5'd10: begin register_address = 8'h15; write_mask = 8'hf0; write_value = 8'h20; end
            // Freeze the previous Audio InfoFrame while fields are changed.
            5'd11: begin register_address = 8'h4a; write_mask = 8'h20; write_value = 8'h20; verify_enable = 1'b0; end
            // Two-channel LPCM, front-left/front-right, no level shift.
            5'd12: begin register_address = 8'h73; write_mask = 8'hff; write_value = 8'h01; end
            5'd13: begin register_address = 8'h74; write_mask = 8'hff; write_value = 8'h00; end
            5'd14: begin register_address = 8'h75; write_mask = 8'hff; write_value = 8'h00; end
            5'd15: begin register_address = 8'h76; write_mask = 8'hff; write_value = 8'h00; end
            5'd16: begin register_address = 8'h77; write_mask = 8'hff; write_value = 8'h00; end
            // Enable ACR/sample/InfoFrame packets, then release packet update.
            5'd17: begin register_address = 8'h44; write_mask = 8'h68; write_value = 8'h68; end
            5'd18: begin register_address = 8'h4a; write_mask = 8'h20; write_value = 8'h00; end
            default: valid = 1'b0;
        endcase
    end
endmodule
