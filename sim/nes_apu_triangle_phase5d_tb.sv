`timescale 1ns/1ps

module nes_apu_triangle_phase5d_tb;
    import nes_apu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_cycle_enable = 1'b0;
    logic cpu_read = 1'b0;
    logic cpu_write = 1'b0;
    logic [15:0] cpu_address = 16'h0000;
    logic [7:0] cpu_write_data = 8'h00;
    logic [7:0] cpu_read_data;
    nes_apu_channel_mask_t channel_active = '0;
    logic dmc_irq_flag = 1'b0;
    nes_apu_channel_mask_t channel_enable;
    logic channel_write;
    logic [4:0] channel_write_register;
    logic [7:0] channel_write_data;
    logic dmc_irq_clear;
    logic quarter_frame_tick;
    logic half_frame_tick;
    logic irq;
    logic [3:0] pulse1_output;
    logic [3:0] pulse2_output;
    logic [3:0] triangle_output;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [3:0] noise_output;
    /* verilator lint_on UNUSEDSIGNAL */
    nes_apu_frame_mode_t frame_mode;
    logic frame_irq_inhibit;
    logic frame_irq_flag;
    logic [15:0] frame_sequence_cycle;
    logic cpu_cycle_odd;
    logic frame_reset_pending;
    logic [2:0] frame_reset_delay;
    logic frame_tick_block;

    int vector_file;
    int scan_result;
    int scenario;
    int previous_scenario = 0;
    int unsigned vector_count = 0;
    int unsigned stall_count = 0;
    int unsigned reset_count = 0;
    int unsigned triangle_write_count = 0;
    int unsigned status_read_count = 0;
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned three_channel_nonzero_count = 0;
    int unsigned held_dac_count = 0;
    logic [31:0] waveform_position_seen = '0;
    logic [7:0] status_combination_seen = '0;

    logic expected_reset;
    logic expected_ce;
    logic expected_read;
    logic expected_write;
    logic [15:0] expected_address;
    logic [7:0] expected_write_data;
    logic [4:0] expected_channel_active;
    logic expected_dmc_irq;
    logic [7:0] expected_read_data;
    logic expected_irq;
    logic [3:0] expected_pre_pulse1_output;
    logic [3:0] expected_pre_pulse2_output;
    logic [3:0] expected_pre_triangle_output;
    logic expected_quarter;
    logic expected_half;
    logic expected_channel_write;
    logic [4:0] expected_channel_register;
    logic [7:0] expected_channel_data;
    logic expected_dmc_clear;
    logic [4:0] expected_channel_enable;
    logic expected_mode;
    logic expected_inhibit;
    logic expected_frame_irq;
    logic [15:0] expected_frame_cycle;
    logic expected_cycle_odd;
    logic expected_reset_pending;
    logic [2:0] expected_reset_delay;
    logic expected_tick_block;
    logic expected_triangle_active;
    logic [3:0] expected_triangle_output;
    logic expected_control;
    logic [6:0] expected_linear_reload_value;
    logic [6:0] expected_linear_counter;
    logic expected_linear_reload_flag;
    logic [4:0] expected_sequence_position;
    logic [10:0] expected_timer_period;
    logic [10:0] expected_timer_counter;
    logic [7:0] expected_length_counter;

    nes_apu dut (.*);

    always #5 clk <= !clk;

    task automatic check_event_outputs;
        begin
            assert (!$isunknown({cpu_read_data, irq, pulse1_output,
                                 pulse2_output, triangle_output,
                                 quarter_frame_tick, half_frame_tick,
                                 channel_write, channel_write_register,
                                 channel_write_data, dmc_irq_clear}))
                else $fatal(1, "unknown APU output at row %0d", vector_count);
            assert (cpu_read_data == expected_read_data &&
                    irq == expected_irq &&
                    pulse1_output == expected_pre_pulse1_output &&
                    pulse2_output == expected_pre_pulse2_output &&
                    triangle_output == expected_pre_triangle_output)
                else $fatal(1, "APU output mismatch row %0d", vector_count);
            assert (quarter_frame_tick == expected_quarter &&
                    half_frame_tick == expected_half)
                else $fatal(1, "frame tick mismatch row %0d", vector_count);
            assert (channel_write == expected_channel_write &&
                    channel_write_register == expected_channel_register &&
                    channel_write_data == expected_channel_data &&
                    dmc_irq_clear == expected_dmc_clear)
                else $fatal(1, "bus event mismatch row %0d", vector_count);
        end
    endtask

    task automatic check_post_edge_state;
        begin
            assert (!$isunknown({channel_enable, frame_mode,
                                 frame_irq_inhibit, frame_irq_flag,
                                 frame_sequence_cycle, cpu_cycle_odd,
                                 frame_reset_pending, frame_reset_delay,
                                 frame_tick_block, dut.triangle.active,
                                 triangle_output,
                                 dut.triangle.control_flag,
                                 dut.triangle.linear_reload_value,
                                 dut.triangle.linear_counter,
                                 dut.triangle.linear_reload_flag,
                                 dut.triangle.sequence_position,
                                 dut.triangle.timer_period,
                                 dut.triangle.timer_counter,
                                 dut.triangle.length_counter}))
                else $fatal(1, "unknown APU state at row %0d", vector_count);
            assert (channel_enable == expected_channel_enable &&
                    frame_mode == expected_mode &&
                    frame_irq_inhibit == expected_inhibit &&
                    frame_irq_flag == expected_frame_irq &&
                    frame_sequence_cycle == expected_frame_cycle &&
                    cpu_cycle_odd == expected_cycle_odd &&
                    frame_reset_pending == expected_reset_pending &&
                    frame_reset_delay == expected_reset_delay &&
                    frame_tick_block == expected_tick_block)
                else $fatal(1, "APU state mismatch row %0d", vector_count);
            assert (dut.triangle.active == expected_triangle_active &&
                    triangle_output == expected_triangle_output &&
                    dut.triangle.control_flag == expected_control &&
                    dut.triangle.linear_reload_value ==
                        expected_linear_reload_value &&
                    dut.triangle.linear_counter == expected_linear_counter &&
                    dut.triangle.linear_reload_flag ==
                        expected_linear_reload_flag &&
                    dut.triangle.sequence_position ==
                        expected_sequence_position &&
                    dut.triangle.timer_period == expected_timer_period &&
                    dut.triangle.timer_counter == expected_timer_counter &&
                    dut.triangle.length_counter == expected_length_counter)
                else $fatal(1, "Triangle mismatch row %0d", vector_count);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_triangle_phase5d.fst");
        $dumpvars(0, nes_apu_triangle_phase5d_tb);

        vector_file = $fopen(
            "build/sim/nes_apu_triangle_phase5d_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5D Triangle vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_ce, expected_read,
                expected_write, expected_address, expected_write_data,
                expected_channel_active, expected_dmc_irq,
                expected_read_data, expected_irq,
                expected_pre_pulse1_output, expected_pre_pulse2_output,
                expected_pre_triangle_output, expected_quarter, expected_half,
                expected_channel_write, expected_channel_register,
                expected_channel_data, expected_dmc_clear,
                expected_channel_enable, expected_mode, expected_inhibit,
                expected_frame_irq, expected_frame_cycle,
                expected_cycle_odd, expected_reset_pending,
                expected_reset_delay, expected_tick_block,
                expected_triangle_active, expected_triangle_output,
                expected_control, expected_linear_reload_value,
                expected_linear_counter, expected_linear_reload_flag,
                expected_sequence_position, expected_timer_period,
                expected_timer_counter, expected_length_counter
            );
            if (scan_result == 39) begin
                @(negedge clk);
                reset = expected_reset;
                cpu_cycle_enable = expected_ce;
                cpu_read = expected_read;
                cpu_write = expected_write;
                cpu_address = expected_address;
                cpu_write_data = expected_write_data;
                channel_active = expected_channel_active;
                dmc_irq_flag = expected_dmc_irq;
                #1;
                check_event_outputs();

                @(posedge clk);
                #1;
                check_post_edge_state();

                vector_count++;
                if (!expected_ce) stall_count++;
                if (expected_reset) reset_count++;
                if (expected_quarter) quarter_count++;
                if (expected_half) half_count++;
                if (expected_channel_write &&
                    expected_channel_register >= 5'h08 &&
                    expected_channel_register <= 5'h0b)
                    triangle_write_count++;
                if (expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_read_count++;
                if (expected_pre_pulse1_output != 0 &&
                    expected_pre_pulse2_output != 0 &&
                    expected_pre_triangle_output != 0)
                    three_channel_nonzero_count++;
                if ((expected_length_counter == 0 ||
                     expected_linear_counter == 0) &&
                    expected_triangle_output != 0)
                    held_dac_count++;
                if (scenario == 2)
                    waveform_position_seen[expected_sequence_position] = 1'b1;
                if (scenario == 4 && expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_combination_seen[expected_read_data[2:0]] = 1'b1;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous Phase 5D scenarios");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 5D vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 300_000);
        assert (previous_scenario == 9);
        assert (stall_count > 50_000 && reset_count >= 10);
        assert (triangle_write_count > 2_000 && status_read_count > 1_000);
        assert (quarter_count > 900 && half_count > 900);
        assert (three_channel_nonzero_count > 100);
        assert (held_dac_count > 1_000);
        assert (waveform_position_seen == 32'hffff_ffff);
        assert (status_combination_seen == 8'hff);
        $display(
            "PASS: Phase 5D Pulse 1/Pulse 2/Triangle (%0d Python-reference cycles, %0d stalls, seed=005d2026, all 32 waveform positions, zero mismatches)",
            vector_count, stall_count
        );
        $finish;
    end
endmodule
