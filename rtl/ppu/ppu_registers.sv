`timescale 1ns/1ps

module ppu_registers (
    input  logic        clk,
    input  logic        reset,

    input  logic        cpu_enable,
    input  logic        cpu_bus_valid,
    input  logic        cpu_bus_write,
    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,
    output logic        cpu_register_selected,
    output logic [2:0]  cpu_register_index,

    input  logic        vblank_start_event,
    input  logic        status_clear_event,
    input  logic        sprite_zero_hit_set,
    input  logic        sprite_overflow_set,

    input  logic [7:0]  oam_read_data,
    output logic [7:0]  oam_addr = 8'h00,
    output logic [7:0]  oam_write_data,
    output logic        oam_write_enable,

    input  logic [7:0]  ppu_memory_read_data,
    input  logic [7:0]  ppu_memory_buffer_read_data,
    output logic [13:0] ppu_memory_address,
    output logic [13:0] ppu_memory_buffer_address,
    output logic        ppu_memory_read_request,
    output logic        ppu_memory_write_request,
    output logic [7:0]  ppu_memory_write_data,

    output logic [7:0]  ppuctrl = 8'h00,
    output logic [7:0]  ppumask = 8'h00,
    output logic        status_vblank = 1'b0,
    output logic        status_sprite_zero_hit = 1'b0,
    output logic        status_sprite_overflow = 1'b0,
    output logic [14:0] vram_address = 15'h0000,
    output logic [14:0] temp_vram_address = 15'h0000,
    output logic [2:0]  fine_x = 3'h0,
    output logic        write_toggle = 1'b0,
    output logic [7:0]  ppu_data_read_buffer = 8'h00,
    output logic [7:0]  ppu_io_latch = 8'h00,

    output logic        nmi_enable,
    output logic        ppu_master_slave,
    output logic        sprite_size_16,
    output logic        background_pattern_table,
    output logic        sprite_pattern_table,
    output logic [5:0]  vram_increment,
    output logic [1:0]  base_nametable,
    output logic        mask_grayscale,
    output logic        mask_show_background_left,
    output logic        mask_show_sprites_left,
    output logic        mask_show_background,
    output logic        mask_show_sprites,
    output logic        mask_emphasize_red,
    output logic        mask_emphasize_green,
    output logic        mask_emphasize_blue,
    output logic        rendering_enabled
);
    localparam logic [2:0] REG_PPUCTRL   = 3'd0;
    localparam logic [2:0] REG_PPUMASK   = 3'd1;
    localparam logic [2:0] REG_PPUSTATUS = 3'd2;
    localparam logic [2:0] REG_OAMADDR   = 3'd3;
    localparam logic [2:0] REG_OAMDATA   = 3'd4;
    localparam logic [2:0] REG_PPUSCROLL = 3'd5;
    localparam logic [2:0] REG_PPUADDR   = 3'd6;
    localparam logic [2:0] REG_PPUDATA   = 3'd7;

    logic accepted_access;
    logic palette_access;

    always_comb begin
        cpu_register_selected = cpu_address >= 16'h2000 &&
                                cpu_address <= 16'h3fff;
        cpu_register_index = cpu_address[2:0];
        accepted_access = !reset && cpu_enable && cpu_bus_valid &&
                          cpu_register_selected;

        ppu_memory_address = vram_address[13:0];
        palette_access = ppu_memory_address >= 14'h3f00;
        ppu_memory_buffer_address = palette_access ?
                                    ppu_memory_address - 14'h1000 :
                                    ppu_memory_address;

        nmi_enable = ppuctrl[7];
        ppu_master_slave = ppuctrl[6];
        sprite_size_16 = ppuctrl[5];
        background_pattern_table = ppuctrl[4];
        sprite_pattern_table = ppuctrl[3];
        vram_increment = ppuctrl[2] ? 6'd32 : 6'd1;
        base_nametable = ppuctrl[1:0];

        mask_grayscale = ppumask[0];
        mask_show_background_left = ppumask[1];
        mask_show_sprites_left = ppumask[2];
        mask_show_background = ppumask[3];
        mask_show_sprites = ppumask[4];
        mask_emphasize_red = ppumask[5];
        mask_emphasize_green = ppumask[6];
        mask_emphasize_blue = ppumask[7];
        rendering_enabled = mask_show_background || mask_show_sprites;

        oam_write_data = cpu_write_data;
        oam_write_enable = accepted_access && cpu_bus_write &&
                           cpu_register_index == REG_OAMDATA;

        ppu_memory_read_request = accepted_access && !cpu_bus_write &&
                                  cpu_register_index == REG_PPUDATA;
        ppu_memory_write_request = accepted_access && cpu_bus_write &&
                                   cpu_register_index == REG_PPUDATA;
        ppu_memory_write_data = cpu_write_data;
    end

    // Keep the read-data mux separate from address/request generation. This
    // makes the external combinational memory contract explicit and avoids a
    // false address-to-data combinational loop in integrated lint analysis.
    always_comb begin
        cpu_read_data = ppu_io_latch;
        if (cpu_register_selected) begin
            case (cpu_register_index)
                REG_PPUSTATUS: cpu_read_data = {
                    status_vblank,
                    status_sprite_zero_hit,
                    status_sprite_overflow,
                    ppu_io_latch[4:0]
                };
                REG_OAMDATA: cpu_read_data = oam_read_data;
                REG_PPUDATA: cpu_read_data = palette_access ?
                                             ppu_memory_read_data :
                                             ppu_data_read_buffer;
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ppuctrl                    <= 8'h00;
            ppumask                    <= 8'h00;
            status_vblank              <= 1'b0;
            status_sprite_zero_hit     <= 1'b0;
            status_sprite_overflow     <= 1'b0;
            oam_addr                   <= 8'h00;
            vram_address               <= 15'h0000;
            temp_vram_address          <= 15'h0000;
            fine_x                     <= 3'h0;
            write_toggle               <= 1'b0;
            ppu_data_read_buffer       <= 8'h00;
            ppu_io_latch               <= 8'h00;
        end else begin
            // The pre-render clear has priority over future sprite event
            // inputs. A status read later in this block has priority over a
            // simultaneous vblank set; exact race behavior is deferred.
            if (status_clear_event) begin
                status_vblank          <= 1'b0;
                status_sprite_zero_hit <= 1'b0;
                status_sprite_overflow <= 1'b0;
            end else begin
                if (vblank_start_event) status_vblank <= 1'b1;
                if (sprite_zero_hit_set) status_sprite_zero_hit <= 1'b1;
                if (sprite_overflow_set) status_sprite_overflow <= 1'b1;
            end

            if (accepted_access) begin
                if (cpu_bus_write) begin
                    ppu_io_latch <= cpu_write_data;
                    case (cpu_register_index)
                        REG_PPUCTRL: begin
                            ppuctrl <= cpu_write_data;
                            temp_vram_address[11:10] <= cpu_write_data[1:0];
                        end
                        REG_PPUMASK: ppumask <= cpu_write_data;
                        REG_OAMADDR: oam_addr <= cpu_write_data;
                        REG_OAMDATA: oam_addr <= oam_addr + 8'd1;
                        REG_PPUSCROLL: begin
                            if (!write_toggle) begin
                                temp_vram_address[4:0] <= cpu_write_data[7:3];
                                fine_x <= cpu_write_data[2:0];
                                write_toggle <= 1'b1;
                            end else begin
                                temp_vram_address[9:5] <= cpu_write_data[7:3];
                                temp_vram_address[14:12] <= cpu_write_data[2:0];
                                write_toggle <= 1'b0;
                            end
                        end
                        REG_PPUADDR: begin
                            if (!write_toggle) begin
                                temp_vram_address[13:8] <= cpu_write_data[5:0];
                                temp_vram_address[14] <= 1'b0;
                                write_toggle <= 1'b1;
                            end else begin
                                temp_vram_address[7:0] <= cpu_write_data;
                                vram_address <= {
                                    temp_vram_address[14:8], cpu_write_data
                                };
                                write_toggle <= 1'b0;
                            end
                        end
                        REG_PPUDATA: begin
                            vram_address <= vram_address +
                                            15'(vram_increment);
                        end
                        default: begin end
                    endcase
                end else begin
                    case (cpu_register_index)
                        REG_PPUSTATUS: begin
                            ppu_io_latch <= cpu_read_data;
                            status_vblank <= 1'b0;
                            write_toggle <= 1'b0;
                        end
                        REG_OAMDATA: ppu_io_latch <= cpu_read_data;
                        REG_PPUDATA: begin
                            ppu_io_latch <= cpu_read_data;
                            ppu_data_read_buffer <= palette_access ?
                                ppu_memory_buffer_read_data :
                                ppu_memory_read_data;
                            vram_address <= vram_address +
                                            15'(vram_increment);
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
