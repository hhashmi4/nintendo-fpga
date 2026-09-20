`timescale 1ns/1ps

// Phase 3G sprite fetch and logical-pixel pipeline.  This block deliberately
// stops before background mixing, sprite-zero-hit generation, and palette RAM.
module ppu_sprite_renderer (
    input  logic        clk,
    input  logic        reset,
    input  logic        ppu_enable,

    input  logic [8:0]  dot,
    input  logic [8:0]  scanline,
    input  logic        visible_pixel,
    input  logic [7:0]  pixel_x,
    input  logic [7:0]  pixel_y,
    input  logic        rendering_enabled,
    input  logic        sprites_enabled,
    input  logic        show_sprites_left,
    input  logic        sprite_size_16,
    input  logic        sprite_pattern_table,
    input  logic [13:0] nametable_fetch_address,

    output logic [2:0]  secondary_read_slot,
    input  logic [7:0]  secondary_read_y,
    input  logic [7:0]  secondary_read_tile,
    // Attribute bits 4:2 are unused by NES sprite rendering.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [7:0]  secondary_read_attributes,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [7:0]  secondary_read_x,
    input  logic [5:0]  secondary_read_sprite_index,
    input  logic        secondary_read_valid,

    output logic        memory_request,
    output logic [13:0] memory_address,
    input  logic        memory_grant,
    input  logic [7:0]  memory_read_data,

    output logic [2:0]  fetch_slot,
    output logic [2:0]  fetch_phase,
    output logic [2:0]  fetch_type,
    output logic        fetch_complete,
    output logic        slot_load_event,
    output logic [3:0]  fetch_relative_row,
    output logic [3:0]  fetch_selected_row,
    output logic [12:0] fetch_pattern_low_address,
    output logic [12:0] fetch_pattern_high_address,
    output logic [7:0]  sprite_decrement_mask,
    output logic [7:0]  sprite_shift_mask,

    output logic        sprite_pixel_valid,
    output logic [7:0]  sprite_x,
    output logic [7:0]  sprite_y,
    output logic [1:0]  sprite_pattern,
    output logic [1:0]  sprite_palette,
    output logic [3:0]  sprite_palette_index,
    output logic        sprite_opaque,
    output logic        sprite_priority_behind_background,
    output logic        sprite_is_zero,
    output logic [2:0]  sprite_slot,
    output logic [5:0]  sprite_original_index
);
    localparam logic [2:0] FETCH_NONE          = 3'd0;
    localparam logic [2:0] FETCH_DUMMY_FIRST   = 3'd1;
    localparam logic [2:0] FETCH_DUMMY_SECOND  = 3'd2;
    localparam logic [2:0] FETCH_PATTERN_LOW   = 3'd3;
    localparam logic [2:0] FETCH_PATTERN_HIGH  = 3'd4;

    logic fetch_window;
    logic capture_phase;
    logic [5:0] fetch_offset;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [7:0] relative_row_full;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] slot_pattern [0:7];
    logic [7:0] pattern_low [0:7];
    logic [7:0] pattern_high [0:7];
    logic [7:0] x_counter [0:7];
    logic [1:0] slot_palette [0:7];
    logic       slot_priority [0:7];
    logic [5:0] slot_original_index [0:7];
    logic       slot_valid [0:7];
    logic       winner_found;
    logic       pixel_enabled;

    function automatic logic [7:0] reverse_bits(input logic [7:0] value);
        for (int bit_index = 0; bit_index < 8; bit_index++)
            reverse_bits[bit_index] = value[7-bit_index];
    endfunction

    assign fetch_window = scanline < 9'd240 &&
                          dot >= 9'd257 && dot <= 9'd320;
    // The low six dot bits wrap from 63 at dot 319 to 0 at dot 320;
    // subtracting one yields the required modulo-64 offset 0..63.
    assign fetch_offset = dot[5:0] - 6'd1;
    assign fetch_slot = fetch_offset[5:3];
    assign fetch_phase = fetch_offset[2:0];
    assign secondary_read_slot = fetch_window ? fetch_slot : 3'd0;
    assign relative_row_full = scanline[7:0] - secondary_read_y;
    assign fetch_relative_row = relative_row_full[3:0];

    ppu_sprite_address address_generator (
        .tile                 (secondary_read_tile),
        .relative_row         (fetch_relative_row),
        .sprite_size_16       (sprite_size_16),
        .sprite_pattern_table (sprite_pattern_table),
        .vertical_flip        (secondary_read_attributes[7]),
        .selected_row         (fetch_selected_row),
        .pattern_low_address  (fetch_pattern_low_address),
        .pattern_high_address (fetch_pattern_high_address)
    );

    always_comb begin
        case (fetch_phase)
            3'd0, 3'd1: fetch_type = FETCH_DUMMY_FIRST;
            3'd2, 3'd3: fetch_type = FETCH_DUMMY_SECOND;
            3'd4, 3'd5: fetch_type = FETCH_PATTERN_LOW;
            3'd6, 3'd7: fetch_type = FETCH_PATTERN_HIGH;
            default:    fetch_type = FETCH_NONE;
        endcase
        if (!fetch_window)
            fetch_type = FETCH_NONE;

        if (fetch_type == FETCH_PATTERN_LOW)
            memory_address = {1'b0, fetch_pattern_low_address};
        else if (fetch_type == FETCH_PATTERN_HIGH)
            memory_address = {1'b0, fetch_pattern_high_address};
        else
            memory_address = nametable_fetch_address;

    end

    assign memory_request = !reset && ppu_enable && rendering_enabled &&
                            fetch_window;
    assign capture_phase = fetch_phase[0];
    assign fetch_complete = memory_request && memory_grant && capture_phase;
    assign slot_load_event = memory_request && fetch_phase == 3'd7;

    always_comb begin
        sprite_decrement_mask = 8'h00;
        sprite_shift_mask = 8'h00;
        for (int slot_index = 0; slot_index < 8; slot_index++) begin
            slot_pattern[slot_index] = 2'b00;
            if (slot_valid[slot_index] && x_counter[slot_index] == 8'h00)
                slot_pattern[slot_index] = {
                    pattern_high[slot_index][7],
                    pattern_low[slot_index][7]
                };
            if (ppu_enable && visible_pixel && slot_valid[slot_index]) begin
                if (x_counter[slot_index] != 8'h00)
                    sprite_decrement_mask[slot_index] = 1'b1;
                else
                    sprite_shift_mask[slot_index] = 1'b1;
            end
        end
    end

    always_comb begin
        sprite_pixel_valid = visible_pixel;
        sprite_x = visible_pixel ? pixel_x : 8'h00;
        sprite_y = visible_pixel ? pixel_y : 8'h00;
        sprite_pattern = 2'b00;
        sprite_palette = 2'b00;
        sprite_palette_index = 4'h0;
        sprite_opaque = 1'b0;
        sprite_priority_behind_background = 1'b0;
        sprite_is_zero = 1'b0;
        sprite_slot = 3'd0;
        sprite_original_index = 6'd0;
        winner_found = 1'b0;
        pixel_enabled = visible_pixel && sprites_enabled &&
                        (show_sprites_left || pixel_x >= 8'd8);

        // Iteration is deliberately low-to-high.  winner_found prevents a
        // later secondary-OAM slot from replacing the first opaque slot.
        for (int slot_index = 0; slot_index < 8; slot_index++) begin
            if (!winner_found && pixel_enabled && slot_valid[slot_index] &&
                slot_pattern[slot_index] != 2'b00) begin
                winner_found = 1'b1;
                sprite_pattern = slot_pattern[slot_index];
                sprite_palette = slot_palette[slot_index];
                sprite_palette_index = {
                    slot_palette[slot_index], slot_pattern[slot_index]
                };
                sprite_opaque = 1'b1;
                sprite_priority_behind_background =
                    slot_priority[slot_index];
                sprite_is_zero = slot_original_index[slot_index] == 6'd0;
                sprite_slot = 3'(slot_index);
                sprite_original_index = slot_original_index[slot_index];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int slot_index = 0; slot_index < 8; slot_index++) begin
                pattern_low[slot_index] <= 8'h00;
                pattern_high[slot_index] <= 8'h00;
                x_counter[slot_index] <= 8'h00;
                slot_palette[slot_index] <= 2'b00;
                slot_priority[slot_index] <= 1'b0;
                slot_original_index[slot_index] <= 6'd0;
                slot_valid[slot_index] <= 1'b0;
            end
        end else if (ppu_enable) begin
            if (visible_pixel) begin
                for (int slot_index = 0; slot_index < 8; slot_index++) begin
                    if (slot_valid[slot_index]) begin
                        if (x_counter[slot_index] != 8'h00)
                            x_counter[slot_index] <=
                                x_counter[slot_index] - 8'd1;
                        else begin
                            pattern_low[slot_index] <= {
                                pattern_low[slot_index][6:0], 1'b0
                            };
                            pattern_high[slot_index] <= {
                                pattern_high[slot_index][6:0], 1'b0
                            };
                        end
                    end
                end
            end

            if (memory_request && fetch_phase == 3'd0) begin
                // Clearing at the start of each group makes an invalid slot
                // and any denied pattern read deterministically transparent.
                pattern_low[fetch_slot] <= 8'h00;
                pattern_high[fetch_slot] <= 8'h00;
                slot_valid[fetch_slot] <= 1'b0;
            end

            if (fetch_complete && fetch_phase == 3'd5 &&
                secondary_read_valid) begin
                pattern_low[fetch_slot] <=
                    secondary_read_attributes[6] ?
                    reverse_bits(memory_read_data) : memory_read_data;
            end

            if (fetch_complete && fetch_phase == 3'd7 &&
                secondary_read_valid) begin
                pattern_high[fetch_slot] <=
                    secondary_read_attributes[6] ?
                    reverse_bits(memory_read_data) : memory_read_data;
            end

            if (slot_load_event) begin
                x_counter[fetch_slot] <= secondary_read_x;
                slot_palette[fetch_slot] <=
                    secondary_read_attributes[1:0];
                slot_priority[fetch_slot] <=
                    secondary_read_attributes[5];
                slot_original_index[fetch_slot] <=
                    secondary_read_sprite_index;
                slot_valid[fetch_slot] <= secondary_read_valid;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset) begin
            assert (!(sprite_opaque && !sprite_pixel_valid));
            assert (!sprite_opaque || sprites_enabled);
            assert (!sprite_opaque || show_sprites_left || pixel_x >= 8'd8);
            if (fetch_type == FETCH_PATTERN_LOW ||
                fetch_type == FETCH_PATTERN_HIGH)
                assert (!memory_address[13]);
            if (!ppu_enable) begin
                assert (sprite_decrement_mask == 8'h00);
                assert (sprite_shift_mask == 8'h00);
            end
            if (sprite_opaque) begin
                assert (slot_valid[sprite_slot]);
                assert (slot_pattern[sprite_slot] != 2'b00);
                assert (sprite_is_zero ==
                        (sprite_original_index == 6'd0));
                for (int earlier_slot = 0; earlier_slot < 8;
                     earlier_slot++) begin
                    if (earlier_slot < sprite_slot)
                        assert (!slot_valid[earlier_slot] ||
                                slot_pattern[earlier_slot] == 2'b00);
                end
            end
        end
    end
`endif
endmodule
