`timescale 1ns/1ps

module cpu_address_gen (
    input  cpu_pkg::cpu_address_request_t request,
    output cpu_pkg::cpu_address_result_t  response
);
    import cpu_pkg::*;

    logic [8:0]         byte_sum;
    logic [7:0]         pointer_high_wrapped;
    logic [15:0]        word_sum_wrapped;
    logic [15:0]        pointer_value;
    logic [15:0]        relative_target_wrapped;

    always_comb begin
        // Inert defaults also define reserved-mode and unresolved-pointer
        // behavior. Every output is assigned on every path.
        response             = '0;
        byte_sum             = '0;
        pointer_high_wrapped = '0;
        word_sum_wrapped      = '0;
        pointer_value         = {request.pointer_high_byte,
                                 request.pointer_low_byte};
        relative_target_wrapped = '0;

        case (request.addressing_mode)
            CPU_ADDR_IMPLIED: begin
                response.is_implied = 1'b1;
                response.mode_valid = 1'b1;
            end

            CPU_ADDR_ACCUMULATOR: begin
                response.uses_accumulator = 1'b1;
                response.mode_valid       = 1'b1;
            end

            CPU_ADDR_IMMEDIATE: begin
                response.immediate_value = request.operand_byte;
                response.immediate_valid = 1'b1;
                response.mode_valid      = 1'b1;
                response.result_valid    = 1'b1;
            end

            CPU_ADDR_ZERO_PAGE: begin
                response.effective_address       = {8'h00,
                                                    request.operand_byte};
                response.effective_address_valid = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_ZERO_PAGE_X: begin
                byte_sum = {1'b0, request.operand_byte}
                         + {1'b0, request.x_index};
                response.effective_address       = {8'h00, byte_sum[7:0]};
                response.effective_address_valid = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_ZERO_PAGE_Y: begin
                byte_sum = {1'b0, request.operand_byte}
                         + {1'b0, request.y_index};
                response.effective_address       = {8'h00, byte_sum[7:0]};
                response.effective_address_valid = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_ABSOLUTE: begin
                response.effective_address       = request.base_address;
                response.effective_address_valid = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_ABSOLUTE_X: begin
                byte_sum = {1'b0, request.base_address[7:0]}
                         + {1'b0, request.x_index};
                word_sum_wrapped = 16'({1'b0, request.base_address}
                                     + {9'b0, request.x_index});
                response.effective_address       = word_sum_wrapped;
                response.effective_address_valid = 1'b1;
                response.indexed_tentative_address = {
                    request.base_address[15:8], byte_sum[7:0]
                };
                response.indexed_tentative_valid = 1'b1;
                response.page_cross              = byte_sum[8];
                response.page_cross_valid        = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_ABSOLUTE_Y: begin
                byte_sum = {1'b0, request.base_address[7:0]}
                         + {1'b0, request.y_index};
                word_sum_wrapped = 16'({1'b0, request.base_address}
                                     + {9'b0, request.y_index});
                response.effective_address       = word_sum_wrapped;
                response.effective_address_valid = 1'b1;
                response.indexed_tentative_address = {
                    request.base_address[15:8], byte_sum[7:0]
                };
                response.indexed_tentative_valid = 1'b1;
                response.page_cross              = byte_sum[8];
                response.page_cross_valid        = 1'b1;
                response.mode_valid              = 1'b1;
                response.result_valid            = 1'b1;
            end

            CPU_ADDR_INDIRECT: begin
                byte_sum = {1'b0, request.base_address[7:0]} + 9'd1;
                response.pointer_low_address  = request.base_address;
                // NMOS 6502 behavior: increment only the pointer's low byte.
                response.pointer_high_address = {request.base_address[15:8],
                                                 byte_sum[7:0]};
                response.pointer_addresses_valid = 1'b1;
                response.mode_valid              = 1'b1;
                if (request.pointer_data_valid) begin
                    response.effective_address       = pointer_value;
                    response.effective_address_valid = 1'b1;
                    response.result_valid            = 1'b1;
                end
            end

            CPU_ADDR_INDEXED_INDIRECT_X: begin
                byte_sum = {1'b0, request.operand_byte}
                         + {1'b0, request.x_index};
                pointer_high_wrapped =
                    8'({1'b0, byte_sum[7:0]} + 9'd1);
                response.pointer_low_address = {8'h00, byte_sum[7:0]};
                response.pointer_high_address = {
                    8'h00, pointer_high_wrapped
                };
                response.pointer_addresses_valid = 1'b1;
                response.mode_valid              = 1'b1;
                if (request.pointer_data_valid) begin
                    response.effective_address       = pointer_value;
                    response.effective_address_valid = 1'b1;
                    response.result_valid            = 1'b1;
                end
            end

            CPU_ADDR_INDIRECT_INDEXED_Y: begin
                byte_sum = {1'b0, request.operand_byte} + 9'd1;
                response.pointer_low_address = {8'h00,
                                                request.operand_byte};
                response.pointer_high_address = {8'h00, byte_sum[7:0]};
                response.pointer_addresses_valid = 1'b1;
                response.mode_valid              = 1'b1;
                if (request.pointer_data_valid) begin
                    byte_sum = {1'b0, request.pointer_low_byte}
                             + {1'b0, request.y_index};
                    word_sum_wrapped = 16'({1'b0, pointer_value}
                                         + {9'b0, request.y_index});
                    response.effective_address       = word_sum_wrapped;
                    response.effective_address_valid = 1'b1;
                    response.indexed_tentative_address = {
                        request.pointer_high_byte, byte_sum[7:0]
                    };
                    response.indexed_tentative_valid = 1'b1;
                    response.page_cross              = byte_sum[8];
                    response.page_cross_valid        = 1'b1;
                    response.result_valid            = 1'b1;
                end
            end

            CPU_ADDR_RELATIVE: begin
                // base_address is supplied by the caller after fetching the
                // displacement. Eighteen signed bits avoid intermediate
                // overflow before the explicit modulo-16-bit selection.
                relative_target_wrapped = 16'(
                    $signed({2'b00, request.base_address})
                  + $signed({{10{request.operand_byte[7]}},
                              request.operand_byte})
                );
                response.branch_target = relative_target_wrapped;
                response.branch_target_valid = 1'b1;
                response.branch_tentative_address = {
                    request.base_address[15:8], relative_target_wrapped[7:0]
                };
                response.page_cross = request.base_address[15:8]
                                    != relative_target_wrapped[15:8];
                response.page_cross_valid = 1'b1;
                response.mode_valid       = 1'b1;
                response.result_valid     = 1'b1;
            end

            default: begin
                // Reserved encodings deliberately retain inert defaults.
            end
        endcase
    end
endmodule
