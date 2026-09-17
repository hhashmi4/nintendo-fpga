`timescale 1ns/1ps

module cpu_phase2g_tb;
    import cpu_pkg::*;

    localparam logic [15:0] PROGRAM_START = 16'h8000;
    localparam logic [15:0] NMI_HANDLER = 16'h9000;
    localparam logic [15:0] IRQ_HANDLER = 16'hA000;
    localparam int unsigned STATUS_VECTOR_COUNT = 64;
    localparam int unsigned SP_VECTOR_COUNT = 6;

    localparam logic [7:0] STACK_POINTERS [0:5] = '{
        8'h00, 8'h01, 8'h02, 8'hFD, 8'hFE, 8'hFF
    };
    localparam logic [15:0] RESET_TARGETS [0:3] = '{
        16'h0000, 16'h0200, 16'h8000, 16'hFFFF
    };

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic nmi = 1'b0;
    logic irq = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data;
    logic bus_write_enable;
    logic bus_valid;
    logic [7:0] debug_a;
    logic [7:0] debug_x;
    logic [7:0] debug_y;
    logic [7:0] debug_sp;
    logic [15:0] debug_pc;
    cpu_status_t debug_status;
    logic [7:0] debug_instruction;
    cpu_execution_state_t debug_execution_state;
    cpu_instruction_t debug_decoded_instruction;
    logic [3:0] debug_addressing_mode;
    logic [15:0] debug_effective_address;
    logic debug_page_cross;
    logic debug_page_cross_valid;
    logic [31:0] memory_write_count;
    logic [15:0] last_write_address;
    logic [7:0] last_write_data;

    logic [15:0] trace_address [0:63];
    logic [7:0] trace_write_data [0:63];
    logic trace_write_enable [0:63];
    int unsigned trace_count = 0;
    int unsigned directed_vector_count = 0;
    int unsigned stall_check_count = 0;
    int unsigned reset_priority_count = 0;

    cpu_core dut (
        .clk                       (clk),
        .reset                     (reset),
        .cpu_enable                (cpu_enable),
        .nmi                       (nmi),
        .irq                       (irq),
        .bus_address               (bus_address),
        .bus_write_data            (bus_write_data),
        .bus_read_data             (bus_read_data),
        .bus_write_enable          (bus_write_enable),
        .bus_valid                 (bus_valid),
        .debug_a                   (debug_a),
        .debug_x                   (debug_x),
        .debug_y                   (debug_y),
        .debug_sp                  (debug_sp),
        .debug_pc                  (debug_pc),
        .debug_status              (debug_status),
        .debug_instruction         (debug_instruction),
        .debug_execution_state     (debug_execution_state),
        .debug_decoded_instruction (debug_decoded_instruction),
        .debug_addressing_mode     (debug_addressing_mode),
        .debug_effective_address   (debug_effective_address),
        .debug_page_cross          (debug_page_cross),
        .debug_page_cross_valid    (debug_page_cross_valid)
    );

    cpu_test_memory memory_model (
        .clk                (clk),
        .reset              (reset),
        .cpu_enable         (cpu_enable),
        .address            (bus_address),
        .write_data         (bus_write_data),
        .write_enable       (bus_write_enable),
        .valid              (bus_valid),
        .read_data          (bus_read_data),
        .write_count        (memory_write_count),
        .last_write_address (last_write_address),
        .last_write_data    (last_write_data)
    );

    always #5 clk <= !clk;

    function automatic logic [7:0] status_from_six_bits(
        input logic [5:0] bits
    );
        logic [7:0] value;
        value = 8'h20;
        value[7] = bits[5];
        value[6] = bits[4];
        value[3] = bits[3];
        value[2] = bits[2];
        value[1] = bits[1];
        value[0] = bits[0];
        return value;
    endfunction

    task automatic step_cpu(input logic record_bus);
        logic [7:0] previous_a;
        logic [7:0] previous_x;
        logic [7:0] previous_y;
        logic [7:0] previous_sp;
        logic [15:0] previous_pc;
        logic [7:0] previous_status;
        cpu_execution_state_t previous_state;
        logic previous_enable;
        logic previous_reset;

        @(negedge clk);
        previous_a = debug_a;
        previous_x = debug_x;
        previous_y = debug_y;
        previous_sp = debug_sp;
        previous_pc = debug_pc;
        previous_status = debug_status;
        previous_state = debug_execution_state;
        previous_enable = cpu_enable;
        previous_reset = reset;

        if (bus_write_enable) begin
            assert (debug_execution_state inside {
                CPU_STATE_MEMORY_WRITE,
                CPU_STATE_RMW_DUMMY_WRITE,
                CPU_STATE_RMW_WRITE,
                CPU_STATE_STACK_PUSH,
                CPU_STATE_JSR_PUSH_HIGH,
                CPU_STATE_JSR_PUSH_LOW,
                CPU_STATE_INTERRUPT_PUSH_HIGH,
                CPU_STATE_INTERRUPT_PUSH_LOW,
                CPU_STATE_INTERRUPT_PUSH_STATUS
            }) else $fatal(1, "write outside an intentional bus state");
        end
        if (record_bus && cpu_enable && bus_valid) begin
            assert (trace_count < 64)
                else $fatal(1, "Phase 2G bus trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write_data[trace_count] = bus_write_data;
            trace_write_enable[trace_count] = bus_write_enable;
            trace_count++;
        end

        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state,
                             debug_decoded_instruction,
                             debug_addressing_mode,
                             debug_effective_address, debug_page_cross,
                             debug_page_cross_valid, bus_address,
                             bus_write_data, bus_write_enable, bus_valid,
                             bus_read_data, memory_write_count,
                             last_write_address, last_write_data,
                             dut.interrupt_source, dut.nmi_pending,
                             dut.nmi_sync, dut.irq_sync}))
            else $fatal(1, "X/Z detected in Phase 2G CPU or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write_enable asserted without valid");

        if (!previous_reset && !previous_enable) begin
            assert ({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                     debug_status, debug_execution_state} ==
                    {previous_a, previous_x, previous_y, previous_sp,
                     previous_pc, previous_status, previous_state})
                else $fatal(1, "architectural state advanced while disabled");
        end
    endtask

    task automatic set_vector(
        input logic [15:0] vector_low,
        input logic [15:0] target
    );
        memory_model.memory[vector_low] = target[7:0];
        memory_model.memory[vector_low + 16'd1] = target[15:8];
    endtask

    task automatic check_trace_read(
        input int unsigned index,
        input logic [15:0] address
    );
        assert (trace_address[index] == address &&
                !trace_write_enable[index])
            else $fatal(1, "read trace mismatch at %0d", index);
    endtask

    task automatic check_trace_write(
        input int unsigned index,
        input logic [15:0] address,
        input logic [7:0] data
    );
        assert (trace_address[index] == address &&
                trace_write_enable[index] &&
                trace_write_data[index] == data)
            else $fatal(1, "write trace mismatch at %0d", index);
    endtask

    task automatic reset_core(input logic [15:0] target);
        set_vector(CPU_VECTOR_RESET_LOW, target);
        reset = 1'b1;
        cpu_enable = 1'b0;
        nmi = 1'b0;
        irq = 1'b0;
        trace_count = 0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_pc == CPU_RESET_PC && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS &&
                !bus_valid && !bus_write_enable && memory_write_count == 0)
            else $fatal(1, "deterministic reset state mismatch");

        reset = 1'b0;
        cpu_enable = 1'b1;
        repeat (7) step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == target && debug_sp == CPU_POST_RESET_SP)
            else $fatal(1, "reset vector did not load PC");
        assert (trace_count == 7)
            else $fatal(1, "reset must expose seven bus reads");
        check_trace_read(0, CPU_RESET_PC);
        check_trace_read(1, CPU_RESET_PC);
        check_trace_read(2, 16'h0100);
        check_trace_read(3, 16'h01FF);
        check_trace_read(4, 16'h01FE);
        check_trace_read(5, CPU_VECTOR_RESET_LOW);
        check_trace_read(6, CPU_VECTOR_RESET_LOW + 16'd1);
        trace_count = 0;
    endtask

    task automatic execute_current_instruction(
        input logic record_bus,
        output int unsigned enabled_steps
    );
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not begin in FETCH");
        enabled_steps = 0;
        do begin
            step_cpu(record_bus);
            enabled_steps++;
            assert (enabled_steps < 24)
                else $fatal(1, "Phase 2G instruction failed to complete");
        end while (debug_execution_state != CPU_STATE_FETCH);
    endtask

    task automatic configure_status_and_sp(
        input logic [7:0] status,
        input logic [7:0] requested_sp
    );
        int unsigned ignored_steps;
        logic [15:0] cursor;
        cursor = debug_pc;
        memory_model.memory[cursor] = 8'hA2; // LDX #(requested_sp - 1)
        memory_model.memory[cursor + 16'd1] = requested_sp - 8'd1;
        memory_model.memory[cursor + 16'd2] = 8'h9A; // TXS
        memory_model.memory[cursor + 16'd3] = 8'h28; // PLP increments to requested_sp
        memory_model.memory[{8'h01, requested_sp}] = status;
        execute_current_instruction(1'b0, ignored_steps);
        execute_current_instruction(1'b0, ignored_steps);
        execute_current_instruction(1'b0, ignored_steps);
        assert (ignored_steps > 0)
            else $fatal(1, "status/SP setup did not execute");
        assert (debug_sp == requested_sp &&
                debug_status == cpu_status_normalize(status))
            else $fatal(1, "status/SP setup failed");
        trace_count = 0;
    endtask

    task automatic synchronize_nmi(input logic level);
        cpu_enable = 1'b0;
        nmi = level;
        repeat (4) step_cpu(1'b0);
    endtask

    task automatic synchronize_irq(input logic level);
        cpu_enable = 1'b0;
        irq = level;
        repeat (3) step_cpu(1'b0);
    endtask

    task automatic service_interrupt;
        int unsigned enabled_steps;
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "interrupt was not sampled at FETCH boundary");
        cpu_enable = 1'b1;
        enabled_steps = 0;
        step_cpu(1'b1);
        enabled_steps++;
        assert (debug_execution_state == CPU_STATE_INTERRUPT_DUMMY)
            else $fatal(1, "interrupt was not recognized");
        while (debug_execution_state != CPU_STATE_FETCH) begin
            step_cpu(1'b1);
            enabled_steps++;
            assert (enabled_steps < 12)
                else $fatal(1, "interrupt entry did not complete");
        end
        assert (enabled_steps == 7)
            else $fatal(1, "unexpected interrupt enabled-step count");
    endtask

    task automatic check_hardware_interrupt_trace(
        input logic [7:0] starting_sp,
        input logic [15:0] return_pc,
        input logic [7:0] status,
        input logic [15:0] vector_low
    );
        assert (trace_count == 7)
            else $fatal(1, "hardware interrupt trace length mismatch");
        check_trace_read(0, return_pc);
        check_trace_read(1, return_pc);
        check_trace_write(2, {8'h01, starting_sp}, return_pc[15:8]);
        check_trace_write(3, {8'h01, starting_sp - 8'd1}, return_pc[7:0]);
        check_trace_write(4, {8'h01, starting_sp - 8'd2},
                          cpu_status_for_interrupt(status));
        check_trace_read(5, vector_low);
        check_trace_read(6, vector_low + 16'd1);
    endtask

    task automatic test_status_space;
        logic [7:0] status;
        logic [15:0] return_pc;
        int unsigned rti_steps;
        for (int unsigned raw = 0; raw < STATUS_VECTOR_COUNT; raw++) begin
            reset_core(PROGRAM_START);
            status = status_from_six_bits(raw[5:0]);
            configure_status_and_sp(status, 8'hFD);
            return_pc = debug_pc;
            set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
            memory_model.memory[NMI_HANDLER] = 8'h40; // RTI
            synchronize_nmi(1'b1);
            trace_count = 0;
            service_interrupt();
            assert (debug_pc == NMI_HANDLER && debug_sp == 8'hFA &&
                    debug_status.interrupt_disable)
                else $fatal(1, "NMI entry state mismatch");
            check_hardware_interrupt_trace(8'hFD, return_pc, status,
                                           CPU_VECTOR_NMI_LOW);
            trace_count = 0;
            execute_current_instruction(1'b1, rti_steps);
            assert (rti_steps == 6 && debug_pc == return_pc &&
                    debug_sp == 8'hFD &&
                    debug_status == cpu_status_normalize(status))
                else $fatal(1, "NMI/RTI status round trip failed");
            assert (trace_count == 6)
                else $fatal(1, "RTI trace length mismatch");
            check_trace_read(0, NMI_HANDLER);
            check_trace_read(1, NMI_HANDLER + 16'd1);
            check_trace_read(2, 16'h01FA);
            check_trace_read(3, 16'h01FB);
            check_trace_read(4, 16'h01FC);
            check_trace_read(5, 16'h01FD);
            directed_vector_count++;
        end
    endtask

    task automatic test_sp_boundaries;
        logic [7:0] sp;
        logic [15:0] return_pc;
        for (int unsigned index = 0; index < SP_VECTOR_COUNT; index++) begin
            sp = STACK_POINTERS[index];
            reset_core(PROGRAM_START);
            configure_status_and_sp(8'h69, sp);
            return_pc = debug_pc;
            set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
            synchronize_nmi(1'b1);
            trace_count = 0;
            service_interrupt();
            assert (debug_sp == sp - 8'd3)
                else $fatal(1, "interrupt SP wrap mismatch");
            check_hardware_interrupt_trace(sp, return_pc, 8'h69,
                                           CPU_VECTOR_NMI_LOW);
            directed_vector_count++;
        end
    endtask

    task automatic test_irq_mask_and_priority;
        logic [15:0] return_pc;
        int unsigned rti_steps;

        // A synchronized level IRQ remains masked while I=1.
        reset_core(PROGRAM_START);
        synchronize_irq(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_status.interrupt_disable && bus_valid &&
                memory_write_count == 0)
            else $fatal(1, "masked IRQ affected execution");
        directed_vector_count++;

        // With I clear, simultaneous requests choose NMI. The still-asserted
        // IRQ is accepted after RTI restores I=0.
        reset_core(PROGRAM_START);
        configure_status_and_sp(8'h21, 8'hFD);
        return_pc = debug_pc;
        set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
        set_vector(CPU_VECTOR_IRQ_LOW, IRQ_HANDLER);
        memory_model.memory[NMI_HANDLER] = 8'h40;
        synchronize_irq(1'b1);
        synchronize_nmi(1'b1);
        trace_count = 0;
        service_interrupt();
        assert (debug_pc == NMI_HANDLER)
            else $fatal(1, "NMI did not win simultaneous priority");
        check_hardware_interrupt_trace(8'hFD, return_pc, 8'h21,
                                       CPU_VECTOR_NMI_LOW);
        trace_count = 0;
        execute_current_instruction(1'b0, rti_steps);
        assert (rti_steps == 6 && debug_pc == return_pc &&
                !debug_status.interrupt_disable)
            else $fatal(1, "RTI did not restore pre-NMI frame");
        trace_count = 0;
        service_interrupt();
        assert (debug_pc == IRQ_HANDLER)
            else $fatal(1, "pending level IRQ was not accepted after RTI");
        check_hardware_interrupt_trace(8'hFD, return_pc, 8'h21,
                                       CPU_VECTOR_IRQ_LOW);
        directed_vector_count += 2;
    endtask

    task automatic test_nmi_edge_capture;
        logic [15:0] first_return;
        int unsigned rti_steps;
        reset_core(PROGRAM_START);
        configure_status_and_sp(8'h21, 8'hFD);
        set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
        memory_model.memory[NMI_HANDLER] = 8'h40;
        first_return = debug_pc;
        synchronize_nmi(1'b1);
        service_interrupt();
        trace_count = 0;
        execute_current_instruction(1'b0, rti_steps);
        assert (rti_steps == 6 && debug_pc == first_return && bus_valid &&
                !dut.nmi_pending)
            else $fatal(1, "held NMI retriggered or lost return PC");

        // A genuine deassert/reassert transition is a second NMI event.
        synchronize_nmi(1'b0);
        synchronize_nmi(1'b1);
        trace_count = 0;
        service_interrupt();
        assert (debug_pc == NMI_HANDLER)
            else $fatal(1, "second NMI edge was not captured");
        directed_vector_count += 2;
    endtask

    task automatic test_brk_rti;
        logic [7:0] sp;
        logic [15:0] brk_pc;
        logic [15:0] return_pc;
        int unsigned brk_steps;
        int unsigned rti_steps;
        for (int unsigned index = 0; index < SP_VECTOR_COUNT; index++) begin
            sp = STACK_POINTERS[index];
            reset_core(PROGRAM_START);
            configure_status_and_sp(8'h69, sp);
            brk_pc = debug_pc;
            return_pc = brk_pc + 16'd2;
            memory_model.memory[brk_pc] = 8'h00;
            memory_model.memory[brk_pc + 16'd1] = 8'hA5;
            set_vector(CPU_VECTOR_IRQ_LOW, IRQ_HANDLER);
            memory_model.memory[IRQ_HANDLER] = 8'h40;
            trace_count = 0;
            execute_current_instruction(1'b1, brk_steps);
            assert (brk_steps == 7 && debug_pc == IRQ_HANDLER &&
                    debug_sp == sp - 8'd3 && trace_count == 7)
                else $fatal(1, "BRK sequencing mismatch");
            check_trace_read(0, brk_pc);
            check_trace_read(1, brk_pc + 16'd1);
            check_trace_write(2, {8'h01, sp}, return_pc[15:8]);
            check_trace_write(3, {8'h01, sp - 8'd1}, return_pc[7:0]);
            check_trace_write(4, {8'h01, sp - 8'd2},
                              cpu_status_for_php(8'h69));
            check_trace_read(5, CPU_VECTOR_IRQ_LOW);
            check_trace_read(6, CPU_VECTOR_IRQ_LOW + 16'd1);
            trace_count = 0;
            execute_current_instruction(1'b1, rti_steps);
            assert (rti_steps == 6 && debug_pc == return_pc &&
                    debug_sp == sp && debug_status == cpu_status_normalize(8'h69))
                else $fatal(1, "BRK/RTI round trip mismatch");
            directed_vector_count++;
        end
    endtask

    task automatic stall_current_state;
        logic [7:0] held_a;
        logic [7:0] held_x;
        logic [7:0] held_y;
        logic [7:0] held_sp;
        logic [15:0] held_pc;
        logic [7:0] held_status;
        cpu_execution_state_t held_state;
        logic [15:0] held_bus_address;
        logic [7:0] held_bus_data;
        logic held_bus_write;
        logic held_bus_valid;
        logic [31:0] held_write_count;

        held_a = debug_a;
        held_x = debug_x;
        held_y = debug_y;
        held_sp = debug_sp;
        held_pc = debug_pc;
        held_status = debug_status;
        held_state = debug_execution_state;
        held_bus_address = bus_address;
        held_bus_data = bus_write_data;
        held_bus_write = bus_write_enable;
        held_bus_valid = bus_valid;
        held_write_count = memory_write_count;
        cpu_enable = 1'b0;
        repeat (3) begin
            step_cpu(1'b0);
            assert ({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                     debug_status, debug_execution_state, bus_address,
                     bus_write_data, bus_write_enable, bus_valid,
                     memory_write_count} ==
                    {held_a, held_x, held_y, held_sp, held_pc,
                     held_status, held_state, held_bus_address,
                     held_bus_data, held_bus_write, held_bus_valid,
                     held_write_count})
                else $fatal(1,
                    "cpu_enable stall was not stable: state=%0d held_addr=%04h addr=%04h held_we=%0b we=%0b held_valid=%0b valid=%0b held_writes=%0d writes=%0d",
                    held_state, held_bus_address, bus_address,
                    held_bus_write, bus_write_enable,
                    held_bus_valid, bus_valid,
                    held_write_count, memory_write_count);
        end
        cpu_enable = 1'b1;
        stall_check_count++;
    endtask

    task automatic test_interrupt_stalls;
        reset_core(PROGRAM_START);
        stall_current_state(); // FETCH
        configure_status_and_sp(8'h21, 8'hFD);
        set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
        memory_model.memory[NMI_HANDLER] = 8'h40;
        synchronize_nmi(1'b1);
        cpu_enable = 1'b1;
        stall_current_state(); // recognition boundary with pending NMI
        step_cpu(1'b0);
        stall_current_state(); // second discarded interrupt read
        step_cpu(1'b0);
        stall_current_state(); // push high
        step_cpu(1'b0);
        stall_current_state(); // push low
        step_cpu(1'b0);
        stall_current_state(); // push status
        step_cpu(1'b0);
        stall_current_state(); // vector low
        step_cpu(1'b0);
        stall_current_state(); // vector high
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_pc == NMI_HANDLER)
            else $fatal(1, "stalled NMI did not complete");

        trace_count = 0;
        stall_current_state(); // RTI opcode fetch
        step_cpu(1'b0);
        stall_current_state(); // dummy next-PC read
        step_cpu(1'b0);
        stall_current_state(); // dummy current-stack read
        step_cpu(1'b0);
        stall_current_state(); // status pull
        step_cpu(1'b0);
        stall_current_state(); // PC low pull
        step_cpu(1'b0);
        stall_current_state(); // PC high pull
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "stalled RTI did not complete");

        // Exercise both reset-vector bus states under enable stalls.
        reset = 1'b1;
        cpu_enable = 1'b0;
        step_cpu(1'b0);
        reset = 1'b0;
        cpu_enable = 1'b1;
        #1; // Allow reset-qualified combinational bus outputs to settle.
        repeat (7) begin
            stall_current_state();
            step_cpu(1'b0);
        end
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "stalled reset vector did not complete");
    endtask

    task automatic reach_state_and_reset(
        input cpu_execution_state_t target_state,
        input logic [7:0] opcode,
        input logic [7:0] operand_low_value,
        input logic [7:0] operand_high_value
    );
        int unsigned steps;
        logic [7:0] protected_memory;
        reset_core(PROGRAM_START);
        memory_model.memory[PROGRAM_START] = opcode;
        memory_model.memory[PROGRAM_START + 16'd1] = operand_low_value;
        memory_model.memory[PROGRAM_START + 16'd2] = operand_high_value;
        memory_model.memory[16'h2000] = 8'h5A;
        steps = 0;
        while (debug_execution_state != target_state) begin
            step_cpu(1'b0);
            steps++;
            assert (steps < 16)
                else $fatal(1, "failed to reach reset-priority state");
        end
        protected_memory = memory_model.memory[16'h2000];
        reset = 1'b1;
        #1;
        assert (!bus_valid && !bus_write_enable)
            else $fatal(1, "reset did not immediately suppress bus activity");
        @(posedge clk);
        #1;
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_pc == CPU_RESET_PC && debug_sp == CPU_RESET_SP &&
                debug_status == CPU_RESET_STATUS &&
                !bus_valid && !bus_write_enable &&
                memory_model.memory[16'h2000] == protected_memory)
            else $fatal(1, "reset priority recovery mismatch");
        reset = 1'b0;
        cpu_enable = 1'b0;
        reset_priority_count++;
    endtask

    task automatic test_reset_priority;
        reach_state_and_reset(CPU_STATE_FETCH, 8'h02, 8'h00, 8'h00);
        reach_state_and_reset(CPU_STATE_OPERAND_LOW, 8'hA9, 8'h01, 8'h00);
        reach_state_and_reset(CPU_STATE_MEMORY_READ, 8'hAD, 8'h00, 8'h20);
        reach_state_and_reset(CPU_STATE_MEMORY_WRITE, 8'h8D, 8'h00, 8'h20);
        reach_state_and_reset(CPU_STATE_ALU_EXECUTE, 8'hE8, 8'h00, 8'h00);
        reach_state_and_reset(CPU_STATE_BRANCH_DECIDE, 8'hD0, 8'h01, 8'h00);
        reach_state_and_reset(CPU_STATE_STACK_PUSH, 8'h48, 8'h00, 8'h00);

        reset_core(PROGRAM_START);
        configure_status_and_sp(8'h21, 8'hFD);
        set_vector(CPU_VECTOR_NMI_LOW, NMI_HANDLER);
        synchronize_nmi(1'b1);
        service_interrupt();
        // Start a second distinct NMI and reset during its first push.
        synchronize_nmi(1'b0);
        synchronize_nmi(1'b1);
        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_INTERRUPT_DUMMY)
            else $fatal(1, "failed to enter interrupt state for reset test");
        reset = 1'b1;
        #1;
        assert (!bus_valid && !bus_write_enable)
            else $fatal(1, "reset did not suppress interrupt stack write");
        @(posedge clk);
        #1;
        assert (debug_execution_state == CPU_STATE_RESET &&
                debug_sp == CPU_RESET_SP && memory_write_count == 0)
            else $fatal(1, "reset did not win during interrupt entry");
        reset = 1'b0;
        cpu_enable = 1'b0;
        reset_priority_count++;
    endtask

    task automatic test_unsupported_trap;
        reset_core(PROGRAM_START);
        memory_model.memory[PROGRAM_START] = 8'h02;
        cpu_enable = 1'b1;
        step_cpu(1'b0);
        assert (debug_execution_state == CPU_STATE_TRAP &&
                memory_write_count == 0 && !bus_valid && !bus_write_enable)
            else $fatal(1, "unsupported opcode policy regressed");
        directed_vector_count++;
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2g.fst");
        $dumpvars(0, cpu_phase2g_tb);

        for (int unsigned index = 0; index < 4; index++) begin
            reset_core(RESET_TARGETS[index]);
            assert (debug_pc == RESET_TARGETS[index])
                else $fatal(1, "reset target boundary mismatch");
            directed_vector_count++;
        end

        test_status_space();
        test_sp_boundaries();
        test_irq_mask_and_priority();
        test_nmi_edge_capture();
        test_brk_rti();
        test_interrupt_stalls();
        test_reset_priority();
        test_unsupported_trap();

        assert (directed_vector_count == 86)
            else $fatal(1, "Phase 2G directed vector accounting mismatch: %0d",
                        directed_vector_count);
        assert (stall_check_count == 21)
            else $fatal(1, "Phase 2G stall accounting mismatch: %0d",
                        stall_check_count);
        assert (reset_priority_count == 8)
            else $fatal(1, "Phase 2G reset-priority accounting mismatch: %0d",
                        reset_priority_count);

        $display("PASS: Phase 2G interrupt/reset verification (%0d directed, %0d stalls, %0d reset-priority)",
                 directed_vector_count, stall_check_count,
                 reset_priority_count);
        $finish;
    end
endmodule
