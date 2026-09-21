`timescale 1ns/1ps

// NES CPU/PPU system integration. All state uses the single fabric clock;
// ppu_enable and cpu_cycle_slot are clock enables, never generated clocks.
module nes_core (
    input  logic        clk,
    input  logic        reset,
    input  logic        nes_enable,
    input  logic        irq,

    input  logic [1:0]  mirroring_mode,

    output logic [15:0] cart_cpu_address,
    output logic        cart_cpu_read,
    output logic        cart_cpu_write,
    output logic [7:0]  cart_cpu_write_data,
    input  logic [7:0]  cart_cpu_read_data,

    output logic [15:0] apu_cpu_address,
    output logic        apu_cpu_read,
    output logic        apu_cpu_write,
    output logic [7:0]  apu_cpu_write_data,
    input  logic [7:0]  apu_cpu_read_data,

    output logic        controller_port,
    output logic        controller_cpu_read,
    output logic        controller_cpu_write,
    output logic [7:0]  controller_cpu_write_data,
    input  logic [7:0]  controller_cpu_read_data,

    output logic [12:0] chr_addr,
    output logic        chr_read,
    output logic        chr_write,
    output logic [7:0]  chr_write_data,
    input  logic [7:0]  chr_read_data,

    output logic        ppu_enable,
    output logic        cpu_cycle_slot,
    output logic        cpu_enable,
    output logic [1:0]  scheduler_phase,

    output logic [15:0] cpu_address,
    output logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,
    output logic        cpu_write_enable,
    output logic        cpu_read_enable,
    output logic        cpu_bus_valid,
    output logic [7:0]  cpu_debug_a,
    output logic [7:0]  cpu_debug_x,
    output logic [7:0]  cpu_debug_y,
    output logic [7:0]  cpu_debug_sp,
    output logic [15:0] cpu_debug_pc,
    output logic [7:0]  cpu_debug_status,

    output nes_system_pkg::nes_cpu_target_t cpu_bus_target,
    output logic [10:0] cpu_ram_address,
    output logic [2:0]  cpu_ppu_register,
    output logic        cpu_ram_access,
    output logic        cpu_ppu_access,
    output logic        cpu_apu_access,
    output logic        cpu_dma_access,
    output logic        cpu_controller_access,
    output logic        cpu_cartridge_access,

    output logic        dma_active,
    output logic [2:0]  dma_phase,
    output logic [7:0]  dma_page,
    output logic [7:0]  dma_index,
    output logic [7:0]  dma_data,
    output logic [9:0]  dma_stall_cycles,
    output logic [8:0]  dma_read_count,
    output logic [8:0]  dma_write_count,
    output logic        dma_read_event,
    output logic        dma_write_event,
    output logic        dma_complete_event,

    output logic [8:0]  ppu_dot,
    output logic [8:0]  ppu_scanline,
    output logic        ppu_frame_odd,
    output logic        ppu_frame_start,
    output logic        ppu_frame_end,
    output logic        ppu_status_vblank,
    output logic        ppu_status_sprite_zero_hit,
    output logic        ppu_status_sprite_overflow,
    output logic [7:0]  ppu_ctrl,
    output logic [7:0]  ppu_mask,
    output logic        ppu_nmi_level,
    output logic        ppu_nmi_event,
    output logic        ppu_nmi_suppressed,
    output logic [7:0]  ppu_oam_addr,
    output logic        ppu_oam_write_commit,
    output logic        ppu_oam_collision,

    output logic        pixel_valid,
    output logic [7:0]  pixel_x,
    output logic [7:0]  pixel_y,
    output logic [13:0] pixel_palette_address,
    output logic [5:0]  pixel_nes_color,
    output logic [2:0]  pixel_color_emphasis,
    output logic [1:0]  pixel_source
);
    import nes_system_pkg::*;

    localparam logic [2:0] DMA_IDLE  = 3'd0;
    localparam logic [2:0] DMA_DUMMY = 3'd1;
    localparam logic [2:0] DMA_ALIGN = 3'd2;
    localparam logic [2:0] DMA_READ  = 3'd3;
    localparam logic [2:0] DMA_WRITE = 3'd4;

    logic cpu_cycle_parity;
    logic dma_start_odd;
    logic [15:0] dma_source_address;
    logic [7:0] dma_source_read_data;
    logic [10:0] shared_ram_read_address;
    logic [7:0] cpu_ram_read_data;
    nes_cpu_target_t dma_source_target;
    logic [10:0] dma_ram_address;
    logic [2:0] dma_ppu_register;

    logic [7:0] ppu_cpu_read_data;
    logic ppu_cpu_enable;
    logic ppu_cpu_valid;
    logic ppu_cpu_write;
    logic [15:0] ppu_cpu_address;
    logic [7:0] ppu_cpu_write_data;

    logic cpu_ram_read;
    logic cpu_ram_write;
    logic [15:0] bus_ppu_address;
    logic bus_ppu_read;
    logic bus_ppu_write;
    logic bus_dma_write;
    logic [7:0] bus_dma_write_data;
    logic [15:0] bus_cart_address;
    logic bus_cart_read;
    logic bus_cart_write;
    logic [7:0] bus_cart_write_data;
    logic dma_trigger;

    logic [7:0] unused_cpu_instruction;
    logic [5:0] unused_cpu_execution_state;
    logic [5:0] unused_cpu_decoded_instruction;
    logic [3:0] unused_cpu_addressing_mode;
    logic [15:0] unused_cpu_effective_address;
    logic unused_cpu_page_cross;
    logic unused_cpu_page_cross_valid;

    assign ppu_enable = !reset && nes_enable;
    assign cpu_cycle_slot = ppu_enable && scheduler_phase == 2'd2;
    assign cpu_enable = cpu_cycle_slot && !dma_active;
    assign cpu_read_enable = !reset && cpu_bus_valid && !cpu_write_enable;

    assign dma_trigger = bus_dma_write;

    assign dma_source_address = {dma_page, dma_index};

    nes_cpu_address_decoder dma_source_decoder (
        .address      (dma_source_address),
        .write_enable(1'b0),
        .target       (dma_source_target),
        .ram_address  (dma_ram_address),
        .ppu_register (dma_ppu_register)
    );

    // The CPU is stalled during DMA, so one muxed registered read port is
    // sufficient for both clients and avoids replicating the 2 KiB RAM.
    assign shared_ram_read_address = dma_active && dma_phase == DMA_READ ?
                                     dma_ram_address :
                                     cpu_ram_address;

    nes_cpu_ram internal_cpu_ram (
        .clk          (clk),
        .read_address (shared_ram_read_address),
        .read_data    (cpu_ram_read_data),
        .write_enable (cpu_ram_write),
        .write_address(cpu_ram_address),
        .write_data   (cpu_write_data)
    );

    nes_cpu_bus system_bus (
        .reset                    (reset),
        .cpu_enable               (cpu_enable),
        .cpu_bus_valid            (cpu_bus_valid),
        .cpu_address              (cpu_address),
        .cpu_write_data           (cpu_write_data),
        .cpu_write_enable         (cpu_write_enable),
        .cpu_read_data            (cpu_read_data),
        .selected_target          (cpu_bus_target),
        .ram_address              (cpu_ram_address),
        .ppu_register             (cpu_ppu_register),
        .ram_read_data            (cpu_ram_read_data),
        .ram_read                 (cpu_ram_read),
        .ram_write                (cpu_ram_write),
        .ppu_read_data            (ppu_cpu_read_data),
        .ppu_address              (bus_ppu_address),
        .ppu_read                 (bus_ppu_read),
        .ppu_write                (bus_ppu_write),
        .apu_read_data            (apu_cpu_read_data),
        .apu_address              (apu_cpu_address),
        .apu_read                 (apu_cpu_read),
        .apu_write                (apu_cpu_write),
        .apu_write_data           (apu_cpu_write_data),
        .dma_select               (cpu_dma_access),
        .dma_write                (bus_dma_write),
        .dma_write_data           (bus_dma_write_data),
        .controller_read_data     (controller_cpu_read_data),
        .controller_port          (controller_port),
        .controller_read          (controller_cpu_read),
        .controller_write         (controller_cpu_write),
        .controller_write_data    (controller_cpu_write_data),
        .cartridge_read_data      (cart_cpu_read_data),
        .cartridge_address        (bus_cart_address),
        .cartridge_read           (bus_cart_read),
        .cartridge_write          (bus_cart_write),
        .cartridge_write_data     (bus_cart_write_data),
        .ram_access               (cpu_ram_access),
        .ppu_access               (cpu_ppu_access),
        .apu_access               (cpu_apu_access),
        .controller_access        (cpu_controller_access),
        .cartridge_access         (cpu_cartridge_access)
    );

    always_comb begin
        dma_source_read_data = 8'h00;
        case (dma_source_target)
            NES_CPU_TARGET_RAM: dma_source_read_data = cpu_ram_read_data;
            NES_CPU_TARGET_PPU: dma_source_read_data = ppu_cpu_read_data;
            NES_CPU_TARGET_CARTRIDGE:
                dma_source_read_data = cart_cpu_read_data;
            default: dma_source_read_data = 8'h00;
        endcase
    end

    always_comb begin
        // The real CPU owns the PPU register port except for DMA source reads
        // from $2000-$3fff and DMA destination writes to $2004.
        ppu_cpu_enable = cpu_enable;
        ppu_cpu_valid = bus_ppu_read || bus_ppu_write;
        ppu_cpu_write = bus_ppu_write;
        ppu_cpu_address = bus_ppu_address;
        ppu_cpu_write_data = cpu_write_data;
        if (dma_active) begin
            ppu_cpu_enable = cpu_cycle_slot;
            ppu_cpu_valid = 1'b0;
            ppu_cpu_write = 1'b0;
            ppu_cpu_address = {13'h400, dma_ppu_register};
            ppu_cpu_write_data = 8'h00;
            if (dma_phase == DMA_READ &&
                dma_source_target == NES_CPU_TARGET_PPU) begin
                ppu_cpu_valid = 1'b1;
            end else if (dma_phase == DMA_WRITE) begin
                ppu_cpu_valid = 1'b1;
                ppu_cpu_write = 1'b1;
                ppu_cpu_address = 16'h2004;
                ppu_cpu_write_data = dma_data;
            end
        end
    end

    always_comb begin
        cart_cpu_address = bus_cart_address;
        cart_cpu_read = bus_cart_read;
        cart_cpu_write = bus_cart_write;
        cart_cpu_write_data = bus_cart_write_data;
        if (dma_active && dma_phase == DMA_READ && cpu_cycle_slot &&
            dma_source_target == NES_CPU_TARGET_CARTRIDGE) begin
            cart_cpu_address = dma_source_address;
            cart_cpu_read = 1'b1;
            cart_cpu_write = 1'b0;
            cart_cpu_write_data = 8'h00;
        end
    end

    assign dma_read_event = dma_active && cpu_cycle_slot &&
                            dma_phase == DMA_READ;
    assign dma_write_event = dma_active && cpu_cycle_slot &&
                             dma_phase == DMA_WRITE;

    always_ff @(posedge clk) begin
        if (reset) begin
            scheduler_phase   <= 2'd0;
            cpu_cycle_parity  <= 1'b0;
            dma_active        <= 1'b0;
            dma_phase         <= DMA_IDLE;
            dma_page          <= 8'h00;
            dma_index         <= 8'h00;
            dma_data          <= 8'h00;
            dma_start_odd     <= 1'b0;
            dma_stall_cycles  <= 10'd0;
            dma_read_count    <= 9'd0;
            dma_write_count   <= 9'd0;
            dma_complete_event <= 1'b0;
        end else begin
            dma_complete_event <= 1'b0;

            if (nes_enable)
                scheduler_phase <= scheduler_phase == 2'd2 ? 2'd0 :
                                   scheduler_phase + 2'd1;

            if (cpu_cycle_slot)
                cpu_cycle_parity <= !cpu_cycle_parity;

            if (dma_trigger) begin
                dma_active       <= 1'b1;
                dma_phase        <= DMA_DUMMY;
                dma_page         <= bus_dma_write_data;
                dma_index        <= 8'h00;
                dma_start_odd    <= cpu_cycle_parity;
                dma_stall_cycles <= 10'd0;
                dma_read_count   <= 9'd0;
                dma_write_count  <= 9'd0;
            end else if (dma_active && cpu_cycle_slot) begin
                dma_stall_cycles <= dma_stall_cycles + 10'd1;
                case (dma_phase)
                    DMA_DUMMY: begin
                        dma_phase <= dma_start_odd ? DMA_ALIGN : DMA_READ;
                    end
                    DMA_ALIGN: dma_phase <= DMA_READ;
                    DMA_READ: begin
                        dma_data <= dma_source_read_data;
                        dma_read_count <= dma_read_count + 9'd1;
                        dma_phase <= DMA_WRITE;
                    end
                    DMA_WRITE: begin
                        dma_write_count <= dma_write_count + 9'd1;
                        if (dma_index == 8'hff) begin
                            dma_active <= 1'b0;
                            dma_phase <= DMA_IDLE;
                            dma_complete_event <= 1'b1;
                        end else begin
                            dma_index <= dma_index + 8'd1;
                            dma_phase <= DMA_READ;
                        end
                    end
                    default: begin
                        dma_active <= 1'b0;
                        dma_phase <= DMA_IDLE;
                    end
                endcase
            end
        end
    end

    cpu_core cpu (
        .clk                    (clk),
        .reset                  (reset),
        .cpu_enable             (cpu_enable),
        .nmi                    (ppu_nmi_level),
        .irq                    (irq),
        .bus_address            (cpu_address),
        .bus_write_data         (cpu_write_data),
        .bus_read_data          (cpu_read_data),
        .bus_write_enable       (cpu_write_enable),
        .bus_valid              (cpu_bus_valid),
        .debug_a                (cpu_debug_a),
        .debug_x                (cpu_debug_x),
        .debug_y                (cpu_debug_y),
        .debug_sp               (cpu_debug_sp),
        .debug_pc               (cpu_debug_pc),
        .debug_status           (cpu_debug_status),
        .debug_instruction      (unused_cpu_instruction),
        .debug_execution_state  (unused_cpu_execution_state),
        .debug_decoded_instruction(unused_cpu_decoded_instruction),
        .debug_addressing_mode  (unused_cpu_addressing_mode),
        .debug_effective_address(unused_cpu_effective_address),
        .debug_page_cross       (unused_cpu_page_cross),
        .debug_page_cross_valid (unused_cpu_page_cross_valid)
    );

    /* verilator lint_off PINMISSING */
    ppu_sprite_core ppu (
        .clk                    (clk),
        .reset                  (reset),
        .ppu_enable             (ppu_enable),
        .cpu_enable             (ppu_cpu_enable),
        .cpu_bus_valid          (ppu_cpu_valid),
        .cpu_bus_write          (ppu_cpu_write),
        .cpu_address            (ppu_cpu_address),
        .cpu_write_data         (ppu_cpu_write_data),
        .cpu_read_data          (ppu_cpu_read_data),
        .oam_addr               (ppu_oam_addr),
        .mirroring_mode         (mirroring_mode),
        .chr_addr               (chr_addr),
        .chr_read               (chr_read),
        .chr_write              (chr_write),
        .chr_write_data         (chr_write_data),
        .chr_read_data          (chr_read_data),
        .dot                    (ppu_dot),
        .scanline               (ppu_scanline),
        .frame_odd              (ppu_frame_odd),
        .frame_start            (ppu_frame_start),
        .frame_end              (ppu_frame_end),
        .ppuctrl                (ppu_ctrl),
        .ppumask                (ppu_mask),
        .status_vblank          (ppu_status_vblank),
        .status_sprite_zero_hit (ppu_status_sprite_zero_hit),
        .status_sprite_overflow (ppu_status_sprite_overflow),
        .ppu_nmi_level          (ppu_nmi_level),
        .ppu_nmi_event          (ppu_nmi_event),
        .ppu_nmi_suppressed     (ppu_nmi_suppressed),
        .final_pixel_valid      (pixel_valid),
        .final_pixel_x          (pixel_x),
        .final_pixel_y          (pixel_y),
        .final_palette_address  (pixel_palette_address),
        .final_nes_color        (pixel_nes_color),
        .final_color_emphasis   (pixel_color_emphasis),
        .final_pixel_source     (pixel_source),
        .secondary_read_slot    (3'd0),
        .cpu_oam_write_commit   (ppu_oam_write_commit),
        .cpu_oam_collision      (ppu_oam_collision)
    );
    /* verilator lint_on PINMISSING */

`ifndef SYNTHESIS
    logic [1:0] previous_scheduler_phase;
    logic previous_dma_active;
    logic previous_nes_enable;

    always_ff @(posedge clk) begin
        if (reset) begin
            previous_scheduler_phase <= 2'd2;
            previous_dma_active <= 1'b0;
            previous_nes_enable <= 1'b1;
        end else begin
            assert (scheduler_phase <= 2'd2);
            assert (scheduler_phase ==
                    (previous_nes_enable ?
                     (previous_scheduler_phase == 2'd2 ? 2'd0 :
                      previous_scheduler_phase + 2'd1) :
                     previous_scheduler_phase));
            assert (!(cpu_enable && dma_active));
            assert (!(cart_cpu_read && cart_cpu_write));
            assert (!(cpu_ram_read && cpu_ram_write));
            assert (!(dma_read_event && dma_write_event));
            assert (dma_phase <= DMA_WRITE);
            if (dma_write_event)
                assert (ppu_cpu_enable && ppu_cpu_valid && ppu_cpu_write &&
                        ppu_cpu_address == 16'h2004);
            if (dma_complete_event) begin
                assert (dma_read_count == 9'd256);
                assert (dma_write_count == 9'd256);
                assert (dma_stall_cycles == (dma_start_odd ? 10'd514 :
                                                              10'd513));
            end
            if (previous_dma_active && dma_active)
                assert (!cpu_enable);
            previous_scheduler_phase <= scheduler_phase;
            previous_dma_active <= dma_active;
            previous_nes_enable <= nes_enable;
        end
    end
`endif
endmodule
