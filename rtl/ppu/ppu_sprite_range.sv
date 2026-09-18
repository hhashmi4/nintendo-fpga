`timescale 1ns/1ps

// The OAM Y byte names the scanline immediately above a sprite. Evaluation on
// visible scanline N therefore tests the eight-bit relative row N - OAM.Y for
// the sprite data that will be consumed on scanline N+1.
module ppu_sprite_range (
    input  logic [7:0] scanline,
    input  logic [7:0] sprite_y,
    input  logic       sprite_size_16,
    output logic [7:0] relative_row,
    output logic [4:0] sprite_height,
    output logic       in_range
);
    always_comb begin
        relative_row = scanline - sprite_y;
        sprite_height = sprite_size_16 ? 5'd16 : 5'd8;
        in_range = relative_row < {3'b000, sprite_height};
    end
endmodule
