`timescale 1ns/1ps

module cpu_board_diag #(
    parameter int unsigned DEBUG_DIVIDER = 2_500_000,
    parameter int unsigned STALL_CYCLES = 256,
    parameter int unsigned NMI_PULSE_CYCLES = 4,
    parameter int unsigned WRITE_STRETCH_CYCLES = 25_000_000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        run_cpu_enable,
    input  logic        debug_mode,
    output logic        cpu_enable,
    output logic        pass,
    output logic        fail,
    output logic [7:0]  failure_code,
    output logic        cpu_alive,
    output logic        write_activity,
    output logic        irq_observed,
    output logic        nmi_observed,
    output logic        stall_active,
    output logic        stall_tested,
    output logic [15:0] bus_address,
    output logic [7:0]  bus_write_data,
    output logic [7:0]  bus_read_data,
    output logic        bus_write_enable,
    output logic        bus_valid,
    output logic [15:0] debug_pc,
    output logic [7:0]  debug_instruction,
    output logic [15:0] observed_pc,
    output logic [7:0]  observed_instruction
);
    import cpu_board_diag_pkg::*;
    import cpu_pkg::*;

    localparam int unsigned DEBUG_COUNTER_WIDTH = $clog2(DEBUG_DIVIDER + 1);
    localparam int unsigned STALL_COUNTER_WIDTH = $clog2(STALL_CYCLES + 1);
    localparam int unsigned NMI_COUNTER_WIDTH = $clog2(NMI_PULSE_CYCLES + 1);
    localparam int unsigned WRITE_COUNTER_WIDTH =
        $clog2(WRITE_STRETCH_CYCLES + 1);

    logic [DEBUG_COUNTER_WIDTH-1:0] debug_counter;
    logic [STALL_COUNTER_WIDTH-1:0] stall_counter;
    logic [NMI_COUNTER_WIDTH-1:0] nmi_counter;
    logic [WRITE_COUNTER_WIDTH-1:0] write_counter;
    logic debug_enable_pulse;
    logic requested_cpu_enable;
    logic irq_line;
    logic nmi_line;
    logic irq_acknowledged;
    logic irq_vector_observed;
    logic nmi_vector_observed;
    logic nmi_requested;
    logic brk_vector_observed;
    logic stall_arming;
    logic stall_completed;
    logic stall_violation;
    logic pass_pending;
    logic [19:0] alive_counter;
    logic [15:0] pass_pc_latch;
    logic [7:0] pass_instruction_latch;
    logic [31:0] ram_write_count;

    logic [7:0] debug_a;
    logic [7:0] debug_x;
    logic [7:0] debug_y;
    logic [7:0] debug_sp;
    cpu_status_t debug_status;
    cpu_execution_state_t debug_execution_state;
    cpu_instruction_t debug_decoded_instruction;
    logic [3:0] debug_addressing_mode;
    logic [15:0] debug_effective_address;
    logic debug_page_cross;
    logic debug_page_cross_valid;

    logic [103:0] stall_observation;
    logic [103:0] stall_snapshot;

    logic bus_write_commit;
    logic bus_read_commit;
    logic result_write;
    logic irq_control_write;
    logic nmi_control_write;
    logic stall_control_write;
    logic prerequisites_complete;
    logic [7:0] stall_status;

    initial begin
        assert (DEBUG_DIVIDER >= 2);
        assert (STALL_CYCLES >= 4);
        assert (NMI_PULSE_CYCLES >= 2);
        assert (WRITE_STRETCH_CYCLES >= 2);
    end

    assign debug_enable_pulse =
        debug_mode && (debug_counter == DEBUG_COUNTER_WIDTH'(DEBUG_DIVIDER - 1));
    assign requested_cpu_enable = debug_mode ? debug_enable_pulse : run_cpu_enable;
    assign stall_active = stall_counter != '0;
    assign cpu_enable = requested_cpu_enable && !stall_active;
    assign nmi_line = nmi_counter != '0;

    assign bus_write_commit =
        cpu_enable && bus_valid && bus_write_enable;
    assign bus_read_commit =
        cpu_enable && bus_valid && !bus_write_enable;
    assign result_write = bus_write_commit &&
                          bus_address == CPU_DIAG_RESULT_ADDRESS;
    assign irq_control_write = bus_write_commit &&
                               bus_address == CPU_DIAG_IRQ_CONTROL;
    assign nmi_control_write = bus_write_commit &&
                               bus_address == CPU_DIAG_NMI_CONTROL;
    assign stall_control_write = bus_write_commit &&
                                 bus_address == CPU_DIAG_STALL_CONTROL;

    assign irq_observed = irq_vector_observed;
    assign nmi_observed = nmi_vector_observed;
    assign stall_tested = stall_completed && !stall_violation;
    assign stall_status = stall_tested ? CPU_DIAG_PASS_SIGNATURE : 8'h00;
    assign cpu_alive = alive_counter[19];
    assign write_activity = write_counter != '0;
    assign prerequisites_complete = brk_vector_observed &&
                                    irq_vector_observed && irq_acknowledged &&
                                    nmi_requested && nmi_vector_observed &&
                                    stall_tested;

    assign stall_observation = {
        debug_a, debug_x, debug_y, debug_sp, debug_pc, debug_status,
        debug_instruction, debug_execution_state, bus_address,
        bus_write_data, bus_write_enable, bus_valid, bus_read_data
    };

    assign observed_pc = pass ? pass_pc_latch : debug_pc;
    assign observed_instruction =
        pass ? pass_instruction_latch : debug_instruction;

    cpu_core cpu (
        .clk(clk),
        .reset(reset),
        .cpu_enable(cpu_enable),
        .nmi(nmi_line),
        .irq(irq_line),
        .bus_address(bus_address),
        .bus_write_data(bus_write_data),
        .bus_read_data(bus_read_data),
        .bus_write_enable(bus_write_enable),
        .bus_valid(bus_valid),
        .debug_a(debug_a),
        .debug_x(debug_x),
        .debug_y(debug_y),
        .debug_sp(debug_sp),
        .debug_pc(debug_pc),
        .debug_status(debug_status),
        .debug_instruction(debug_instruction),
        .debug_execution_state(debug_execution_state),
        .debug_decoded_instruction(debug_decoded_instruction),
        .debug_addressing_mode(debug_addressing_mode),
        .debug_effective_address(debug_effective_address),
        .debug_page_cross(debug_page_cross),
        .debug_page_cross_valid(debug_page_cross_valid)
    );

    cpu_board_diag_memory memory (
        .clk(clk),
        .reset(reset),
        .cpu_enable(cpu_enable),
        .address(bus_address),
        .write_data(bus_write_data),
        .write_enable(bus_write_enable),
        .valid(bus_valid),
        .stall_status(stall_status),
        .read_data(bus_read_data),
        .ram_write_count(ram_write_count)
    );

    always_ff @(posedge clk) begin
        if (reset || !debug_mode) begin
            debug_counter <= '0;
        end else if (debug_enable_pulse) begin
            debug_counter <= '0;
        end else begin
            debug_counter <= debug_counter + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            irq_line <= 1'b0;
            irq_acknowledged <= 1'b0;
        end else if (irq_control_write) begin
            if (bus_write_data == CPU_DIAG_REQUEST_SIGNATURE) begin
                irq_line <= 1'b1;
            end else if (bus_write_data == CPU_DIAG_PASS_SIGNATURE) begin
                if (irq_line) begin
                    irq_acknowledged <= 1'b1;
                end
                irq_line <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            nmi_counter <= '0;
            nmi_requested <= 1'b0;
        end else if (nmi_control_write &&
                     bus_write_data == CPU_DIAG_REQUEST_SIGNATURE) begin
            nmi_counter <= NMI_COUNTER_WIDTH'(NMI_PULSE_CYCLES);
            nmi_requested <= 1'b1;
        end else if (nmi_counter != '0) begin
            nmi_counter <= nmi_counter - 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            irq_vector_observed <= 1'b0;
            nmi_vector_observed <= 1'b0;
            brk_vector_observed <= 1'b0;
        end else if (bus_read_commit) begin
            if ((bus_address == CPU_VECTOR_IRQ_LOW ||
                 bus_address == CPU_VECTOR_IRQ_LOW + 16'd1) && irq_line) begin
                irq_vector_observed <= 1'b1;
            end
            if ((bus_address == CPU_VECTOR_IRQ_LOW ||
                 bus_address == CPU_VECTOR_IRQ_LOW + 16'd1) && !irq_line) begin
                brk_vector_observed <= 1'b1;
            end
            if (bus_address == CPU_VECTOR_NMI_LOW ||
                bus_address == CPU_VECTOR_NMI_LOW + 16'd1) begin
                nmi_vector_observed <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            stall_counter <= '0;
            stall_arming <= 1'b0;
            stall_completed <= 1'b0;
            stall_violation <= 1'b0;
            stall_snapshot <= '0;
        end else if (stall_control_write &&
                     bus_write_data == CPU_DIAG_REQUEST_SIGNATURE) begin
            stall_counter <= STALL_COUNTER_WIDTH'(STALL_CYCLES);
            stall_arming <= 1'b1;
            stall_completed <= 1'b0;
            stall_violation <= 1'b0;
        end else if (stall_counter != '0) begin
            stall_counter <= stall_counter - 1'b1;
            if (stall_arming) begin
                stall_snapshot <= stall_observation;
                stall_arming <= 1'b0;
            end else if (stall_observation != stall_snapshot) begin
                stall_violation <= 1'b1;
            end
            if (stall_counter == STALL_COUNTER_WIDTH'(1)) begin
                stall_completed <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            alive_counter <= '0;
            write_counter <= '0;
        end else begin
            if (cpu_enable) begin
                alive_counter <= alive_counter + 1'b1;
            end
            if (bus_write_commit) begin
                write_counter <= WRITE_COUNTER_WIDTH'(WRITE_STRETCH_CYCLES);
            end else if (write_counter != '0) begin
                write_counter <= write_counter - 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            pass <= 1'b0;
            fail <= 1'b0;
            failure_code <= 8'h00;
            pass_pending <= 1'b0;
            pass_pc_latch <= 16'h0000;
            pass_instruction_latch <= 8'h00;
        end else if (!pass && !fail) begin
            if (debug_execution_state == CPU_STATE_TRAP) begin
                fail <= 1'b1;
                failure_code <= CPU_DIAG_TRAP_FAILURE;
            end else if (result_write) begin
                if (bus_write_data != CPU_DIAG_PASS_SIGNATURE) begin
                    fail <= 1'b1;
                    failure_code <= bus_write_data;
                end else if (!prerequisites_complete) begin
                    fail <= 1'b1;
                    failure_code <= CPU_DIAG_INTERNAL_FAILURE;
                end else begin
                    pass_pending <= 1'b1;
                end
            end else if (pass_pending &&
                         debug_execution_state == CPU_STATE_FETCH &&
                         debug_pc == CPU_DIAG_PASS_LOOP &&
                         debug_instruction == 8'h4C) begin
                pass <= 1'b1;
                pass_pending <= 1'b0;
                pass_pc_latch <= debug_pc;
                pass_instruction_latch <= debug_instruction;
            end
        end
    end
endmodule
