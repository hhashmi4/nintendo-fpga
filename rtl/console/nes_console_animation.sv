`timescale 1ns/1ps

// Presentation only: never gates supervisor commands, input, or game admission.
// All animated registers change at the existing raster boundary, no new clock.
module nes_console_animation #(parameter bit REDUCED_MOTION=0) (
    input logic pixel_clk, reset, frame_end, status_valid,
    input logic [31:0] status,
    input logic [7:0] buttons,
    input logic focus,
    output logic splash,
    output logic [4:0] phase
);
    import nes_console_style_pkg::*;
    logic [4:0] boot_frames, phase_count;
    logic skipped;
    logic [3:0] previous_state;
    wire valid_status = status_valid;
    assign splash = valid_status && !REDUCED_MOTION && !skipped && buttons==0 && !focus &&
                    boot_frames < 5'(UI_SPLASH_FRAMES) && status[3:0] <= 1;
    // Status commits on the same edge as frame_end. Mask the old state's
    // phase immediately, then count the first completed frame as phase one.
    assign phase = REDUCED_MOTION || !status_valid || status[3:0]!=previous_state ?
                   5'd0 : phase_count;
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            boot_frames <= 0;
            skipped <= 0;
            previous_state <= 0;
            phase_count <= 0;
        end else if (frame_end) begin
            previous_state <= status[3:0];
            if (valid_status) begin
                if (boot_frames < 5'(UI_SPLASH_FRAMES)) boot_frames <= boot_frames + 1'b1;
                if (buttons != 0 || focus || status[3:0] > 1) skipped <= 1;
            end
            if (REDUCED_MOTION || !valid_status) phase_count <= 0;
            else if (status[3:0] != previous_state) phase_count <= 1;
            else phase_count <= phase_count + 1'b1;
        end
    end
endmodule
