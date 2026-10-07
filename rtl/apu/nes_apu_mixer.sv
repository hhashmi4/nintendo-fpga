`timescale 1ns/1ps

// One-stage NES nonlinear mixer. mixed_audio is unsigned Q0.20: 0 is digital
// silence and 20'hfffff is the positive full-scale endpoint.  The registered
// lookup stage gives one fabric-clock cycle of deterministic latency.
module nes_apu_mixer (
    input  logic        clk,
    input  logic        reset,
    input  logic [3:0]  pulse1_output,
    input  logic [3:0]  pulse2_output,
    input  logic [3:0]  triangle_output,
    input  logic [3:0]  noise_output,
    input  logic [6:0]  dmc_output,
    output logic [19:0] mixed_audio
);
    import nes_apu_mixer_lut_pkg::*;

    logic [4:0] pulse_sum;
    logic [19:0] pulse_contribution_q;
    logic [17:0] triangle_drive;
    logic [16:0] noise_drive;
    logic [18:0] dmc_drive;
    logic [19:0] tnd_drive;
    logic [8:0] tnd_segment_index;
    logic [10:0] tnd_segment_fraction;
    logic [31:0] tnd_segment_q;
    logic [10:0] tnd_segment_fraction_q;
    logic [19:0] tnd_base;
    logic [11:0] tnd_delta;
    logic [22:0] tnd_product;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [22:0] tnd_rounded_product;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [11:0] tnd_interpolation;
    logic [20:0] tnd_contribution;
    logic [20:0] mixed_sum;

    always_comb begin
        pulse_sum = {1'b0, pulse1_output} + {1'b0, pulse2_output};

        // Q12 approximations to 22638/8227 and 22638/12241. DMC has
        // coefficient 1.0, so tnd_drive is expressed in DMC-level units.
        triangle_drive = triangle_output * 14'd11271;
        noise_drive = noise_output * 13'd7575;
        dmc_drive = {dmc_output, 12'b0};
        tnd_drive = {2'b0, triangle_drive} + {3'b0, noise_drive} +
                    {1'b0, dmc_drive};

        // Each segment spans one half DMC-level unit. Interpolation is
        // round-to-nearest with exact halves upward.
        tnd_segment_index = tnd_drive[19:11];
        tnd_segment_fraction = tnd_drive[10:0];
        tnd_base = tnd_segment_q[31:12];
        tnd_delta = tnd_segment_q[11:0];
        tnd_product = tnd_delta * tnd_segment_fraction_q;
        tnd_rounded_product = tnd_product + 23'd1024;
        tnd_interpolation = tnd_rounded_product[22:11];
        tnd_contribution = {1'b0, tnd_base} +
                           {9'b0, tnd_interpolation};

        mixed_sum = {1'b0, pulse_contribution_q} + tnd_contribution;
        mixed_audio = mixed_sum[20] ? 20'hfffff : mixed_sum[19:0];
    end

    // Register the two table selections and the interpolation fraction. This
    // breaks the long raw-channel -> nonlinear-table -> multiplier path while
    // preserving exact table contents and rounding behavior.
    always_ff @(posedge clk) begin
        if (reset) begin
            pulse_contribution_q <= '0;
            tnd_segment_q <= '0;
            tnd_segment_fraction_q <= '0;
        end else begin
            pulse_contribution_q <= apu_pulse_mix_lut(pulse_sum);
            tnd_segment_q <= apu_tnd_segment_lut(tnd_segment_index);
            tnd_segment_fraction_q <= tnd_segment_fraction;
        end
    end

`ifndef SYNTHESIS
    always_comb begin
        assert (pulse_sum <= 5'd30);
        assert (tnd_segment_index <= 9'd392);
        if (!reset)
            assert (tnd_contribution <= 21'h0c0000);
    end
`endif
endmodule
