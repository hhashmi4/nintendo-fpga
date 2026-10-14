`timescale 1ns/1ps

// Production cartridge boundary with backward-compatible build-time NROM and
// an atomically selected runtime Mapper-0 image. Loader traffic never uses the
// NES CPU/PPU buses. The legacy cartridge remains selected until an explicit,
// validated ACTIVATE request completes its controlled reset window.
module nes_cartridge_runtime_mux #(
    parameter integer LEGACY_MAPPER_NUMBER = 0,
    parameter integer LEGACY_PRG_ROM_BYTES = 16384,
    parameter bit     LEGACY_CHR_IS_RAM = 1'b0,
    parameter bit     LEGACY_PRG_RAM_ENABLE = 1'b0,
    parameter logic [1:0] LEGACY_MIRRORING_MODE = 2'd0,
    parameter string  LEGACY_PRG_INIT_FILE = "",
    parameter string  LEGACY_CHR_INIT_FILE = "",
    parameter integer ACTIVATION_RESET_CYCLES = 4
) (
    input  logic                                      clk,
    input  logic                                      reset,

    input  logic                                      command_valid,
    input  nes_runtime_loader_pkg::loader_command_t   command,
    input  nes_runtime_loader_pkg::loader_target_t    command_target,
    input  logic [nes_runtime_loader_pkg::LOADER_ADDRESS_BITS-1:0]
                                                        command_address,
    input  logic [7:0]                                command_data,
    output logic                                      command_ready,
    output logic                                      command_accepted,

    input  logic                                      manifest_valid,
    input  logic [7:0]                                manifest_mapper,
    input  logic [15:0]                               manifest_prg_bytes,
    input  logic [15:0]                               manifest_chr_bytes,
    input  logic                                      manifest_chr_is_ram,
    input  logic [1:0]                                manifest_mirroring,

    input  logic        cpu_cycle_tick,
    input  logic        ppu_cycle_tick,
    input  logic [13:0] ppu_bus_address,
    input  logic        ppu_bus_read,
    input  logic        ppu_bus_write,
    output logic                                      mapper_irq,

    input  logic [15:0]                               cpu_address,
    input  logic                                      cpu_read,
    input  logic                                      cpu_write,
    input  logic [7:0]                                cpu_write_data,
    output logic [7:0]                                cpu_read_data,

    input  logic [12:0]                               chr_address,
    input  logic                                      chr_read,
    input  logic                                      chr_write,
    input  logic [7:0]                                chr_write_data,
    output logic [7:0]                                chr_read_data,

    output logic                                      cartridge_present,
    output logic [7:0]                                mapper_number,
    output logic                                      nrom_256,
    output logic                                      chr_is_ram,
    output logic [1:0]                                mirroring_mode,

    output nes_runtime_loader_pkg::loader_state_t     loader_state,
    output logic                                      loader_busy,
    output logic                                      loader_completed,
    output logic                                      loader_error,
    output nes_runtime_loader_pkg::loader_error_t     loader_error_code,
    output logic                                      staged_image_valid,
    output logic                                      activation_accepted,
    output logic                                      activation_in_progress,
    output logic                                      activation_error,
    output logic                                      runtime_active,
    output logic                                      nes_hold_reset,

    output logic [14:0]                               debug_prg_address,
    output logic [7:0]                                debug_prg_data,
    output logic [12:0]                               debug_chr_address,
    output logic [7:0]                                debug_chr_data,
    output logic                                      debug_prg_read,
    output logic                                      debug_prg_write,
    output logic                                      debug_prg_ram_read,
    output logic                                      debug_prg_ram_write,
    output logic                                      debug_chr_read,
    output logic                                      debug_chr_write
);
    logic [7:0] legacy_cpu_read_data;
    logic [7:0] legacy_chr_read_data;
    logic legacy_present;
    logic [7:0] legacy_mapper;
    logic legacy_nrom_256;
    logic legacy_chr_is_ram;
    logic [1:0] legacy_mirroring;
    logic [14:0] legacy_debug_prg_address;
    logic [7:0] legacy_debug_prg_data;
    logic [12:0] legacy_debug_chr_address;
    logic [7:0] legacy_debug_chr_data;
    logic legacy_debug_prg_read;
    logic legacy_debug_prg_write;
    logic legacy_debug_prg_ram_read;
    logic legacy_debug_prg_ram_write;
    logic legacy_debug_chr_read;
    logic legacy_debug_chr_write;

    logic [7:0] runtime_cpu_read_data;
    logic [7:0] runtime_chr_read_data;
    logic [7:0] staged_mapper;
    logic [15:0] staged_prg_bytes;
    logic [15:0] staged_chr_bytes;
    logic staged_chr_is_ram;
    logic [1:0] staged_mirroring;
    logic [7:0] active_mapper;
    logic [15:0] active_prg_bytes;
    logic [15:0] active_chr_bytes;
    logic active_chr_is_ram;
    logic [1:0] active_mirroring;
    logic [14:0] runtime_debug_prg_address;
    logic [7:0] runtime_debug_prg_data;
    logic [12:0] runtime_debug_chr_address;
    logic [7:0] runtime_debug_chr_data;
    logic runtime_debug_prg_read;
    logic runtime_debug_prg_write;
    logic runtime_debug_chr_read;
    logic runtime_debug_chr_write;

    logic legacy_irq;
    logic runtime_irq;
    logic [1:0] runtime_mirroring;
    logic legacy_selected;
    logic runtime_bus_enabled;

    assign legacy_selected = !runtime_active;
    assign runtime_bus_enabled = runtime_active && !nes_hold_reset;

    assign cartridge_present = runtime_active ? 1'b1 : legacy_present;
    assign mapper_number = runtime_active ? active_mapper : legacy_mapper;
    assign nrom_256 = runtime_active ?
                      active_prg_bytes ==
                      nes_runtime_loader_pkg::LOADER_PRG_NROM256_BYTES :
                      legacy_nrom_256;
    assign chr_is_ram = runtime_active ? active_chr_is_ram :
                                         legacy_chr_is_ram;
    assign mapper_irq = !reset && !nes_hold_reset &&
                        (runtime_active ? runtime_irq : legacy_irq);
    assign mirroring_mode = runtime_active ? runtime_mirroring :
                                             legacy_mirroring;

    assign cpu_read_data = runtime_active ? runtime_cpu_read_data :
                                            legacy_cpu_read_data;
    assign chr_read_data = runtime_active ? runtime_chr_read_data :
                                            legacy_chr_read_data;

    assign debug_prg_address = runtime_active ? runtime_debug_prg_address :
                                                legacy_debug_prg_address;
    assign debug_prg_data = runtime_active ? runtime_debug_prg_data :
                                             legacy_debug_prg_data;
    assign debug_chr_address = runtime_active ? runtime_debug_chr_address :
                                                legacy_debug_chr_address;
    assign debug_chr_data = runtime_active ? runtime_debug_chr_data :
                                             legacy_debug_chr_data;
    assign debug_prg_read = runtime_active ? runtime_debug_prg_read :
                                             legacy_debug_prg_read;
    assign debug_prg_write = runtime_active ? runtime_debug_prg_write :
                                              legacy_debug_prg_write;
    assign debug_prg_ram_read = runtime_active ? 1'b0 :
                                                 legacy_debug_prg_ram_read;
    assign debug_prg_ram_write = runtime_active ? 1'b0 :
                                                  legacy_debug_prg_ram_write;
    assign debug_chr_read = runtime_active ? runtime_debug_chr_read :
                                             legacy_debug_chr_read;
    assign debug_chr_write = runtime_active ? runtime_debug_chr_write :
                                              legacy_debug_chr_write;

    nes_cartridge #(
        .MAPPER_NUMBER (LEGACY_MAPPER_NUMBER),
        .PRG_ROM_BYTES (LEGACY_PRG_ROM_BYTES),
        .CHR_IS_RAM    (LEGACY_CHR_IS_RAM),
        .PRG_RAM_ENABLE(LEGACY_PRG_RAM_ENABLE),
        .MIRRORING_MODE(LEGACY_MIRRORING_MODE),
        .PRG_INIT_FILE (LEGACY_PRG_INIT_FILE),
        .CHR_INIT_FILE (LEGACY_CHR_INIT_FILE)
    ) legacy_cartridge (
        .cpu_cycle_tick(cpu_cycle_tick),
        .ppu_cycle_tick(ppu_cycle_tick),
        .ppu_bus_address(ppu_bus_address),
        .ppu_bus_read(ppu_bus_read),
        .ppu_bus_write(ppu_bus_write),
        .irq(legacy_irq),
        .clk                     (clk),
        .reset                   (reset || nes_hold_reset),
        .cpu_address             (cpu_address),
        .cpu_read                (cpu_read && legacy_selected &&
                                  !nes_hold_reset),
        .cpu_write               (cpu_write && legacy_selected &&
                                  !nes_hold_reset),
        .cpu_write_data          (cpu_write_data),
        .cpu_read_data           (legacy_cpu_read_data),
        .chr_address             (chr_address),
        .chr_read                (chr_read && legacy_selected &&
                                  !nes_hold_reset),
        .chr_write               (chr_write && legacy_selected &&
                                  !nes_hold_reset),
        .chr_write_data          (chr_write_data),
        .chr_read_data           (legacy_chr_read_data),
        .cartridge_present       (legacy_present),
        .mapper_number           (legacy_mapper),
        .nrom_256                (legacy_nrom_256),
        .chr_is_ram              (legacy_chr_is_ram),
        .mirroring_mode          (legacy_mirroring),
        .debug_prg_address       (legacy_debug_prg_address),
        .debug_prg_data          (legacy_debug_prg_data),
        .debug_chr_address       (legacy_debug_chr_address),
        .debug_chr_data          (legacy_debug_chr_data),
        .debug_prg_read          (legacy_debug_prg_read),
        .debug_prg_write         (legacy_debug_prg_write),
        .debug_prg_ram_read      (legacy_debug_prg_ram_read),
        .debug_prg_ram_write     (legacy_debug_prg_ram_write),
        .debug_chr_read          (legacy_debug_chr_read),
        .debug_chr_write         (legacy_debug_chr_write)
    );

    nes_runtime_cartridge #(
        .IMAGE_VALIDATION_ENABLE(1'b1),
        .ACTIVATION_ENABLE      (1'b1),
        .ACTIVATION_RESET_CYCLES(ACTIVATION_RESET_CYCLES)
    ) runtime_cartridge (
        .cpu_cycle_tick(cpu_cycle_tick),
        .ppu_cycle_tick(ppu_cycle_tick),
        .ppu_bus_address(ppu_bus_address),
        .ppu_bus_read(ppu_bus_read),
        .ppu_bus_write(ppu_bus_write),
        .mapper_irq(runtime_irq), .mapper_mirroring(runtime_mirroring),
        .clk                    (clk),
        .reset                  (reset),
        .command_valid          (command_valid),
        .command                (command),
        .command_target         (command_target),
        .command_address        (command_address),
        .command_data           (command_data),
        .command_ready          (command_ready),
        .command_accepted       (command_accepted),
        .manifest_valid         (manifest_valid),
        .manifest_mapper        (manifest_mapper),
        .manifest_prg_bytes     (manifest_prg_bytes),
        .manifest_chr_bytes     (manifest_chr_bytes),
        .manifest_chr_is_ram    (manifest_chr_is_ram),
        .manifest_mirroring     (manifest_mirroring),
        .nrom_256               (1'b0),
        .chr_is_ram             (1'b0),
        .cpu_address            (cpu_address),
        .cpu_read               (cpu_read && runtime_bus_enabled),
        .cpu_write              (cpu_write && runtime_bus_enabled),
        .cpu_write_data         (cpu_write_data),
        .cpu_read_data          (runtime_cpu_read_data),
        .chr_address            (chr_address),
        .chr_read               (chr_read && runtime_bus_enabled),
        .chr_write              (chr_write && runtime_bus_enabled),
        .chr_write_data         (chr_write_data),
        .chr_read_data          (runtime_chr_read_data),
        .loader_state           (loader_state),
        .loader_busy            (loader_busy),
        .loader_completed       (loader_completed),
        .loader_error           (loader_error),
        .loader_error_code      (loader_error_code),
        .nes_hold_reset         (nes_hold_reset),
        .image_valid            (staged_image_valid),
        .image_mapper           (staged_mapper),
        .image_prg_bytes        (staged_prg_bytes),
        .image_chr_bytes        (staged_chr_bytes),
        .image_chr_is_ram       (staged_chr_is_ram),
        .image_mirroring        (staged_mirroring),
        .activation_accepted    (activation_accepted),
        .activation_in_progress (activation_in_progress),
        .activation_error       (activation_error),
        .runtime_active         (runtime_active),
        .active_mapper          (active_mapper),
        .active_prg_bytes       (active_prg_bytes),
        .active_chr_bytes       (active_chr_bytes),
        .active_chr_is_ram      (active_chr_is_ram),
        .active_mirroring       (active_mirroring),
        .debug_prg_address      (runtime_debug_prg_address),
        .debug_prg_data         (runtime_debug_prg_data),
        .debug_chr_address      (runtime_debug_chr_address),
        .debug_chr_data         (runtime_debug_chr_data),
        .debug_prg_read         (runtime_debug_prg_read),
        .debug_prg_write        (runtime_debug_prg_write),
        .debug_chr_read         (runtime_debug_chr_read),
        .debug_chr_write        (runtime_debug_chr_write)
    );

`ifndef SYNTHESIS
    always_comb begin
        assert (!(legacy_selected && runtime_active));
        if (!runtime_active) begin
            assert (mapper_number == legacy_mapper);
            assert (mirroring_mode == legacy_mirroring);
        end
        if (runtime_active) begin
            assert (mapper_number == active_mapper);
            assert (mirroring_mode == active_mirroring);
            assert ((active_chr_is_ram && active_chr_bytes == 16'h0000) ||
                    (!active_chr_is_ram && active_chr_bytes ==
                     nes_runtime_loader_pkg::LOADER_CHR_ROM_BYTES));
        end
        if (staged_image_valid) begin
            assert (staged_mapper == 8'd0);
            assert (staged_prg_bytes ==
                    nes_runtime_loader_pkg::LOADER_PRG_NROM128_BYTES ||
                    staged_prg_bytes ==
                    nes_runtime_loader_pkg::LOADER_PRG_NROM256_BYTES);
            assert ((staged_chr_is_ram && staged_chr_bytes == 16'h0000) ||
                    (!staged_chr_is_ram && staged_chr_bytes ==
                     nes_runtime_loader_pkg::LOADER_CHR_ROM_BYTES));
            assert (staged_mirroring ==
                    nes_runtime_loader_pkg::LOADER_MIRROR_VERTICAL ||
                    staged_mirroring ==
                    nes_runtime_loader_pkg::LOADER_MIRROR_HORIZONTAL);
        end
        if (nes_hold_reset) begin
            assert (!legacy_debug_prg_read && !runtime_debug_prg_read);
            assert (!legacy_debug_chr_read && !runtime_debug_chr_read);
        end
    end
`endif
endmodule
