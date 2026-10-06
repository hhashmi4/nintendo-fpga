`timescale 1ns/1ps

module nes_apu_pulse1_phase5b_tb;
    logic clk = 1'b0;
    logic reset = 1'b0;
    logic cpu_cycle_enable = 1'b0;
    logic timer_tick = 1'b0;
    logic enable = 1'b0;
    logic write = 1'b0;
    logic [1:0] write_register = 2'd0;
    logic [7:0] write_data = 8'd0;
    logic quarter_frame_tick = 1'b0;
    logic half_frame_tick = 1'b0;

    logic active;
    logic [3:0] raw_output;
    logic [1:0] duty;
    logic [2:0] duty_position;
    logic [10:0] timer_period;
    logic [10:0] timer_counter;
    logic [7:0] length_counter;
    logic length_halt;
    logic constant_volume;
    logic [3:0] envelope_period;
    logic envelope_start;
    logic [3:0] envelope_divider;
    logic [3:0] envelope_decay;
    logic sweep_enabled;
    logic [2:0] sweep_period;
    logic sweep_negate;
    logic [2:0] sweep_shift;
    logic sweep_reload;
    logic [2:0] sweep_divider;
    logic [11:0] sweep_target;
    logic sweep_mute;

    int vector_file;
    int scan_result;
    int scenario;
    int previous_scenario = 0;
    int unsigned vector_count = 0;
    int unsigned stall_count = 0;
    int unsigned write_count = 0;
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned timer_tick_count = 0;
    int unsigned nonzero_output_count = 0;

    logic expected_reset;
    logic expected_ce;
    logic expected_timer_tick;
    logic expected_enable;
    logic expected_write;
    logic [1:0] expected_write_register;
    logic [7:0] expected_write_data;
    logic expected_quarter;
    logic expected_half;
    logic expected_active;
    logic [3:0] expected_raw_output;
    logic [1:0] expected_duty;
    logic [2:0] expected_duty_position;
    logic [10:0] expected_timer_period;
    logic [10:0] expected_timer_counter;
    logic [7:0] expected_length_counter;
    logic expected_length_halt;
    logic expected_constant_volume;
    logic [3:0] expected_envelope_period;
    logic expected_envelope_start;
    logic [3:0] expected_envelope_divider;
    logic [3:0] expected_envelope_decay;
    logic expected_sweep_enabled;
    logic [2:0] expected_sweep_period;
    logic expected_sweep_negate;
    logic [2:0] expected_sweep_shift;
    logic expected_sweep_reload;
    logic [2:0] expected_sweep_divider;
    logic [11:0] expected_sweep_target;
    logic expected_sweep_mute;

    nes_apu_pulse #(.CHANNEL_ONE(1'b1)) dut (.*);

    always #5 clk <= !clk;

    task automatic check_state_and_output;
        begin
            assert (!$isunknown({active, raw_output, duty, duty_position,
                                 timer_period, timer_counter, length_counter,
                                 length_halt, constant_volume, envelope_period,
                                 envelope_start, envelope_divider,
                                 envelope_decay, sweep_enabled, sweep_period,
                                 sweep_negate, sweep_shift, sweep_reload,
                                 sweep_divider, sweep_target, sweep_mute}))
                else $fatal(1, "unknown Pulse 1 value at row %0d", vector_count);
            assert (active == expected_active &&
                    raw_output == expected_raw_output)
                else $fatal(1, "output mismatch row %0d: got active=%0d raw=%0d expected %0d/%0d",
                            vector_count, active, raw_output,
                            expected_active, expected_raw_output);
            assert (duty == expected_duty &&
                    duty_position == expected_duty_position)
                else $fatal(1, "duty mismatch row %0d", vector_count);
            assert (timer_period == expected_timer_period &&
                    timer_counter == expected_timer_counter)
                else $fatal(1, "timer mismatch row %0d: got %0d/%0d expected %0d/%0d",
                            vector_count, timer_period, timer_counter,
                            expected_timer_period, expected_timer_counter);
            assert (length_counter == expected_length_counter &&
                    length_halt == expected_length_halt)
                else $fatal(1, "length mismatch row %0d", vector_count);
            assert (constant_volume == expected_constant_volume &&
                    envelope_period == expected_envelope_period &&
                    envelope_start == expected_envelope_start &&
                    envelope_divider == expected_envelope_divider &&
                    envelope_decay == expected_envelope_decay)
                else $fatal(1, "envelope mismatch row %0d", vector_count);
            assert (sweep_enabled == expected_sweep_enabled &&
                    sweep_period == expected_sweep_period &&
                    sweep_negate == expected_sweep_negate &&
                    sweep_shift == expected_sweep_shift &&
                    sweep_reload == expected_sweep_reload &&
                    sweep_divider == expected_sweep_divider &&
                    sweep_target == expected_sweep_target &&
                    sweep_mute == expected_sweep_mute)
                else $fatal(1, "sweep mismatch row %0d: target got %0d expected %0d",
                            vector_count, sweep_target, expected_sweep_target);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_pulse1_phase5b.fst");
        $dumpvars(0, nes_apu_pulse1_phase5b_tb);

        vector_file = $fopen(
            "build/sim/nes_apu_pulse1_phase5b_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5B Pulse 1 reference vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_ce,
                expected_timer_tick, expected_enable, expected_write,
                expected_write_register, expected_write_data,
                expected_quarter, expected_half, expected_active,
                expected_raw_output, expected_duty, expected_duty_position,
                expected_timer_period, expected_timer_counter,
                expected_length_counter, expected_length_halt,
                expected_constant_volume, expected_envelope_period,
                expected_envelope_start, expected_envelope_divider,
                expected_envelope_decay, expected_sweep_enabled,
                expected_sweep_period, expected_sweep_negate,
                expected_sweep_shift, expected_sweep_reload,
                expected_sweep_divider, expected_sweep_target,
                expected_sweep_mute
            );
            if (scan_result == 31) begin
                @(negedge clk);
                reset = expected_reset;
                cpu_cycle_enable = expected_ce;
                timer_tick = expected_timer_tick;
                enable = expected_enable;
                write = expected_write;
                write_register = expected_write_register;
                write_data = expected_write_data;
                quarter_frame_tick = expected_quarter;
                half_frame_tick = expected_half;

                @(posedge clk);
                #1;
                check_state_and_output();

                vector_count++;
                if (!expected_ce) stall_count++;
                if (expected_ce && expected_write) write_count++;
                if (expected_ce && expected_quarter) quarter_count++;
                if (expected_ce && expected_half) half_count++;
                if (expected_timer_tick) timer_tick_count++;
                if (raw_output != 4'd0) nonzero_output_count++;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous scenario numbering");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Pulse 1 vector after row %0d", vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 215_000)
            else $fatal(1, "insufficient model vectors: %0d", vector_count);
        assert (previous_scenario == 6);
        assert (stall_count > 40_000 && write_count > 8_000);
        assert (quarter_count > 2_000 && half_count > 1_000);
        assert (timer_tick_count > 80_000);
        assert (nonzero_output_count > 100);
        $display(
            "PASS: Phase 5B Pulse 1 (%0d Python-reference cycles, %0d stalls, seed=005b2026, zero mismatches)",
            vector_count, stall_count
        );
        $finish;
    end
endmodule
