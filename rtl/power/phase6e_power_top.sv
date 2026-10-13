`timescale 1ns/1ps

// Logical qualification target only. All power/controller I/O is virtual.
module phase6e_power_top (
    input logic CLOCK_50, STATUS_CLK, RESET_N,
    input logic STATUS_VALID,
    input logic [63:0] STATUS_DATA,
    input logic FAULT_CLEAR,
    output logic STATUS_READY,
    output logic [3:0] STARTUP_STATE,
    output logic SYSTEM_READY, VIDEO_POWER_PERMIT, AUDIO_POWER_PERMIT,
    output logic DOWNSTREAM_DISABLE_REQUEST,
    output logic [415:0] DIAGNOSTICS
);
    logic reset, status_valid;
    logic [63:0] status_data;
    usbc_power_status_cdc status_mailbox(
        .source_clk(STATUS_CLK), .destination_clk(CLOCK_50), .reset_n(RESET_N),
        .source_valid(STATUS_VALID), .source_data(STATUS_DATA),
        .source_ready(STATUS_READY), .destination_reset(reset),
        .destination_valid(status_valid), .destination_data(status_data));
    usbc_power_supervisor supervisor(
        .clk(CLOCK_50), .reset(reset), .status_valid(status_valid),
        .status_data(status_data), .fault_clear(FAULT_CLEAR), .state(STARTUP_STATE),
        .system_ready(SYSTEM_READY), .video_power_permit(VIDEO_POWER_PERMIT),
        .audio_power_permit(AUDIO_POWER_PERMIT),
        .downstream_disable_request(DOWNSTREAM_DISABLE_REQUEST), .diagnostics(DIAGNOSTICS));
endmodule
