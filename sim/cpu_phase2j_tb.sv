`timescale 1ns/1ps

module cpu_phase2j_tb;
    import cpu_pkg::*;

    localparam logic [15:0] START   = 16'h8000;
    localparam logic [15:0] HANDLER = 16'h9000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic nmi = 1'b0;
    logic irq = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data;
    logic bus_write_enable, bus_valid;
    logic [7:0] debug_a, debug_x, debug_y, debug_sp;
    logic [15:0] debug_pc;
    cpu_status_t debug_status;
    logic [7:0] debug_instruction;
    cpu_execution_state_t debug_execution_state;
    cpu_instruction_t debug_decoded_instruction;
    logic [3:0] debug_addressing_mode;
    logic [15:0] debug_effective_address;
    logic debug_page_cross, debug_page_cross_valid;
    logic [31:0] memory_write_count;
    logic [15:0] last_write_address;
    logic [7:0] last_write_data;

    logic [7:0] decoder_opcode;
    cpu_decode_result_t decoder_result;

    logic [15:0] trace_address [0:15];
    logic trace_write [0:15];
    int unsigned trace_count = 0;
    int unsigned bit_vectors = 0;
    int unsigned flag_vectors = 0;
    int unsigned interrupt_vectors = 0;
    int unsigned decimal_vectors = 0;
    int unsigned policy_vectors = 0;

    cpu_core dut (
        .clk(clk), .reset(reset), .cpu_enable(cpu_enable), .nmi(nmi), .irq(irq),
        .bus_address(bus_address), .bus_write_data(bus_write_data),
        .bus_read_data(bus_read_data), .bus_write_enable(bus_write_enable),
        .bus_valid(bus_valid), .debug_a(debug_a), .debug_x(debug_x),
        .debug_y(debug_y), .debug_sp(debug_sp), .debug_pc(debug_pc),
        .debug_status(debug_status), .debug_instruction(debug_instruction),
        .debug_execution_state(debug_execution_state),
        .debug_decoded_instruction(debug_decoded_instruction),
        .debug_addressing_mode(debug_addressing_mode),
        .debug_effective_address(debug_effective_address),
        .debug_page_cross(debug_page_cross),
        .debug_page_cross_valid(debug_page_cross_valid)
    );

    cpu_decoder decoder_audit (
        .opcode(decoder_opcode), .decoded(decoder_result)
    );

    cpu_test_memory memory_model (
        .clk(clk), .reset(reset), .cpu_enable(cpu_enable),
        .address(bus_address), .write_data(bus_write_data),
        .write_enable(bus_write_enable), .valid(bus_valid),
        .read_data(bus_read_data), .write_count(memory_write_count),
        .last_write_address(last_write_address),
        .last_write_data(last_write_data)
    );

    always #5 clk <= !clk;

    task automatic step_cpu(input logic record_bus);
        @(negedge clk);
        if (record_bus && cpu_enable) begin
            assert (trace_count < 16) else $fatal(1, "Phase 2J trace overflow");
            trace_address[trace_count] = bus_address;
            trace_write[trace_count] = bus_write_enable;
            trace_count++;
        end
        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state, debug_decoded_instruction,
                             debug_addressing_mode, debug_effective_address,
                             debug_page_cross, debug_page_cross_valid,
                             bus_address, bus_write_data, bus_write_enable,
                             bus_valid, bus_read_data, memory_write_count,
                             last_write_address, last_write_data}))
            else $fatal(1, "X/Z in Phase 2J CPU or bus state");
        assert (!bus_write_enable || bus_valid)
            else $fatal(1, "write asserted without valid");
    endtask

    task automatic reset_core(input logic [15:0] target);
        memory_model.memory[CPU_VECTOR_RESET_LOW] = target[7:0];
        memory_model.memory[CPU_VECTOR_RESET_LOW + 16'd1] = target[15:8];
        reset = 1'b1;
        cpu_enable = 1'b0;
        nmi = 1'b0;
        irq = 1'b0;
        step_cpu(1'b0);
        step_cpu(1'b0);
        reset = 1'b0;
        cpu_enable = 1'b1;
        trace_count = 0;
        repeat (7) step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH && debug_pc == target &&
                debug_sp == CPU_POST_RESET_SP && debug_status == CPU_RESET_STATUS &&
                memory_write_count == 0)
            else $fatal(1, "Phase 2J reset mismatch");
        trace_count = 0;
    endtask

    task automatic execute_instruction(output int unsigned cycles);
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "instruction did not start in FETCH");
        cycles = 0;
        trace_count = 0;
        do begin
            step_cpu(1'b1);
            cycles++;
            assert (cycles <= 8) else $fatal(1, "instruction exceeded 8 cycles");
        end while (debug_execution_state != CPU_STATE_FETCH &&
                   debug_execution_state != CPU_STATE_TRAP);
    endtask

    task automatic test_decoder_completion;
        int unsigned valid_count;
        valid_count = 0;
        for (int unsigned opcode = 0; opcode < 256; opcode++) begin
            decoder_opcode = opcode[7:0];
            #1;
            if (decoder_result.valid) valid_count++;
            assert (!$isunknown(decoder_result))
                else $fatal(1, "decoder X/Z opcode=%02h", opcode[7:0]);
        end
        assert (valid_count == 151)
            else $fatal(1, "official decoder count=%0d", valid_count);
        decoder_opcode = 8'h24; #1;
        assert (decoder_result.valid && decoder_result.instruction == CPU_INSTR_BIT &&
                decoder_result.addressing_mode == CPU_ADDR_ZERO_PAGE);
        decoder_opcode = 8'h2C; #1;
        assert (decoder_result.valid && decoder_result.instruction == CPU_INSTR_BIT &&
                decoder_result.addressing_mode == CPU_ADDR_ABSOLUTE);
        decoder_opcode = 8'hEA; #1;
        assert (decoder_result.valid && decoder_result.instruction == CPU_INSTR_NOP);
        decoder_opcode = 8'h02; #1;
        assert (!decoder_result.valid);
        policy_vectors += 256;
    endtask

    task automatic check_bit(input logic [7:0] opcode,
                             input logic [7:0] accumulator,
                             input logic [7:0] operand);
        int unsigned cycles;
        logic [7:0] expected_status;
        memory_model.memory[START] = 8'hA9; // LDA #A
        memory_model.memory[START + 1] = accumulator;
        memory_model.memory[START + 2] = 8'h38; // SEC
        memory_model.memory[START + 3] = 8'hF8; // SED
        memory_model.memory[START + 4] = opcode;
        memory_model.memory[START + 5] = 8'h80;
        memory_model.memory[START + 6] = 8'h20;
        memory_model.memory[16'h0080] = operand;
        memory_model.memory[16'h2080] = operand;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        execute_instruction(cycles);
        expected_status = debug_status;
        expected_status[7] = operand[7];
        expected_status[6] = operand[6];
        expected_status[1] = ((accumulator & operand) == 8'h00);
        execute_instruction(cycles);
        assert (cycles == (opcode == 8'h24 ? 3 : 4) &&
                debug_a == accumulator && debug_x == 8'h00 && debug_y == 8'h00 &&
                debug_status == expected_status &&
                debug_pc == START + (opcode == 8'h24 ? 16'd6 : 16'd7) &&
                memory_write_count == 0)
            else $fatal(1, "BIT mismatch op=%02h A=%02h M=%02h", opcode,
                        accumulator, operand);
        assert (trace_address[cycles-1] ==
                (opcode == 8'h24 ? 16'h0080 : 16'h2080) &&
                !trace_write[cycles-1])
            else $fatal(1, "BIT final read mismatch");
        bit_vectors++;
    endtask

    task automatic test_bit;
        logic [7:0] values [0:5];
        values[0] = 8'h00; values[1] = 8'h01; values[2] = 8'h3F;
        values[3] = 8'h40; values[4] = 8'h80; values[5] = 8'hFF;
        for (int unsigned a_index = 0; a_index < 6; a_index++) begin
            for (int unsigned m_index = 0; m_index < 6; m_index++) begin
                check_bit(8'h24, values[a_index], values[m_index]);
                check_bit(8'h2C, values[a_index], values[m_index]);
            end
        end
    endtask

    task automatic check_implied(input logic [7:0] opcode,
                                 input logic [7:0] raw_status,
                                 input logic [7:0] expected_status);
        int unsigned cycles;
        memory_model.memory[START] = 8'h28; // PLP
        memory_model.memory[START + 1] = opcode;
        memory_model.memory[16'h01FE] = raw_status;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_status == cpu_status_normalize(expected_status) &&
                debug_pc == START + 2 && memory_write_count == 0)
            else $fatal(1, "implied mismatch op=%02h P=%02h got=%02h",
                        opcode, raw_status, debug_status);
        assert (trace_count == 2 && trace_address[0] == START + 16'd1 &&
                trace_address[1] == START + 16'd2 &&
                !trace_write[0] && !trace_write[1])
            else $fatal(1, "implied dummy-read trace mismatch op=%02h", opcode);
        flag_vectors++;
    endtask

    task automatic test_flag_and_nop;
        logic [7:0] raw;
        for (int unsigned status_value = 0; status_value < 256; status_value++) begin
            raw = status_value[7:0];
            check_implied(8'h18, raw, raw & 8'hFE); // CLC
            check_implied(8'h38, raw, raw | 8'h01); // SEC
            check_implied(8'h58, raw, raw & 8'hFB); // CLI
            check_implied(8'h78, raw, raw | 8'h04); // SEI
            check_implied(8'hB8, raw, raw & 8'hBF); // CLV
            check_implied(8'hD8, raw, raw & 8'hF7); // CLD
            check_implied(8'hF8, raw, raw | 8'h08); // SED
            check_implied(8'hEA, raw, raw);         // official NOP
        end
    endtask

    task automatic test_cli_sei_polling;
        int unsigned cycles;
        memory_model.memory[CPU_VECTOR_IRQ_LOW] = HANDLER[7:0];
        memory_model.memory[CPU_VECTOR_IRQ_LOW + 16'd1] = HANDLER[15:8];

        // CLI polls with old I=1: one NOP executes before IRQ is accepted.
        memory_model.memory[START] = 8'h58;
        memory_model.memory[START + 1] = 8'hEA;
        reset_core(START);
        cpu_enable = 1'b0;
        irq = 1'b1;
        repeat (3) step_cpu(1'b0);
        cpu_enable = 1'b1;
        execute_instruction(cycles);
        assert (cycles == 2 && !debug_status.interrupt_disable);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_pc == START + 2);
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER)
            else $fatal(1, "CLI old-I polling mismatch");
        interrupt_vectors++;

        // Clear I and consume the delayed boundary. Assert IRQ only after SEI
        // opcode fetch; old I=0 must still admit the pending IRQ.
        memory_model.memory[START] = 8'h58;
        memory_model.memory[START + 1] = 8'hEA;
        memory_model.memory[START + 2] = 8'h78;
        reset_core(START);
        execute_instruction(cycles);
        execute_instruction(cycles);
        step_cpu(1'b1); // fetch SEI
        assert (debug_execution_state == CPU_STATE_IMPLIED);
        cpu_enable = 1'b0;
        irq = 1'b1;
        repeat (3) step_cpu(1'b0);
        cpu_enable = 1'b1;
        step_cpu(1'b1); // execute SEI
        assert (debug_execution_state == CPU_STATE_FETCH &&
                debug_status.interrupt_disable);
        execute_instruction(cycles);
        assert (cycles == 7 && debug_pc == HANDLER)
            else $fatal(1, "SEI old-I polling mismatch");
        interrupt_vectors++;
    endtask

    task automatic test_sed_cld_binary_arithmetic;
        int unsigned cycles;
        memory_model.memory[START] = 8'hF8; // SED
        memory_model.memory[START + 1] = 8'h18; // CLC
        memory_model.memory[START + 2] = 8'hA9; // LDA #$49
        memory_model.memory[START + 3] = 8'h49;
        memory_model.memory[START + 4] = 8'h69; // ADC #$51 = $9A binary
        memory_model.memory[START + 5] = 8'h51;
        memory_model.memory[START + 6] = 8'h38; // SEC
        memory_model.memory[START + 7] = 8'hE9; // SBC #$01 = $99 binary
        memory_model.memory[START + 8] = 8'h01;
        memory_model.memory[START + 9] = 8'hD8; // CLD
        reset_core(START);
        execute_instruction(cycles);
        assert (cycles == 2 && debug_status.decimal);
        execute_instruction(cycles);
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (debug_a == 8'h9A && debug_status.decimal)
            else $fatal(1, "SED altered ADC binary arithmetic");
        decimal_vectors++;
        execute_instruction(cycles);
        execute_instruction(cycles);
        assert (debug_a == 8'h99 && debug_status.decimal)
            else $fatal(1, "SED altered SBC binary arithmetic");
        decimal_vectors++;
        execute_instruction(cycles);
        assert (!debug_status.decimal);
    endtask

    task automatic test_cpu_enable_stall_and_unofficial_trap;
        logic [15:0] saved_pc;
        logic [7:0] saved_status;
        logic [31:0] saved_writes;
        memory_model.memory[START] = 8'h38; // SEC
        memory_model.memory[START + 1] = 8'h02; // unofficial trap
        reset_core(START);
        step_cpu(1'b1); // fetch SEC
        assert (debug_execution_state == CPU_STATE_IMPLIED);
        saved_pc = debug_pc;
        saved_status = debug_status;
        saved_writes = memory_write_count;
        cpu_enable = 1'b0;
        repeat (5) begin
            step_cpu(1'b0);
            assert (debug_execution_state == CPU_STATE_IMPLIED &&
                    debug_pc == saved_pc && debug_status == saved_status &&
                    memory_write_count == saved_writes && !bus_write_enable);
        end
        cpu_enable = 1'b1;
        step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_FETCH && debug_status.carry);
        step_cpu(1'b1);
        assert (debug_execution_state == CPU_STATE_TRAP &&
                memory_write_count == saved_writes && !bus_write_enable)
            else $fatal(1, "unofficial opcode policy mismatch");
        policy_vectors += 2;
    endtask

    initial begin
        $dumpfile("build/sim/cpu_phase2j.fst");
        $dumpvars(0, cpu_phase2j_tb);
        #1;
        test_decoder_completion();
        test_bit();
        test_flag_and_nop();
        test_cli_sei_polling();
        test_sed_cld_binary_arithmetic();
        test_cpu_enable_stall_and_unofficial_trap();
        assert (bit_vectors == 72 && flag_vectors == 2048 &&
                interrupt_vectors == 2 && decimal_vectors == 2 &&
                policy_vectors == 258)
            else $fatal(1, "Phase 2J vector accounting mismatch");
        $display("PASS: Phase 2J final CPU RTL (72 BIT, 2048 implied/status, 2 interrupt-poll, 2 decimal, 258 policy vectors)");
        $finish;
    end
endmodule
