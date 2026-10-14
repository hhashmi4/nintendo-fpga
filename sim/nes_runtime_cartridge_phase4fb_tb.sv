`timescale 1ns/1ps

module nes_runtime_cartridge_phase4fb_tb;
    logic unused_phase7a_mapper_irq_0;
    logic [1:0] unused_phase7a_mapper_mirroring_1;
    import nes_runtime_loader_pkg::*;

    localparam integer EXPECTED_VECTORS = 12021;
    localparam integer EXPECTED_VECTOR_LOADER_WRITES = 5953;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic command_valid = 1'b0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [LOADER_ADDRESS_BITS-1:0] command_address = 16'h0000;
    logic [7:0] command_data = 8'h00;
    logic command_ready;
    logic command_accepted;
    logic manifest_valid = 1'b0;
    logic [7:0] manifest_mapper = 8'h00;
    logic [15:0] manifest_prg_bytes = 16'h0000;
    logic [15:0] manifest_chr_bytes = 16'h0000;
    logic manifest_chr_is_ram = 1'b0;
    logic [1:0] manifest_mirroring = LOADER_MIRROR_VERTICAL;

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
    logic nes_hold_reset;
    /* verilator lint_off UNUSEDSIGNAL */
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
    /* verilator lint_on UNUSEDSIGNAL */

    logic [14:0] debug_prg_address;
    logic [7:0] debug_prg_data;
    logic [12:0] debug_chr_address;
    logic [7:0] debug_chr_data;
    logic debug_prg_read;
    logic debug_prg_write;
    logic debug_chr_read;
    logic debug_chr_write;

    integer directed_checks = 0;
    integer mismatches = 0;
    integer accepted_loader_writes = 0;
    integer vector_count = 0;
    integer vector_reads = 0;
    integer vector_loader_writes = 0;
    integer vector_ppu_writes = 0;

    nes_runtime_cartridge #(
        .IMAGE_VALIDATION_ENABLE(1'b0),
        .ACTIVATION_ENABLE      (1'b0)
    ) dut (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .mapper_irq(unused_phase7a_mapper_irq_0),
        .mapper_mirroring(unused_phase7a_mapper_mirroring_1),
        .*
    );

    always #5 clk <= ~clk;

    always_ff @(posedge clk) begin
        if (!reset && command_accepted && command == LOADER_COMMAND_WRITE)
            accepted_loader_writes <= accepted_loader_writes + 1;
    end

    task automatic check_bit(
        input logic actual,
        input logic expected,
        input string description
    );
        begin
            directed_checks = directed_checks + 1;
            if (actual !== expected) begin
                mismatches = mismatches + 1;
                $error("%s: actual=%b expected=%b", description,
                       actual, expected);
            end
        end
    endtask

    task automatic check_byte(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input string description
    );
        begin
            directed_checks = directed_checks + 1;
            if (actual !== expected) begin
                mismatches = mismatches + 1;
                $error("%s: actual=%02x expected=%02x", description,
                       actual, expected);
            end
        end
    endtask

    task automatic check_state(
        input loader_state_t expected,
        input string description
    );
        begin
            directed_checks = directed_checks + 1;
            if (loader_state !== expected) begin
                mismatches = mismatches + 1;
                $error("%s: state=%0d expected=%0d", description,
                       loader_state, expected);
            end
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
                check_bit(command_accepted, 1'b0,
                          "stalled command must not be accepted");
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            check_bit(command_accepted, 1'b1, "command handshake");
            @(negedge clk);
            command_valid = 1'b0;
            command = LOADER_COMMAND_BEGIN;
            command_target = LOADER_TARGET_NONE;
            command_address = 16'h0000;
            command_data = 8'h00;
        end
    endtask

    task automatic begin_load;
        begin
            send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            check_state(LOADER_STATE_LOADING, "BEGIN enters LOADING");
            check_bit(loader_busy, 1'b1, "loader busy during load");
            check_bit(nes_hold_reset, 1'b1, "NES hold remains asserted");
        end
    endtask

    task automatic commit_load;
        begin
            send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            check_state(LOADER_STATE_READY, "COMMIT enters READY");
            check_bit(loader_completed, 1'b1, "completion indication");
            check_bit(nes_hold_reset, 1'b0, "READY releases hold request");
        end
    endtask

    task automatic loader_write_byte(
        input loader_target_t target,
        input logic [15:0] address,
        input logic [7:0] data
    );
        begin
            send_command(LOADER_COMMAND_WRITE, target, address, data);
        end
    endtask

    task automatic read_cpu_byte(
        input logic [15:0] address,
        input logic mode_256,
        input logic [7:0] expected,
        input string description
    );
        begin
            @(negedge clk);
            nrom_256 = mode_256;
            cpu_address = address;
            cpu_read = 1'b1;
            cpu_write = 1'b0;
            @(posedge clk);
            #1;
            check_byte(cpu_read_data, expected, description);
            check_byte(debug_prg_data, expected, "debug PRG data follows CPU");
            check_bit(debug_prg_read, 1'b1, "debug PRG read strobe");
            check_bit(debug_prg_address ==
                      (mode_256 ? address[14:0] :
                       {1'b0, address[13:0]}),
                      1'b1, "debug PRG mapped address");
            @(negedge clk);
            cpu_read = 1'b0;
        end
    endtask

    task automatic read_chr_byte(
        input logic [12:0] address,
        input logic [7:0] expected,
        input string description
    );
        begin
            @(negedge clk);
            chr_address = address;
            chr_read = 1'b1;
            chr_write = 1'b0;
            @(posedge clk);
            #1;
            check_byte(chr_read_data, expected, description);
            check_byte(debug_chr_data, expected, "debug CHR data follows PPU");
            check_bit(debug_chr_read, 1'b1, "debug CHR read strobe");
            check_bit(debug_chr_address == address, 1'b1,
                      "debug CHR address");
            @(negedge clk);
            chr_read = 1'b0;
        end
    endtask

    task automatic ppu_write_byte(
        input logic [12:0] address,
        input logic [7:0] data,
        input logic ram_mode
    );
        begin
            @(negedge clk);
            chr_is_ram = ram_mode;
            chr_address = address;
            chr_read = 1'b0;
            chr_write = 1'b1;
            chr_write_data = data;
            @(posedge clk);
            #1;
            check_bit(debug_chr_write, 1'b1, "debug CHR write strobe");
            @(negedge clk);
            chr_write = 1'b0;
        end
    endtask

    task automatic loader_prg_read_collision(
        input logic [14:0] address,
        input logic [7:0] data
    );
        begin
            @(negedge clk);
            nrom_256 = 1'b1;
            cpu_address = {1'b1, address};
            cpu_read = 1'b1;
            command_valid = 1'b1;
            command = LOADER_COMMAND_WRITE;
            command_target = LOADER_TARGET_PRG;
            command_address = {1'b0, address};
            command_data = data;
            check_bit(command_ready, 1'b1, "PRG collision write ready");
            @(posedge clk);
            #1;
            check_bit(command_accepted, 1'b1,
                      "PRG collision write accepted");
            check_byte(cpu_read_data, data, "PRG collision is write-first");
            @(negedge clk);
            command_valid = 1'b0;
            cpu_read = 1'b0;
        end
    endtask

    task automatic loader_chr_read_collision(
        input logic [12:0] address,
        input logic [7:0] data
    );
        begin
            @(negedge clk);
            chr_address = address;
            chr_read = 1'b1;
            command_valid = 1'b1;
            command = LOADER_COMMAND_WRITE;
            command_target = LOADER_TARGET_CHR;
            command_address = {3'b000, address};
            command_data = data;
            check_bit(command_ready, 1'b1, "CHR collision write ready");
            @(posedge clk);
            #1;
            check_bit(command_accepted, 1'b1,
                      "CHR collision write accepted");
            check_byte(chr_read_data, data, "CHR collision is write-first");
            @(negedge clk);
            command_valid = 1'b0;
            chr_read = 1'b0;
        end
    endtask

    task automatic run_model_vectors;
        integer vector_file;
        integer scan_result;
        integer operation;
        logic vector_nrom_256;
        logic vector_chr_is_ram;
        logic [15:0] vector_address;
        logic [7:0] vector_data;
        logic [7:0] vector_expected;
        begin
            vector_file = $fopen(
                "build/sim/runtime_cartridge_reference.txt", "r"
            );
            if (vector_file == 0)
                $fatal(1, "cannot open Phase 4F-B reference vectors");

            while (!$feof(vector_file)) begin
                scan_result = $fscanf(
                    vector_file, "%d %d %d %h %h %h\n",
                    operation, vector_nrom_256, vector_chr_is_ram,
                    vector_address, vector_data, vector_expected
                );
                if (scan_result == 6) begin
                    vector_count = vector_count + 1;
                    case (operation)
                        0: begin
                            loader_write_byte(LOADER_TARGET_PRG,
                                              vector_address, vector_data);
                            vector_loader_writes =
                                vector_loader_writes + 1;
                        end
                        1: begin
                            loader_write_byte(LOADER_TARGET_CHR,
                                              vector_address, vector_data);
                            vector_loader_writes =
                                vector_loader_writes + 1;
                        end
                        2: begin
                            read_cpu_byte(vector_address,
                                          vector_nrom_256,
                                          vector_expected,
                                          "model CPU read");
                            vector_reads = vector_reads + 1;
                        end
                        3: begin
                            read_chr_byte(vector_address[12:0],
                                          vector_expected,
                                          "model CHR read");
                            vector_reads = vector_reads + 1;
                        end
                        4: begin
                            ppu_write_byte(vector_address[12:0], vector_data,
                                           vector_chr_is_ram);
                            vector_ppu_writes = vector_ppu_writes + 1;
                        end
                        default: $fatal(1, "bad Phase 4F-B vector opcode");
                    endcase
                end else if (!$feof(vector_file)) begin
                    $fatal(1, "malformed Phase 4F-B reference vector");
                end
            end
            $fclose(vector_file);
        end
    endtask

    integer sequence_index;
    integer writes_before_cancel;

    initial begin
        $dumpfile("build/sim/nes_runtime_cartridge_phase4fb.fst");
        $dumpvars(0, nes_runtime_cartridge_phase4fb_tb);

        repeat (3) @(posedge clk);
        #1;
        check_state(LOADER_STATE_IDLE, "reset loader state");
        check_bit(command_ready, 1'b0, "reset blocks command handshake");
        check_bit(nes_hold_reset, 1'b1, "reset requests NES hold");
        check_byte(cpu_read_data, 8'h00, "reset masks PRG output");
        check_byte(chr_read_data, 8'h00, "reset masks CHR output");
        check_bit(debug_prg_write, 1'b0, "reset masks PRG write debug");

        @(negedge clk);
        reset = 1'b0;
        begin_load();
        run_model_vectors();
        commit_load();

        check_bit(vector_count == EXPECTED_VECTORS, 1'b1,
                  "randomized vector count");
        check_bit(vector_loader_writes == EXPECTED_VECTOR_LOADER_WRITES,
                  1'b1, "randomized loader write count");

        // Directed PRG boundaries, sequential ordering, and overwrite.
        begin_load();
        loader_write_byte(LOADER_TARGET_PRG, 16'h0000, 8'hA9);
        loader_write_byte(LOADER_TARGET_PRG, 16'h0001, 8'h42);
        loader_write_byte(LOADER_TARGET_PRG, 16'h3FFF, 8'h3F);
        loader_write_byte(LOADER_TARGET_PRG, 16'h4000, 8'h40);
        loader_write_byte(LOADER_TARGET_PRG, 16'h7FFF, 8'hFF);
        read_cpu_byte(16'h8000, 1'b0, 8'hA9, "NROM-128 first byte");
        read_cpu_byte(16'hC000, 1'b0, 8'hA9, "NROM-128 first mirror");
        read_cpu_byte(16'hBFFF, 1'b0, 8'h3F, "NROM-128 final byte");
        read_cpu_byte(16'hFFFF, 1'b0, 8'h3F, "NROM-128 final mirror");
        read_cpu_byte(16'h8000, 1'b1, 8'hA9, "NROM-256 lower first");
        read_cpu_byte(16'hC000, 1'b1, 8'h40, "NROM-256 midpoint");
        read_cpu_byte(16'hFFFF, 1'b1, 8'hFF, "NROM-256 final byte");

        for (sequence_index = 0; sequence_index < 64;
             sequence_index = sequence_index + 1)
            loader_write_byte(LOADER_TARGET_PRG,
                              16'h0200 + 16'(sequence_index),
                              8'h80 + 8'(sequence_index));
        for (sequence_index = 0; sequence_index < 64;
             sequence_index = sequence_index + 1)
            read_cpu_byte(16'h8200 + 16'(sequence_index), 1'b1,
                          8'h80 + 8'(sequence_index),
                          "sequential PRG byte");
        loader_write_byte(LOADER_TARGET_PRG, 16'h0200, 8'h5A);
        read_cpu_byte(16'h8200, 1'b1, 8'h5A, "PRG overwrite");

        // CHR boundaries, overwrite, and PRG/CHR isolation.
        loader_write_byte(LOADER_TARGET_CHR, 16'h0000, 8'h10);
        loader_write_byte(LOADER_TARGET_CHR, 16'h1000, 8'h20);
        loader_write_byte(LOADER_TARGET_CHR, 16'h1FFF, 8'h30);
        read_chr_byte(13'h0000, 8'h10, "CHR first byte");
        read_chr_byte(13'h1000, 8'h20, "CHR middle byte");
        read_chr_byte(13'h1FFF, 8'h30, "CHR final byte");
        loader_write_byte(LOADER_TARGET_CHR, 16'h1000, 8'h21);
        read_chr_byte(13'h1000, 8'h21, "CHR overwrite");

        loader_write_byte(LOADER_TARGET_PRG, 16'h0420, 8'h55);
        loader_write_byte(LOADER_TARGET_CHR, 16'h0420, 8'hAA);
        loader_write_byte(LOADER_TARGET_PRG, 16'h0420, 8'h56);
        read_cpu_byte(16'h8420, 1'b1, 8'h56, "PRG isolation");
        read_chr_byte(13'h0420, 8'hAA, "CHR isolation");

        // Preserve existing Mapper-0 CHR-ROM/CHR-RAM semantics.
        ppu_write_byte(13'h0420, 8'h11, 1'b0);
        read_chr_byte(13'h0420, 8'hAA, "CHR-ROM ignores PPU write");
        ppu_write_byte(13'h0420, 8'h22, 1'b1);
        read_chr_byte(13'h0420, 8'h22, "CHR-RAM accepts PPU write");

        loader_prg_read_collision(15'h1234, 8'hC3);
        loader_chr_read_collision(13'h0777, 8'h3C);
        commit_load();

        // Reset cancels an unaccepted write, masks reads, and retains bytes
        // that were accepted before reset without clearing the block RAMs.
        begin_load();
        loader_write_byte(LOADER_TARGET_PRG, 16'h2222, 8'h5A);
        writes_before_cancel = accepted_loader_writes;
        @(negedge clk);
        command_valid = 1'b1;
        command = LOADER_COMMAND_WRITE;
        command_target = LOADER_TARGET_PRG;
        command_address = 16'h2222;
        command_data = 8'hA5;
        reset = 1'b1;
        repeat (2) begin
            @(posedge clk);
            #1;
            check_bit(command_ready, 1'b0, "reset backpressure");
            check_bit(command_accepted, 1'b0, "reset cancels write");
            check_byte(cpu_read_data, 8'h00, "reset masks retained PRG");
            check_byte(chr_read_data, 8'h00, "reset masks retained CHR");
        end
        check_bit(accepted_loader_writes == writes_before_cancel, 1'b1,
                  "cancelled write not counted");
        @(negedge clk);
        command_valid = 1'b0;
        reset = 1'b0;
        @(posedge clk);
        #1;
        check_state(LOADER_STATE_IDLE, "reset returns loader to IDLE");
        read_cpu_byte(16'hA222, 1'b1, 8'h5A,
                      "reset retains accepted PRG byte");
        read_chr_byte(13'h0777, 8'h3C,
                      "reset retains accepted CHR byte");

        begin_load();
        loader_write_byte(LOADER_TARGET_CHR, 16'h1FFE, 8'h6D);
        commit_load();
        read_chr_byte(13'h1FFE, 8'h6D, "post-reset loader recovery");

        check_bit(loader_error, 1'b0, "no loader protocol error");
        check_bit(loader_error_code == LOADER_ERROR_NONE, 1'b1,
                  "no loader error code");
        if (mismatches != 0)
            $fatal(1, "Phase 4F-B mismatches=%0d", mismatches);

        $display("PASS: Phase 4F-B runtime cartridge storage/Mapper-0");
        $display("vectors=%0d loader_writes=%0d ppu_writes=%0d reads=%0d mismatches=%0d",
                 vector_count, vector_loader_writes, vector_ppu_writes,
                 vector_reads, mismatches);
        $display("accepted_loader_writes=%0d directed_checks=%0d NROM-128/NROM-256/CHR/reset/collision",
                 accepted_loader_writes, directed_checks);
        $finish;
    end
endmodule
