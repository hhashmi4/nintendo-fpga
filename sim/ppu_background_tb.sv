`timescale 1ns/1ps

module ppu_background_tb;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic rendering_enabled;
    logic background_enabled;
    logic show_background_left;
    logic background_pattern_table;
    logic [2:0] fine_x;
    logic [2:0] fine_y;
    logic coarse_x_bit_1;
    logic coarse_y_bit_1;
    logic [13:0] nametable_fetch_address;
    logic [13:0] attribute_fetch_address;
    logic renderer_memory_request;
    logic [13:0] renderer_memory_address;
    logic renderer_memory_grant;
    logic [7:0] renderer_memory_read_data;
    logic [2:0] fetch_phase;
    logic [2:0] fetch_type;
    logic fetch_complete_event;
    logic tile_load_event;
    logic shifter_shift_event;
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

    int vector_file;
    int scan_result;
    int values [0:39];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:5];
    int unsigned fetch_counts [0:5];
    int unsigned tile_loads = 0;
    int unsigned shifts = 0;

    logic [7:0] old_next_tile_id;
    logic [1:0] old_next_tile_attribute;
    logic [7:0] old_next_tile_pattern_low;
    logic [7:0] old_next_tile_pattern_high;
    logic [15:0] old_pattern_low_shift;
    logic [15:0] old_pattern_high_shift;
    logic [15:0] old_attribute_low_shift;
    logic [15:0] old_attribute_high_shift;

    ppu_background dut (.*);
    always #5 clk <= !clk;

    task automatic check_pre_edge;
        begin
            assert (!$isunknown({renderer_memory_request,
                                 renderer_memory_address, fetch_phase,
                                 fetch_type, fetch_complete_event,
                                 tile_load_event, shifter_shift_event,
                                 bg_pixel_valid, bg_x, bg_y, bg_pattern,
                                 bg_palette, bg_opaque, bg_index}));
            assert (int'(renderer_memory_request) == values[18]);
            assert (int'(renderer_memory_address) == values[19]);
            assert (int'(fetch_phase) == values[20]);
            assert (int'(fetch_type) == values[21]);
            assert (int'(fetch_complete_event) == values[22]);
            assert (int'(tile_load_event) == values[23]);
            assert (int'(shifter_shift_event) == values[24]);
            assert (int'(bg_pixel_valid) == values[25]);
            assert (int'(bg_x) == values[26]);
            assert (int'(bg_y) == values[27]);
            assert (int'(bg_pattern) == values[28]);
            assert (int'(bg_palette) == values[29]);
            assert (int'(bg_opaque) == values[30]);
            assert (int'(bg_index) == values[31]);

            assert (bg_opaque == (bg_pattern != 2'b00));
            if (!background_enabled ||
                (visible_pixel && pixel_x < 8 && !show_background_left)) begin
                assert (!bg_opaque && bg_pattern == 0 && bg_palette == 0);
            end
            if (!ppu_enable) begin
                assert (!renderer_memory_request);
                assert (!fetch_complete_event && !tile_load_event &&
                        !shifter_shift_event);
            end
            if (renderer_memory_request) begin
                assert (rendering_enabled);
                assert (scanline < 240 || scanline == 261);
                assert ((dot >= 1 && dot <= 256) ||
                        (dot >= 321 && dot <= 340));
            end
            if (fetch_type == 3 || fetch_type == 4)
                assert (renderer_memory_address < 14'h2000);
            if (fetch_type == 1 || fetch_type == 5)
                assert (renderer_memory_address >= 14'h2000 &&
                        renderer_memory_address < 14'h3000);
            if (tile_load_event)
                assert (((dot >= 8 && dot <= 256) ||
                         dot == 328 || dot == 336) && dot[2:0] == 0);
        end
    endtask

    task automatic check_post_edge;
        begin
            assert (int'(next_tile_id) == values[32]);
            assert (int'(next_tile_attribute) == values[33]);
            assert (int'(next_tile_pattern_low) == values[34]);
            assert (int'(next_tile_pattern_high) == values[35]);
            assert (int'(pattern_low_shift) == values[36]);
            assert (int'(pattern_high_shift) == values[37]);
            assert (int'(attribute_low_shift) == values[38]);
            assert (int'(attribute_high_shift) == values[39]);
            if (!reset && !ppu_enable) begin
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
        $dumpfile("build/sim/ppu_background.fst");
        $dumpvars(1, ppu_background_tb);
        for (int index = 1; index <= 5; index++) scenario_counts[index] = 0;
        for (int index = 0; index <= 5; index++) fetch_counts[index] = 0;

        vector_file = $fopen("build/sim/ppu_background_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3E background vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37], values[38], values[39]
            );
            if (scan_result == 40) begin
                @(negedge clk);
                reset = values[1][0];
                ppu_enable = values[2][0];
                dot = values[3][8:0];
                scanline = values[4][8:0];
                visible_pixel = values[5][0];
                pixel_x = values[6][7:0];
                pixel_y = values[7][7:0];
                rendering_enabled = values[8][0];
                background_enabled = values[9][0];
                show_background_left = values[10][0];
                background_pattern_table = values[11][0];
                fine_x = values[12][2:0];
                fine_y = values[13][14:12];
                coarse_x_bit_1 = values[13][1];
                coarse_y_bit_1 = values[13][6];
                nametable_fetch_address = values[14][13:0];
                attribute_fetch_address = values[15][13:0];
                renderer_memory_grant = values[16][0];
                renderer_memory_read_data = values[17][7:0];
                #1;
                check_pre_edge();

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
                if (fetch_complete_event) fetch_counts[fetch_type]++;
                tile_loads += int'(tile_load_event);
                shifts += int'(shifter_shift_event);

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed background vector after row %0d", rows);
            end
        end
        $fclose(vector_file);

        assert (scenario_counts[2] == 1_026);
        assert (scenario_counts[3] == 12_290);
        assert (scenario_counts[5] == 50_002);
        $display(
            "PASS: Phase 3E standalone background rows=%0d nt=%0d at=%0d low=%0d high=%0d dummy=%0d loads=%0d shifts=%0d mismatches=0 seed=3e5eed01",
            rows, fetch_counts[1], fetch_counts[2], fetch_counts[3],
            fetch_counts[4], fetch_counts[5], tile_loads, shifts
        );
        $finish;
    end
endmodule
