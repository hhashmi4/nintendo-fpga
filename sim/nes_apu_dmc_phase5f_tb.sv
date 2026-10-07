`timescale 1ns/1ps

module nes_apu_dmc_phase5f_tb;
    import nes_apu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_cycle_enable = 1'b0;
    logic enable = 1'b0;
    logic status_write = 1'b0;
    logic write = 1'b0;
    logic [1:0] write_register = 2'd0;
    logic [7:0] write_data = 8'h00;
    logic mem_request;
    logic [15:0] mem_address;
    logic mem_acknowledge = 1'b0;
    logic [7:0] mem_read_data = 8'h00;
    logic active;
    logic irq_flag;
    logic [6:0] raw_output;
    logic irq_enable;
    logic loop;
    logic [3:0] rate_index;
    logic [7:0] sample_address_register;
    logic [7:0] sample_length_register;
    logic [15:0] current_address;
    logic [11:0] bytes_remaining;
    logic [7:0] sample_buffer;
    logic sample_buffer_empty;
    logic [7:0] shift_register;
    logic [3:0] bits_remaining;
    logic silence;
    logic [8:0] timer_period;
    logic [8:0] timer_counter;

    int vector_file;
    int scan_result;
    int scenario;
    int previous_scenario = 0;
    int unsigned vector_count = 0;
    int unsigned stall_count = 0;
    int unsigned ack_count = 0;
    int unsigned request_count = 0;
    int unsigned output_change_count = 0;
    logic [6:0] previous_output = 7'd0;
    logic [15:0] rate_seen = '0;
    logic wrap_seen = 1'b0;

    logic expected_reset;
    logic expected_ce;
    logic expected_enable;
    logic expected_status_write;
    logic expected_write;
    logic [1:0] expected_write_register;
    logic [7:0] expected_write_data;
    logic expected_ack;
    logic [7:0] expected_mem_data;
    logic expected_pre_active;
    logic expected_pre_irq;
    logic [6:0] expected_pre_output;
    logic expected_pre_request;
    logic [15:0] expected_pre_address;
    logic expected_irq_enable;
    logic expected_loop;
    logic [3:0] expected_rate_index;
    logic [7:0] expected_address_register;
    logic [7:0] expected_length_register;
    logic [15:0] expected_current_address;
    logic [11:0] expected_bytes_remaining;
    logic [7:0] expected_sample_buffer;
    logic expected_buffer_empty;
    logic [7:0] expected_shift_register;
    logic [3:0] expected_bits_remaining;
    logic expected_silence;
    logic [6:0] expected_output;
    logic [8:0] expected_timer_period;
    logic [8:0] expected_timer_counter;
    logic expected_post_request;
    logic [15:0] expected_post_address;
    logic expected_post_irq;

    nes_apu_dmc dut (.*);

    always #5 clk <= !clk;

    task automatic check_pre_edge;
        begin
            assert (!$isunknown({active, irq_flag, raw_output, mem_request,
                                 mem_address}))
                else $fatal(1, "unknown DMC output row %0d", vector_count);
            assert (active == expected_pre_active &&
                    irq_flag == expected_pre_irq &&
                    raw_output == expected_pre_output &&
                    mem_request == expected_pre_request &&
                    mem_address == expected_pre_address)
                else $fatal(1, "DMC pre-edge mismatch row %0d", vector_count);
        end
    endtask

    task automatic check_post_edge;
        begin
            assert (!$isunknown({irq_enable, loop, rate_index,
                                 sample_address_register,
                                 sample_length_register, current_address,
                                 bytes_remaining, sample_buffer,
                                 sample_buffer_empty, shift_register,
                                 bits_remaining, silence, raw_output,
                                 timer_period, timer_counter, mem_request,
                                 mem_address, irq_flag}))
                else $fatal(1, "unknown DMC state row %0d", vector_count);
            assert (irq_enable == expected_irq_enable &&
                    loop == expected_loop &&
                    rate_index == expected_rate_index &&
                    sample_address_register == expected_address_register &&
                    sample_length_register == expected_length_register &&
                    current_address == expected_current_address &&
                    bytes_remaining == expected_bytes_remaining)
                else $fatal(1, "DMC reader/register mismatch row %0d", vector_count);
            assert (sample_buffer == expected_sample_buffer &&
                    sample_buffer_empty == expected_buffer_empty &&
                    shift_register == expected_shift_register &&
                    bits_remaining == expected_bits_remaining &&
                    silence == expected_silence &&
                    raw_output == expected_output)
                else $fatal(1, "DMC output-unit mismatch row %0d", vector_count);
            assert (timer_period == expected_timer_period &&
                    timer_counter == expected_timer_counter &&
                    mem_request == expected_post_request &&
                    mem_address == expected_post_address &&
                    irq_flag == expected_post_irq)
                else $fatal(1, "DMC timing/handshake mismatch row %0d", vector_count);
        end
    endtask

    initial begin
        $dumpfile("build/sim/nes_apu_dmc_phase5f.fst");
        $dumpvars(0, nes_apu_dmc_phase5f_tb);
        vector_file = $fopen(
            "build/sim/nes_apu_dmc_phase5f_reference.txt", "r"
        );
        assert (vector_file != 0)
            else $fatal(1, "cannot open Phase 5F DMC vectors");

        while (!$feof(vector_file)) begin
            scan_result = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                scenario, expected_reset, expected_ce, expected_enable,
                expected_status_write, expected_write,
                expected_write_register, expected_write_data, expected_ack,
                expected_mem_data, expected_pre_active, expected_pre_irq,
                expected_pre_output, expected_pre_request,
                expected_pre_address, expected_irq_enable, expected_loop,
                expected_rate_index, expected_address_register,
                expected_length_register, expected_current_address,
                expected_bytes_remaining, expected_sample_buffer,
                expected_buffer_empty, expected_shift_register,
                expected_bits_remaining, expected_silence, expected_output,
                expected_timer_period, expected_timer_counter,
                expected_post_request, expected_post_address,
                expected_post_irq
            );
            if (scan_result == 33) begin
                @(negedge clk);
                reset = expected_reset;
                cpu_cycle_enable = expected_ce;
                enable = expected_enable;
                status_write = expected_status_write;
                write = expected_write;
                write_register = expected_write_register;
                write_data = expected_write_data;
                mem_acknowledge = expected_ack;
                mem_read_data = expected_mem_data;
                #1;
                check_pre_edge();
                @(posedge clk);
                #1;
                check_post_edge();

                vector_count++;
                if (!expected_ce) stall_count++;
                if (expected_ack) ack_count++;
                if (expected_pre_request) request_count++;
                if (raw_output != previous_output) output_change_count++;
                previous_output = raw_output;
                if (expected_write && expected_write_register == 2'd0)
                    rate_seen[expected_write_data[3:0]] = 1'b1;
                if (expected_pre_address == 16'hffff && expected_ack &&
                    current_address == 16'h8000)
                    wrap_seen = 1'b1;
                if (scenario != previous_scenario) begin
                    assert (scenario == previous_scenario + 1)
                        else $fatal(1, "non-contiguous DMC scenarios");
                    previous_scenario = scenario;
                end
            end else if (scan_result != -1) begin
                $fatal(1, "malformed Phase 5F vector after row %0d",
                       vector_count);
            end
        end
        $fclose(vector_file);

        assert (vector_count > 125_000);
        assert (previous_scenario == 8);
        assert (stall_count > 20_000);
        assert (ack_count > 100 && request_count > 1_000);
        assert (output_change_count > 100);
        assert (&rate_seen && wrap_seen);
        $display("PASS: Phase 5F DMC model comparison vectors=%0d stalls=%0d acks=%0d requests=%0d output_changes=%0d",
                 vector_count, stall_count, ack_count, request_count,
                 output_change_count);
        $finish;
    end
endmodule
