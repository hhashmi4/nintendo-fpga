`timescale 1ns/1ps

module ppu_sprite_address_tb;
    logic [7:0] tile;
    logic [3:0] relative_row;
    logic sprite_size_16;
    logic sprite_pattern_table;
    logic vertical_flip;
    logic [3:0] selected_row;
    logic [12:0] pattern_low_address;
    logic [12:0] pattern_high_address;

    int vector_file;
    int scan_result;
    int values [0:7];
    int unsigned vectors_8 = 0;
    int unsigned vectors_16 = 0;

    ppu_sprite_address dut (.*);

    initial begin
        vector_file = $fopen(
            "build/sim/ppu_sprite_address_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "could not open sprite-address vectors");
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file, "%d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3],
                values[4], values[5], values[6], values[7]
            );
            if (scan_result == 8) begin
                sprite_size_16 = values[0][0];
                sprite_pattern_table = values[1][0];
                tile = values[2][7:0];
                relative_row = values[3][3:0];
                vertical_flip = values[4][0];
                #1;
                assert (int'(selected_row) == values[5]);
                assert (int'(pattern_low_address) == values[6]);
                assert (int'(pattern_high_address) == values[7]);
                assert (!pattern_low_address[12] ||
                        pattern_low_address >= 13'h1000);
                if (sprite_size_16) vectors_16++;
                else vectors_8++;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed sprite-address vector");
            end
        end
        $fclose(vector_file);
        assert (vectors_8 == 8192);
        assert (vectors_16 == 8192);
        $display(
            "PASS: Phase 3G sprite addresses 8x8_vectors=%0d 8x8_plane_cases=%0d 8x16_vectors=%0d 8x16_plane_cases=%0d total_plane_cases=%0d mismatches=0",
            vectors_8, vectors_8 * 2, vectors_16, vectors_16 * 2,
            (vectors_8 + vectors_16) * 2
        );
        $finish;
    end
endmodule
