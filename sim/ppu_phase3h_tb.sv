`timescale 1ns/1ps

module ppu_phase3h_tb;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic cpu_enable;
    logic cpu_bus_valid;
    logic cpu_bus_write;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [7:0] cpu_read_data;
    logic [1:0] mirroring_mode = 2'b00;
    logic [12:0] chr_addr;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic [7:0] ppuctrl;
    logic [7:0] ppumask;
    logic status_vblank;
    logic status_sprite_zero_hit;
    logic status_sprite_overflow;
    logic write_toggle;
    logic [2:0] secondary_read_slot = 3'd0;
    logic final_pixel_valid;
    logic [7:0] final_pixel_x;
    logic [7:0] final_pixel_y;
    logic [13:0] final_palette_address;
    logic [5:0] final_nes_color;
    logic [2:0] final_color_emphasis;
    logic [1:0] final_pixel_source;
    logic sprite_zero_hit_event;
    logic [2:0] final_winning_sprite_slot;
    logic final_winning_sprite_zero;
    logic bg_opaque;
    logic sprite_opaque;
    logic sprite_priority_behind_background;
    logic sprite_is_zero;
    logic [5:0] sprite_original_index;
    logic sprite_overflow_set;

    logic [7:0] chr_memory [0:8191];
    int pixel_file;
    int stats_file;
    int scan_result;
    int values [0:6];
    int expected [0:7];
    int unsigned fabric_cycles = 0;
    int unsigned enabled_ticks = 0;
    int unsigned stalls = 0;
    int unsigned visible_coordinates = 0;
    int unsigned source_counts [0:2];
    int unsigned palette_reads = 0;
    int unsigned zero_hit_events = 0;
    int unsigned grayscale_pixels = 0;
    int unsigned behind_zero_hit_pixels = 0;
    logic [31:0] stall_state = 32'h38a1105e;
    logic pending_hit;
    logic [7:0] status_read_data;
    logic observation_parity;

    /* verilator lint_off PINMISSING */
    ppu_sprite_core dut (
        .clk                       (clk),
        .reset                     (reset),
        .ppu_enable                (ppu_enable),
        .cpu_enable                (cpu_enable),
        .cpu_bus_valid             (cpu_bus_valid),
        .cpu_bus_write             (cpu_bus_write),
        .cpu_address               (cpu_address),
        .cpu_write_data            (cpu_write_data),
        .cpu_read_data             (cpu_read_data),
        .mirroring_mode            (mirroring_mode),
        .chr_addr                  (chr_addr),
        .chr_read                  (chr_read),
        .chr_write                 (chr_write),
        .chr_write_data            (chr_write_data),
        .chr_read_data             (chr_read_data),
        .dot                       (dot),
        .scanline                  (scanline),
        .visible_pixel             (visible_pixel),
        .pixel_x                   (pixel_x),
        .pixel_y                   (pixel_y),
        .ppuctrl                   (ppuctrl),
        .ppumask                   (ppumask),
        .status_vblank             (status_vblank),
        .status_sprite_zero_hit    (status_sprite_zero_hit),
        .status_sprite_overflow    (status_sprite_overflow),
        .write_toggle              (write_toggle),
        .secondary_read_slot       (secondary_read_slot),
        .final_pixel_valid         (final_pixel_valid),
        .final_pixel_x             (final_pixel_x),
        .final_pixel_y             (final_pixel_y),
        .final_palette_address     (final_palette_address),
        .final_nes_color           (final_nes_color),
        .final_color_emphasis      (final_color_emphasis),
        .final_pixel_source        (final_pixel_source),
        .sprite_zero_hit_event     (sprite_zero_hit_event),
        .final_winning_sprite_slot (final_winning_sprite_slot),
        .final_winning_sprite_zero (final_winning_sprite_zero),
        .bg_opaque                 (bg_opaque),
        .sprite_opaque             (sprite_opaque),
        .sprite_priority_behind_background
                                   (sprite_priority_behind_background),
        .sprite_is_zero            (sprite_is_zero),
        .sprite_original_index     (sprite_original_index),
        .sprite_overflow_set       (sprite_overflow_set)
    );
    /* verilator lint_on PINMISSING */

    assign chr_read_data = chr_memory[chr_addr];
    assign observation_parity = ^{
        chr_read, pixel_x, pixel_y, final_winning_sprite_slot,
        final_winning_sprite_zero, sprite_overflow_set
    };
    always #5 clk <= !clk;
    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    function automatic logic [31:0] xorshift32(input logic [31:0] value);
        logic [31:0] next_value;
        begin
            next_value = value;
            next_value = next_value ^ (next_value << 13);
            next_value = next_value ^ (next_value >> 17);
            next_value = next_value ^ (next_value << 5);
            xorshift32 = next_value;
        end
    endfunction

    task automatic register_write(input logic [2:0] index,
                                  input logic [7:0] data);
        begin
            @(negedge clk);
            ppu_enable = 1'b0;
            cpu_enable = 1'b1;
            cpu_bus_valid = 1'b1;
            cpu_bus_write = 1'b1;
            cpu_address = 16'h2000 + {13'd0, index};
            cpu_write_data = data;
            @(posedge clk);
            #1;
            @(negedge clk);
            cpu_enable = 1'b0;
            cpu_bus_valid = 1'b0;
            cpu_bus_write = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_phase3h.fst");
        $dumpvars(1, ppu_phase3h_tb);
        $readmemh("build/sim/ppu_phase3h_ciram.hex",
                  dut.background_core.memory.ciram);
        $readmemh("build/sim/ppu_phase3h_chr.hex", chr_memory);
        $readmemh("build/sim/ppu_phase3h_oam.hex", dut.oam.primary_oam);
        $readmemh("build/sim/ppu_phase3h_palette.hex",
                  dut.background_core.memory.palette_ram);
        for (int index = 0; index < 32; index++)
            dut.oam.secondary_oam[index] = 8'hff;
        for (int index = 0; index < 8; index++)
            dut.oam.secondary_sprite_index[index] = 6'd0;
        for (int index = 0; index < 3; index++) source_counts[index] = 0;

        reset = 1'b1;
        ppu_enable = 1'b0;
        cpu_enable = 1'b0;
        cpu_bus_valid = 1'b0;
        cpu_bus_write = 1'b0;
        cpu_address = 16'h0000;
        cpu_write_data = 8'h00;
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        register_write(3'd0, 8'h10);
        register_write(3'd1, 8'hbe);
        assert (ppuctrl == 8'h10 && ppumask == 8'hbe);

        pixel_file = $fopen(
            "build/sim/ppu_phase3h_pixels_reference.txt", "r"
        );
        assert (pixel_file != 0);

        while (visible_coordinates < 61_440) begin
            @(negedge clk);
            stall_state = xorshift32(stall_state);
            ppu_enable = stall_state[7:0] < 8'd205;
            #1;
            assert (!$isunknown(observation_parity));
            fabric_cycles++;
            enabled_ticks += int'(ppu_enable);
            stalls += int'(!ppu_enable);
            if (!ppu_enable) begin
                assert (!visible_pixel);
                assert (!final_pixel_valid);
                assert (!sprite_zero_hit_event);
            end
            pending_hit = sprite_zero_hit_event;
            if (final_pixel_valid) begin
                scan_result = $fscanf(
                    pixel_file, "%d %d %d %d %d %d %d\n",
                    values[0], values[1], values[2], values[3], values[4],
                    values[5], values[6]
                );
                assert (scan_result == 7);
                assert (int'(final_pixel_x) == values[0]);
                assert (int'(final_pixel_y) == values[1]);
                assert (int'(final_pixel_source) == values[2]);
                assert (int'(final_palette_address) == values[3]);
                assert (int'(final_nes_color) == values[4]);
                assert (int'(final_color_emphasis) == values[5]);
                assert (int'(sprite_zero_hit_event) == values[6]);
                assert (final_palette_address >= 14'h3f00 &&
                        final_palette_address <= 14'h3f1f);
                visible_coordinates++;
                source_counts[final_pixel_source]++;
                palette_reads++;
                zero_hit_events += int'(sprite_zero_hit_event);
                grayscale_pixels += int'(ppumask[0]);
                behind_zero_hit_pixels += int'(
                    sprite_zero_hit_event &&
                    sprite_priority_behind_background &&
                    final_pixel_source == 2'd1
                );
                if (sprite_zero_hit_event) begin
                    assert (bg_opaque && sprite_opaque && sprite_is_zero);
                    assert (sprite_original_index == 0);
                    assert (final_pixel_x != 8'd255);
                end
            end
            @(posedge clk);
            #1;
            if (pending_hit) assert (status_sprite_zero_hit);
        end
        $fclose(pixel_file);

        stats_file = $fopen("build/sim/ppu_phase3h_frame_stats.txt", "r");
        assert (stats_file != 0);
        scan_result = $fscanf(
            stats_file, "%d %d %d %d %d %d %d %d\n",
            expected[0], expected[1], expected[2], expected[3],
            expected[4], expected[5], expected[6], expected[7]
        );
        assert (scan_result == 8);
        $fclose(stats_file);
        assert (visible_coordinates == expected[0]);
        assert (source_counts[0] == expected[1]);
        assert (source_counts[1] == expected[2]);
        assert (source_counts[2] == expected[3]);
        assert (palette_reads == expected[4]);
        assert (zero_hit_events == expected[5]);
        assert (grayscale_pixels == expected[6]);
        assert (behind_zero_hit_pixels == expected[7]);
        assert (status_sprite_zero_hit);
        assert (status_sprite_overflow);
        assert (!status_vblank);

        // Enter vblank and confirm all status flags are independently set.
        while (!(scanline == 9'd241 && dot == 9'd2)) begin
            @(negedge clk);
            ppu_enable = 1'b1;
            @(posedge clk);
            #1;
        end
        assert (status_vblank && status_sprite_zero_hit &&
                status_sprite_overflow);

        // Set w, then read PPUSTATUS. Only vblank and w clear.
        register_write(3'd5, 8'h12);
        assert (write_toggle);
        @(negedge clk);
        ppu_enable = 1'b0;
        cpu_enable = 1'b1;
        cpu_bus_valid = 1'b1;
        cpu_bus_write = 1'b0;
        cpu_address = 16'h2002;
        #1;
        status_read_data = cpu_read_data;
        assert (status_read_data[7:5] == 3'b111);
        @(posedge clk);
        #1;
        assert (!status_vblank);
        assert (status_sprite_zero_hit);
        assert (status_sprite_overflow);
        assert (!write_toggle);
        @(negedge clk);
        cpu_enable = 1'b0;
        cpu_bus_valid = 1'b0;

        // Existing pre-render dot-1 clear owns all three status latches.
        while (!(scanline == 9'd261 && dot == 9'd2)) begin
            @(negedge clk);
            ppu_enable = 1'b1;
            @(posedge clk);
            #1;
        end
        assert (!status_vblank && !status_sprite_zero_hit &&
                !status_sprite_overflow);

        $display(
            "PASS: integrated Phase 3H seed=3f38a6e1 stall_seed=38a1105e fabric=%0d ticks=%0d stalls=%0d visible=%0d universal=%0d background=%0d sprite=%0d palette_reads=%0d zero_hits=%0d grayscale=%0d behind_zero_hits=%0d mismatches=0 status_read=%02x",
            fabric_cycles, enabled_ticks, stalls, visible_coordinates,
            source_counts[0], source_counts[1], source_counts[2],
            palette_reads, zero_hit_events, grayscale_pixels,
            behind_zero_hit_pixels, status_read_data
        );
        $finish;
    end
endmodule
