`timescale 1ns/1ps

module cpu_address_gen_tb;
    import cpu_pkg::*;

    localparam int unsigned EXPECTED_VECTOR_COUNT = 1_508_186;
    localparam logic [15:0] BOUNDARY_ADDRESSES [0:9] = '{
        16'h0000, 16'h0001, 16'h00FE, 16'h00FF, 16'h0100,
        16'h7FFF, 16'h8000, 16'hFF00, 16'hFFFE, 16'hFFFF
    };
    localparam logic [7:0] HIGH_BYTE_SAMPLES [0:5] = '{
        8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF
    };
    localparam logic [7:0] RELATIVE_OFFSETS [0:6] = '{
        8'h00, 8'h01, 8'h7F, 8'h80, 8'h81, 8'hFE, 8'hFF
    };

    cpu_address_request_t request = '0;
    cpu_address_result_t response;
    int unsigned vector_count = 0;

    cpu_address_gen dut (
        .request  (request),
        .response (response)
    );

    task automatic apply_and_check(
        input cpu_address_request_t requested,
        input cpu_address_result_t expected
    );
        request = requested;
        #1;

        assert (!$isunknown(response))
            else $fatal(1, "unknown address-generator output: request=%h",
                        requested);
        assert (response == expected)
            else $fatal(1,
                        "address mismatch: request=%h expected=%h actual=%h",
                        requested, expected, response);
        vector_count++;
    endtask

    initial begin
        cpu_address_request_t requested;
        cpu_address_result_t expected;
        int signed signed_offset;
        int signed target_value;
        int unsigned base_value;
        int unsigned pointer_value;

        $dumpfile("build/sim/cpu_address_gen.fst");
        $dumpvars(0, cpu_address_gen_tb);

        requested = '0;
        requested.addressing_mode = CPU_ADDR_IMPLIED;
        expected = '0;
        expected.is_implied = 1'b1;
        expected.mode_valid = 1'b1;
        apply_and_check(requested, expected);

        requested = '0;
        requested.addressing_mode = CPU_ADDR_ACCUMULATOR;
        expected = '0;
        expected.uses_accumulator = 1'b1;
        expected.mode_valid = 1'b1;
        apply_and_check(requested, expected);

        for (int unsigned operand = 0; operand < 256; operand++) begin
            requested = '0;
            requested.addressing_mode = CPU_ADDR_IMMEDIATE;
            requested.operand_byte = 8'(operand);
            expected = '0;
            expected.immediate_value = 8'(operand);
            expected.immediate_valid = 1'b1;
            expected.mode_valid = 1'b1;
            expected.result_valid = 1'b1;
            apply_and_check(requested, expected);

            requested.addressing_mode = CPU_ADDR_ZERO_PAGE;
            expected = '0;
            expected.effective_address = {8'h00, 8'(operand)};
            expected.effective_address_valid = 1'b1;
            expected.mode_valid = 1'b1;
            expected.result_valid = 1'b1;
            apply_and_check(requested, expected);
        end

        for (int unsigned operand = 0; operand < 256; operand++) begin
            for (int unsigned index_value = 0;
                 index_value < 256; index_value++) begin
                requested = '0;
                requested.addressing_mode = CPU_ADDR_ZERO_PAGE_X;
                requested.operand_byte = 8'(operand);
                requested.x_index = 8'(index_value);
                expected = '0;
                expected.effective_address = {
                    8'h00, 8'(operand + index_value)
                };
                expected.effective_address_valid = 1'b1;
                expected.mode_valid = 1'b1;
                expected.result_valid = 1'b1;
                apply_and_check(requested, expected);

                requested = '0;
                requested.addressing_mode = CPU_ADDR_ZERO_PAGE_Y;
                requested.operand_byte = 8'(operand);
                requested.y_index = 8'(index_value);
                expected = '0;
                expected.effective_address = {
                    8'h00, 8'(operand + index_value)
                };
                expected.effective_address_valid = 1'b1;
                expected.mode_valid = 1'b1;
                expected.result_valid = 1'b1;
                apply_and_check(requested, expected);
            end
        end

        for (int unsigned boundary = 0; boundary < 10; boundary++) begin
            requested = '0;
            requested.addressing_mode = CPU_ADDR_ABSOLUTE;
            requested.base_address = BOUNDARY_ADDRESSES[boundary];
            expected = '0;
            expected.effective_address = BOUNDARY_ADDRESSES[boundary];
            expected.effective_address_valid = 1'b1;
            expected.mode_valid = 1'b1;
            expected.result_valid = 1'b1;
            apply_and_check(requested, expected);
        end

        for (int unsigned high_sample = 0;
             high_sample < 6; high_sample++) begin
            for (int unsigned low_byte = 0; low_byte < 256; low_byte++) begin
                base_value = (int'(HIGH_BYTE_SAMPLES[high_sample]) << 8)
                           | low_byte;
                for (int unsigned index_value = 0;
                     index_value < 256; index_value++) begin
                    requested = '0;
                    requested.addressing_mode = CPU_ADDR_ABSOLUTE_X;
                    requested.base_address = 16'(base_value);
                    requested.x_index = 8'(index_value);
                    expected = '0;
                    expected.effective_address =
                        16'(base_value + index_value);
                    expected.effective_address_valid = 1'b1;
                    expected.indexed_tentative_address = {
                        8'(base_value >> 8), 8'(low_byte + index_value)
                    };
                    expected.indexed_tentative_valid = 1'b1;
                    expected.page_cross = (low_byte + index_value) > 255;
                    expected.page_cross_valid = 1'b1;
                    expected.mode_valid = 1'b1;
                    expected.result_valid = 1'b1;
                    apply_and_check(requested, expected);

                    requested = '0;
                    requested.addressing_mode = CPU_ADDR_ABSOLUTE_Y;
                    requested.base_address = 16'(base_value);
                    requested.y_index = 8'(index_value);
                    expected = '0;
                    expected.effective_address =
                        16'(base_value + index_value);
                    expected.effective_address_valid = 1'b1;
                    expected.indexed_tentative_address = {
                        8'(base_value >> 8), 8'(low_byte + index_value)
                    };
                    expected.indexed_tentative_valid = 1'b1;
                    expected.page_cross = (low_byte + index_value) > 255;
                    expected.page_cross_valid = 1'b1;
                    expected.mode_valid = 1'b1;
                    expected.result_valid = 1'b1;
                    apply_and_check(requested, expected);
                end
            end
        end

        for (int unsigned pointer = 0; pointer < 65_536; pointer++) begin
            requested = '0;
            requested.addressing_mode = CPU_ADDR_INDIRECT;
            requested.base_address = 16'(pointer);
            requested.pointer_low_byte = 8'(pointer ^ 16'h005A);
            requested.pointer_high_byte = 8'((pointer >> 8) ^ 8'hA5);
            requested.pointer_data_valid = 1'b1;
            expected = '0;
            expected.effective_address = {
                requested.pointer_high_byte, requested.pointer_low_byte
            };
            expected.effective_address_valid = 1'b1;
            expected.pointer_low_address = 16'(pointer);
            expected.pointer_high_address = {
                8'(pointer >> 8), 8'(pointer + 1)
            };
            expected.pointer_addresses_valid = 1'b1;
            expected.mode_valid = 1'b1;
            expected.result_valid = 1'b1;
            apply_and_check(requested, expected);
        end

        requested = '0;
        requested.addressing_mode = CPU_ADDR_INDIRECT;
        requested.base_address = 16'h12FF;
        requested.pointer_low_byte = 8'hCD;
        requested.pointer_high_byte = 8'hAB;
        expected = '0;
        expected.pointer_low_address = 16'h12FF;
        expected.pointer_high_address = 16'h1200;
        expected.pointer_addresses_valid = 1'b1;
        expected.mode_valid = 1'b1;
        apply_and_check(requested, expected);

        for (int unsigned operand = 0; operand < 256; operand++) begin
            for (int unsigned index_value = 0;
                 index_value < 256; index_value++) begin
                requested = '0;
                requested.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X;
                requested.operand_byte = 8'(operand);
                requested.x_index = 8'(index_value);
                requested.pointer_low_byte = 8'(operand ^ 8'h5A);
                requested.pointer_high_byte = 8'(index_value ^ 8'hA5);
                requested.pointer_data_valid = 1'b1;
                expected = '0;
                expected.effective_address = {
                    requested.pointer_high_byte, requested.pointer_low_byte
                };
                expected.effective_address_valid = 1'b1;
                expected.pointer_low_address = {
                    8'h00, 8'(operand + index_value)
                };
                expected.pointer_high_address = {
                    8'h00, 8'(operand + index_value + 1)
                };
                expected.pointer_addresses_valid = 1'b1;
                expected.mode_valid = 1'b1;
                expected.result_valid = 1'b1;
                apply_and_check(requested, expected);
            end
        end

        requested = '0;
        requested.addressing_mode = CPU_ADDR_INDEXED_INDIRECT_X;
        requested.operand_byte = 8'hFF;
        requested.x_index = 8'h02;
        requested.pointer_low_byte = 8'h34;
        requested.pointer_high_byte = 8'h12;
        expected = '0;
        expected.pointer_low_address = 16'h0001;
        expected.pointer_high_address = 16'h0002;
        expected.pointer_addresses_valid = 1'b1;
        expected.mode_valid = 1'b1;
        apply_and_check(requested, expected);

        for (int unsigned operand = 0; operand < 256; operand++) begin
            requested = '0;
            requested.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y;
            requested.operand_byte = 8'(operand);
            expected = '0;
            expected.pointer_low_address = {8'h00, 8'(operand)};
            expected.pointer_high_address = {8'h00, 8'(operand + 1)};
            expected.pointer_addresses_valid = 1'b1;
            expected.mode_valid = 1'b1;
            apply_and_check(requested, expected);
        end

        for (int unsigned high_sample = 0;
             high_sample < 6; high_sample++) begin
            for (int unsigned pointer_low = 0;
                 pointer_low < 256; pointer_low++) begin
                pointer_value =
                    (int'(HIGH_BYTE_SAMPLES[high_sample]) << 8) | pointer_low;
                for (int unsigned index_value = 0;
                     index_value < 256; index_value++) begin
                    requested = '0;
                    requested.addressing_mode = CPU_ADDR_INDIRECT_INDEXED_Y;
                    requested.operand_byte = 8'hFF;
                    requested.y_index = 8'(index_value);
                    requested.pointer_low_byte = 8'(pointer_low);
                    requested.pointer_high_byte =
                        HIGH_BYTE_SAMPLES[high_sample];
                    requested.pointer_data_valid = 1'b1;
                    expected = '0;
                    expected.effective_address =
                        16'(pointer_value + index_value);
                    expected.effective_address_valid = 1'b1;
                    expected.indexed_tentative_address = {
                        HIGH_BYTE_SAMPLES[high_sample],
                        8'(pointer_low + index_value)
                    };
                    expected.indexed_tentative_valid = 1'b1;
                    expected.pointer_low_address = 16'h00FF;
                    expected.pointer_high_address = 16'h0000;
                    expected.pointer_addresses_valid = 1'b1;
                    expected.page_cross =
                        (pointer_low + index_value) > 255;
                    expected.page_cross_valid = 1'b1;
                    expected.mode_valid = 1'b1;
                    expected.result_valid = 1'b1;
                    apply_and_check(requested, expected);
                end
            end
        end

        for (int unsigned base_low = 0; base_low < 256; base_low++) begin
            base_value = 32'h0000_7F00 | base_low;
            for (int unsigned offset = 0; offset < 256; offset++) begin
                signed_offset = (offset < 128)
                              ? int'(offset) : int'(offset) - 256;
                target_value = int'(base_value) + signed_offset;
                requested = '0;
                requested.addressing_mode = CPU_ADDR_RELATIVE;
                requested.base_address = 16'(base_value);
                requested.operand_byte = 8'(offset);
                expected = '0;
                expected.branch_target = 16'(target_value);
                expected.branch_target_valid = 1'b1;
                expected.branch_tentative_address = {
                    requested.base_address[15:8], 8'(target_value)
                };
                expected.page_cross = requested.base_address[15:8]
                                    != 8'(target_value >> 8);
                expected.page_cross_valid = 1'b1;
                expected.mode_valid = 1'b1;
                expected.result_valid = 1'b1;
                apply_and_check(requested, expected);
            end
        end

        for (int unsigned boundary = 0; boundary < 10; boundary++) begin
            for (int unsigned offset_index = 0;
                 offset_index < 7; offset_index++) begin
                signed_offset = (RELATIVE_OFFSETS[offset_index] < 8'h80)
                              ? int'(RELATIVE_OFFSETS[offset_index])
                              : int'(RELATIVE_OFFSETS[offset_index]) - 256;
                target_value = int'(BOUNDARY_ADDRESSES[boundary])
                             + signed_offset;
                requested = '0;
                requested.addressing_mode = CPU_ADDR_RELATIVE;
                requested.base_address = BOUNDARY_ADDRESSES[boundary];
                requested.operand_byte = RELATIVE_OFFSETS[offset_index];
                expected = '0;
                expected.branch_target = 16'(target_value);
                expected.branch_target_valid = 1'b1;
                expected.branch_tentative_address = {
                    requested.base_address[15:8], 8'(target_value)
                };
                expected.page_cross = requested.base_address[15:8]
                                    != 8'(target_value >> 8);
                expected.page_cross_valid = 1'b1;
                expected.mode_valid = 1'b1;
                expected.result_valid = 1'b1;
                apply_and_check(requested, expected);
            end
        end

        requested = '0;
        requested.addressing_mode = CPU_ADDR_RELATIVE;
        requested.base_address = 16'h1000;
        requested.operand_byte = 8'h05;
        expected = '0;
        expected.branch_target = 16'h1005;
        expected.branch_target_valid = 1'b1;
        expected.branch_tentative_address = 16'h1005;
        expected.page_cross = 1'b0;
        expected.page_cross_valid = 1'b1;
        expected.mode_valid = 1'b1;
        expected.result_valid = 1'b1;
        apply_and_check(requested, expected);

        requested.operand_byte = 8'hFB;
        expected.branch_target = 16'h0FFB;
        expected.branch_tentative_address = 16'h10FB;
        expected.page_cross = 1'b1;
        apply_and_check(requested, expected);

        requested.base_address = 16'h00FE;
        requested.operand_byte = 8'h05;
        expected.branch_target = 16'h0103;
        expected.branch_tentative_address = 16'h0003;
        expected.page_cross = 1'b1;
        apply_and_check(requested, expected);

        for (int unsigned encoding = 13; encoding < 16; encoding++) begin
            requested = '1;
            requested.addressing_mode = 4'(encoding);
            expected = '0;
            apply_and_check(requested, expected);
        end

        assert (vector_count == EXPECTED_VECTOR_COUNT)
            else $fatal(1, "unexpected address vector count: %0d",
                        vector_count);

        $display("PASS: Phase 2C address verification (%0d vectors)",
                 vector_count);
        $finish;
    end
endmodule
