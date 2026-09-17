`timescale 1ns/1ps

// Generic 64 KiB simulation memory. It has no NES address decoding: reads are
// combinational, while one write is committed on the enabled CPU edge that
// completes a valid write cycle.
module cpu_test_memory (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_enable,
    input  logic [15:0] address,
    input  logic [7:0]  write_data,
    input  logic        write_enable,
    input  logic        valid,
    output logic [7:0]  read_data,
    output logic [31:0] write_count,
    output logic [15:0] last_write_address,
    output logic [7:0]  last_write_data
);
    logic [7:0] memory [0:65_535];

    initial begin
        for (int unsigned index = 0; index < 65_536; index++) begin
            memory[index] = 8'h00;
        end
    end

    always_comb begin
        read_data = 8'h00;
        if (valid && !write_enable) begin
            read_data = memory[address];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            write_count       <= 32'd0;
            last_write_address <= 16'h0000;
            last_write_data    <= 8'h00;
        end else if (cpu_enable && valid && write_enable) begin
            memory[address]    <= write_data;
            write_count        <= write_count + 32'd1;
            last_write_address <= address;
            last_write_data    <= write_data;
        end
    end
endmodule
