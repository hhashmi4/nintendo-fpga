`timescale 1ns/1ps

module nes_runtime_image_phase4fc_tb;
    import nes_runtime_loader_pkg::*;

    localparam integer PRG_NROM128_COUNT =
        integer'(LOADER_PRG_NROM128_BYTES);
    localparam integer PRG_NROM256_COUNT =
        integer'(LOADER_PRG_NROM256_BYTES);
    localparam integer CHR_ROM_COUNT = integer'(LOADER_CHR_ROM_BYTES);

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic command_valid = 1'b0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [LOADER_ADDRESS_BITS-1:0] command_address = 16'h0000;
    logic [7:0] command_data = 8'h00;
    logic command_ready;
    logic command_accepted;

    logic manifest_valid = 1'b1;
    logic [7:0] manifest_mapper = 8'd0;
    logic [15:0] manifest_prg_bytes = LOADER_PRG_NROM128_BYTES;
    logic [15:0] manifest_chr_bytes = LOADER_CHR_ROM_BYTES;
    logic manifest_chr_is_ram = 1'b0;
    logic [1:0] manifest_mirroring = LOADER_MIRROR_HORIZONTAL;

    logic nrom_256 = 1'b0;
    logic chr_is_ram = 1'b0;
    logic [15:0] cpu_address = 16'h8000;
    logic cpu_read = 1'b0;
    logic cpu_write = 1'b0;
    logic [7:0] cpu_write_data = 8'h00;
    logic [7:0] cpu_read_data;
    logic [12:0] chr_address = 13'h0000;
    logic chr_read = 1'b0;
    logic chr_write = 1'b0;
    logic [7:0] chr_write_data = 8'h00;
    logic [7:0] chr_read_data;

    loader_state_t loader_state;
    logic loader_busy;
    logic loader_completed;
    logic loader_error;
    loader_error_t loader_error_code;
    /* verilator lint_off UNUSEDSIGNAL */
    logic nes_hold_reset;
    logic image_valid;
    logic [7:0] image_mapper;
    logic [15:0] image_prg_bytes;
    logic [15:0] image_chr_bytes;
    logic image_chr_is_ram;
    logic [1:0] image_mirroring;
    logic activation_accepted;
    logic activation_in_progress;
    logic activation_error;
    logic runtime_active;
    logic [7:0] active_mapper;
    logic [15:0] active_prg_bytes;
    logic [15:0] active_chr_bytes;
    logic active_chr_is_ram;
    logic [1:0] active_mirroring;

    logic [14:0] debug_prg_address;
    logic [7:0] debug_prg_data;
    logic [12:0] debug_chr_address;
    logic [7:0] debug_chr_data;
    logic debug_prg_read;
    logic debug_prg_write;
    logic debug_chr_read;
    logic debug_chr_write;
    /* verilator lint_on UNUSEDSIGNAL */

    integer checks = 0;
    integer accepted_storage_writes = 0;
    integer successful_images = 0;

    // A second loader proves that Phase 4F-C coverage advances only on the
    // downstream ready/valid handshake. The composition below supplies the
    // end-to-end manifest -> storage -> Mapper-0 proof.
    logic bp_reset = 1'b1;
    logic bp_command_valid = 1'b0;
    loader_command_t bp_command = LOADER_COMMAND_BEGIN;
    loader_target_t bp_command_target = LOADER_TARGET_NONE;
    logic [15:0] bp_command_address = 16'h0000;
    logic [7:0] bp_command_data = 8'h00;
    logic bp_command_ready;
    logic bp_command_accepted;
    logic bp_storage_write_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    loader_target_t bp_storage_write_target;
    logic [15:0] bp_storage_write_address;
    logic [7:0] bp_storage_write_data;
    logic bp_storage_write_ready = 1'b0;
    loader_state_t bp_state;
    logic bp_busy;
    logic bp_completed;
    logic bp_error;
    loader_error_t bp_error_code;
    logic bp_nes_hold_reset;
    logic bp_image_valid;
    logic [7:0] bp_image_mapper;
    logic [15:0] bp_image_prg_bytes;
    logic [15:0] bp_image_chr_bytes;
    logic bp_image_chr_is_ram;
    logic [1:0] bp_image_mirroring;
    logic bp_activation_accepted;
    /* verilator lint_on UNUSEDSIGNAL */

    always #5 clk <= !clk;

    nes_runtime_cartridge #(
        .ACTIVATION_ENABLE(1'b0)
    ) dut (.*);

    nes_runtime_loader backpressure_dut (
        .clk                  (clk),
        .reset                (bp_reset),
        .command_valid        (bp_command_valid),
        .command              (bp_command),
        .command_target       (bp_command_target),
        .command_address      (bp_command_address),
        .command_data         (bp_command_data),
        .command_ready        (bp_command_ready),
        .command_accepted     (bp_command_accepted),
        .manifest_valid       (1'b1),
        .manifest_mapper      (8'd0),
        .manifest_prg_bytes   (LOADER_PRG_NROM128_BYTES),
        .manifest_chr_bytes   (16'h0000),
        .manifest_chr_is_ram  (1'b1),
        .manifest_mirroring   (LOADER_MIRROR_HORIZONTAL),
        .storage_write_valid  (bp_storage_write_valid),
        .storage_write_target (bp_storage_write_target),
        .storage_write_address(bp_storage_write_address),
        .storage_write_data   (bp_storage_write_data),
        .storage_write_ready  (bp_storage_write_ready),
        .state                (bp_state),
        .busy                 (bp_busy),
        .completed            (bp_completed),
        .error                (bp_error),
        .error_code           (bp_error_code),
        .nes_hold_reset       (bp_nes_hold_reset),
        .image_valid          (bp_image_valid),
        .image_mapper         (bp_image_mapper),
        .image_prg_bytes      (bp_image_prg_bytes),
        .image_chr_bytes      (bp_image_chr_bytes),
        .image_chr_is_ram     (bp_image_chr_is_ram),
        .image_mirroring      (bp_image_mirroring),
        .activation_accepted  (bp_activation_accepted)
    );

    always_ff @(posedge clk) begin
        if (!reset && dut.storage_write_valid && dut.storage_write_ready)
            accepted_storage_writes <= accepted_storage_writes + 1;
    end

    function automatic logic [7:0] prg_pattern(input logic [15:0] address);
        prg_pattern = address[7:0] ^ address[15:8] ^ 8'ha5;
    endfunction

    function automatic logic [7:0] chr_pattern(input logic [15:0] address);
        chr_pattern = address[7:0] + address[15:8] + 8'h3c;
    endfunction

    task automatic check(input logic condition, input string description);
        begin
            checks = checks + 1;
            assert (condition) else $fatal(1, "check failed: %s", description);
        end
    endtask

    task automatic send_command(
        input loader_command_t requested_command,
        input loader_target_t requested_target,
        input logic [15:0] requested_address,
        input logic [7:0] requested_data
    );
        begin
            @(negedge clk);
            command_valid = 1'b1;
            command = requested_command;
            command_target = requested_target;
            command_address = requested_address;
            command_data = requested_data;
            while (!command_ready) begin
                @(posedge clk);
                #1;
                check(!command_accepted, "backpressured command not accepted");
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            check(command_accepted, "command accepted");
            @(negedge clk);
            command_valid = 1'b0;
            command = LOADER_COMMAND_BEGIN;
            command_target = LOADER_TARGET_NONE;
            command_address = 16'h0000;
            command_data = 8'h00;
        end
    endtask

    task automatic set_manifest(
        input logic valid_value,
        input logic [7:0] mapper_value,
        input logic [15:0] prg_bytes_value,
        input logic [15:0] chr_bytes_value,
        input logic chr_ram_value,
        input logic [1:0] mirroring_value
    );
        begin
            manifest_valid = valid_value;
            manifest_mapper = mapper_value;
            manifest_prg_bytes = prg_bytes_value;
            manifest_chr_bytes = chr_bytes_value;
            manifest_chr_is_ram = chr_ram_value;
            manifest_mirroring = mirroring_value;
        end
    endtask

    task automatic begin_image;
        begin
            send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            check(loader_state == LOADER_STATE_LOADING,
                   "valid BEGIN enters LOADING");
            check(loader_busy && !image_valid,
                   "new session is busy and invalid");
        end
    endtask

    task automatic expect_error(
        input loader_error_t expected_error,
        input string description
    );
        begin
            check(loader_state == LOADER_STATE_ERROR, description);
            check(loader_error && loader_error_code == expected_error,
                   "typed first error");
            check(!image_valid, "error cannot leave IMAGE_VALID asserted");
        end
    endtask

    task automatic write_byte(
        input loader_target_t target,
        input logic [15:0] address,
        input logic [7:0] data
    );
        send_command(LOADER_COMMAND_WRITE, target, address, data);
    endtask

    task automatic write_prg(input integer byte_count);
        begin
            for (integer address = 0; address < byte_count; address++)
                write_byte(LOADER_TARGET_PRG, 16'(address),
                           prg_pattern(16'(address)));
        end
    endtask

    task automatic write_chr(input integer byte_count);
        begin
            for (integer address = 0; address < byte_count; address++)
                write_byte(LOADER_TARGET_CHR, 16'(address),
                           chr_pattern(16'(address)));
        end
    endtask

    task automatic commit_image;
        begin
            send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            check(loader_state == LOADER_STATE_READY,
                   "complete COMMIT enters READY");
            check(loader_completed && image_valid,
                   "complete COMMIT asserts IMAGE_VALID");
            successful_images = successful_images + 1;
        end
    endtask

    task automatic read_prg(
        input logic [15:0] address,
        input logic [7:0] expected
    );
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_read = 1'b1;
            @(posedge clk);
            #1;
            check(cpu_read_data == expected, "Mapper-0 PRG readback");
            @(negedge clk);
            cpu_read = 1'b0;
        end
    endtask

    task automatic read_chr(
        input logic [12:0] address,
        input logic [7:0] expected
    );
        begin
            @(negedge clk);
            chr_address = address;
            chr_read = 1'b1;
            @(posedge clk);
            #1;
            check(chr_read_data == expected, "Mapper-0 CHR readback");
            @(negedge clk);
            chr_read = 1'b0;
        end
    endtask

    initial begin
        integer writes_before_error;

        $dumpfile("build/sim/nes_runtime_image_phase4fc.fst");
        $dumpvars(0, nes_runtime_image_phase4fc_tb);

        repeat (3) @(posedge clk);
        #1;
        check(loader_state == LOADER_STATE_IDLE, "reset state is IDLE");
        check(!image_valid && !command_ready, "reset invalidates image");
        check(image_prg_bytes == 0 && image_chr_bytes == 0,
               "reset clears staged manifest status");
        @(negedge clk);
        reset = 1'b0;

        // Manifest validation and deterministic error precedence.
        set_manifest(1'b0, 8'd0, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0,
                     LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_INVALID_MANIFEST, "missing manifest");

        set_manifest(1'b1, 8'd1, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0,
                     LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_UNSUPPORTED_MAPPER, "unsupported mapper");

        set_manifest(1'b1, 8'd0, 16'h2000, LOADER_CHR_ROM_BYTES,
                     1'b0, LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_UNSUPPORTED_PRG, "invalid PRG size");

        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES, 16'h1000,
                     1'b0, LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_UNSUPPORTED_CHR, "invalid CHR size");

        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b1,
                     LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_UNSUPPORTED_CHR,
                     "contradictory CHR metadata");

        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0, 2'd2);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_INVALID_MANIFEST,
                     "reserved mirroring value");

        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0,
                     LOADER_MIRROR_VERTICAL);
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_PRG,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_INVALID_MANIFEST,
                     "reserved BEGIN payload");

        // Gaps and duplicates are accepted as commands but never written.
        begin_image();
        writes_before_error = accepted_storage_writes;
        write_byte(LOADER_TARGET_PRG, 16'h0001, 8'h11);
        expect_error(LOADER_ERROR_UNEXPECTED_ADDRESS,
                     "out-of-order PRG address");
        check(accepted_storage_writes == writes_before_error,
               "out-of-order byte does not reach storage");

        begin_image();
        write_byte(LOADER_TARGET_PRG, 16'h0000, 8'h22);
        writes_before_error = accepted_storage_writes;
        write_byte(LOADER_TARGET_PRG, 16'h0000, 8'h33);
        expect_error(LOADER_ERROR_UNEXPECTED_ADDRESS,
                     "duplicate PRG address");
        check(accepted_storage_writes == writes_before_error,
               "duplicate byte does not reach storage");

        begin_image();
        write_byte(LOADER_TARGET_PRG, LOADER_PRG_NROM128_BYTES, 8'h44);
        expect_error(LOADER_ERROR_BAD_ADDRESS,
                     "declared NROM-128 boundary enforced");

        begin_image();
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_PRG_INCOMPLETE, "early empty COMMIT");

        // Exactly one PRG byte short must fail even for CHR-RAM.
        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES, 16'h0000,
                     1'b1, LOADER_MIRROR_HORIZONTAL);
        begin_image();
        write_prg(PRG_NROM128_COUNT - 1);
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_PRG_INCOMPLETE, "one-byte-short PRG");

        // Exactly one CHR byte short distinguishes CHR completeness.
        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0,
                     LOADER_MIRROR_HORIZONTAL);
        begin_image();
        write_prg(PRG_NROM128_COUNT);
        write_chr(CHR_ROM_COUNT - 1);
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_CHR_INCOMPLETE, "one-byte-short CHR");

        // Complete NROM-128 + CHR-ROM transfer and real Mapper-0 readback.
        begin_image();
        write_prg(PRG_NROM128_COUNT);
        write_chr(CHR_ROM_COUNT);
        commit_image();
        nrom_256 = 1'b0;
        chr_is_ram = 1'b0;
        read_prg(16'h8000, prg_pattern(16'h0000));
        read_prg(16'hbfff, prg_pattern(16'h3fff));
        read_prg(16'hc000, prg_pattern(16'h0000));
        read_prg(16'hffff, prg_pattern(16'h3fff));
        read_chr(13'h0000, chr_pattern(16'h0000));
        read_chr(13'h1fff, chr_pattern(16'h1fff));
        check(image_mapper == 0 &&
               image_prg_bytes == LOADER_PRG_NROM128_BYTES &&
               image_chr_bytes == LOADER_CHR_ROM_BYTES &&
               !image_chr_is_ram &&
               image_mirroring == LOADER_MIRROR_HORIZONTAL,
               "validated manifest status is retained");

        // A replacement BEGIN invalidates the old result and coverage.
        begin_image();
        check(!image_valid, "new BEGIN clears previous IMAGE_VALID");
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        expect_error(LOADER_ERROR_PRG_INCOMPLETE,
                     "old coverage cannot leak into replacement session");

        // Reset drops a partial session without clearing payload RAM.
        begin_image();
        write_byte(LOADER_TARGET_PRG, 16'h0000, 8'h5a);
        @(negedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        check(loader_state == LOADER_STATE_IDLE && !image_valid,
               "reset cancels partial session");
        check(image_prg_bytes == 0 && image_chr_bytes == 0,
               "reset clears logical manifest state");
        @(negedge clk);
        reset = 1'b0;

        // ERROR -> fresh BEGIN -> complete CHR-RAM image.
        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM128_BYTES, 16'h0000,
                     1'b1, LOADER_MIRROR_VERTICAL);
        begin_image();
        writes_before_error = accepted_storage_writes;
        write_byte(LOADER_TARGET_CHR, 16'h0000, 8'h66);
        expect_error(LOADER_ERROR_BAD_TARGET,
                     "CHR-RAM rejects ROM payload");
        check(accepted_storage_writes == writes_before_error,
               "CHR-RAM payload does not reach storage");
        begin_image();
        write_prg(PRG_NROM128_COUNT);
        commit_image();
        chr_is_ram = 1'b1;
        @(negedge clk);
        chr_address = 13'h1fff;
        chr_write_data = 8'hc7;
        chr_write = 1'b1;
        @(posedge clk);
        @(negedge clk);
        chr_write = 1'b0;
        read_chr(13'h1fff, 8'hc7);

        // Complete NROM-256 proves both 16 KiB halves and exact boundaries.
        set_manifest(1'b1, 8'd0, LOADER_PRG_NROM256_BYTES,
                     LOADER_CHR_ROM_BYTES, 1'b0,
                     LOADER_MIRROR_HORIZONTAL);
        begin_image();
        write_prg(PRG_NROM256_COUNT);
        write_chr(CHR_ROM_COUNT);
        commit_image();
        nrom_256 = 1'b1;
        chr_is_ram = 1'b0;
        read_prg(16'h8000, prg_pattern(16'h0000));
        read_prg(16'hbfff, prg_pattern(16'h3fff));
        read_prg(16'hc000, prg_pattern(16'h4000));
        read_prg(16'hffff, prg_pattern(16'h7fff));
        read_chr(13'h1fff, chr_pattern(16'h1fff));

        // Backpressure holds address zero stable and cannot create coverage.
        @(negedge clk);
        bp_reset = 1'b0;
        bp_command_valid = 1'b1;
        bp_command = LOADER_COMMAND_BEGIN;
        bp_storage_write_ready = 1'b0;
        @(posedge clk);
        #1;
        check(bp_command_accepted && bp_state == LOADER_STATE_LOADING,
               "backpressure loader accepts BEGIN");
        @(negedge clk);
        bp_command = LOADER_COMMAND_WRITE;
        bp_command_target = LOADER_TARGET_PRG;
        bp_command_address = 16'h0000;
        bp_command_data = 8'hd1;
        repeat (5) begin
            #1;
            check(bp_storage_write_valid && !bp_command_ready &&
                   !bp_command_accepted,
                   "valid first byte remains stalled");
            @(posedge clk);
            @(negedge clk);
        end
        bp_storage_write_ready = 1'b1;
        #1;
        check(bp_command_ready && bp_command_accepted,
               "stalled byte accepts exactly when storage is ready");
        @(posedge clk);
        @(negedge clk);
        bp_command_valid = 1'b0;
        bp_storage_write_ready = 1'b0;
        bp_command = LOADER_COMMAND_COMMIT;
        bp_command_target = LOADER_TARGET_NONE;
        bp_command_address = 16'h0000;
        bp_command_data = 8'h00;
        bp_command_valid = 1'b1;
        @(posedge clk);
        #1;
        check(bp_state == LOADER_STATE_ERROR &&
               bp_error_code == LOADER_ERROR_PRG_INCOMPLETE,
               "one accepted backpressured byte is still incomplete");

        check(successful_images == 3, "three supported images validated");
        $display("PASS: Phase 4F-C manifest and complete-transfer validation");
        $display("checks=%0d storage_writes=%0d images=%0d NROM-128/NROM-256/CHR-ROM/CHR-RAM/backpressure",
                 checks, accepted_storage_writes, successful_images);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Phase 4F-C runtime-image timeout");
    end
endmodule
