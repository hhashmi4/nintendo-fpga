`timescale 1ns/1ps

module ppu_phase3f_tb;
    logic [13:0] unused_phase7a_mapper_ppu_address_0;
    logic unused_phase7a_mapper_ppu_read_1;
    logic unused_phase7a_mapper_ppu_write_2;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic cpu_enable;
    logic cpu_bus_valid;
    logic cpu_bus_write;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [7:0] cpu_read_data;
    logic cpu_register_selected;
    logic [2:0] cpu_register_index;
    logic [7:0] oam_addr;
    logic [7:0] oam_write_data;
    logic oam_write_enable;
    logic [1:0] mirroring_mode;
    logic [12:0] chr_addr;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;
    logic [13:0] ppu_memory_address;
    logic [13:0] ppu_memory_buffer_address;
    logic ppu_memory_read_request;
    logic ppu_memory_write_request;
    logic [7:0] ppu_memory_write_data;
    logic [1:0] memory_region;
    logic [11:0] normalized_nametable_address;
    logic [1:0] logical_nametable;
    logic [9:0] nametable_offset;
    logic physical_ciram_page;
    logic [10:0] ciram_address;
    logic [4:0] palette_index;
    logic ciram_write_enable;
    logic palette_write_enable;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic frame_odd;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic timing_vblank;
    logic frame_start;
    logic frame_end;
    logic scanline_start;
    logic vblank_start;
    logic vblank_end;
    logic pre_render;
    logic post_render;
    logic [7:0] ppuctrl;
    logic [7:0] ppumask;
    logic status_vblank;
    logic status_sprite_zero_hit;
    logic status_sprite_overflow;
    logic [14:0] vram_address;
    logic [14:0] temp_vram_address;
    logic [2:0] fine_x;
    logic write_toggle;
    logic [7:0] ppu_data_read_buffer;
    logic [7:0] ppu_io_latch;
    logic nmi_enable;
    /* verilator lint_off UNUSEDSIGNAL */
    logic ppu_nmi_level;
    logic ppu_nmi_event;
    logic ppu_nmi_suppressed;
    /* verilator lint_on UNUSEDSIGNAL */
    logic ppu_master_slave;
    logic sprite_size_16;
    logic background_pattern_table;
    logic sprite_pattern_table;
    logic [5:0] vram_increment;
    logic [1:0] base_nametable;
    logic mask_grayscale;
    logic rendering_enabled;
    logic mask_show_background;
    logic mask_show_background_left;
    logic mask_show_sprites_left;
    logic mask_show_sprites;
    logic mask_emphasize_red;
    logic mask_emphasize_green;
    logic mask_emphasize_blue;
    logic rendering_scanline;
    logic active_render_period;
    logic coarse_x_increment_event;
    logic vertical_increment_event;
    logic horizontal_copy_event;
    logic vertical_copy_event;
    logic automatic_scroll_event;
    logic [13:0] nametable_fetch_address;
    logic [13:0] attribute_fetch_address;
    logic renderer_memory_request;
    logic [13:0] renderer_memory_address;
    logic renderer_memory_grant;
    logic renderer_cpu_collision;
    logic sprite_memory_request;
    logic [13:0] sprite_memory_address;
    logic sprite_memory_grant;
    logic [7:0] sprite_memory_read_data;
    logic renderer_owner_conflict;
    logic [2:0] background_fetch_phase;
    logic [2:0] background_fetch_type;
    logic background_fetch_complete;
    logic background_tile_load;
    logic background_shift;
    logic [7:0] next_tile_id;
    logic [1:0] next_tile_attribute;
    logic [7:0] next_tile_pattern_low;
    logic [7:0] next_tile_pattern_high;
    logic [15:0] pattern_low_shift;
    logic [15:0] pattern_high_shift;
    logic [15:0] attribute_low_shift;
    logic [15:0] attribute_high_shift;
    logic bg_pixel_valid;
    logic [7:0] bg_x;
    logic [7:0] bg_y;
    logic [1:0] bg_pattern;
    logic [1:0] bg_palette;
    logic bg_opaque;
    logic [3:0] bg_index;
    logic [2:0] sprite_fetch_slot;
    logic [2:0] sprite_fetch_phase;
    logic [2:0] sprite_fetch_type;
    logic sprite_fetch_complete;
    logic sprite_slot_load;
    logic [3:0] sprite_fetch_relative_row;
    logic [3:0] sprite_fetch_selected_row;
    logic [12:0] sprite_pattern_low_address;
    logic [12:0] sprite_pattern_high_address;
    logic [7:0] sprite_decrement_mask;
    logic [7:0] sprite_shift_mask;
    logic sprite_pixel_valid;
    logic [7:0] sprite_x;
    logic [7:0] sprite_y;
    logic [1:0] sprite_pattern;
    logic [1:0] sprite_palette;
    logic [3:0] sprite_palette_index;
    logic sprite_opaque;
    logic sprite_priority_behind_background;
    logic sprite_is_zero;
    logic [2:0] sprite_slot;
    logic [5:0] sprite_original_index;
    logic final_pixel_valid;
    logic [7:0] final_pixel_x;
    logic [7:0] final_pixel_y;
    logic [13:0] final_palette_address;
    logic [5:0] final_nes_color;
    logic [2:0] final_color_emphasis;
    logic [1:0] final_pixel_source;
    logic sprite_zero_hit_event;
    logic [2:0] final_winning_sprite_slot;
    logic final_winning_sprite_zero;
    logic [2:0] secondary_read_slot;
    logic [7:0] secondary_read_y;
    logic [7:0] secondary_read_tile;
    logic [7:0] secondary_read_attributes;
    logic [7:0] secondary_read_x;
    logic [5:0] secondary_read_sprite_index;
    logic secondary_read_valid;
    logic [3:0] selected_sprite_count;
    logic sprite_zero_in_secondary;
    logic sprite_overflow_set;
    logic [2:0] sprite_evaluation_phase;
    logic [5:0] sprite_evaluation_index;
    logic [1:0] sprite_evaluation_byte;
    logic [7:0] sprite_evaluation_relative_row;
    logic [4:0] sprite_height;
    logic [7:0] primary_oam_read_address;
    logic [7:0] primary_oam_read_data;
    logic secondary_clear_write;
    logic secondary_evaluation_write;
    logic [4:0] secondary_write_address;
    logic [7:0] secondary_write_data;
    logic sprite_evaluation_done;
    logic cpu_oam_write_commit;
    logic cpu_oam_collision;

    logic [7:0] chr_memory [0:8191];
    int vector_file;
    int scan_result;
    int values [0:46];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:5];
    int unsigned ppu_ticks = 0;
    int unsigned ppu_stalls = 0;
    int unsigned accepted = 0;
    int unsigned oam_transactions = 0;
    int unsigned oam_reads = 0;
    int unsigned oam_writes = 0;
    int unsigned oam_commits = 0;
    int unsigned collisions = 0;
    int unsigned clear_writes = 0;
    int unsigned secondary_writes = 0;
    int unsigned evaluated_y = 0;
    int unsigned sprites_selected = 0;
    int unsigned overflow_sets = 0;
    int unsigned sprite_zero_selections = 0;
    int unsigned visible_lines = 0;
    int unsigned frames = 0;

    logic [8:0] old_dot;
    logic [8:0] old_scanline;
    logic old_frame_odd;
    logic [3:0] old_selected_count;
    logic old_sprite_zero;
    logic [2:0] old_phase;
    logic [5:0] old_n;
    logic [1:0] old_m;
    logic old_done;
    logic retained_observation_parity;

    ppu_sprite_core dut (
        .mapper_ppu_address(unused_phase7a_mapper_ppu_address_0),
        .mapper_ppu_read(unused_phase7a_mapper_ppu_read_1),
        .mapper_ppu_write(unused_phase7a_mapper_ppu_write_2),
        .*
    );
    assign chr_read_data = chr_memory[chr_addr];
    always #5 clk <= !clk;
    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    // Consume and sanity-check every retained Phase 3A-3E observation port.
    // The Phase 3F wrapper deliberately keeps these interfaces intact.
    assign retained_observation_parity = ^{
        oam_write_data, chr_read, ppu_memory_address,
        ppu_memory_buffer_address, ppu_memory_read_request,
        ppu_memory_write_request, ppu_memory_write_data, memory_region,
        normalized_nametable_address, logical_nametable, nametable_offset,
        physical_ciram_page, ciram_address, palette_index,
        ciram_write_enable, palette_write_enable, visible_pixel, pixel_x,
        pixel_y, timing_vblank, frame_start, frame_end, scanline_start,
        vblank_start, vblank_end, pre_render, post_render, status_vblank,
        status_sprite_zero_hit, vram_address, temp_vram_address, fine_x,
        write_toggle, ppu_data_read_buffer, nmi_enable, ppu_master_slave,
        sprite_size_16, background_pattern_table, sprite_pattern_table,
        vram_increment, base_nametable, mask_grayscale,
        mask_show_background, mask_show_background_left,
        mask_show_sprites_left, mask_show_sprites, mask_emphasize_red,
        mask_emphasize_green, mask_emphasize_blue, rendering_scanline,
        active_render_period, coarse_x_increment_event,
        vertical_increment_event, horizontal_copy_event,
        vertical_copy_event, automatic_scroll_event,
        nametable_fetch_address, attribute_fetch_address,
        renderer_memory_request, renderer_memory_address,
        renderer_memory_grant, renderer_cpu_collision,
        sprite_memory_request, sprite_memory_address,
        sprite_memory_grant, sprite_memory_read_data,
        renderer_owner_conflict,
        background_fetch_phase, background_fetch_type,
        background_fetch_complete, background_tile_load, background_shift,
        next_tile_id, next_tile_attribute, next_tile_pattern_low,
        next_tile_pattern_high, pattern_low_shift, pattern_high_shift,
        attribute_low_shift, attribute_high_shift, bg_pixel_valid, bg_x,
        bg_y, bg_pattern, bg_palette, bg_opaque, bg_index,
        sprite_fetch_slot, sprite_fetch_phase, sprite_fetch_type,
        sprite_fetch_complete, sprite_slot_load,
        sprite_fetch_relative_row, sprite_fetch_selected_row,
        sprite_pattern_low_address, sprite_pattern_high_address,
        sprite_decrement_mask, sprite_shift_mask, sprite_pixel_valid,
        sprite_x, sprite_y, sprite_pattern, sprite_palette,
        sprite_palette_index, sprite_opaque,
        sprite_priority_behind_background, sprite_is_zero, sprite_slot,
        sprite_original_index, final_pixel_valid, final_pixel_x,
        final_pixel_y, final_palette_address, final_nes_color,
        final_color_emphasis, final_pixel_source, sprite_zero_hit_event,
        final_winning_sprite_slot, final_winning_sprite_zero,
        sprite_evaluation_relative_row, sprite_height
    };

    task automatic check_pre_edge;
        begin
            assert (!$isunknown({dot, scanline, frame_odd, cpu_read_data,
                                 cpu_register_selected, cpu_register_index,
                                 oam_addr, oam_write_enable,
                                 cpu_oam_write_commit, cpu_oam_collision,
                                 primary_oam_read_address,
                                 primary_oam_read_data,
                                 secondary_clear_write,
                                 secondary_evaluation_write,
                                 secondary_write_address,
                                 secondary_write_data}));
            assert (!$isunknown(retained_observation_parity));
            assert (int'(dot) == values[10]);
            assert (int'(scanline) == values[11]);
            assert (int'(frame_odd) == values[12]);
            assert (int'(cpu_register_selected) == values[13]);
            assert (int'(cpu_register_index) == values[14]);
            assert (int'(cpu_read_data) == values[15])
                else $fatal(1,
                    "CPU read mismatch row=%0d addr=%04x actual=%02x expected=%02x",
                    rows + 1, cpu_address, cpu_read_data, values[15]);
            assert (int'(oam_addr) == values[16]);
            assert (int'(oam_write_enable) == values[17]);
            assert (int'(cpu_oam_write_commit) == values[18]);
            assert (int'(cpu_oam_collision) == values[19]);
            assert (int'(primary_oam_read_address) == values[20]);
            assert (int'(primary_oam_read_data) == values[21]);
            assert (int'(secondary_clear_write) == values[22]);
            assert (int'(secondary_evaluation_write) == values[23]);
            assert (int'(secondary_write_address) == values[24]);
            assert (int'(secondary_write_data) == values[25]);

            assert (!cpu_oam_write_commit || !cpu_oam_collision);
            assert (!(secondary_clear_write && secondary_evaluation_write));
            assert (selected_sprite_count <= 8);
            if (secondary_clear_write) begin
                assert (scanline < 240 && dot >= 2 && dot <= 64);
                assert (!dot[0] && secondary_write_data == 8'hff);
            end
            if (secondary_evaluation_write) begin
                assert (scanline < 240 && dot >= 66 && dot <= 256);
                assert (!dot[0] && rendering_enabled);
            end
            if (!ppu_enable) begin
                assert (!secondary_clear_write);
                assert (!secondary_evaluation_write);
            end
            if (cpu_oam_collision)
                assert (rendering_enabled &&
                        (scanline < 240 || scanline == 261));
        end
    endtask

    task automatic check_post_edge;
        begin
            assert (!$isunknown({dot, scanline, frame_odd, ppuctrl, ppumask,
                                 oam_addr, ppu_io_latch,
                                 status_sprite_overflow,
                                 selected_sprite_count,
                                 sprite_zero_in_secondary,
                                 sprite_overflow_set,
                                 sprite_evaluation_phase,
                                 sprite_evaluation_index,
                                 sprite_evaluation_byte,
                                 sprite_evaluation_done,
                                 secondary_read_y, secondary_read_tile,
                                 secondary_read_attributes, secondary_read_x,
                                 secondary_read_sprite_index,
                                 secondary_read_valid}));
            assert (int'(status_sprite_overflow) == values[26]);
            assert (int'(dot) == values[27]);
            assert (int'(scanline) == values[28]);
            assert (int'(frame_odd) == values[29]);
            assert (int'(ppuctrl) == values[30]);
            assert (int'(ppumask) == values[31]);
            assert (int'(oam_addr) == values[32]);
            assert (int'(ppu_io_latch) == values[33]);
            assert (int'(selected_sprite_count) == values[34]);
            assert (int'(sprite_zero_in_secondary) == values[35]);
            assert (int'(sprite_overflow_set) == values[36]);
            assert (int'(sprite_evaluation_phase) == values[37]);
            assert (int'(sprite_evaluation_index) == values[38]);
            assert (int'(sprite_evaluation_byte) == values[39]);
            assert (int'(sprite_evaluation_done) == values[40]);
            assert (int'(secondary_read_y) == values[41]);
            assert (int'(secondary_read_tile) == values[42]);
            assert (int'(secondary_read_attributes) == values[43]);
            assert (int'(secondary_read_x) == values[44]);
            assert (int'(secondary_read_sprite_index) == values[45]);
            assert (int'(secondary_read_valid) == values[46]);

            if (!reset && !ppu_enable) begin
                assert (dot == old_dot && scanline == old_scanline);
                assert (frame_odd == old_frame_odd);
                assert (selected_sprite_count == old_selected_count);
                assert (sprite_zero_in_secondary == old_sprite_zero);
                assert (sprite_evaluation_phase == old_phase);
                assert (sprite_evaluation_index == old_n);
                assert (sprite_evaluation_byte == old_m);
                assert (sprite_evaluation_done == old_done);
            end
            if (cpu_oam_write_commit)
                assert (dut.oam.primary_oam[values[16][7:0]] ==
                        cpu_write_data);
            if (sprite_zero_in_secondary)
                assert (dut.oam.secondary_sprite_index[0] == 0);
            if (old_scanline == 261 && old_dot == 1 && ppu_enable)
                assert (!status_sprite_overflow);
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3f.fst");
        $dumpvars(1, ppu_phase3f_tb);
        for (int index = 0; index < 8192; index++) chr_memory[index] = 8'h00;
        for (int index = 0; index < 2048; index++)
            dut.background_core.memory.ciram[index] = 8'h00;
        for (int index = 0; index < 32; index++) begin
            dut.background_core.memory.palette_ram[index] = 8'h00;
            dut.oam.secondary_oam[index] = 8'h00;
        end
        for (int index = 0; index < 256; index++)
            dut.oam.primary_oam[index] = 8'h00;
        for (int index = 0; index < 8; index++)
            dut.oam.secondary_sprite_index[index] = 6'd0;
        for (int index = 1; index <= 5; index++) scenario_counts[index] = 0;

        vector_file = $fopen("build/sim/ppu_phase3f_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3F integration vectors");
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37], values[38], values[39],
                values[40], values[41], values[42], values[43], values[44],
                values[45], values[46]
            );
            if (scan_result == 47) begin
                @(negedge clk);
                reset = values[1][0];
                ppu_enable = values[2][0];
                cpu_enable = values[3][0];
                cpu_bus_valid = values[4][0];
                cpu_bus_write = values[5][0];
                cpu_address = values[6][15:0];
                cpu_write_data = values[7][7:0];
                mirroring_mode = values[8][1:0];
                secondary_read_slot = values[9][2:0];
                #1;
                check_pre_edge();

                old_dot = dot;
                old_scanline = scanline;
                old_frame_odd = frame_odd;
                old_selected_count = selected_sprite_count;
                old_sprite_zero = sprite_zero_in_secondary;
                old_phase = sprite_evaluation_phase;
                old_n = sprite_evaluation_index;
                old_m = sprite_evaluation_byte;
                old_done = sprite_evaluation_done;

                rows++;
                scenario_counts[values[0]]++;
                ppu_ticks += int'(ppu_enable && !reset);
                ppu_stalls += int'(!ppu_enable && !reset);
                accepted += int'(!reset && cpu_enable && cpu_bus_valid &&
                                 cpu_register_selected);
                if (!reset && cpu_enable && cpu_bus_valid &&
                    cpu_register_selected && cpu_register_index == 4) begin
                    oam_transactions++;
                    if (cpu_bus_write) oam_writes++;
                    else oam_reads++;
                end
                oam_commits += int'(cpu_oam_write_commit);
                collisions += int'(cpu_oam_collision);
                clear_writes += int'(secondary_clear_write);
                secondary_writes += int'(secondary_evaluation_write);
                if (ppu_enable && dot >= 65 && dot <= 256 && !dot[0] &&
                    (sprite_evaluation_phase == 2 ||
                     sprite_evaluation_phase == 4))
                    evaluated_y++;
                if (ppu_enable && dot == 1 && scanline < 240 &&
                    rendering_enabled)
                    visible_lines++;

                @(posedge clk);
                #1;
                frames += int'(!reset && frame_odd != old_frame_odd);
                overflow_sets += int'(sprite_overflow_set);
                if (!old_sprite_zero && sprite_zero_in_secondary)
                    sprite_zero_selections++;
                if (selected_sprite_count > old_selected_count)
                    sprites_selected += int'(selected_sprite_count) -
                                        int'(old_selected_count);
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 3F vector after row %0d", rows);
            end
        end
        $fclose(vector_file);

        assert (scenario_counts[4] == 220_273);
        assert (scenario_counts[5] == 268_851);
        assert (visible_lines == 1_273);
        assert (frames == 4);
        $display(
            "PASS: integrated Phase 3F rows=%0d ticks=%0d stalls=%0d accepted=%0d oam_transactions=%0d reads=%0d writes=%0d commits=%0d collisions=%0d clears=%0d secondary_writes=%0d evaluated_y=%0d selected=%0d overflow_sets=%0d sprite_zero=%0d visible_lines=%0d frames=%0d mismatches=0 seed=3f200401",
            rows, ppu_ticks, ppu_stalls, accepted, oam_transactions,
            oam_reads, oam_writes, oam_commits, collisions, clear_writes,
            secondary_writes, evaluated_y, sprites_selected, overflow_sets,
            sprite_zero_selections, visible_lines, frames
        );
        $finish;
    end
endmodule
