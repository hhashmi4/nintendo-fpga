`timescale 1ns/1ps

module nes_runtime_loader_mmio_phase4ff_tb;
    import nes_runtime_loader_pkg::*;
    import nes_runtime_loader_mmio_pkg::*;

    logic source_clk = 1'b0;
    logic destination_clk = 1'b0;
    logic source_reset = 1'b1;
    logic destination_reset = 1'b1;

    logic [5:0] avs_address = 6'd0;
    logic avs_read = 1'b0;
    logic avs_write = 1'b0;
    logic [31:0] avs_writedata = 32'd0;
    logic [3:0] avs_byteenable = 4'hf;
    logic avs_waitrequest;
    logic [31:0] avs_readdata;
    logic avs_readdatavalid;

    logic source_valid;
    loader_command_t source_command;
    loader_target_t source_target;
    logic [15:0] source_address;
    logic [7:0] source_data;
    logic source_manifest_valid;
    logic [7:0] source_manifest_mapper;
    logic [15:0] source_manifest_prg_bytes;
    logic [15:0] source_manifest_chr_bytes;
    logic source_manifest_chr_is_ram;
    logic [1:0] source_manifest_mirroring;
    logic source_ready, source_busy, source_done;
    loader_state_t source_response_state;
    logic source_response_error;
    loader_error_t source_response_error_code;
    loader_state_t source_status_state;
    logic source_status_busy, source_status_ready;
    logic source_status_image_valid, source_status_runtime_active;
    logic source_status_nes_hold_reset, source_status_error;
    loader_error_t source_status_error_code;
    logic source_status_activation_in_progress;

    logic destination_valid;
    loader_command_t destination_command;
    loader_target_t destination_target;
    logic [15:0] destination_address;
    logic [7:0] destination_data;
    logic destination_manifest_valid;
    logic [7:0] destination_manifest_mapper;
    logic [15:0] destination_manifest_prg_bytes;
    logic [15:0] destination_manifest_chr_bytes;
    logic destination_manifest_chr_is_ram;
    logic [1:0] destination_manifest_mirroring;
    logic loader_command_ready, loader_command_accepted;
    logic storage_write_valid;
    loader_target_t storage_write_target;
    logic [15:0] storage_write_address;
    logic [7:0] storage_write_data;
    logic storage_write_ready = 1'b1;
    loader_state_t loader_state;
    logic loader_busy, loader_completed, loader_error;
    loader_error_t loader_error_code;
    logic loader_nes_hold_reset, loader_image_valid;
    logic [7:0] loader_image_mapper;
    logic [15:0] loader_image_prg_bytes, loader_image_chr_bytes;
    logic loader_image_chr_is_ram;
    logic [1:0] loader_image_mirroring;
    logic activation_accepted;
    logic runtime_active;
    logic activation_in_progress;
    logic [2:0] activation_countdown;

    integer accepted_commands = 0;
    integer accepted_writes = 0;
    integer directed_checks = 0;

    always #7 source_clk = !source_clk;
    always #11 destination_clk = !destination_clk;

    nes_runtime_loader_mmio mmio (
        .clk(source_clk),
        .reset(source_reset),
        .avs_address(avs_address),
        .avs_read(avs_read),
        .avs_write(avs_write),
        .avs_writedata(avs_writedata),
        .avs_byteenable(avs_byteenable),
        .avs_waitrequest(avs_waitrequest),
        .avs_readdata(avs_readdata),
        .avs_readdatavalid(avs_readdatavalid),
        .command_submit(source_valid),
        .command(source_command),
        .command_target(source_target),
        .command_address(source_address),
        .command_data(source_data),
        .manifest_valid(source_manifest_valid),
        .manifest_mapper(source_manifest_mapper),
        .manifest_prg_bytes(source_manifest_prg_bytes),
        .manifest_chr_bytes(source_manifest_chr_bytes),
        .manifest_chr_is_ram(source_manifest_chr_is_ram),
        .manifest_mirroring(source_manifest_mirroring),
        .command_channel_ready(source_ready),
        .command_channel_busy(source_busy),
        .command_done(source_done),
        .command_response_state(source_response_state),
        .command_response_error(source_response_error),
        .command_response_error_code(source_response_error_code),
        .status_loader_state(source_status_state),
        .status_loader_busy(source_status_busy),
        .status_loader_ready(source_status_ready),
        .status_image_valid(source_status_image_valid),
        .status_runtime_active(source_status_runtime_active),
        .status_nes_hold_reset(source_status_nes_hold_reset),
        .status_loader_error(source_status_error),
        .status_activation_in_progress(
            source_status_activation_in_progress)
    );

    nes_runtime_loader_cdc cdc (
        .source_clk(source_clk),
        .source_reset(source_reset),
        .source_valid(source_valid),
        .source_command(source_command),
        .source_target(source_target),
        .source_address(source_address),
        .source_data(source_data),
        .source_manifest_valid(source_manifest_valid),
        .source_manifest_mapper(source_manifest_mapper),
        .source_manifest_prg_bytes(source_manifest_prg_bytes),
        .source_manifest_chr_bytes(source_manifest_chr_bytes),
        .source_manifest_chr_is_ram(source_manifest_chr_is_ram),
        .source_manifest_mirroring(source_manifest_mirroring),
        .source_ready(source_ready),
        .source_busy(source_busy),
        .source_done(source_done),
        .source_response_state(source_response_state),
        .source_response_error(source_response_error),
        .source_response_error_code(source_response_error_code),
        .source_status_state(source_status_state),
        .source_status_busy(source_status_busy),
        .source_status_ready(source_status_ready),
        .source_status_image_valid(source_status_image_valid),
        .source_status_runtime_active(source_status_runtime_active),
        .source_status_nes_hold_reset(source_status_nes_hold_reset),
        .source_status_error(source_status_error),
        .source_status_error_code(source_status_error_code),
        .source_status_activation_in_progress(
            source_status_activation_in_progress),
        .destination_clk(destination_clk),
        .destination_reset(destination_reset),
        .destination_valid(destination_valid),
        .destination_command(destination_command),
        .destination_target(destination_target),
        .destination_address(destination_address),
        .destination_data(destination_data),
        .destination_manifest_valid(destination_manifest_valid),
        .destination_manifest_mapper(destination_manifest_mapper),
        .destination_manifest_prg_bytes(destination_manifest_prg_bytes),
        .destination_manifest_chr_bytes(destination_manifest_chr_bytes),
        .destination_manifest_chr_is_ram(destination_manifest_chr_is_ram),
        .destination_manifest_mirroring(destination_manifest_mirroring),
        .destination_command_ready(loader_command_ready),
        .destination_command_accepted(loader_command_accepted),
        .destination_status_state(loader_state),
        .destination_status_busy(loader_busy),
        .destination_status_image_valid(loader_image_valid),
        .destination_status_runtime_active(runtime_active),
        .destination_status_nes_hold_reset(
            loader_nes_hold_reset || activation_in_progress),
        .destination_status_error(loader_error),
        .destination_status_error_code(loader_error_code),
        .destination_status_activation_in_progress(
            activation_in_progress)
    );

    nes_runtime_loader loader (
        .clk(destination_clk),
        .reset(destination_reset),
        .command_valid(destination_valid),
        .command(destination_command),
        .command_target(destination_target),
        .command_address(destination_address),
        .command_data(destination_data),
        .command_ready(loader_command_ready),
        .command_accepted(loader_command_accepted),
        .manifest_valid(destination_manifest_valid),
        .manifest_mapper(destination_manifest_mapper),
        .manifest_prg_bytes(destination_manifest_prg_bytes),
        .manifest_chr_bytes(destination_manifest_chr_bytes),
        .manifest_chr_is_ram(destination_manifest_chr_is_ram),
        .manifest_mirroring(destination_manifest_mirroring),
        .storage_write_valid(storage_write_valid),
        .storage_write_target(storage_write_target),
        .storage_write_address(storage_write_address),
        .storage_write_data(storage_write_data),
        .storage_write_ready(storage_write_ready),
        .state(loader_state),
        .busy(loader_busy),
        .completed(loader_completed),
        .error(loader_error),
        .error_code(loader_error_code),
        .nes_hold_reset(loader_nes_hold_reset),
        .image_valid(loader_image_valid),
        .image_mapper(loader_image_mapper),
        .image_prg_bytes(loader_image_prg_bytes),
        .image_chr_bytes(loader_image_chr_bytes),
        .image_chr_is_ram(loader_image_chr_is_ram),
        .image_mirroring(loader_image_mirroring),
        .activation_accepted(activation_accepted)
    );

    always_ff @(posedge destination_clk) begin
        if (destination_reset) begin
            accepted_commands <= 0;
            accepted_writes <= 0;
            runtime_active <= 1'b0;
            activation_in_progress <= 1'b0;
            activation_countdown <= 3'd0;
        end else begin
            if (loader_command_accepted)
                accepted_commands <= accepted_commands + 1;
            if (storage_write_valid && storage_write_ready) begin
                accepted_writes <= accepted_writes + 1;
                assert (storage_write_target == LOADER_TARGET_PRG);
                assert (storage_write_address[15:8] == 8'h00 ||
                        storage_write_address[15:8] < 8'h40);
                assert (storage_write_data == storage_write_address[7:0]);
            end
            if (activation_accepted) begin
                runtime_active <= 1'b1;
                activation_in_progress <= 1'b1;
                activation_countdown <= 3'd4;
            end else if (activation_in_progress) begin
                if (activation_countdown == 3'd1) begin
                    activation_in_progress <= 1'b0;
                    activation_countdown <= 3'd0;
                end else begin
                    activation_countdown <= activation_countdown - 3'd1;
                end
            end
        end
    end

    task automatic av_write(input logic [5:0] address,
                            input logic [31:0] data);
        @(negedge source_clk);
        avs_address = address;
        avs_writedata = data;
        avs_byteenable = 4'hf;
        avs_write = 1'b1;
        @(negedge source_clk);
        assert (!avs_waitrequest);
        avs_write = 1'b0;
        avs_address = 6'd0;
        avs_writedata = 32'd0;
    endtask

    task automatic av_read(input logic [5:0] address,
                           output logic [31:0] data);
        @(negedge source_clk);
        avs_address = address;
        avs_read = 1'b1;
        @(negedge source_clk);
        assert (!avs_waitrequest);
        data = avs_readdata;
        assert (avs_readdatavalid);
        avs_read = 1'b0;
        avs_address = 6'd0;
    endtask

    task automatic wait_status(input integer bit_index,
                               input logic expected);
        logic [31:0] value;
        for (integer poll = 0; poll < 1000; poll++) begin
            av_read(MMIO_REG_STATUS, value);
            if (value[bit_index] == expected)
                return;
        end
        $fatal(1, "status bit %0d did not become %0d", bit_index, expected);
    endtask

    task automatic stage_command(input loader_target_t target,
                                 input logic [15:0] address,
                                 input logic [7:0] data);
        av_write(MMIO_REG_TARGET, {30'd0, target});
        av_write(MMIO_REG_ADDRESS, {16'd0, address});
        av_write(MMIO_REG_WRITE_DATA, {24'd0, data});
    endtask

    task automatic issue_command(input loader_command_t requested_command);
        logic [31:0] before_count;
        logic [31:0] count;
        logic [31:0] status;
        wait_status(MMIO_STATUS_BRIDGE_READY_BIT, 1'b1);
        av_read(MMIO_REG_COMPLETED_COUNT, before_count);
        av_write(MMIO_REG_COMMAND, {30'd0, requested_command});
        for (integer poll = 0; poll < 1000; poll++) begin
            av_read(MMIO_REG_STATUS, status);
            av_read(MMIO_REG_COMPLETED_COUNT, count);
            if (count != before_count &&
                !status[MMIO_STATUS_COMMAND_PENDING_BIT])
                return;
        end
        $fatal(1, "command %0d did not complete", requested_command);
    endtask

    initial begin
        logic [31:0] value;
        logic [31:0] before_count;
        logic [31:0] count;
        integer full_load_commands;

        $dumpfile("build/sim/nes_runtime_loader_mmio_phase4ff.fst");
        $dumpvars(0, nes_runtime_loader_mmio_phase4ff_tb);
        #200;
        @(negedge source_clk);
        source_reset = 1'b0;
        @(negedge destination_clk);
        destination_reset = 1'b0;

        av_read(MMIO_REG_MAGIC, value);
        assert (value == MMIO_MAGIC);
        av_read(MMIO_REG_VERSION, value);
        assert (value == MMIO_VERSION);
        av_read(MMIO_REG_CAPABILITIES, value);
        assert (value == MMIO_CAPABILITIES);
        av_read(6'h3c, value);
        assert (value == 32'd0);
        directed_checks += 4;

        // Explicit manifest encoding: valid, CHR-RAM, horizontal, Mapper 0.
        av_write(MMIO_REG_MANIFEST,
            (32'd1 << MMIO_MANIFEST_VALID_SHIFT) |
            (32'd1 << MMIO_MANIFEST_CHR_IS_RAM_SHIFT) |
            (32'(LOADER_MIRROR_HORIZONTAL) <<
             MMIO_MANIFEST_MIRRORING_SHIFT));
        av_write(MMIO_REG_MANIFEST_PRG_BYTES,
                 {16'd0, LOADER_PRG_NROM128_BYTES});
        av_write(MMIO_REG_MANIFEST_CHR_BYTES, 32'd0);
        stage_command(LOADER_TARGET_NONE, 16'd0, 8'd0);
        issue_command(LOADER_COMMAND_BEGIN);
        assert (loader_state == LOADER_STATE_LOADING);
        assert (loader_image_prg_bytes == LOADER_PRG_NROM128_BYTES);
        assert (loader_image_chr_is_ram);
        av_read(MMIO_REG_ERROR, value);
        assert (!value[MMIO_ERROR_RESPONSE_FAILED_BIT]);
        assert (value[MMIO_ERROR_STATE_SHIFT +: 2] ==
                LOADER_STATE_LOADING);
        directed_checks += 5;

        // Hold the first write behind downstream backpressure. Reads cannot
        // duplicate it, and a second COMMAND write cannot overwrite it.
        storage_write_ready = 1'b0;
        stage_command(LOADER_TARGET_PRG, 16'd0, 8'h00);
        wait_status(MMIO_STATUS_BRIDGE_READY_BIT, 1'b1);
        av_read(MMIO_REG_COMPLETED_COUNT, before_count);
        av_write(MMIO_REG_COMMAND, {30'd0, LOADER_COMMAND_WRITE});
        wait_status(MMIO_STATUS_COMMAND_PENDING_BIT, 1'b1);
        repeat (12) begin
            av_read(MMIO_REG_COMMAND, value);
            assert (value == 32'd0);
        end
        av_write(MMIO_REG_COMMAND, {30'd0, LOADER_COMMAND_COMMIT});
        av_read(MMIO_REG_STATUS, value);
        assert (value[MMIO_STATUS_SUBMIT_REJECTED_BIT]);
        assert (accepted_writes == 0);
        av_write(MMIO_REG_CONTROL,
                 32'd1 << MMIO_CONTROL_CLEAR_SUBMIT_REJECTED_BIT);
        storage_write_ready = 1'b1;
        for (integer poll = 0; poll < 1000; poll++) begin
            av_read(MMIO_REG_COMPLETED_COUNT, count);
            if (count != before_count)
                break;
        end
        assert (count == before_count + 32'd1);
        assert (accepted_writes == 1);
        directed_checks += 16;

        for (integer address = 1;
             address < LOADER_PRG_NROM128_BYTES; address++) begin
            stage_command(LOADER_TARGET_PRG, 16'(address), 8'(address));
            issue_command(LOADER_COMMAND_WRITE);
        end
        stage_command(LOADER_TARGET_NONE, 16'd0, 8'd0);
        issue_command(LOADER_COMMAND_COMMIT);
        wait_status(MMIO_STATUS_IMAGE_VALID_BIT, 1'b1);
        assert (accepted_writes == integer'(LOADER_PRG_NROM128_BYTES));
        assert (loader_completed && loader_image_valid);
        assert (loader_image_mapper == 8'd0 &&
                loader_image_chr_bytes == 16'd0 &&
                loader_image_mirroring == LOADER_MIRROR_HORIZONTAL);

        issue_command(LOADER_COMMAND_ACTIVATE);
        wait_status(MMIO_STATUS_RUNTIME_ACTIVE_BIT, 1'b1);
        wait_status(MMIO_STATUS_ACTIVATION_IN_PROGRESS_BIT, 1'b0);
        wait_status(MMIO_STATUS_NES_HELD_RESET_BIT, 1'b0);
        assert (runtime_active);
        full_load_commands = 3 + integer'(LOADER_PRG_NROM128_BYTES);
        assert (accepted_commands == full_load_commands);
        directed_checks += 6;

        // A typed loader failure crosses back in the command response bank.
        stage_command(LOADER_TARGET_PRG, 16'd0, 8'h00);
        issue_command(LOADER_COMMAND_WRITE);
        av_read(MMIO_REG_ERROR, value);
        assert (value[MMIO_ERROR_RESPONSE_FAILED_BIT]);
        assert (value[3:0] == LOADER_ERROR_WRONG_STATE);
        assert (value[MMIO_ERROR_STATE_SHIFT +: 2] == LOADER_STATE_ERROR);
        assert (source_status_error_code == LOADER_ERROR_WRONG_STATE);
        directed_checks += 3;

        // BEGIN is the protocol-defined recovery from a sticky loader error.
        stage_command(LOADER_TARGET_NONE, 16'd0, 8'd0);
        issue_command(LOADER_COMMAND_BEGIN);
        assert (!loader_error && loader_state == LOADER_STATE_LOADING);

        // Reset both sides with a command held behind backpressure. No stale
        // request may fire after independently synchronized clock release.
        storage_write_ready = 1'b0;
        stage_command(LOADER_TARGET_PRG, 16'd0, 8'h00);
        av_write(MMIO_REG_COMMAND, {30'd0, LOADER_COMMAND_WRITE});
        wait_status(MMIO_STATUS_COMMAND_PENDING_BIT, 1'b1);
        source_reset = 1'b1;
        destination_reset = 1'b1;
        #200;
        source_reset = 1'b0;
        destination_reset = 1'b0;
        storage_write_ready = 1'b1;
        repeat (20) @(negedge destination_clk);
        assert (!destination_valid && accepted_commands == 0);
        av_read(MMIO_REG_COMPLETED_COUNT, value);
        assert (value == 32'd0);
        wait_status(MMIO_STATUS_BRIDGE_READY_BIT, 1'b1);
        directed_checks += 4;

        $display("PASS: Phase 4F-F MMIO/CDC full NROM-128 transfer writes=%0d checks=%0d asynchronous clocks/backpressure/exactly-once/status/reset",
                 LOADER_PRG_NROM128_BYTES, directed_checks);
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "Phase 4F-F MMIO/CDC timeout");
    end
endmodule
