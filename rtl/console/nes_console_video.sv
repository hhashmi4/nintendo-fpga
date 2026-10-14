`timescale 1ns/1ps

// Independent, coherent status + source ownership. This owns no frame RAM.
// Normal source changes commit at raster end; safety inhibition may blank
// gameplay immediately while the next system frame is being admitted.
module nes_console_video (
    input logic source_clk, source_reset,
    input logic [31:0] requested_status,
    input logic [7:0] buttons,
    input logic held_reset, inhibit_game,
    output logic source_ack,
    output logic [31:0] source_response,
    input logic pixel_clk, pixel_reset, content_reset,
    input logic frame_end, framebuffer_valid,
    output logic [1:0] selected_source,
    output logic [31:0] displayed_status,
    output logic [7:0] displayed_buttons,
    output logic displayed_reset, game_visible
);
    logic request_valid, request_ready;
    logic [40:0] request_data;
    logic [31:0] response_data;
    logic [1:0] admitted_source;
    logic content_blocked;
    logic source_channel_reset, pixel_channel_reset;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] inhibit_sync;
    // Coordinate a unilateral system/display reset just as the existing
    // framebuffer does. NES content reset is deliberately NOT in this pair.
    reset_sync source_epoch_reset (
        .clk(source_clk), .async_reset_n(!source_reset && !pixel_reset),
        .reset(source_channel_reset)
    );
    reset_sync pixel_epoch_reset (
        .clk(pixel_clk), .async_reset_n(!source_reset && !pixel_reset),
        .reset(pixel_channel_reset)
    );
    nes_console_mailbox #(.REQUEST_BITS(41)) channel (
        .source_clk(source_clk), .source_reset(source_channel_reset),
        .source_valid(1'b1),
        .source_data({held_reset, buttons, requested_status}),
        .source_ready(request_ready), .source_ack(source_ack),
        .source_response(source_response),
        .destination_clk(pixel_clk), .destination_reset(pixel_channel_reset),
        .destination_valid(request_valid), .destination_data(request_data),
        .destination_done(frame_end), .destination_response(response_data)
    );
    always_comb begin
        admitted_source = request_data[7:6];
        if (admitted_source == 2'd3 ||
            (admitted_source == 2'd1 &&
             (inhibit_sync[1] || content_reset || !framebuffer_valid)))
            admitted_source = 2'd0;
        response_data = request_data[31:0];
        response_data[7:6] = admitted_source;
    end
    always_ff @(posedge pixel_clk) begin
        if (pixel_channel_reset) begin
            inhibit_sync <= 2'b11;
            selected_source <= 0;
            displayed_status <= 0;
            displayed_buttons <= 0;
            displayed_reset <= 1;
            content_blocked <= 1;
        end else begin
            inhibit_sync <= {inhibit_sync[0], inhibit_game};
            // Sample the asynchronously asserted content reset at a pixel
            // edge, so emergency blanking cannot glitch RGB within a pixel.
            content_blocked <= inhibit_sync[1] || content_reset || !framebuffer_valid;
            if (frame_end && request_valid) begin
                selected_source <= admitted_source;
                displayed_status <= response_data;
                displayed_buttons <= request_data[39:32];
                displayed_reset <= request_data[40];
            end else if (frame_end && (inhibit_sync[1] || content_reset) &&
                         selected_source == 1)
                selected_source <= 0;
        end
    end
    assign game_visible = selected_source == 1 && !content_blocked;
    // Ready is intentionally not a policy dependency: this producer always
    // offers the latest observation when the one-entry channel is available.
    logic unused_ready;
    assign unused_ready = request_ready;
endmodule
