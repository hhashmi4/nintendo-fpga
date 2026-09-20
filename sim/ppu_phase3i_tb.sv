`timescale 1ns/1ps

module ppu_phase3i_tb;
    /* verilator lint_off WIDTHTRUNC */
    /* verilator lint_off WIDTHEXPAND */
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ppu_enable = 1'b0;
    logic cpu_enable = 1'b0;
    logic cpu_bus_valid = 1'b0;
    logic cpu_bus_write = 1'b0;
    logic [15:0] cpu_address = 16'h0000;
    logic [7:0] cpu_write_data = 8'h00;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [7:0] cpu_read_data;
    /* verilator lint_on UNUSEDSIGNAL */
    logic sprite_zero_hit_set = 1'b0;
    logic sprite_overflow_set = 1'b0;

    logic [8:0] dot;
    logic [8:0] scanline;
    logic frame_odd;
    logic timing_vblank;
    logic vblank_start;
    logic vblank_end;
    logic [7:0] ppuctrl;
    logic status_vblank;
    logic status_sprite_zero_hit;
    logic status_sprite_overflow;
    logic nmi_enable;
    logic ppu_nmi_level;
    logic ppu_nmi_event;
    logic ppu_nmi_suppressed;

    integer vector_file;
    integer stats_file;
    integer scan_result;
    integer values [0:30];
    integer expected [0:11];
    longint unsigned fabric_cycles = 0;
    longint unsigned enabled_ticks = 0;
    longint unsigned stalls = 0;
    longint unsigned frame_boundaries = 0;
    longint unsigned vblank_sets = 0;
    longint unsigned vblank_clears = 0;
    longint unsigned status_reads = 0;
    longint unsigned control_writes = 0;
    longint unsigned condition_activations = 0;
    longint unsigned nmi_events = 0;
    longint unsigned suppressed_nmis = 0;
    logic old_status_vblank;
    logic old_nmi_level;

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    /* verilator lint_off PINMISSING */
    ppu_core dut (
        .clk                         (clk),
        .reset                       (reset),
        .ppu_enable                  (ppu_enable),
        .cpu_enable                  (cpu_enable),
        .cpu_bus_valid               (cpu_bus_valid),
        .cpu_bus_write               (cpu_bus_write),
        .cpu_address                 (cpu_address),
        .cpu_write_data              (cpu_write_data),
        .cpu_read_data               (cpu_read_data),
        .sprite_zero_hit_set         (sprite_zero_hit_set),
        .sprite_overflow_set         (sprite_overflow_set),
        .oam_read_data               (8'h00),
        .ppu_memory_read_data        (8'h00),
        .ppu_memory_buffer_read_data (8'h00),
        .dot                         (dot),
        .scanline                    (scanline),
        .frame_odd                   (frame_odd),
        .timing_vblank               (timing_vblank),
        .vblank_start                (vblank_start),
        .vblank_end                  (vblank_end),
        .ppuctrl                     (ppuctrl),
        .status_vblank               (status_vblank),
        .status_sprite_zero_hit      (status_sprite_zero_hit),
        .status_sprite_overflow      (status_sprite_overflow),
        .nmi_enable                  (nmi_enable),
        .ppu_nmi_level               (ppu_nmi_level),
        .ppu_nmi_event               (ppu_nmi_event),
        .ppu_nmi_suppressed          (ppu_nmi_suppressed)
    );
    /* verilator lint_on PINMISSING */

    initial begin
        $dumpfile("build/sim/ppu_phase3i.fst");
        $dumpvars(0, ppu_phase3i_tb);

        vector_file = $fopen("build/sim/ppu_phase3i_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Phase 3I reference vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                values[0], values[1], values[2], values[3], values[4],
                values[5], values[6], values[7], values[8], values[9],
                values[10], values[11], values[12], values[13], values[14],
                values[15], values[16], values[17], values[18], values[19],
                values[20], values[21], values[22], values[23], values[24],
                values[25], values[26], values[27], values[28], values[29],
                values[30]
            );
            if (scan_result == 31) begin
                @(negedge clk);
                reset = values[0];
                ppu_enable = values[1];
                cpu_enable = values[2];
                cpu_bus_valid = values[3];
                cpu_bus_write = values[4];
                cpu_address = values[5][15:0];
                cpu_write_data = values[6][7:0];
                sprite_zero_hit_set = values[7];
                sprite_overflow_set = values[8];
                #1;

                assert (scanline == values[9] && dot == values[10]);
                assert (frame_odd == values[11]);
                assert (timing_vblank == values[12]);
                assert (vblank_start == values[13]);
                assert (vblank_end == values[14]);
                if (values[28] && !values[4] && values[5][2:0] == 3'd2)
                    assert (cpu_read_data[7] == values[15])
                        else $fatal(1,
                            "PPUSTATUS bit 7 mismatch frame=%0d at %0d:%0d",
                            values[29], values[9], values[10]);

                old_status_vblank = status_vblank;
                old_nmi_level = ppu_nmi_level;
                @(posedge clk);
                #1;

                assert (scanline == values[16] && dot == values[17])
                    else $fatal(1,
                        "post timing mismatch frame=%0d pre=%0d:%0d enable=%0d actual=%0d:%0d expected=%0d:%0d cycle=%0d",
                        values[29], values[9], values[10], values[1],
                        scanline, dot, values[16], values[17], fabric_cycles);
                assert (frame_odd == values[18]);
                assert (status_vblank == values[19]);
                assert (status_sprite_zero_hit == values[20]);
                assert (status_sprite_overflow == values[21]);
                assert (ppuctrl == values[22]);
                assert (nmi_enable == values[23]);
                assert (ppu_nmi_level == values[24]);
                assert (ppu_nmi_event == values[25]);
                assert (ppu_nmi_suppressed == values[26]);
                assert (timing_vblank == values[27]);
                assert (ppu_nmi_level == (status_vblank && nmi_enable));
                if (ppu_nmi_event)
                    assert (ppu_nmi_level);
                if (ppu_nmi_suppressed)
                    assert (!ppu_nmi_event);

                fabric_cycles++;
                if (!reset) begin
                    enabled_ticks += ppu_enable;
                    stalls += !ppu_enable;
                    frame_boundaries += ppu_enable &&
                                        values[9] == 261 && values[10] == 340;
                    vblank_sets += !old_status_vblank && status_vblank;
                    vblank_clears += old_status_vblank && !status_vblank;
                    status_reads += values[28] && !values[4] &&
                                    values[5][2:0] == 3'd2;
                    control_writes += values[28] && values[4] &&
                                      values[5][2:0] == 3'd0;
                    condition_activations += !old_nmi_level && ppu_nmi_level;
                    nmi_events += ppu_nmi_event;
                    suppressed_nmis += ppu_nmi_suppressed;
                end
            end
        end
        $fclose(vector_file);

        stats_file = $fopen("build/sim/ppu_phase3i_stats.txt", "r");
        assert (stats_file != 0);
        scan_result = $fscanf(
            stats_file,
            "%d %d %d %d %d %d %d %d %d %d %d %d\n",
            expected[0], expected[1], expected[2], expected[3],
            expected[4], expected[5], expected[6], expected[7],
            expected[8], expected[9], expected[10], expected[11]
        );
        assert (scan_result == 12);
        $fclose(stats_file);

        assert (fabric_cycles == expected[1]);
        assert (enabled_ticks == expected[2]);
        assert (stalls == expected[3]);
        assert (frame_boundaries == expected[4]);
        assert (vblank_sets == expected[5]);
        assert (vblank_clears == expected[6]);
        assert (status_reads == expected[7]);
        assert (control_writes == expected[8]);
        assert (condition_activations == expected[9]);
        assert (nmi_events == expected[10]);
        assert (suppressed_nmis == expected[11]);

        $display(
            "PASS: Phase 3I seed=%08x fabric=%0d ticks=%0d stalls=%0d frames=%0d vblank_sets=%0d clears=%0d status_reads=%0d control_writes=%0d activations=%0d events=%0d suppressed=%0d mismatches=0",
            expected[0], fabric_cycles, enabled_ticks, stalls,
            frame_boundaries, vblank_sets, vblank_clears, status_reads,
            control_writes, condition_activations, nmi_events,
            suppressed_nmis
        );
        $finish;
    end

    /* verilator lint_on WIDTHEXPAND */
    /* verilator lint_on WIDTHTRUNC */
endmodule
