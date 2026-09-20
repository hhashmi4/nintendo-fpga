`timescale 1ns/1ps

module ppu_sprite_range_tb;
    logic [7:0] scanline;
    logic [7:0] sprite_y;
    logic sprite_size_16;
    logic [7:0] relative_row;
    logic [4:0] sprite_height;
    logic in_range;

    int vector_file;
    int scan_result;
    int values [0:5];
    int unsigned cases = 0;

    ppu_sprite_range dut (.*);

    initial begin
        vector_file = $fopen("build/sim/ppu_sprite_range_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3F range vectors");
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5]
            );
            if (scan_result == 6) begin
                scanline = values[0][7:0];
                sprite_y = values[1][7:0];
                sprite_size_16 = values[2][0];
                #1;
                assert (!$isunknown({relative_row, sprite_height, in_range}));
                assert (int'(relative_row) == values[3]);
                assert (int'(sprite_height) == values[4]);
                assert (int'(in_range) == values[5]);
                cases++;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed sprite-range vector after case %0d", cases);
            end
        end
        $fclose(vector_file);
        assert (cases == 122_880);
        $display("PASS: Phase 3F sprite range cases=%0d mismatches=0", cases);
        $finish;
    end
endmodule
