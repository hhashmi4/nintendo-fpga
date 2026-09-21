`timescale 1ns/1ps

// Synchronizes an abstract controller-state vector into the 50 MHz fabric
// domain. Debouncing, USB decoding, Bluetooth, or original-port sampling can
// be placed before this boundary without changing nes_controller.
module controller_input_sync #(
    parameter int WIDTH = 8
) (
    input  logic             clk,
    input  logic             reset,
    input  logic [WIDTH-1:0] async_buttons,
    output logic [WIDTH-1:0] synced_buttons
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [WIDTH-1:0] meta_buttons;

    always_ff @(posedge clk) begin
        if (reset) begin
            meta_buttons <= '0;
            synced_buttons <= '0;
        end else begin
            meta_buttons <= async_buttons;
            synced_buttons <= meta_buttons;
        end
    end
endmodule
