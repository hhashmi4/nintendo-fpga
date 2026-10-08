`timescale 1ns/1ps

// Deterministic WM8731 two-wire write-only configuration controller.  The
// board straps the codec to 7-bit address 0x1a (8-bit write byte 0x34).
module wm8731_i2c_init #(
    parameter int unsigned CLOCK_HZ = 50_000_000,
    parameter int unsigned I2C_HZ = 100_000,
    parameter int unsigned LOCK_TIMEOUT_CYCLES = 5_000_000,
    parameter int unsigned BUS_TIMEOUT_CYCLES = 50_000,
    parameter int unsigned MAX_RETRIES = 2
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        pll_locked,
    input  logic        retry_request,
    input  logic        i2c_scl_in,
    input  logic        i2c_sda_in,
    output logic        i2c_scl_drive_low,
    output logic        i2c_sda_drive_low,
    output logic        codec_init_busy,
    output logic        codec_init_done,
    output logic        codec_init_error,
    output logic [31:0] ack_count,
    output logic [31:0] nack_count,
    output logic [31:0] timeout_count,
    output logic [31:0] retry_count,
    output logic [7:0]  last_fault_code,
    output logic [3:0]  register_index_debug
);
    localparam int unsigned HALF_PERIOD = CLOCK_HZ / (I2C_HZ * 2);
    localparam int unsigned SEQUENCE_LENGTH = 10;

    localparam logic [7:0] FAULT_NONE = 8'h00;
    localparam logic [7:0] FAULT_PLL_TIMEOUT = 8'h01;
    localparam logic [7:0] FAULT_NACK = 8'h02;
    localparam logic [7:0] FAULT_SCL_TIMEOUT = 8'h03;
    localparam logic [7:0] FAULT_BUS_STUCK = 8'h04;

    typedef enum logic [3:0] {
        I2C_WAIT_LOCK,
        I2C_BUS_WAIT,
        I2C_START_DATA,
        I2C_START_CLOCK,
        I2C_BIT_LOW,
        I2C_BIT_HIGH,
        I2C_ACK_LOW,
        I2C_ACK_HIGH,
        I2C_STOP_LOW,
        I2C_STOP_CLOCK,
        I2C_STOP_DATA,
        I2C_REGISTER_DELAY,
        I2C_COMPLETE,
        I2C_FAILED
    } i2c_state_t;

    i2c_state_t state;
    logic [31:0] state_counter;
    logic [31:0] wait_counter;
    logic [23:0] transaction;
    logic [4:0] bit_index;
    logic [3:0] register_index;
    logic [7:0] attempt_count;
    logic transaction_failed;
    logic [7:0] transaction_fault;

    function automatic logic [15:0] register_word(input logic [3:0] index);
        case (index)
            4'd0: register_word = {7'd15, 9'h000};
            4'd1: register_word = {7'd9,  9'h000};
            4'd2: register_word = {7'd5,  9'h008};
            4'd3: register_word = {7'd6,  9'h007};
            4'd4: register_word = {7'd2,  9'h1f0};
            4'd5: register_word = {7'd4,  9'h012};
            4'd6: register_word = {7'd7,  9'h002};
            4'd7: register_word = {7'd8,  9'h001};
            4'd8: register_word = {7'd9,  9'h001};
            4'd9: register_word = {7'd5,  9'h000};
            default: register_word = '0;
        endcase
    endfunction

    function automatic logic [31:0] saturating_increment(
        input logic [31:0] value
    );
        if (&value)
            saturating_increment = value;
        else
            saturating_increment = value + 1'b1;
    endfunction

    task automatic begin_transaction;
        logic [15:0] word;
        begin
            word = register_word(register_index);
            transaction <= {8'h34, word};
            bit_index <= 5'd23;
            state_counter <= '0;
            state <= I2C_START_DATA;
        end
    endtask

    assign codec_init_busy = (state != I2C_COMPLETE) && (state != I2C_FAILED);
    assign codec_init_done = state == I2C_COMPLETE;
    assign codec_init_error = state == I2C_FAILED;
    assign register_index_debug = register_index;

    always_comb begin
        i2c_scl_drive_low = 1'b0;
        i2c_sda_drive_low = 1'b0;
        case (state)
            I2C_START_DATA: begin
                i2c_sda_drive_low = 1'b1;
            end
            I2C_START_CLOCK: begin
                i2c_scl_drive_low = 1'b1;
                i2c_sda_drive_low = 1'b1;
            end
            I2C_BIT_LOW: begin
                i2c_scl_drive_low = 1'b1;
                i2c_sda_drive_low = !transaction[bit_index];
            end
            I2C_BIT_HIGH: begin
                i2c_sda_drive_low = !transaction[bit_index];
            end
            I2C_ACK_LOW: begin
                i2c_scl_drive_low = 1'b1;
            end
            I2C_STOP_LOW: begin
                i2c_scl_drive_low = 1'b1;
                i2c_sda_drive_low = 1'b1;
            end
            I2C_STOP_CLOCK: begin
                i2c_sda_drive_low = 1'b1;
            end
            default: begin
                i2c_scl_drive_low = 1'b0;
                i2c_sda_drive_low = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset || retry_request) begin
            state <= I2C_WAIT_LOCK;
            state_counter <= '0;
            wait_counter <= '0;
            transaction <= '0;
            bit_index <= '0;
            register_index <= '0;
            attempt_count <= '0;
            transaction_failed <= 1'b0;
            transaction_fault <= FAULT_NONE;
            ack_count <= '0;
            nack_count <= '0;
            timeout_count <= '0;
            retry_count <= '0;
            last_fault_code <= FAULT_NONE;
        end else if (!pll_locked && state != I2C_WAIT_LOCK) begin
            state <= I2C_WAIT_LOCK;
            state_counter <= '0;
            wait_counter <= '0;
            register_index <= '0;
            transaction_failed <= 1'b0;
            last_fault_code <= FAULT_PLL_TIMEOUT;
        end else begin
            case (state)
                I2C_WAIT_LOCK: begin
                    if (pll_locked) begin
                        wait_counter <= '0;
                        state_counter <= '0;
                        state <= I2C_BUS_WAIT;
                    end else if (wait_counter == LOCK_TIMEOUT_CYCLES - 1) begin
                        timeout_count <= saturating_increment(timeout_count);
                        last_fault_code <= FAULT_PLL_TIMEOUT;
                        state <= I2C_FAILED;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                I2C_BUS_WAIT: begin
                    if (i2c_scl_in && i2c_sda_in) begin
                        if (state_counter == HALF_PERIOD - 1)
                            begin_transaction();
                        else
                            state_counter <= state_counter + 1'b1;
                    end else if (wait_counter == BUS_TIMEOUT_CYCLES - 1) begin
                        timeout_count <= saturating_increment(timeout_count);
                        transaction_failed <= 1'b1;
                        transaction_fault <= FAULT_BUS_STUCK;
                        last_fault_code <= FAULT_BUS_STUCK;
                        state_counter <= '0;
                        state <= I2C_STOP_LOW;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                I2C_START_DATA: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        state <= I2C_START_CLOCK;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_START_CLOCK: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        state <= I2C_BIT_LOW;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_BIT_LOW: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        wait_counter <= '0;
                        state <= I2C_BIT_HIGH;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_BIT_HIGH: begin
                    if (!i2c_scl_in) begin
                        if (wait_counter == BUS_TIMEOUT_CYCLES - 1) begin
                            timeout_count <= saturating_increment(timeout_count);
                            transaction_failed <= 1'b1;
                            transaction_fault <= FAULT_SCL_TIMEOUT;
                            last_fault_code <= FAULT_SCL_TIMEOUT;
                            state_counter <= '0;
                            state <= I2C_STOP_LOW;
                        end else wait_counter <= wait_counter + 1'b1;
                    end else if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        if ((bit_index == 5'd16) || (bit_index == 5'd8) ||
                            (bit_index == 5'd0)) begin
                            state <= I2C_ACK_LOW;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= I2C_BIT_LOW;
                        end
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_ACK_LOW: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        wait_counter <= '0;
                        state <= I2C_ACK_HIGH;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_ACK_HIGH: begin
                    if (!i2c_scl_in) begin
                        if (wait_counter == BUS_TIMEOUT_CYCLES - 1) begin
                            timeout_count <= saturating_increment(timeout_count);
                            transaction_failed <= 1'b1;
                            transaction_fault <= FAULT_SCL_TIMEOUT;
                            last_fault_code <= FAULT_SCL_TIMEOUT;
                            state_counter <= '0;
                            state <= I2C_STOP_LOW;
                        end else wait_counter <= wait_counter + 1'b1;
                    end else if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        if (i2c_sda_in) begin
                            nack_count <= saturating_increment(nack_count);
                            transaction_failed <= 1'b1;
                            transaction_fault <= FAULT_NACK;
                            last_fault_code <= FAULT_NACK;
                            state <= I2C_STOP_LOW;
                        end else begin
                            ack_count <= saturating_increment(ack_count);
                            if (bit_index == 0)
                                state <= I2C_STOP_LOW;
                            else begin
                                bit_index <= bit_index - 1'b1;
                                state <= I2C_BIT_LOW;
                            end
                        end
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_STOP_LOW: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        wait_counter <= '0;
                        state <= I2C_STOP_CLOCK;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_STOP_CLOCK: begin
                    if (!i2c_scl_in) begin
                        if (wait_counter == BUS_TIMEOUT_CYCLES - 1) begin
                            timeout_count <= saturating_increment(timeout_count);
                            transaction_failed <= 1'b1;
                            transaction_fault <= FAULT_SCL_TIMEOUT;
                            last_fault_code <= FAULT_SCL_TIMEOUT;
                            state_counter <= '0;
                            state <= I2C_STOP_DATA;
                        end else wait_counter <= wait_counter + 1'b1;
                    end else if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        state <= I2C_STOP_DATA;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_STOP_DATA: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        if (transaction_failed) begin
                            if (attempt_count < 8'(MAX_RETRIES)) begin
                                attempt_count <= attempt_count + 1'b1;
                                retry_count <= saturating_increment(retry_count);
                                register_index <= '0;
                                transaction_failed <= 1'b0;
                                wait_counter <= '0;
                                state <= I2C_REGISTER_DELAY;
                            end else begin
                                last_fault_code <= transaction_fault;
                                state <= I2C_FAILED;
                            end
                        end else if (register_index ==
                                     4'(SEQUENCE_LENGTH - 1)) begin
                            last_fault_code <= FAULT_NONE;
                            state <= I2C_COMPLETE;
                        end else begin
                            register_index <= register_index + 1'b1;
                            state <= I2C_REGISTER_DELAY;
                        end
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_REGISTER_DELAY: begin
                    if (state_counter == HALF_PERIOD - 1) begin
                        state_counter <= '0;
                        wait_counter <= '0;
                        state <= I2C_BUS_WAIT;
                    end else state_counter <= state_counter + 1'b1;
                end

                I2C_COMPLETE: begin
                    last_fault_code <= FAULT_NONE;
                end

                I2C_FAILED: begin
                end

                default: state <= I2C_WAIT_LOCK;
            endcase
        end
    end

    initial begin
        if (HALF_PERIOD < 2)
            $error("wm8731_i2c_init I2C clock is too fast");
    end
endmodule
