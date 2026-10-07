`timescale 1ns/1ps

// NTSC NES delta-modulation channel. The channel owns the sample reader and
// output unit, but not CPU-bus arbitration: mem_request is a held transaction
// request and is retired exactly once by mem_acknowledge.
module nes_apu_dmc (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_cycle_enable,

    input  logic        enable,
    input  logic        status_write,
    input  logic        write,
    input  logic [1:0]  write_register,
    input  logic [7:0]  write_data,

    output logic        mem_request,
    output logic [15:0] mem_address,
    input  logic        mem_acknowledge,
    input  logic [7:0]  mem_read_data,

    output logic        active,
    output logic        irq_flag,
    output logic [6:0]  raw_output,

    output logic        irq_enable,
    output logic        loop,
    output logic [3:0]  rate_index,
    output logic [7:0]  sample_address_register,
    output logic [7:0]  sample_length_register,
    output logic [15:0] current_address,
    output logic [11:0] bytes_remaining,
    output logic [7:0]  sample_buffer,
    output logic        sample_buffer_empty,
    output logic [7:0]  shift_register,
    output logic [3:0]  bits_remaining,
    output logic        silence,
    output logic [8:0]  timer_period,
    output logic [8:0]  timer_counter
);
    import nes_apu_pkg::*;

    logic output_reload_event;
    logic acknowledge_bypass;
    logic [15:0] programmed_address;
    logic [11:0] programmed_length;
    logic mem_request_register;
    logic irq_flag_register;

    assign programmed_address = {1'b1, 1'b1,
                                 sample_address_register, 6'b000000};
    assign programmed_length = {sample_length_register, 4'b0000} + 12'd1;
    assign timer_period = APU_DMC_RATE_TABLE[rate_index];
    assign active = !reset && bytes_remaining != 12'd0;
    assign raw_output = reset ? 7'd0 : raw_output_register;
    assign mem_request = !reset && mem_request_register;
    assign irq_flag = !reset && irq_flag_register;

    logic [6:0] raw_output_register;

    // When the reader returns a byte on the same edge that a new output unit
    // begins, forward it directly into the shifter instead of manufacturing
    // an eight-bit silent gap or briefly claiming the one-byte buffer is full.
    assign output_reload_event = cpu_cycle_enable && timer_counter == 9'd0 &&
                                 bits_remaining == 4'd1;
    assign acknowledge_bypass = mem_acknowledge && output_reload_event &&
                                sample_buffer_empty;

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_request_register    <= 1'b0;
            mem_address             <= 16'h0000;
            irq_flag_register       <= 1'b0;
            irq_enable              <= 1'b0;
            loop                    <= 1'b0;
            rate_index              <= 4'd0;
            sample_address_register <= 8'h00;
            sample_length_register  <= 8'h00;
            current_address         <= 16'h0000;
            bytes_remaining         <= 12'd0;
            sample_buffer           <= 8'h00;
            sample_buffer_empty     <= 1'b1;
            shift_register          <= 8'h00;
            bits_remaining          <= 4'd8;
            silence                 <= 1'b1;
            raw_output_register     <= 7'd0;
            timer_counter           <= 9'd0;
        end else if (cpu_cycle_enable) begin
            // The output unit runs continuously in CPU/APU time. Disabling
            // the reader does not silence or reset the DAC/output shifter.
            if (timer_counter == 9'd0) begin
                timer_counter <= timer_period - 9'd1;

                if (!silence) begin
                    if (shift_register[0]) begin
                        if (raw_output_register <= 7'd125)
                            raw_output_register <= raw_output_register + 7'd2;
                    end else if (raw_output_register >= 7'd2) begin
                        raw_output_register <= raw_output_register - 7'd2;
                    end
                end

                if (bits_remaining == 4'd1) begin
                    bits_remaining <= 4'd8;
                    if (!sample_buffer_empty) begin
                        shift_register <= sample_buffer;
                        sample_buffer_empty <= 1'b1;
                        silence <= 1'b0;
                    end else begin
                        shift_register <= 8'h00;
                        silence <= 1'b1;
                    end
                end else begin
                    bits_remaining <= bits_remaining - 4'd1;
                    shift_register <= {1'b0, shift_register[7:1]};
                end
            end else begin
                timer_counter <= timer_counter - 9'd1;
            end

            // Reader acknowledgements retire one and only one byte. The
            // address wraps into the documented sample window, never $0000.
            if (mem_acknowledge) begin
                mem_request_register <= 1'b0;
                current_address <= current_address == 16'hffff ?
                                   16'h8000 : current_address + 16'd1;

                if (acknowledge_bypass) begin
                    shift_register <= mem_read_data;
                    bits_remaining <= 4'd8;
                    silence <= 1'b0;
                    sample_buffer_empty <= 1'b1;
                end else begin
                    sample_buffer <= mem_read_data;
                    sample_buffer_empty <= 1'b0;
                end

                if (bytes_remaining == 12'd1) begin
                    if (loop) begin
                        current_address <= programmed_address;
                        bytes_remaining <= programmed_length;
                    end else begin
                        bytes_remaining <= 12'd0;
                        if (irq_enable)
                            irq_flag_register <= 1'b1;
                    end
                end else if (bytes_remaining != 12'd0) begin
                    bytes_remaining <= bytes_remaining - 12'd1;
                end
            end else if (!mem_request_register && sample_buffer_empty &&
                         bytes_remaining != 12'd0) begin
                mem_request_register <= 1'b1;
                mem_address <= current_address;
            end

            // A $4015 write always clears DMC IRQ. Clearing bit 4 terminates
            // the reader; setting it restarts only when no bytes remain.
            if (status_write) begin
                irq_flag_register <= 1'b0;
                if (!enable) begin
                    bytes_remaining <= 12'd0;
                    mem_request_register <= 1'b0;
                end else if (bytes_remaining == 12'd0) begin
                    current_address <= programmed_address;
                    bytes_remaining <= programmed_length;
                    if (sample_buffer_empty && !mem_request_register) begin
                        mem_request_register <= 1'b1;
                        mem_address <= programmed_address;
                    end
                end
            end

            if (write) begin
                case (write_register)
                    2'd0: begin
                        irq_enable <= write_data[7];
                        loop <= write_data[6];
                        rate_index <= write_data[3:0];
                        if (!write_data[7])
                            irq_flag_register <= 1'b0;
                    end
                    2'd1: raw_output_register <= write_data[6:0];
                    2'd2: sample_address_register <= write_data;
                    2'd3: sample_length_register <= write_data;
                    default: begin end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        if (!reset) begin
            assert (bits_remaining >= 4'd1 && bits_remaining <= 4'd8);
            assert (bytes_remaining <= 12'd4081);
        end
        if (mem_request)
            assert (bytes_remaining != 12'd0);
        if (reset) begin
            assert (!mem_request && !active && !irq_flag);
            assert (raw_output == 7'd0);
        end
    end

    always_ff @(posedge clk) begin
        if (!reset && cpu_cycle_enable && mem_acknowledge)
            assert (mem_request_register);
    end
`endif
endmodule
