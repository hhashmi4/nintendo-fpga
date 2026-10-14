`timescale 1ns/1ps

// Shared extraction of the existing build-time/runtime NROM translation.
// Memory reads must continue on every fabric clock, ahead of bus acceptance.
module nes_mapper0_address (
    input  logic        nrom_256,
    input  logic [14:0] cpu_address,
    output logic [14:0] prg_address
);
    assign prg_address = nrom_256 ? cpu_address[14:0] :
                                  {1'b0, cpu_address[13:0]};
endmodule
