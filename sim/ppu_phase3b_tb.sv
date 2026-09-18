`timescale 1ns/1ps

module ppu_phase3b_tb;
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
    logic [7:0] ppu_memory_read_data = 8'h00;
    logic [7:0] ppu_memory_buffer_read_data = 8'h00;
    logic [13:0] ppu_memory_address;
    logic [13:0] ppu_memory_buffer_address;
    logic ppu_memory_read_request;
    logic ppu_memory_write_request;
    logic [7:0] ppu_memory_write_data;
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

    int vector_file;
    int scan_result;
    int values [0:46];
    int active_scenario = 0;
    int unsigned row_count = 0;
    int unsigned scenario_rows = 0;
    int unsigned selected_count = 0;
    int unsigned accepted_count = 0;
    int unsigned ppu_tick_count = 0;
    int unsigned register_counts [0:7];

    logic [7:0] old_ppuctrl;
    logic [7:0] old_ppumask;
    logic [7:0] old_oam_addr;
    logic [14:0] old_vram_address;
    logic [14:0] old_temp_vram_address;
    logic [2:0] old_fine_x;
    logic old_write_toggle;
    logic [7:0] old_read_buffer;
    logic [7:0] old_io_latch;

    ppu_core dut (.*);

    always #5 clk <= !clk;

    task automatic clear_counts;
        begin
            scenario_rows = 0;
            selected_count = 0;
            accepted_count = 0;
            ppu_tick_count = 0;
            for (int index = 0; index < 8; index++) register_counts[index] = 0;
        end
    endtask

    task automatic check_scenario(input int completed_scenario);
        begin
            case (completed_scenario)
                1: begin
                    assert (scenario_rows == 8_199);
                    assert (selected_count == 8_192)
                        else $fatal(1, "mirroring selected count %0d", selected_count);
                    for (int index = 0; index < 8; index++) begin
                        assert (register_counts[index] == 1_024)
                            else $fatal(1, "mirror index %0d count %0d",
                                        index, register_counts[index]);
                    end
                    $display("PPU exhaustive mirroring PASS: 8192/8192 addresses");
                end
                2: begin
                    assert (scenario_rows > 40);
                    assert (accepted_count > 30);
                    $display("PPU directed register trace PASS: rows=%0d accepted=%0d",
                             scenario_rows, accepted_count);
                end
                3: begin
                    assert (scenario_rows == 200_002);
                    assert (accepted_count == 76_207);
                    assert (ppu_tick_count == 134_135);
                    assert (register_counts[0] == 9_489);
                    assert (register_counts[1] == 9_482);
                    assert (register_counts[2] == 9_413);
                    assert (register_counts[3] == 9_432);
                    assert (register_counts[4] == 9_668);
                    assert (register_counts[5] == 9_772);
                    assert (register_counts[6] == 9_482);
                    assert (register_counts[7] == 9_469);
                    $display(
                        "PPU randomized trace PASS: fabric=200000 accepted=%0d stalls/rejected=%0d ppu_ticks=%0d seed=3b5eed01",
                        accepted_count, 200_000 - accepted_count, ppu_tick_count
                    );
                end
                default: $fatal(1, "unknown vector scenario %0d", completed_scenario);
            endcase
        end
    endtask

    task automatic check_pre_edge;
        logic expected_visible;
        logic expected_frame_end;
        begin
            expected_visible = values[1] == 0 && values[2] != 0 &&
                               values[25] < 240 &&
                               values[24] >= 1 && values[24] <= 256;
            expected_frame_end = values[1] == 0 && values[2] != 0 &&
                values[25] == 261 &&
                ((values[30] != 0 && values[26] != 0 && values[24] == 339) ||
                 (!(values[30] != 0 && values[26] != 0) && values[24] == 340));

            assert (!$isunknown({cpu_read_data, cpu_register_selected,
                                 cpu_register_index, oam_addr,
                                 oam_write_enable, ppu_memory_address,
                                 ppu_memory_buffer_address,
                                 ppu_memory_read_request,
                                 ppu_memory_write_request, dot, scanline,
                                 frame_odd, timing_vblank, vblank_start,
                                 vblank_end, rendering_enabled}))
                else $fatal(1, "unknown pre-edge output at row %0d", row_count);
            assert (int'(cpu_register_selected) == values[13]);
            assert (int'(cpu_register_index) == values[14]);
            assert (int'(cpu_read_data) == values[15]);
            assert (int'(oam_addr) == values[16]);
            assert (int'(oam_write_enable) == values[17]);
            assert (int'(oam_write_data) == values[18]);
            assert (int'(ppu_memory_address) == values[19]);
            assert (int'(ppu_memory_buffer_address) == values[20]);
            assert (int'(ppu_memory_read_request) == values[21]);
            assert (int'(ppu_memory_write_request) == values[22]);
            assert (int'(ppu_memory_write_data) == values[23]);
            assert (int'(dot) == values[24] && int'(scanline) == values[25]);
            assert (int'(frame_odd) == values[26]);
            assert (int'(timing_vblank) == values[27]);
            assert (int'(vblank_start) == values[28]);
            assert (int'(vblank_end) == values[29]);
            assert (int'(rendering_enabled) == values[30]);
            assert (visible_pixel == expected_visible);
            assert (frame_start == (values[1] == 0 && values[2] != 0 &&
                                    values[25] == 0 && values[24] == 0));
            assert (frame_end == expected_frame_end);
            assert (scanline_start == (values[1] == 0 && values[2] != 0 &&
                                       values[24] == 0));
            assert (pre_render == (values[25] == 261));
            assert (post_render == (values[25] == 240));
            assert (!ppu_memory_write_request || cpu_bus_write);
            assert (!oam_write_enable || cpu_bus_write);
            assert (ppu_memory_address == vram_address[13:0]);

            if (values[25] < 240 && values[24] >= 1 && values[24] <= 256) begin
                assert (int'(pixel_x) == values[24] - 1 &&
                        int'(pixel_y) == values[25]);
            end else begin
                assert (pixel_x == 0 && pixel_y == 0);
            end
        end
    endtask

    task automatic check_post_edge;
        logic accepted;
        begin
            accepted = values[1] == 0 && values[3] != 0 &&
                       values[4] != 0 && values[13] != 0;
            assert (int'(dot) == values[31] && int'(scanline) == values[32]);
            assert (int'(frame_odd) == values[33]);
            assert (int'(timing_vblank) == values[34]);
            assert (int'(ppuctrl) == values[35]);
            assert (int'(ppumask) == values[36]);
            assert (int'(status_vblank) == values[37]);
            assert (int'(status_sprite_zero_hit) == values[38]);
            assert (int'(status_sprite_overflow) == values[39]);
            assert (int'(oam_addr) == values[40]);
            assert (int'(vram_address) == values[41]);
            assert (int'(temp_vram_address) == values[42]);
            assert (int'(fine_x) == values[43]);
            assert (int'(write_toggle) == values[44]);
            assert (int'(ppu_data_read_buffer) == values[45]);
            assert (int'(ppu_io_latch) == values[46]);

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

            if (values[1] == 0 && !accepted) begin
                assert (ppuctrl == old_ppuctrl && ppumask == old_ppumask);
                assert (oam_addr == old_oam_addr);
                assert (vram_address == old_vram_address);
                assert (temp_vram_address == old_temp_vram_address);
                assert (fine_x == old_fine_x && write_toggle == old_write_toggle);
                assert (ppu_data_read_buffer == old_read_buffer);
                assert (ppu_io_latch == old_io_latch);
            end
            if (accepted && values[5] != 0 && values[14] == 4) begin
                assert (oam_addr == old_oam_addr + 8'd1)
                    else $fatal(1, "OAMADDR did not increment exactly once");
            end
            if (accepted && values[5] == 0 && values[14] == 4) begin
                assert (oam_addr == old_oam_addr);
            end
            if (accepted && values[14] == 7) begin
                assert (vram_address == old_vram_address +
                        (old_ppuctrl[2] ? 15'd32 : 15'd1))
                    else $fatal(1, "PPUDATA did not increment exactly once");
            end
        end
    endtask

    task automatic drive_idle;
        begin
            ppu_enable = 1'b0;
            cpu_enable = 1'b0;
            cpu_bus_valid = 1'b0;
            cpu_bus_write = 1'b0;
            cpu_address = 16'h0000;
            cpu_write_data = 8'h00;
            sprite_zero_hit_set = 1'b0;
            sprite_overflow_set = 1'b0;
            oam_read_data = 8'h00;
            ppu_memory_read_data = 8'h00;
            ppu_memory_buffer_read_data = 8'h00;
        end
    endtask

    task automatic reset_core;
        begin
            @(negedge clk);
            drive_idle();
            reset = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
        end
    endtask

    task automatic cpu_write(input logic [15:0] address, input logic [7:0] data);
        begin
            @(negedge clk);
            ppu_enable = 1'b0;
            cpu_enable = 1'b1;
            cpu_bus_valid = 1'b1;
            cpu_bus_write = 1'b1;
            cpu_address = address;
            cpu_write_data = data;
            @(posedge clk);
            #1;
            @(negedge clk);
            cpu_enable = 1'b0;
            cpu_bus_valid = 1'b0;
            cpu_bus_write = 1'b0;
        end
    endtask

    task automatic run_frame(input int expected_ticks, input string label);
        logic starting_parity;
        int ticks;
        begin
            assert (dot == 0 && scanline == 0)
                else $fatal(1, "%s did not begin at 0:0", label);
            starting_parity = frame_odd;
            ticks = 0;
            @(negedge clk);
            ppu_enable = 1'b1;
            while (frame_odd == starting_parity) begin
                @(posedge clk);
                #1;
                ticks++;
            end
            @(negedge clk);
            ppu_enable = 1'b0;
            assert (ticks == expected_ticks)
                else $fatal(1, "%s length %0d expected %0d",
                            label, ticks, expected_ticks);
            assert (dot == 0 && scanline == 0);
            $display("PPU integrated frame PASS: %s = %0d ticks", label, ticks);
        end
    endtask

    task automatic advance_to(input int target_scanline, input int target_dot);
        begin
            @(negedge clk);
            ppu_enable = 1'b1;
            while (!(int'(scanline) == target_scanline &&
                     int'(dot) == target_dot)) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic run_frame_integration;
        begin
            reset_core();
            run_frame(89_342, "rendering disabled even");
            run_frame(89_342, "rendering disabled odd");

            reset_core();
            cpu_write(16'h2001, 8'h08);
            run_frame(89_342, "background enabled even");
            run_frame(89_341, "background enabled odd");
            run_frame(89_342, "background enabled even after odd");
            cpu_write(16'h2001, 8'h00);
            run_frame(89_342, "background disabled odd");

            reset_core();
            cpu_write(16'h2001, 8'h10);
            run_frame(89_342, "sprites enabled even");
            run_frame(89_341, "sprites enabled odd");

            reset_core();
            cpu_write(16'h2001, 8'h18);
            run_frame(89_342, "background and sprites enabled even");
            run_frame(89_341, "background and sprites enabled odd");
        end
    endtask

    task automatic run_vblank_integration;
        logic [7:0] status_result;
        begin
            reset_core();
            cpu_write(16'h2005, 8'h15);
            @(negedge clk);
            sprite_zero_hit_set = 1'b1;
            sprite_overflow_set = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            sprite_zero_hit_set = 1'b0;
            sprite_overflow_set = 1'b0;

            advance_to(241, 1);
            assert (vblank_start && timing_vblank);
            @(posedge clk);
            #1;
            assert (status_vblank && status_sprite_zero_hit &&
                    status_sprite_overflow && scanline == 241 && dot == 2);

            @(negedge clk);
            ppu_enable = 1'b0;
            cpu_enable = 1'b1;
            cpu_bus_valid = 1'b1;
            cpu_bus_write = 1'b0;
            cpu_address = 16'h2002;
            #1;
            status_result = cpu_read_data;
            assert (status_result == 8'hF5)
                else $fatal(1, "PPUSTATUS returned %02x expected f5", status_result);
            @(posedge clk);
            #1;
            assert (!status_vblank && !write_toggle);
            assert (status_sprite_zero_hit && status_sprite_overflow);
            assert (timing_vblank && scanline == 241 && dot == 2);
            @(negedge clk);
            cpu_enable = 1'b0;
            cpu_bus_valid = 1'b0;

            advance_to(261, 1);
            assert (vblank_end && !timing_vblank);
            @(posedge clk);
            #1;
            assert (!status_vblank && !status_sprite_zero_hit &&
                    !status_sprite_overflow);
            assert (scanline == 261 && dot == 2);
            @(negedge clk);
            ppu_enable = 1'b0;
            $display(
                "PPU vblank/status integration PASS: set=241:1 result=%02x clear/read-w=1 pre-render-clear=261:1",
                status_result
            );
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3b.fst");
        $dumpvars(0, ppu_phase3b_tb);

        vector_file = $fopen("build/sim/ppu_register_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3B Python reference vectors");

        clear_counts();
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
                sprite_zero_hit_set = values[8][0];
                sprite_overflow_set = values[9][0];
                oam_read_data = values[10][7:0];
                ppu_memory_read_data = values[11][7:0];
                ppu_memory_buffer_read_data = values[12][7:0];
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

                row_count++;
                scenario_rows++;
                selected_count += values[13];
                if (values[1] == 0 && values[3] != 0 && values[4] != 0 &&
                    values[13] != 0) begin
                    accepted_count++;
                    register_counts[values[14]]++;
                end else if (values[0] == 1 && values[13] != 0) begin
                    register_counts[values[14]]++;
                end
                if (values[1] == 0 && values[2] != 0) ppu_tick_count++;

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed PPU register vector after row %0d", row_count);
            end
        end
        check_scenario(active_scenario);
        $fclose(vector_file);
        assert (row_count == 208_249);

        drive_idle();
        run_frame_integration();
        run_vblank_integration();

        $display(
            "PASS: Phase 3B PPU registers (%0d Python-reference cycles plus integrated frames)",
            row_count
        );
        $finish;
    end
endmodule
