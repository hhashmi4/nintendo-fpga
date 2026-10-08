`timescale 1ns/1ps

// Small dual-clock FIFO with Gray-coded pointer synchronization.  Only Gray
// pointers cross clock domains; sample words remain in dual-port storage.
module audio_async_fifo #(
    parameter int unsigned WIDTH = 16,
    parameter int unsigned DEPTH = 32
) (
    input  logic                         write_clk,
    input  logic                         write_reset,
    input  logic                         write_enable,
    input  logic [WIDTH-1:0]             write_data,
    output logic                         full,
    output logic                         overflow_event,
    output logic [$clog2(DEPTH):0]       write_level,
    input  logic                         read_clk,
    input  logic                         read_reset,
    input  logic                         read_enable,
    output logic [WIDTH-1:0]             read_data,
    output logic                         empty,
    output logic                         underflow_event,
    output logic [$clog2(DEPTH):0]       read_level
);
    localparam int unsigned ADDRESS_WIDTH = $clog2(DEPTH);
    localparam int unsigned POINTER_WIDTH = ADDRESS_WIDTH + 1;

    logic [WIDTH-1:0] storage [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_binary;
    logic [POINTER_WIDTH-1:0] write_gray;
    logic [POINTER_WIDTH-1:0] read_binary;
    logic [POINTER_WIDTH-1:0] read_gray;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [POINTER_WIDTH-1:0] read_gray_sync1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [POINTER_WIDTH-1:0] read_gray_sync2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [POINTER_WIDTH-1:0] write_gray_sync1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [POINTER_WIDTH-1:0] write_gray_sync2;
    logic [POINTER_WIDTH-1:0] write_binary_next;
    logic [POINTER_WIDTH-1:0] write_gray_next;
    logic [POINTER_WIDTH-1:0] read_binary_next;
    logic [POINTER_WIDTH-1:0] read_gray_next;
    logic [POINTER_WIDTH-1:0] read_binary_sync;
    logic [POINTER_WIDTH-1:0] write_binary_sync;

    function automatic logic [POINTER_WIDTH-1:0] binary_to_gray(
        input logic [POINTER_WIDTH-1:0] value
    );
        binary_to_gray = (value >> 1) ^ value;
    endfunction

    function automatic logic [POINTER_WIDTH-1:0] gray_to_binary(
        input logic [POINTER_WIDTH-1:0] value
    );
        logic [POINTER_WIDTH-1:0] result;
        integer index;
        begin
            result[POINTER_WIDTH-1] = value[POINTER_WIDTH-1];
            for (index = POINTER_WIDTH - 2; index >= 0; index = index - 1)
                result[index] = result[index + 1] ^ value[index];
            gray_to_binary = result;
        end
    endfunction

    always_comb begin
        full = write_gray == {
            ~read_gray_sync2[POINTER_WIDTH-1:POINTER_WIDTH-2],
            read_gray_sync2[POINTER_WIDTH-3:0]
        };
        empty = read_gray == write_gray_sync2;
        write_binary_next = write_binary +
                            POINTER_WIDTH'(write_enable && !full);
        write_gray_next = binary_to_gray(write_binary_next);
        read_binary_next = read_binary +
                           POINTER_WIDTH'(read_enable && !empty);
        read_gray_next = binary_to_gray(read_binary_next);
        read_binary_sync = gray_to_binary(read_gray_sync2);
        write_binary_sync = gray_to_binary(write_gray_sync2);
        write_level = write_binary - read_binary_sync;
        read_level = write_binary_sync - read_binary;
        read_data = storage[read_binary[ADDRESS_WIDTH-1:0]];
    end

    always_ff @(posedge write_clk) begin
        if (write_reset) begin
            write_binary <= '0;
            write_gray <= '0;
            read_gray_sync1 <= '0;
            read_gray_sync2 <= '0;
            overflow_event <= 1'b0;
        end else begin
            read_gray_sync1 <= read_gray;
            read_gray_sync2 <= read_gray_sync1;
            overflow_event <= write_enable && full;
            if (write_enable && !full) begin
                storage[write_binary[ADDRESS_WIDTH-1:0]] <= write_data;
                write_binary <= write_binary_next;
                write_gray <= write_gray_next;
            end
        end
    end

    always_ff @(posedge read_clk) begin
        if (read_reset) begin
            read_binary <= '0;
            read_gray <= '0;
            write_gray_sync1 <= '0;
            write_gray_sync2 <= '0;
            underflow_event <= 1'b0;
        end else begin
            write_gray_sync1 <= write_gray;
            write_gray_sync2 <= write_gray_sync1;
            underflow_event <= read_enable && empty;
            if (read_enable && !empty) begin
                read_binary <= read_binary_next;
                read_gray <= read_gray_next;
            end
        end
    end

    initial begin
        if (DEPTH < 4 || (DEPTH & (DEPTH - 1)) != 0)
            $error("audio_async_fifo DEPTH must be a power of two >= 4");
    end
endmodule
