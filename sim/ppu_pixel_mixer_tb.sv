`timescale 1ns/1ps

module ppu_pixel_mixer_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ppu_enable = 1'b0;
    logic visible_pixel = 1'b0;
    logic [7:0] pixel_x = 8'h00;
    logic [7:0] pixel_y = 8'h00;
    logic background_enabled = 1'b0;
    logic sprites_enabled = 1'b0;
    logic show_background_left = 1'b0;
    logic show_sprites_left = 1'b0;
    logic grayscale = 1'b0;
    logic [2:0] emphasis = 3'b000;
    logic bg_pixel_valid = 1'b0;
    logic [7:0] bg_x = 8'h00;
    logic [7:0] bg_y = 8'h00;
    logic [1:0] bg_pattern = 2'b00;
    logic [1:0] bg_palette = 2'b00;
    logic bg_opaque = 1'b0;
    logic sprite_pixel_valid = 1'b0;
    logic [7:0] sprite_x = 8'h00;
    logic [7:0] sprite_y = 8'h00;
    logic [1:0] sprite_pattern = 2'b00;
    logic [1:0] sprite_palette = 2'b00;
    logic sprite_opaque = 1'b0;
    logic sprite_priority_behind_background = 1'b0;
    logic sprite_is_zero = 1'b0;
    logic [2:0] sprite_slot = 3'd0;
    logic [5:0] sprite_original_index = 6'd0;
    logic [13:0] palette_address;
    logic [7:0] palette_read_data = 8'h00;
    logic final_pixel_valid;
    logic [7:0] final_pixel_x;
    logic [7:0] final_pixel_y;
    logic [5:0] nes_color;
    logic [2:0] color_emphasis;
    logic [1:0] pixel_source;
    logic sprite_zero_hit_event;
    logic [2:0] winning_sprite_slot;
    logic winning_sprite_zero;

    int vector_file;
    int stats_file;
    int scan_result;
    int values [0:37];
    int expected [0:9];
    int unsigned counters [0:9];

    ppu_pixel_mixer dut (.*);
    always #5 clk <= !clk;

    task automatic check_outputs;
        begin
            assert (int'(palette_address) == values[28]);
            assert (int'(final_pixel_valid) == values[29]);
            assert (int'(final_pixel_x) == values[30]);
            assert (int'(final_pixel_y) == values[31]);
            assert (int'(nes_color) == values[32]);
            assert (int'(color_emphasis) == values[33]);
            assert (int'(pixel_source) == values[34]);
            assert (int'(sprite_zero_hit_event) == values[35]);
            assert (int'(winning_sprite_slot) == values[36]);
            assert (int'(winning_sprite_zero) == values[37]);
            assert (!$isunknown({palette_address, final_pixel_valid,
                                 final_pixel_x, final_pixel_y, nes_color,
                                 color_emphasis, pixel_source,
                                 sprite_zero_hit_event,
                                 winning_sprite_slot,
                                 winning_sprite_zero}));
        end
    endtask

    initial begin
        for (int index = 0; index < 10; index++) counters[index] = 0;
        vector_file = $fopen("build/sim/ppu_pixel_mixer_reference.txt", "r");
        assert (vector_file != 0);
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30], values[31], values[32], values[33], values[34],
                values[35], values[36], values[37]
            );
            if (scan_result == 38) begin
                @(negedge clk);
                reset = values[0][0];
                ppu_enable = values[1][0];
                visible_pixel = values[2][0];
                pixel_x = values[3][7:0];
                pixel_y = values[4][7:0];
                background_enabled = values[5][0];
                sprites_enabled = values[6][0];
                show_background_left = values[7][0];
                show_sprites_left = values[8][0];
                grayscale = values[9][0];
                emphasis = values[10][2:0];
                bg_pixel_valid = values[11][0];
                bg_x = values[12][7:0];
                bg_y = values[13][7:0];
                bg_pattern = values[14][1:0];
                bg_palette = values[15][1:0];
                bg_opaque = values[16][0];
                sprite_pixel_valid = values[17][0];
                sprite_x = values[18][7:0];
                sprite_y = values[19][7:0];
                sprite_pattern = values[20][1:0];
                sprite_palette = values[21][1:0];
                sprite_opaque = values[22][0];
                sprite_priority_behind_background = values[23][0];
                sprite_is_zero = values[24][0];
                sprite_slot = values[25][2:0];
                sprite_original_index = values[26][5:0];
                palette_read_data = values[27][7:0];
                #1;
                check_outputs();
                counters[0]++;
                counters[1] += int'(ppu_enable);
                counters[2] += int'(!ppu_enable);
                counters[3] += int'(final_pixel_valid);
                if (final_pixel_valid)
                    counters[4 + int'(pixel_source)]++;
                counters[7] += int'(final_pixel_valid);
                counters[8] += int'(sprite_zero_hit_event);
                counters[9] += int'(final_pixel_valid && grayscale);
                @(posedge clk);
                #1;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 3H mixer vector");
            end
        end
        $fclose(vector_file);

        stats_file = $fopen("build/sim/ppu_pixel_mixer_stats.txt", "r");
        assert (stats_file != 0);
        scan_result = $fscanf(
            stats_file, "%d %d %d %d %d %d %d %d %d %d\n",
            expected[0], expected[1], expected[2], expected[3], expected[4],
            expected[5], expected[6], expected[7], expected[8], expected[9]
        );
        assert (scan_result == 10);
        $fclose(stats_file);
        for (int index = 0; index < 10; index++)
            assert (counters[index] == expected[index]);
        $display(
            "PASS: Phase 3H mixer seed=38202601 fabric=%0d ticks=%0d stalls=%0d pixels=%0d universal=%0d background=%0d sprite=%0d palette_reads=%0d zero_hits=%0d grayscale=%0d mismatches=0",
            counters[0], counters[1], counters[2], counters[3], counters[4],
            counters[5], counters[6], counters[7], counters[8], counters[9]
        );
        $finish;
    end
endmodule
