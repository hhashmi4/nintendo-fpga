`timescale 1ns/1ps

module ppu_phase3g_tb;
    logic clk = 1'b0;
    logic reset;
    logic ppu_enable;
    logic cpu_enable;
    logic cpu_bus_valid;
    logic cpu_bus_write;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [7:0] cpu_read_data;
    logic sprite_zero_hit_set = 1'b0;
    logic [1:0] mirroring_mode = 2'b00;
    logic [12:0] chr_addr;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic frame_odd;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic frame_end;
    logic [7:0] ppuctrl;
    logic [7:0] ppumask;
    logic [2:0] secondary_read_slot = 3'd0;
    logic renderer_memory_request;
    logic renderer_memory_grant;
    logic renderer_cpu_collision;
    logic sprite_memory_request;
    logic [13:0] sprite_memory_address;
    logic sprite_memory_grant;
    logic [7:0] sprite_memory_read_data;
    logic renderer_owner_conflict;
    logic [2:0] sprite_fetch_type;
    logic sprite_fetch_complete;
    logic sprite_slot_load;
    logic [3:0] sprite_fetch_selected_row;
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

    logic [7:0] chr_memory [0:8191];
    int pixel_file;
    int stats_file;
    int scan_result;
    int values [0:10];
    int expected [0:4];
    int unsigned visible_coordinates = 0;
    int unsigned opaque_pixels = 0;
    int unsigned transparent_pixels = 0;
    int unsigned sprite_zero_pixels = 0;
    int unsigned clipped_pixels = 0;
    int unsigned slots_loaded = 0;
    int unsigned chr_low_fetches = 0;
    int unsigned chr_high_fetches = 0;
    int unsigned dummy_fetches = 0;
    int unsigned x_decrements = 0;
    int unsigned sprite_shifts = 0;
    int unsigned memory_collisions = 0;
    logic done = 1'b0;
    logic observation_parity;

    /* verilator lint_off PINMISSING */
    ppu_sprite_core dut (
        .clk                               (clk),
        .reset                             (reset),
        .ppu_enable                        (ppu_enable),
        .cpu_enable                        (cpu_enable),
        .cpu_bus_valid                     (cpu_bus_valid),
        .cpu_bus_write                     (cpu_bus_write),
        .cpu_address                       (cpu_address),
        .cpu_write_data                    (cpu_write_data),
        .cpu_read_data                     (cpu_read_data),
        .sprite_zero_hit_set               (sprite_zero_hit_set),
        .mirroring_mode                    (mirroring_mode),
        .chr_addr                          (chr_addr),
        .chr_read                          (chr_read),
        .chr_write                         (chr_write),
        .chr_write_data                    (chr_write_data),
        .chr_read_data                     (chr_read_data),
        .dot                               (dot),
        .scanline                          (scanline),
        .frame_odd                         (frame_odd),
        .visible_pixel                     (visible_pixel),
        .pixel_x                           (pixel_x),
        .pixel_y                           (pixel_y),
        .frame_end                         (frame_end),
        .ppuctrl                           (ppuctrl),
        .ppumask                           (ppumask),
        .secondary_read_slot               (secondary_read_slot),
        .renderer_memory_request           (renderer_memory_request),
        .renderer_memory_grant             (renderer_memory_grant),
        .renderer_cpu_collision            (renderer_cpu_collision),
        .sprite_memory_request             (sprite_memory_request),
        .sprite_memory_address             (sprite_memory_address),
        .sprite_memory_grant               (sprite_memory_grant),
        .sprite_memory_read_data           (sprite_memory_read_data),
        .renderer_owner_conflict           (renderer_owner_conflict),
        .sprite_fetch_type                 (sprite_fetch_type),
        .sprite_fetch_complete             (sprite_fetch_complete),
        .sprite_slot_load                  (sprite_slot_load),
        .sprite_fetch_selected_row         (sprite_fetch_selected_row),
        .sprite_decrement_mask             (sprite_decrement_mask),
        .sprite_shift_mask                 (sprite_shift_mask),
        .sprite_pixel_valid                (sprite_pixel_valid),
        .sprite_x                          (sprite_x),
        .sprite_y                          (sprite_y),
        .sprite_pattern                    (sprite_pattern),
        .sprite_palette                    (sprite_palette),
        .sprite_palette_index              (sprite_palette_index),
        .sprite_opaque                     (sprite_opaque),
        .sprite_priority_behind_background (sprite_priority_behind_background),
        .sprite_is_zero                    (sprite_is_zero),
        .sprite_slot                       (sprite_slot),
        .sprite_original_index             (sprite_original_index)
    );
    /* verilator lint_on PINMISSING */

    assign chr_read_data = chr_memory[chr_addr];
    assign observation_parity = ^{
        cpu_read_data, frame_odd, chr_read, chr_write_data,
        dot, scanline,
        renderer_memory_request, renderer_memory_grant,
        sprite_memory_request, sprite_memory_address,
        sprite_memory_grant, sprite_memory_read_data,
        sprite_fetch_selected_row
    };
    always #5 clk <= !clk;
    always_ff @(posedge clk) begin
        if (chr_write) chr_memory[chr_addr] <= chr_write_data;
    end

    function automatic int unsigned bit_count(input logic [7:0] value);
        bit_count = 0;
        for (int bit_index = 0; bit_index < 8; bit_index++)
            bit_count += int'(value[bit_index]);
    endfunction

    task automatic register_write(input logic [2:0] index,
                                  input logic [7:0] data);
        begin
            @(negedge clk);
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
        $dumpfile("build/sim/ppu_phase3g.fst");
        $dumpvars(1, ppu_phase3g_tb);
        $readmemh("build/sim/ppu_phase3g_oam.hex", dut.oam.primary_oam);
        $readmemh("build/sim/ppu_phase3g_chr.hex", chr_memory);
        for (int index = 0; index < 2048; index++)
            dut.background_core.memory.ciram[index] = 8'h00;
        for (int index = 0; index < 32; index++) begin
            dut.background_core.memory.palette_ram[index] = 8'h00;
            dut.oam.secondary_oam[index] = 8'hff;
        end
        for (int index = 0; index < 8; index++)
            dut.oam.secondary_sprite_index[index] = 6'd0;

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
        // 8x16 sprites; PPUCTRL bit 3 is intentionally set even though the
        // 8x16 bank must come only from tile bit 0.
        register_write(3'd0, 8'h28);
        // Sprites enabled, sprite-left disabled, background disabled.
        register_write(3'd1, 8'h10);
        assert (ppuctrl == 8'h28 && ppumask == 8'h10);

        pixel_file = $fopen(
            "build/sim/ppu_phase3g_pixels_reference.txt", "r"
        );
        assert (pixel_file != 0);
        @(negedge clk);
        ppu_enable = 1'b1;

        while (!done) begin
            @(negedge clk);
            #1;
            assert (!renderer_owner_conflict);
            assert (!renderer_cpu_collision);
            assert (!chr_write);
            assert (!$isunknown(observation_parity));
            slots_loaded += int'(sprite_slot_load);
            chr_low_fetches += int'(sprite_fetch_complete &&
                                    sprite_fetch_type == 3);
            chr_high_fetches += int'(sprite_fetch_complete &&
                                     sprite_fetch_type == 4);
            dummy_fetches += int'(sprite_fetch_complete &&
                                  (sprite_fetch_type == 1 ||
                                   sprite_fetch_type == 2));
            x_decrements += bit_count(sprite_decrement_mask);
            sprite_shifts += bit_count(sprite_shift_mask);
            memory_collisions += int'(renderer_cpu_collision);

            if (visible_pixel) begin
                scan_result = $fscanf(
                    pixel_file,
                    "%d %d %d %d %d %d %d %d %d %d %d\n",
                    values[0], values[1], values[2], values[3], values[4],
                    values[5], values[6], values[7], values[8], values[9],
                    values[10]
                );
                assert (scan_result == 11);
                assert (int'(pixel_x) == values[0]);
                assert (int'(pixel_y) == values[1]);
                assert (sprite_pixel_valid);
                assert (sprite_x == pixel_x && sprite_y == pixel_y);
                assert (int'(sprite_pattern) == values[2]);
                assert (int'(sprite_palette) == values[3]);
                assert (int'(sprite_palette_index) == values[4]);
                assert (int'(sprite_opaque) == values[5])
                    else $fatal(1, "opaque mismatch x=%0d y=%0d", pixel_x,
                                pixel_y);
                assert (int'(sprite_priority_behind_background) == values[6]);
                assert (int'(sprite_is_zero) == values[7]);
                assert (int'(sprite_slot) == values[8]);
                assert (int'(sprite_original_index) == values[9]);
                visible_coordinates++;
                opaque_pixels += int'(sprite_opaque);
                transparent_pixels += int'(!sprite_opaque);
                sprite_zero_pixels += int'(sprite_opaque && sprite_is_zero);
                clipped_pixels += values[10];
            end
            if (frame_end) done = 1'b1;
        end
        $fclose(pixel_file);

        stats_file = $fopen("build/sim/ppu_phase3g_frame_stats.txt", "r");
        assert (stats_file != 0);
        scan_result = $fscanf(
            stats_file, "%d %d %d %d %d\n",
            expected[0], expected[1], expected[2], expected[3], expected[4]
        );
        assert (scan_result == 5);
        $fclose(stats_file);
        assert (visible_coordinates == expected[0]);
        assert (opaque_pixels == expected[1]);
        assert (transparent_pixels == expected[2]);
        assert (sprite_zero_pixels == expected[3]);
        assert (clipped_pixels == expected[4]);
        assert (slots_loaded == 1920);
        assert (chr_low_fetches == 1920);
        assert (chr_high_fetches == 1920);
        assert (dummy_fetches == 3840);
        assert (memory_collisions == 0);
        $display(
            "PASS: integrated Phase 3G full frame visible=%0d opaque=%0d transparent=%0d sprite_zero=%0d clipped=%0d slots=%0d low=%0d high=%0d dummy=%0d decrements=%0d shifts=%0d collisions=%0d mismatches=0 seed=3f37a6e1",
            visible_coordinates, opaque_pixels, transparent_pixels,
            sprite_zero_pixels, clipped_pixels, slots_loaded,
            chr_low_fetches, chr_high_fetches, dummy_fetches,
            x_decrements, sprite_shifts, memory_collisions
        );
        $finish;
    end
endmodule
