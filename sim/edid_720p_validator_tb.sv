`timescale 1ns/1ps

module edid_720p_validator_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic byte_valid = 1'b0;
    logic [7:0] byte_index = '0;
    logic [7:0] byte_data = '0;
    logic finish = 1'b0;
    logic busy, done, edid_valid, mode_supported;
    logic [7:0] image [0:255];
    integer failures = 0;
    integer index;
    integer checksum;

    always #5 clk = !clk;

    edid_720p_validator dut (.*);

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $display("FAIL: %s", message);
            failures = failures + 1;
        end
    endtask

    task automatic prepare_cta(input logic include_vic4);
        begin
            for (index = 0; index < 256; index = index + 1)
                image[index] = 8'h00;
            image[0] = 8'h00;
            for (index = 1; index <= 6; index = index + 1)
                image[index] = 8'hff;
            image[7] = 8'h00;
            image[18] = 8'h01;
            image[19] = 8'h04;
            image[126] = 8'h01;
            checksum = 0;
            for (index = 0; index < 127; index = index + 1)
                checksum = checksum + integer'(image[index]);
            image[127] = 8'(-checksum);
            image[128] = 8'h02;
            image[129] = 8'h03;
            image[130] = 8'h06;
            image[131] = 8'h00;
            image[132] = 8'h41;
            image[133] = include_vic4 ? 8'h84 : 8'h90;
            checksum = 0;
            for (index = 128; index < 255; index = index + 1)
                checksum = checksum + integer'(image[index]);
            image[255] = 8'(-checksum);
        end
    endtask

    task automatic submit(input integer byte_count);
        integer byte_number;
        integer wait_cycles;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            check(busy, "validator reports busy while collecting bytes");
            for (byte_number = 0; byte_number < byte_count;
                 byte_number = byte_number + 1) begin
                byte_valid = 1'b1;
                byte_index = 8'(byte_number);
                byte_data = image[byte_number];
                @(negedge clk);
            end
            byte_valid = 1'b0;
            finish = 1'b1;
            @(negedge clk);
            finish = 1'b0;
            wait_cycles = 0;
            while (!done && wait_cycles < 300) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
            check(done, "validator completes within bound");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        prepare_cta(1'b1);
        submit(256);
        check(edid_valid, "valid EDID header and checksums");
        check(mode_supported, "CTA VIC 4 identifies 720p60");

        prepare_cta(1'b1);
        image[200] = 8'h01;
        submit(256);
        check(!edid_valid, "malformed extension checksum is rejected");
        check(!mode_supported, "malformed EDID cannot enable a mode");

        prepare_cta(1'b0);
        submit(256);
        check(edid_valid, "unsupported-mode EDID remains structurally valid");
        check(!mode_supported, "missing VIC 4 is unsupported");

        // A base-block detailed timing can independently identify 720p60.
        prepare_cta(1'b0);
        image[126] = 8'h00;
        image[54] = 8'h01;
        image[55] = 8'h1d;
        image[56] = 8'h00;
        image[57] = 8'h72;
        image[58] = 8'h51;
        image[59] = 8'hd0;
        image[60] = 8'h1e;
        image[61] = 8'h20;
        checksum = 0;
        for (index = 0; index < 127; index = index + 1)
            checksum = checksum + integer'(image[index]);
        image[127] = 8'(-checksum);
        submit(128);
        check(edid_valid && mode_supported,
              "base detailed timing identifies exact 720p60 totals");

        if (failures == 0) begin
            $display("Phase 6C EDID validation test passed");
            $finish;
        end else begin
            $fatal(1, "Phase 6C EDID validation failed: %0d checks", failures);
        end
    end
endmodule
