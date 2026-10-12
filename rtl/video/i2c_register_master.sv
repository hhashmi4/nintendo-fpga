`timescale 1ns/1ps

// Single-byte register I2C master.  Reads use the standard write-address,
// register-byte, repeated-START, read-address transaction.  SCL and SDA are
// represented only as active-low enables; the wrapper must provide pull-ups.
module i2c_register_master #(
    parameter integer CLOCKS_PER_HALF_PERIOD = 250,
    parameter integer STRETCH_TIMEOUT_CYCLES = 50_000
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       command_valid,
    output logic       command_ready,
    input  logic       command_read,
    input  logic [6:0] command_device_address,
    input  logic [7:0] command_register_address,
    input  logic [7:0] command_write_data,
    output logic       response_valid,
    output logic       response_ack,
    output logic       response_nack,
    output logic       response_timeout,
    output logic [7:0] response_read_data,
    output logic       bus_recovery_pulse,
    input  logic       scl_in,
    input  logic       sda_in,
    output logic       scl_drive_low,
    output logic       sda_drive_low
);
    localparam integer DIV_WIDTH = CLOCKS_PER_HALF_PERIOD <= 1 ?
        1 : $clog2(CLOCKS_PER_HALF_PERIOD);
    localparam integer TIMEOUT_WIDTH = STRETCH_TIMEOUT_CYCLES <= 1 ?
        1 : $clog2(STRETCH_TIMEOUT_CYCLES);

    typedef enum logic [5:0] {
        I2C_IDLE,
        I2C_START_IDLE,
        I2C_START_SDA,
        I2C_SEND_LOW,
        I2C_SEND_HIGH,
        I2C_SEND_FALL,
        I2C_ACK_LOW,
        I2C_ACK_HIGH,
        I2C_ACK_FALL,
        I2C_RESTART_LOW,
        I2C_RESTART_HIGH,
        I2C_RESTART_SDA,
        I2C_READ_LOW,
        I2C_READ_HIGH,
        I2C_READ_FALL,
        I2C_MASTER_NACK_LOW,
        I2C_MASTER_NACK_HIGH,
        I2C_MASTER_NACK_FALL,
        I2C_STOP_LOW,
        I2C_STOP_HIGH,
        I2C_STOP_RELEASE,
        I2C_COMPLETE,
        I2C_RECOVERY_LOW,
        I2C_RECOVERY_HIGH,
        I2C_RECOVERY_STOP_LOW,
        I2C_RECOVERY_STOP_HIGH,
        I2C_RECOVERY_STOP_RELEASE,
        I2C_TIMEOUT
    } i2c_state_t;

    i2c_state_t state;
    logic [DIV_WIDTH-1:0] divider_count;
    logic [TIMEOUT_WIDTH-1:0] stretch_count;
    logic latched_read;
    logic [6:0] latched_device_address;
    logic [7:0] latched_register_address, latched_write_data;
    logic [7:0] send_byte, read_shift;
    logic [2:0] bit_index;
    logic [1:0] byte_phase;
    logic [3:0] recovery_pulses;
    logic nack_seen;
    logic half_period_done;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic scl_meta, scl_sampled, sda_meta, sda_sampled;

    assign half_period_done = CLOCKS_PER_HALF_PERIOD <= 1 ||
                              divider_count ==
                              DIV_WIDTH'(CLOCKS_PER_HALF_PERIOD - 1);
    assign command_ready = state == I2C_IDLE;

    always_comb begin
        scl_drive_low = 1'b0;
        sda_drive_low = 1'b0;
        unique case (state)
            I2C_START_SDA,
            I2C_RESTART_SDA: sda_drive_low = 1'b1;
            I2C_SEND_LOW,
            I2C_SEND_HIGH,
            I2C_SEND_FALL: begin
                scl_drive_low = state != I2C_SEND_HIGH;
                sda_drive_low = !send_byte[bit_index];
            end
            I2C_ACK_LOW,
            I2C_ACK_FALL,
            I2C_RESTART_LOW,
            I2C_READ_LOW,
            I2C_READ_FALL,
            I2C_MASTER_NACK_LOW,
            I2C_MASTER_NACK_FALL: scl_drive_low = 1'b1;
            I2C_STOP_LOW,
            I2C_RECOVERY_STOP_LOW: begin
                scl_drive_low = 1'b1;
                sda_drive_low = 1'b1;
            end
            I2C_STOP_HIGH,
            I2C_RECOVERY_STOP_HIGH: sda_drive_low = 1'b1;
            I2C_RECOVERY_LOW: scl_drive_low = 1'b1;
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            scl_meta <= 1'b1;
            scl_sampled <= 1'b1;
            sda_meta <= 1'b1;
            sda_sampled <= 1'b1;
            state <= I2C_IDLE;
            divider_count <= '0;
            stretch_count <= '0;
            latched_read <= 1'b0;
            latched_device_address <= '0;
            latched_register_address <= '0;
            latched_write_data <= '0;
            send_byte <= '0;
            read_shift <= '0;
            bit_index <= 3'd7;
            byte_phase <= 2'd0;
            recovery_pulses <= '0;
            nack_seen <= 1'b0;
            response_valid <= 1'b0;
            response_ack <= 1'b0;
            response_nack <= 1'b0;
            response_timeout <= 1'b0;
            response_read_data <= '0;
            bus_recovery_pulse <= 1'b0;
        end else begin
            // Slave-driven ACK/data and clock stretching are asynchronous to
            // the controller clock.  At 100 kHz the two-cycle observation
            // latency is negligible and removes metastability from the FSM.
            scl_meta <= scl_in;
            scl_sampled <= scl_meta;
            sda_meta <= sda_in;
            sda_sampled <= sda_meta;
            response_valid <= 1'b0;
            response_ack <= 1'b0;
            response_nack <= 1'b0;
            response_timeout <= 1'b0;
            bus_recovery_pulse <= 1'b0;

            // The divider counts only while the current phase is allowed to
            // progress.  High phases instead reset it while a slave stretches
            // SCL low and use a separate bounded timeout.
            if (state == I2C_IDLE || state == I2C_COMPLETE ||
                state == I2C_TIMEOUT)
                divider_count <= '0;
            else if ((state == I2C_START_IDLE || state == I2C_SEND_HIGH ||
                      state == I2C_ACK_HIGH || state == I2C_RESTART_HIGH ||
                      state == I2C_READ_HIGH ||
                      state == I2C_MASTER_NACK_HIGH ||
                      state == I2C_STOP_HIGH ||
                      state == I2C_RECOVERY_HIGH ||
                      state == I2C_RECOVERY_STOP_HIGH) && !scl_sampled)
                divider_count <= '0;
            else if (half_period_done)
                divider_count <= '0;
            else
                divider_count <= divider_count + 1'b1;

            if ((state == I2C_START_IDLE || state == I2C_SEND_HIGH ||
                 state == I2C_ACK_HIGH || state == I2C_RESTART_HIGH ||
                 state == I2C_READ_HIGH ||
                 state == I2C_MASTER_NACK_HIGH ||
                 state == I2C_STOP_HIGH ||
                 state == I2C_RECOVERY_HIGH ||
                 state == I2C_RECOVERY_STOP_HIGH) && !scl_sampled) begin
                if (STRETCH_TIMEOUT_CYCLES <= 1 ||
                    stretch_count ==
                    TIMEOUT_WIDTH'(STRETCH_TIMEOUT_CYCLES - 1)) begin
                    state <= I2C_TIMEOUT;
                    stretch_count <= '0;
                end else begin
                    stretch_count <= stretch_count + 1'b1;
                end
            end else begin
                stretch_count <= '0;
                unique case (state)
                    I2C_IDLE: begin
                        if (command_valid) begin
                            latched_read <= command_read;
                            latched_device_address <= command_device_address;
                            latched_register_address <=
                                command_register_address;
                            latched_write_data <= command_write_data;
                            nack_seen <= 1'b0;
                            read_shift <= '0;
                            byte_phase <= 2'd0;
                            recovery_pulses <= 4'd0;
                            state <= sda_sampled ? I2C_START_IDLE :
                                              I2C_RECOVERY_LOW;
                        end
                    end
                    I2C_START_IDLE:
                        if (half_period_done) state <= I2C_START_SDA;
                    I2C_START_SDA: begin
                        if (half_period_done) begin
                            send_byte <= {latched_device_address, 1'b0};
                            bit_index <= 3'd7;
                            state <= I2C_SEND_LOW;
                        end
                    end
                    I2C_SEND_LOW:
                        if (half_period_done) state <= I2C_SEND_HIGH;
                    I2C_SEND_HIGH:
                        if (half_period_done) state <= I2C_SEND_FALL;
                    I2C_SEND_FALL: begin
                        if (half_period_done) begin
                            if (bit_index == 0)
                                state <= I2C_ACK_LOW;
                            else begin
                                bit_index <= bit_index - 1'b1;
                                state <= I2C_SEND_LOW;
                            end
                        end
                    end
                    I2C_ACK_LOW:
                        if (half_period_done) state <= I2C_ACK_HIGH;
                    I2C_ACK_HIGH: begin
                        if (half_period_done) begin
                            nack_seen <= sda_sampled;
                            state <= I2C_ACK_FALL;
                        end
                    end
                    I2C_ACK_FALL: begin
                        if (half_period_done) begin
                            if (nack_seen) begin
                                state <= I2C_STOP_LOW;
                            end else if (byte_phase == 2'd0) begin
                                byte_phase <= 2'd1;
                                send_byte <= latched_register_address;
                                bit_index <= 3'd7;
                                state <= I2C_SEND_LOW;
                            end else if (byte_phase == 2'd1 && latched_read) begin
                                state <= I2C_RESTART_LOW;
                            end else if (byte_phase == 2'd1) begin
                                byte_phase <= 2'd2;
                                send_byte <= latched_write_data;
                                bit_index <= 3'd7;
                                state <= I2C_SEND_LOW;
                            end else if (byte_phase == 2'd2) begin
                                state <= I2C_STOP_LOW;
                            end else begin
                                bit_index <= 3'd7;
                                state <= I2C_READ_LOW;
                            end
                        end
                    end
                    I2C_RESTART_LOW:
                        if (half_period_done) state <= I2C_RESTART_HIGH;
                    I2C_RESTART_HIGH:
                        if (half_period_done) state <= I2C_RESTART_SDA;
                    I2C_RESTART_SDA: begin
                        if (half_period_done) begin
                            byte_phase <= 2'd3;
                            send_byte <= {latched_device_address, 1'b1};
                            bit_index <= 3'd7;
                            state <= I2C_SEND_LOW;
                        end
                    end
                    I2C_READ_LOW:
                        if (half_period_done) state <= I2C_READ_HIGH;
                    I2C_READ_HIGH: begin
                        if (half_period_done) begin
                            read_shift[bit_index] <= sda_sampled;
                            state <= I2C_READ_FALL;
                        end
                    end
                    I2C_READ_FALL: begin
                        if (half_period_done) begin
                            if (bit_index == 0)
                                state <= I2C_MASTER_NACK_LOW;
                            else begin
                                bit_index <= bit_index - 1'b1;
                                state <= I2C_READ_LOW;
                            end
                        end
                    end
                    I2C_MASTER_NACK_LOW:
                        if (half_period_done) state <= I2C_MASTER_NACK_HIGH;
                    I2C_MASTER_NACK_HIGH:
                        if (half_period_done) state <= I2C_MASTER_NACK_FALL;
                    I2C_MASTER_NACK_FALL:
                        if (half_period_done) state <= I2C_STOP_LOW;
                    I2C_STOP_LOW:
                        if (half_period_done) state <= I2C_STOP_HIGH;
                    I2C_STOP_HIGH:
                        if (half_period_done) state <= I2C_STOP_RELEASE;
                    I2C_STOP_RELEASE:
                        if (half_period_done) state <= I2C_COMPLETE;
                    I2C_COMPLETE: begin
                        response_valid <= 1'b1;
                        response_ack <= !nack_seen;
                        response_nack <= nack_seen;
                        response_read_data <= read_shift;
                        state <= I2C_IDLE;
                    end
                    I2C_RECOVERY_LOW:
                        if (half_period_done) state <= I2C_RECOVERY_HIGH;
                    I2C_RECOVERY_HIGH: begin
                        if (half_period_done) begin
                            if (sda_sampled || recovery_pulses == 4'd8)
                                state <= I2C_RECOVERY_STOP_LOW;
                            else begin
                                recovery_pulses <= recovery_pulses + 1'b1;
                                state <= I2C_RECOVERY_LOW;
                            end
                        end
                    end
                    I2C_RECOVERY_STOP_LOW:
                        if (half_period_done)
                            state <= I2C_RECOVERY_STOP_HIGH;
                    I2C_RECOVERY_STOP_HIGH:
                        if (half_period_done)
                            state <= I2C_RECOVERY_STOP_RELEASE;
                    I2C_RECOVERY_STOP_RELEASE: begin
                        if (half_period_done) begin
                            if (sda_sampled) begin
                                bus_recovery_pulse <= 1'b1;
                                state <= I2C_START_IDLE;
                            end else begin
                                state <= I2C_TIMEOUT;
                            end
                        end
                    end
                    I2C_TIMEOUT: begin
                        response_valid <= 1'b1;
                        response_timeout <= 1'b1;
                        state <= I2C_IDLE;
                    end
                    default: state <= I2C_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset) begin
            assert (!(scl_drive_low && scl_in));
            // Active-low enables are the only output representation.  There
            // is intentionally no signal capable of driving either wire high.
        end
    end
`endif
endmodule
