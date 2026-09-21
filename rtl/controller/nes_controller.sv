`timescale 1ns/1ps

// Two standard NES controllers behind the Phase 4A $4016/$4017 bus port.
// Button vectors use NES serial order: bit 0=A through bit 7=Right.
module nes_controller (
    input  logic       clk,
    input  logic       reset,

    input  logic [7:0] controller1_buttons,
    input  logic [7:0] controller2_buttons,

    input  logic       cpu_port,
    input  logic       cpu_read,
    input  logic       cpu_write,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [7:0] cpu_write_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [7:0] cpu_read_data,

    output logic       debug_strobe,
    output logic [7:0] debug_live_controller1,
    output logic [7:0] debug_live_controller2,
    output logic [7:0] debug_shift_controller1,
    output logic [7:0] debug_shift_controller2,
    output logic [3:0] debug_index_controller1,
    output logic [3:0] debug_index_controller2,
    output logic       debug_serial_controller1,
    output logic       debug_serial_controller2,
    output logic       debug_read_4016,
    output logic       debug_read_4017,
    output logic       debug_latch_event
);
    logic strobe;
    logic [7:0] shift_controller1;
    logic [7:0] shift_controller2;
    logic [3:0] index_controller1;
    logic [3:0] index_controller2;
    logic serial_controller1;
    logic serial_controller2;

    // When strobe is high, the data pin follows the live A button. With
    // strobe low, the latched LSB is presented before the accepted read edge.
    assign serial_controller1 = strobe ? controller1_buttons[0] :
                                         shift_controller1[0];
    assign serial_controller2 = strobe ? controller2_buttons[0] :
                                         shift_controller2[0];
    assign cpu_read_data = reset ? 8'h00 :
                           {7'b0000000,
                            cpu_port ? serial_controller2 :
                                       serial_controller1};

    assign debug_strobe = strobe;
    assign debug_live_controller1 = controller1_buttons;
    assign debug_live_controller2 = controller2_buttons;
    assign debug_shift_controller1 = shift_controller1;
    assign debug_shift_controller2 = shift_controller2;
    assign debug_index_controller1 = index_controller1;
    assign debug_index_controller2 = index_controller2;
    assign debug_serial_controller1 = serial_controller1;
    assign debug_serial_controller2 = serial_controller2;
    assign debug_read_4016 = !reset && cpu_read && !cpu_port;
    assign debug_read_4017 = !reset && cpu_read && cpu_port;
    assign debug_latch_event = !reset && cpu_write && strobe &&
                               !cpu_write_data[0];

    always_ff @(posedge clk) begin
        if (reset) begin
            strobe <= 1'b0;
            shift_controller1 <= 8'h00;
            shift_controller2 <= 8'h00;
            index_controller1 <= 4'd0;
            index_controller2 <= 4'd0;
        end else begin
            if (cpu_write) begin
                // $4016 bit 0 is shared by both ports. The high-to-low edge
                // captures both live button vectors at exactly the same time.
                if (strobe && !cpu_write_data[0]) begin
                    shift_controller1 <= controller1_buttons;
                    shift_controller2 <= controller2_buttons;
                    index_controller1 <= 4'd0;
                    index_controller2 <= 4'd0;
                end
                strobe <= cpu_write_data[0];
            end

            if (cpu_read && !strobe) begin
                if (!cpu_port) begin
                    // Inserting one makes every read after the eighth return
                    // the standard NES-compatible logical one.
                    shift_controller1 <= {1'b1, shift_controller1[7:1]};
                    if (index_controller1 < 4'd8)
                        index_controller1 <= index_controller1 + 4'd1;
                end else begin
                    shift_controller2 <= {1'b1, shift_controller2[7:1]};
                    if (index_controller2 < 4'd8)
                        index_controller2 <= index_controller2 + 4'd1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (index_controller1 <= 4'd8);
        assert (index_controller2 <= 4'd8);
        assert (cpu_read_data[7:1] == 7'b0000000);
        if (reset) begin
            assert (cpu_read_data == 8'h00);
            assert (!(debug_read_4016 || debug_read_4017 ||
                      debug_latch_event));
        end else
            assert (!(cpu_read && cpu_write));
    end
`endif
endmodule
