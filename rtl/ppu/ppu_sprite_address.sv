`timescale 1ns/1ps

// Combinational CHR address helper shared by the sprite renderer and the
// exhaustive Phase 3G address test.  relative_row uses the Phase 3F
// scanline-minus-OAM-Y convention and is valid for the selected sprite size.
module ppu_sprite_address (
    input  logic [7:0]  tile,
    input  logic [3:0]  relative_row,
    input  logic        sprite_size_16,
    input  logic        sprite_pattern_table,
    input  logic        vertical_flip,
    output logic [3:0]  selected_row,
    output logic [12:0] pattern_low_address,
    output logic [12:0] pattern_high_address
);
    logic [7:0] selected_tile;

    always_comb begin
        if (vertical_flip)
            selected_row = sprite_size_16 ?
                (4'd15 - relative_row) :
                {1'b0, (3'd7 - relative_row[2:0])};
        else
            selected_row = relative_row;

        if (sprite_size_16) begin
            // In 8x16 mode tile[0] is the pattern-table bank and the
            // remaining bits name an even/odd pair of 8x8 tiles.
            selected_tile = {tile[7:1], 1'b0} +
                            {7'd0, selected_row[3]};
            pattern_low_address = {
                tile[0], selected_tile, 1'b0, selected_row[2:0]
            };
        end else begin
            selected_tile = tile;
            pattern_low_address = {
                sprite_pattern_table, selected_tile,
                1'b0, selected_row[2:0]
            };
        end
        pattern_high_address = pattern_low_address + 13'd8;
    end

`ifndef SYNTHESIS
    always_comb begin
        if (sprite_size_16)
            assert (pattern_low_address[12] == tile[0]);
    end
`endif
endmodule
