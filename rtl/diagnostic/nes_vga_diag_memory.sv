`timescale 1ns/1ps

// Small cartridge-shaped diagnostic image for the Phase 3K board top. The
// 6502 program initializes palette/nametable/OAM through the real NES buses,
// starts rendering, and moves sprite zero eight NES pixels per NMI. Nothing
// here bypasses the CPU, DMA, PPU, framebuffer, scaler, or palette pipeline.
module nes_vga_diag_memory (
    input  logic [15:0] cpu_address,
    input  logic        cpu_read,
    input  logic        cpu_write,
    input  logic [7:0]  cpu_write_data,
    output logic [7:0]  cpu_read_data,
    input  logic [12:0] chr_address,
    input  logic        chr_read,
    input  logic        chr_write,
    input  logic [7:0]  chr_write_data,
    output logic [7:0]  chr_read_data
);
    logic [7:0] prg_data;
    logic [7:0] chr_data;
    logic [8:0] tile_number;
    logic       pattern_plane;
    logic [2:0] pattern_row;

    always_comb begin
        prg_data = 8'hea;
        case (cpu_address)
            16'h8000: prg_data = 8'h78; 16'h8001: prg_data = 8'hd8;
            16'h8002: prg_data = 8'ha2; 16'h8003: prg_data = 8'h00;
            16'h8004: prg_data = 8'ha9; 16'h8005: prg_data = 8'hff;
            16'h8006: prg_data = 8'h9d; 16'h8007: prg_data = 8'h00;
            16'h8008: prg_data = 8'h02; 16'h8009: prg_data = 8'he8;
            16'h800a: prg_data = 8'hd0; 16'h800b: prg_data = 8'hfa;
            16'h800c: prg_data = 8'ha9; 16'h800d: prg_data = 8'h40;
            16'h800e: prg_data = 8'h8d; 16'h800f: prg_data = 8'h00;
            16'h8010: prg_data = 8'h02; 16'h8011: prg_data = 8'ha9;
            16'h8012: prg_data = 8'h03; 16'h8013: prg_data = 8'h8d;
            16'h8014: prg_data = 8'h01; 16'h8015: prg_data = 8'h02;
            16'h8016: prg_data = 8'ha9; 16'h8017: prg_data = 8'h00;
            16'h8018: prg_data = 8'h8d; 16'h8019: prg_data = 8'h02;
            16'h801a: prg_data = 8'h02; 16'h801b: prg_data = 8'ha9;
            16'h801c: prg_data = 8'h28; 16'h801d: prg_data = 8'h8d;
            16'h801e: prg_data = 8'h03; 16'h801f: prg_data = 8'h02;
            16'h8020: prg_data = 8'ha9; 16'h8021: prg_data = 8'h70;
            16'h8022: prg_data = 8'h8d; 16'h8023: prg_data = 8'h04;
            16'h8024: prg_data = 8'h02; 16'h8025: prg_data = 8'ha9;
            16'h8026: prg_data = 8'h04; 16'h8027: prg_data = 8'h8d;
            16'h8028: prg_data = 8'h05; 16'h8029: prg_data = 8'h02;
            16'h802a: prg_data = 8'ha9; 16'h802b: prg_data = 8'h01;
            16'h802c: prg_data = 8'h8d; 16'h802d: prg_data = 8'h06;
            16'h802e: prg_data = 8'h02; 16'h802f: prg_data = 8'ha9;
            16'h8030: prg_data = 8'h90; 16'h8031: prg_data = 8'h8d;
            16'h8032: prg_data = 8'h07; 16'h8033: prg_data = 8'h02;
            16'h8034: prg_data = 8'ha9; 16'h8035: prg_data = 8'h00;
            16'h8036: prg_data = 8'h8d; 16'h8037: prg_data = 8'h00;
            16'h8038: prg_data = 8'h20; 16'h8039: prg_data = 8'ha9;
            16'h803a: prg_data = 8'h00; 16'h803b: prg_data = 8'h8d;
            16'h803c: prg_data = 8'h01; 16'h803d: prg_data = 8'h20;
            16'h803e: prg_data = 8'ha9; 16'h803f: prg_data = 8'h3f;
            16'h8040: prg_data = 8'h8d; 16'h8041: prg_data = 8'h06;
            16'h8042: prg_data = 8'h20; 16'h8043: prg_data = 8'ha9;
            16'h8044: prg_data = 8'h00; 16'h8045: prg_data = 8'h8d;
            16'h8046: prg_data = 8'h06; 16'h8047: prg_data = 8'h20;
            16'h8048: prg_data = 8'ha2; 16'h8049: prg_data = 8'h00;
            16'h804a: prg_data = 8'hbd; 16'h804b: prg_data = 8'h00;
            16'h804c: prg_data = 8'h81; 16'h804d: prg_data = 8'h8d;
            16'h804e: prg_data = 8'h07; 16'h804f: prg_data = 8'h20;
            16'h8050: prg_data = 8'he8; 16'h8051: prg_data = 8'he0;
            16'h8052: prg_data = 8'h20; 16'h8053: prg_data = 8'hd0;
            16'h8054: prg_data = 8'hf5; 16'h8055: prg_data = 8'ha9;
            16'h8056: prg_data = 8'h20; 16'h8057: prg_data = 8'h8d;
            16'h8058: prg_data = 8'h06; 16'h8059: prg_data = 8'h20;
            16'h805a: prg_data = 8'ha9; 16'h805b: prg_data = 8'h00;
            16'h805c: prg_data = 8'h8d; 16'h805d: prg_data = 8'h06;
            16'h805e: prg_data = 8'h20; 16'h805f: prg_data = 8'ha0;
            16'h8060: prg_data = 8'h04; 16'h8061: prg_data = 8'ha2;
            16'h8062: prg_data = 8'h00; 16'h8063: prg_data = 8'h8a;
            16'h8064: prg_data = 8'h29; 16'h8065: prg_data = 8'h03;
            16'h8066: prg_data = 8'h18; 16'h8067: prg_data = 8'h69;
            16'h8068: prg_data = 8'h01; 16'h8069: prg_data = 8'h8d;
            16'h806a: prg_data = 8'h07; 16'h806b: prg_data = 8'h20;
            16'h806c: prg_data = 8'he8; 16'h806d: prg_data = 8'hd0;
            16'h806e: prg_data = 8'hf4; 16'h806f: prg_data = 8'h88;
            16'h8070: prg_data = 8'hd0; 16'h8071: prg_data = 8'hf1;
            16'h8072: prg_data = 8'ha9; 16'h8073: prg_data = 8'h00;
            16'h8074: prg_data = 8'h8d; 16'h8075: prg_data = 8'h05;
            16'h8076: prg_data = 8'h20; 16'h8077: prg_data = 8'ha9;
            16'h8078: prg_data = 8'h00; 16'h8079: prg_data = 8'h8d;
            16'h807a: prg_data = 8'h05; 16'h807b: prg_data = 8'h20;
            16'h807c: prg_data = 8'ha9; 16'h807d: prg_data = 8'h00;
            16'h807e: prg_data = 8'h8d; 16'h807f: prg_data = 8'h03;
            16'h8080: prg_data = 8'h20; 16'h8081: prg_data = 8'ha9;
            16'h8082: prg_data = 8'h02; 16'h8083: prg_data = 8'h8d;
            16'h8084: prg_data = 8'h14; 16'h8085: prg_data = 8'h40;
            16'h8086: prg_data = 8'ha9; 16'h8087: prg_data = 8'h80;
            16'h8088: prg_data = 8'h8d; 16'h8089: prg_data = 8'h00;
            16'h808a: prg_data = 8'h20; 16'h808b: prg_data = 8'ha9;
            16'h808c: prg_data = 8'h1e; 16'h808d: prg_data = 8'h8d;
            16'h808e: prg_data = 8'h01; 16'h808f: prg_data = 8'h20;
            16'h8090: prg_data = 8'h4c; 16'h8091: prg_data = 8'h90;
            16'h8092: prg_data = 8'h80;

            16'h8100: prg_data = 8'h0f; 16'h8101: prg_data = 8'h01;
            16'h8102: prg_data = 8'h21; 16'h8103: prg_data = 8'h31;
            16'h8104: prg_data = 8'h0f; 16'h8105: prg_data = 8'h06;
            16'h8106: prg_data = 8'h16; 16'h8107: prg_data = 8'h26;
            16'h8108: prg_data = 8'h0f; 16'h8109: prg_data = 8'h09;
            16'h810a: prg_data = 8'h19; 16'h810b: prg_data = 8'h29;
            16'h810c: prg_data = 8'h0f; 16'h810d: prg_data = 8'h0c;
            16'h810e: prg_data = 8'h2c; 16'h810f: prg_data = 8'h3c;
            16'h8110: prg_data = 8'h0f; 16'h8111: prg_data = 8'h2a;
            16'h8112: prg_data = 8'h27; 16'h8113: prg_data = 8'h38;
            16'h8114: prg_data = 8'h0f; 16'h8115: prg_data = 8'h06;
            16'h8116: prg_data = 8'h26; 16'h8117: prg_data = 8'h36;
            16'h8118: prg_data = 8'h0f; 16'h8119: prg_data = 8'h09;
            16'h811a: prg_data = 8'h29; 16'h811b: prg_data = 8'h39;
            16'h811c: prg_data = 8'h0f; 16'h811d: prg_data = 8'h0c;
            16'h811e: prg_data = 8'h2c; 16'h811f: prg_data = 8'h3c;

            16'h9000: prg_data = 8'he6; 16'h9001: prg_data = 8'h04;
            16'h9002: prg_data = 8'had; 16'h9003: prg_data = 8'h03;
            16'h9004: prg_data = 8'h02; 16'h9005: prg_data = 8'h18;
            16'h9006: prg_data = 8'h69; 16'h9007: prg_data = 8'h08;
            16'h9008: prg_data = 8'h8d; 16'h9009: prg_data = 8'h03;
            16'h900a: prg_data = 8'h02; 16'h900b: prg_data = 8'ha9;
            16'h900c: prg_data = 8'h00; 16'h900d: prg_data = 8'h8d;
            16'h900e: prg_data = 8'h03; 16'h900f: prg_data = 8'h20;
            16'h9010: prg_data = 8'ha9; 16'h9011: prg_data = 8'h02;
            16'h9012: prg_data = 8'h8d; 16'h9013: prg_data = 8'h14;
            16'h9014: prg_data = 8'h40; 16'h9015: prg_data = 8'h40;

            16'hfffa: prg_data = 8'h00; 16'hfffb: prg_data = 8'h90;
            16'hfffc: prg_data = 8'h00; 16'hfffd: prg_data = 8'h80;
            16'hfffe: prg_data = 8'h00; 16'hffff: prg_data = 8'h80;
            default: prg_data = 8'hea;
        endcase
    end

    always_comb begin
        tile_number = chr_address[12:4];
        pattern_plane = chr_address[3];
        pattern_row = chr_address[2:0];
        chr_data = 8'h00;
        if (!pattern_plane) begin
            case (tile_number)
                9'd1: chr_data = 8'haa;
                9'd2: chr_data = pattern_row[0] ? 8'hff : 8'h00;
                9'd3: chr_data = 8'hff;
                9'd4: begin
                    case (pattern_row)
                        3'd0, 3'd7: chr_data = 8'h18;
                        3'd1, 3'd6: chr_data = 8'h3c;
                        3'd2, 3'd5: chr_data = 8'h7e;
                        default: chr_data = 8'hff;
                    endcase
                end
                default: chr_data = 8'h00;
            endcase
        end
    end

    // ROM outputs are address-driven. Qualifying the data with the PPU read
    // request would create a combinational request/data loop in ppu_memory.
    assign cpu_read_data = prg_data;
    assign chr_read_data = chr_data;

    // This diagnostic cartridge is ROM-only. Keep write ports explicit so
    // replacing it with a mapper later does not alter nes_core's boundary.
    logic unused_writes;
    assign unused_writes = cpu_read || chr_read ||
                           (cpu_write && ^cpu_write_data) ||
                           (chr_write && ^chr_write_data);
endmodule
