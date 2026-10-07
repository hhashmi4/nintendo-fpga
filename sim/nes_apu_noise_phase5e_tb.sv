`timescale 1ns/1ps

module nes_apu_noise_phase5e_tb;
    import nes_apu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_cycle_enable = 1'b0;
    logic cpu_read = 1'b0;
    logic cpu_write = 1'b0;
    logic [15:0] cpu_address = 16'h0000;
    logic [7:0] cpu_write_data = 8'h00;
    logic [7:0] cpu_read_data;
    logic dmc_mem_request;
    logic [15:0] dmc_mem_address;
    logic dmc_mem_acknowledge = 1'b0;
    logic [7:0] dmc_mem_read_data = 8'h00;
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
    logic [3:0] noise_output;
    logic [6:0] dmc_output;
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
    int unsigned noise_write_count = 0;
    int unsigned status_read_count = 0;
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned lfsr_shift_count = 0;
    int unsigned four_channel_nonzero_count = 0;
    int unsigned long_mode_shift_count = 0;
    int unsigned short_mode_shift_count = 0;
    logic [15:0] period_seen = '0;
    logic [15:0] status_combination_seen = '0;

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
    logic [3:0] expected_pre_noise_output;
    logic expected_quarter;
    logic expected_half;
    logic expected_channel_write;
    logic [4:0] expected_channel_register;
    logic [7:0] expected_channel_data;
    logic expected_dmc_clear;
    logic [4:0] expected_channel_enable;
    logic expected_frame_mode;
    logic expected_inhibit;
    logic expected_frame_irq;
    logic [15:0] expected_frame_cycle;
    logic expected_cycle_odd;
    logic expected_reset_pending;
    logic [2:0] expected_reset_delay;
    logic expected_tick_block;
    logic expected_noise_active;
    logic [3:0] expected_noise_output;
    logic expected_length_halt;
    logic expected_constant_volume;
    logic [3:0] expected_envelope_period;
    logic expected_envelope_start;
    logic [3:0] expected_envelope_divider;
    logic [3:0] expected_envelope_decay;
    logic expected_noise_mode;
    logic [3:0] expected_period_index;
    logic [11:0] expected_timer_period;
    logic [10:0] expected_timer_counter;
    logic [7:0] expected_length_counter;
    logic [14:0] expected_lfsr;
    logic expected_lfsr_shift;

    nes_apu dut (.*);

    always #5 clk <= !clk;

    task automatic check_event_outputs;
        begin
            assert (!$isunknown({cpu_read_data, irq, pulse1_output,
                                 pulse2_output, triangle_output, noise_output,
                                 quarter_frame_tick, half_frame_tick,
                                 channel_write, channel_write_register,
                                 channel_write_data, dmc_irq_clear,
                                 dmc_mem_request, dmc_mem_address,
                                 dmc_output}))
                else $fatal(1, "unknown APU output at row %0d", vector_count);
            assert (cpu_read_data == expected_read_data &&
                    irq == expected_irq &&
                    pulse1_output == expected_pre_pulse1_output &&
                    pulse2_output == expected_pre_pulse2_output &&
                    triangle_output == expected_pre_triangle_output &&
                    noise_output == expected_pre_noise_output)
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
                                 frame_tick_block, dut.noise.active,
                                 noise_output, dut.noise.length_halt,
                                 dut.noise.constant_volume,
                                 dut.noise.envelope_period,
                                 dut.noise.envelope_start,
                                 dut.noise.envelope_divider,
                                 dut.noise.envelope_decay,
                                 dut.noise.mode, dut.noise.period_index,
                                 dut.noise.timer_period,
                                 dut.noise.timer_counter,
                                 dut.noise.length_counter, dut.noise.lfsr}))
                else $fatal(1, "unknown APU/Noise state row %0d", vector_count);
            assert (channel_enable == expected_channel_enable &&
                    frame_mode == expected_frame_mode &&
                    frame_irq_inhibit == expected_inhibit &&
                    frame_irq_flag == expected_frame_irq &&
                    frame_sequence_cycle == expected_frame_cycle &&
                    cpu_cycle_odd == expected_cycle_odd &&
                    frame_reset_pending == expected_reset_pending &&
                    frame_reset_delay == expected_reset_delay &&
                    frame_tick_block == expected_tick_block)
                else $fatal(1, "APU state mismatch row %0d", vector_count);
            assert (dut.noise.active == expected_noise_active &&
                    noise_output == expected_noise_output &&
                    dut.noise.length_halt == expected_length_halt &&
                    dut.noise.constant_volume == expected_constant_volume &&
                    dut.noise.envelope_period == expected_envelope_period &&
                    dut.noise.envelope_start == expected_envelope_start &&
                    dut.noise.envelope_divider == expected_envelope_divider &&
                    dut.noise.envelope_decay == expected_envelope_decay &&
                    dut.noise.mode == expected_noise_mode &&
                    dut.noise.period_index == expected_period_index &&
                    dut.noise.timer_period == expected_timer_period &&
                    dut.noise.timer_counter == expected_timer_counter &&
                    dut.noise.length_counter == expected_length_counter &&
                    dut.noise.lfsr == expected_lfsr)
                else $fatal(1, "Noise mismatch row %0d", vector_count);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_noise_phase5e.fst");
        $dumpvars(0, nes_apu_noise_phase5e_tb);

        vector_file = $fopen(
            "build/sim/nes_apu_noise_phase5e_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5E Noise vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_ce, expected_read,
                expected_write, expected_address, expected_write_data,
                expected_channel_active, expected_dmc_irq,
                expected_read_data, expected_irq,
                expected_pre_pulse1_output, expected_pre_pulse2_output,
                expected_pre_triangle_output, expected_pre_noise_output,
                expected_quarter, expected_half, expected_channel_write,
                expected_channel_register, expected_channel_data,
                expected_dmc_clear, expected_channel_enable,
                expected_frame_mode, expected_inhibit, expected_frame_irq,
                expected_frame_cycle, expected_cycle_odd,
                expected_reset_pending, expected_reset_delay,
                expected_tick_block, expected_noise_active,
                expected_noise_output, expected_length_halt,
                expected_constant_volume, expected_envelope_period,
                expected_envelope_start, expected_envelope_divider,
                expected_envelope_decay, expected_noise_mode,
                expected_period_index, expected_timer_period,
                expected_timer_counter, expected_length_counter,
                expected_lfsr, expected_lfsr_shift
            );
            if (scan_result == 45) begin
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
                if (expected_lfsr_shift) lfsr_shift_count++;
                if (expected_channel_write &&
                    expected_channel_register >= 5'h0c &&
                    expected_channel_register <= 5'h0f)
                    noise_write_count++;
                if (expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_read_count++;
                if (expected_pre_pulse1_output != 0 &&
                    expected_pre_pulse2_output != 0 &&
                    expected_pre_triangle_output != 0 &&
                    expected_pre_noise_output != 0)
                    four_channel_nonzero_count++;
                if (scenario == 1 && expected_channel_write &&
                    expected_channel_register == 5'h0e)
                    period_seen[expected_channel_data[3:0]] = 1'b1;
                if (scenario == 2 && expected_lfsr_shift)
                    long_mode_shift_count++;
                if (scenario == 3 && expected_lfsr_shift &&
                    expected_noise_mode)
                    short_mode_shift_count++;
                if (scenario == 5 && expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_combination_seen[expected_read_data[3:0]] = 1'b1;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous Phase 5E scenarios");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 5E vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 360_000);
        assert (previous_scenario == 10);
        assert (stall_count > 60_000 && reset_count >= 8);
        assert (noise_write_count > 2_000 && status_read_count > 1_000);
        assert (quarter_count > 800 && half_count > 800);
        assert (lfsr_shift_count > 6_000);
        assert (four_channel_nonzero_count > 50);
        assert (long_mode_shift_count >= 60);
        assert (short_mode_shift_count >= 60);
        assert (period_seen == 16'hffff);
        assert (status_combination_seen == 16'hffff);
        $display(
            "PASS: Phase 5E four-channel APU (%0d Python-reference cycles, %0d stalls, %0d Noise writes, %0d status reads, %0d quarter, %0d half, %0d LFSR shifts, seed=005e2026, zero mismatches)",
            vector_count, stall_count, noise_write_count, status_read_count,
            quarter_count, half_count, lfsr_shift_count
        );
        $finish;
    end
endmodule
