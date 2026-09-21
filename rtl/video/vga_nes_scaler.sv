`timescale 1ns/1ps

// Map the 256x240 NES framebuffer into the 640x480 active VGA region. Normal
// mode centers the exact 2x image. Developer layout places the same exact 2x
// image at x=0 so the remaining 128 pixels can hold the side panel.
module vga_nes_scaler (
    input  logic [9:0]  vga_x,
    input  logic [9:0]  vga_y,
    input  logic        active_video,
    input  logic        developer_layout,
    output logic        nes_region,
    output logic [7:0]  nes_x,
    output logic [7:0]  nes_y,
    output logic [15:0] framebuffer_address
);
    localparam logic [9:0] LEFT_BORDER = 10'd64;
    localparam logic [9:0] NES_SCALED_WIDTH = 10'd512;

    logic [9:0] scaled_x;
    logic [9:0] left_edge;

    always_comb begin
        left_edge = developer_layout ? 10'd0 : LEFT_BORDER;
        nes_region = active_video &&
                     vga_x >= left_edge &&
                     vga_x < left_edge + NES_SCALED_WIDTH;
        scaled_x = vga_x - left_edge;
        nes_x = nes_region ? 8'(scaled_x >> 1) : 8'd0;
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
