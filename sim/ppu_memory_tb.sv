`timescale 1ns/1ps

module ppu_memory_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [1:0] mirroring_mode = 2'd0;
    logic access_valid = 1'b0;
    logic access_write = 1'b0;
    logic [13:0] access_address = 14'h0000;
    logic [7:0] access_write_data = 8'h00;
    logic [7:0] access_read_data;
    logic [13:0] buffer_read_address = 14'h2000;
    logic [7:0] buffer_read_data;
    logic [13:0] pixel_palette_address = 14'h3f00;
    logic [7:0] pixel_palette_read_data;
    logic [12:0] chr_addr;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;
    logic [1:0] access_region;
    logic [11:0] normalized_nametable_address;
    logic [1:0] logical_nametable;
    logic [9:0] nametable_offset;
    logic physical_ciram_page;
    logic [10:0] ciram_address;
    logic [4:0] palette_index;
    logic ciram_write_enable;
    logic palette_write_enable;

    // Simulation-only cartridge device. Production ppu_memory contains no
    // CHR storage and exposes this access through its cartridge interface.
    logic [7:0] chr_memory [0:8191];

    int vector_file;
    int scan_result;
    int values [0:24];
    int active_scenario = 0;
    int unsigned row_count = 0;
    int unsigned scenario_rows = 0;
    int unsigned random_reads = 0;
    int unsigned random_writes = 0;
    int unsigned random_regions [0:2];
    int unsigned random_modes [0:3];

    ppu_memory dut (.*);

    assign chr_read_data = chr_memory[chr_addr];

    always #5 clk <= !clk;

    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    task automatic clear_counts;
        begin
            scenario_rows = 0;
            random_reads = 0;
            random_writes = 0;
            for (int index = 0; index < 3; index++) random_regions[index] = 0;
            for (int index = 0; index < 4; index++) random_modes[index] = 0;
        end
    endtask

    task automatic check_scenario(input int completed_scenario);
        begin
            case (completed_scenario)
                1: begin
                    assert (scenario_rows == 65_538);
                    $display(
                        "PPU memory exhaustive decoder PASS: 16384 addresses x 4 modes"
                    );
                end
                2: begin
                    assert (scenario_rows == 66);
                    $display(
                        "PPU memory directed aliases PASS: rows=%0d",
                        scenario_rows
                    );
                end
                3: begin
                    assert (scenario_rows == 100_000);
                    assert (random_reads == 49_906);
                    assert (random_writes == 50_094);
                    assert (random_regions[0] == 50_168);
                    assert (random_regions[1] == 48_226);
                    assert (random_regions[2] == 1_606);
                    assert (random_modes[0] == 24_896);
                    assert (random_modes[1] == 25_048);
                    assert (random_modes[2] == 24_979);
                    assert (random_modes[3] == 25_077);
                    $display(
                        "PPU memory randomized PASS: seed=3c5eed01 accesses=100000 reads=%0d writes=%0d chr=%0d nametable=%0d palette=%0d",
                        random_reads, random_writes, random_regions[0],
                        random_regions[1], random_regions[2]
                    );
                end
                default: $fatal(1, "unknown PPU memory scenario %0d",
                                completed_scenario);
            endcase
        end
    endtask

    task automatic check_pre_edge;
        int destination_count;
        begin
            assert (!$isunknown({access_read_data, buffer_read_data,
                                 pixel_palette_read_data,
                                 chr_addr, chr_read, chr_write,
                                 chr_write_data, access_region,
                                 normalized_nametable_address,
                                 logical_nametable, nametable_offset,
                                 physical_ciram_page, ciram_address,
                                 palette_index, ciram_write_enable,
                                 palette_write_enable}))
                else $fatal(1, "unknown memory output at row %0d", row_count);

            assert (int'(access_read_data) == values[8]);
            assert (int'(buffer_read_data) == values[9]);
            assert (int'(access_region) == values[10]);
            assert (int'(normalized_nametable_address) == values[11]);
            assert (int'(logical_nametable) == values[12]);
            assert (int'(nametable_offset) == values[13]);
            assert (int'(physical_ciram_page) == values[14]);
            assert (int'(ciram_address) == values[15]);
            assert (int'(palette_index) == values[16]);
            assert (int'(chr_addr) == values[17]);
            assert (int'(chr_read) == values[18]);
            assert (int'(chr_write) == values[19]);
            assert (int'(chr_write_data) == values[20]);
            assert (int'(ciram_write_enable) == values[21]);
            assert (int'(palette_write_enable) == values[22]);
            assert (pixel_palette_read_data == dut.palette_ram[0]);

            assert (int'(palette_index) < 32);
            assert (int'(physical_ciram_page) < 2);
            assert (int'(nametable_offset) < 1024);
            assert (int'(chr_addr) < 8192);
            assert (!(chr_read && chr_write));
            assert (!chr_read || access_region == 0);
            assert (!chr_write || access_region == 0);
            assert (!ciram_write_enable || access_region == 1);
            assert (!palette_write_enable || access_region == 2);
            assert (!chr_write || !ciram_write_enable);
            assert (!chr_write || !palette_write_enable);
            assert (!ciram_write_enable || !palette_write_enable);

            destination_count = int'(chr_write) + int'(ciram_write_enable) +
                                int'(palette_write_enable);
            if (!reset && access_valid && access_write)
                assert (destination_count == 1)
                    else $fatal(1, "write did not select exactly one destination");
            else
                assert (destination_count == 0)
                    else $fatal(1, "spurious write destination at row %0d",
                                row_count);
        end
    endtask

    task automatic check_post_edge;
        begin
            // MLAB read-during-write output is deliberately don't-care; the
            // following non-write observations prove the committed contents.
            if (!(values[1] == 0 && values[3] != 0 && values[4] != 0))
                assert (int'(access_read_data) == values[23]);
            assert (int'(buffer_read_data) == values[24]);
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_memory.fst");
        $dumpvars(1, ppu_memory_tb);

        // Deterministic simulation state without adding production RAM reset
        // networks. Real CIRAM/palette power-up contents remain unspecified.
        for (int index = 0; index < 2048; index++) dut.ciram[index] = 8'h00;
        for (int index = 0; index < 32; index++) dut.palette_ram[index] = 8'h00;
        for (int index = 0; index < 8192; index++) chr_memory[index] = 8'h00;

        vector_file = $fopen("build/sim/ppu_memory_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3C memory reference vectors");

        clear_counts();
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24]
            );
            if (scan_result == 25) begin
                if (active_scenario != values[0]) begin
                    if (active_scenario != 0) check_scenario(active_scenario);
                    active_scenario = values[0];
                    clear_counts();
                end

                @(negedge clk);
                reset = values[1][0];
                mirroring_mode = values[2][1:0];
                access_valid = values[3][0];
                access_write = values[4][0];
                access_address = values[5][13:0];
                access_write_data = values[6][7:0];
                buffer_read_address = values[7][13:0];
                #1;
                check_pre_edge();

                row_count++;
                scenario_rows++;
                if (values[0] == 3) begin
                    if (values[4] != 0) random_writes++;
                    else random_reads++;
                    random_regions[values[10]]++;
                    random_modes[values[2]]++;
                end

                @(posedge clk);
                #1;
                check_post_edge();
            end else if (scan_result != -1) begin
                $fatal(1, "malformed PPU memory vector after row %0d", row_count);
            end
        end
        check_scenario(active_scenario);
        $fclose(vector_file);
        assert (row_count == 165_604);

        $display(
            "PASS: Phase 3C PPU memory (%0d Python-reference cycles, mismatches=0)",
            row_count
        );
        $finish;
    end
endmodule
