`timescale 1ns/1ps

module ppu_background_core (
    input  logic        clk,
    input  logic        reset,
    input  logic        ppu_enable,

    input  logic        cpu_enable,
    input  logic        cpu_bus_valid,
    input  logic        cpu_bus_write,
    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,
    output logic        cpu_register_selected,
    output logic [2:0]  cpu_register_index,

    input  logic        sprite_zero_hit_set,
    input  logic        sprite_overflow_set,
    input  logic [7:0]  oam_read_data,
    output logic [7:0]  oam_addr,
    output logic [7:0]  oam_write_data,
    output logic        oam_write_enable,

    input  logic [1:0]  mirroring_mode,
    output logic [12:0] chr_addr,
    output logic        chr_read,
    output logic        chr_write,
    output logic [7:0]  chr_write_data,
    input  logic [7:0]  chr_read_data,

    output logic [13:0] ppu_memory_address,
    output logic [13:0] ppu_memory_buffer_address,
    output logic        ppu_memory_read_request,
    output logic        ppu_memory_write_request,
    output logic [7:0]  ppu_memory_write_data,
    output logic [1:0]  memory_region,
    output logic [11:0] normalized_nametable_address,
    output logic [1:0]  logical_nametable,
    output logic [9:0]  nametable_offset,
    output logic        physical_ciram_page,
    output logic [10:0] ciram_address,
    output logic [4:0]  palette_index,
    output logic        ciram_write_enable,
    output logic        palette_write_enable,

    output logic [8:0]  dot,
    output logic [8:0]  scanline,
    output logic        frame_odd,
    output logic        visible_pixel,
    output logic [7:0]  pixel_x,
    output logic [7:0]  pixel_y,
    output logic        timing_vblank,
    output logic        frame_start,
    output logic        frame_end,
    output logic        scanline_start,
    output logic        vblank_start,
    output logic        vblank_end,
    output logic        pre_render,
    output logic        post_render,

    output logic [7:0]  ppuctrl,
    output logic [7:0]  ppumask,
    output logic        status_vblank,
    output logic        status_sprite_zero_hit,
    output logic        status_sprite_overflow,
    output logic [14:0] vram_address,
    output logic [14:0] temp_vram_address,
    output logic [2:0]  fine_x,
    output logic        write_toggle,
    output logic [7:0]  ppu_data_read_buffer,
    output logic [7:0]  ppu_io_latch,
    output logic        nmi_enable,
    output logic        ppu_master_slave,
    output logic        sprite_size_16,
    output logic        background_pattern_table,
    output logic        sprite_pattern_table,
    output logic [5:0]  vram_increment,
    output logic [1:0]  base_nametable,
    output logic        mask_grayscale,
    output logic        rendering_enabled,
    output logic        mask_show_background,
    output logic        mask_show_background_left,
    output logic        mask_show_sprites_left,
    output logic        mask_show_sprites,
    output logic        mask_emphasize_red,
    output logic        mask_emphasize_green,
    output logic        mask_emphasize_blue,
    output logic        rendering_scanline,
    output logic        active_render_period,
    output logic        coarse_x_increment_event,
    output logic        vertical_increment_event,
    output logic        horizontal_copy_event,
    output logic        vertical_copy_event,
    output logic        automatic_scroll_event,
    output logic [13:0] nametable_fetch_address,
    output logic [13:0] attribute_fetch_address,

    output logic        renderer_memory_request,
    output logic [13:0] renderer_memory_address,
    output logic        renderer_memory_grant,
    output logic        renderer_cpu_collision,
    input  logic        sprite_memory_request,
    input  logic [13:0] sprite_memory_address,
    output logic        sprite_memory_grant,
    output logic [7:0]  sprite_memory_read_data,
    output logic        renderer_owner_conflict,
    output logic [2:0]  background_fetch_phase,
    output logic [2:0]  background_fetch_type,
    output logic        background_fetch_complete,
    output logic        background_tile_load,
    output logic        background_shift,
    output logic [7:0]  next_tile_id,
    output logic [1:0]  next_tile_attribute,
    output logic [7:0]  next_tile_pattern_low,
    output logic [7:0]  next_tile_pattern_high,
    output logic [15:0] pattern_low_shift,
    output logic [15:0] pattern_high_shift,
    output logic [15:0] attribute_low_shift,
    output logic [15:0] attribute_high_shift,
    output logic        bg_pixel_valid,
    output logic [7:0]  bg_x,
    output logic [7:0]  bg_y,
    output logic [1:0]  bg_pattern,
    output logic [1:0]  bg_palette,
    output logic        bg_opaque,
    output logic [3:0]  bg_index
);
    logic [7:0] memory_read_data;
    logic [7:0] memory_buffer_read_data;
    logic cpu_memory_access;
    logic memory_access_valid;
    logic memory_access_write;
    logic [13:0] memory_access_address;
    logic [7:0] memory_access_write_data;
    logic background_memory_request;
    logic [13:0] background_memory_address;
    logic background_memory_grant;

    always_comb begin
        cpu_memory_access = ppu_memory_read_request ||
                            ppu_memory_write_request;
        renderer_memory_request = background_memory_request ||
                                  sprite_memory_request;
        // Preserve the Phase 3E observable address when neither renderer is
        // requesting.  The sprite address replaces it only while the sprite
        // client is the active renderer owner.
        renderer_memory_address = sprite_memory_request &&
                                  !background_memory_request ?
                                  sprite_memory_address :
                                  background_memory_address;
        renderer_memory_grant = renderer_memory_request &&
                                !cpu_memory_access;
        renderer_cpu_collision = renderer_memory_request &&
                                 cpu_memory_access;
        renderer_owner_conflict = background_memory_request &&
                                  sprite_memory_request;
        // Background wins only if a programming error creates overlap.  The
        // architectural windows are disjoint and the assertion below proves
        // this condition absent in normal operation.
        background_memory_grant = background_memory_request &&
                                  !cpu_memory_access;
        sprite_memory_grant = sprite_memory_request &&
                              !cpu_memory_access &&
                              !background_memory_request;
        sprite_memory_read_data = memory_read_data;

        memory_access_valid = cpu_memory_access || renderer_memory_request;
        memory_access_write = ppu_memory_write_request;
        memory_access_address = cpu_memory_access ? ppu_memory_address :
                                renderer_memory_address;
        memory_access_write_data = ppu_memory_write_data;
    end

    ppu_core core (
        .clk                         (clk),
        .reset                       (reset),
        .ppu_enable                  (ppu_enable),
        .cpu_enable                  (cpu_enable),
        .cpu_bus_valid               (cpu_bus_valid),
        .cpu_bus_write               (cpu_bus_write),
        .cpu_address                 (cpu_address),
        .cpu_write_data              (cpu_write_data),
        .cpu_read_data               (cpu_read_data),
        .cpu_register_selected       (cpu_register_selected),
        .cpu_register_index          (cpu_register_index),
        .sprite_zero_hit_set         (sprite_zero_hit_set),
        .sprite_overflow_set         (sprite_overflow_set),
        .oam_read_data               (oam_read_data),
        .oam_addr                    (oam_addr),
        .oam_write_data              (oam_write_data),
        .oam_write_enable            (oam_write_enable),
        .ppu_memory_read_data        (memory_read_data),
        .ppu_memory_buffer_read_data (memory_buffer_read_data),
        .ppu_memory_address          (ppu_memory_address),
        .ppu_memory_buffer_address   (ppu_memory_buffer_address),
        .ppu_memory_read_request     (ppu_memory_read_request),
        .ppu_memory_write_request    (ppu_memory_write_request),
        .ppu_memory_write_data       (ppu_memory_write_data),
        .dot                         (dot),
        .scanline                    (scanline),
        .frame_odd                   (frame_odd),
        .visible_pixel               (visible_pixel),
        .pixel_x                     (pixel_x),
        .pixel_y                     (pixel_y),
        .timing_vblank               (timing_vblank),
        .frame_start                 (frame_start),
        .frame_end                   (frame_end),
        .scanline_start              (scanline_start),
        .vblank_start                (vblank_start),
        .vblank_end                  (vblank_end),
        .pre_render                  (pre_render),
        .post_render                 (post_render),
        .ppuctrl                     (ppuctrl),
        .ppumask                     (ppumask),
        .status_vblank               (status_vblank),
        .status_sprite_zero_hit      (status_sprite_zero_hit),
        .status_sprite_overflow      (status_sprite_overflow),
        .vram_address                (vram_address),
        .temp_vram_address           (temp_vram_address),
        .fine_x                      (fine_x),
        .write_toggle                (write_toggle),
        .ppu_data_read_buffer        (ppu_data_read_buffer),
        .ppu_io_latch                (ppu_io_latch),
        .nmi_enable                  (nmi_enable),
        .ppu_master_slave            (ppu_master_slave),
        .sprite_size_16              (sprite_size_16),
        .background_pattern_table    (background_pattern_table),
        .sprite_pattern_table        (sprite_pattern_table),
        .vram_increment              (vram_increment),
        .base_nametable              (base_nametable),
        .mask_grayscale              (mask_grayscale),
        .mask_show_background_left   (mask_show_background_left),
        .mask_show_sprites_left      (mask_show_sprites_left),
        .mask_show_background        (mask_show_background),
        .mask_show_sprites           (mask_show_sprites),
        .mask_emphasize_red          (mask_emphasize_red),
        .mask_emphasize_green        (mask_emphasize_green),
        .mask_emphasize_blue         (mask_emphasize_blue),
        .rendering_enabled           (rendering_enabled),
        .rendering_scanline          (rendering_scanline),
        .active_render_period        (active_render_period),
        .coarse_x_increment_event    (coarse_x_increment_event),
        .vertical_increment_event    (vertical_increment_event),
        .horizontal_copy_event       (horizontal_copy_event),
        .vertical_copy_event         (vertical_copy_event),
        .automatic_scroll_event      (automatic_scroll_event),
        .nametable_fetch_address     (nametable_fetch_address),
        .attribute_fetch_address     (attribute_fetch_address)
    );

    ppu_background background (
        .clk                         (clk),
        .reset                       (reset),
        .ppu_enable                  (ppu_enable),
        .dot                         (dot),
        .scanline                    (scanline),
        .visible_pixel               (visible_pixel),
        .pixel_x                     (pixel_x),
        .pixel_y                     (pixel_y),
        .rendering_enabled           (rendering_enabled),
        .background_enabled          (mask_show_background),
        .show_background_left        (mask_show_background_left),
        .background_pattern_table    (background_pattern_table),
        .fine_x                      (fine_x),
        .fine_y                      (vram_address[14:12]),
        .coarse_x_bit_1              (vram_address[1]),
        .coarse_y_bit_1              (vram_address[6]),
        .nametable_fetch_address     (nametable_fetch_address),
        .attribute_fetch_address     (attribute_fetch_address),
        .renderer_memory_request     (background_memory_request),
        .renderer_memory_address     (background_memory_address),
        .renderer_memory_grant       (background_memory_grant),
        .renderer_memory_read_data   (memory_read_data),
        .fetch_phase                 (background_fetch_phase),
        .fetch_type                  (background_fetch_type),
        .fetch_complete_event        (background_fetch_complete),
        .tile_load_event             (background_tile_load),
        .shifter_shift_event         (background_shift),
        .next_tile_id                (next_tile_id),
        .next_tile_attribute         (next_tile_attribute),
        .next_tile_pattern_low       (next_tile_pattern_low),
        .next_tile_pattern_high      (next_tile_pattern_high),
        .pattern_low_shift           (pattern_low_shift),
        .pattern_high_shift          (pattern_high_shift),
        .attribute_low_shift         (attribute_low_shift),
        .attribute_high_shift        (attribute_high_shift),
        .bg_pixel_valid              (bg_pixel_valid),
        .bg_x                        (bg_x),
        .bg_y                        (bg_y),
        .bg_pattern                  (bg_pattern),
        .bg_palette                  (bg_palette),
        .bg_opaque                   (bg_opaque),
        .bg_index                    (bg_index)
    );

    ppu_memory memory (
        .clk                          (clk),
        .reset                        (reset),
        .mirroring_mode               (mirroring_mode),
        .access_valid                 (memory_access_valid),
        .access_write                 (memory_access_write),
        .access_address               (memory_access_address),
        .access_write_data            (memory_access_write_data),
        .access_read_data             (memory_read_data),
        .buffer_read_address          (ppu_memory_buffer_address),
        .buffer_read_data             (memory_buffer_read_data),
        .chr_addr                     (chr_addr),
        .chr_read                     (chr_read),
        .chr_write                    (chr_write),
        .chr_write_data               (chr_write_data),
        .chr_read_data                (chr_read_data),
        .access_region                (memory_region),
        .normalized_nametable_address (normalized_nametable_address),
        .logical_nametable            (logical_nametable),
        .nametable_offset             (nametable_offset),
        .physical_ciram_page          (physical_ciram_page),
        .ciram_address                (ciram_address),
        .palette_index                (palette_index),
        .ciram_write_enable           (ciram_write_enable),
        .palette_write_enable         (palette_write_enable)
    );

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset) begin
            assert (!renderer_owner_conflict);
            assert (!(memory_access_write && !cpu_memory_access));
            assert (!(background_memory_grant && sprite_memory_grant));
        end
    end
`endif
endmodule
