`timescale 1ns/1ps

// Complete real-time Phase 5K path.  Diagnostics are bounded counters in the
// 50 MHz domain so a later HPS/Developer Mode register bank can expose them
// without touching the real-time datapath.
module nes_audio_output #(
    parameter bit ENABLE_HDMI_CLOCK = 1'b0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        source_reset,
    input  logic        input_tick,
    input  logic [19:0] mixed_audio,
    input  logic        test_tone_enable,
    input  logic        codec_retry_request,
    input  logic        i2c_scl_in,
    input  logic        i2c_sda_in,
    output logic        i2c_scl_drive_low,
    output logic        i2c_sda_drive_low,
    output logic        aud_xck,
    output logic        aud_bclk,
    output logic        aud_daclrck,
    output logic        aud_dacdat,
    output logic        audio_pll_locked,
    output logic        codec_init_busy,
    output logic        codec_init_done,
    output logic        codec_init_error,
    output logic [31:0] diag_i2c_ack_count,
    output logic [31:0] diag_i2c_nack_count,
    output logic [31:0] diag_init_retry_count,
    output logic [31:0] diag_i2c_timeout_count,
    output logic [31:0] diag_samples_generated,
    output logic [31:0] diag_samples_transmitted,
    output logic [31:0] diag_fifo_underruns,
    output logic [31:0] diag_fifo_overruns,
    output logic [31:0] diag_saturation_count,
    output logic [15:0] diag_fifo_occupancy,
    output logic [31:0] diag_sample_rate,
    output logic        diag_muted,
    output logic [7:0]  diag_last_fault,

    // Phase 6D broadcast contract.  This is the conditioned Phase 5K stream
    // before the codec FIFO: exact-rate signed 16-bit mono PCM in the 50 MHz
    // domain.  Consumers may not backpressure the real-time producer; each
    // consumer therefore owns an independently diagnosed FIFO.
    output logic signed [15:0] pcm_output_sample,
    output logic               pcm_output_valid,
    output logic               pcm_output_reset,
    output logic               hdmi_audio_clk
);
    logic audio_clk;
    logic audio_pll_locked_raw;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] audio_pll_lock_sync;
    logic audio_reset;
    logic pipeline_reset;
    logic stream_reset;
    logic resampler_valid;
    logic signed [31:0] filtered_sample;
    logic resampler_busy;
    logic schedule_overrun;
    logic [13:0] unused_phase_debug;
    logic pcm_valid;
    logic signed [15:0] pcm_sample;
    logic saturation_event;
    logic fifo_full;
    logic fifo_empty;
    logic fifo_overflow_event;
    logic fifo_underflow_event;
    logic [5:0] fifo_write_level;
    logic [5:0] fifo_read_level;
    logic signed [15:0] fifo_read_data;
    logic fifo_read_enable;
    logic prefill_ready;
    logic prefill_complete;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] prefill_sync;
    logic serializer_muted;
    logic serializer_frame_event;
    logic serializer_transmitted_event;
    logic serializer_underrun_event;
    logic [31:0] audio_transmitted_binary;
    logic [31:0] audio_underrun_binary;
    logic [31:0] audio_transmitted_gray;
    logic [31:0] audio_underrun_gray;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] transmitted_gray_sync1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] transmitted_gray_sync2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] underrun_gray_sync1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [31:0] underrun_gray_sync2;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] mute_sync;
    logic [31:0] transmitted_synced;
    logic [31:0] underrun_synced;
    logic [31:0] previous_underrun_synced;
    logic [25:0] rate_clock_count;
    logic [31:0] rate_sample_count;
    logic [7:0] codec_fault;
    logic [3:0] unused_register_index;

    function automatic logic [31:0] binary_to_gray(input logic [31:0] value);
        binary_to_gray = (value >> 1) ^ value;
    endfunction

    function automatic logic [31:0] gray_to_binary(input logic [31:0] value);
        logic [31:0] result;
        integer index;
        begin
            result[31] = value[31];
            for (index = 30; index >= 0; index = index - 1)
                result[index] = result[index + 1] ^ value[index];
            gray_to_binary = result;
        end
    endfunction

    function automatic logic [31:0] saturating_increment(
        input logic [31:0] value
    );
        saturating_increment = (&value) ? value : value + 1'b1;
    endfunction

    audio_pll #(.ENABLE_HDMI_CLOCK(ENABLE_HDMI_CLOCK)) audio_clock_source (
        .ref_clk(clk),
        .reset(reset),
        .audio_clk(audio_clk),
        .hdmi_audio_clk(hdmi_audio_clk),
        .locked(audio_pll_locked_raw)
    );
    assign aud_xck = audio_clk;

    // The PLL lock detector is asynchronous to the 50 MHz fabric domain.
    // Only its synchronized, monotonically asserted indication controls the
    // codec FSM and the source-side pipeline reset.
    always_ff @(posedge clk) begin
        if (reset)
            audio_pll_lock_sync <= '0;
        else
            audio_pll_lock_sync <= {audio_pll_lock_sync[0],
                                    audio_pll_locked_raw};
    end
    assign audio_pll_locked = audio_pll_lock_sync[1];

    wm8731_i2c_init codec_configuration (
        .clk(clk),
        .reset(reset),
        .pll_locked(audio_pll_locked),
        .retry_request(codec_retry_request),
        .i2c_scl_in(i2c_scl_in),
        .i2c_sda_in(i2c_sda_in),
        .i2c_scl_drive_low(i2c_scl_drive_low),
        .i2c_sda_drive_low(i2c_sda_drive_low),
        .codec_init_busy(codec_init_busy),
        .codec_init_done(codec_init_done),
        .codec_init_error(codec_init_error),
        .ack_count(diag_i2c_ack_count),
        .nack_count(diag_i2c_nack_count),
        .timeout_count(diag_i2c_timeout_count),
        .retry_count(diag_init_retry_count),
        .last_fault_code(codec_fault),
        .register_index_debug(unused_register_index)
    );

    assign pipeline_reset = reset || source_reset || !audio_pll_locked ||
                            !codec_init_done;

    nes_audio_resampler sample_converter (
        .clk(clk),
        .reset(stream_reset),
        .input_tick(input_tick),
        .mixed_audio(mixed_audio),
        .sample_valid(resampler_valid),
        .filtered_sample(filtered_sample),
        .busy(resampler_busy),
        .schedule_overrun(schedule_overrun),
        .phase_debug(unused_phase_debug)
    );

    nes_audio_conditioner conditioner (
        .clk(clk),
        .reset(stream_reset),
        .sample_valid(resampler_valid),
        .filtered_sample(filtered_sample),
        .test_tone_enable(test_tone_enable),
        .pcm_valid(pcm_valid),
        .pcm_sample(pcm_sample),
        .saturation_event(saturation_event)
    );

    assign pcm_output_sample = pcm_sample;
    assign pcm_output_valid = pcm_valid && !stream_reset;
    assign pcm_output_reset = stream_reset;

    reset_sync audio_reset_generator (
        .clk(audio_clk),
        .async_reset_n(!pipeline_reset),
        .reset(audio_reset)
    );

    // A short functional reset can end before a 12 MHz edge. Keep the
    // producer, FIFO write pointer and returning diagnostic synchronizers
    // reset until the consumer has cleared its old epoch and released reset.
    // audio_reset depends only on pipeline_reset, so this has no reset loop.
    reset_sync stream_reset_generator (
        .clk(clk),
        .async_reset_n(!pipeline_reset && !audio_reset),
        .reset(stream_reset)
    );

    audio_async_fifo #(.WIDTH(16), .DEPTH(32)) sample_fifo (
        .write_clk(clk),
        .write_reset(stream_reset),
        .write_enable(pcm_valid),
        .write_data(pcm_sample),
        .full(fifo_full),
        .overflow_event(fifo_overflow_event),
        .write_level(fifo_write_level),
        .read_clk(audio_clk),
        .read_reset(audio_reset),
        .read_enable(fifo_read_enable),
        .read_data(fifo_read_data),
        .empty(fifo_empty),
        .underflow_event(fifo_underflow_event),
        .read_level(fifo_read_level)
    );

    // Prefill is a startup threshold, not a running flow-control threshold.
    // Latch it so the expected one-entry CDC occupancy ripple cannot pause a
    // correctly clocked stream.  A genuine source stall therefore reaches
    // the serializer's explicit underrun detector instead of silently
    // inserting a stop/start cycle.
    assign prefill_ready = fifo_write_level >= 6'd4;
    always_ff @(posedge clk) begin
        if (stream_reset)
            prefill_complete <= 1'b0;
        else if (prefill_ready)
            prefill_complete <= 1'b1;
    end
    always_ff @(posedge audio_clk) begin
        if (audio_reset)
            prefill_sync <= '0;
        else
            prefill_sync <= {prefill_sync[0], prefill_complete};
    end

    wm8731_i2s_tx serializer (
        .audio_clk(audio_clk),
        .reset(audio_reset),
        .stream_enable(prefill_sync[1]),
        .fifo_empty(fifo_empty),
        .fifo_read_data(fifo_read_data),
        .fifo_read_enable(fifo_read_enable),
        .aud_bclk(aud_bclk),
        .aud_daclrck(aud_daclrck),
        .aud_dacdat(aud_dacdat),
        .muted(serializer_muted),
        .frame_event(serializer_frame_event),
        .sample_transmitted_event(serializer_transmitted_event),
        .underrun_event(serializer_underrun_event)
    );

    always_ff @(posedge audio_clk) begin
        if (audio_reset) begin
            audio_transmitted_binary <= '0;
            audio_underrun_binary <= '0;
            audio_transmitted_gray <= '0;
            audio_underrun_gray <= '0;
        end else begin
            // Register Gray codes at their source: combinational conversion
            // can glitch during a multi-bit carry in the binary counter.
            if (serializer_transmitted_event) begin
                audio_transmitted_binary <= saturating_increment(audio_transmitted_binary);
                audio_transmitted_gray <= binary_to_gray(saturating_increment(audio_transmitted_binary));
            end
            if (serializer_underrun_event || fifo_underflow_event) begin
                audio_underrun_binary <= saturating_increment(audio_underrun_binary);
                audio_underrun_gray <= binary_to_gray(saturating_increment(audio_underrun_binary));
            end
        end
    end

    assign transmitted_synced = gray_to_binary(transmitted_gray_sync2);
    assign underrun_synced = gray_to_binary(underrun_gray_sync2);

    always_ff @(posedge clk) begin
        if (reset) begin
            transmitted_gray_sync1 <= '0;
            transmitted_gray_sync2 <= '0;
            underrun_gray_sync1 <= '0;
            underrun_gray_sync2 <= '0;
            mute_sync <= '1;
            diag_samples_generated <= '0;
            diag_fifo_overruns <= '0;
            diag_saturation_count <= '0;
            diag_samples_transmitted <= '0;
            diag_fifo_underruns <= '0;
            previous_underrun_synced <= '0;
            diag_fifo_occupancy <= '0;
            diag_sample_rate <= '0;
            rate_clock_count <= '0;
            rate_sample_count <= '0;
            diag_muted <= 1'b1;
            diag_last_fault <= '0;
        end else begin
            transmitted_gray_sync1 <= audio_transmitted_gray;
            transmitted_gray_sync2 <= transmitted_gray_sync1;
            underrun_gray_sync1 <= audio_underrun_gray;
            underrun_gray_sync2 <= underrun_gray_sync1;
            mute_sync <= {mute_sync[0], serializer_muted};
            diag_samples_transmitted <= transmitted_synced;
            diag_fifo_underruns <= underrun_synced;
            previous_underrun_synced <= underrun_synced;
            diag_fifo_occupancy <= {10'd0, fifo_write_level};
            diag_muted <= mute_sync[1];

            if (stream_reset) begin
                transmitted_gray_sync1 <= '0;
                transmitted_gray_sync2 <= '0;
                underrun_gray_sync1 <= '0;
                underrun_gray_sync2 <= '0;
                mute_sync <= '1;
                diag_samples_transmitted <= '0;
                diag_fifo_underruns <= '0;
                previous_underrun_synced <= '0;
                diag_fifo_occupancy <= '0;
                diag_muted <= 1'b1;
            end

            if (pcm_valid && !stream_reset) begin
                diag_samples_generated <=
                    saturating_increment(diag_samples_generated);
                rate_sample_count <= rate_sample_count + 1'b1;
            end
            if (fifo_overflow_event && !stream_reset)
                diag_fifo_overruns <= saturating_increment(diag_fifo_overruns);
            if (saturation_event && !stream_reset)
                diag_saturation_count <=
                    saturating_increment(diag_saturation_count);

            if (rate_clock_count == 26'd49_999_999) begin
                diag_sample_rate <= rate_sample_count + 32'(pcm_valid && !stream_reset);
                rate_clock_count <= '0;
                rate_sample_count <= '0;
            end else begin
                rate_clock_count <= rate_clock_count + 1'b1;
            end

            if (codec_fault != 0)
                diag_last_fault <= codec_fault;
            else if (schedule_overrun)
                diag_last_fault <= 8'h12;
            else if (fifo_overflow_event)
                diag_last_fault <= 8'h11;
            else if (!stream_reset && underrun_synced > previous_underrun_synced)
                diag_last_fault <= 8'h10;
        end
    end

endmodule
