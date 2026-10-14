`timescale 1ns/1ps

module mapper_lifecycle_tb;
    import nes_runtime_loader_pkg::*;
    logic clk = 0;
    always #5 clk = !clk;
    logic reset = 1;
    logic command_valid = 0;
    loader_command_t command = LOADER_COMMAND_BEGIN;
    loader_target_t command_target = LOADER_TARGET_NONE;
    logic [15:0] command_address = 0;
    logic [7:0] command_data = 0;
    logic command_ready;
    logic manifest_valid = 1;
    logic [7:0] manifest_mapper = 0;
    logic [15:0] manifest_prg_bytes = 16384;
    logic [15:0] manifest_chr_bytes = 8192;
    logic manifest_chr_is_ram = 0;
    logic [1:0] manifest_mirroring = 1;
    logic [15:0] cpu_address = 0;
    logic cpu_read = 0, cpu_write = 0;
    logic [7:0] cpu_write_data = 0, cpu_read_data;
    logic [12:0] chr_address = 0;
    logic chr_read = 0, chr_write = 0;
    logic [7:0] chr_write_data = 0, chr_read_data;
    logic mapper_irq;
    logic [1:0] mapper_mirroring;
    logic nes_hold_reset, runtime_active;
    logic [7:0] active_mapper;
    logic [15:0] active_prg_bytes;
    loader_error_t loader_error_code;
    integer loads = 0;
    integer checks = 0;

    nes_runtime_cartridge dut (
        .clk(clk),
        .reset(reset),
        .command_valid(command_valid),
        .command(command),
        .command_target(command_target),
        .command_address(command_address),
        .command_data(command_data),
        .command_ready(command_ready),
        .command_accepted(),
        .manifest_valid(manifest_valid),
        .manifest_mapper(manifest_mapper),
        .manifest_prg_bytes(manifest_prg_bytes),
        .manifest_chr_bytes(manifest_chr_bytes),
        .manifest_chr_is_ram(manifest_chr_is_ram),
        .manifest_mirroring(manifest_mirroring),
        .nrom_256('0),
        .chr_is_ram('0),
        .cpu_cycle_tick('0),
        .ppu_cycle_tick('0),
        .ppu_bus_address('0),
        .ppu_bus_read('0),
        .ppu_bus_write('0),
        .mapper_mirroring(mapper_mirroring),
        .mapper_irq(mapper_irq),
        .cpu_address(cpu_address),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data),
        .chr_address(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .loader_state(),
        .loader_busy(),
        .loader_completed(),
        .loader_error(),
        .loader_error_code(loader_error_code),
        .nes_hold_reset(nes_hold_reset),
        .image_valid(),
        .image_mapper(),
        .image_prg_bytes(),
        .image_chr_bytes(),
        .image_chr_is_ram(),
        .image_mirroring(),
        .activation_accepted(),
        .activation_in_progress(),
        .activation_error(),
        .runtime_active(runtime_active),
        .active_mapper(active_mapper),
        .active_prg_bytes(active_prg_bytes),
        .active_chr_bytes(),
        .active_chr_is_ram(),
        .active_mirroring(),
        .debug_prg_address(),
        .debug_prg_data(),
        .debug_chr_address(),
        .debug_chr_data(),
        .debug_prg_read(),
        .debug_prg_write(),
        .debug_chr_read(),
        .debug_chr_write()
    );

    task automatic send(input loader_command_t op, input loader_target_t target,
                        input logic [15:0] address, input logic [7:0] data);
        @(negedge clk);
        command = op; command_target = target;
        command_address = address; command_data = data; command_valid = 1;
        #1;
        assert (command_ready) else $fatal(1, "command unexpectedly blocked");
        @(posedge clk); #1;
        @(negedge clk); command_valid = 0;
    endtask

    task automatic read_pair(input logic [15:0] ca, input logic [12:0] pa,
                             input logic [7:0] expected_prg,
                             input logic [7:0] expected_chr);
        @(negedge clk);
        cpu_address = ca; chr_address = pa; cpu_read = 1; chr_read = 1;
        @(posedge clk); #1;
        assert (cpu_read_data == expected_prg && chr_read_data == expected_chr)
            else $fatal(1, "read cpu=%04x chr=%04x actual=%02x/%02x expected=%02x/%02x",
                        ca, pa, cpu_read_data, chr_read_data, expected_prg, expected_chr);
        assert (!mapper_irq);
        checks++;
        @(negedge clk); cpu_read = 0; chr_read = 0;
    endtask

    task automatic load_image(input bit is_nrom256, input bit ram, input logic [7:0] tag);
        manifest_mapper = 0;
        manifest_prg_bytes = is_nrom256 ? 32768 : 16384;
        manifest_chr_bytes = ram ? 0 : 8192;
        manifest_chr_is_ram = ram;
        manifest_mirroring = ram ? 0 : 1;
        send(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
        assert (nes_hold_reset && !mapper_irq);
        for (int offset = 0; offset < int'(manifest_prg_bytes); offset++)
            send(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG, 16'(offset),
                 offset < 16384 ? tag : tag + 8'h40);
        for (int offset = 0; offset < int'(manifest_chr_bytes); offset++)
            send(LOADER_COMMAND_WRITE, LOADER_TARGET_CHR, 16'(offset),
                 offset < 4096 ? 8'h35 : 8'ha7);
        send(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE, 0, 0);
        assert (nes_hold_reset && loader_error_code == LOADER_ERROR_NONE);
        send(LOADER_COMMAND_ACTIVATE, LOADER_TARGET_NONE, 0, 0);
        repeat (5) @(posedge clk);
        #1;
        assert (runtime_active && !nes_hold_reset && !mapper_irq);
        assert (active_mapper == 0 && active_prg_bytes == manifest_prg_bytes);
        assert (mapper_mirroring == (ram ? 0 : 1));
        loads++;
    endtask

    always @(posedge clk) begin
        assert (!mapper_irq) else $fatal(1, "unexpected mapper IRQ");
        if (nes_hold_reset && !reset) begin
            assert (!dut.mapper.chr_write_enable);
            assert (!dut.mapper.cpu_prg_select);
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); reset = 0;
        load_image(0, 0, 8'h11);
        read_pair(16'h8000, 0, 8'h11, 8'h35);
        read_pair(16'hbfff, 13'h0fff, 8'h11, 8'h35);
        read_pair(16'hc000, 13'h1000, 8'h11, 8'ha7);
        read_pair(16'hffff, 13'h1fff, 8'h11, 8'ha7);
        read_pair(16'h7fff, 0, 0, 8'h35);
        // NROM register writes and CHR-ROM writes cannot alter either payload.
        @(negedge clk); cpu_address = 16'h8000; cpu_write_data = 8'hff;
        cpu_write = 1; chr_write = 1; chr_write_data = 8'hff;
        @(posedge clk); @(negedge clk); cpu_write = 0; chr_write = 0;
        read_pair(16'h8000, 0, 8'h11, 8'h35);
        // FPGA rejection preserves bytes and active metadata. Its established
        // protocol changes to ERROR/hold; there is intentionally no rollback.
        for (int id = 1; id < 256; id++) begin
            manifest_mapper = 8'(id);
            send(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
            assert (loader_error_code == LOADER_ERROR_UNSUPPORTED_MAPPER);
            send(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG, 0, 8'hde);
            assert (nes_hold_reset && runtime_active && active_mapper == 0);
            assert (active_prg_bytes == 16384 && mapper_mirroring == 1);
            assert (dut.mapper.storage.prg_memory[0] == 8'h11);
            assert (dut.mapper.storage.chr_memory[0] == 8'h35);
            assert (cpu_read_data == 0 && chr_read_data == 0);
            checks++;
        end
        load_image(1, 1, 8'h22);
        read_pair(16'h8000, 0, 8'h22, 8'h35);
        read_pair(16'hc000, 13'h1fff, 8'h62, 8'ha7);
        @(negedge clk); chr_write = 1; chr_write_data = 8'h5c;
        @(posedge clk); @(negedge clk); chr_write = 0;
        read_pair(16'hffff, 13'h1fff, 8'h62, 8'h5c);
        load_image(0, 0, 8'h33);
        read_pair(16'hffff, 13'h1fff, 8'h33, 8'ha7);
        // Abort after overwriting one byte: no partial program can execute.
        send(LOADER_COMMAND_BEGIN, LOADER_TARGET_NONE, 0, 0);
        send(LOADER_COMMAND_WRITE, LOADER_TARGET_PRG, 0, 8'h99);
        send(LOADER_COMMAND_COMMIT, LOADER_TARGET_NONE, 0, 0);
        assert (loader_error_code == LOADER_ERROR_PRG_INCOMPLETE && nes_hold_reset);
        assert (cpu_read_data == 0 && chr_read_data == 0);
        for (int epoch = 0; epoch < 8; epoch++) begin
            @(negedge clk); reset = 1;
            repeat (2) @(posedge clk);
            @(negedge clk); reset = 0;
            #1; assert (!runtime_active && !mapper_irq);
        end
        load_image(1, 1, 8'h44);
        read_pair(16'hffff, 13'h1fff, 8'h84, 8'ha7);
        $display("PASS: Phase7A runtime lifecycle loads=%0d checks=%0d unsupported_IDs=255 resets=8 CHR ROM/RAM, failed loads, permissions and concurrent reads", loads, checks);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "mapper lifecycle timeout");
    end
endmodule
