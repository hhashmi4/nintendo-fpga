`timescale 1ns/1ps

// Behavioral external transmitter/EDID endpoint, not synthesizable hardware.
// Transaction direction is observed at the existing I2C master boundary;
// every address, payload byte, ACK and repeated START travels over the pins.
module phase6g_hdmi_sink (
    input logic scl, sda, read_transaction,
    output logic drive_low = 0
);
    logic [7:0] registers [0:255];
    logic [7:0] edid [0:255];
    task automatic start;
        @(negedge sda);
        while (!scl) @(negedge sda);
    endtask
    task automatic stop;
        @(posedge sda);
        while (!scl) @(posedge sda);
    endtask
    task automatic receive(output logic [7:0] value);
        for (integer bit_index = 7; bit_index >= 0; bit_index--) begin
            @(posedge scl); value[bit_index] = sda;
        end
        @(negedge scl); drive_low = 1;
        @(posedge scl);
        @(negedge scl); drive_low = 0;
    endtask
    task automatic transmit(input logic [7:0] value);
        for (integer bit_index = 7; bit_index >= 0; bit_index--) begin
            drive_low = !value[bit_index];
            @(posedge scl); @(negedge scl);
        end
        drive_low = 0;
        @(posedge scl);
        if (!sda) $fatal(1, "HDMI receiver expected final master NACK");
        @(negedge scl);
    endtask
    initial begin
        integer checksum;
        logic [7:0] address, reg_address, value;
        for (integer i = 0; i < 256; i++) begin
            registers[i] = 8'(i ^ 8'ha5); edid[i] = 0;
        end
        registers[8'h96] = 8'h04;
        for (integer i = 1; i <= 6; i++) edid[i] = 8'hff;
        edid[18] = 1; edid[19] = 4; edid[126] = 1;
        edid[128] = 2; edid[129] = 3; edid[130] = 6;
        edid[131] = 8'h40; // CTA basic audio: stereo LPCM, including 48 kHz
        edid[132] = 8'h41; edid[133] = 8'h84; // VIC 4, 720p60
        for (integer block_index = 0; block_index < 2; block_index++) begin
            checksum = 0;
            for (integer i = 0; i < 127; i++) checksum += 32'(edid[block_index*128+i]);
            edid[block_index*128+127] = 8'(-checksum);
        end
        forever begin
            start(); receive(address); receive(reg_address);
            if (address != 8'h72 && address != 8'h7e)
                $fatal(1, "unexpected HDMI slave address %h", address);
            if (read_transaction) begin
                start(); receive(value);
                if (value != (address | 8'h01)) $fatal(1, "bad repeated START address");
                transmit(address == 8'h72 ? registers[reg_address] : edid[reg_address]);
            end else begin
                receive(value);
                if (address != 8'h72) $fatal(1, "unexpected EDID write");
                registers[reg_address] = value;
            end
            stop();
        end
    end
endmodule
