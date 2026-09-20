`timescale 1ns/1ps

module nes_phase3j_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic irq = 1'b0;
    logic [1:0] mirroring_mode = 2'b00;

    logic [15:0] cart_cpu_address;
    logic cart_cpu_read;
    logic [7:0] cart_cpu_read_data;
    logic [12:0] chr_addr;
    logic [7:0] chr_read_data;
    logic ppu_enable;
    logic cpu_cycle_slot;
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic cpu_bus_valid;
    logic [15:0] cpu_debug_pc;
    logic dma_active;
    logic [9:0] dma_stall_cycles;
    logic [8:0] dma_read_count;
    logic [8:0] dma_write_count;
    logic dma_read_event;
    logic dma_write_event;
    logic dma_complete_event;
    logic ppu_frame_start;
    logic [7:0] ppu_ctrl;
    logic [7:0] ppu_mask;
    logic ppu_nmi_event;
    logic pixel_valid;
    logic [7:0] pixel_x;
    logic [7:0] pixel_y;
    logic [1:0] pixel_source;

    logic [7:0] prg_memory [0:65535];
    logic [7:0] chr_memory [0:8191];
    logic [15:0] cursor;
    logic [15:0] main_loop_address;
    integer index;
    integer frame_number = -1;
    integer frame_sprite_x [0:7];
    integer fabric_cycles = 0;
    integer ppu_ticks = 0;
    integer cpu_slots = 0;
    integer cpu_run_cycles = 0;
    integer cartridge_reads = 0;
    integer ppu_cpu_accesses = 0;
    integer dma_completions = 0;
    integer dma_reads = 0;
    integer dma_writes = 0;
    integer nmi_events = 0;
    integer sprite_pixels = 0;
    integer dynamic_pairs = 0;
    integer first_dma_stall = 0;
    integer second_dma_stall = 0;
    integer ppu_ticks_since_last_slot = 0;
    logic first_dma_checked = 1'b0;
    logic second_dma_checked = 1'b0;

    task automatic emit(input logic [7:0] value);
        begin
            prg_memory[cursor] = value;
            cursor = cursor + 16'd1;
        end
    endtask

    /* verilator lint_off PINMISSING */
    nes_core dut (
        .clk                    (clk),
        .reset                  (reset),
        .irq                    (irq),
        .mirroring_mode         (mirroring_mode),
        .cart_cpu_address       (cart_cpu_address),
        .cart_cpu_read          (cart_cpu_read),
        .cart_cpu_read_data     (cart_cpu_read_data),
        .chr_addr               (chr_addr),
        .chr_read_data          (chr_read_data),
        .ppu_enable             (ppu_enable),
        .cpu_cycle_slot         (cpu_cycle_slot),
        .cpu_enable             (cpu_enable),
        .cpu_address            (cpu_address),
        .cpu_bus_valid          (cpu_bus_valid),
        .cpu_debug_pc           (cpu_debug_pc),
        .dma_active             (dma_active),
        .dma_stall_cycles       (dma_stall_cycles),
        .dma_read_count         (dma_read_count),
        .dma_write_count        (dma_write_count),
        .dma_read_event         (dma_read_event),
        .dma_write_event        (dma_write_event),
        .dma_complete_event     (dma_complete_event),
        .ppu_frame_start        (ppu_frame_start),
        .ppu_ctrl               (ppu_ctrl),
        .ppu_mask               (ppu_mask),
        .ppu_nmi_event          (ppu_nmi_event),
        .pixel_valid            (pixel_valid),
        .pixel_x                (pixel_x),
        .pixel_y                (pixel_y),
        .pixel_source           (pixel_source)
    );
    /* verilator lint_on PINMISSING */

    assign cart_cpu_read_data = prg_memory[cart_cpu_address];
    assign chr_read_data = chr_memory[chr_addr];

    always #10 clk <= ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            fabric_cycles <= fabric_cycles + 1;
            if (ppu_enable) begin
                ppu_ticks <= ppu_ticks + 1;
                ppu_ticks_since_last_slot <= ppu_ticks_since_last_slot + 1;
            end
            if (cpu_cycle_slot) begin
                cpu_slots <= cpu_slots + 1;
                assert (ppu_ticks_since_last_slot == 2)
                    else $fatal(1, "scheduler gap %0d", ppu_ticks_since_last_slot);
                ppu_ticks_since_last_slot <= 0;
            end
            if (cpu_enable)
                cpu_run_cycles <= cpu_run_cycles + 1;
            if (cart_cpu_read)
                cartridge_reads <= cartridge_reads + 1;
            if (cpu_enable && cpu_bus_valid &&
                cpu_address >= 16'h2000 && cpu_address <= 16'h3fff)
                ppu_cpu_accesses <= ppu_cpu_accesses + 1;
            if (dma_read_event)
                dma_reads <= dma_reads + 1;
            if (dma_write_event)
                dma_writes <= dma_writes + 1;
            if (ppu_nmi_event)
                nmi_events <= nmi_events + 1;

            if (dma_complete_event) begin
                dma_completions <= dma_completions + 1;
                assert (dma_read_count == 9'd256);
                assert (dma_write_count == 9'd256);
                assert (dma_stall_cycles == 10'd513 ||
                        dma_stall_cycles == 10'd514);
                if (dma_completions == 0) begin
                    first_dma_stall <= {22'd0, dma_stall_cycles};
                    assert (dut.ppu.oam.primary_oam[8'hfc] == 8'h14);
                    assert (dut.ppu.oam.primary_oam[8'hfd] == 8'h01);
                    assert (dut.ppu.oam.primary_oam[8'hfe] == 8'h00);
                    assert (dut.ppu.oam.primary_oam[8'hff] == 8'h28);
                    assert (dut.ppu.oam.primary_oam[8'h00] == 8'hff);
                    first_dma_checked <= 1'b1;
                end else if (dma_completions == 1) begin
                    second_dma_stall <= {22'd0, dma_stall_cycles};
                    assert (dut.ppu.oam.primary_oam[8'h00] == 8'h14);
                    assert (dut.ppu.oam.primary_oam[8'h01] == 8'h01);
                    assert (dut.ppu.oam.primary_oam[8'h02] == 8'h00);
                    assert (dut.ppu.oam.primary_oam[8'h03] == 8'h28);
                    second_dma_checked <= 1'b1;
                end
            end

            if (ppu_frame_start) begin
                frame_number <= frame_number + 1;
                if (frame_number + 1 < 8)
                    frame_sprite_x[frame_number + 1] <= -1;
            end
            if (pixel_valid && pixel_source == 2'd2) begin
                sprite_pixels <= sprite_pixels + 1;
                if (pixel_y == 8'd21 && frame_number >= 0 &&
                    frame_number < 8 && frame_sprite_x[frame_number] < 0)
                    frame_sprite_x[frame_number] <= {24'd0, pixel_x};
            end
        end
    end

    initial begin
        $dumpfile("build/sim/nes_phase3j.fst");
        $dumpvars(0, nes_phase3j_tb);

        for (index = 0; index < 65536; index = index + 1)
            prg_memory[index] = 8'hea;
        for (index = 0; index < 8192; index = index + 1)
            chr_memory[index] = 8'h00;
        for (index = 0; index < 8; index = index + 1) begin
            chr_memory[16 + index] = 8'hff;
            frame_sprite_x[index] = -1;
        end

        cursor = 32768;
        emit(8'h78);                    // SEI
        emit(8'hd8);                    // CLD
        emit(8'ha2); emit(8'h00);       // LDX #$00
        emit(8'ha9); emit(8'hff);       // LDA #$ff
        emit(8'h9d); emit(8'h00); emit(8'h02); // fill: STA $0200,X
        emit(8'he8);                    // INX
        emit(8'hd0); emit(8'hfa);       // BNE fill
        emit(8'ha9); emit(8'h14); emit(8'h8d); emit(8'h00); emit(8'h02);
        emit(8'ha9); emit(8'h01); emit(8'h8d); emit(8'h01); emit(8'h02);
        emit(8'ha9); emit(8'h00); emit(8'h8d); emit(8'h02); emit(8'h02);
        emit(8'ha9); emit(8'h28); emit(8'h8d); emit(8'h03); emit(8'h02);

        // First DMA starts at $fc and therefore verifies OAMADDR wrapping.
        emit(8'ha9); emit(8'hfc); emit(8'h8d); emit(8'h03); emit(8'h20);
        emit(8'ha9); emit(8'h02); emit(8'h8d); emit(8'h14); emit(8'h40);
        emit(8'h24); emit(8'h00);       // odd-cycle separation (BIT $00)
        emit(8'ha9); emit(8'h00); emit(8'h8d); emit(8'h03); emit(8'h20);
        emit(8'ha9); emit(8'h02); emit(8'h8d); emit(8'h14); emit(8'h40);

        // CPU RAM mirror and mirrored PPU register routing.
        emit(8'ha9); emit(8'ha5); emit(8'h8d); emit(8'h02); emit(8'h00);
        emit(8'had); emit(8'h02); emit(8'h08);
        emit(8'h8d); emit(8'h03); emit(8'h00);
        emit(8'ha9); emit(8'h03); emit(8'h8d); emit(8'h0d); emit(8'h20);
        emit(8'ha9); emit(8'h05); emit(8'h8d); emit(8'h0d); emit(8'h20);
        emit(8'ha9); emit(8'h3f); emit(8'h8d); emit(8'hfe); emit(8'h3f);
        emit(8'ha9); emit(8'h11); emit(8'h8d); emit(8'hfe); emit(8'h3f);
        emit(8'ha9); emit(8'h30); emit(8'h8d); emit(8'hff); emit(8'h3f);
        emit(8'ha9); emit(8'h80); emit(8'h8d); emit(8'h08); emit(8'h20);
        emit(8'ha9); emit(8'h14); emit(8'h8d); emit(8'hf9); emit(8'h3f);
        emit(8'ha9); emit(8'h5a); emit(8'h85); emit(8'h05);
        main_loop_address = cursor;
        emit(8'h4c); emit(main_loop_address[7:0]);
        emit(main_loop_address[15:8]);

        cursor = 36864;
        emit(8'he6); emit(8'h04);       // INC $04 (NMI count)
        emit(8'had); emit(8'h03); emit(8'h02); // LDA $0203
        emit(8'h18);                    // CLC
        emit(8'h69); emit(8'h08);       // ADC #8
        emit(8'h8d); emit(8'h03); emit(8'h02); // STA $0203
        emit(8'ha9); emit(8'h00); emit(8'h8d); emit(8'h03); emit(8'h20);
        emit(8'ha9); emit(8'h02); emit(8'h8d); emit(8'h14); emit(8'h40);
        emit(8'h40);                    // RTI

        prg_memory[16'hfffa] = 8'h00;
        prg_memory[16'hfffb] = 8'h90;
        prg_memory[16'hfffc] = 8'h00;
        prg_memory[16'hfffd] = 8'h80;
        prg_memory[16'hfffe] = 8'h00;
        prg_memory[16'hffff] = 8'h80;

        repeat (6) @(posedge clk);
        reset = 1'b0;

        while ((dut.cpu_ram[11'h004] < 8'd3 || dma_active ||
                frame_number < 4) && fabric_cycles < 500000)
            @(posedge clk);
        repeat (1000) @(posedge clk);

        assert (fabric_cycles < 500000)
            else $fatal(1, "integrated program timeout PC=%04x", cpu_debug_pc);
        assert (dut.cpu_ram[11'h003] == 8'ha5)
            else $fatal(1, "RAM mirror failed");
        assert (dut.cpu_ram[11'h005] == 8'h5a)
            else $fatal(1, "CPU did not finish initialization");
        assert (ppu_ctrl == 8'h80 && ppu_mask == 8'h14)
            else $fatal(1, "mirrored PPU writes failed %02x %02x",
                        ppu_ctrl, ppu_mask);
        assert (dut.ppu.background_core.memory.palette_ram[5'h11] == 8'h30)
            else $fatal(1, "PPUDATA palette write failed");
        assert (first_dma_checked && second_dma_checked);
        assert ((first_dma_stall == 513 && second_dma_stall == 514) ||
                (first_dma_stall == 514 && second_dma_stall == 513))
            else $fatal(1, "DMA parities not both covered: %0d %0d",
                        first_dma_stall, second_dma_stall);
        assert (dma_reads == dma_completions * 256);
        assert (dma_writes == dma_completions * 256);
        assert (nmi_events >= 3);
        assert (dut.cpu_ram[11'h004] >= 8'd3);
        assert (sprite_pixels > 0)
            else $fatal(1, "integrated sprite path produced no sprite pixels");

        for (index = 1; index < 8; index = index + 1) begin
            if (frame_sprite_x[index - 1] >= 0 &&
                frame_sprite_x[index] >= 0) begin
                assert (frame_sprite_x[index] ==
                        ((frame_sprite_x[index - 1] + 8) & 255))
                    else $fatal(1, "sprite did not move: frame %0d %0d -> %0d",
                                index, frame_sprite_x[index - 1],
                                frame_sprite_x[index]);
                dynamic_pairs = dynamic_pairs + 1;
            end
        end
        assert (dynamic_pairs >= 2)
            else $fatal(1, "insufficient dynamic sprite frames");

        $display("Phase 3J integrated system passed");
        $display("fabric_cycles=%0d ppu_ticks=%0d cpu_slots=%0d cpu_run_cycles=%0d",
                 fabric_cycles, ppu_ticks, cpu_slots, cpu_run_cycles);
        $display("dma_completions=%0d dma_reads=%0d dma_writes=%0d stalls=%0d/%0d",
                 dma_completions, dma_reads, dma_writes,
                 first_dma_stall, second_dma_stall);
        $display("nmi_events=%0d nmi_handlers=%0d cartridge_reads=%0d ppu_accesses=%0d",
                 nmi_events, dut.cpu_ram[11'h004], cartridge_reads,
                 ppu_cpu_accesses);
        $display("frames=%0d sprite_pixels=%0d dynamic_pairs=%0d",
                 frame_number + 1, sprite_pixels, dynamic_pairs);
        $finish;
    end
endmodule
