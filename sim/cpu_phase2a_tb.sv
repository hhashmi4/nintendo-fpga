`timescale 1ns/1ps

module cpu_phase2a_tb;
    import cpu_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic cpu_enable = 1'b0;
    logic [15:0] bus_address;
    logic [7:0] bus_write_data;
    logic [7:0] bus_read_data = 8'h00;
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

    cpu_core dut (
        .clk                   (clk),
        .reset                 (reset),
        .cpu_enable            (cpu_enable),
        .bus_address           (bus_address),
        .bus_write_data        (bus_write_data),
        .bus_read_data         (bus_read_data),
        .bus_write_enable      (bus_write_enable),
        .bus_valid             (bus_valid),
        .debug_a               (debug_a),
        .debug_x               (debug_x),
        .debug_y               (debug_y),
        .debug_sp              (debug_sp),
        .debug_pc              (debug_pc),
        .debug_status          (debug_status),
        .debug_instruction     (debug_instruction),
        .debug_execution_state (debug_execution_state)
    );

    always #10 clk <= !clk;

    task automatic sample_clock;
        @(posedge clk);
        #1;
        assert (!$isunknown({debug_a, debug_x, debug_y, debug_sp, debug_pc,
                             debug_status, debug_instruction,
                             debug_execution_state, bus_address,
                             bus_write_data, bus_write_enable, bus_valid}))
            else $fatal(1, "unknown CPU or bus state after clock edge");
        assert (!bus_write_enable)
            else $fatal(1, "Phase 2A asserted bus_write_enable");
    endtask

    task automatic assert_reset_state;
        assert (debug_a == CPU_RESET_A)
            else $fatal(1, "unexpected A reset value");
        assert (debug_x == CPU_RESET_X)
            else $fatal(1, "unexpected X reset value");
        assert (debug_y == CPU_RESET_Y)
            else $fatal(1, "unexpected Y reset value");
        assert (debug_sp == CPU_RESET_SP)
            else $fatal(1, "unexpected SP reset value");
        assert (debug_pc == CPU_RESET_PC)
            else $fatal(1, "unexpected PC reset value");
        assert (debug_status == CPU_RESET_STATUS)
            else $fatal(1, "unexpected processor-status reset value");
        assert (debug_instruction == CPU_RESET_IR)
            else $fatal(1, "unexpected instruction-register reset value");
        assert (debug_execution_state == CPU_STATE_RESET)
            else $fatal(1, "CPU did not enter reset state");
        assert ({bus_valid, bus_write_enable} == 2'b00)
            else $fatal(1, "bus active during reset state");
        assert (bus_address == CPU_RESET_PC && bus_write_data == 8'h00)
            else $fatal(1, "bus reset outputs are not deterministic");
    endtask

    task automatic assert_architecture_unchanged;
        assert (debug_a == CPU_RESET_A && debug_x == CPU_RESET_X &&
                debug_y == CPU_RESET_Y && debug_sp == CPU_RESET_SP &&
                debug_pc == CPU_RESET_PC &&
                debug_status == CPU_RESET_STATUS)
            else $fatal(1, "architectural register changed in Phase 2A");
    endtask

    initial begin
        assert ($bits(debug_pc) == 16)
            else $fatal(1, "PC is not 16 bits wide");
        assert ($bits(debug_sp) == 8)
            else $fatal(1, "SP is not 8 bits wide");

        $dumpfile("build/sim/cpu_phase2a.fst");
        $dumpvars(0, cpu_phase2a_tb);

        // Combinational bus controls are deterministic as soon as reset is
        // asserted; architectural state becomes valid on the first clock.
        #1;
        assert ({bus_valid, bus_write_enable} == 2'b00)
            else $fatal(1, "bus active before first reset edge");
        assert (bus_address == CPU_RESET_PC && bus_write_data == 8'h00)
            else $fatal(1, "bus unknown before first reset edge");

        sample_clock();
        assert_reset_state();
        repeat (2) begin
            bus_read_data = 8'($urandom);
            sample_clock();
            assert_reset_state();
        end

        // With reset released and cpu_enable low, even the reset-state to
        // fetch-state boundary must not be crossed.
        reset = 1'b0;
        repeat (4) begin
            bus_read_data = 8'($urandom);
            sample_clock();
            assert_reset_state();
        end

        // The first enable enters FETCH but does not sample a byte because no
        // valid read cycle existed before this edge.
        cpu_enable = 1'b1;
        bus_read_data = 8'hA9;
        sample_clock();
        assert (debug_execution_state == CPU_STATE_FETCH)
            else $fatal(1, "CPU did not enter fetch state on enable");
        assert (debug_instruction == CPU_RESET_IR)
            else $fatal(1, "instruction sampled before a valid fetch cycle");
        assert (bus_valid && !bus_write_enable)
            else $fatal(1, "fetch placeholder is not a read cycle");
        assert_architecture_unchanged();

        // Read data and all state must hold while the clock enable is low.
        cpu_enable = 1'b0;
        bus_read_data = 8'h5A;
        repeat (5) begin
            sample_clock();
            assert (debug_execution_state == CPU_STATE_FETCH)
                else $fatal(1, "execution state changed without cpu_enable");
            assert (debug_instruction == CPU_RESET_IR)
                else $fatal(1, "instruction register changed without cpu_enable");
            assert (bus_valid && bus_address == CPU_RESET_PC)
                else $fatal(1, "fetch bus outputs changed while stalled");
            assert_architecture_unchanged();
        end

        // A valid fetch byte is sampled only on an enabled edge. PC remains a
        // 16-bit placeholder and deliberately does not increment in Phase 2A.
        cpu_enable = 1'b1;
        sample_clock();
        assert (debug_instruction == 8'h5A)
            else $fatal(1, "fetch byte was not sampled on cpu_enable");
        assert (debug_pc == 16'h0000)
            else $fatal(1, "Phase 2A unexpectedly advanced PC");

        bus_read_data = 8'hC3;
        sample_clock();
        assert (debug_instruction == 8'hC3)
            else $fatal(1, "second fetch byte was not sampled");
        assert_architecture_unchanged();

        // Reassert synchronous platform reset with cpu_enable high. Reset must
        // win, restore every field, and remove bus_valid deterministically.
        #7 reset = 1'b1;
        #1;
        assert (!bus_valid && !bus_write_enable)
            else $fatal(1, "bus did not become inactive on reset assertion");
        sample_clock();
        assert_reset_state();

        // Releasing reset again must reproduce the same enable-gated startup.
        reset = 1'b0;
        cpu_enable = 1'b0;
        repeat (3) begin
            sample_clock();
            assert_reset_state();
        end
        cpu_enable = 1'b1;
        sample_clock();
        assert (debug_execution_state == CPU_STATE_FETCH && bus_valid)
            else $fatal(1, "repeated reset produced different startup state");
        assert_architecture_unchanged();

        $display("PASS: Phase 2A CPU reset, enable gating, scaffold, and bus");
        $finish;
    end
endmodule
