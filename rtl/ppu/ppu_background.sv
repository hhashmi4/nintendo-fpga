`timescale 1ns/1ps

module ppu_background (
    input  logic        clk,
    input  logic        reset,
    input  logic        ppu_enable,

    input  logic [8:0]  dot,
    input  logic [8:0]  scanline,
    input  logic        visible_pixel,
    input  logic [7:0]  pixel_x,
    input  logic [7:0]  pixel_y,

    input  logic        rendering_enabled,
    input  logic        background_enabled,
    input  logic        show_background_left,
    input  logic        background_pattern_table,
    input  logic [2:0]  fine_x,
    input  logic [2:0]  fine_y,
    input  logic        coarse_x_bit_1,
    input  logic        coarse_y_bit_1,
    input  logic [13:0] nametable_fetch_address,
    input  logic [13:0] attribute_fetch_address,

    output logic        renderer_memory_request,
    output logic [13:0] renderer_memory_address,
    input  logic        renderer_memory_grant,
    input  logic [7:0]  renderer_memory_read_data,

    output logic [2:0]  fetch_phase,
    output logic [2:0]  fetch_type,
    output logic        fetch_complete_event,
    output logic        tile_load_event,
    output logic        shifter_shift_event,

    output logic [7:0]  next_tile_id = 8'h00,
    output logic [1:0]  next_tile_attribute = 2'b00,
    output logic [7:0]  next_tile_pattern_low = 8'h00,
    output logic [7:0]  next_tile_pattern_high = 8'h00,
    output logic [15:0] pattern_low_shift = 16'h0000,
    output logic [15:0] pattern_high_shift = 16'h0000,
    output logic [15:0] attribute_low_shift = 16'h0000,
    output logic [15:0] attribute_high_shift = 16'h0000,

    output logic        bg_pixel_valid,
    output logic [7:0]  bg_x,
    output logic [7:0]  bg_y,
    output logic [1:0]  bg_pattern,
    output logic [1:0]  bg_palette,
    output logic        bg_opaque,
    output logic [3:0]  bg_index
);
    localparam logic [2:0] PHASE_PATTERN_HIGH_CAPTURE = 3'd0;
    localparam logic [2:0] PHASE_NAMETABLE_ADDRESS    = 3'd1;
    localparam logic [2:0] PHASE_NAMETABLE_CAPTURE    = 3'd2;
    localparam logic [2:0] PHASE_ATTRIBUTE_ADDRESS    = 3'd3;
    localparam logic [2:0] PHASE_ATTRIBUTE_CAPTURE    = 3'd4;
    localparam logic [2:0] PHASE_PATTERN_LOW_ADDRESS  = 3'd5;
    localparam logic [2:0] PHASE_PATTERN_LOW_CAPTURE  = 3'd6;
    localparam logic [2:0] PHASE_PATTERN_HIGH_ADDRESS = 3'd7;

    localparam logic [2:0] FETCH_NONE         = 3'd0;
    localparam logic [2:0] FETCH_NAMETABLE    = 3'd1;
    localparam logic [2:0] FETCH_ATTRIBUTE    = 3'd2;
    localparam logic [2:0] FETCH_PATTERN_LOW  = 3'd3;
    localparam logic [2:0] FETCH_PATTERN_HIGH = 3'd4;
    localparam logic [2:0] FETCH_NAMETABLE_DUMMY = 3'd5;

    logic rendering_scanline;
    logic main_fetch_window;
    logic trailing_fetch_window;
    logic fetch_window;
    logic fetch_capture_phase;
    logic [1:0] selected_attribute;
    logic [15:0] fine_x_mask;
    logic [1:0] raw_pattern;
    logic [1:0] raw_palette;
    logic pixel_enabled;

    function automatic logic [1:0] select_attribute_quadrant(
        input logic [7:0] attribute,
        input logic       select_x,
        input logic       select_y
    );
        case ({select_y, select_x})
            2'b00: select_attribute_quadrant = attribute[1:0];
            2'b01: select_attribute_quadrant = attribute[3:2];
            2'b10: select_attribute_quadrant = attribute[5:4];
            2'b11: select_attribute_quadrant = attribute[7:6];
            default: select_attribute_quadrant = 2'b00;
        endcase
    endfunction

    always_comb begin
        rendering_scanline = scanline < 9'd240 || scanline == 9'd261;
        main_fetch_window = (dot >= 9'd1 && dot <= 9'd256) ||
                            (dot >= 9'd321 && dot <= 9'd336);
        trailing_fetch_window = dot >= 9'd337 && dot <= 9'd340;
        fetch_window = main_fetch_window || trailing_fetch_window;
        fetch_phase = dot[2:0];

        fetch_type = FETCH_NONE;
        renderer_memory_address = 14'h0000;
        if (trailing_fetch_window) begin
            fetch_type = FETCH_NAMETABLE_DUMMY;
            renderer_memory_address = nametable_fetch_address;
        end else if (main_fetch_window) begin
            case (fetch_phase)
                PHASE_NAMETABLE_ADDRESS,
                PHASE_NAMETABLE_CAPTURE: begin
                    fetch_type = FETCH_NAMETABLE;
                    renderer_memory_address = nametable_fetch_address;
                end
                PHASE_ATTRIBUTE_ADDRESS,
                PHASE_ATTRIBUTE_CAPTURE: begin
                    fetch_type = FETCH_ATTRIBUTE;
                    renderer_memory_address = attribute_fetch_address;
                end
                PHASE_PATTERN_LOW_ADDRESS,
                PHASE_PATTERN_LOW_CAPTURE: begin
                    fetch_type = FETCH_PATTERN_LOW;
                    renderer_memory_address = {
                        1'b0, background_pattern_table, next_tile_id,
                        1'b0, fine_y
                    };
                end
                PHASE_PATTERN_HIGH_ADDRESS,
                PHASE_PATTERN_HIGH_CAPTURE: begin
                    fetch_type = FETCH_PATTERN_HIGH;
                    renderer_memory_address = {
                        1'b0, background_pattern_table, next_tile_id,
                        1'b1, fine_y
                    };
                end
                default: begin end
            endcase
        end

        renderer_memory_request = !reset && ppu_enable &&
                                  rendering_enabled && rendering_scanline &&
                                  fetch_window;
        fetch_capture_phase = trailing_fetch_window ? !dot[0] :
                              fetch_phase == PHASE_NAMETABLE_CAPTURE ||
                              fetch_phase == PHASE_ATTRIBUTE_CAPTURE ||
                              fetch_phase == PHASE_PATTERN_LOW_CAPTURE ||
                              fetch_phase == PHASE_PATTERN_HIGH_CAPTURE;
        tile_load_event = !reset && ppu_enable && rendering_enabled &&
                          rendering_scanline && main_fetch_window &&
                          fetch_phase == PHASE_PATTERN_HIGH_CAPTURE;
        shifter_shift_event = !reset && ppu_enable && rendering_enabled &&
                              rendering_scanline && main_fetch_window;

    end

    always_comb begin
        fetch_complete_event = renderer_memory_request &&
                               renderer_memory_grant && fetch_capture_phase;
        selected_attribute = select_attribute_quadrant(
            renderer_memory_read_data, coarse_x_bit_1, coarse_y_bit_1
        );
    end

    always_comb begin
        fine_x_mask = 16'h8000 >> fine_x;
        raw_pattern = {
            |(pattern_high_shift & fine_x_mask),
            |(pattern_low_shift & fine_x_mask)
        };
        raw_palette = {
            |(attribute_high_shift & fine_x_mask),
            |(attribute_low_shift & fine_x_mask)
        };

        bg_pixel_valid = visible_pixel;
        bg_x = visible_pixel ? pixel_x : 8'h00;
        bg_y = visible_pixel ? pixel_y : 8'h00;
        pixel_enabled = visible_pixel && background_enabled &&
                        (show_background_left || pixel_x >= 8'd8);
        bg_pattern = pixel_enabled ? raw_pattern : 2'b00;
        bg_opaque = pixel_enabled && raw_pattern != 2'b00;
        bg_palette = bg_opaque ? raw_palette : 2'b00;
        bg_index = bg_opaque ? {raw_palette, raw_pattern} : 4'h0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            next_tile_id           <= 8'h00;
            next_tile_attribute    <= 2'b00;
            next_tile_pattern_low  <= 8'h00;
            next_tile_pattern_high <= 8'h00;
            pattern_low_shift      <= 16'h0000;
            pattern_high_shift     <= 16'h0000;
            attribute_low_shift    <= 16'h0000;
            attribute_high_shift   <= 16'h0000;
        end else if (ppu_enable) begin
            if (shifter_shift_event) begin
                pattern_low_shift    <= {pattern_low_shift[14:0], 1'b0};
                pattern_high_shift   <= {pattern_high_shift[14:0], 1'b0};
                attribute_low_shift  <= {attribute_low_shift[14:0], 1'b0};
                attribute_high_shift <= {attribute_high_shift[14:0], 1'b0};
            end

            if (fetch_complete_event && main_fetch_window) begin
                case (fetch_phase)
                    PHASE_NAMETABLE_CAPTURE:
                        next_tile_id <= renderer_memory_read_data;
                    PHASE_ATTRIBUTE_CAPTURE:
                        next_tile_attribute <= selected_attribute;
                    PHASE_PATTERN_LOW_CAPTURE:
                        next_tile_pattern_low <= renderer_memory_read_data;
                    PHASE_PATTERN_HIGH_CAPTURE:
                        next_tile_pattern_high <= renderer_memory_read_data;
                    default: begin end
                endcase
            end

            // The dot-8 completion edge first advances the active pixels and
            // then fills the low/future byte. The just-completed high-plane
            // value is forwarded directly because nonblocking assignments
            // update the fetch latch after this edge.
            if (tile_load_event) begin
                pattern_low_shift <= {
                    pattern_low_shift[14:7], next_tile_pattern_low
                };
                pattern_high_shift <= {
                    pattern_high_shift[14:7],
                    (fetch_complete_event ? renderer_memory_read_data :
                                            next_tile_pattern_high)
                };
                attribute_low_shift <= {
                    attribute_low_shift[14:7],
                    {8{next_tile_attribute[0]}}
                };
                attribute_high_shift <= {
                    attribute_high_shift[14:7],
                    {8{next_tile_attribute[1]}}
                };
            end
        end
    end
endmodule
