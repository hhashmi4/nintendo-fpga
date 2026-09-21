`timescale 1ns/1ps

package nes_system_pkg;
    typedef enum logic [2:0] {
        NES_CPU_TARGET_NONE       = 3'd0,
        NES_CPU_TARGET_RAM        = 3'd1,
        NES_CPU_TARGET_PPU        = 3'd2,
        NES_CPU_TARGET_APU        = 3'd3,
        NES_CPU_TARGET_DMA        = 3'd4,
        NES_CPU_TARGET_CONTROLLER = 3'd5,
        NES_CPU_TARGET_CARTRIDGE  = 3'd6
    } nes_cpu_target_t;

    typedef enum logic [1:0] {
        NES_BUS_MASTER_NONE = 2'd0,
        NES_BUS_MASTER_CPU  = 2'd1,
        NES_BUS_MASTER_DMA  = 2'd2
    } nes_bus_master_t;

    typedef enum logic [2:0] {
        NES_DMA_IDLE  = 3'd0,
        NES_DMA_DUMMY = 3'd1,
        NES_DMA_ALIGN = 3'd2,
        NES_DMA_READ  = 3'd3,
        NES_DMA_WRITE = 3'd4
    } nes_dma_phase_t;
endpackage
