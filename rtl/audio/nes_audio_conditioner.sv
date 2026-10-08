`timescale 1ns/1ps

// Converts the signed FIR result to 16-bit PCM through a 10 Hz Q30 DC
// blocker and a fixed 0.75 gain.  The normal path is a five-cycle pipeline;
// input samples are more than 1,000 fabric cycles apart.  The diagnostic tone
// is a separate final source and never changes APU state.
module nes_audio_conditioner (
    input  logic               clk,
    input  logic               reset,
    input  logic               sample_valid,
    input  logic signed [31:0] filtered_sample,
    input  logic               test_tone_enable,
    output logic               pcm_valid,
    output logic signed [15:0] pcm_sample,
    output logic               saturation_event
);
    localparam logic signed [31:0] DC_BLOCK_Q30 = 32'sd1072337219;

    logic signed [31:0] previous_input;
    logic signed [47:0] previous_output;
    logic dc_initialized;
    logic [5:0] tone_phase;
    logic signed [31:0] pending_input;
    logic signed [79:0] feedback_product;
    logic signed [47:0] feedback;
    logic signed [47:0] blocked;
    logic signed [49:0] gained_product;

    typedef enum logic [2:0] {
        CONDITION_IDLE,
        CONDITION_FEEDBACK,
        CONDITION_BLOCK,
        CONDITION_GAIN,
        CONDITION_CONVERT
    } condition_state_t;
    condition_state_t state;

    function automatic logic signed [47:0] round_q30(
        input logic signed [79:0] value
    );
        logic signed [79:0] magnitude;
        logic signed [79:0] rounded;
        begin
            if (value < 0) begin
                magnitude = -value;
                rounded = (magnitude + 80'sd536870912) >>> 30;
                round_q30 = -rounded[47:0];
            end else begin
                rounded = (value + 80'sd536870912) >>> 30;
                round_q30 = rounded[47:0];
            end
        end
    endfunction

    function automatic logic signed [47:0] round_div128(
        input logic signed [49:0] value
    );
        logic signed [49:0] magnitude;
        logic signed [49:0] rounded;
        begin
            if (value < 0) begin
                magnitude = -value;
                rounded = (magnitude + 50'sd64) >>> 7;
                round_div128 = -rounded[47:0];
            end else begin
                rounded = (value + 50'sd64) >>> 7;
                round_div128 = rounded[47:0];
            end
        end
    endfunction

    always_ff @(posedge clk) begin : condition_sample
        logic signed [47:0] converted;

        if (reset) begin
            previous_input <= '0;
            previous_output <= '0;
            dc_initialized <= 1'b0;
            tone_phase <= '0;
            pending_input <= '0;
            feedback_product <= '0;
            feedback <= '0;
            blocked <= '0;
            gained_product <= '0;
            state <= CONDITION_IDLE;
            pcm_valid <= 1'b0;
            pcm_sample <= '0;
            saturation_event <= 1'b0;
        end else begin
            pcm_valid <= 1'b0;
            saturation_event <= 1'b0;

            case (state)
                CONDITION_IDLE: begin
                    if (sample_valid) begin
                        if (test_tone_enable) begin
                            pcm_valid <= 1'b1;
                            if (tone_phase < 6'd24)
                                pcm_sample <= 16'sd8192;
                            else
                                pcm_sample <= -16'sd8192;
                            if (tone_phase == 6'd47)
                                tone_phase <= '0;
                            else
                                tone_phase <= tone_phase + 1'b1;
                            dc_initialized <= 1'b0;
                            previous_output <= '0;
                        end else if (!dc_initialized) begin
                            previous_input <= filtered_sample;
                            previous_output <= '0;
                            dc_initialized <= 1'b1;
                            tone_phase <= '0;
                            pcm_sample <= '0;
                            pcm_valid <= 1'b1;
                        end else begin
                            pending_input <= filtered_sample;
                            feedback_product <=
                                previous_output * DC_BLOCK_Q30;
                            state <= CONDITION_FEEDBACK;
                        end
                    end
                end

                CONDITION_FEEDBACK: begin
                    feedback <= round_q30(feedback_product);
                    state <= CONDITION_BLOCK;
                end

                CONDITION_BLOCK: begin
                    blocked <= $signed({{16{pending_input[31]}},
                                        pending_input}) -
                               $signed({{16{previous_input[31]}},
                                        previous_input}) + feedback;
                    previous_input <= pending_input;
                    state <= CONDITION_GAIN;
                end

                CONDITION_GAIN: begin
                    previous_output <= blocked;
                    gained_product <= blocked * 3;
                    state <= CONDITION_CONVERT;
                end

                CONDITION_CONVERT: begin
                    converted = round_div128(gained_product);
                    if (converted > 48'sd32767) begin
                        pcm_sample <= 16'sh7fff;
                        saturation_event <= 1'b1;
                    end else if (converted < -48'sd32768) begin
                        pcm_sample <= 16'sh8000;
                        saturation_event <= 1'b1;
                    end else begin
                        pcm_sample <= converted[15:0];
                    end
                    pcm_valid <= 1'b1;
                    state <= CONDITION_IDLE;
                end

                default: state <= CONDITION_IDLE;
            endcase
        end
    end
endmodule
