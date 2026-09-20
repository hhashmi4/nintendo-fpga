`timescale 1ns/1ps

module ppu_phase3e_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ppu_enable = 1'b0;
    logic cpu_enable = 1'b0;
    logic cpu_bus_valid = 1'b0;
    logic cpu_bus_write = 1'b0;
    logic [15:0] cpu_address = 16'h0000;
    logic [7:0] cpu_write_data = 8'h00;
    logic [7:0] cpu_read_data;
    logic cpu_register_selected;
    logic [2:0] cpu_register_index;
    logic sprite_zero_hit_set = 1'b0;
    logic sprite_overflow_set = 1'b0;
    logic [7:0] oam_read_data = 8'h00;
    logic [7:0] oam_addr;
    logic [7:0] oam_write_data;
    logic oam_write_enable;
    logic [1:0] mirroring_mode = 2'd0;
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
    logic [13:0] pixel_palette_address = 14'h3f00;
    logic [7:0] pixel_palette_read_data;
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
    logic sprite_memory_request = 1'b0;
    logic [13:0] sprite_memory_address = 14'h0000;
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

    logic [7:0] chr_memory [0:8191];
    int vector_file;
    int trace_file;
    int scan_result;
    int values [0:71];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:5];
    int unsigned ppu_ticks = 0;
    int unsigned ppu_stalls = 0;
    int unsigned accepted_count = 0;
    int unsigned collision_count = 0;
    int unsigned fetch_counts [0:5];
    int unsigned tile_loads = 0;
    int unsigned shifts = 0;
    int unsigned full_frame_pixels = 0;
    int unsigned first_scanline_pixels = 0;
    int unsigned scroll_pixels = 0;
    int unsigned frame_count = 0;
    int unsigned random_ticks = 0;
    int unsigned random_stalls = 0;
    int unsigned random_accepted = 0;
    int unsigned random_collisions = 0;
    int unsigned random_fetches [0:5];
    int unsigned random_loads = 0;
    int unsigned random_shifts = 0;
    int unsigned random_pixels = 0;

    logic [8:0] old_dot;
    logic [8:0] old_scanline;
    logic old_frame_odd;
    logic [7:0] old_next_tile_id;
    logic [1:0] old_next_tile_attribute;
    logic [7:0] old_next_tile_pattern_low;
    logic [7:0] old_next_tile_pattern_high;
    logic [15:0] old_pattern_low_shift;
    logic [15:0] old_pattern_high_shift;
    logic [15:0] old_attribute_low_shift;
    logic [15:0] old_attribute_high_shift;

    ppu_background_core dut (.*);
    assign chr_read_data = chr_memory[chr_addr];
    always #5 clk <= !clk;
    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    task automatic check_pre_edge;
        int write_destinations;
        begin
            assert (!$isunknown({cpu_read_data, cpu_register_selected,
                                 cpu_register_index, ppu_memory_address,
                                 ppu_memory_buffer_address,
                                 ppu_memory_read_request,
                                 ppu_memory_write_request,
                                 renderer_memory_request,
                                 renderer_memory_address,
                                 renderer_memory_grant,
                                 renderer_cpu_collision,
                                 sprite_memory_grant,
                                 sprite_memory_read_data,
                                 renderer_owner_conflict,
                                 memory_region, chr_addr, chr_read, chr_write,
                                 ciram_write_enable, palette_write_enable,
                                 dot, scanline, frame_odd, vram_address,
                                 temp_vram_address, fine_x, ppuctrl, ppumask,
                                 rendering_enabled, background_fetch_phase,
                                 background_fetch_type,
                                 background_fetch_complete,
                                 background_tile_load, background_shift,
                                 bg_pixel_valid, bg_x, bg_y, bg_pattern,
                                 bg_palette, bg_opaque, bg_index,
                                 nametable_fetch_address,
                                 attribute_fetch_address, next_tile_id,
                                 oam_addr, oam_write_data, oam_write_enable,
                                 normalized_nametable_address,
                                 logical_nametable, nametable_offset,
                                 physical_ciram_page, ciram_address,
                                 palette_index, pixel_y, timing_vblank,
                                 pixel_palette_read_data,
                                 frame_start, scanline_start, vblank_start,
                                 vblank_end, pre_render, post_render,
                                 status_sprite_zero_hit,
                                 status_sprite_overflow, nmi_enable,
                                 ppu_master_slave, sprite_size_16,
                                 background_pattern_table,
                                 sprite_pattern_table, vram_increment,
                                 base_nametable, mask_grayscale,
                                 mask_show_sprites_left, mask_show_sprites,
                                 mask_emphasize_red, mask_emphasize_green,
                                 mask_emphasize_blue, active_render_period,
                                 coarse_x_increment_event,
                                 vertical_increment_event,
                                 horizontal_copy_event, vertical_copy_event,
                                 automatic_scroll_event}));

            assert (int'(cpu_register_selected) == values[9]);
            assert (int'(cpu_register_index) == values[10]);
            assert (int'(cpu_read_data) == values[11]);
            assert (int'(ppu_memory_address) == values[12]);
            assert (int'(ppu_memory_buffer_address) == values[13]);
            assert (int'(ppu_memory_read_request) == values[14]);
            assert (int'(ppu_memory_write_request) == values[15]);
            assert (int'(renderer_memory_request) == values[16]);
            assert (int'(renderer_memory_address) == values[17]);
            assert (int'(renderer_memory_grant) == values[18]);
            assert (int'(renderer_cpu_collision) == values[19]);
            assert (int'(dut.memory_access_address) == values[20]);
            assert (int'(dut.memory_read_data) == values[21]);
            assert (int'(memory_region) == values[22]);
            assert (int'(chr_addr) == values[23]);
            assert (int'(chr_read) == values[24]);
            assert (int'(chr_write) == values[25]);
            assert (int'(ciram_write_enable) == values[26]);
            assert (int'(palette_write_enable) == values[27]);
            assert (int'(dot) == values[28]);
            assert (int'(scanline) == values[29]);
            assert (int'(frame_odd) == values[30]);
            assert (int'(vram_address) == values[31]);
            assert (int'(temp_vram_address) == values[32]);
            assert (int'(fine_x) == values[33]);
            assert (int'(ppuctrl) == values[34]);
            assert (int'(ppumask) == values[35]);
            assert (int'(rendering_enabled) == values[36]);
            assert (int'(background_fetch_phase) == values[37]);
            assert (int'(background_fetch_type) == values[38]);
            assert (int'(background_fetch_complete) == values[39]);
            assert (int'(background_tile_load) == values[40]);
            assert (int'(background_shift) == values[41]);
            assert (int'(bg_pixel_valid) == values[42]);
            assert (int'(bg_x) == values[43]);
            assert (int'(bg_y) == values[44]);
            assert (int'(bg_pattern) == values[45]);
            assert (int'(bg_palette) == values[46]);
            assert (int'(bg_opaque) == values[47]);
            assert (int'(bg_index) == values[48]);
            assert (int'(nametable_fetch_address) == values[49]);
            assert (int'(attribute_fetch_address) == values[50]);
            assert (int'(next_tile_id) == values[51]);

            assert (renderer_memory_grant ==
                    (renderer_memory_request &&
                     !ppu_memory_read_request && !ppu_memory_write_request));
            assert (renderer_cpu_collision ==
                    (renderer_memory_request &&
                     (ppu_memory_read_request || ppu_memory_write_request)));
            assert (!renderer_memory_grant || !renderer_cpu_collision);
            if (!ppu_enable) begin
                assert (!renderer_memory_request);
                assert (!background_fetch_complete);
                assert (!background_tile_load && !background_shift);
            end
            if (renderer_memory_request) begin
                assert (rendering_enabled && rendering_scanline);
                assert ((dot >= 1 && dot <= 256) ||
                        (dot >= 321 && dot <= 340));
            end
            if (background_fetch_type == 3 || background_fetch_type == 4)
                assert (renderer_memory_address < 14'h2000);
            if (background_fetch_type == 1 || background_fetch_type == 5)
                assert (renderer_memory_address >= 14'h2000 &&
                        renderer_memory_address < 14'h3000);
            if (background_fetch_type == 2)
                assert ((renderer_memory_address & 14'h03c0) == 14'h03c0);
            if (background_tile_load)
                assert (((dot >= 8 && dot <= 256) ||
                         dot == 328 || dot == 336) && dot[2:0] == 0);

            assert (bg_pixel_valid == visible_pixel);
            assert (bg_opaque == (bg_pattern != 0));
            if (bg_opaque) begin
                assert (bg_palette <= 3);
                assert (bg_index == {bg_palette, bg_pattern});
            end else begin
                assert (bg_index == 0);
            end
            if (!mask_show_background ||
                (visible_pixel && pixel_x < 8 &&
                 !mask_show_background_left)) begin
                assert (!bg_opaque && bg_pattern == 0 && bg_palette == 0);
            end

            write_destinations = int'(chr_write) +
                                 int'(ciram_write_enable) +
                                 int'(palette_write_enable);
            assert (write_destinations == int'(ppu_memory_write_request));
            assert (!chr_write || !renderer_memory_grant);
            assert (!ppu_memory_read_request || !ppu_memory_write_request);
            assert (ppu_memory_write_data == cpu_write_data);
            assert (chr_write_data == cpu_write_data);
        end
    endtask

    task automatic check_post_edge;
        begin
            assert (int'(dot) == values[52]);
            assert (int'(scanline) == values[53]);
            assert (int'(frame_odd) == values[54]);
            assert (int'(vram_address) == values[55]);
            assert (int'(temp_vram_address) == values[56]);
            assert (int'(fine_x) == values[57]);
            assert (int'(write_toggle) == values[58]);
            assert (int'(ppuctrl) == values[59]);
            assert (int'(ppumask) == values[60]);
            assert (int'(next_tile_id) == values[61]);
            assert (int'(next_tile_attribute) == values[62]);
            assert (int'(next_tile_pattern_low) == values[63]);
            assert (int'(next_tile_pattern_high) == values[64]);
            assert (int'(pattern_low_shift) == values[65]);
            assert (int'(pattern_high_shift) == values[66]);
            assert (int'(attribute_low_shift) == values[67]);
            assert (int'(attribute_high_shift) == values[68]);
            assert (int'(ppu_data_read_buffer) == values[69]);
            assert (int'(ppu_io_latch) == values[70]);
            assert (int'(status_vblank) == values[71]);

            if (!reset && !ppu_enable) begin
                assert (dot == old_dot && scanline == old_scanline &&
                        frame_odd == old_frame_odd);
                assert (next_tile_id == old_next_tile_id);
                assert (next_tile_attribute == old_next_tile_attribute);
                assert (next_tile_pattern_low == old_next_tile_pattern_low);
                assert (next_tile_pattern_high == old_next_tile_pattern_high);
                assert (pattern_low_shift == old_pattern_low_shift);
                assert (pattern_high_shift == old_pattern_high_shift);
                assert (attribute_low_shift == old_attribute_low_shift);
                assert (attribute_high_shift == old_attribute_high_shift);
            end
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3e.fst");
        $dumpvars(1, ppu_phase3e_tb);
        for (int index = 0; index < 2048; index++)
            dut.memory.ciram[index] =
                8'(index * 37 + (index >> 3) * 11 + 32'h5a);
        for (int index = 0; index < 32; index++)
            dut.memory.palette_ram[index] = 8'(index * 13 + 32'h31);
        for (int index = 0; index < 8192; index++)
            chr_memory[index] =
                8'(index * 29 + (index >> 4) * 7 + 32'ha5);
        for (int index = 1; index <= 5; index++) scenario_counts[index] = 0;
        for (int index = 0; index <= 5; index++) begin
            fetch_counts[index] = 0;
            random_fetches[index] = 0;
        end

        vector_file = $fopen("build/sim/ppu_phase3e_reference.txt", "r");
        trace_file = $fopen("build/sim/ppu_phase3e_fetch_rtl.txt", "w");
        assert (vector_file != 0 && trace_file != 0)
            else $fatal(1, "could not open Phase 3E vector/trace files");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37], values[38], values[39],
                values[40], values[41], values[42], values[43], values[44],
                values[45], values[46], values[47], values[48], values[49],
                values[50], values[51], values[52], values[53], values[54],
                values[55], values[56], values[57], values[58], values[59],
                values[60], values[61], values[62], values[63], values[64],
                values[65], values[66], values[67], values[68], values[69],
                values[70], values[71]
            );
            if (scan_result == 72) begin
                @(negedge clk);
                reset = values[1][0];
                ppu_enable = values[2][0];
                cpu_enable = values[3][0];
                cpu_bus_valid = values[4][0];
                cpu_bus_write = values[5][0];
                cpu_address = values[6][15:0];
                cpu_write_data = values[7][7:0];
                mirroring_mode = values[8][1:0];
                sprite_zero_hit_set = 1'b0;
                sprite_overflow_set = 1'b0;
                oam_read_data = 8'h00;
                #1;
                check_pre_edge();

                if (values[0] == 2 &&
                    (scanline == 0 || scanline == 1 || scanline == 31 ||
                     scanline == 239 || scanline == 261) &&
                    background_fetch_complete) begin
                    $fwrite(
                        trace_file,
                        "%0d %0d %0d %04x %04x %02x %0d\n",
                        dot, scanline, background_fetch_type,
                        renderer_memory_address, vram_address,
                        next_tile_id, vram_address[14:12]
                    );
                end

                old_dot = dot;
                old_scanline = scanline;
                old_frame_odd = frame_odd;
                old_next_tile_id = next_tile_id;
                old_next_tile_attribute = next_tile_attribute;
                old_next_tile_pattern_low = next_tile_pattern_low;
                old_next_tile_pattern_high = next_tile_pattern_high;
                old_pattern_low_shift = pattern_low_shift;
                old_pattern_high_shift = pattern_high_shift;
                old_attribute_low_shift = attribute_low_shift;
                old_attribute_high_shift = attribute_high_shift;

                rows++;
                scenario_counts[values[0]]++;
                if (!reset) begin
                    ppu_ticks += int'(ppu_enable);
                    ppu_stalls += int'(!ppu_enable);
                    accepted_count += int'(cpu_enable && cpu_bus_valid &&
                                           cpu_register_selected);
                    collision_count += int'(renderer_cpu_collision);
                    if (background_fetch_complete)
                        fetch_counts[background_fetch_type]++;
                    tile_loads += int'(background_tile_load);
                    shifts += int'(background_shift);
                    if (values[0] == 2 && visible_pixel) begin
                        full_frame_pixels++;
                        first_scanline_pixels += int'(scanline == 0);
                    end
                    if (values[0] == 3 && visible_pixel) scroll_pixels++;
                    frame_count += int'(frame_end);
                    if (values[0] == 5) begin
                        random_ticks += int'(ppu_enable);
                        random_stalls += int'(!ppu_enable);
                        random_accepted += int'(cpu_enable && cpu_bus_valid &&
                                                cpu_register_selected);
                        random_collisions += int'(renderer_cpu_collision);
                        if (background_fetch_complete)
                            random_fetches[background_fetch_type]++;
                        random_loads += int'(background_tile_load);
                        random_shifts += int'(background_shift);
                        random_pixels += int'(visible_pixel);
                    end
                end

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 3E vector after row %0d", rows);
            end
        end
        $fclose(vector_file);
        $fclose(trace_file);

        assert (rows == 1_075_191);
        assert (scenario_counts[1] == 89_351);
        assert (scenario_counts[2] == 89_341);
        assert (scenario_counts[3] == 715_129);
        assert (scenario_counts[4] == 1_368);
        assert (scenario_counts[5] == 180_002);
        assert (ppu_ticks == 1_018_972);
        assert (ppu_stalls == 56_215);
        assert (accepted_count == 87_482);
        assert (collision_count == 9_507);
        assert (fetch_counts[1] == 89_824);
        assert (fetch_counts[2] == 89_830);
        assert (fetch_counts[3] == 89_819);
        assert (fetch_counts[4] == 89_823);
        assert (fetch_counts[5] == 5_258);
        assert (tile_loads == 90_990);
        assert (shifts == 727_859);
        assert (full_frame_pixels == 61_440);
        assert (first_scanline_pixels == 256);
        assert (scroll_pixels == 491_776);
        assert (frame_count == 11);
        assert (random_ticks == 123_852);
        assert (random_stalls == 56_148);
        assert (random_accepted == 87_415);
        assert (random_collisions == 9_507);
        assert (random_fetches[1] == 7_748);
        assert (random_fetches[2] == 7_754);
        assert (random_fetches[3] == 7_743);
        assert (random_fetches[4] == 7_747);
        assert (random_fetches[5] == 435);
        assert (random_loads == 8_914);
        assert (random_shifts == 71_251);
        assert (random_pixels == 87_364);

        $display(
            "PASS: Phase 3E integrated rows=%0d ticks=%0d stalls=%0d accepted=%0d collisions=%0d nt=%0d at=%0d low=%0d high=%0d dummy=%0d loads=%0d shifts=%0d pixels=%0d first=%0d scroll_pixels=%0d frames=%0d random_ticks=%0d random_stalls=%0d random_accepted=%0d random_collisions=%0d random_nt=%0d random_at=%0d random_low=%0d random_high=%0d random_dummy=%0d random_loads=%0d random_shifts=%0d random_pixels=%0d mismatches=0 seed=3e200701",
            rows, ppu_ticks, ppu_stalls, accepted_count, collision_count,
            fetch_counts[1], fetch_counts[2], fetch_counts[3], fetch_counts[4],
            fetch_counts[5], tile_loads, shifts, full_frame_pixels,
            first_scanline_pixels, scroll_pixels, frame_count,
            random_ticks, random_stalls, random_accepted, random_collisions,
            random_fetches[1], random_fetches[2], random_fetches[3],
            random_fetches[4], random_fetches[5], random_loads,
            random_shifts, random_pixels
        );
        $finish;
    end
endmodule
