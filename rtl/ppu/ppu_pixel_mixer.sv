`timescale 1ns/1ps

// Phase 3H final logical-pixel selection.  Background and sprite artwork,
// scrolling, evaluation, and pattern shifting remain owned by earlier stages.
// This block chooses a palette entry, interprets its NES color byte, and emits
// the overlap event consumed by the existing PPUSTATUS sprite-zero latch.
module ppu_pixel_mixer (
    input  logic        clk,
    input  logic        reset,
    input  logic        ppu_enable,
    input  logic        visible_pixel,
    input  logic [7:0]  pixel_x,
    input  logic [7:0]  pixel_y,

    input  logic        background_enabled,
    input  logic        sprites_enabled,
    input  logic        show_background_left,
    input  logic        show_sprites_left,
    input  logic        grayscale,
    input  logic [2:0]  emphasis,

    input  logic        bg_pixel_valid,
    input  logic [7:0]  bg_x,
    input  logic [7:0]  bg_y,
    input  logic [1:0]  bg_pattern,
    input  logic [1:0]  bg_palette,
    input  logic        bg_opaque,

    input  logic        sprite_pixel_valid,
    input  logic [7:0]  sprite_x,
    input  logic [7:0]  sprite_y,
    input  logic [1:0]  sprite_pattern,
    input  logic [1:0]  sprite_palette,
    input  logic        sprite_opaque,
    input  logic        sprite_priority_behind_background,
    input  logic        sprite_is_zero,
    input  logic [2:0]  sprite_slot,
    input  logic [5:0]  sprite_original_index,

    output logic [13:0] palette_address,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [7:0]  palette_read_data,
    /* verilator lint_on UNUSEDSIGNAL */

    output logic        final_pixel_valid,
    output logic [7:0]  final_pixel_x,
    output logic [7:0]  final_pixel_y,
    output logic [5:0]  nes_color,
    output logic [2:0]  color_emphasis,
    // 0 = universal background, 1 = background, 2 = sprite.
    output logic [1:0]  pixel_source,
    output logic        sprite_zero_hit_event,
    output logic [2:0]  winning_sprite_slot,
    output logic        winning_sprite_zero
);
    localparam logic [1:0] SOURCE_UNIVERSAL = 2'd0;
    localparam logic [1:0] SOURCE_BACKGROUND = 2'd1;
    localparam logic [1:0] SOURCE_SPRITE = 2'd2;

    logic coordinates_match;
    logic background_opaque_effective;
    logic sprite_opaque_effective;

    always_comb begin
        coordinates_match = bg_x == pixel_x && bg_y == pixel_y &&
                            sprite_x == pixel_x && sprite_y == pixel_y;
        final_pixel_valid = !reset && ppu_enable && visible_pixel &&
                            bg_pixel_valid && sprite_pixel_valid &&
                            coordinates_match && pixel_y < 8'd240;
        final_pixel_x = final_pixel_valid ? pixel_x : 8'h00;
        final_pixel_y = final_pixel_valid ? pixel_y : 8'h00;

        // Pattern zero is transparent even if malformed upstream metadata
        // claims otherwise.  The enable terms make zero-hit requirements
        // explicit in addition to the upstream PPUMASK qualification.
        background_opaque_effective = final_pixel_valid &&
                                      background_enabled && bg_opaque &&
                                      bg_pattern != 2'b00 &&
                                      (show_background_left ||
                                       pixel_x >= 8'd8);
        sprite_opaque_effective = final_pixel_valid && sprites_enabled &&
                                  sprite_opaque &&
                                  sprite_pattern != 2'b00 &&
                                  (show_sprites_left || pixel_x >= 8'd8);

        pixel_source = SOURCE_UNIVERSAL;
        palette_address = 14'h3f00;
        if (background_opaque_effective && !sprite_opaque_effective) begin
            pixel_source = SOURCE_BACKGROUND;
            palette_address = {10'h3f0, bg_palette, bg_pattern};
        end else if (!background_opaque_effective &&
                     sprite_opaque_effective) begin
            pixel_source = SOURCE_SPRITE;
            palette_address = {9'h1f8, 1'b1,
                               sprite_palette, sprite_pattern};
        end else if (background_opaque_effective &&
                     sprite_opaque_effective) begin
            if (sprite_priority_behind_background) begin
                pixel_source = SOURCE_BACKGROUND;
                palette_address = {10'h3f0, bg_palette, bg_pattern};
            end else begin
                pixel_source = SOURCE_SPRITE;
                palette_address = {9'h1f8, 1'b1,
                                   sprite_palette, sprite_pattern};
            end
        end

        // PPUMASK grayscale keeps only the $x0 luminance-family bits from
        // the stored six-bit color number; palette storage is unchanged.
        nes_color = palette_read_data[5:0] &
                    (grayscale ? 6'h30 : 6'h3f);
        color_emphasis = emphasis;

        sprite_zero_hit_event = background_opaque_effective &&
                                sprite_opaque_effective &&
                                sprite_is_zero &&
                                sprite_original_index == 6'd0 &&
                                pixel_x != 8'd255;
        winning_sprite_slot = sprite_slot;
        winning_sprite_zero = sprite_opaque_effective && sprite_is_zero &&
                              sprite_original_index == 6'd0;
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset) begin
            assert (palette_address >= 14'h3f00 &&
                    palette_address <= 14'h3f1f);
            if (!ppu_enable) begin
                assert (!final_pixel_valid);
                assert (!sprite_zero_hit_event);
            end
            if (final_pixel_valid) begin
                assert (final_pixel_y < 8'd240);
                assert (bg_pixel_valid && sprite_pixel_valid);
                assert (coordinates_match);
                if (!background_opaque_effective &&
                    !sprite_opaque_effective)
                    assert (pixel_source == SOURCE_UNIVERSAL &&
                            palette_address == 14'h3f00);
                if (background_opaque_effective &&
                    !sprite_opaque_effective)
                    assert (pixel_source == SOURCE_BACKGROUND);
                if (!background_opaque_effective &&
                    sprite_opaque_effective)
                    assert (pixel_source == SOURCE_SPRITE);
                if (background_opaque_effective &&
                    sprite_opaque_effective &&
                    sprite_priority_behind_background)
                    assert (pixel_source == SOURCE_BACKGROUND);
                if (background_opaque_effective &&
                    sprite_opaque_effective &&
                    !sprite_priority_behind_background)
                    assert (pixel_source == SOURCE_SPRITE);
                if (pixel_x < 8'd8) begin
                    if (!show_background_left)
                        assert (!background_opaque_effective);
                    if (!show_sprites_left)
                        assert (!sprite_opaque_effective);
                end
            end
            if (sprite_zero_hit_event) begin
                assert (final_pixel_valid && background_opaque_effective &&
                        sprite_opaque_effective);
                assert (sprite_is_zero && sprite_original_index == 6'd0);
                assert (pixel_x != 8'd255);
            end
        end
    end
`endif
endmodule
