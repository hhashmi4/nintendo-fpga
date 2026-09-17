`timescale 1ns/1ps

module platform_foundation_tb;
    import platform_config_pkg::*;

    localparam int unsigned TEST_WINDOW_CYCLES =
        MASTER_CE_DENOMINATOR * NTSC_PPU_MASTER_DIVISOR;
    localparam int unsigned PATTERN_CYCLES = 128;

    logic ref_clk = 1'b0;
    logic ext_reset_n = 1'b0;
    logic sys_clk;
    logic reset;
    logic nes_master_ce;
    logic ppu_ce;
    logic cpu_ce;
    logic apu_ce;
    logic ppu_heartbeat;
    logic cpu_heartbeat;
    logic [PATTERN_CYCLES-1:0] first_master_pattern = '0;
    logic [PATTERN_CYCLES-1:0] first_pattern = '0;

    int unsigned master_count;
    int unsigned ppu_count;
    int unsigned cpu_count;
    int unsigned apu_count;
    int unsigned ppu_since_cpu;
    logic previous_master_ce;

    platform_core dut (
        .ref_clk     (ref_clk),
        .ext_reset_n (ext_reset_n),
        .sys_clk     (sys_clk),
        .reset       (reset),
        .nes_master_ce (nes_master_ce),
        .ppu_ce      (ppu_ce),
        .cpu_ce      (cpu_ce),
        .apu_ce      (apu_ce)
    );

    platform_diagnostic diagnostic (
        .clk           (sys_clk),
        .reset         (reset),
        .nes_master_ce (nes_master_ce),
        .ppu_ce        (ppu_ce),
        .cpu_ce        (cpu_ce),
        .apu_ce        (apu_ce),
        .ppu_heartbeat (ppu_heartbeat),
        .cpu_heartbeat (cpu_heartbeat)
    );

    always #10 ref_clk <= !ref_clk;

    task automatic sample_clock;
        @(posedge ref_clk);
        #1;
        assert (!$isunknown({reset, nes_master_ce, ppu_ce, cpu_ce, apu_ce,
                             ppu_heartbeat, cpu_heartbeat}))
            else $fatal(1, "unknown platform state after clock edge");
    endtask

    task automatic release_reset;
        ext_reset_n = 1'b1;
        sample_clock();
        assert (reset) else $fatal(1, "reset released before synchronizer delay");
        sample_clock();
        assert (!reset) else $fatal(1, "reset did not release after two clocks");
        assert ({nes_master_ce, ppu_ce, cpu_ce, apu_ce} == 4'b0000)
            else $fatal(1, "clock enables active during reset release");
    endtask

    initial begin
        $dumpfile("build/sim/platform_foundation.fst");
        $dumpvars(0, platform_foundation_tb);

        #1;
        assert (reset) else $fatal(1, "power-up reset state is not asserted");
        assert ({nes_master_ce, ppu_ce, cpu_ce, apu_ce} == 4'b0000)
            else $fatal(1, "power-up enable state is not zero");

        repeat (3) begin
            sample_clock();
            assert (reset) else $fatal(1, "reset did not remain asserted");
            assert ({nes_master_ce, ppu_ce, cpu_ce, apu_ce} == 4'b0000)
                else $fatal(1, "enable active while reset asserted");
        end

        release_reset();

        master_count = 0;
        ppu_count = 0;
        cpu_count = 0;
        apu_count = 0;
        ppu_since_cpu = 0;
        previous_master_ce = 1'b0;

        for (int unsigned cycle = 0; cycle < TEST_WINDOW_CYCLES; cycle++) begin
            sample_clock();

            if (cycle < PATTERN_CYCLES) begin
                first_master_pattern[cycle] = nes_master_ce;
                first_pattern[cycle] = ppu_ce;
            end

            assert (!(nes_master_ce && previous_master_ce))
                else $fatal(1, "master enable repeated on adjacent clocks");
            assert (apu_ce == cpu_ce)
                else $fatal(1, "APU and CPU enables diverged");
            assert (!ppu_ce || nes_master_ce)
                else $fatal(1, "PPU enable occurred without master enable");
            assert (!cpu_ce || ppu_ce)
                else $fatal(1, "CPU enable occurred without PPU enable");

            if (nes_master_ce) begin
                master_count++;
            end
            if (ppu_ce) begin
                ppu_count++;
                ppu_since_cpu++;
            end
            if (cpu_ce) begin
                cpu_count++;
                assert (ppu_since_cpu == PPU_TICKS_PER_CPU_TICK)
                    else $fatal(1, "CPU enable did not follow three PPU enables");
                ppu_since_cpu = 0;
            end
            if (apu_ce) begin
                apu_count++;
            end

            previous_master_ce = nes_master_ce;
        end

        assert (master_count ==
                MASTER_CE_NUMERATOR * NTSC_PPU_MASTER_DIVISOR)
            else $fatal(1, "unexpected master enable count: %0d", master_count);
        assert (ppu_count == MASTER_CE_NUMERATOR)
            else $fatal(1, "expected %0d PPU enables, observed %0d",
                        MASTER_CE_NUMERATOR, ppu_count);
        assert (cpu_count == MASTER_CE_NUMERATOR / PPU_TICKS_PER_CPU_TICK)
            else $fatal(1, "unexpected CPU enable count: %0d", cpu_count);
        assert (apu_count == cpu_count)
            else $fatal(1, "unexpected APU enable count: %0d", apu_count);

        // Reassert between clock edges. The internal reset must assert without
        // waiting for a clock, while consumers clear on the following edge.
        #7 ext_reset_n = 1'b0;
        #1;
        assert (reset) else $fatal(1, "internal reset did not assert asynchronously");
        sample_clock();
        assert ({nes_master_ce, ppu_ce, cpu_ce, apu_ce} == 4'b0000)
            else $fatal(1, "enable not cleared by reset clock edge");
        assert (!ppu_heartbeat && !cpu_heartbeat)
            else $fatal(1, "diagnostic state not cleared by reset");

        release_reset();

        for (int unsigned cycle = 0; cycle < PATTERN_CYCLES; cycle++) begin
            sample_clock();
            assert (nes_master_ce == first_master_pattern[cycle])
                else $fatal(1, "master startup pattern changed at cycle %0d", cycle);
            assert (ppu_ce == first_pattern[cycle])
                else $fatal(1, "startup timing pattern changed at cycle %0d", cycle);
        end

        $display("PASS: reset, deterministic startup, and clock-enable relationships");
        $finish;
    end
endmodule
