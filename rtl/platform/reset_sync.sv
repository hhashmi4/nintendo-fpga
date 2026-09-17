`timescale 1ns/1ps

module reset_sync #(
    parameter int unsigned STAGES = 2
) (
    input  logic clk,
    input  logic async_reset_n,
    output logic reset
);
    // Cyclone V configuration initializes these registers low. The external
    // active-low reset asserts asynchronously; ones then propagate through
    // the synchronizer so reset can only deassert on a clock edge.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [STAGES-1:0] sync_ff = '0;

    initial begin
        assert (STAGES >= 2)
            else $error("reset_sync requires at least two stages");
    end

    always_ff @(posedge clk or negedge async_reset_n) begin
        if (!async_reset_n) begin
            sync_ff <= '0;
        end else begin
            sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
        end
    end

    assign reset = !sync_ff[STAGES-1];
endmodule
