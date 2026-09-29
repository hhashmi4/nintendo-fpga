`timescale 1ns/1ps

module nes_runtime_loader_phase4fa_tb;
    import nes_runtime_loader_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic command_valid = 1'b0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [LOADER_ADDRESS_BITS-1:0] command_address = '0;
    logic [7:0] command_data = 8'h00;
    logic command_ready;
    logic command_accepted;
    logic storage_write_valid;
    loader_target_t storage_write_target;
    logic [LOADER_ADDRESS_BITS-1:0] storage_write_address;
    logic [7:0] storage_write_data;
    logic storage_write_ready = 1'b0;
    loader_state_t state;
    logic busy;
    logic completed;
    logic error;
    loader_error_t error_code;
    logic nes_hold_reset;

    loader_target_t observed_target [0:255];
    logic [LOADER_ADDRESS_BITS-1:0] observed_address [0:255];
    logic [7:0] observed_data [0:255];
    integer observed_writes = 0;
    integer directed_checks = 0;

    integer vector_file;
    integer scan_result;
    integer vector_rows = 0;
    logic vector_reset;
    logic vector_valid;
    logic [1:0] vector_command;
    logic [1:0] vector_target;
    logic [15:0] vector_address;
    logic [7:0] vector_data;
    logic vector_storage_ready;
    logic expected_command_ready;
    logic expected_command_accepted;
    logic expected_write_valid;
    logic [1:0] expected_write_target;
    logic [15:0] expected_write_address;
    logic [7:0] expected_write_data;
    logic [1:0] expected_state;
    logic expected_busy;
    logic expected_completed;
    logic expected_error;
    logic [2:0] expected_error_code;
    logic expected_hold;

    always #5 clk <= !clk;

    nes_runtime_loader dut (.*);

    always_ff @(posedge clk) begin
        if (storage_write_valid && storage_write_ready && !reset) begin
            assert (observed_writes < 256);
            observed_target[observed_writes] <= storage_write_target;
            observed_address[observed_writes] <= storage_write_address;
            observed_data[observed_writes] <= storage_write_data;
            observed_writes <= observed_writes + 1;
        end
    end

    task automatic check_idle_reset;
        begin
            #1;
            assert (state == LOADER_STATE_IDLE);
            assert (!busy && !completed && !error);
            assert (error_code == LOADER_ERROR_NONE);
            assert (nes_hold_reset);
            assert (!command_ready && !command_accepted);
            assert (!storage_write_valid);
            directed_checks++;
        end
    endtask

    task automatic reset_loader;
        begin
            @(negedge clk);
            reset = 1'b1;
            command_valid = 1'b0;
            storage_write_ready = 1'b0;
            @(posedge clk);
            check_idle_reset();
            @(negedge clk);
            reset = 1'b0;
            #1;
            assert (state == LOADER_STATE_IDLE && nes_hold_reset);
        end
    endtask

    task automatic issue_command(
        input loader_command_t requested_command,
        input loader_target_t requested_target,
        input logic [15:0] requested_address,
        input logic [7:0] requested_data
    );
        begin
            @(negedge clk);
            command = requested_command;
            command_target = requested_target;
            command_address = requested_address;
            command_data = requested_data;
            storage_write_ready = 1'b1;
            command_valid = 1'b1;
            #1;
            assert (command_ready && command_accepted)
                else $fatal(1, "command was not accepted command=%0d", requested_command);
            @(posedge clk);
            #1;
            @(negedge clk);
            command_valid = 1'b0;
            storage_write_ready = 1'b0;
            #1;
            directed_checks++;
        end
    endtask

    task automatic begin_load;
        begin
            issue_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                          16'h0000, 8'h00);
            assert (state == LOADER_STATE_LOADING && busy);
            assert (!completed && !error && nes_hold_reset);
        end
    endtask

    task automatic check_error(input loader_error_t expected);
        begin
            assert (state == LOADER_STATE_ERROR && error);
            assert (error_code == expected);
            assert (!busy && !completed && nes_hold_reset);
            assert (!storage_write_valid);
            directed_checks++;
        end
    endtask

    task automatic run_model_vectors;
        begin
            vector_file = $fopen("build/sim/runtime_loader_reference.txt", "r");
            assert (vector_file != 0)
                else $fatal(1, "could not open runtime-loader vectors");

            while (!$feof(vector_file)) begin
                scan_result = $fscanf(vector_file,
                    "%d %d %d %d %x %x %d %d %d %d %d %x %x %d %d %d %d %d %d\n",
                    vector_reset, vector_valid, vector_command, vector_target,
                    vector_address, vector_data, vector_storage_ready,
                    expected_command_ready, expected_command_accepted,
                    expected_write_valid, expected_write_target,
                    expected_write_address, expected_write_data,
                    expected_state, expected_busy, expected_completed,
                    expected_error, expected_error_code, expected_hold);
                if (scan_result == 19) begin
                    @(negedge clk);
                    reset = vector_reset;
                    command_valid = vector_valid;
                    command = loader_command_t'(vector_command);
                    command_target = loader_target_t'(vector_target);
                    command_address = vector_address;
                    command_data = vector_data;
                    storage_write_ready = vector_storage_ready;
                    #1;
                    assert (command_ready == expected_command_ready);
                    assert (command_accepted == expected_command_accepted);
                    assert (storage_write_valid == expected_write_valid);
                    assert (storage_write_target ==
                            loader_target_t'(expected_write_target));
                    assert (storage_write_address == expected_write_address);
                    assert (storage_write_data == expected_write_data);
                    assert (state == loader_state_t'(expected_state));
                    assert (busy == expected_busy);
                    assert (completed == expected_completed);
                    assert (error == expected_error);
                    assert (error_code == loader_error_t'(expected_error_code));
                    assert (nes_hold_reset == expected_hold);
                    @(posedge clk);
                    #1;
                    vector_rows++;
                end
            end
            $fclose(vector_file);
            assert (vector_rows == 4096)
                else $fatal(1, "runtime-loader vector count=%0d", vector_rows);
            @(negedge clk);
            reset = 1'b0;
            command_valid = 1'b0;
            storage_write_ready = 1'b0;
        end
    endtask

    initial begin
        integer first_write;

        $dumpfile("build/sim/nes_runtime_loader_phase4fa.fst");
        $dumpvars(0, nes_runtime_loader_phase4fa_tb);

        repeat (2) @(posedge clk);
        check_idle_reset();
        @(negedge clk);
        reset = 1'b0;

        // Write and COMMIT while idle are rejected without a storage write.
        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                      16'h0000, 8'h11);
        check_error(LOADER_ERROR_WRONG_STATE);
        assert (observed_writes == 0);

        reset_loader();
        issue_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        check_error(LOADER_ERROR_WRONG_STATE);

        // BEGIN while active fails the session. A fresh BEGIN recovers and
        // clears the latched error without a global reset.
        reset_loader();
        begin_load();
        issue_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        check_error(LOADER_ERROR_BEGIN_BUSY);
        issue_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        check_error(LOADER_ERROR_BEGIN_BUSY);
        begin_load();

        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_RESERVED,
                      16'h0000, 8'h22);
        check_error(LOADER_ERROR_BAD_TARGET);
        begin_load();
        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                      16'h8000, 8'h33);
        check_error(LOADER_ERROR_BAD_ADDRESS);
        begin_load();
        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_CHR,
                      16'h2000, 8'h44);
        check_error(LOADER_ERROR_BAD_ADDRESS);
        begin_load();
        issue_command(LOADER_COMMAND_RESERVED, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        check_error(LOADER_ERROR_BAD_COMMAND);
        begin_load();
        issue_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        check_error(LOADER_ERROR_EMPTY_LOAD);
        assert (observed_writes == 0);

        // One PRG and one CHR write prove typed routing and exact payloads.
        begin_load();
        first_write = observed_writes;
        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                      16'h7fff, 8'ha5);
        issue_command(LOADER_COMMAND_WRITE, LOADER_TARGET_CHR,
                      16'h1fff, 8'h5a);
        assert (observed_writes == first_write + 2);
        assert (observed_target[first_write] == LOADER_TARGET_PRG);
        assert (observed_address[first_write] == 16'h7fff);
        assert (observed_data[first_write] == 8'ha5);
        assert (observed_target[first_write + 1] == LOADER_TARGET_CHR);
        assert (observed_address[first_write + 1] == 16'h1fff);
        assert (observed_data[first_write + 1] == 8'h5a);
        issue_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        assert (state == LOADER_STATE_READY && completed);
        assert (!busy && !error && !nes_hold_reset);

        // A new load from READY immediately returns execution to the held
        // loading state and clears completion.
        begin_load();
        first_write = observed_writes;
        for (int index = 0; index < 64; index++) begin
            issue_command(LOADER_COMMAND_WRITE,
                          index[0] ? LOADER_TARGET_CHR : LOADER_TARGET_PRG,
                          index[0] ? 16'(index >> 1) : 16'(16'h4000 + index),
                          8'(index ^ 8'hc3));
        end
        assert (observed_writes == first_write + 64);
        for (int index = 0; index < 64; index++) begin
            assert (observed_target[first_write + index] ==
                    (index[0] ? LOADER_TARGET_CHR : LOADER_TARGET_PRG));
            assert (observed_address[first_write + index] ==
                    (index[0] ? 16'(index >> 1) : 16'(16'h4000 + index)));
            assert (observed_data[first_write + index] == 8'(index ^ 8'hc3));
        end
        issue_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                      16'h0000, 8'h00);
        assert (completed && !nes_hold_reset);

        // Backpressure must preserve one stable write and must not duplicate
        // it when the downstream endpoint finally accepts it.
        begin_load();
        first_write = observed_writes;
        @(negedge clk);
        command = LOADER_COMMAND_WRITE;
        command_target = LOADER_TARGET_PRG;
        command_address = 16'h2345;
        command_data = 8'hde;
        command_valid = 1'b1;
        storage_write_ready = 1'b0;
        repeat (9) begin
            #1;
            assert (storage_write_valid && !command_ready &&
                    !command_accepted);
            assert (storage_write_target == LOADER_TARGET_PRG &&
                    storage_write_address == 16'h2345 &&
                    storage_write_data == 8'hde);
            @(posedge clk);
            @(negedge clk);
        end
        assert (observed_writes == first_write);
        storage_write_ready = 1'b1;
        #1;
        assert (command_ready && command_accepted && storage_write_valid);
        @(posedge clk);
        #1;
        assert (observed_writes == first_write + 1);
        @(negedge clk);
        command_valid = 1'b0;
        storage_write_ready = 1'b0;
        assert (observed_target[first_write] == LOADER_TARGET_PRG &&
                observed_address[first_write] == 16'h2345 &&
                observed_data[first_write] == 8'hde);

        // Reset cancels a backpressured transaction and never reports the
        // partial session as completed or emits a stale write afterward.
        @(negedge clk);
        command_valid = 1'b1;
        command = LOADER_COMMAND_WRITE;
        command_target = LOADER_TARGET_CHR;
        command_address = 16'h0123;
        command_data = 8'h67;
        storage_write_ready = 1'b0;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b1;
        storage_write_ready = 1'b1;
        check_idle_reset();
        @(posedge clk);
        check_idle_reset();
        @(negedge clk);
        command_valid = 1'b0;
        storage_write_ready = 1'b0;
        reset = 1'b0;
        #1;
        assert (state == LOADER_STATE_IDLE && nes_hold_reset);
        assert (observed_writes == first_write + 1);

        run_model_vectors();
        $display("PASS: Phase 4F-A runtime loader directed_checks=%0d vectors=%0d downstream_writes=%0d",
                 directed_checks, vector_rows, observed_writes);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Phase 4F-A runtime-loader timeout");
    end
endmodule
