`timescale 1ns/1ps

// Center a 2x-scaled 256x240 NES image in the 640x480 active VGA region.
module vga_nes_scaler (
    input  logic [9:0]  vga_x,
    input  logic [9:0]  vga_y,
    input  logic        active_video,
    output logic        nes_region,
    output logic [7:0]  nes_x,
    output logic [7:0]  nes_y,
    output logic [15:0] framebuffer_address
);
    localparam logic [9:0] LEFT_BORDER = 10'd64;
    localparam logic [9:0] NES_SCALED_WIDTH = 10'd512;

    logic [9:0] centered_x;

    always_comb begin
        nes_region = active_video &&
                     vga_x >= LEFT_BORDER &&
                     vga_x < LEFT_BORDER + NES_SCALED_WIDTH;
        centered_x = vga_x - LEFT_BORDER;
        nes_x = nes_region ? 8'(centered_x >> 1) : 8'd0;
        nes_y = nes_region ? 8'(vga_y >> 1) : 8'd0;
        framebuffer_address = {nes_y, nes_x};
    end

`ifndef SYNTHESIS
    always_comb begin
        if (nes_region) begin
            assert (nes_y < 8'd240);
            assert (framebuffer_address < 16'd61440);
        end
    end
`endif
endmodule
