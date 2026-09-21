`timescale 1ns/1ps

// NES internal work RAM. The eleven-bit physical address implements the four
// CPU-visible mirrors before this module, so only one 2 KiB array exists.
// Contents intentionally have no reset value; software must initialize any
// location before depending on it, matching SRAM behavior while preserving
// block-RAM inference. Read data is registered for Cyclone V M10K mapping.
module nes_cpu_ram (
    input  logic        clk,
    input  logic [10:0] read_address,
    output logic [7:0]  read_data,
    input  logic        write_enable,
    input  logic [10:0] write_address,
    input  logic [7:0]  write_data
);
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory [0:2047];

    always_ff @(posedge clk) begin
        read_data <= memory[read_address];
        if (write_enable)
            memory[write_address] <= write_data;
    end
endmodule
