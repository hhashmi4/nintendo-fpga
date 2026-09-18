`timescale 1ns/1ps

module ppu_timing_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ppu_enable = 1'b0;
    logic rendering_enabled = 1'b0;
    logic [8:0] dot;
    logic [8:0] scanline;
    logic frame_odd;
    logic visible_pixel;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic vblank;
    logic frame_start;
    logic frame_end;
    logic scanline_start;
    logic vblank_start;
    logic vblank_end;
    logic pre_render;
    logic post_render;

    int vector_file;
    int scan_result;
    int scenario;
    logic expected_reset;
    logic expected_enable;
    logic expected_rendering;
    logic [8:0] expected_dot;
    logic [8:0] expected_scanline;
    logic expected_odd;
    logic expected_vblank;
    int active_scenario = 0;
    int unsigned row_count = 0;
    int unsigned scenario_rows = 0;
    int unsigned enabled_count = 0;
    int unsigned stall_count = 0;
    int unsigned visible_count = 0;
    int unsigned frame_start_count = 0;
    int unsigned frame_end_count = 0;
    int unsigned vblank_start_count = 0;
    int unsigned vblank_end_count = 0;
    int unsigned odd_skip_count = 0;
    int unsigned disabled_odd_no_skip_count = 0;

    logic previous_valid = 1'b0;
    logic previous_reset;
    logic previous_enable;
    logic previous_rendering;
    logic previous_odd;
    logic previous_vblank;
    logic [8:0] previous_dot;
    logic [8:0] previous_scanline;

    ppu_timing dut (.*);

    always #5 clk <= !clk;

    task automatic check_scenario(input int completed_scenario);
        begin
            case (completed_scenario)
                1: begin
                    assert (enabled_count == 178_684)
                        else $fatal(1, "disabled-render frame ticks: %0d", enabled_count);
                    assert (visible_count == 122_880)
                        else $fatal(1, "disabled-render visible count: %0d", visible_count);
                    assert (frame_start_count == 2 && frame_end_count == 2);
                    assert (vblank_start_count == 2 && vblank_end_count == 2);
                    assert (odd_skip_count == 0);
                    assert (disabled_odd_no_skip_count == 1)
                        else $fatal(1, "disabled odd frame did not execute dot 340");
                end
                2: begin
                    assert (enabled_count == 357_366)
                        else $fatal(1, "rendered frame ticks: %0d", enabled_count);
                    assert (visible_count == 245_760);
                    assert (frame_start_count == 4 && frame_end_count == 4);
                    assert (vblank_start_count == 4 && vblank_end_count == 4);
                    assert (odd_skip_count == 2)
                        else $fatal(1, "expected two directed odd-frame skips");
                    assert (disabled_odd_no_skip_count == 0);
                end
                3: begin
                    assert (enabled_count == 536_049)
                        else $fatal(1, "stalled rendered frame ticks: %0d", enabled_count);
                    assert (visible_count == 368_640);
                    assert (frame_start_count == 6 && frame_end_count == 6);
                    assert (vblank_start_count == 6 && vblank_end_count == 6);
                    assert (odd_skip_count == 3);
                    assert (stall_count > 250_000)
                        else $fatal(1, "insufficient randomized stalls: %0d", stall_count);
                end
                default: $fatal(1, "unknown scenario %0d", completed_scenario);
            endcase
            $display(
                "PPU scenario %0d PASS: rows=%0d enabled=%0d stalls=%0d visible=%0d",
                completed_scenario, scenario_rows, enabled_count, stall_count,
                visible_count
            );
        end
    endtask

    task automatic clear_scenario_counts;
        begin
            scenario_rows = 0;
            enabled_count = 0;
            stall_count = 0;
            visible_count = 0;
            frame_start_count = 0;
            frame_end_count = 0;
            vblank_start_count = 0;
            vblank_end_count = 0;
            odd_skip_count = 0;
            disabled_odd_no_skip_count = 0;
            previous_valid = 1'b0;
        end
    endtask

    task automatic check_outputs;
        logic expected_visible;
        logic expected_frame_end;
        begin
            expected_visible = !expected_reset && expected_enable &&
                               expected_scanline < 240 &&
                               expected_dot >= 1 && expected_dot <= 256;
            expected_frame_end = !expected_reset && expected_enable &&
                expected_scanline == 261 &&
                ((expected_rendering && expected_odd && expected_dot == 339) ||
                 (!(expected_rendering && expected_odd) && expected_dot == 340));

            assert (!$isunknown({dot, scanline, frame_odd, visible_pixel,
                                 pixel_x, pixel_y, vblank, frame_start,
                                 frame_end, scanline_start, vblank_start,
                                 vblank_end, pre_render, post_render}))
                else $fatal(1, "unknown PPU output at vector %0d", row_count);
            assert (dot == expected_dot && scanline == expected_scanline)
                else $fatal(1, "coordinate mismatch row %0d: got %0d:%0d expected %0d:%0d",
                            row_count, scanline, dot,
                            expected_scanline, expected_dot);
            assert (frame_odd == expected_odd && vblank == expected_vblank)
                else $fatal(1, "state mismatch at row %0d", row_count);
            assert (dot <= 340 && scanline <= 261)
                else $fatal(1, "timing state outside legal range");
            assert (visible_pixel == expected_visible);
            assert (frame_start == (!expected_reset && expected_enable &&
                                    expected_scanline == 0 && expected_dot == 0));
            assert (frame_end == expected_frame_end);
            assert (scanline_start == (!expected_reset && expected_enable &&
                                       expected_dot == 0));
            assert (vblank_start == (!expected_reset && expected_enable &&
                                     expected_scanline == 241 && expected_dot == 1));
            assert (vblank_end == (!expected_reset && expected_enable &&
                                   expected_scanline == 261 && expected_dot == 1));
            assert (pre_render == (expected_scanline == 261));
            assert (post_render == (expected_scanline == 240));

            if (expected_scanline < 240 &&
                expected_dot >= 1 && expected_dot <= 256) begin
                assert (pixel_x == expected_dot[7:0] - 8'd1 &&
                        pixel_y == expected_scanline[7:0])
                    else $fatal(1, "visible coordinate mismatch");
            end else begin
                assert (pixel_x == 0 && pixel_y == 0)
                    else $fatal(1, "invalid-region pixel coordinates not zero");
            end

            if (!expected_enable) begin
                assert (!visible_pixel && !frame_start && !frame_end &&
                        !scanline_start && !vblank_start && !vblank_end)
                    else $fatal(1, "event asserted during enable stall");
            end

            if (previous_valid) begin
                if (previous_reset) begin
                    assert ({scanline, dot, frame_odd, vblank} == '0)
                        else $fatal(1, "reset did not clear timing state");
                end else if (!previous_enable) begin
                    assert (dot == previous_dot && scanline == previous_scanline &&
                            frame_odd == previous_odd &&
                            vblank == previous_vblank)
                        else $fatal(1, "timing state advanced during stall");
                end

                if (previous_enable && previous_scanline == 261 &&
                    previous_dot == 339 && previous_odd &&
                    previous_rendering) begin
                    assert (scanline == 0 && dot == 0 && !frame_odd)
                        else $fatal(1, "illegal odd-frame shortened transition");
                    odd_skip_count++;
                end
                if (previous_enable && previous_scanline == 261 &&
                    previous_dot == 339 && previous_odd &&
                    !previous_rendering) begin
                    assert (scanline == 261 && dot == 340 && frame_odd)
                        else $fatal(1, "odd-frame skip occurred while rendering disabled");
                    disabled_odd_no_skip_count++;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("build/sim/ppu_timing.fst");
        $dumpvars(0, ppu_timing_tb);

        vector_file = $fopen("build/sim/ppu_timing_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "could not open Python PPU reference vectors");

        clear_scenario_counts();
        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file, "%d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_enable,
                expected_rendering, expected_dot, expected_scanline,
                expected_odd, expected_vblank
            );
            if (scan_result == 8) begin
                if (active_scenario != scenario) begin
                    if (active_scenario != 0) check_scenario(active_scenario);
                    active_scenario = scenario;
                    clear_scenario_counts();
                end

                @(negedge clk);
                reset = expected_reset;
                ppu_enable = expected_enable;
                rendering_enabled = expected_rendering;
                #1;
                check_outputs();

                row_count++;
                scenario_rows++;
                if (!expected_reset) begin
                    if (expected_enable) enabled_count++;
                    else stall_count++;
                    if (visible_pixel) visible_count++;
                    if (frame_start) frame_start_count++;
                    if (frame_end) frame_end_count++;
                    if (vblank_start) vblank_start_count++;
                    if (vblank_end) vblank_end_count++;
                end

                previous_valid = 1'b1;
                previous_reset = expected_reset;
                previous_enable = expected_enable;
                previous_rendering = expected_rendering;
                previous_dot = expected_dot;
                previous_scanline = expected_scanline;
                previous_odd = expected_odd;
                previous_vblank = expected_vblank;
            end else if (scan_result != -1) begin
                $fatal(1, "malformed PPU reference vector after row %0d", row_count);
            end
        end
        check_scenario(active_scenario);
        $fclose(vector_file);

        assert (row_count > 1_300_000)
            else $fatal(1, "insufficient multi-frame RTL coverage: %0d", row_count);
        $display(
            "PASS: Phase 3A PPU timing (%0d Python-reference fabric cycles, seed=003a5eed)",
            row_count
        );
        $finish;
    end
endmodule
