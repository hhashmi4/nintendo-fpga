`timescale 1ns/1ps

module nes_phase3j_nmi_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [15:0] cart_cpu_address;
    logic [7:0] cart_cpu_read_data;
    logic [7:0] chr_read_data = 8'h00;
    logic cpu_enable;
    logic [15:0] cpu_address;
    logic cpu_write_enable;
    logic cpu_bus_valid;
    logic [8:0] ppu_dot;
    logic [8:0] ppu_scanline;
    logic ppu_frame_start;
    logic ppu_status_vblank;
    logic ppu_nmi_event;
    logic ppu_nmi_suppressed;

    logic [7:0] prg_memory [0:65535];
    integer index;
    integer frame_count = 0;
    integer nmi_events = 0;
    integer suppressed_events = 0;
    integer status_reads = 0;
    integer boundary_read_dot0 = 0;
    integer boundary_read_after = 0;
    integer control_writes_in_vblank = 0;

    /* verilator lint_off PINMISSING */
    nes_core dut (
        .clk                  (clk),
        .reset                (reset),
        .irq                  (1'b0),
        .mirroring_mode       (2'b00),
        .cart_cpu_address     (cart_cpu_address),
        .cart_cpu_read_data   (cart_cpu_read_data),
        .chr_read_data        (chr_read_data),
        .cpu_enable           (cpu_enable),
        .cpu_address          (cpu_address),
        .cpu_write_enable     (cpu_write_enable),
        .cpu_bus_valid        (cpu_bus_valid),
        .ppu_dot              (ppu_dot),
        .ppu_scanline         (ppu_scanline),
        .ppu_frame_start      (ppu_frame_start),
        .ppu_status_vblank    (ppu_status_vblank),
        .ppu_nmi_event        (ppu_nmi_event),
        .ppu_nmi_suppressed   (ppu_nmi_suppressed)
    );
    /* verilator lint_on PINMISSING */

    assign cart_cpu_read_data = prg_memory[cart_cpu_address];
    always #10 clk <= ~clk;

    always @(posedge clk) begin
        if (!reset) begin
            if (ppu_frame_start)
                frame_count <= frame_count + 1;
            if (ppu_nmi_event)
                nmi_events <= nmi_events + 1;
            if (ppu_nmi_suppressed)
                suppressed_events <= suppressed_events + 1;

            if (cpu_enable && cpu_bus_valid && !cpu_write_enable &&
                cpu_address >= 16'h2000 && cpu_address <= 16'h3fff &&
                cpu_address[2:0] == 3'd2) begin
                status_reads <= status_reads + 1;
                if (ppu_scanline == 9'd241 && ppu_dot == 9'd0)
                    boundary_read_dot0 <= boundary_read_dot0 + 1;
                if (ppu_scanline == 9'd241 && ppu_dot >= 9'd3 &&
                    ppu_dot <= 9'd12)
                    boundary_read_after <= boundary_read_after + 1;
            end

            if (cpu_enable && cpu_bus_valid && cpu_write_enable &&
                cpu_address >= 16'h2000 && cpu_address <= 16'h3fff &&
                cpu_address[2:0] == 3'd0 && ppu_status_vblank)
                control_writes_in_vblank <= control_writes_in_vblank + 1;
        end
    end

    initial begin
        for (index = 0; index < 65536; index = index + 1)
            prg_memory[index] = 8'hea;

        // Enable NMI, wait until two recognitions from the first VBlank and
        // one from the second, then continuously poll $2002.  The first NMI
        // handler deliberately disables and re-enables NMI while VBlank is
        // still set, producing the required immediate second activation.
        prg_memory[16'h8000] = 8'ha9; prg_memory[16'h8001] = 8'h80;
        prg_memory[16'h8002] = 8'h8d; prg_memory[16'h8003] = 8'h00;
        prg_memory[16'h8004] = 8'h20;
        prg_memory[16'h8005] = 8'ha5; prg_memory[16'h8006] = 8'h10;
        prg_memory[16'h8007] = 8'hc9; prg_memory[16'h8008] = 8'h03;
        prg_memory[16'h8009] = 8'hd0; prg_memory[16'h800a] = 8'hfa;
        prg_memory[16'h800b] = 8'had; prg_memory[16'h800c] = 8'h02;
        prg_memory[16'h800d] = 8'h20;
        prg_memory[16'h800e] = 8'h4c; prg_memory[16'h800f] = 8'h0b;
        prg_memory[16'h8010] = 8'h80;

        prg_memory[16'h9000] = 8'he6; prg_memory[16'h9001] = 8'h10;
        prg_memory[16'h9002] = 8'ha5; prg_memory[16'h9003] = 8'h10;
        prg_memory[16'h9004] = 8'hc9; prg_memory[16'h9005] = 8'h01;
        prg_memory[16'h9006] = 8'hd0; prg_memory[16'h9007] = 8'h0a;
        prg_memory[16'h9008] = 8'ha9; prg_memory[16'h9009] = 8'h00;
        prg_memory[16'h900a] = 8'h8d; prg_memory[16'h900b] = 8'h00;
        prg_memory[16'h900c] = 8'h20;
        prg_memory[16'h900d] = 8'ha9; prg_memory[16'h900e] = 8'h80;
        prg_memory[16'h900f] = 8'h8d; prg_memory[16'h9010] = 8'h00;
        prg_memory[16'h9011] = 8'h20;
        prg_memory[16'h9012] = 8'h40;

        prg_memory[16'hfffa] = 8'h00;
        prg_memory[16'hfffb] = 8'h90;
        prg_memory[16'hfffc] = 8'h00;
        prg_memory[16'hfffd] = 8'h80;
        prg_memory[16'hfffe] = 8'h00;
        prg_memory[16'hffff] = 8'h80;

        repeat (6) @(posedge clk);
        reset = 1'b0;
        while (frame_count < 24)
            @(posedge clk);
        repeat (200) @(posedge clk);

        assert ({24'd0, dut.cpu_ram[11'h010]} == nmi_events)
            else $fatal(1, "CPU saw %0d NMIs but PPU generated %0d",
                        dut.cpu_ram[11'h010], nmi_events);
        assert (control_writes_in_vblank == 2)
            else $fatal(1, "enable-during-VBlank sequence missing");
        assert (nmi_events >= 4)
            else $fatal(1, "ordinary/immediate NMI recognition missing");
        assert (status_reads > 1000);
        assert (boundary_read_dot0 > 0)
            else $fatal(1, "schedule never exercised 241:0 read");
        assert (boundary_read_after > 0)
            else $fatal(1, "schedule never exercised post-set read");
        assert (suppressed_events > 0)
            else $fatal(1, "boundary read never suppressed VBlank NMI");

        $display("Phase 3J scheduled NMI sampling passed");
        $display("frames=%0d events=%0d cpu_recognitions=%0d suppressions=%0d",
                 frame_count, nmi_events, dut.cpu_ram[11'h010],
                 suppressed_events);
        $display("status_reads=%0d boundary_dot0=%0d boundary_after=%0d vblank_control_writes=%0d",
                 status_reads, boundary_read_dot0, boundary_read_after,
                 control_writes_in_vblank);
        $finish;
    end
endmodule
