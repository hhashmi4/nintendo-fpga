`timescale 1ns/1ps

module cpu_board_diag_top (
    input  logic       CLOCK_50,
    input  logic       KEY0,
    input  logic       SW0,
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5
);
    logic sys_clk;
    logic clock_locked;
    logic reset_request_n;
    logic reset;
    logic nes_master_ce;
    logic ppu_ce;
    logic run_cpu_ce;
    logic apu_ce;
    logic debug_mode;
    logic cpu_enable;
    logic pass;
    logic fail;
    logic [7:0] failure_code;
    logic cpu_alive;
    logic write_activity;
    logic irq_observed;
    logic nmi_observed;
    logic stall_active;
    logic stall_tested;
    logic bus_valid;
    logic [15:0] debug_pc;
    logic [7:0] debug_instruction;
    logic [15:0] observed_pc;
    logic [7:0] observed_instruction;
    logic [3:0] display_digit [0:5];

    platform_clock clock_source (
        .ref_clk(CLOCK_50),
        .sys_clk(sys_clk),
        .locked(clock_locked)
    );

    assign reset_request_n = KEY0 && clock_locked;

    reset_sync reset_generator (
        .clk(sys_clk),
        .async_reset_n(reset_request_n),
        .reset(reset)
    );

    level_sync debug_switch_sync (
        .clk(sys_clk),
        .reset(reset),
        .async_level(SW0),
        .synced_level(debug_mode)
    );

    nes_timing_gen timing_generator (
        .clk(sys_clk),
        .reset(reset),
        .nes_master_ce(nes_master_ce),
        .ppu_ce(ppu_ce),
        .cpu_ce(run_cpu_ce),
        .apu_ce(apu_ce)
    );

    cpu_board_diag diagnostic (
        .clk(sys_clk),
        .reset(reset),
        .run_cpu_enable(run_cpu_ce),
        .debug_mode(debug_mode),
        .cpu_enable(cpu_enable),
        .pass(pass),
        .fail(fail),
        .failure_code(failure_code),
        .cpu_alive(cpu_alive),
        .write_activity(write_activity),
        .irq_observed(irq_observed),
        .nmi_observed(nmi_observed),
        .stall_active(stall_active),
        .stall_tested(stall_tested),
        .bus_address(),
        .bus_write_data(),
        .bus_read_data(),
        .bus_write_enable(),
        .bus_valid(bus_valid),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .observed_pc(observed_pc),
        .observed_instruction(observed_instruction)
    );

    always_comb begin
        if (fail) begin
            // Failure display is FPPPCC: F, low 12 bits of live PC, code.
            display_digit[5] = 4'hF;
            display_digit[4] = observed_pc[11:8];
            display_digit[3] = observed_pc[7:4];
            display_digit[2] = observed_pc[3:0];
            display_digit[1] = failure_code[7:4];
            display_digit[0] = failure_code[3:0];
        end else begin
            // Normal display is PPPPOO: PC and current debug instruction.
            display_digit[5] = observed_pc[15:12];
            display_digit[4] = observed_pc[11:8];
            display_digit[3] = observed_pc[7:4];
            display_digit[2] = observed_pc[3:0];
            display_digit[1] = observed_instruction[7:4];
            display_digit[0] = observed_instruction[3:0];
        end
    end

    hex7seg hex0_driver (.value(display_digit[0]), .segments_n(HEX0));
    hex7seg hex1_driver (.value(display_digit[1]), .segments_n(HEX1));
    hex7seg hex2_driver (.value(display_digit[2]), .segments_n(HEX2));
    hex7seg hex3_driver (.value(display_digit[3]), .segments_n(HEX3));
    hex7seg hex4_driver (.value(display_digit[4]), .segments_n(HEX4));
    hex7seg hex5_driver (.value(display_digit[5]), .segments_n(HEX5));

    assign LEDR[0] = cpu_alive;
    assign LEDR[1] = pass;
    assign LEDR[2] = fail;
    assign LEDR[3] = write_activity;
    assign LEDR[4] = irq_observed;
    assign LEDR[5] = nmi_observed;
    assign LEDR[6] = bus_valid;
    assign LEDR[7] = stall_tested;
    assign LEDR[8] = debug_mode;
    assign LEDR[9] = reset;
endmodule
