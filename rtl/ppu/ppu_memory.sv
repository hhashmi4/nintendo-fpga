`timescale 1ns/1ps

module ppu_memory (
    input  logic        clk,
    input  logic        reset,

    input  logic [1:0]  mirroring_mode,
    input  logic        access_valid,
    input  logic        access_write,
    input  logic [13:0] access_address,
    input  logic [7:0]  access_write_data,
    output logic [7:0]  access_read_data,

    // Phase 3B palette reads refill PPUDATA from a second, nametable-side
    // address. This read-only port keeps that operation explicit.
    input  logic [13:0] buffer_read_address,
    output logic [7:0]  buffer_read_data,

    // Cartridge-owned CHR space. No CHR storage is instantiated here.
    output logic [12:0] chr_addr,
    output logic        chr_read,
    output logic        chr_write,
    output logic [7:0]  chr_write_data,
    input  logic [7:0]  chr_read_data,

    // Translation observability for verification and later integration.
    output logic [1:0]  access_region,
    output logic [11:0] normalized_nametable_address,
    output logic [1:0]  logical_nametable,
    output logic [9:0]  nametable_offset,
    output logic        physical_ciram_page,
    output logic [10:0] ciram_address,
    output logic [4:0]  palette_index,
    output logic        ciram_write_enable,
    output logic        palette_write_enable
);
    localparam logic [1:0] MIRROR_VERTICAL            = 2'd0;
    localparam logic [1:0] MIRROR_HORIZONTAL          = 2'd1;
    localparam logic [1:0] MIRROR_SINGLE_SCREEN_LOWER = 2'd2;
    localparam logic [1:0] MIRROR_SINGLE_SCREEN_UPPER = 2'd3;

    localparam logic [1:0] REGION_CHR       = 2'd0;
    localparam logic [1:0] REGION_NAMETABLE = 2'd1;
    localparam logic [1:0] REGION_PALETTE   = 2'd2;

    // Cyclone V MLABs support the asynchronous read contract inherited from
    // Phase 3B. CPU writes never consume read data on their accepting edge,
    // so same-address read-during-write data is intentionally unspecified;
    // the next read observes the committed byte. This hint avoids converting
    // the arrays into thousands of reset-free flip-flops.
    (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] ciram [0:2047];
    (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] palette_ram [0:31];

    logic [11:0] buffer_nametable_address;
    logic [1:0] buffer_logical_nametable;
    logic [9:0] buffer_nametable_offset;
    logic buffer_physical_ciram_page;
    logic [10:0] buffer_ciram_address;
    logic [1:0] buffer_region;
    logic [10:0] ciram_read_address;
    logic [7:0] ciram_read_data;

    function automatic logic [1:0] decode_region(input logic [13:0] address);
        if (address < 14'h2000) decode_region = REGION_CHR;
        else if (address < 14'h3f00) decode_region = REGION_NAMETABLE;
        else decode_region = REGION_PALETTE;
    endfunction

    function automatic logic [11:0] normalize_nametable(
        input logic [13:0] address
    );
        if (address >= 14'h3000 && address <= 14'h3eff)
            normalize_nametable = 12'(address - 14'h3000);
        else
            normalize_nametable = 12'(address - 14'h2000);
    endfunction

    function automatic logic select_ciram_page(
        input logic [1:0] mode,
        input logic [1:0] logical_page
    );
        case (mode)
            MIRROR_VERTICAL:            select_ciram_page = logical_page[0];
            MIRROR_HORIZONTAL:          select_ciram_page = logical_page[1];
            MIRROR_SINGLE_SCREEN_LOWER: select_ciram_page = 1'b0;
            MIRROR_SINGLE_SCREEN_UPPER: select_ciram_page = 1'b1;
            default:                    select_ciram_page = 1'b0;
        endcase
    endfunction

    function automatic logic [4:0] normalize_palette(
        input logic [4:0] raw_index
    );
        logic [4:0] index;
        begin
            index = raw_index;
            if (index[4] && index[1:0] == 2'b00) index[4] = 1'b0;
            normalize_palette = index;
        end
    endfunction

    always_comb begin
        access_region = decode_region(access_address);
        normalized_nametable_address = normalize_nametable(access_address);
        logical_nametable = normalized_nametable_address[11:10];
        nametable_offset = normalized_nametable_address[9:0];
        physical_ciram_page = select_ciram_page(
            mirroring_mode, logical_nametable
        );
        ciram_address = {physical_ciram_page, nametable_offset};
        palette_index = normalize_palette(access_address[4:0]);

        buffer_region = decode_region(buffer_read_address);
        buffer_nametable_address = normalize_nametable(buffer_read_address);
        buffer_logical_nametable = buffer_nametable_address[11:10];
        buffer_nametable_offset = buffer_nametable_address[9:0];
        buffer_physical_ciram_page = select_ciram_page(
            mirroring_mode, buffer_logical_nametable
        );
        buffer_ciram_address = {
            buffer_physical_ciram_page, buffer_nametable_offset
        };

        // The auxiliary address is consumed only for the nametable-side
        // refill performed by a palette PPUDATA read. A palette primary read
        // does not consume CIRAM, so one logical read port serves both cases
        // without duplicating the 2 KiB storage.
        ciram_read_address = access_region == REGION_PALETTE ?
                             buffer_ciram_address : ciram_address;
        ciram_read_data = ciram[ciram_read_address];

        chr_addr = access_address[12:0];
        chr_read = !reset && access_valid && !access_write &&
                   access_region == REGION_CHR;
        chr_write = !reset && access_valid && access_write &&
                    access_region == REGION_CHR;
        chr_write_data = access_write_data;

        ciram_write_enable = !reset && access_valid && access_write &&
                             access_region == REGION_NAMETABLE;
        palette_write_enable = !reset && access_valid && access_write &&
                               access_region == REGION_PALETTE;

        case (access_region)
            REGION_CHR:       access_read_data = chr_read_data;
            REGION_NAMETABLE: access_read_data = ciram_read_data;
            REGION_PALETTE:   access_read_data = palette_ram[palette_index];
            default:          access_read_data = 8'h00;
        endcase

        // Valid only alongside a palette primary access. Phase 3B always
        // supplies the corresponding $2Fxx nametable address in that case.
        buffer_read_data = 8'h00;
        if (access_region == REGION_PALETTE &&
            buffer_region == REGION_NAMETABLE)
            buffer_read_data = ciram_read_data;
    end

    // CIRAM and palette contents are intentionally not reset. Original NES
    // software cannot rely on their power-up values, and clearing the arrays
    // would force a large reset network and prevent efficient RAM inference.
    always_ff @(posedge clk) begin
        if (ciram_write_enable)
            ciram[ciram_address] <= access_write_data;
        if (palette_write_enable)
            palette_ram[palette_index] <= access_write_data;
    end
endmodule
