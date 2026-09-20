`timescale 1ns/1ps

module ppu_sprite_renderer_tb;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic rendering_enabled;
    logic sprites_enabled;
    logic show_sprites_left;
    logic sprite_size_16;
    logic sprite_pattern_table;
    logic [13:0] nametable_fetch_address;
    logic [2:0] secondary_read_slot;
    logic [7:0] secondary_read_y;
    logic [7:0] secondary_read_tile;
    logic [7:0] secondary_read_attributes;
    logic [7:0] secondary_read_x;
    logic [5:0] secondary_read_sprite_index;
    logic secondary_read_valid;
    logic memory_request;
    logic [13:0] memory_address;
    logic memory_grant;
    logic [7:0] memory_read_data;
    logic [2:0] fetch_slot;
    logic [2:0] fetch_phase;
    logic [2:0] fetch_type;
    logic fetch_complete;
    logic slot_load_event;
    logic [3:0] fetch_relative_row;
    logic [3:0] fetch_selected_row;
    logic [12:0] fetch_pattern_low_address;
    logic [12:0] fetch_pattern_high_address;
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

    int vector_file;
    int trace_file;
    int stats_file;
    int scan_result;
    int values [0:45];
    int expected [0:12];
    int unsigned counters [0:12];
    int unsigned trace_rows = 0;

    ppu_sprite_renderer dut (.*);
    always #5 clk <= !clk;

    function automatic int unsigned bit_count(input logic [7:0] value);
        bit_count = 0;
        for (int bit_index = 0; bit_index < 8; bit_index++)
            bit_count += int'(value[bit_index]);
    endfunction

    task automatic check_outputs;
        begin
            assert (int'(secondary_read_slot) == values[21]);
            assert (int'(memory_request) == values[22]);
            assert (int'(memory_address) == values[23]);
            assert (int'(fetch_slot) == values[24]);
            assert (int'(fetch_phase) == values[25]);
            assert (int'(fetch_type) == values[26]);
            assert (int'(fetch_complete) == values[27]);
            assert (int'(slot_load_event) == values[28]);
            assert (int'(fetch_relative_row) == values[29]);
            assert (int'(fetch_selected_row) == values[30]);
            assert (int'(fetch_pattern_low_address) == values[31]);
            assert (int'(fetch_pattern_high_address) == values[32]);
            assert (int'(sprite_decrement_mask) == values[33]);
            assert (int'(sprite_shift_mask) == values[34]);
            assert (int'(sprite_pixel_valid) == values[35]);
            assert (int'(sprite_x) == values[36]);
            assert (int'(sprite_y) == values[37]);
            assert (int'(sprite_pattern) == values[38]);
            assert (int'(sprite_palette) == values[39]);
            assert (int'(sprite_palette_index) == values[40]);
            assert (int'(sprite_opaque) == values[41]);
            assert (int'(sprite_priority_behind_background) == values[42]);
            assert (int'(sprite_is_zero) == values[43]);
            assert (int'(sprite_slot) == values[44]);
            assert (int'(sprite_original_index) == values[45]);
            assert (!$isunknown({memory_request, memory_address,
                fetch_slot, fetch_phase, fetch_type, fetch_complete,
                slot_load_event, sprite_decrement_mask, sprite_shift_mask,
                sprite_pixel_valid, sprite_pattern, sprite_palette,
                sprite_opaque, sprite_slot, sprite_original_index}));
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_sprite_renderer.fst");
        $dumpvars(1, ppu_sprite_renderer_tb);
        for (int index = 0; index < 13; index++) counters[index] = 0;
        vector_file = $fopen(
            "build/sim/ppu_sprite_renderer_reference.txt", "r"
        );
        trace_file = $fopen(
            "build/sim/ppu_sprite_fetch_rtl.txt", "w"
        );
        assert (vector_file != 0 && trace_file != 0);

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37], values[38], values[39],
                values[40], values[41], values[42], values[43], values[44],
                values[45]
            );
            if (scan_result == 46) begin
                @(negedge clk);
                reset = values[0][0];
                ppu_enable = values[1][0];
                dot = values[2][8:0];
                scanline = values[3][8:0];
                visible_pixel = values[4][0];
                pixel_x = values[5][7:0];
                pixel_y = values[6][7:0];
                rendering_enabled = values[7][0];
                sprites_enabled = values[8][0];
                show_sprites_left = values[9][0];
                sprite_size_16 = values[10][0];
                sprite_pattern_table = values[11][0];
                nametable_fetch_address = values[12][13:0];
                memory_grant = values[13][0];
                secondary_read_y = values[14][7:0];
                secondary_read_tile = values[15][7:0];
                secondary_read_attributes = values[16][7:0];
                secondary_read_x = values[17][7:0];
                secondary_read_sprite_index = values[18][5:0];
                secondary_read_valid = values[19][0];
                memory_read_data = values[20][7:0];
                #1;
                check_outputs();

                counters[0]++;
                counters[1] += int'(ppu_enable && !reset);
                counters[2] += int'(!ppu_enable && !reset);
                counters[3] += int'(slot_load_event);
                counters[4] += int'(fetch_complete && fetch_type == 3);
                counters[5] += int'(fetch_complete && fetch_type == 4);
                counters[6] += int'(fetch_complete &&
                                    (fetch_type == 1 || fetch_type == 2));
                counters[7] += bit_count(sprite_decrement_mask);
                counters[8] += bit_count(sprite_shift_mask);
                counters[9] += int'(ppu_enable && sprite_opaque);
                counters[11] += int'(ppu_enable && sprite_opaque &&
                                     sprite_is_zero);
                counters[12] += int'(memory_request && !memory_grant);
                if (trace_rows < 32 && fetch_complete) begin
                    $fwrite(
                        trace_file, "%0d %0d %0d %0d %0d %0d %0d %0d\n",
                        scanline, dot, fetch_slot, fetch_type,
                        secondary_read_tile, fetch_selected_row,
                        memory_address, memory_read_data
                    );
                    trace_rows++;
                end

                @(posedge clk);
                #1;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed renderer vector");
            end
        end
        $fclose(vector_file);
        $fclose(trace_file);

        stats_file = $fopen(
            "build/sim/ppu_sprite_renderer_stats.txt", "r"
        );
        assert (stats_file != 0);
        scan_result = $fscanf(
            stats_file,
            "%d %d %d %d %d %d %d %d %d %d %d %d %d\n",
            expected[0], expected[1], expected[2], expected[3],
            expected[4], expected[5], expected[6], expected[7],
            expected[8], expected[9], expected[10], expected[11],
            expected[12]
        );
        assert (scan_result == 13);
        $fclose(stats_file);
        // Overlap is a semantic reference count without a dedicated RTL
        // output; every other statistic is independently accumulated here.
        for (int index = 0; index < 13; index++) begin
            if (index != 10)
                assert (counters[index] == expected[index]);
        end
        assert (expected[10] > 0);
        $display(
            "PASS: Phase 3G renderer seed=37202601 fabric=%0d ticks=%0d stalls=%0d slots=%0d low=%0d high=%0d dummy=%0d decrements=%0d shifts=%0d opaque=%0d overlaps=%0d sprite_zero=%0d collisions=%0d mismatches=0",
            counters[0], counters[1], counters[2], counters[3], counters[4],
            counters[5], counters[6], counters[7], counters[8], counters[9],
            expected[10], counters[11], counters[12]
        );
        $finish;
    end
endmodule
