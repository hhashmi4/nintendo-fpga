`timescale 1ns/1ps

module nes_apu_phase5a_tb;
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
    int unsigned quarter_count = 0;
    int unsigned half_count = 0;
    int unsigned channel_write_count = 0;
    int unsigned status_write_count = 0;

    logic expected_reset;
    logic expected_enable;
    logic expected_read;
    logic expected_write;
    logic [15:0] expected_address;
    logic [7:0] expected_write_data;
    logic [4:0] expected_channel_active;
    logic expected_dmc_irq;
    logic [7:0] expected_read_data;
    logic expected_irq;
    logic [3:0] expected_pulse1_output;
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

    nes_apu dut (.*);

    always #5 clk <= !clk;

    task automatic check_event_outputs;
        begin
            assert (!$isunknown({cpu_read_data, irq, quarter_frame_tick,
                                 half_frame_tick, channel_write,
                                 channel_write_register, channel_write_data,
                                 dmc_irq_clear}))
                else $fatal(1, "unknown event output at vector %0d", vector_count);
            assert (cpu_read_data == expected_read_data)
                else $fatal(1, "read data row %0d: got %02x expected %02x",
                            vector_count, cpu_read_data, expected_read_data);
            assert (irq == expected_irq)
                else $fatal(1, "IRQ mismatch row %0d", vector_count);
            assert (pulse1_output == expected_pulse1_output)
                else $fatal(1, "Pulse 1 output row %0d: got %0x expected %0x",
                            vector_count, pulse1_output,
                            expected_pulse1_output);
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

    task automatic check_state_outputs;
        begin
            assert (!$isunknown({channel_enable, frame_mode,
                                 frame_irq_inhibit, frame_irq_flag,
                                 frame_sequence_cycle, cpu_cycle_odd,
                                 frame_reset_pending, frame_reset_delay,
                                 frame_tick_block}))
                else $fatal(1, "unknown state at vector %0d", vector_count);
            assert (channel_enable == expected_channel_enable)
                else $fatal(1, "enable state mismatch row %0d", vector_count);
            assert (frame_mode == expected_mode &&
                    frame_irq_inhibit == expected_inhibit &&
                    frame_irq_flag == expected_frame_irq)
                else $fatal(1, "frame control mismatch row %0d", vector_count);
            assert (frame_sequence_cycle == expected_frame_cycle &&
                    cpu_cycle_odd == expected_cycle_odd)
                else $fatal(1, "frame timing state mismatch row %0d", vector_count);
            assert (frame_reset_pending == expected_reset_pending &&
                    frame_reset_delay == expected_reset_delay &&
                    frame_tick_block == expected_tick_block)
                else $fatal(1, "delayed reset mismatch row %0d", vector_count);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_phase5a.fst");
        $dumpvars(0, nes_apu_phase5a_tb);

        vector_file = $fopen("build/sim/nes_apu_phase5a_reference.txt", "r");
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5A APU reference vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %x %x %x %d %x %d %x %d %d %d %x %x %d %x %d %d %d %x %d %d %d %d\n",
                scenario, expected_reset, expected_enable,
                expected_read, expected_write, expected_address,
                expected_write_data, expected_channel_active,
                expected_dmc_irq, expected_read_data, expected_irq,
                expected_pulse1_output, expected_quarter, expected_half,
                expected_channel_write,
                expected_channel_register, expected_channel_data,
                expected_dmc_clear, expected_channel_enable, expected_mode,
                expected_inhibit, expected_frame_irq, expected_frame_cycle,
                expected_cycle_odd, expected_reset_pending,
                expected_reset_delay, expected_tick_block
            );
            if (scan_result == 27) begin
                @(negedge clk);
                reset = expected_reset;
                cpu_cycle_enable = expected_enable;
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
                check_state_outputs();

                vector_count++;
                if (expected_reset) reset_count++;
                if (!expected_enable) stall_count++;
                if (expected_quarter) quarter_count++;
                if (expected_half) half_count++;
                if (expected_channel_write) channel_write_count++;
                if (expected_dmc_clear) status_write_count++;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous scenario numbering");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed APU reference vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 140_000)
            else $fatal(1, "insufficient model-comparison vectors: %0d",
                        vector_count);
        assert (previous_scenario == 5);
        assert (reset_count >= 3 && stall_count > 5_000);
        assert (quarter_count >= 9 && half_count >= 5);
        assert (channel_write_count >= 20 && status_write_count >= 1);
        $display(
            "PASS: Phase 5A APU foundation (%0d Python-reference cycles, %0d stalls, seed=005a2026)",
            vector_count, stall_count
        );
        $finish;
    end
endmodule
