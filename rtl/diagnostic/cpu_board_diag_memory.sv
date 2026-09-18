`timescale 1ns/1ps

// Flat Phase 2K-only memory: independent zero-page and stack RAM, explicit
// absolute/page-cross test cells, a 1 KiB program ROM window, vector bytes,
// and four diagnostic control/status addresses. No NES decoding or mirroring
// is implemented here.
module cpu_board_diag_memory (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_enable,
    input  logic [15:0] address,
    input  logic [7:0]  write_data,
    input  logic        write_enable,
    input  logic        valid,
    input  logic [7:0]  stall_status,
    output logic [7:0]  read_data,
    output logic [31:0] ram_write_count
);
    import cpu_board_diag_pkg::*;
    import cpu_pkg::*;

    (* ramstyle = "logic" *) logic [7:0] low_ram [0:511];
    logic [7:0] absolute_test_0400;
    logic [7:0] absolute_test_0500;
    logic [7:0] program_rom [0:1023];

    initial begin
        for (int unsigned index = 0; index < 512; index++) begin
            low_ram[index] = 8'h00;
        end
        absolute_test_0400 = 8'h00;
        absolute_test_0500 = 8'h00;
    end

`include "cpu_board_diag_program.svh"

    always_comb begin
        read_data = 8'h00;
        if (valid && !write_enable) begin
            if (address < 16'h0200) begin
                read_data = low_ram[address[8:0]];
            end else if (address == 16'h0400) begin
                read_data = absolute_test_0400;
            end else if (address == 16'h0500) begin
                read_data = absolute_test_0500;
            end else if (address >= CPU_DIAG_PROGRAM_START &&
                         address <= CPU_DIAG_PROGRAM_END) begin
                read_data = program_rom[address[9:0]];
            end else begin
                case (address)
                    CPU_DIAG_STALL_CONTROL: read_data = stall_status;
                    CPU_VECTOR_NMI_LOW: read_data = CPU_DIAG_NMI_HANDLER[7:0];
                    CPU_VECTOR_NMI_LOW + 16'd1:
                        read_data = CPU_DIAG_NMI_HANDLER[15:8];
                    CPU_VECTOR_RESET_LOW:
                        read_data = CPU_DIAG_PROGRAM_START[7:0];
                    CPU_VECTOR_RESET_LOW + 16'd1:
                        read_data = CPU_DIAG_PROGRAM_START[15:8];
                    CPU_VECTOR_IRQ_LOW: read_data = CPU_DIAG_IRQ_HANDLER[7:0];
                    CPU_VECTOR_IRQ_LOW + 16'd1:
                        read_data = CPU_DIAG_IRQ_HANDLER[15:8];
                    default: read_data = 8'h00;
                endcase
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ram_write_count <= 32'd0;
        end else if (cpu_enable && valid && write_enable) begin
            if (address < 16'h0200) begin
                low_ram[address[8:0]] <= write_data;
                ram_write_count <= ram_write_count + 32'd1;
            end else if (address == 16'h0400) begin
                absolute_test_0400 <= write_data;
                ram_write_count <= ram_write_count + 32'd1;
            end else if (address == 16'h0500) begin
                absolute_test_0500 <= write_data;
                ram_write_count <= ram_write_count + 32'd1;
            end
        end
    end
endmodule
