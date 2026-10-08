`timescale 1ns/1ps

// Exact 352/13125 rational scheduler followed by a symmetric, time-multiplexed
// 961-tap Q18 FIR.  Two replicated history memories supply a symmetric sample
// pair to one pre-adder and one multiply per 50 MHz fabric cycle.  All 481
// coefficient groups finish well before the next 48 kHz result is due, and
// the old half of the snapshot is read before live writes can wrap over it.
module nes_audio_resampler (
    input  logic               clk,
    input  logic               reset,
    input  logic               input_tick,
    input  logic [19:0]        mixed_audio,
    output logic               sample_valid,
    output logic signed [31:0] filtered_sample,
    output logic               busy,
    output logic               schedule_overrun,
    output logic [13:0]        phase_debug
);
    import nes_audio_fir_coeff_pkg::*;

    localparam int unsigned POINTER_WIDTH = $clog2(NES_AUDIO_FIR_TAPS);

    typedef enum logic [1:0] {
        FIR_IDLE,
        FIR_WARM,
        FIR_MAC,
        FIR_FLUSH
    } fir_state_t;

    logic [19:0] history_near [0:NES_AUDIO_FIR_TAPS-1];
    logic [19:0] history_far [0:NES_AUDIO_FIR_TAPS-1];
    logic [POINTER_WIDTH-1:0] write_pointer;
    logic [POINTER_WIDTH-1:0] read_pointer_near;
    logic [POINTER_WIDTH-1:0] read_pointer_far;
    logic [POINTER_WIDTH-1:0] newest_pointer;
    logic [POINTER_WIDTH-1:0] oldest_pointer;
    logic [POINTER_WIDTH-1:0] mac_index;
    logic [POINTER_WIDTH-1:0] history_count;
    logic [POINTER_WIDTH-1:0] snapshot_count;
    logic [19:0] first_sample;
    logic [19:0] history_read_near;
    logic [19:0] history_read_far;
    logic [13:0] sample_phase;
    logic [14:0] sample_phase_sum;
    logic signed [47:0] accumulator;
    logic signed [47:0] completed_accumulator;
    logic [19:0] selected_sample_near;
    logic [19:0] selected_sample_far;
    logic signed [18:0] selected_coefficient;
    logic [POINTER_WIDTH-1:0] far_lag;
    logic signed [21:0] signed_pair;
    logic signed [40:0] product;
    logic signed [47:0] product_registered;
    logic               product_valid;
    logic [8:0] coefficient_index;
    fir_state_t state;

    assign sample_phase_sum = {1'b0, sample_phase} + 15'd352;
    assign phase_debug = sample_phase;
    assign busy = state != FIR_IDLE;

    always_comb begin
        if (mac_index < snapshot_count)
            selected_sample_near = history_read_near;
        else
            selected_sample_near = first_sample;

        far_lag = POINTER_WIDTH'(NES_AUDIO_FIR_TAPS - 1) - mac_index;
        if (far_lag < snapshot_count)
            selected_sample_far = history_read_far;
        else
            selected_sample_far = first_sample;

        coefficient_index = mac_index[8:0];
        selected_coefficient = NES_AUDIO_FIR_COEFFICIENTS[coefficient_index];
        if (mac_index == POINTER_WIDTH'(NES_AUDIO_FIR_TAPS / 2))
            signed_pair = $signed({2'b00, selected_sample_near});
        else
            signed_pair = $signed({1'b0, selected_sample_near}) +
                          $signed({1'b0, selected_sample_far});
        product = signed_pair * selected_coefficient;
        completed_accumulator = accumulator + product_registered;
    end

    function automatic logic [POINTER_WIDTH-1:0] pointer_before(
        input logic [POINTER_WIDTH-1:0] pointer
    );
        if (pointer == '0)
            pointer_before = POINTER_WIDTH'(NES_AUDIO_FIR_TAPS - 1);
        else
            pointer_before = pointer - 1'b1;
    endfunction

    function automatic logic [POINTER_WIDTH-1:0] pointer_after(
        input logic [POINTER_WIDTH-1:0] pointer
    );
        if (pointer == POINTER_WIDTH'(NES_AUDIO_FIR_TAPS - 1))
            pointer_after = '0;
        else
            pointer_after = pointer + 1'b1;
    endfunction

    function automatic logic signed [31:0] round_q18(
        input logic signed [47:0] value
    );
        logic signed [47:0] magnitude;
        logic signed [47:0] rounded;
        begin
            if (value < 0) begin
                magnitude = -value;
                rounded = (magnitude + 48'sd131072) >>> 18;
                round_q18 = -rounded[31:0];
            end else begin
                rounded = (value + 48'sd131072) >>> 18;
                round_q18 = rounded[31:0];
            end
        end
    endfunction

    // Replication gives the symmetric MAC two independent read ports while
    // retaining an inference-friendly write/read pair in each memory.  Reset
    // validity, rather than clearing 961 words, defines startup contents.
    always_ff @(posedge clk) begin
        if (input_tick) begin
            history_near[write_pointer] <= mixed_audio;
            history_far[write_pointer] <= mixed_audio;
        end
        history_read_near <= history_near[read_pointer_near];
        history_read_far <= history_far[read_pointer_far];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            write_pointer <= '0;
            read_pointer_near <= '0;
            read_pointer_far <= '0;
            newest_pointer <= '0;
            oldest_pointer <= '0;
            mac_index <= '0;
            history_count <= '0;
            snapshot_count <= '0;
            first_sample <= '0;
            sample_phase <= '0;
            accumulator <= '0;
            product_registered <= '0;
            product_valid <= 1'b0;
            filtered_sample <= '0;
            sample_valid <= 1'b0;
            schedule_overrun <= 1'b0;
            state <= FIR_IDLE;
        end else begin
            sample_valid <= 1'b0;

            if (input_tick) begin
                if (history_count == '0)
                    first_sample <= mixed_audio;
                if (history_count < POINTER_WIDTH'(NES_AUDIO_FIR_TAPS))
                    history_count <= history_count + 1'b1;
                if (write_pointer == POINTER_WIDTH'(NES_AUDIO_FIR_TAPS - 1))
                    write_pointer <= '0;
                else
                    write_pointer <= write_pointer + 1'b1;

                if (sample_phase_sum >= 15'd13125) begin
                    sample_phase <= 14'(sample_phase_sum - 15'd13125);
                    if (state == FIR_IDLE) begin
                        // The write on this edge is part of the causal sample.
                        newest_pointer <= write_pointer;
                        oldest_pointer <= pointer_after(write_pointer);
                        read_pointer_near <= write_pointer;
                        read_pointer_far <= pointer_after(write_pointer);
                        if (history_count <
                            POINTER_WIDTH'(NES_AUDIO_FIR_TAPS))
                            snapshot_count <= history_count + 1'b1;
                        else
                            snapshot_count <= history_count;
                        accumulator <= '0;
                        product_registered <= '0;
                        product_valid <= 1'b0;
                        state <= FIR_WARM;
                    end else begin
                        schedule_overrun <= 1'b1;
                    end
                end else begin
                    sample_phase <= sample_phase_sum[13:0];
                end
            end

            case (state)
                FIR_IDLE: begin
                    mac_index <= '0;
                end

                FIR_WARM: begin
                    mac_index <= '0;
                    read_pointer_near <= pointer_before(newest_pointer);
                    read_pointer_far <= pointer_after(oldest_pointer);
                    state <= FIR_MAC;
                end

                FIR_MAC: begin
                    product_registered <=
                        $signed({{7{product[40]}}, product});
                    if (product_valid)
                        accumulator <= completed_accumulator;
                    product_valid <= 1'b1;

                    if (mac_index ==
                        POINTER_WIDTH'(NES_AUDIO_FIR_TAPS / 2)) begin
                        state <= FIR_FLUSH;
                    end else begin
                        mac_index <= mac_index + 1'b1;
                        read_pointer_near <=
                            pointer_before(read_pointer_near);
                        read_pointer_far <= pointer_after(read_pointer_far);
                    end
                end

                FIR_FLUSH: begin
                    filtered_sample <= round_q18(completed_accumulator);
                    sample_valid <= 1'b1;
                    product_valid <= 1'b0;
                    state <= FIR_IDLE;
                end

                default: state <= FIR_IDLE;
            endcase
        end
    end
endmodule
