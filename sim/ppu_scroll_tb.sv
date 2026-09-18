`timescale 1ns/1ps

module ppu_scroll_tb;
    logic [14:0] vram_address;
    logic [14:0] temp_vram_address;
    logic ppu_enable;
    logic rendering_enabled;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic rendering_scanline;
    logic active_render_period;
    logic coarse_x_increment_event;
    logic vertical_increment_event;
    logic horizontal_copy_event;
    logic vertical_copy_event;
    logic automatic_scroll_event;
    logic [14:0] automatic_vram_address;
    logic [14:0] active_data_increment_address;
    logic [13:0] nametable_fetch_address;
    logic [13:0] attribute_fetch_address;

    int vector_file;
    int scan_result;
    int values [0:17];
    int unsigned rows = 0;
    int unsigned scenario_counts [1:4];

    ppu_scroll dut (.*);

    task automatic check_outputs;
        begin
            assert (!$isunknown({rendering_scanline, active_render_period,
                                 coarse_x_increment_event,
                                 vertical_increment_event,
                                 horizontal_copy_event, vertical_copy_event,
                                 automatic_scroll_event,
                                 automatic_vram_address,
                                 active_data_increment_address,
                                 nametable_fetch_address,
                                 attribute_fetch_address}));
            assert (int'(rendering_scanline) == values[7]);
            assert (int'(active_render_period) == values[8]);
            assert (int'(coarse_x_increment_event) == values[9]);
            assert (int'(vertical_increment_event) == values[10]);
            assert (int'(horizontal_copy_event) == values[11]);
            assert (int'(vertical_copy_event) == values[12]);
            assert (int'(automatic_scroll_event) == values[13]);
            assert (int'(automatic_vram_address) == values[14]);
            assert (int'(active_data_increment_address) == values[15]);
            assert (int'(nametable_fetch_address) == values[16]);
            assert (int'(attribute_fetch_address) == values[17]);

            if (!automatic_scroll_event)
                assert (automatic_vram_address == vram_address);
            if (horizontal_copy_event && !vertical_copy_event) begin
                assert ((automatic_vram_address & 15'h041f) ==
                        (temp_vram_address & 15'h041f));
            end
            assert (nametable_fetch_address[13:12] == 2'b10);
            assert (attribute_fetch_address[13:10] >= 4'b1000 &&
                    attribute_fetch_address[13:10] <= 4'b1011);
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_scroll.fst");
        $dumpvars(1, ppu_scroll_tb);
        for (int index = 1; index <= 4; index++) scenario_counts[index] = 0;

        vector_file = $fopen("build/sim/ppu_scroll_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3D scroll vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17]
            );
            if (scan_result == 18) begin
                vram_address = values[1][14:0];
                temp_vram_address = values[2][14:0];
                ppu_enable = values[3][0];
                rendering_enabled = values[4][0];
                dot = values[5][8:0];
                scanline = values[6][8:0];
                #1;
                check_outputs();
                rows++;
                scenario_counts[values[0]]++;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed scroll vector after row %0d", rows);
            end
        end
        $fclose(vector_file);

        assert (rows == 53_344);
        assert (scenario_counts[1] == 64);
        assert (scenario_counts[2] == 512);
        assert (scenario_counts[3] == 32_768);
        assert (scenario_counts[4] == 20_000);
        $display(
            "PASS: Phase 3D standalone scroll (rows=%0d coarse_x=%0d vertical=%0d helpers=%0d random=%0d mismatches=0)",
            rows, scenario_counts[1], scenario_counts[2],
            scenario_counts[3], scenario_counts[4]
        );
        $finish;
    end
endmodule
