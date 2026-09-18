`timescale 1ns/1ps

module level_sync (
    input  logic clk,
    input  logic reset,
    input  logic async_level,
    output logic synced_level
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic meta_level;

    always_ff @(posedge clk) begin
        if (reset) begin
            meta_level <= 1'b0;
            synced_level <= 1'b0;
        end else begin
            meta_level <= async_level;
            synced_level <= meta_level;
        end
    end
endmodule
