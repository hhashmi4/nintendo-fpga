`timescale 1ns/1ps

module ppu_registers (
    input  logic        clk,
    input  logic        reset,

    input  logic        ppu_enable,
    input  logic [8:0]  dot,
    input  logic [8:0]  scanline,

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
    output logic        ppu_nmi_level,
    output logic        ppu_nmi_event = 1'b0,
    output logic        ppu_nmi_suppressed = 1'b0,
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
    output logic        rendering_enabled,

    output logic        rendering_scanline,
    output logic        active_render_period,
    output logic        coarse_x_increment_event,
    output logic        vertical_increment_event,
    output logic        horizontal_copy_event,
    output logic        vertical_copy_event,
    output logic        automatic_scroll_event,
    output logic [13:0] nametable_fetch_address,
    output logic [13:0] attribute_fetch_address
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
    logic accepted_status_read;
    logic accepted_control_write;
    logic palette_access;
    logic [14:0] automatic_vram_address;
    logic [14:0] active_data_increment_address;
    logic suppress_next_vblank = 1'b0;
    logic nmi_activation_pending = 1'b0;
    logic vblank_set_allowed;
    logic next_status_vblank;
    logic next_nmi_enable;
    logic next_nmi_condition;
    logic ordinary_nmi_activation;
    logic immediate_nmi_activation;

    ppu_scroll scroll (
        .vram_address                 (vram_address),
        .temp_vram_address            (temp_vram_address),
        .ppu_enable                   (ppu_enable),
        .rendering_enabled            (rendering_enabled),
        .dot                          (dot),
        .scanline                     (scanline),
        .rendering_scanline           (rendering_scanline),
        .active_render_period         (active_render_period),
        .coarse_x_increment_event     (coarse_x_increment_event),
        .vertical_increment_event     (vertical_increment_event),
        .horizontal_copy_event        (horizontal_copy_event),
        .vertical_copy_event          (vertical_copy_event),
        .automatic_scroll_event       (automatic_scroll_event),
        .automatic_vram_address       (automatic_vram_address),
        .active_data_increment_address(active_data_increment_address),
        .nametable_fetch_address      (nametable_fetch_address),
        .attribute_fetch_address      (attribute_fetch_address)
    );

    always_comb begin
        cpu_register_selected = cpu_address >= 16'h2000 &&
                                cpu_address <= 16'h3fff;
        cpu_register_index = cpu_address[2:0];
        accepted_access = !reset && cpu_enable && cpu_bus_valid &&
                          cpu_register_selected;
        accepted_status_read = accepted_access && !cpu_bus_write &&
                               cpu_register_index == REG_PPUSTATUS;
        accepted_control_write = accepted_access && cpu_bus_write &&
                                 cpu_register_index == REG_PPUCTRL;

        ppu_memory_address = vram_address[13:0];
        palette_access = ppu_memory_address >= 14'h3f00;
        ppu_memory_buffer_address = palette_access ?
                                    ppu_memory_address - 14'h1000 :
                                    ppu_memory_address;

        nmi_enable = ppuctrl[7];
        ppu_nmi_level = status_vblank && nmi_enable;

        // The accepted CPU transaction and internal status events are reduced
        // to explicit next-state values here. This avoids relying on ordering
        // between nonblocking assignments for the VBlank/NMI boundary races.
        vblank_set_allowed = vblank_start_event &&
                             !accepted_status_read &&
                             !suppress_next_vblank;
        next_status_vblank = status_vblank;
        if (status_clear_event)
            next_status_vblank = 1'b0;
        else if (vblank_set_allowed)
            next_status_vblank = 1'b1;
        if (accepted_status_read)
            next_status_vblank = 1'b0;

        next_nmi_enable = accepted_control_write ?
                          cpu_write_data[7] : nmi_enable;
        next_nmi_condition = next_status_vblank && next_nmi_enable;

        // A VBlank-created activation is held for one enabled PPU tick so an
        // accepted $2002 read at 241:2 can model the documented short-pulse
        // suppression case. Enabling NMI during an established VBlank is not
        // delayed and creates an immediate event on its accepting fabric edge.
        ordinary_nmi_activation = vblank_set_allowed &&
                                  !ppu_nmi_level &&
                                  next_nmi_condition;
        immediate_nmi_activation = !vblank_start_event &&
                                   accepted_control_write &&
                                   !ppu_nmi_level &&
                                   next_nmi_condition;
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
            suppress_next_vblank       <= 1'b0;
            nmi_activation_pending     <= 1'b0;
            ppu_nmi_event              <= 1'b0;
            ppu_nmi_suppressed         <= 1'b0;
        end else begin
            // Event outputs are active-high one-fabric-clock pulses. Ordinary
            // VBlank activation waits through the next enabled PPU tick; CPU
            // register writes remain governed solely by cpu_enable.
            ppu_nmi_event      <= 1'b0;
            ppu_nmi_suppressed <= 1'b0;

            // A status read while the timing generator presents 241:0 blocks
            // the following 241:1 flag set. Reads at 241:1 block it directly.
            if (vblank_start_event)
                suppress_next_vblank <= 1'b0;
            else if (accepted_status_read &&
                     scanline == 9'd241 && dot == 9'd0)
                suppress_next_vblank <= 1'b1;

            if (vblank_start_event && !vblank_set_allowed &&
                next_nmi_enable)
                ppu_nmi_suppressed <= 1'b1;

            if (status_clear_event || accepted_status_read ||
                !next_nmi_condition) begin
                if (nmi_activation_pending && accepted_status_read)
                    ppu_nmi_suppressed <= 1'b1;
                nmi_activation_pending <= 1'b0;
            end else if (ordinary_nmi_activation) begin
                nmi_activation_pending <= 1'b1;
            end else if (immediate_nmi_activation) begin
                nmi_activation_pending <= 1'b0;
                ppu_nmi_event <= 1'b1;
            end else if (nmi_activation_pending && ppu_enable) begin
                nmi_activation_pending <= 1'b0;
                ppu_nmi_event <= 1'b1;
            end

            // Rendering-time scrolling and CPU programming share this one
            // sequential owner. Automatic operations consume the current PPU
            // coordinate. A same-edge second $2006 write or $2007 access below
            // has deterministic priority over this scheduled update.
            if (automatic_scroll_event)
                vram_address <= automatic_vram_address;

            // The pre-render clear has priority over future sprite event
            // inputs. Boundary suppression and an accepted status read have
            // explicit priority over the VBlank set.
            if (status_clear_event) begin
                status_vblank          <= 1'b0;
                status_sprite_zero_hit <= 1'b0;
                status_sprite_overflow <= 1'b0;
            end else begin
                if (vblank_set_allowed) status_vblank <= 1'b1;
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
                            vram_address <= active_render_period ?
                                active_data_increment_address :
                                vram_address + 15'(vram_increment);
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
                            vram_address <= active_render_period ?
                                active_data_increment_address :
                                vram_address + 15'(vram_increment);
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end

`ifdef VERILATOR
    logic nmi_event_seen_for_level = 1'b0;

    always_ff @(posedge clk) begin
        if (reset) begin
            nmi_event_seen_for_level <= 1'b0;
            assert (!ppu_nmi_event);
        end else begin
            assert (ppu_nmi_level == (status_vblank && nmi_enable));
            if (!ppu_nmi_level)
                nmi_event_seen_for_level <= 1'b0;
            if (ppu_nmi_event) begin
                assert (ppu_nmi_level);
                assert (!nmi_event_seen_for_level)
                    else $error("repeated NMI event while level stayed active");
                nmi_event_seen_for_level <= 1'b1;
            end
            if (ppu_nmi_suppressed)
                assert (!ppu_nmi_event);
        end
    end
`endif
endmodule
