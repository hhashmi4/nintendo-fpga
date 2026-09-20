`timescale 1ns/1ps

module ppu_oam (
    input  logic       clk,
    input  logic       reset,
    input  logic       ppu_enable,
    input  logic [8:0] dot,
    input  logic [8:0] scanline,
    input  logic       rendering_enabled,
    input  logic       sprite_size_16,

    input  logic [7:0] cpu_oam_addr,
    input  logic [7:0] cpu_write_data,
    input  logic       cpu_write_enable,
    input  logic       cpu_access,
    output logic [7:0] cpu_read_data,
    output logic       cpu_write_commit,
    output logic       cpu_collision,

    input  logic [2:0] secondary_read_slot,
    output logic [7:0] secondary_read_y,
    output logic [7:0] secondary_read_tile,
    output logic [7:0] secondary_read_attributes,
    output logic [7:0] secondary_read_x,
    output logic [5:0] secondary_read_sprite_index,
    output logic       secondary_read_valid,

    // Independent read-only view consumed by the dots 257-320 renderer.
    // Keeping this separate preserves the Phase 3F debug/readback slot port.
    input  logic [2:0] renderer_read_slot,
    output logic [7:0] renderer_read_y,
    output logic [7:0] renderer_read_tile,
    output logic [7:0] renderer_read_attributes,
    output logic [7:0] renderer_read_x,
    output logic [5:0] renderer_read_sprite_index,
    output logic       renderer_read_valid,

    output logic [3:0] selected_sprite_count = 4'd0,
    output logic       sprite_zero_in_secondary = 1'b0,
    output logic       sprite_overflow_set,
    output logic [2:0] evaluation_phase = 3'd0,
    output logic [5:0] evaluation_sprite_index = 6'd0,
    output logic [1:0] evaluation_byte_index = 2'd0,
    output logic [7:0] evaluation_relative_row,
    output logic [4:0] sprite_height,
    output logic [7:0] primary_read_address,
    output logic [7:0] primary_read_data,
    output logic       secondary_clear_write,
    output logic       secondary_evaluation_write,
    output logic [4:0] secondary_write_address,
    output logic [7:0] secondary_write_data,
    output logic       evaluation_done = 1'b0
);
    localparam logic [2:0] PHASE_IDLE          = 3'd0;
    localparam logic [2:0] PHASE_CLEAR         = 3'd1;
    localparam logic [2:0] PHASE_EVALUATE_Y    = 3'd2;
    localparam logic [2:0] PHASE_COPY_SPRITE   = 3'd3;
    localparam logic [2:0] PHASE_OVERFLOW_SCAN = 3'd4;
    localparam logic [2:0] PHASE_OVERFLOW_TAIL = 3'd5;
    localparam logic [2:0] PHASE_DONE          = 3'd6;

    // Primary OAM has no architectural reset value. The single muxed read
    // address keeps storage ownership compatible with inferred FPGA RAM and a
    // future DMA requester. CPU writes are the only Phase 3F array writer.
    (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] primary_oam [0:255];
    logic [7:0] secondary_oam [0:31];
    logic [5:0] secondary_sprite_index [0:7];

    logic [7:0] evaluation_read_latch = 8'h00;
    logic [4:0] secondary_destination = 5'd0;
    logic [1:0] overflow_tail_remaining = 2'd0;
    logic visible_scanline;
    logic evaluation_window;
    logic internal_oam_owner;
    logic odd_evaluation_dot;
    logic even_evaluation_dot;
    logic [7:0] evaluator_address;
    logic evaluated_in_range;
    logic [4:0] secondary_slot_base;
    logic [4:0] renderer_slot_base;

    assign visible_scanline = scanline < 9'd240;
    assign evaluation_window = rendering_enabled && visible_scanline &&
                               dot >= 9'd65 && dot <= 9'd256;
    assign internal_oam_owner = rendering_enabled &&
                                (visible_scanline || scanline == 9'd261);
    assign odd_evaluation_dot = evaluation_window && dot[0];
    assign even_evaluation_dot = evaluation_window && !dot[0];
    assign evaluator_address = {evaluation_sprite_index,
                                evaluation_byte_index};

    // During visible evaluation, $2004 reads expose the internal primary-OAM
    // bus. During the clear window that bus is forced to $ff. Elsewhere Phase
    // 3F supplies ordinary addressed OAM reads. Active-render writes are
    // deliberately ignored; exact corruption/address quirks remain deferred.
    always_comb begin
        primary_read_address = evaluation_window ? evaluator_address :
                                                   cpu_oam_addr;
        primary_read_data = primary_oam[primary_read_address];
        if (rendering_enabled && visible_scanline &&
            dot >= 9'd1 && dot <= 9'd64)
            cpu_read_data = 8'hff;
        else
            cpu_read_data = primary_read_data;

        cpu_write_commit = cpu_write_enable && !internal_oam_owner;
        cpu_collision = cpu_access && internal_oam_owner;
    end

    ppu_sprite_range range_test (
        .scanline       (scanline[7:0]),
        .sprite_y       (evaluation_read_latch),
        .sprite_size_16 (sprite_size_16),
        .relative_row   (evaluation_relative_row),
        .sprite_height  (sprite_height),
        .in_range       (evaluated_in_range)
    );

    always_comb begin
        secondary_clear_write = !reset && ppu_enable && rendering_enabled &&
                                visible_scanline && dot >= 9'd1 &&
                                dot <= 9'd64 && !dot[0];
        secondary_evaluation_write = !reset && ppu_enable &&
                                     even_evaluation_dot &&
                                     (evaluation_phase == PHASE_EVALUATE_Y ||
                                      evaluation_phase == PHASE_COPY_SPRITE) &&
                                     (evaluation_phase == PHASE_COPY_SPRITE ||
                                      evaluated_in_range) &&
                                     selected_sprite_count < 4'd8;
        secondary_write_address = secondary_clear_write ?
            (dot[5:1] - 5'd1) : secondary_destination;
        secondary_write_data = secondary_clear_write ? 8'hff :
                                                       evaluation_read_latch;
    end

    assign secondary_slot_base = {secondary_read_slot, 2'b00};
    assign renderer_slot_base = {renderer_read_slot, 2'b00};
    always_comb begin
        secondary_read_y = secondary_oam[secondary_slot_base];
        secondary_read_tile = secondary_oam[secondary_slot_base + 5'd1];
        secondary_read_attributes = secondary_oam[secondary_slot_base + 5'd2];
        secondary_read_x = secondary_oam[secondary_slot_base + 5'd3];
        secondary_read_sprite_index =
            secondary_sprite_index[secondary_read_slot];
        secondary_read_valid = {1'b0, secondary_read_slot} <
                               selected_sprite_count;

        renderer_read_y = secondary_oam[renderer_slot_base];
        renderer_read_tile = secondary_oam[renderer_slot_base + 5'd1];
        renderer_read_attributes =
            secondary_oam[renderer_slot_base + 5'd2];
        renderer_read_x = secondary_oam[renderer_slot_base + 5'd3];
        renderer_read_sprite_index =
            secondary_sprite_index[renderer_read_slot];
        renderer_read_valid = {1'b0, renderer_read_slot} <
                              selected_sprite_count;
    end

    always_ff @(posedge clk) begin
        if (cpu_write_commit)
            primary_oam[cpu_oam_addr] <= cpu_write_data;

        if (reset) begin
            selected_sprite_count       <= 4'd0;
            sprite_zero_in_secondary    <= 1'b0;
            sprite_overflow_set         <= 1'b0;
            evaluation_phase            <= PHASE_IDLE;
            evaluation_sprite_index     <= 6'd0;
            evaluation_byte_index       <= 2'd0;
            evaluation_read_latch       <= 8'h00;
            secondary_destination       <= 5'd0;
            overflow_tail_remaining     <= 2'd0;
            evaluation_done             <= 1'b0;
        end else begin
            sprite_overflow_set <= 1'b0;

            if (ppu_enable && rendering_enabled && visible_scanline) begin
                if (dot == 9'd1) begin
                    selected_sprite_count    <= 4'd0;
                    sprite_zero_in_secondary <= 1'b0;
                    evaluation_phase         <= PHASE_CLEAR;
                    evaluation_sprite_index  <= 6'd0;
                    evaluation_byte_index    <= 2'd0;
                    secondary_destination    <= 5'd0;
                    overflow_tail_remaining  <= 2'd0;
                    evaluation_done          <= 1'b0;
                end

                if (secondary_clear_write)
                    secondary_oam[secondary_write_address] <= 8'hff;

                if (dot == 9'd64)
                    evaluation_phase <= PHASE_EVALUATE_Y;

                if (odd_evaluation_dot)
                    evaluation_read_latch <= primary_read_data;

                if (secondary_evaluation_write) begin
                    secondary_oam[secondary_write_address] <=
                        evaluation_read_latch;
                    secondary_destination <= secondary_destination + 5'd1;
                end

                if (even_evaluation_dot && !evaluation_done) begin
                    case (evaluation_phase)
                        PHASE_EVALUATE_Y: begin
                            if (evaluated_in_range) begin
                                secondary_sprite_index[
                                    selected_sprite_count[2:0]
                                ] <= evaluation_sprite_index;
                                if (evaluation_sprite_index == 6'd0)
                                    sprite_zero_in_secondary <= 1'b1;
                                evaluation_byte_index <= 2'd1;
                                evaluation_phase <= PHASE_COPY_SPRITE;
                            end else if (evaluation_sprite_index == 6'd63) begin
                                evaluation_done <= 1'b1;
                                evaluation_phase <= PHASE_DONE;
                                evaluation_byte_index <= 2'd0;
                            end else begin
                                evaluation_sprite_index <=
                                    evaluation_sprite_index + 6'd1;
                            end
                        end

                        PHASE_COPY_SPRITE: begin
                            if (evaluation_byte_index == 2'd3) begin
                                selected_sprite_count <=
                                    selected_sprite_count + 4'd1;
                                evaluation_byte_index <= 2'd0;
                                if (evaluation_sprite_index == 6'd63) begin
                                    evaluation_done <= 1'b1;
                                    evaluation_phase <= PHASE_DONE;
                                end else begin
                                    evaluation_sprite_index <=
                                        evaluation_sprite_index + 6'd1;
                                    if (selected_sprite_count == 4'd7)
                                        evaluation_phase <= PHASE_OVERFLOW_SCAN;
                                    else
                                        evaluation_phase <= PHASE_EVALUATE_Y;
                                end
                            end else begin
                                evaluation_byte_index <=
                                    evaluation_byte_index + 2'd1;
                            end
                        end

                        PHASE_OVERFLOW_SCAN: begin
                            if (evaluated_in_range) begin
                                sprite_overflow_set <= 1'b1;
                                overflow_tail_remaining <= 2'd3;
                                evaluation_phase <= PHASE_OVERFLOW_TAIL;
                                if (evaluation_byte_index == 2'd3) begin
                                    evaluation_byte_index <= 2'd0;
                                    evaluation_sprite_index <=
                                        evaluation_sprite_index + 6'd1;
                                    if (evaluation_sprite_index == 6'd63) begin
                                        evaluation_done <= 1'b1;
                                        evaluation_phase <= PHASE_DONE;
                                    end
                                end else begin
                                    evaluation_byte_index <=
                                        evaluation_byte_index + 2'd1;
                                end
                            end else if (evaluation_sprite_index == 6'd63) begin
                                evaluation_done <= 1'b1;
                                evaluation_phase <= PHASE_DONE;
                                evaluation_byte_index <= 2'd0;
                            end else begin
                                // Documented overflow bug: n and m advance
                                // independently, so the scan walks diagonally
                                // through tile/attribute/X bytes as though Y.
                                evaluation_sprite_index <=
                                    evaluation_sprite_index + 6'd1;
                                evaluation_byte_index <=
                                    evaluation_byte_index + 2'd1;
                            end
                        end

                        PHASE_OVERFLOW_TAIL: begin
                            // Consume each of the three bytes following the
                            // matching overflow candidate. The last byte must
                            // still advance m (and n when m wraps) before the
                            // evaluator enters its failed-copy phase.
                            if (evaluation_byte_index == 2'd3) begin
                                evaluation_byte_index <= 2'd0;
                                evaluation_sprite_index <=
                                    evaluation_sprite_index + 6'd1;
                            end else begin
                                evaluation_byte_index <=
                                    evaluation_byte_index + 2'd1;
                            end

                            if (overflow_tail_remaining == 2'd1 ||
                                (evaluation_byte_index == 2'd3 &&
                                 evaluation_sprite_index == 6'd63)) begin
                                overflow_tail_remaining <= 2'd0;
                                evaluation_phase <= PHASE_DONE;
                                evaluation_done <= 1'b1;
                            end else begin
                                overflow_tail_remaining <=
                                    overflow_tail_remaining - 2'd1;
                            end
                        end

                        default: begin
                            evaluation_done <= 1'b1;
                            evaluation_phase <= PHASE_DONE;
                        end
                    endcase
                    end else if (even_evaluation_dot &&
                                 evaluation_phase == PHASE_DONE) begin
                        // After evaluation terminates, hardware continues
                        // failed Y-byte copies until dot 256. Keep that OAM
                        // bus cadence visible without changing OAM2/state.
                        evaluation_byte_index <= 2'd0;
                        evaluation_sprite_index <=
                            evaluation_sprite_index + 6'd1;
                    end
                end

            if (ppu_enable && dot == 9'd257 && visible_scanline &&
                rendering_enabled) begin
                evaluation_done <= 1'b1;
                evaluation_phase <= PHASE_DONE;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset) begin
            assert (selected_sprite_count <= 4'd8);
            assert (!(secondary_clear_write &&
                      secondary_evaluation_write));
            assert (!cpu_write_commit || !internal_oam_owner);
            if (!ppu_enable) begin
                assert (!secondary_clear_write);
                assert (!secondary_evaluation_write);
            end
        end
    end
`endif

endmodule
