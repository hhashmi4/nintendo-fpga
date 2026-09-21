`timescale 1ns/1ps

// Mapper 0/NROM memory implementation. CPU and PPU addresses are registered
// on the 50 MHz fabric clock; the existing clock-enable schedule leaves the
// mapped data stable before either core accepts its next bus cycle.
module nes_mapper0 #(
    parameter integer PRG_ROM_BYTES = 16384,
    parameter bit     CHR_IS_RAM = 1'b0,
    parameter bit     PRG_RAM_ENABLE = 1'b0,
    parameter string  PRG_INIT_FILE = "",
    parameter string  CHR_INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        reset,

    input  logic [15:0] cpu_address,
    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,

    input  logic [12:0] chr_address,
    input  logic        chr_read,
    input  logic        chr_write,
    input  logic [7:0]  chr_write_data,
    output logic [7:0]  chr_read_data,

    output logic [14:0] debug_prg_address,
    output logic [7:0]  debug_prg_data,
    output logic [12:0] debug_chr_address,
    output logic [7:0]  debug_chr_data,
    output logic        debug_prg_read,
    output logic        debug_prg_write,
    output logic        debug_prg_ram_read,
    output logic        debug_prg_ram_write,
    output logic        debug_chr_read,
    output logic        debug_chr_write
);
    localparam integer PRG_ADDRESS_BITS =
        PRG_ROM_BYTES == 16384 ? 14 : 15;

    (* ramstyle = "M10K" *) logic [7:0] prg_rom
        [0:PRG_ROM_BYTES-1];
    (* ramstyle = "M10K" *) logic [7:0] chr_memory [0:8191];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] prg_ram [0:8191];

    logic [14:0] mapped_prg_address;
    logic [7:0] prg_rom_data;
    logic [7:0] prg_ram_data;
    logic [7:0] chr_memory_data;

`ifndef ALTERA_SYNTHESIS
    integer initialize_index;
`endif
    initial begin
`ifndef ALTERA_SYNTHESIS
        for (initialize_index = 0;
             initialize_index < PRG_ROM_BYTES;
             initialize_index = initialize_index + 1)
            prg_rom[initialize_index] = 8'h00;
`endif
`ifdef ALTERA_SYNTHESIS
        // Quartus 23.1 accepts only literal readmemh paths, while Verilator
        // accepts the reusable filename parameters used by the test suite.
        // The board build regenerates these project-owned artifacts first.
        $readmemh("../build/cartridge/phase4db_playable_nrom128.prg.hex",
                  prg_rom);
`else
        $readmemh(PRG_INIT_FILE, prg_rom);
`endif

`ifndef ALTERA_SYNTHESIS
        for (initialize_index = 0; initialize_index < 8192;
             initialize_index = initialize_index + 1)
            chr_memory[initialize_index] = 8'h00;
`endif
        if (!CHR_IS_RAM) begin
`ifdef ALTERA_SYNTHESIS
            $readmemh("../build/cartridge/phase4db_playable_nrom128.chr.hex",
                      chr_memory);
`else
            $readmemh(CHR_INIT_FILE, chr_memory);
`endif
        end
    end

    always_comb begin
        if (PRG_ROM_BYTES == 16384)
            mapped_prg_address = {1'b0, cpu_address[13:0]};
        else
            mapped_prg_address = cpu_address[14:0];
    end

    always_comb begin
        cpu_read_data = 8'h00;
        if (!reset) begin
            if (cpu_address >= 16'h8000)
                cpu_read_data = prg_rom_data;
            else if (PRG_RAM_ENABLE && cpu_address >= 16'h6000 &&
                     cpu_address <= 16'h7fff)
                cpu_read_data = prg_ram_data;
        end
        chr_read_data = reset ? 8'h00 : chr_memory_data;
    end

    assign debug_prg_address = mapped_prg_address;
    assign debug_prg_data = cpu_read_data;
    assign debug_chr_address = chr_address;
    assign debug_chr_data = chr_read_data;
    assign debug_prg_read = !reset && cpu_read && cpu_address >= 16'h8000;
    assign debug_prg_write = !reset && cpu_write && cpu_address >= 16'h8000;
    assign debug_prg_ram_read = !reset && cpu_read &&
                                cpu_address >= 16'h6000 &&
                                cpu_address <= 16'h7fff;
    assign debug_prg_ram_write = !reset && cpu_write &&
                                 cpu_address >= 16'h6000 &&
                                 cpu_address <= 16'h7fff;
    assign debug_chr_read = !reset && chr_read;
    assign debug_chr_write = !reset && chr_write;

    always_ff @(posedge clk) begin
        // These registered reads use Quartus' canonical synchronous-memory
        // inference pattern. The existing CPU/PPU clock-enable schedule
        // establishes each address at least one fabric cycle before consuming
        // the byte, so no console-visible cycle is added.
        prg_rom_data <=
            prg_rom[mapped_prg_address[PRG_ADDRESS_BITS-1:0]];
        prg_ram_data <= prg_ram[cpu_address[12:0]];
        chr_memory_data <= chr_memory[chr_address];

        if (!reset) begin
            if (PRG_RAM_ENABLE && cpu_write &&
                cpu_address >= 16'h6000 && cpu_address <= 16'h7fff)
                prg_ram[cpu_address[12:0]] <= cpu_write_data;
            if (CHR_IS_RAM && chr_write)
                chr_memory[chr_address] <= chr_write_data;
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (PRG_ROM_BYTES == 16384 || PRG_ROM_BYTES == 32768)
            else $fatal(1, "Mapper 0 PRG ROM must be 16 KiB or 32 KiB");
    end

    always_comb begin
        assert (!(cpu_read && cpu_write));
        assert (!(chr_read && chr_write));
    end
`endif
endmodule
