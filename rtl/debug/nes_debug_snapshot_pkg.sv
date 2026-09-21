`timescale 1ns/1ps

package nes_debug_snapshot_pkg;
    typedef struct packed {
        logic [15:0] pc;
        logic [7:0]  a;
        logic [7:0]  x;
        logic [7:0]  y;
        logic [7:0]  sp;
        logic [7:0]  status;
        logic [7:0]  opcode;
        logic [15:0] address;
        logic [7:0]  read_data;
        logic [7:0]  write_data;
        logic        read;
        logic        write;
        logic        bus_valid;
        logic        stalled;
        logic [1:0]  bus_owner;
    } nes_cpu_debug_snapshot_t;

    typedef struct packed {
        logic [8:0]  scanline;
        logic [8:0]  dot;
        logic        frame_odd;
        logic [7:0]  ctrl;
        logic [7:0]  mask;
        logic [7:0]  status;
        logic [7:0]  pixel_x;
        logic [7:0]  pixel_y;
        logic [13:0] palette_address;
        logic [5:0]  pixel_color;
        logic [2:0]  pixel_emphasis;
        logic [1:0]  pixel_source;
        logic        pixel_valid;
        logic        nmi_enabled;
        logic        nmi_level;
        logic        nmi_event;
        logic        nmi_suppressed;
        logic        vblank;
        logic        sprite_zero_hit;
        logic        sprite_overflow;
    } nes_ppu_debug_snapshot_t;

    typedef struct packed {
        logic        present;
        logic [7:0]  mapper_number;
        logic        nrom_256;
        logic [14:0] prg_address;
        logic [7:0]  prg_data;
        logic        prg_read;
        logic        prg_write;
        logic [12:0] chr_address;
        logic [7:0]  chr_data;
        logic        chr_read;
        logic        chr_write;
        logic        chr_is_ram;
        logic [1:0]  mirroring;
    } nes_cartridge_debug_snapshot_t;

    typedef struct packed {
        logic [7:0] live1;
        logic [7:0] live2;
        logic [7:0] shift1;
        logic [7:0] shift2;
        logic [3:0] index1;
        logic [3:0] index2;
        logic       strobe;
        logic       serial1;
        logic       serial2;
        logic       read_4016;
        logic       read_4017;
        logic       latch_event;
    } nes_controller_debug_snapshot_t;

    typedef struct packed {
        logic        active;
        logic [7:0]  source_page;
        logic [15:0] source_address;
        logic [7:0]  source_data;
        logic [7:0]  byte_index;
        logic [7:0]  oam_data;
        logic [2:0]  phase;
        logic        started_odd;
        logic [9:0]  elapsed_slots;
        logic [8:0]  read_count;
        logic [8:0]  write_count;
        logic        cpu_stall;
        logic [1:0]  bus_owner;
        logic        start_event;
        logic        read_event;
        logic        write_event;
        logic        complete_event;
        logic        dummy_cycle;
        logic        alignment_cycle;
    } nes_dma_debug_snapshot_t;

    typedef struct packed {
        logic [31:0] snapshot_id;
        logic [31:0] source_frame_number;
        logic [31:0] nmi_count;
        logic [31:0] dma_count;
        logic [31:0] controller_poll_count;
        logic [31:0] cpu_slot_count;
        logic [31:0] ppu_cycle_count;
        logic [31:0] prg_read_count;
        logic [31:0] chr_read_count;
        logic [31:0] missed_capture_count;
    } nes_system_debug_snapshot_t;

    typedef struct packed {
        nes_cpu_debug_snapshot_t        cpu;
        nes_ppu_debug_snapshot_t        ppu;
        nes_cartridge_debug_snapshot_t  cartridge;
        nes_controller_debug_snapshot_t controller;
        nes_dma_debug_snapshot_t        dma;
        nes_system_debug_snapshot_t     system;
    } nes_debug_snapshot_t;

    localparam int unsigned NES_CPU_DEBUG_SNAPSHOT_BITS =
        $bits(nes_cpu_debug_snapshot_t);
    localparam int unsigned NES_PPU_DEBUG_SNAPSHOT_BITS =
        $bits(nes_ppu_debug_snapshot_t);
    localparam int unsigned NES_CARTRIDGE_DEBUG_SNAPSHOT_BITS =
        $bits(nes_cartridge_debug_snapshot_t);
    localparam int unsigned NES_CONTROLLER_DEBUG_SNAPSHOT_BITS =
        $bits(nes_controller_debug_snapshot_t);
    localparam int unsigned NES_DMA_DEBUG_SNAPSHOT_BITS =
        $bits(nes_dma_debug_snapshot_t);
    localparam int unsigned NES_SYSTEM_DEBUG_SNAPSHOT_BITS =
        $bits(nes_system_debug_snapshot_t);
    localparam int unsigned NES_DEBUG_SNAPSHOT_BITS =
        $bits(nes_debug_snapshot_t);
endpackage
