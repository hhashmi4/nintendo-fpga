`timescale 1ns/1ps

// Ordered, retry-bounded ADV7513 profile executor.  Configuration uses
// read/modify/write so reserved bits keep their silicon values; verification
// is a second independent read-only pass over every documented mask.
module adv7513_config_engine #(
    parameter integer MAX_RETRIES = 2
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       start_config,
    input  logic       start_verify,
    output logic       busy,
    output logic       done,
    output logic       failed,
    output logic [7:0] failure_code,
    output logic       transmitter_seen,
    output logic       command_valid,
    input  logic       command_ready,
    output logic       command_read,
    output logic [6:0] command_device_address,
    output logic [7:0] command_register_address,
    output logic [7:0] command_write_data,
    input  logic       response_valid,
    input  logic       response_nack,
    input  logic       response_timeout,
    input  logic [7:0] response_read_data
);
    import hdmi_tx_pkg::*;

    localparam integer ENTRY_COUNT = 24;
    localparam integer RETRY_WIDTH = MAX_RETRIES <= 0 ?
        1 : $clog2(MAX_RETRIES + 1);

    typedef enum logic [3:0] {
        CONFIG_IDLE,
        CONFIG_REQUEST_READ,
        CONFIG_WAIT_READ,
        CONFIG_REQUEST_WRITE,
        CONFIG_WAIT_WRITE,
        CONFIG_DONE,
        CONFIG_FAILED
    } config_state_t;

    config_state_t state;
    logic verify_only;
    logic [4:0] profile_index;
    logic [RETRY_WIDTH-1:0] retry_count;
    logic [7:0] profile_register, profile_mask, profile_value;
    logic profile_valid, profile_verify_enable;
    logic [7:0] merged_value;

    adv7513_720p_profile profile (
        .index(profile_index),
        .register_address(profile_register),
        .write_mask(profile_mask),
        .write_value(profile_value),
        .verify_enable(profile_verify_enable),
        .valid(profile_valid)
    );

    assign busy = state != CONFIG_IDLE && state != CONFIG_DONE &&
                  state != CONFIG_FAILED;
    assign command_valid = state == CONFIG_REQUEST_READ ||
                           state == CONFIG_REQUEST_WRITE;
    assign command_read = state == CONFIG_REQUEST_READ;
    assign command_device_address = ADV7513_MAIN_ADDRESS;
    assign command_register_address = profile_register;
    assign command_write_data = merged_value;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= CONFIG_IDLE;
            verify_only <= 1'b0;
            profile_index <= '0;
            retry_count <= '0;
            merged_value <= '0;
            done <= 1'b0;
            failed <= 1'b0;
            failure_code <= HDMI_ERROR_NONE;
            transmitter_seen <= 1'b0;
        end else begin
            done <= 1'b0;
            failed <= 1'b0;
            unique case (state)
                CONFIG_IDLE: begin
                    if (start_config || start_verify) begin
                        verify_only <= start_verify;
                        profile_index <= 5'd0;
                        retry_count <= '0;
                        failure_code <= HDMI_ERROR_NONE;
                        state <= CONFIG_REQUEST_READ;
                    end
                end
                CONFIG_REQUEST_READ: begin
                    if (command_ready)
                        state <= CONFIG_WAIT_READ;
                end
                CONFIG_WAIT_READ: begin
                    if (response_valid) begin
                        if (response_nack || response_timeout) begin
                            if (retry_count < RETRY_WIDTH'(MAX_RETRIES)) begin
                                retry_count <= retry_count + 1'b1;
                                state <= CONFIG_REQUEST_READ;
                            end else begin
                                failure_code <= response_timeout ?
                                    HDMI_TX_I2C_TIMEOUT : HDMI_TX_I2C_NACK;
                                state <= CONFIG_FAILED;
                            end
                        end else begin
                            transmitter_seen <= 1'b1;
                            retry_count <= '0;
                            if (verify_only) begin
                                if (profile_verify_enable &&
                                    (response_read_data & profile_mask) !=
                                    (profile_value & profile_mask)) begin
                                    failure_code <=
                                        HDMI_CONFIG_VERIFY_FAILED;
                                    state <= CONFIG_FAILED;
                                end else if (profile_index ==
                                             5'(ENTRY_COUNT - 1)) begin
                                    state <= CONFIG_DONE;
                                end else begin
                                    profile_index <= profile_index + 1'b1;
                                    state <= CONFIG_REQUEST_READ;
                                end
                            end else begin
                                merged_value <=
                                    (response_read_data & ~profile_mask) |
                                    (profile_value & profile_mask);
                                state <= CONFIG_REQUEST_WRITE;
                            end
                        end
                    end
                end
                CONFIG_REQUEST_WRITE: begin
                    if (command_ready)
                        state <= CONFIG_WAIT_WRITE;
                end
                CONFIG_WAIT_WRITE: begin
                    if (response_valid) begin
                        if (response_nack || response_timeout) begin
                            if (retry_count < RETRY_WIDTH'(MAX_RETRIES)) begin
                                retry_count <= retry_count + 1'b1;
                                state <= CONFIG_REQUEST_WRITE;
                            end else begin
                                failure_code <= response_timeout ?
                                    HDMI_TX_I2C_TIMEOUT : HDMI_TX_I2C_NACK;
                                state <= CONFIG_FAILED;
                            end
                        end else begin
                            transmitter_seen <= 1'b1;
                            retry_count <= '0;
                            if (profile_index == 5'(ENTRY_COUNT - 1)) begin
                                state <= CONFIG_DONE;
                            end else begin
                                profile_index <= profile_index + 1'b1;
                                state <= CONFIG_REQUEST_READ;
                            end
                        end
                    end
                end
                CONFIG_DONE: begin
                    done <= 1'b1;
                    state <= CONFIG_IDLE;
                end
                CONFIG_FAILED: begin
                    failed <= 1'b1;
                    state <= CONFIG_IDLE;
                end
                default: state <= CONFIG_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset && busy)
            assert (profile_valid);
    end
`endif
endmodule
