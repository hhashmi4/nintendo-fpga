`timescale 1ns/1ps

// Electrical-protocol-neutral RGB888 adapter for an external transmitter.
// Phase 6B launches registered data on pixel_clk rising edges.  Forwarding the
// inverted clock makes the ADV7513 rising capture edge occur half a pixel
// later, providing board-level setup time without changing raster alignment.
module hdmi_rgb_output (
    input  logic        pixel_clk,
    input  logic        pixel_reset,
    input  logic        video_enable_async,
    input  logic [23:0] pipeline_rgb,
    input  logic        pipeline_hsync,
    input  logic        pipeline_vsync,
    input  logic        pipeline_de,
    input  logic        pipeline_frame_start,
    output logic        tx_pixel_clock,
    output logic [23:0] tx_rgb,
    output logic        tx_hsync,
    output logic        tx_vsync,
    output logic        tx_data_enable,
    output logic        tx_frame_start,
    output logic        frame_toggle
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] video_enable_sync;

    always_ff @(posedge pixel_clk) begin
        if (pixel_reset) begin
            video_enable_sync <= 2'b00;
            frame_toggle <= 1'b0;
        end else begin
            video_enable_sync <= {video_enable_sync[0], video_enable_async};
            if (video_enable_sync[1] && pipeline_frame_start)
                frame_toggle <= !frame_toggle;
        end
    end

    assign tx_pixel_clock = !pixel_clk;
    assign tx_rgb = video_enable_sync[1] && pipeline_de ?
                    pipeline_rgb : 24'h000000;
    assign tx_hsync = pipeline_hsync;
    assign tx_vsync = pipeline_vsync;
    assign tx_data_enable = video_enable_sync[1] && pipeline_de;
    assign tx_frame_start = video_enable_sync[1] && pipeline_frame_start;

`ifndef SYNTHESIS
    always_ff @(posedge pixel_clk) begin
        if (!pixel_reset && !video_enable_sync[1]) begin
            assert (!tx_data_enable);
            assert (tx_rgb == 24'h000000);
        end
    end
`endif
endmodule
