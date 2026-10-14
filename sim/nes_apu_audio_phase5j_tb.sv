`timescale 1ns/1ps

module nes_apu_audio_phase5j_tb;
    logic [13:0] unused_phase7a_mapper_ppu_address_0;
    logic unused_phase7a_mapper_ppu_read_1;
    logic unused_phase7a_mapper_ppu_write_2;
    logic unused_phase7a_irq_3;
    import cpu_pkg::*;
    import nes_apu_pkg::*;
    import nes_system_pkg::*;

    localparam longint unsigned MAX_CAPTURE_CYCLES = 20_000_000;
    localparam int unsigned MAX_FABRIC_CYCLES = 100_100_000;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic injected_reset = 1'b0;
    logic debugger_authorized = 1'b1;
    logic functional_reset;

    logic [15:0] cart_cpu_address;
    logic cart_cpu_read;
    logic cart_cpu_write;
    logic [7:0] cart_cpu_write_data;
    logic [7:0] cart_cpu_read_data;
    logic [12:0] chr_address;
    logic chr_read;
    logic chr_write;
    logic [7:0] chr_write_data;
    logic [7:0] chr_read_data;

    logic [15:0] apu_cpu_address;
    logic apu_cpu_read;
    logic apu_cpu_write;
    logic [7:0] apu_cpu_write_data;
    logic [7:0] apu_cpu_read_data;
    logic apu_irq;
    logic [3:0] pulse1_output;
    logic [3:0] pulse2_output;
    logic [3:0] triangle_output;
    logic [3:0] noise_output;
    logic [6:0] dmc_output;
    logic [19:0] mixed_audio;
    logic dmc_mem_request;
    logic [15:0] dmc_mem_address;
    logic dmc_mem_acknowledge;
    logic [7:0] dmc_mem_read_data;

    logic controller_port;
    logic controller_cpu_read;
    logic controller_cpu_write;
    logic [7:0] controller_cpu_write_data;
    logic [7:0] controller_cpu_read_data;

    logic ppu_enable;
    logic cpu_cycle_slot;
    logic cpu_enable;
    logic cpu_bus_valid;
    logic cpu_write_enable;
    logic [15:0] cpu_address;
    logic [7:0] cpu_write_data;
    logic [15:0] cpu_debug_pc;
    logic [5:0] cpu_debug_execution_state;
    logic dma_active;
    logic dmc_dma_cpu_stall;

    string scenario = "silence";
    string rom_path = "build/sim/phase5j_silence.prg.hex";
    string capture_path = "build/audio/phase5j_silence.apucap";
    longint unsigned target_cpu_cycles = 89_489;
    longint pause_at = -1;
    longint reset_at = -1;
    integer capture_file;

    longint unsigned fabric_cycles = 0;
    longint unsigned emulated_slots = 0;
    longint unsigned audio_cycle = 0;
    longint unsigned instructions = 0;
    longint unsigned write_count = 0;
    longint unsigned fetch_count = 0;
    longint unsigned event_count = 0;
    logic capture_started = 1'b0;
    logic capture_done = 1'b0;
    logic previous_slot = 1'b0;
    logic previous_event_valid = 1'b0;
    logic [19:0] previous_mixed = '0;
    logic [3:0] previous_pulse1 = '0;
    logic [3:0] previous_pulse2 = '0;
    logic [3:0] previous_triangle = '0;
    logic [3:0] previous_noise = '0;
    logic [6:0] previous_dmc = '0;

    assign functional_reset = reset || injected_reset;

    /* verilator lint_off PINMISSING */
    nes_core nes (
        .mapper_ppu_address(unused_phase7a_mapper_ppu_address_0),
        .mapper_ppu_read(unused_phase7a_mapper_ppu_read_1),
        .mapper_ppu_write(unused_phase7a_mapper_ppu_write_2),
        .clk(clk),
        .reset(functional_reset),
        .nes_enable(debugger_authorized),
        .irq(apu_irq),
        .mirroring_mode(2'd0),
        .cart_cpu_address(cart_cpu_address),
        .cart_cpu_read(cart_cpu_read),
        .cart_cpu_write(cart_cpu_write),
        .cart_cpu_write_data(cart_cpu_write_data),
        .cart_cpu_read_data(cart_cpu_read_data),
        .apu_cpu_address(apu_cpu_address),
        .apu_cpu_read(apu_cpu_read),
        .apu_cpu_write(apu_cpu_write),
        .apu_cpu_write_data(apu_cpu_write_data),
        .apu_cpu_read_data(apu_cpu_read_data),
        .dmc_mem_request(dmc_mem_request),
        .dmc_mem_address(dmc_mem_address),
        .dmc_mem_acknowledge(dmc_mem_acknowledge),
        .dmc_mem_read_data(dmc_mem_read_data),
        .controller_port(controller_port),
        .controller_cpu_read(controller_cpu_read),
        .controller_cpu_write(controller_cpu_write),
        .controller_cpu_write_data(controller_cpu_write_data),
        .controller_cpu_read_data(controller_cpu_read_data),
        .chr_addr(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data),
        .ppu_enable(ppu_enable),
        .cpu_cycle_slot(cpu_cycle_slot),
        .cpu_enable(cpu_enable),
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),
        .cpu_write_enable(cpu_write_enable),
        .cpu_bus_valid(cpu_bus_valid),
        .cpu_debug_pc(cpu_debug_pc),
        .cpu_debug_execution_state(cpu_debug_execution_state),
        .dma_active(dma_active),
        .dmc_dma_cpu_stall(dmc_dma_cpu_stall)
    );
    /* verilator lint_on PINMISSING */

    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off PINMISSING */
    nes_apu apu (
        .clk(clk),
        .reset(functional_reset),
        .cpu_cycle_enable(cpu_cycle_slot),
        .cpu_read(apu_cpu_read),
        .cpu_write(apu_cpu_write),
        .cpu_address(apu_cpu_address),
        .cpu_write_data(apu_cpu_write_data),
        .cpu_read_data(apu_cpu_read_data),
        .dmc_mem_request(dmc_mem_request),
        .dmc_mem_address(dmc_mem_address),
        .dmc_mem_acknowledge(dmc_mem_acknowledge),
        .dmc_mem_read_data(dmc_mem_read_data),
        .channel_active('0),
        .dmc_irq_flag(1'b0),
        .irq(apu_irq),
        .pulse1_output(pulse1_output),
        .pulse2_output(pulse2_output),
        .triangle_output(triangle_output),
        .noise_output(noise_output),
        .dmc_output(dmc_output),
        .mixed_audio(mixed_audio)
    );
    /* verilator lint_on PINMISSING */
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_controller controllers (
        .clk(clk),
        .reset(functional_reset),
        .controller1_buttons('0),
        .controller2_buttons('0),
        .cpu_port(controller_port),
        .cpu_read(controller_cpu_read),
        .cpu_write(controller_cpu_write),
        .cpu_write_data(controller_cpu_write_data),
        .cpu_read_data(controller_cpu_read_data)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    nes_cartridge #(
        .PRG_ROM_BYTES(16_384),
        .CHR_IS_RAM(1'b1),
        .MIRRORING_MODE(2'd0),
        .PRG_INIT_FILE("build/sim/phase5j_silence.prg.hex")
    ) cartridge (
        .cpu_cycle_tick(1'b0), .ppu_cycle_tick(1'b0),
        .ppu_bus_address(14'd0), .ppu_bus_read(1'b0), .ppu_bus_write(1'b0),
        .irq(unused_phase7a_irq_3),
        .clk(clk),
        .reset(functional_reset),
        .cpu_address(cart_cpu_address),
        .cpu_read(cart_cpu_read),
        .cpu_write(cart_cpu_write),
        .cpu_write_data(cart_cpu_write_data),
        .cpu_read_data(cart_cpu_read_data),
        .chr_address(chr_address),
        .chr_read(chr_read),
        .chr_write(chr_write),
        .chr_write_data(chr_write_data),
        .chr_read_data(chr_read_data)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk = !clk;

    task automatic write_audio_event;
        begin
            if (!previous_event_valid || mixed_audio != previous_mixed ||
                pulse1_output != previous_pulse1 ||
                pulse2_output != previous_pulse2 ||
                triangle_output != previous_triangle ||
                noise_output != previous_noise || dmc_output != previous_dmc) begin
                $fdisplay(capture_file, "A %0d %0d %0d %0d %0d %0d %0d 0",
                          audio_cycle, mixed_audio, pulse1_output, pulse2_output,
                          triangle_output, noise_output, dmc_output);
                event_count++;
                previous_event_valid = 1'b1;
                previous_mixed = mixed_audio;
                previous_pulse1 = pulse1_output;
                previous_pulse2 = pulse2_output;
                previous_triangle = triangle_output;
                previous_noise = noise_output;
                previous_dmc = dmc_output;
            end
        end
    endtask

    task automatic finish_capture;
        begin
            assert (capture_started);
            assert (instructions > 0 && write_count > 0);
            $fdisplay(capture_file, "I %0d", instructions);
            $fdisplay(capture_file, "END %0d %0d %0d %0d", target_cpu_cycles,
                      event_count, write_count, fetch_count);
            $fclose(capture_file);
            capture_done = 1'b1;
            $display("PASS: Phase 5J RTL audio scenario=%s cycles=%0d instructions=%0d APU_writes=%0d DMC_fetches=%0d events=%0d",
                     scenario, target_cpu_cycles, instructions, write_count,
                     fetch_count, event_count);
            $finish;
        end
    endtask

    always @(posedge clk) begin : capture_monitor
        logic was_slot;
        was_slot = cpu_cycle_slot;
        fabric_cycles++;
        if (functional_reset)
            previous_slot = 1'b0;
        else begin
            if (was_slot)
                emulated_slots++;
            if (cpu_enable && cpu_bus_valid &&
                cpu_debug_execution_state == CPU_STATE_FETCH)
                instructions++;
            assert (!apu_cpu_write ||
                    (cpu_enable && cpu_bus_valid && cpu_write_enable));
            assert (!apu_cpu_read ||
                    (cpu_enable && cpu_bus_valid && !cpu_write_enable));
            if (apu_cpu_write) begin
                assert (!dma_active && !dmc_dma_cpu_stall);
                write_count++;
                $fdisplay(capture_file, "W %0d 0x%04x 0x%04x 0x%02x",
                          emulated_slots, cpu_debug_pc, apu_cpu_address,
                          apu_cpu_write_data);
            end
            if (dmc_mem_acknowledge) begin
                assert (dmc_mem_read_data ==
                        cartridge.mapper0_selected.mapper.prg_rom[
                            dmc_mem_address[13:0]
                        ]);
                fetch_count++;
                $fdisplay(capture_file, "F %0d 0x%04x 0x%02x",
                          emulated_slots, dmc_mem_address, dmc_mem_read_data);
            end
        end
        #1;
        if (!functional_reset && previous_slot) begin
            // The raw tuple changed on the preceding APU slot. Sampling here,
            // one fabric edge later, explicitly removes the mixer pipeline
            // latency without shifting the signal by an NES CPU cycle.
            if (!capture_started && nes.internal_cpu_ram.memory[0] == 8'hA5) begin
                capture_started = 1'b1;
                audio_cycle = 0;
                $fdisplay(capture_file, "S %0d", emulated_slots);
                write_audio_event();
            end else if (capture_started) begin
                if (audio_cycle + 1 < target_cpu_cycles) begin
                    audio_cycle++;
                    write_audio_event();
                end else begin
                    finish_capture();
                end
            end
        end
        previous_slot = !functional_reset && was_slot;
    end

    initial begin : test_sequence
        logic [19:0] held_mixed;
        logic [3:0] held_pulse1;
        logic [3:0] held_pulse2;
        logic [3:0] held_triangle;
        logic [3:0] held_noise;
        logic [6:0] held_dmc;
        integer ignored;

        ignored = $value$plusargs("SCENARIO=%s", scenario);
        ignored = $value$plusargs("ROM=%s", rom_path);
        ignored = $value$plusargs("CAPTURE=%s", capture_path);
        ignored = $value$plusargs("CPU_CYCLES=%d", target_cpu_cycles);
        ignored = $value$plusargs("PAUSE_AT=%d", pause_at);
        ignored = $value$plusargs("RESET_AT=%d", reset_at);
        assert (target_cpu_cycles > 0 &&
                target_cpu_cycles <= MAX_CAPTURE_CYCLES);

        #1;
        $readmemh(rom_path, cartridge.mapper0_selected.mapper.prg_rom);
        capture_file = $fopen(capture_path, "w");
        assert (capture_file != 0) else $fatal(1, "cannot open capture file");
        $fdisplay(capture_file, "NESAPU_CAPTURE_V1");
        $fdisplay(capture_file, "scenario=%s", scenario);
        $fdisplay(capture_file, "cpu_rate_num=19687500");
        $fdisplay(capture_file, "cpu_rate_den=11");
        $fdisplay(capture_file, "cpu_cycles=%0d", target_cpu_cycles);
        $fdisplay(capture_file, "mixer_q_bits=20");
        $fdisplay(capture_file, "mixer_latency_fabric_cycles=1");
        $fdisplay(capture_file, "pause_policy=omit");
        $fdisplay(capture_file, "BEGIN");

        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        wait (capture_started);

        if (pause_at >= 0) begin
            wait (audio_cycle >= pause_at);
            @(negedge clk);
            held_mixed = mixed_audio;
            held_pulse1 = pulse1_output;
            held_pulse2 = pulse2_output;
            held_triangle = triangle_output;
            held_noise = noise_output;
            held_dmc = dmc_output;
            debugger_authorized = 1'b0;
            repeat (96) begin
                @(posedge clk);
                #1;
                assert (!cpu_cycle_slot && mixed_audio == held_mixed &&
                        pulse1_output == held_pulse1 &&
                        pulse2_output == held_pulse2 &&
                        triangle_output == held_triangle &&
                        noise_output == held_noise && dmc_output == held_dmc);
            end
            $fdisplay(capture_file, "P %0d 96", audio_cycle);
            @(negedge clk);
            debugger_authorized = 1'b1;
        end

        if (reset_at >= 0) begin
            wait (audio_cycle >= reset_at);
            @(negedge clk);
            $fdisplay(capture_file, "R %0d 1", audio_cycle);
            injected_reset = 1'b1;
            repeat (4) @(posedge clk);
            #1;
            assert (mixed_audio == 0 && pulse1_output == 0 &&
                    pulse2_output == 0 && triangle_output == 15 &&
                    noise_output == 0 && dmc_output == 0 && !apu_irq);
            @(negedge clk);
            injected_reset = 1'b0;
            $fdisplay(capture_file, "R %0d 0", audio_cycle);
        end

        wait (capture_done);
    end

    initial begin : timeout
        repeat (MAX_FABRIC_CYCLES) @(posedge clk);
        $fatal(1, "Phase 5J audio capture timeout");
    end
endmodule
