`timescale 1ns/1ps

module nes_apu_complete_phase5g_tb;
    import nes_apu_pkg::*;

    localparam int INPUT_WIDTH = 43;
    localparam int EVENT_WIDTH = 66;
    localparam int STATE_WIDTH = 377;
    localparam int POST_WIDTH = EVENT_WIDTH + STATE_WIDTH;

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

    logic [INPUT_WIDTH-1:0] vector_input;
    logic [EVENT_WIDTH-1:0] expected_pre;
    logic [POST_WIDTH-1:0] expected_post;
    logic [EVENT_WIDTH-1:0] actual_event;
    logic [STATE_WIDTH-1:0] actual_state;
    logic [POST_WIDTH-1:0] actual_post;

    int vector_file;
    int scan_result;
    int scenario;
    int previous_scenario = 0;
    int unsigned vector_count = 0;
    int unsigned stall_count = 0;
    int unsigned reset_count = 0;
    int unsigned read_count = 0;
    int unsigned write_count = 0;
    int unsigned ack_count = 0;
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned all_active_count = 0;
    int unsigned all_nonzero_count = 0;
    logic [31:0] status_seen = '0;

    nes_apu dut (.*);

    always #5 clk <= !clk;

    assign actual_event = {
        cpu_read_data,
        irq,
        pulse1_output,
        pulse2_output,
        triangle_output,
        noise_output,
        dmc_output,
        quarter_frame_tick,
        half_frame_tick,
        channel_write,
        channel_write_register,
        channel_write_data,
        dmc_irq_clear,
        dmc_mem_request,
        dmc_mem_address
    };

    assign actual_state = {
        channel_enable,
        frame_mode,
        frame_irq_inhibit,
        frame_irq_flag,
        frame_sequence_cycle,
        cpu_cycle_odd,
        frame_reset_pending,
        frame_reset_delay,
        frame_tick_block,

        dut.pulse1.duty,
        dut.pulse1.duty_position,
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

        dut.pulse2.duty,
        dut.pulse2.duty_position,
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

        dut.triangle.control_flag,
        dut.triangle.linear_reload_value,
        dut.triangle.linear_counter,
        dut.triangle.linear_reload_flag,
        dut.triangle.sequence_position,
        dut.triangle.timer_period,
        dut.triangle.timer_counter,
        dut.triangle.length_counter,

        dut.noise.length_halt,
        dut.noise.constant_volume,
        dut.noise.envelope_period,
        dut.noise.envelope_start,
        dut.noise.envelope_divider,
        dut.noise.envelope_decay,
        dut.noise.mode,
        dut.noise.period_index,
        dut.noise.timer_period,
        dut.noise.timer_counter,
        dut.noise.length_counter,
        dut.noise.lfsr,

        dut.dmc.irq_enable,
        dut.dmc.loop,
        dut.dmc.rate_index,
        dut.dmc.sample_address_register,
        dut.dmc.sample_length_register,
        dut.dmc.current_address,
        dut.dmc.bytes_remaining,
        dut.dmc.sample_buffer,
        dut.dmc.sample_buffer_empty,
        dut.dmc.shift_register,
        dut.dmc.bits_remaining,
        dut.dmc.silence,
        dut.dmc.raw_output_register,
        dut.dmc.timer_counter,
        dut.dmc.mem_request_register,
        dut.dmc.mem_address,
        dut.dmc.irq_flag_register
    };

    assign actual_post = {actual_event, actual_state};

    task automatic check_known;
        begin
            assert (!$isunknown({actual_event, actual_state}))
                else $fatal(1, "unknown complete APU state row %0d scenario %0d",
                            vector_count, scenario);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_complete_phase5g.fst");
        $dumpvars(0, nes_apu_complete_phase5g_tb);

        vector_file = $fopen(
            "build/sim/nes_apu_complete_phase5g_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5G complete APU vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file, "%d %h %h %h\n",
                scenario, vector_input, expected_pre, expected_post
            );
            if (scan_result == 4) begin
                @(negedge clk);
                {
                    reset,
                    cpu_cycle_enable,
                    cpu_read,
                    cpu_write,
                    cpu_address,
                    cpu_write_data,
                    channel_active,
                    dmc_irq_flag,
                    dmc_mem_acknowledge,
                    dmc_mem_read_data
                } = vector_input;
                #1;
                check_known();
                assert (actual_event == expected_pre)
                    else $fatal(1,
                        "Phase 5G pre-edge mismatch row %0d scenario %0d got=%h expected=%h",
                        vector_count, scenario, actual_event, expected_pre);

                @(posedge clk);
                #1;
                check_known();
                assert (actual_post == expected_post)
                    else $fatal(1,
                        "Phase 5G post-edge mismatch row %0d scenario %0d got=%h expected=%h",
                        vector_count, scenario, actual_post, expected_post);

                vector_count++;
                if (!cpu_cycle_enable) stall_count++;
                if (reset) reset_count++;
                if (cpu_cycle_enable && cpu_read) read_count++;
                if (cpu_cycle_enable && cpu_write) write_count++;
                if (cpu_cycle_enable && dmc_mem_acknowledge) ack_count++;
                if (quarter_frame_tick) quarter_count++;
                if (half_frame_tick) half_count++;
                if (dut.pulse1.active && dut.pulse2.active &&
                    dut.triangle.active && dut.noise.active && dut.dmc.active)
                    all_active_count++;
                if (pulse1_output != 0 && pulse2_output != 0 &&
                    triangle_output != 0 && noise_output != 0 &&
                    dmc_output != 0)
                    all_nonzero_count++;
                if (cpu_cycle_enable && cpu_read &&
                    cpu_address == APU_STATUS_REGISTER)
                    status_seen[cpu_read_data[4:0]] = 1'b1;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous Phase 5G scenarios");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 5G vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 750_000);
        assert (previous_scenario == 9);
        assert (stall_count > 100_000 && reset_count >= 40);
        assert (read_count > 10_000 && write_count > 60_000);
        assert (ack_count > 300);
        assert (quarter_count > 1_000 && half_count > 1_000);
        assert (all_active_count > 30_000 && all_nonzero_count > 30_000);
        assert (&status_seen);
        $display(
            "PASS: Phase 5G complete APU model comparison cycles=%0d stalls=%0d resets=%0d reads=%0d writes=%0d acks=%0d quarter=%0d half=%0d all-active=%0d all-nonzero=%0d seed=00572026 zero mismatches",
            vector_count, stall_count, reset_count, read_count, write_count,
            ack_count, quarter_count, half_count, all_active_count,
            all_nonzero_count
        );
        $finish;
    end
endmodule
