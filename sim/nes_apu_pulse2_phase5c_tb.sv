`timescale 1ns/1ps

module nes_apu_pulse2_phase5c_tb;
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
    int unsigned pulse1_write_count = 0;
    int unsigned pulse2_write_count = 0;
    int unsigned status_read_count = 0;
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned dual_nonzero_count = 0;
    int unsigned negate_difference_count = 0;
    logic [3:0] pulse2_duty_seen = 4'b0000;
    logic [3:0] status_combination_seen = 4'b0000;

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

    logic expected_active [0:1];
    logic [3:0] expected_raw_output [0:1];
    logic [1:0] expected_duty [0:1];
    logic [2:0] expected_duty_position [0:1];
    logic [10:0] expected_timer_period [0:1];
    logic [10:0] expected_timer_counter [0:1];
    logic [7:0] expected_length_counter [0:1];
    logic expected_length_halt [0:1];
    logic expected_constant_volume [0:1];
    logic [3:0] expected_envelope_period [0:1];
    logic expected_envelope_start [0:1];
    logic [3:0] expected_envelope_divider [0:1];
    logic [3:0] expected_envelope_decay [0:1];
    logic expected_sweep_enabled [0:1];
    logic [2:0] expected_sweep_period [0:1];
    logic expected_sweep_negate [0:1];
    logic [2:0] expected_sweep_shift [0:1];
    logic expected_sweep_reload [0:1];
    logic [2:0] expected_sweep_divider [0:1];
    logic [11:0] expected_sweep_target [0:1];
    logic expected_sweep_mute [0:1];

    nes_apu dut (.*);

    always #5 clk <= !clk;

    task automatic check_event_outputs;
        begin
            assert (!$isunknown({cpu_read_data, irq, pulse1_output,
                                 pulse2_output, quarter_frame_tick,
                                 half_frame_tick, channel_write,
                                 channel_write_register, channel_write_data,
                                 dmc_irq_clear}))
                else $fatal(1, "unknown APU event output at row %0d",
                            vector_count);
            assert (cpu_read_data == expected_read_data &&
                    irq == expected_irq &&
                    pulse1_output == expected_pre_pulse1_output &&
                    pulse2_output == expected_pre_pulse2_output)
                else $fatal(1, "APU output mismatch row %0d", vector_count);
            assert (quarter_frame_tick == expected_quarter &&
                    half_frame_tick == expected_half)
                else $fatal(1, "frame tick mismatch row %0d", vector_count);
            assert (channel_write == expected_channel_write &&
                    channel_write_register == expected_channel_register &&
                    channel_write_data == expected_channel_data)
                else $fatal(1, "channel write mismatch row %0d", vector_count);
            assert (dmc_irq_clear == expected_dmc_clear)
                else $fatal(1, "DMC clear mismatch row %0d", vector_count);
        end
    endtask

    task automatic check_apu_state;
        begin
            assert (!$isunknown({channel_enable, frame_mode,
                                 frame_irq_inhibit, frame_irq_flag,
                                 frame_sequence_cycle, cpu_cycle_odd,
                                 frame_reset_pending, frame_reset_delay,
                                 frame_tick_block}))
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
        end
    endtask

    task automatic check_pulse1_state;
        begin
            assert (!$isunknown({dut.pulse1.active, pulse1_output,
                                 dut.pulse1.duty, dut.pulse1.duty_position,
                                 dut.pulse1.timer_period,
                                 dut.pulse1.timer_counter,
                                 dut.pulse1.length_counter,
                                 dut.pulse1.length_halt,
                                 dut.pulse1.constant_volume,
                                 dut.pulse1.envelope_period,
                                 dut.pulse1.envelope_start,
                                 dut.pulse1.envelope_divider,
                                 dut.pulse1.envelope_decay,
                                 dut.pulse1.sweep_enabled,
                                 dut.pulse1.sweep_period,
                                 dut.pulse1.sweep_negate,
                                 dut.pulse1.sweep_shift,
                                 dut.pulse1.sweep_reload,
                                 dut.pulse1.sweep_divider,
                                 dut.pulse1.sweep_target,
                                 dut.pulse1.sweep_mute}))
                else $fatal(1, "unknown Pulse 1 state at row %0d", vector_count);
            assert (dut.pulse1.active == expected_active[0] &&
                    pulse1_output == expected_raw_output[0] &&
                    dut.pulse1.duty == expected_duty[0] &&
                    dut.pulse1.duty_position == expected_duty_position[0] &&
                    dut.pulse1.timer_period == expected_timer_period[0] &&
                    dut.pulse1.timer_counter == expected_timer_counter[0] &&
                    dut.pulse1.length_counter == expected_length_counter[0] &&
                    dut.pulse1.length_halt == expected_length_halt[0] &&
                    dut.pulse1.constant_volume == expected_constant_volume[0] &&
                    dut.pulse1.envelope_period == expected_envelope_period[0] &&
                    dut.pulse1.envelope_start == expected_envelope_start[0] &&
                    dut.pulse1.envelope_divider == expected_envelope_divider[0] &&
                    dut.pulse1.envelope_decay == expected_envelope_decay[0] &&
                    dut.pulse1.sweep_enabled == expected_sweep_enabled[0] &&
                    dut.pulse1.sweep_period == expected_sweep_period[0] &&
                    dut.pulse1.sweep_negate == expected_sweep_negate[0] &&
                    dut.pulse1.sweep_shift == expected_sweep_shift[0] &&
                    dut.pulse1.sweep_reload == expected_sweep_reload[0] &&
                    dut.pulse1.sweep_divider == expected_sweep_divider[0] &&
                    dut.pulse1.sweep_target == expected_sweep_target[0] &&
                    dut.pulse1.sweep_mute == expected_sweep_mute[0])
                else $fatal(1, "Pulse 1 mismatch row %0d", vector_count);
        end
    endtask

    task automatic check_pulse2_state;
        begin
            assert (!$isunknown({dut.pulse2.active, pulse2_output,
                                 dut.pulse2.duty, dut.pulse2.duty_position,
                                 dut.pulse2.timer_period,
                                 dut.pulse2.timer_counter,
                                 dut.pulse2.length_counter,
                                 dut.pulse2.length_halt,
                                 dut.pulse2.constant_volume,
                                 dut.pulse2.envelope_period,
                                 dut.pulse2.envelope_start,
                                 dut.pulse2.envelope_divider,
                                 dut.pulse2.envelope_decay,
                                 dut.pulse2.sweep_enabled,
                                 dut.pulse2.sweep_period,
                                 dut.pulse2.sweep_negate,
                                 dut.pulse2.sweep_shift,
                                 dut.pulse2.sweep_reload,
                                 dut.pulse2.sweep_divider,
                                 dut.pulse2.sweep_target,
                                 dut.pulse2.sweep_mute}))
                else $fatal(1, "unknown Pulse 2 state at row %0d", vector_count);
            assert (dut.pulse2.active == expected_active[1] &&
                    pulse2_output == expected_raw_output[1] &&
                    dut.pulse2.duty == expected_duty[1] &&
                    dut.pulse2.duty_position == expected_duty_position[1] &&
                    dut.pulse2.timer_period == expected_timer_period[1] &&
                    dut.pulse2.timer_counter == expected_timer_counter[1] &&
                    dut.pulse2.length_counter == expected_length_counter[1] &&
                    dut.pulse2.length_halt == expected_length_halt[1] &&
                    dut.pulse2.constant_volume == expected_constant_volume[1] &&
                    dut.pulse2.envelope_period == expected_envelope_period[1] &&
                    dut.pulse2.envelope_start == expected_envelope_start[1] &&
                    dut.pulse2.envelope_divider == expected_envelope_divider[1] &&
                    dut.pulse2.envelope_decay == expected_envelope_decay[1] &&
                    dut.pulse2.sweep_enabled == expected_sweep_enabled[1] &&
                    dut.pulse2.sweep_period == expected_sweep_period[1] &&
                    dut.pulse2.sweep_negate == expected_sweep_negate[1] &&
                    dut.pulse2.sweep_shift == expected_sweep_shift[1] &&
                    dut.pulse2.sweep_reload == expected_sweep_reload[1] &&
                    dut.pulse2.sweep_divider == expected_sweep_divider[1] &&
                    dut.pulse2.sweep_target == expected_sweep_target[1] &&
                    dut.pulse2.sweep_mute == expected_sweep_mute[1])
                else $fatal(1, "Pulse 2 mismatch row %0d", vector_count);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_pulse2_phase5c.fst");
        $dumpvars(0, nes_apu_pulse2_phase5c_tb);

        vector_file = $fopen(
            "build/sim/nes_apu_pulse2_phase5c_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5C dual-pulse vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_ce, expected_read,
                expected_write, expected_address, expected_write_data,
                expected_channel_active, expected_dmc_irq,
                expected_read_data, expected_irq,
                expected_pre_pulse1_output, expected_pre_pulse2_output,
                expected_quarter, expected_half, expected_channel_write,
                expected_channel_register, expected_channel_data,
                expected_dmc_clear, expected_channel_enable, expected_mode,
                expected_inhibit, expected_frame_irq, expected_frame_cycle,
                expected_cycle_odd, expected_reset_pending,
                expected_reset_delay, expected_tick_block,
                expected_active[0], expected_raw_output[0], expected_duty[0],
                expected_duty_position[0], expected_timer_period[0],
                expected_timer_counter[0], expected_length_counter[0],
                expected_length_halt[0], expected_constant_volume[0],
                expected_envelope_period[0], expected_envelope_start[0],
                expected_envelope_divider[0], expected_envelope_decay[0],
                expected_sweep_enabled[0], expected_sweep_period[0],
                expected_sweep_negate[0], expected_sweep_shift[0],
                expected_sweep_reload[0], expected_sweep_divider[0],
                expected_sweep_target[0], expected_sweep_mute[0],
                expected_active[1], expected_raw_output[1], expected_duty[1],
                expected_duty_position[1], expected_timer_period[1],
                expected_timer_counter[1], expected_length_counter[1],
                expected_length_halt[1], expected_constant_volume[1],
                expected_envelope_period[1], expected_envelope_start[1],
                expected_envelope_divider[1], expected_envelope_decay[1],
                expected_sweep_enabled[1], expected_sweep_period[1],
                expected_sweep_negate[1], expected_sweep_shift[1],
                expected_sweep_reload[1], expected_sweep_divider[1],
                expected_sweep_target[1], expected_sweep_mute[1]
            );
            if (scan_result == 70) begin
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
                check_apu_state();
                check_pulse1_state();
                check_pulse2_state();

                vector_count++;
                if (!expected_ce) stall_count++;
                if (expected_reset) reset_count++;
                if (expected_quarter) quarter_count++;
                if (expected_half) half_count++;
                if (expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_read_count++;
                if (expected_channel_write &&
                    expected_channel_register <= 5'h03)
                    pulse1_write_count++;
                if (expected_channel_write &&
                    expected_channel_register >= 5'h04 &&
                    expected_channel_register <= 5'h07)
                    pulse2_write_count++;
                if (expected_raw_output[0] != 4'd0 &&
                    expected_raw_output[1] != 4'd0)
                    dual_nonzero_count++;
                if (expected_sweep_negate[0] && expected_sweep_negate[1] &&
                    expected_timer_period[1] ==
                        expected_timer_period[0] + 11'd1)
                    negate_difference_count++;
                if (scenario == 1)
                    pulse2_duty_seen[expected_duty[1]] = 1'b1;
                if (scenario == 5 && expected_ce && expected_read &&
                    expected_address == 16'h4015)
                    status_combination_seen[expected_read_data[1:0]] = 1'b1;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous Phase 5C scenarios");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 5C vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 270_000);
        assert (previous_scenario == 9);
        assert (stall_count > 40_000 && reset_count >= 8);
        assert (pulse1_write_count > 1_000 && pulse2_write_count > 1_000);
        assert (status_read_count > 100);
        assert (quarter_count > 50 && half_count > 40);
        assert (dual_nonzero_count > 100);
        assert (negate_difference_count > 0);
        assert (pulse2_duty_seen == 4'b1111);
        assert (status_combination_seen == 4'b1111);
        $display(
            "PASS: Phase 5C dual Pulse 1/Pulse 2 (%0d Python-reference cycles, %0d stalls, seed=005c2026, zero mismatches)",
            vector_count, stall_count
        );
        $finish;
    end
endmodule
