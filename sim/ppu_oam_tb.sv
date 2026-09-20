`timescale 1ns/1ps

module ppu_oam_tb;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic rendering_enabled;
    logic sprite_size_16;
    logic [7:0] cpu_oam_addr;
    logic [7:0] cpu_write_data;
    logic cpu_write_enable;
    logic cpu_access;
    logic [7:0] cpu_read_data;
    logic cpu_write_commit;
    logic cpu_collision;
    logic [2:0] secondary_read_slot;
    logic [7:0] secondary_read_y;
    logic [7:0] secondary_read_tile;
    logic [7:0] secondary_read_attributes;
    logic [7:0] secondary_read_x;
    logic [5:0] secondary_read_sprite_index;
    logic secondary_read_valid;
    logic [2:0] renderer_read_slot = 3'd0;
    logic [7:0] renderer_read_y;
    logic [7:0] renderer_read_tile;
    logic [7:0] renderer_read_attributes;
    logic [7:0] renderer_read_x;
    logic [5:0] renderer_read_sprite_index;
    logic renderer_read_valid;
    logic [3:0] selected_sprite_count;
    logic sprite_zero_in_secondary;
    logic sprite_overflow_set;
    logic [2:0] evaluation_phase;
    logic [5:0] evaluation_sprite_index;
    logic [1:0] evaluation_byte_index;
    logic [7:0] evaluation_relative_row;
    logic [4:0] sprite_height;
    logic [7:0] primary_read_address;
    logic [7:0] primary_read_data;
    logic secondary_clear_write;
    logic secondary_evaluation_write;
    logic [4:0] secondary_write_address;
    logic [7:0] secondary_write_data;
    logic evaluation_done;

    int vector_file;
    int scan_result;
    int values [0:36];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:7];
    int unsigned ppu_ticks = 0;
    int unsigned ppu_stalls = 0;
    int unsigned cpu_accesses = 0;
    int unsigned cpu_writes = 0;
    int unsigned cpu_commits = 0;
    int unsigned collisions = 0;
    int unsigned clear_writes = 0;
    int unsigned secondary_writes = 0;
    int unsigned overflow_sets = 0;
    int unsigned sprites_selected = 0;
    int unsigned visible_lines = 0;

    logic [3:0] old_selected_count;
    logic old_sprite_zero;
    logic [2:0] old_phase;
    logic [5:0] old_n;
    logic [1:0] old_m;
    logic old_done;
    logic [7:0] old_read_latch;
    logic [4:0] old_secondary_destination;
    logic [1:0] old_overflow_tail;

    ppu_oam dut (.*);
    always #5 clk <= !clk;

    task automatic check_pre_edge;
        begin
            assert (!$isunknown({cpu_read_data, cpu_write_commit,
                                 cpu_collision, primary_read_address,
                                 primary_read_data, secondary_clear_write,
                                 secondary_evaluation_write,
                                 secondary_write_address,
                                 secondary_write_data,
                                 evaluation_relative_row, sprite_height}));
            assert (int'(cpu_read_data) == values[12]);
            assert (int'(cpu_write_commit) == values[13]);
            assert (int'(cpu_collision) == values[14]);
            assert (int'(primary_read_address) == values[15]);
            assert (int'(primary_read_data) == values[16]);
            assert (int'(secondary_clear_write) == values[17]);
            assert (int'(secondary_evaluation_write) == values[18]);
            assert (int'(secondary_write_address) == values[19]);
            assert (int'(secondary_write_data) == values[20]);
            assert (int'(evaluation_relative_row) == values[21]);
            assert (int'(dut.evaluated_in_range) == values[22]);
            assert (!cpu_write_commit || !cpu_collision);
            assert (!(secondary_clear_write && secondary_evaluation_write));
            if (secondary_clear_write) begin
                assert (dot >= 2 && dot <= 64 && !dot[0]);
                assert (secondary_write_data == 8'hff);
            end
            if (secondary_evaluation_write) begin
                assert (dot >= 66 && dot <= 256 && !dot[0]);
                assert (selected_sprite_count < 8);
            end
            if (!ppu_enable) begin
                assert (!secondary_clear_write);
                assert (!secondary_evaluation_write);
            end
        end
    endtask

    task automatic check_post_edge;
        begin
            assert (!$isunknown({selected_sprite_count,
                                 sprite_zero_in_secondary,
                                 sprite_overflow_set, evaluation_phase,
                                 evaluation_sprite_index,
                                 evaluation_byte_index, evaluation_done,
                                 secondary_read_y, secondary_read_tile,
                                 secondary_read_attributes, secondary_read_x,
                                 secondary_read_sprite_index,
                                 secondary_read_valid,
                                 renderer_read_y, renderer_read_tile,
                                 renderer_read_attributes, renderer_read_x,
                                 renderer_read_sprite_index,
                                 renderer_read_valid}));
            assert (int'(selected_sprite_count) == values[23]);
            assert (int'(sprite_zero_in_secondary) == values[24]);
            assert (int'(sprite_overflow_set) == values[25]);
            assert (int'(evaluation_phase) == values[26]);
            assert (int'(evaluation_sprite_index) == values[27]);
            assert (int'(evaluation_byte_index) == values[28]);
            assert (int'(sprite_height) == values[29]);
            assert (int'(evaluation_done) == values[30]);
            assert (int'(secondary_read_y) == values[31]);
            assert (int'(secondary_read_tile) == values[32]);
            assert (int'(secondary_read_attributes) == values[33]);
            assert (int'(secondary_read_x) == values[34]);
            assert (int'(secondary_read_sprite_index) == values[35]);
            assert (int'(secondary_read_valid) == values[36]);
            assert (selected_sprite_count <= 8);
            if (cpu_write_commit)
                assert (dut.primary_oam[cpu_oam_addr] == cpu_write_data);
            if (!reset && !ppu_enable) begin
                assert (selected_sprite_count == old_selected_count);
                assert (sprite_zero_in_secondary == old_sprite_zero);
                assert (evaluation_phase == old_phase);
                assert (evaluation_sprite_index == old_n);
                assert (evaluation_byte_index == old_m);
                assert (evaluation_done == old_done);
                assert (dut.evaluation_read_latch == old_read_latch);
                assert (dut.secondary_destination == old_secondary_destination);
                assert (dut.overflow_tail_remaining == old_overflow_tail);
            end
            if (sprite_zero_in_secondary)
                assert (dut.secondary_sprite_index[0] == 0);
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_oam.fst");
        $dumpvars(1, ppu_oam_tb);
        for (int index = 0; index < 256; index++)
            dut.primary_oam[index] = 8'h00;
        for (int index = 0; index < 32; index++)
            dut.secondary_oam[index] = 8'h00;
        for (int index = 0; index < 8; index++)
            dut.secondary_sprite_index[index] = 6'd0;
        for (int index = 1; index <= 7; index++) scenario_counts[index] = 0;

        vector_file = $fopen("build/sim/ppu_oam_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3F OAM vectors");
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36]
            );
            if (scan_result == 37) begin
                @(negedge clk);
                reset = values[1][0];
                ppu_enable = values[2][0];
                dot = values[3][8:0];
                scanline = values[4][8:0];
                rendering_enabled = values[5][0];
                sprite_size_16 = values[6][0];
                cpu_oam_addr = values[7][7:0];
                cpu_write_data = values[8][7:0];
                cpu_write_enable = values[9][0];
                cpu_access = values[10][0];
                secondary_read_slot = values[11][2:0];
                #1;
                check_pre_edge();

                old_selected_count = selected_sprite_count;
                old_sprite_zero = sprite_zero_in_secondary;
                old_phase = evaluation_phase;
                old_n = evaluation_sprite_index;
                old_m = evaluation_byte_index;
                old_done = evaluation_done;
                old_read_latch = dut.evaluation_read_latch;
                old_secondary_destination = dut.secondary_destination;
                old_overflow_tail = dut.overflow_tail_remaining;

                rows++;
                scenario_counts[values[0]]++;
                ppu_ticks += int'(ppu_enable);
                ppu_stalls += int'(!ppu_enable && !reset);
                cpu_accesses += int'(cpu_access);
                cpu_writes += int'(cpu_write_enable);
                cpu_commits += int'(cpu_write_commit);
                collisions += int'(cpu_collision);
                clear_writes += int'(secondary_clear_write);
                secondary_writes += int'(secondary_evaluation_write);
                if (dot == 1 && ppu_enable && rendering_enabled &&
                    scanline < 240)
                    visible_lines++;

                @(posedge clk);
                #1;
                overflow_sets += int'(sprite_overflow_set);
                if (selected_sprite_count > old_selected_count)
                    sprites_selected += int'(selected_sprite_count) -
                                        int'(old_selected_count);
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed OAM vector after row %0d", rows);
            end
        end
        $fclose(vector_file);

        assert (scenario_counts[1] > 500);
        assert (scenario_counts[6] > 60_000);
        assert (scenario_counts[7] > 240_000);
        assert (visible_lines == 1_070);
        $display(
            "PASS: Phase 3F OAM rows=%0d ticks=%0d stalls=%0d cpu_access=%0d cpu_writes=%0d commits=%0d collisions=%0d clears=%0d secondary_writes=%0d selected=%0d overflow_sets=%0d visible_lines=%0d mismatches=0 seed=3f5eed01",
            rows, ppu_ticks, ppu_stalls, cpu_accesses, cpu_writes,
            cpu_commits, collisions, clear_writes, secondary_writes,
            sprites_selected, overflow_sets, visible_lines
        );
        $finish;
    end
endmodule
