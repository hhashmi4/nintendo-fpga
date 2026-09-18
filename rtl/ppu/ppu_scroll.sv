`timescale 1ns/1ps

module ppu_scroll (
    input  logic [14:0] vram_address,
    input  logic [14:0] temp_vram_address,
    input  logic        ppu_enable,
    input  logic        rendering_enabled,
    input  logic [8:0]  dot,
    input  logic [8:0]  scanline,

    output logic        rendering_scanline,
    output logic        active_render_period,
    output logic        coarse_x_increment_event,
    output logic        vertical_increment_event,
    output logic        horizontal_copy_event,
    output logic        vertical_copy_event,
    output logic        automatic_scroll_event,

    output logic [14:0] automatic_vram_address,
    output logic [14:0] active_data_increment_address,
    output logic [13:0] nametable_fetch_address,
    output logic [13:0] attribute_fetch_address
);
    function automatic logic [14:0] increment_coarse_x(
        input logic [14:0] address
    );
        logic [14:0] result;
        begin
            result = address;
            if (address[4:0] == 5'd31) begin
                result[4:0] = 5'd0;
                result[10] = ~address[10];
            end else begin
                result[4:0] = address[4:0] + 5'd1;
            end
            increment_coarse_x = result;
        end
    endfunction

    function automatic logic [14:0] increment_vertical(
        input logic [14:0] address
    );
        logic [14:0] result;
        begin
            result = address;
            if (address[14:12] != 3'd7) begin
                result[14:12] = address[14:12] + 3'd1;
            end else begin
                result[14:12] = 3'd0;
                case (address[9:5])
                    5'd29: begin
                        result[9:5] = 5'd0;
                        result[11] = ~address[11];
                    end
                    5'd31: result[9:5] = 5'd0;
                    default: result[9:5] = address[9:5] + 5'd1;
                endcase
            end
            increment_vertical = result;
        end
    endfunction

    always_comb begin
        rendering_scanline = scanline < 9'd240 || scanline == 9'd261;
        active_render_period = rendering_enabled && rendering_scanline;

        coarse_x_increment_event = ppu_enable && active_render_period &&
            (((dot >= 9'd8 && dot <= 9'd256) && dot[2:0] == 3'd0) ||
             dot == 9'd328 || dot == 9'd336);
        vertical_increment_event = ppu_enable && active_render_period &&
                                   dot == 9'd256;
        horizontal_copy_event = ppu_enable && active_render_period &&
                                dot == 9'd257;
        vertical_copy_event = ppu_enable && rendering_enabled &&
                              scanline == 9'd261 &&
                              dot >= 9'd280 && dot <= 9'd304;
        automatic_scroll_event = coarse_x_increment_event ||
                                 vertical_increment_event ||
                                 horizontal_copy_event ||
                                 vertical_copy_event;

        active_data_increment_address =
            increment_vertical(increment_coarse_x(vram_address));

        automatic_vram_address = vram_address;
        if (coarse_x_increment_event)
            automatic_vram_address =
                increment_coarse_x(automatic_vram_address);
        if (vertical_increment_event)
            automatic_vram_address =
                increment_vertical(automatic_vram_address);
        if (horizontal_copy_event) begin
            automatic_vram_address[4:0] = temp_vram_address[4:0];
            automatic_vram_address[10] = temp_vram_address[10];
        end
        if (vertical_copy_event) begin
            automatic_vram_address[9:5] = temp_vram_address[9:5];
            automatic_vram_address[11] = temp_vram_address[11];
            automatic_vram_address[14:12] = temp_vram_address[14:12];
        end

        nametable_fetch_address = 14'h2000 |
                                  (vram_address[13:0] & 14'h0fff);
        attribute_fetch_address = 14'h23c0 |
                                  (vram_address[13:0] & 14'h0c00) |
                                  ((vram_address[13:0] >> 4) & 14'h0038) |
                                  ((vram_address[13:0] >> 2) & 14'h0007);
    end
endmodule
