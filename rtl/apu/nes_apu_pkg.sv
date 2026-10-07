`timescale 1ns/1ps

package nes_apu_pkg;
    localparam logic [15:0] APU_REGISTER_FIRST = 16'h4000;
    localparam logic [15:0] APU_REGISTER_LAST  = 16'h4017;
    localparam logic [15:0] APU_CHANNEL_REGISTER_LAST = 16'h4013;
    localparam logic [15:0] APU_STATUS_REGISTER = 16'h4015;
    localparam logic [15:0] APU_FRAME_COUNTER_REGISTER = 16'h4017;

    localparam int unsigned APU_STATUS_PULSE1_BIT   = 0;
    localparam int unsigned APU_STATUS_PULSE2_BIT   = 1;
    localparam int unsigned APU_STATUS_TRIANGLE_BIT = 2;
    localparam int unsigned APU_STATUS_NOISE_BIT    = 3;
    localparam int unsigned APU_STATUS_DMC_BIT      = 4;
    localparam int unsigned APU_STATUS_FRAME_IRQ_BIT = 6;
    localparam int unsigned APU_STATUS_DMC_IRQ_BIT   = 7;

    typedef logic [4:0] nes_apu_channel_mask_t;

    typedef enum logic {
        NES_APU_FRAME_MODE_4_STEP = 1'b0,
        NES_APU_FRAME_MODE_5_STEP = 1'b1
    } nes_apu_frame_mode_t;

    // Shared channel constants. The length table is indexed by bits 7:3 of
    // the pulse/triangle/noise high-timer register. Pulse sequencers count
    // downward, so position zero is the first value after a $4003 write and
    // position seven is selected by the first timer expiration.
    localparam logic [7:0] APU_LENGTH_TABLE [0:31] = '{
        8'd10,  8'd254, 8'd20,  8'd2,   8'd40,  8'd4,   8'd80,  8'd6,
        8'd160, 8'd8,   8'd60,  8'd10,  8'd14,  8'd12,  8'd26,  8'd14,
        8'd12,  8'd16,  8'd24,  8'd18,  8'd48,  8'd20,  8'd96,  8'd22,
        8'd192, 8'd24,  8'd72,  8'd26,  8'd16,  8'd28,  8'd32,  8'd30
    };

    // NTSC 2A03 Noise timer periods in CPU cycles. The Noise timer is
    // clocked on every other CPU cycle, so its reload is (period / 2) - 1.
    localparam logic [11:0] APU_NOISE_PERIOD_TABLE [0:15] = '{
        12'd4,    12'd8,    12'd16,   12'd32,
        12'd64,   12'd96,   12'd128,  12'd160,
        12'd202,  12'd254,  12'd380,  12'd508,
        12'd762,  12'd1016, 12'd2034, 12'd4068
    };

    localparam logic [7:0] APU_PULSE_DUTY_TABLE [0:3] = '{
        8'b1000_0000,
        8'b1100_0000,
        8'b1111_0000,
        8'b0011_1111
    };

    // The triangle sequencer is a 32-entry, 4-bit DAC lookup rather than an
    // arithmetic waveform. Position zero is the deterministic FPGA-reset
    // phase; timer expirations advance upward through the table.
    localparam logic [3:0] APU_TRIANGLE_SEQUENCE [0:31] = '{
        4'd15, 4'd14, 4'd13, 4'd12, 4'd11, 4'd10, 4'd9,  4'd8,
        4'd7,  4'd6,  4'd5,  4'd4,  4'd3,  4'd2,  4'd1,  4'd0,
        4'd0,  4'd1,  4'd2,  4'd3,  4'd4,  4'd5,  4'd6,  4'd7,
        4'd8,  4'd9,  4'd10, 4'd11, 4'd12, 4'd13, 4'd14, 4'd15
    };

    // NTSC 2A03 CPU-cycle positions. The 4-step terminal IRQ is asserted
    // across three consecutive CPU cycles; the quarter/half event is on the
    // middle cycle. The final entry in each sequence resets the cycle count.
    localparam logic [15:0] APU_NTSC_QUARTER_1 = 16'd7457;
    localparam logic [15:0] APU_NTSC_HALF_1    = 16'd14913;
    localparam logic [15:0] APU_NTSC_QUARTER_3 = 16'd22371;
    localparam logic [15:0] APU_NTSC_4STEP_IRQ_1 = 16'd29828;
    localparam logic [15:0] APU_NTSC_4STEP_HALF  = 16'd29829;
    localparam logic [15:0] APU_NTSC_4STEP_END   = 16'd29830;
    localparam logic [15:0] APU_NTSC_5STEP_GAP   = 16'd29829;
    localparam logic [15:0] APU_NTSC_5STEP_HALF  = 16'd37281;
    localparam logic [15:0] APU_NTSC_5STEP_END   = 16'd37282;
endpackage
