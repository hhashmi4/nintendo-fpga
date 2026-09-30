`timescale 1ns/1ps

module nes_runtime_activation_phase4fd_tb;
    import nes_runtime_loader_pkg::*;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic functional_reset;
    logic debugger_authorized = 1'b1;

    logic command_valid = 1'b0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [15:0] command_address = 16'h0000;
    logic [7:0] command_data = 8'h00;
    logic command_ready;
    logic command_accepted;
    logic manifest_valid = 1'b1;
    logic [7:0] manifest_mapper = 8'd0;
    logic [15:0] manifest_prg_bytes = LOADER_PRG_NROM128_BYTES;
    logic [15:0] manifest_chr_bytes = LOADER_CHR_ROM_BYTES;
    logic manifest_chr_is_ram = 1'b0;
    logic [1:0] manifest_mirroring = LOADER_MIRROR_HORIZONTAL;

    logic [15:0] cart_cpu_address;
    logic cart_cpu_read;
    logic cart_cpu_write;
    logic [7:0] cart_cpu_write_data;
    logic [7:0] cart_cpu_read_data;
    logic [12:0] core_chr_address;
    logic core_chr_read;
    logic core_chr_write;
    logic [7:0] core_chr_write_data;
    logic [7:0] cart_chr_read_data;
    logic manual_chr_bus = 1'b0;
    logic [12:0] manual_chr_address = 13'h0000;
    logic manual_chr_read = 1'b0;
    logic manual_chr_write = 1'b0;
    logic [7:0] manual_chr_write_data = 8'h00;
    logic [12:0] mux_chr_address;
    logic mux_chr_read;
    logic mux_chr_write;
    logic [7:0] mux_chr_write_data;

    logic cartridge_present;
    logic [7:0] mapper_number;
    logic nrom_256;
    logic chr_is_ram;
    logic [1:0] mirroring_mode;
    loader_state_t loader_state;
    logic loader_busy;
    logic loader_completed;
    logic loader_error;
    loader_error_t loader_error_code;
    logic staged_image_valid;
    logic activation_accepted;
    logic activation_in_progress;
    logic activation_error;
    logic runtime_active;
    logic nes_hold_reset;

    logic ppu_enable;
    logic cpu_enable;
    logic [15:0] cpu_debug_pc;
    logic dma_active;
    logic ppu_nmi_level;
    logic [7:0] ppu_ctrl;
    logic [7:0] ppu_mask;

    integer reset_vector_low_reads = 0;
    integer reset_vector_high_reads = 0;
    integer runtime_chr_reads = 0;
    integer activation_count = 0;
    integer replacement_count = 0;

    assign functional_reset = reset || nes_hold_reset;
    assign mux_chr_address = manual_chr_bus ? manual_chr_address :
                                              core_chr_address;
    assign mux_chr_read = manual_chr_bus ? manual_chr_read : core_chr_read;
    assign mux_chr_write = manual_chr_bus ? manual_chr_write : core_chr_write;
    assign mux_chr_write_data = manual_chr_bus ? manual_chr_write_data :
                                                 core_chr_write_data;

    /* verilator lint_off PINMISSING */
    nes_core nes (
        .clk(clk),
        .reset(functional_reset),
        .nes_enable(debugger_authorized),
        .irq(1'b0),
        .mirroring_mode(mirroring_mode),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_read_data(8'h00),
        .controller_cpu_read_data(8'h00),
        .chr_addr(core_chr_address),
        .chr_read(core_chr_read),
        .chr_write(core_chr_write),
        .chr_write_data(core_chr_write_data),
        .chr_read_data(cart_chr_read_data),
        .ppu_enable(ppu_enable),
        .cpu_enable(cpu_enable),
        .cpu_debug_pc(cpu_debug_pc),
        .dma_active(dma_active),
        .ppu_ctrl(ppu_ctrl),
        .ppu_mask(ppu_mask),
        .ppu_nmi_level(ppu_nmi_level)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_cartridge_runtime_mux #(
        .LEGACY_MAPPER_NUMBER(0),
        .LEGACY_PRG_ROM_BYTES(16384),
        .LEGACY_CHR_IS_RAM(1'b0),
        .LEGACY_PRG_RAM_ENABLE(1'b0),
        .LEGACY_MIRRORING_MODE(LOADER_MIRROR_HORIZONTAL),
        .LEGACY_PRG_INIT_FILE(
            "build/cartridge/phase4b_boot_nrom128.prg.hex"),
        .LEGACY_CHR_INIT_FILE(
            "build/cartridge/phase4b_boot_nrom128.chr.hex"),
        .ACTIVATION_RESET_CYCLES(4)
    ) cartridge (
        .clk(clk),
        .reset(reset),
        .command_valid(command_valid),
        .command(command),
        .command_target(command_target),
        .command_address(command_address),
        .command_data(command_data),
        .command_ready(command_ready),
        .command_accepted(command_accepted),
        .manifest_valid(manifest_valid),
        .manifest_mapper(manifest_mapper),
        .manifest_prg_bytes(manifest_prg_bytes),
        .manifest_chr_bytes(manifest_chr_bytes),
        .manifest_chr_is_ram(manifest_chr_is_ram),
        .manifest_mirroring(manifest_mirroring),
        .cpu_address(cart_cpu_address),
        .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write),
        .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(mux_chr_address),
        .chr_read(mux_chr_read),
        .chr_write(mux_chr_write),
        .chr_write_data(mux_chr_write_data),
        .chr_read_data(cart_chr_read_data),
        .cartridge_present(cartridge_present),
        .mapper_number(mapper_number),
        .nrom_256(nrom_256),
        .chr_is_ram(chr_is_ram),
        .mirroring_mode(mirroring_mode),
        .loader_state(loader_state),
        .loader_busy(loader_busy),
        .loader_completed(loader_completed),
        .loader_error(loader_error),
        .loader_error_code(loader_error_code),
        .staged_image_valid(staged_image_valid),
        .activation_accepted(activation_accepted),
        .activation_in_progress(activation_in_progress),
        .activation_error(activation_error),
        .runtime_active(runtime_active),
        .nes_hold_reset(nes_hold_reset),
        .debug_prg_address(),
        .debug_prg_data(),
        .debug_chr_address(),
        .debug_chr_data(),
        .debug_prg_read(),
        .debug_prg_write(),
        .debug_prg_ram_read(),
        .debug_prg_ram_write(),
        .debug_chr_read(),
        .debug_chr_write()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk <= ~clk;

    function automatic logic [7:0] image_a_prg(input logic [15:0] address);
        begin
            image_a_prg = 8'hea;
            case (address)
                16'h0000: image_a_prg = 8'ha9; // LDA #$42
                16'h0001: image_a_prg = 8'h42;
                16'h0002: image_a_prg = 8'h85; // STA $02
                16'h0003: image_a_prg = 8'h02;
                16'h0004: image_a_prg = 8'ha9; // LDA #$80
                16'h0005: image_a_prg = 8'h80;
                16'h0006: image_a_prg = 8'h8d; // STA $2000
                16'h0007: image_a_prg = 8'h00;
                16'h0008: image_a_prg = 8'h20;
                16'h0009: image_a_prg = 8'ha9; // LDA #$1e
                16'h000a: image_a_prg = 8'h1e;
                16'h000b: image_a_prg = 8'h8d; // STA $2001
                16'h000c: image_a_prg = 8'h01;
                16'h000d: image_a_prg = 8'h20;
                16'h000e: image_a_prg = 8'ha9; // LDA #$02
                16'h000f: image_a_prg = 8'h02;
                16'h0010: image_a_prg = 8'h8d; // STA $4014
                16'h0011: image_a_prg = 8'h14;
                16'h0012: image_a_prg = 8'h40;
                16'h0013: image_a_prg = 8'h4c; // JMP $800e
                16'h0014: image_a_prg = 8'h0e;
                16'h0015: image_a_prg = 8'h80;
                16'h0100: image_a_prg = 8'h40; // RTI
                16'h3ffa: image_a_prg = 8'h00;
                16'h3ffb: image_a_prg = 8'h81;
                16'h3ffc: image_a_prg = 8'h00;
                16'h3ffd: image_a_prg = 8'h80;
                16'h3ffe: image_a_prg = 8'h00;
                16'h3fff: image_a_prg = 8'h81;
                default: begin end
            endcase
        end
    endfunction

    function automatic logic [7:0] image_b_prg(input logic [15:0] address);
        begin
            image_b_prg = address < 16'h4000 ? 8'hea : 8'h55;
            case (address)
                16'h0000: image_b_prg = 8'ha9; // LDA #$99
                16'h0001: image_b_prg = 8'h99;
                16'h0002: image_b_prg = 8'h85; // STA $03
                16'h0003: image_b_prg = 8'h03;
                16'h0004: image_b_prg = 8'h4c; // JMP $8004
                16'h0005: image_b_prg = 8'h04;
                16'h0006: image_b_prg = 8'h80;
                16'h0100: image_b_prg = 8'h40;
                16'h7ffa: image_b_prg = 8'h00;
                16'h7ffb: image_b_prg = 8'h81;
                16'h7ffc: image_b_prg = 8'h00;
                16'h7ffd: image_b_prg = 8'h80;
                16'h7ffe: image_b_prg = 8'h00;
                16'h7fff: image_b_prg = 8'h81;
                default: begin end
            endcase
        end
    endfunction

    function automatic logic [7:0] image_a_chr(input logic [12:0] address);
        image_a_chr = address[7:0] ^ {3'b000, address[12:8]} ^ 8'h5a;
    endfunction

    task automatic send_command(
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
            command_valid = 1'b1;
            while (!command_ready)
                @(negedge clk);
            @(posedge clk);
            #1;
            assert (command_accepted)
                else $fatal(1, "loader command was not accepted");
            @(negedge clk);
            command_valid = 1'b0;
            command_target = LOADER_TARGET_NONE;
            command_address = 16'h0000;
            command_data = 8'h00;
        end
    endtask

    task automatic begin_image(
        input logic [15:0] prg_bytes,
        input logic [15:0] chr_bytes,
        input logic chr_ram,
        input logic [1:0] mirroring
    );
        begin
            manifest_valid = 1'b1;
            manifest_mapper = 8'd0;
            manifest_prg_bytes = prg_bytes;
            manifest_chr_bytes = chr_bytes;
            manifest_chr_is_ram = chr_ram;
            manifest_mirroring = mirroring;
            send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            #1;
            assert (loader_busy && nes_hold_reset && functional_reset);
        end
    endtask

    task automatic activate_and_release;
        integer held_cycles;
        begin
            send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE,
                         16'h0000, 8'h00);
            #1;
            assert (activation_accepted && runtime_active);
            assert (activation_in_progress && nes_hold_reset);
            held_cycles = 0;
            while (activation_in_progress) begin
                @(posedge clk);
                #1;
                held_cycles = held_cycles + 1;
                if (activation_in_progress)
                    assert (!cpu_enable && !ppu_enable);
            end
            assert (held_cycles == 4)
                else $fatal(1, "activation reset lasted %0d cycles",
                            held_cycles);
            assert (!nes_hold_reset && !functional_reset);
            activation_count = activation_count + 1;
        end
    endtask

    task automatic read_chr(
        input logic [12:0] address,
        input logic [7:0] expected
    );
        begin
            debugger_authorized = 1'b0;
            @(posedge clk);
            manual_chr_bus = 1'b1;
            manual_chr_address = address;
            manual_chr_read = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            assert (cart_chr_read_data == expected)
                else $fatal(1, "CHR[%04x] was %02x expected %02x",
                            address, cart_chr_read_data, expected);
            runtime_chr_reads = runtime_chr_reads + 1;
            manual_chr_read = 1'b0;
            manual_chr_bus = 1'b0;
            debugger_authorized = 1'b1;
        end
    endtask

    task automatic write_chr(
        input logic [12:0] address,
        input logic [7:0] data
    );
        begin
            debugger_authorized = 1'b0;
            @(posedge clk);
            manual_chr_bus = 1'b1;
            manual_chr_address = address;
            manual_chr_write_data = data;
            manual_chr_write = 1'b1;
            @(posedge clk);
            manual_chr_write = 1'b0;
            @(posedge clk);
            manual_chr_bus = 1'b0;
            debugger_authorized = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (nes_hold_reset) begin
            assert (!cpu_enable && !ppu_enable)
                else $fatal(1, "debugger authorization bypassed loader hold");
            assert (!cartridge.runtime_cartridge.debug_prg_read);
            assert (!cartridge.runtime_cartridge.debug_chr_read);
        end
        if (!functional_reset && runtime_active && cart_cpu_read) begin
            if (cart_cpu_address == 16'hfffc) begin
                reset_vector_low_reads <= reset_vector_low_reads + 1;
                assert (cart_cpu_read_data == 8'h00)
                    else $fatal(1, "runtime reset-vector low=%02x",
                                cart_cpu_read_data);
            end
            if (cart_cpu_address == 16'hfffd) begin
                reset_vector_high_reads <= reset_vector_high_reads + 1;
                assert (cart_cpu_read_data == 8'h80)
                    else $fatal(1, "runtime reset-vector high=%02x",
                                cart_cpu_read_data);
            end
        end
    end

    initial begin : phase4fd_test
        integer address;
        integer timeout;
        integer vector_low_before;
        integer vector_high_before;
        logic [7:0] chr_original;

        $dumpfile("build/sim/nes_runtime_activation_phase4fd.fst");
        $dumpvars(0, nes_runtime_activation_phase4fd_tb);

        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (20) @(posedge clk);
        assert (!runtime_active && !nes_hold_reset && !functional_reset);
        assert (loader_state == LOADER_STATE_IDLE);
        assert (cartridge_present && mapper_number == 8'd0);
        assert (!nrom_256 && !chr_is_ram &&
                mirroring_mode == LOADER_MIRROR_HORIZONTAL);
        assert (cpu_enable || ppu_enable)
            else $fatal(1, "legacy cartridge mode did not execute");

        // ACTIVATE is explicit and illegal before a staged image is valid.
        send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (loader_error && activation_error);
        assert (loader_error_code == LOADER_ERROR_ACTIVATE_INVALID);
        assert (!runtime_active && !nes_hold_reset);

        // Even a valid manifest remains held if ACTIVATE arrives mid-load.
        begin_image(LOADER_PRG_NROM128_BYTES, LOADER_CHR_ROM_BYTES,
                    1'b0, LOADER_MIRROR_HORIZONTAL);
        send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (activation_error && !runtime_active && nes_hold_reset);

        // A fresh BEGIN recovers and stages NROM-128 + CHR-ROM image A.
        begin_image(LOADER_PRG_NROM128_BYTES, LOADER_CHR_ROM_BYTES,
                    1'b0, LOADER_MIRROR_HORIZONTAL);
        for (address = 0; address < 16'h4000; address = address + 1)
            send_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                         16'(address), image_a_prg(16'(address)));
        for (address = 0; address < 16'h2000; address = address + 1)
            send_command(LOADER_COMMAND_WRITE, LOADER_TARGET_CHR,
                         16'(address), image_a_chr(13'(address)));
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (staged_image_valid && loader_completed);
        assert (!runtime_active && nes_hold_reset);

        vector_low_before = reset_vector_low_reads;
        vector_high_before = reset_vector_high_reads;
        activate_and_release();
        assert (!nrom_256 && !chr_is_ram);
        assert (mirroring_mode == LOADER_MIRROR_HORIZONTAL);
        timeout = 0;
        while ((nes.internal_cpu_ram.memory[11'h002] != 8'h42 ||
                ppu_ctrl != 8'h80 || ppu_mask != 8'h1e ||
                reset_vector_low_reads == vector_low_before ||
                reset_vector_high_reads == vector_high_before) &&
               timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        assert (timeout < 10000)
            else $fatal(1, "NROM-128 runtime boot timed out PC=%04x",
                        cpu_debug_pc);
        assert (nes.internal_cpu_ram.memory[11'h002] == 8'h42);
        assert (ppu_ctrl == 8'h80 && ppu_mask == 8'h1e);

        // Focused PPU cartridge-port proof and CHR-ROM write protection.
        chr_original = image_a_chr(13'h0123);
        read_chr(13'h0123, chr_original);
        write_chr(13'h0123, 8'hc7);
        read_chr(13'h0123, chr_original);

        // Image A repeats DMA. Begin replacement while DMA and a pending
        // vblank NMI are both observable; functional reset clears both.
        timeout = 0;
        while ((!dma_active || !ppu_nmi_level) && timeout < 150000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        assert (timeout < 150000)
            else $fatal(1, "did not reach DMA+NMI replacement point");
        begin_image(LOADER_PRG_NROM256_BYTES, 16'h0000,
                    1'b1, LOADER_MIRROR_VERTICAL);
        repeat (2) @(posedge clk);
        #1;
        assert (!dma_active && !ppu_nmi_level);
        assert (!cpu_enable && !ppu_enable);
        assert (runtime_active && !nrom_256 && !chr_is_ram);
        assert (mirroring_mode == LOADER_MIRROR_HORIZONTAL);

        for (address = 0; address < 16'h8000; address = address + 1)
            send_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                         16'(address), image_b_prg(16'(address)));
        send_command(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (staged_image_valid && nes_hold_reset);
        assert (!nrom_256 && !chr_is_ram);
        assert (mirroring_mode == LOADER_MIRROR_HORIZONTAL);

        vector_low_before = reset_vector_low_reads;
        vector_high_before = reset_vector_high_reads;
        activate_and_release();
        replacement_count = replacement_count + 1;
        assert (runtime_active && nrom_256 && chr_is_ram);
        assert (mirroring_mode == LOADER_MIRROR_VERTICAL);
        timeout = 0;
        while ((nes.internal_cpu_ram.memory[11'h003] != 8'h99 ||
                reset_vector_low_reads == vector_low_before ||
                reset_vector_high_reads == vector_high_before) &&
               timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        assert (timeout < 10000)
            else $fatal(1, "NROM-256 runtime boot timed out PC=%04x",
                        cpu_debug_pc);
        assert (cartridge.runtime_cartridge.debug_prg_address ==
                cart_cpu_address[14:0]);

        // Zero-payload CHR-RAM is writable only after the new metadata is
        // activated.
        write_chr(13'h0456, 8'h3c);
        read_chr(13'h0456, 8'h3c);

        // Repeated ACTIVATE keeps the same image selected and performs a
        // deterministic reboot through the real reset vector.
        vector_low_before = reset_vector_low_reads;
        vector_high_before = reset_vector_high_reads;
        activate_and_release();
        assert (runtime_active && nrom_256 && chr_is_ram);
        timeout = 0;
        while ((reset_vector_low_reads == vector_low_before ||
                reset_vector_high_reads == vector_high_before) &&
               timeout < 10000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        assert (timeout < 10000);

        // An invalid replacement never publishes metadata or releases the
        // active runtime image into partially overwritten storage.
        manifest_valid = 1'b0;
        send_command(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (loader_error &&
                loader_error_code == LOADER_ERROR_INVALID_MANIFEST);
        assert (runtime_active && nrom_256 && chr_is_ram);
        assert (nes_hold_reset && functional_reset);
        send_command(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE,
                     16'h0000, 8'h00);
        #1;
        assert (loader_error && nes_hold_reset);

        // A physical reset during the failed transfer returns to the
        // backwards-compatible build-time cartridge path.
        reset = 1'b1;
        repeat (4) @(posedge clk);
        assert (!runtime_active && nes_hold_reset && functional_reset);
        reset = 1'b0;
        repeat (8) @(posedge clk);
        assert (!runtime_active && !nes_hold_reset && !functional_reset);
        assert (!nrom_256 && !chr_is_ram &&
                mirroring_mode == LOADER_MIRROR_HORIZONTAL);

        // Reset during a valid but incomplete replacement invalidates the
        // staged session and returns to legacy execution. The partial byte in
        // runtime RAM remains unselected and therefore cannot execute.
        begin_image(LOADER_PRG_NROM128_BYTES, LOADER_CHR_ROM_BYTES,
                    1'b0, LOADER_MIRROR_VERTICAL);
        send_command(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG,
                     16'h0000, 8'ha9);
        assert (loader_busy && !staged_image_valid && nes_hold_reset);
        reset = 1'b1;
        repeat (4) @(posedge clk);
        assert (!runtime_active && nes_hold_reset && functional_reset);
        reset = 1'b0;
        repeat (8) @(posedge clk);
        assert (loader_state == LOADER_STATE_IDLE);
        assert (!runtime_active && !staged_image_valid &&
                !nes_hold_reset && !functional_reset);
        assert (!nrom_256 && !chr_is_ram &&
                mirroring_mode == LOADER_MIRROR_HORIZONTAL);

        assert (activation_count == 3 && replacement_count == 1);
        assert (reset_vector_low_reads >= 3 &&
                reset_vector_high_reads >= 3);
        assert (runtime_chr_reads == 3);
        $display("PASS: Phase 4F-D atomic runtime activation and NES reset");
        $display("activations=%0d replacements=%0d vectors=%0d/%0d chr_reads=%0d",
                 activation_count, replacement_count,
                 reset_vector_low_reads, reset_vector_high_reads,
                 runtime_chr_reads);
        $finish;
    end
endmodule
