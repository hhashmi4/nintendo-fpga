`timescale 1ns/1ps

// Video-domain Developer Mode page selection. Requests may arrive at any
// point in a VGA frame, but the renderer-visible page changes only on the
// next frame_start pulse. This keeps every displayed frame on one page.
module nes_debug_page_select #(
    parameter logic [2:0] RESET_PAGE = 3'd0
) (
    input  logic       pixel_clk,
    input  logic       reset,
    input  logic       frame_start,
    input  logic       page_next_request,
    input  logic       page_select_valid,
    input  logic [2:0] requested_page,
    output logic [2:0] active_page,
    output logic       request_pending
);
    localparam logic [2:0] LAST_PAGE = 3'd4;

    logic [2:0] pending_page;
    logic [2:0] selected_base;
    logic [2:0] requested_page_sanitized;

    always_comb begin
        requested_page_sanitized = (requested_page <= LAST_PAGE) ?
                                   requested_page : 3'd0;
        selected_base = request_pending ? pending_page : active_page;
    end

    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            active_page <= (RESET_PAGE <= LAST_PAGE) ? RESET_PAGE : 3'd0;
            pending_page <= (RESET_PAGE <= LAST_PAGE) ? RESET_PAGE : 3'd0;
            request_pending <= 1'b0;
        end else begin
            // A direct page request has priority over page-next when both
            // controls are asserted in the same pixel clock.
            if (page_select_valid) begin
                pending_page <= requested_page_sanitized;
                request_pending <= 1'b1;
            end else if (page_next_request) begin
                pending_page <= (selected_base == LAST_PAGE) ?
                                3'd0 : selected_base + 3'd1;
                request_pending <= 1'b1;
            end

            // A request coincident with frame_start is committed immediately;
            // otherwise a previously queued request is committed here.
            if (frame_start) begin
                if (page_select_valid) begin
                    active_page <= requested_page_sanitized;
                    request_pending <= 1'b0;
                end else if (page_next_request) begin
                    active_page <= (selected_base == LAST_PAGE) ?
                                   3'd0 : selected_base + 3'd1;
                    request_pending <= 1'b0;
                end else if (request_pending) begin
                    active_page <= pending_page;
                    request_pending <= 1'b0;
                end
            end
        end
    end
endmodule
