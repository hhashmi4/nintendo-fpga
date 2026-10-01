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
