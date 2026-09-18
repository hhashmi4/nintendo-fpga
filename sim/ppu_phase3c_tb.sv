`timescale 1ns/1ps

module ppu_phase3c_tb;
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
    logic ppu_master_slave;
    logic sprite_size_16;
    logic background_pattern_table;
    logic sprite_pattern_table;
    logic [5:0] vram_increment;
    logic [1:0] base_nametable;
    logic mask_grayscale;
    logic mask_show_background_left;
    logic mask_show_sprites_left;
    logic mask_show_background;
    logic mask_show_sprites;
    logic mask_emphasize_red;
    logic mask_emphasize_green;
    logic mask_emphasize_blue;
    logic rendering_enabled;
    logic rendering_scanline;
    logic active_render_period;
    logic coarse_x_increment_event;
    logic vertical_increment_event;
    logic horizontal_copy_event;
    logic vertical_copy_event;
    logic automatic_scroll_event;
    logic [13:0] nametable_fetch_address;
    logic [13:0] attribute_fetch_address;

    // Fake CHR-RAM cartridge exists only in this simulation testbench.
    logic [7:0] chr_memory [0:8191];

    int vector_file;
    int scan_result;
    int values [0:53];
    int active_scenario = 0;
    int unsigned row_count = 0;
    int unsigned scenario_rows = 0;
    int unsigned accepted_count = 0;
    int unsigned ppudata_count = 0;
    int unsigned ppudata_reads = 0;
    int unsigned ppudata_writes = 0;
    int unsigned active_stalls = 0;
    int unsigned ppu_ticks = 0;
    int unsigned region_counts [0:2];
    int unsigned mode_counts [0:3];

    logic [7:0] old_ppuctrl;
    logic [7:0] old_ppumask;
    logic [7:0] old_oam_addr;
    logic [14:0] old_vram_address;
    logic [14:0] old_temp_vram_address;
    logic [2:0] old_fine_x;
    logic old_write_toggle;
    logic [7:0] old_read_buffer;
    logic [7:0] old_io_latch;
    logic old_automatic_scroll_event;
    logic old_active_render_period;
    logic [14:0] old_active_data_increment_address;

    ppu_memory_core dut (.*);

    assign chr_read_data = chr_memory[chr_addr];

    always #5 clk <= !clk;

    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    task automatic clear_counts;
        begin
            scenario_rows = 0;
            accepted_count = 0;
            ppudata_count = 0;
            ppudata_reads = 0;
            ppudata_writes = 0;
            active_stalls = 0;
            ppu_ticks = 0;
            for (int index = 0; index < 3; index++) region_counts[index] = 0;
            for (int index = 0; index < 4; index++) mode_counts[index] = 0;
        end
    endtask

    task automatic check_scenario(input int completed_scenario);
        begin
            case (completed_scenario)
                1: begin
                    assert (scenario_rows == 310);
                    assert (ppudata_count == 100);
                    $display(
                        "Integrated PPUDATA directed PASS: rows=%0d accesses=%0d",
                        scenario_rows, ppudata_count
                    );
                end
                2: begin
                    assert (scenario_rows == 120_002);
                    assert (accepted_count == 59_741);
                    assert (ppudata_count == 29_822);
                    assert (ppudata_reads == 14_853);
                    assert (ppudata_writes == 14_969);
                    assert (active_stalls == 37_683);
                    assert (ppu_ticks == 81_457);
                    assert (region_counts[0] == 14_979);
                    assert (region_counts[1] == 14_444);
                    assert (region_counts[2] == 399);
                    assert (mode_counts[0] == 7_461);
                    assert (mode_counts[1] == 7_471);
                    assert (mode_counts[2] == 7_455);
                    assert (mode_counts[3] == 7_435);
                    $display(
                        "Integrated PPUDATA randomized PASS: seed=3c200701 fabric=120000 accepted=%0d ppudata=%0d reads=%0d writes=%0d stalls=%0d ppu_ticks=%0d chr=%0d nametable=%0d palette=%0d",
                        accepted_count, ppudata_count, ppudata_reads,
                        ppudata_writes, active_stalls, ppu_ticks,
                        region_counts[0], region_counts[1], region_counts[2]
                    );
                end
                default: $fatal(1, "unknown integrated scenario %0d",
                                completed_scenario);
            endcase
        end
    endtask

    task automatic check_pre_edge;
        int write_destinations;
        logic coordinate_visible;
        logic terminal_tick;
        begin
            assert (!$isunknown({cpu_read_data, cpu_register_selected,
                                 cpu_register_index, ppu_memory_address,
                                 ppu_memory_buffer_address,
                                 ppu_memory_read_request,
                                 ppu_memory_write_request, chr_addr,
                                 chr_read, chr_write, memory_region,
                                 ciram_write_enable, palette_write_enable,
                                 dot, scanline, frame_odd, timing_vblank}))
                else $fatal(1, "unknown integrated output at row %0d", row_count);

            assert (int'(cpu_register_selected) == values[9]);
            assert (int'(cpu_register_index) == values[10]);
            assert (int'(cpu_read_data) == values[11]);
            assert (int'(ppu_memory_address) == values[12]);
            assert (int'(ppu_memory_buffer_address) == values[13]);
            assert (int'(ppu_memory_read_request) == values[14]);
            assert (int'(ppu_memory_write_request) == values[15]);
            assert (int'(ppu_memory_write_data) == values[16]);
            assert (int'(chr_addr) == values[17]);
            assert (int'(chr_read) == values[18]);
            assert (int'(chr_write) == values[19]);
            assert (int'(chr_write_data) == values[20]);
            assert (int'(memory_region) == values[21]);
            assert (int'(normalized_nametable_address) == values[22]);
            assert (int'(logical_nametable) == values[23]);
            assert (int'(nametable_offset) == values[24]);
            assert (int'(physical_ciram_page) == values[25]);
            assert (int'(ciram_address) == values[26]);
            assert (int'(palette_index) == values[27]);
            assert (int'(ciram_write_enable) == values[28]);
            assert (int'(palette_write_enable) == values[29]);
            assert (int'(dut.memory_read_data) == values[30]);
            assert (int'(dut.memory_buffer_read_data) == values[31]);
            assert (int'(dot) == values[32]);
            assert (int'(scanline) == values[33]);
            assert (int'(frame_odd) == values[34]);
            assert (int'(timing_vblank) == values[35]);

            coordinate_visible = scanline < 240 && dot >= 1 && dot <= 256;
            terminal_tick = scanline == 261 &&
                ((rendering_enabled && frame_odd && dot == 339) || dot == 340);
            assert (visible_pixel == (!reset && ppu_enable &&
                                      coordinate_visible));
            if (coordinate_visible) begin
                assert (pixel_x == dot[7:0] - 8'd1);
                assert (pixel_y == scanline[7:0]);
            end else begin
                assert (pixel_x == 0 && pixel_y == 0);
            end
            assert (frame_start == (!reset && ppu_enable &&
                                    scanline == 0 && dot == 0));
            assert (frame_end == (!reset && ppu_enable && terminal_tick));
            assert (scanline_start == (!reset && ppu_enable && dot == 0));
            assert (vblank_start == (!reset && ppu_enable &&
                                     scanline == 241 && dot == 1));
            assert (vblank_end == (!reset && ppu_enable &&
                                   scanline == 261 && dot == 1));
            assert (pre_render == (scanline == 261));
            assert (post_render == (scanline == 240));

            assert (oam_write_data == cpu_write_data);
            assert (!oam_write_enable);
            assert (nmi_enable == ppuctrl[7]);
            assert (ppu_master_slave == ppuctrl[6]);
            assert (sprite_size_16 == ppuctrl[5]);
            assert (background_pattern_table == ppuctrl[4]);
            assert (sprite_pattern_table == ppuctrl[3]);
            assert (vram_increment == (ppuctrl[2] ? 6'd32 : 6'd1));
            assert (base_nametable == ppuctrl[1:0]);
            assert ({mask_emphasize_blue, mask_emphasize_green,
                     mask_emphasize_red, mask_show_sprites,
                     mask_show_background, mask_show_sprites_left,
                     mask_show_background_left, mask_grayscale} == ppumask);
            assert (rendering_enabled == (ppumask[3] || ppumask[4]));
            assert (rendering_scanline ==
                    (scanline < 9'd240 || scanline == 9'd261));
            assert (active_render_period ==
                    (rendering_enabled && rendering_scanline));
            assert (coarse_x_increment_event ==
                    (!reset && ppu_enable && active_render_period &&
                     (((dot >= 9'd8 && dot <= 9'd256) &&
                       dot[2:0] == 3'd0) || dot == 9'd328 ||
                      dot == 9'd336)));
            assert (vertical_increment_event ==
                    (!reset && ppu_enable && active_render_period &&
                     dot == 9'd256));
            assert (horizontal_copy_event ==
                    (!reset && ppu_enable && active_render_period &&
                     dot == 9'd257));
            assert (vertical_copy_event ==
                    (!reset && ppu_enable && rendering_enabled &&
                     scanline == 9'd261 && dot >= 9'd280 && dot <= 9'd304));
            assert (nametable_fetch_address ==
                    (14'h2000 | (vram_address[13:0] & 14'h0fff)));
            assert (attribute_fetch_address ==
                    (14'h23c0 | (vram_address[13:0] & 14'h0c00) |
                     ((vram_address[13:0] >> 4) & 14'h0038) |
                     ((vram_address[13:0] >> 2) & 14'h0007)));

            write_destinations = int'(chr_write) + int'(ciram_write_enable) +
                                 int'(palette_write_enable);
            if (ppu_memory_write_request) begin
                assert (write_destinations == 1);
            end else begin
                assert (write_destinations == 0);
            end
            assert (!ppu_memory_read_request || !ppu_memory_write_request);
            assert (!chr_write || cpu_bus_write);
            assert (!ciram_write_enable || cpu_bus_write);
            assert (!palette_write_enable || cpu_bus_write);
            if (!cpu_enable || !cpu_bus_valid) begin
                assert (!ppu_memory_read_request && !ppu_memory_write_request);
                assert (!chr_write && !ciram_write_enable &&
                        !palette_write_enable);
            end
        end
    endtask

    task automatic check_post_edge;
        logic accepted;
        begin
            accepted = values[1] == 0 && values[3] != 0 &&
                       values[4] != 0 && values[9] != 0;
            assert (int'(ppuctrl) == values[36]);
            assert (int'(ppumask) == values[37]);
            assert (int'(status_vblank) == values[38]);
            assert (int'(status_sprite_zero_hit) == values[39]);
            assert (int'(status_sprite_overflow) == values[40]);
            assert (int'(oam_addr) == values[41]);
            assert (int'(vram_address) == values[42]);
            assert (int'(temp_vram_address) == values[43]);
            assert (int'(fine_x) == values[44]);
            assert (int'(write_toggle) == values[45]);
            assert (int'(ppu_data_read_buffer) == values[46]);
            assert (int'(ppu_io_latch) == values[47]);
            assert (int'(dot) == values[48]);
            assert (int'(scanline) == values[49]);
            assert (int'(frame_odd) == values[50]);
            assert (int'(timing_vblank) == values[51]);
            assert (int'(dut.memory_read_data) == values[52]);
            assert (int'(dut.memory_buffer_read_data) == values[53]);

            if (values[1] == 0 && !accepted) begin
                assert (ppuctrl == old_ppuctrl && ppumask == old_ppumask);
                assert (oam_addr == old_oam_addr);
                if (!old_automatic_scroll_event)
                    assert (vram_address == old_vram_address);
                assert (temp_vram_address == old_temp_vram_address);
                assert (fine_x == old_fine_x && write_toggle == old_write_toggle);
                assert (ppu_data_read_buffer == old_read_buffer);
                assert (ppu_io_latch == old_io_latch);
            end
            if (accepted && values[10] == 7) begin
                assert (vram_address == (old_active_render_period ?
                        old_active_data_increment_address :
                        old_vram_address +
                        (old_ppuctrl[2] ? 15'd32 : 15'd1)))
                    else $fatal(1, "integrated PPUDATA did not increment once");
            end
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3c.fst");
        $dumpvars(1, ppu_phase3c_tb);

        for (int index = 0; index < 2048; index++)
            dut.memory.ciram[index] = 8'h00;
        for (int index = 0; index < 32; index++)
            dut.memory.palette_ram[index] = 8'h00;
        for (int index = 0; index < 8192; index++) chr_memory[index] = 8'h00;

        vector_file = $fopen("build/sim/ppu_phase3c_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open integrated Phase 3C vectors");

        clear_counts();
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
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
                values[50], values[51], values[52], values[53]
            );
            if (scan_result == 54) begin
                if (active_scenario != values[0]) begin
                    if (active_scenario != 0) check_scenario(active_scenario);
                    active_scenario = values[0];
                    clear_counts();
                end

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

                old_ppuctrl = ppuctrl;
                old_ppumask = ppumask;
                old_oam_addr = oam_addr;
                old_vram_address = vram_address;
                old_temp_vram_address = temp_vram_address;
                old_fine_x = fine_x;
                old_write_toggle = write_toggle;
                old_read_buffer = ppu_data_read_buffer;
                old_io_latch = ppu_io_latch;
                old_automatic_scroll_event = automatic_scroll_event;
                old_active_render_period = active_render_period;
                old_active_data_increment_address =
                    dut.core.registers.active_data_increment_address;

                row_count++;
                scenario_rows++;
                if (values[1] == 0 && values[3] != 0 && values[4] != 0 &&
                    values[9] != 0) begin
                    accepted_count++;
                    if (values[10] == 7) begin
                        ppudata_count++;
                        if (values[5] != 0) ppudata_writes++;
                        else ppudata_reads++;
                        region_counts[values[21]]++;
                        mode_counts[values[8]]++;
                    end
                end
                if (values[1] == 0 && values[3] == 0 && values[4] != 0 &&
                    values[9] != 0) active_stalls++;
                if (values[1] == 0 && values[2] != 0) ppu_ticks++;

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed integrated vector after row %0d", row_count);
            end
        end
        check_scenario(active_scenario);
        $fclose(vector_file);
        assert (row_count == 120_312);

        $display(
            "PASS: Phase 3C integrated PPUDATA (%0d Python-reference cycles, mismatches=0)",
            row_count
        );
        $finish;
    end
endmodule
