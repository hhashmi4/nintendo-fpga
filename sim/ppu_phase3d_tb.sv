`timescale 1ns/1ps

module ppu_phase3d_tb;
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

    logic [7:0] chr_memory [0:8191];

    int vector_file;
    int scan_result;
    int values [0:48];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:3];
    int unsigned ppu_ticks = 0;
    int unsigned ppu_stalls = 0;
    int unsigned accepted_count = 0;
    int unsigned scroll_transactions = 0;
    int unsigned ppudata_transactions = 0;
    int unsigned x_increments = 0;
    int unsigned y_increments = 0;
    int unsigned horizontal_copies = 0;
    int unsigned vertical_copies = 0;
    int unsigned collision_count = 0;
    int unsigned frame_count = 0;

    logic [14:0] old_vram_address;
    logic [14:0] old_temp_vram_address;
    logic [2:0] old_fine_x;
    logic old_write_toggle;
    logic [7:0] old_ppuctrl;
    logic [7:0] old_ppumask;
    logic [7:0] old_oam_addr;
    logic [7:0] old_read_buffer;
    logic [7:0] old_io_latch;
    logic old_auto_event;

    ppu_memory_core dut (.*);

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
                                 ppu_memory_write_request, memory_region,
                                 normalized_nametable_address,
                                 logical_nametable, nametable_offset,
                                 physical_ciram_page, ciram_address,
                                 palette_index,
                                 chr_addr, chr_read, chr_write,
                                 ciram_write_enable, palette_write_enable,
                                 dot, scanline, frame_odd, timing_vblank,
                                 vram_address, temp_vram_address, fine_x,
                                 write_toggle, rendering_enabled,
                                 status_sprite_zero_hit,
                                 status_sprite_overflow,
                                 rendering_scanline, active_render_period,
                                 coarse_x_increment_event,
                                 vertical_increment_event,
                                 horizontal_copy_event, vertical_copy_event,
                                 automatic_scroll_event,
                                 nametable_fetch_address,
                                 attribute_fetch_address}));

            assert (int'(cpu_register_selected) == values[9]);
            assert (int'(cpu_register_index) == values[10]);
            assert (int'(cpu_read_data) == values[11]);
            assert (int'(ppu_memory_address) == values[12]);
            assert (int'(ppu_memory_buffer_address) == values[13]);
            assert (int'(ppu_memory_read_request) == values[14]);
            assert (int'(ppu_memory_write_request) == values[15]);
            assert (int'(dut.memory_read_data) == values[16]);
            assert (int'(dut.memory_buffer_read_data) == values[17]);
            assert (int'(chr_addr) == values[18]);
            assert (int'(chr_read) == values[19]);
            assert (int'(chr_write) == values[20]);
            assert (int'(ciram_write_enable) == values[21]);
            assert (int'(palette_write_enable) == values[22]);
            assert (int'(dot) == values[23]);
            assert (int'(scanline) == values[24]);
            assert (int'(frame_odd) == values[25]);
            assert (int'(rendering_enabled) == values[26]);
            assert (int'(rendering_scanline) == values[27]);
            assert (int'(active_render_period) == values[28]);
            assert (int'(coarse_x_increment_event) == values[29]);
            assert (int'(vertical_increment_event) == values[30]);
            assert (int'(horizontal_copy_event) == values[31]);
            assert (int'(vertical_copy_event) == values[32]);
            assert (int'(automatic_scroll_event) == values[33]);
            assert (int'(nametable_fetch_address) == values[34]);
            assert (int'(attribute_fetch_address) == values[35]);
            assert (int'(memory_region) == values[48]);

            assert (rendering_scanline ==
                    (scanline < 9'd240 || scanline == 9'd261));
            assert (!automatic_scroll_event ||
                    (ppu_enable && rendering_enabled && rendering_scanline));
            assert (!vertical_copy_event ||
                    (scanline == 9'd261 && dot >= 9'd280 && dot <= 9'd304));
            assert (!horizontal_copy_event || dot == 9'd257);
            assert (!vertical_increment_event || dot == 9'd256);
            assert (!coarse_x_increment_event ||
                    (((dot >= 9'd8 && dot <= 9'd256) &&
                      dot[2:0] == 3'd0) || dot == 9'd328 || dot == 9'd336));
            if (!ppu_enable) assert (!automatic_scroll_event);

            assert (nametable_fetch_address ==
                    (14'h2000 | (vram_address[13:0] & 14'h0fff)));
            assert (attribute_fetch_address ==
                    (14'h23c0 | (vram_address[13:0] & 14'h0c00) |
                     ((vram_address[13:0] >> 4) & 14'h0038) |
                     ((vram_address[13:0] >> 2) & 14'h0007)));

            assert (oam_write_data == cpu_write_data);
            assert (ppu_memory_write_data == cpu_write_data);
            assert (chr_write_data == cpu_write_data);
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

            write_destinations = int'(chr_write) + int'(ciram_write_enable) +
                                 int'(palette_write_enable);
            assert (write_destinations == int'(ppu_memory_write_request));
            assert (!ppu_memory_read_request || !ppu_memory_write_request);
            if (!cpu_enable || !cpu_bus_valid) begin
                assert (!oam_write_enable);
                assert (!ppu_memory_read_request && !ppu_memory_write_request);
            end

            assert (visible_pixel == (!reset && ppu_enable &&
                    scanline < 9'd240 && dot >= 9'd1 && dot <= 9'd256));
            if (scanline < 9'd240 && dot >= 9'd1 && dot <= 9'd256) begin
                assert (pixel_x == dot[7:0] - 8'd1);
                assert (pixel_y == scanline[7:0]);
            end else begin
                assert (pixel_x == 0 && pixel_y == 0);
            end
            assert (frame_start == (!reset && ppu_enable &&
                                    scanline == 0 && dot == 0));
            assert (scanline_start == (!reset && ppu_enable && dot == 0));
            assert (vblank_start == (!reset && ppu_enable &&
                                     scanline == 241 && dot == 1));
            assert (vblank_end == (!reset && ppu_enable &&
                                   scanline == 261 && dot == 1));
            assert (pre_render == (scanline == 261));
            assert (post_render == (scanline == 240));
            assert (frame_end == (!reset && ppu_enable &&
                    scanline == 261 &&
                    ((rendering_enabled && frame_odd && dot == 339) ||
                     dot == 340)));
        end
    endtask

    task automatic check_post_edge;
        logic accepted;
        logic cpu_v_operation;
        begin
            accepted = values[1] == 0 && values[3] != 0 &&
                       values[4] != 0 && values[9] != 0;
            cpu_v_operation = accepted &&
                (values[10] == 7 ||
                 (values[10] == 6 && values[5] != 0 && old_write_toggle));

            assert (int'(dot) == values[36]);
            assert (int'(scanline) == values[37]);
            assert (int'(frame_odd) == values[38]);
            assert (int'(ppuctrl) == values[39]);
            assert (int'(ppumask) == values[40]);
            assert (int'(vram_address) == values[41]);
            assert (int'(temp_vram_address) == values[42]);
            assert (int'(fine_x) == values[43]);
            assert (int'(write_toggle) == values[44]);
            assert (int'(ppu_data_read_buffer) == values[45]);
            assert (int'(ppu_io_latch) == values[46]);
            assert (int'(status_vblank) == values[47]);

            if (values[1] == 0 && !accepted && !old_auto_event) begin
                assert (vram_address == old_vram_address);
                assert (temp_vram_address == old_temp_vram_address);
                assert (fine_x == old_fine_x);
                assert (write_toggle == old_write_toggle);
                assert (ppuctrl == old_ppuctrl && ppumask == old_ppumask);
                assert (oam_addr == old_oam_addr);
                assert (ppu_data_read_buffer == old_read_buffer);
                assert (ppu_io_latch == old_io_latch);
            end
            if (old_auto_event && !cpu_v_operation) begin
                if (values[31] != 0)
                    assert ((vram_address & 15'h041f) ==
                            (old_temp_vram_address & 15'h041f));
                if (values[32] != 0)
                    assert ((vram_address & 15'h7be0) ==
                            (old_temp_vram_address & 15'h7be0));
            end
            if (cpu_v_operation && old_auto_event) collision_count++;
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3d.fst");
        $dumpvars(1, ppu_phase3d_tb);
        for (int index = 0; index < 2048; index++)
            dut.memory.ciram[index] = 8'h00;
        for (int index = 0; index < 32; index++)
            dut.memory.palette_ram[index] = 8'h00;
        for (int index = 0; index < 8192; index++) chr_memory[index] = 8'h00;
        for (int index = 1; index <= 3; index++) scenario_counts[index] = 0;

        vector_file = $fopen("build/sim/ppu_phase3d_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open integrated Phase 3D vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37], values[38], values[39],
                values[40], values[41], values[42], values[43], values[44],
                values[45], values[46], values[47], values[48]
            );
            if (scan_result == 49) begin
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

                old_vram_address = vram_address;
                old_temp_vram_address = temp_vram_address;
                old_fine_x = fine_x;
                old_write_toggle = write_toggle;
                old_ppuctrl = ppuctrl;
                old_ppumask = ppumask;
                old_oam_addr = oam_addr;
                old_read_buffer = ppu_data_read_buffer;
                old_io_latch = ppu_io_latch;
                old_auto_event = automatic_scroll_event;

                rows++;
                scenario_counts[values[0]]++;
                if (values[1] == 0) begin
                    ppu_ticks += values[2];
                    ppu_stalls += int'(values[2] == 0);
                    if (values[3] != 0 && values[4] != 0 && values[9] != 0) begin
                        accepted_count++;
                        if (values[10] == 0 || values[10] == 1 ||
                            values[10] == 2 || values[10] == 5 ||
                            values[10] == 6) scroll_transactions++;
                        if (values[10] == 7) ppudata_transactions++;
                    end
                    x_increments += values[29];
                    y_increments += values[30];
                    horizontal_copies += values[31];
                    vertical_copies += values[32];
                    if (frame_end) frame_count++;
                end

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 3D vector after row %0d", rows);
            end
        end
        $fclose(vector_file);

        assert (rows == 758_097);
        assert (scenario_counts[1] == 89_348);
        assert (scenario_counts[2] == 488_747);
        assert (scenario_counts[3] == 180_002);
        assert (ppu_ticks == 660_273);
        assert (ppu_stalls == 97_812);
        assert (accepted_count == 83_718);
        assert (scroll_transactions == 45_830);
        assert (ppudata_transactions == 22_518);
        assert (x_increments == 49_713);
        assert (y_increments == 1_463);
        assert (horizontal_copies == 1_465);
        assert (vertical_copies == 145);
        assert (collision_count == 1_306);
        assert (frame_count == 6);

        $display(
            "PASS: Phase 3D integrated scroll rows=%0d ppu_ticks=%0d stalls=%0d accepted=%0d scroll_regs=%0d ppudata=%0d x_inc=%0d y_inc=%0d hcopy=%0d vcopy=%0d collisions=%0d frames=%0d mismatches=0 seeds=3d200701/3d57a110",
            rows, ppu_ticks, ppu_stalls, accepted_count,
            scroll_transactions, ppudata_transactions, x_increments,
            y_increments, horizontal_copies, vertical_copies,
            collision_count, frame_count
        );
        $finish;
    end
endmodule
