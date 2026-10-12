`timescale 1ns/1ps

// Uses the ADV7513's documented EDID-ready interrupt and buffered EDID I2C
// map.  The FPGA never contends for the sink DDC pins: ADV7513 is the DDC
// master and this block reads only its host-side EDID RAM.
module adv7513_edid_reader #(
    parameter integer MAX_RETRIES = 2,
    parameter integer READY_POLLS = 256,
    parameter integer POLL_DELAY_CYCLES = 50_000
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    output logic       busy,
    output logic       done,
    output logic       failed,
    output logic [7:0] failure_code,
    output logic       edid_available,
    output logic       byte_valid,
    output logic [7:0] byte_index,
    output logic [7:0] byte_data,
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

    localparam integer RETRY_WIDTH = MAX_RETRIES <= 0 ?
        1 : $clog2(MAX_RETRIES + 1);
    localparam integer POLL_WIDTH = READY_POLLS <= 1 ?
        1 : $clog2(READY_POLLS);
    localparam integer DELAY_WIDTH = POLL_DELAY_CYCLES <= 1 ?
        1 : $clog2(POLL_DELAY_CYCLES);

    typedef enum logic [3:0] {
        EDID_IDLE,
        EDID_POLL_REQUEST,
        EDID_POLL_WAIT,
        EDID_POLL_DELAY,
        EDID_BYTE_REQUEST,
        EDID_BYTE_WAIT,
        EDID_DONE,
        EDID_FAILED
    } edid_reader_state_t;

    edid_reader_state_t state;
    logic [RETRY_WIDTH-1:0] retry_count;
    logic [POLL_WIDTH-1:0] poll_count;
    logic [DELAY_WIDTH-1:0] poll_delay_count;
    logic [7:0] read_index, extension_count;

    assign busy = state != EDID_IDLE && state != EDID_DONE &&
                  state != EDID_FAILED;
    assign command_valid = state == EDID_POLL_REQUEST ||
                           state == EDID_BYTE_REQUEST;
    assign command_read = 1'b1;
    assign command_device_address = state == EDID_POLL_REQUEST ?
        ADV7513_MAIN_ADDRESS : ADV7513_EDID_ADDRESS;
    assign command_register_address = state == EDID_POLL_REQUEST ?
        8'h96 : read_index;
    assign command_write_data = 8'h00;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= EDID_IDLE;
            retry_count <= '0;
            poll_count <= '0;
            poll_delay_count <= '0;
            read_index <= '0;
            extension_count <= '0;
            done <= 1'b0;
            failed <= 1'b0;
            failure_code <= HDMI_ERROR_NONE;
            edid_available <= 1'b0;
            byte_valid <= 1'b0;
            byte_index <= '0;
            byte_data <= '0;
        end else begin
            done <= 1'b0;
            failed <= 1'b0;
            byte_valid <= 1'b0;
            unique case (state)
                EDID_IDLE: begin
                    if (start) begin
                        retry_count <= '0;
                        poll_count <= '0;
                        poll_delay_count <= '0;
                        read_index <= '0;
                        extension_count <= '0;
                        failure_code <= HDMI_ERROR_NONE;
                        edid_available <= 1'b0;
                        state <= EDID_POLL_REQUEST;
                    end
                end
                EDID_POLL_REQUEST: begin
                    if (command_ready)
                        state <= EDID_POLL_WAIT;
                end
                EDID_POLL_WAIT: begin
                    if (response_valid) begin
                        if (response_nack || response_timeout) begin
                            if (retry_count < RETRY_WIDTH'(MAX_RETRIES)) begin
                                retry_count <= retry_count + 1'b1;
                                state <= EDID_POLL_REQUEST;
                            end else begin
                                failure_code <= response_timeout ?
                                    HDMI_TX_I2C_TIMEOUT : HDMI_TX_I2C_NACK;
                                state <= EDID_FAILED;
                            end
                        end else if (response_read_data[2]) begin
                            retry_count <= '0;
                            read_index <= 8'd0;
                            edid_available <= 1'b1;
                            state <= EDID_BYTE_REQUEST;
                        end else if (READY_POLLS <= 1 ||
                                     poll_count ==
                                     POLL_WIDTH'(READY_POLLS - 1)) begin
                            failure_code <= HDMI_TX_I2C_TIMEOUT;
                            state <= EDID_FAILED;
                        end else begin
                            poll_count <= poll_count + 1'b1;
                            poll_delay_count <= '0;
                            state <= EDID_POLL_DELAY;
                        end
                    end
                end
                EDID_POLL_DELAY: begin
                    if (POLL_DELAY_CYCLES <= 1 ||
                        poll_delay_count ==
                        DELAY_WIDTH'(POLL_DELAY_CYCLES - 1)) begin
                        poll_delay_count <= '0;
                        state <= EDID_POLL_REQUEST;
                    end else begin
                        poll_delay_count <= poll_delay_count + 1'b1;
                    end
                end
                EDID_BYTE_REQUEST: begin
                    if (command_ready)
                        state <= EDID_BYTE_WAIT;
                end
                EDID_BYTE_WAIT: begin
                    if (response_valid) begin
                        if (response_nack || response_timeout) begin
                            if (retry_count < RETRY_WIDTH'(MAX_RETRIES)) begin
                                retry_count <= retry_count + 1'b1;
                                state <= EDID_BYTE_REQUEST;
                            end else begin
                                failure_code <= response_timeout ?
                                    HDMI_TX_I2C_TIMEOUT : HDMI_TX_I2C_NACK;
                                state <= EDID_FAILED;
                            end
                        end else begin
                            retry_count <= '0;
                            byte_valid <= 1'b1;
                            byte_index <= read_index;
                            byte_data <= response_read_data;
                            if (read_index == 8'd126)
                                extension_count <= response_read_data;
                            if (read_index == 8'd255 ||
                                (read_index == 8'd127 &&
                                 extension_count == 0)) begin
                                state <= EDID_DONE;
                            end else begin
                                read_index <= read_index + 1'b1;
                                state <= EDID_BYTE_REQUEST;
                            end
                        end
                    end
                end
                EDID_DONE: begin
                    done <= 1'b1;
                    state <= EDID_IDLE;
                end
                EDID_FAILED: begin
                    failed <= 1'b1;
                    state <= EDID_IDLE;
                end
                default: state <= EDID_IDLE;
            endcase
        end
    end
endmodule
