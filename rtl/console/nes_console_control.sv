`timescale 1ns/1ps

// Fabric-clock policy. File transfer belongs to HPS; frame admission belongs
// to scanout. Neither acknowledgement requires CPU or PPU progress.
module nes_console_control #(
    parameter int unsigned START_TIMEOUT_CYCLES = 100000000
) (
    input logic clk, reset, bridge_reset,
    input logic loader_begin, activation_accepted, loader_hold, runtime_active,
    input logic [1:0] loader_state,
    input logic [3:0] loader_error_code,
    input logic [7:0] buttons,
    input logic command_valid,
    input logic [31:0] command_word,
    output logic command_done,
    output logic [1:0] command_result,
    output logic [31:0] command_status,
    input logic video_ack,
    input logic [31:0] video_response,
    output logic [31:0] video_request, status,
    output logic core_hold, inhibit_game,
    output logic focus,
    output logic [7:0] game_buttons, navigation
);
    localparam logic [3:0] INIT=0, MENU=1, LOADING=2, STARTING=3,
        GAME=4, RETURNING=5, ERROR=6, DEVELOPER=7;
    localparam int TIMER_BITS = $clog2(START_TIMEOUT_CYCLES + 1);
    logic [3:0] state, next_state, error_code, next_error;
    logic [15:0] epoch, next_epoch;
    logic [1:0] selected_source, input_owner, desired_source;
    logic [1:0] next_result;
    logic [TIMER_BITS-1:0] timer;
    logic bridge_was_reset, loader_was_error, command_seen;
    logic input_armed;
    logic [7:0] previous_buttons;
    logic available, take_command;

    assign available = !loader_hold && loader_state != 2'd3 && !bridge_reset;
    assign core_hold = state != STARTING && state != GAME && state != DEVELOPER;
    assign inhibit_game = state != STARTING && state != GAME;
    assign input_owner = state == GAME ? 2'd1 : state == DEVELOPER ? 2'd2 : 2'd0;
    assign game_buttons = state == GAME && input_armed ? buttons : 8'd0;
    assign navigation = input_armed && (state == MENU || state == DEVELOPER ||
                        state == ERROR || state == LOADING) ? buttons & ~previous_buttons : 8'd0;
    assign desired_source = (state == STARTING || state == GAME) ? 2'd1 :
                            state == DEVELOPER ? 2'd2 : 2'd0;
    assign status = {epoch, error_code, loader_state, runtime_active, available,
                     selected_source, input_owner, state};
    always_comb begin
        video_request = status;
        video_request[7:6] = desired_source;
    end
    assign take_command = command_valid && !command_seen;

    always_comb begin
        next_state = state;
        next_epoch = epoch;
        next_error = error_code;
        next_result = 2'd0;
        // Autonomous completions precede new intentions. Reset/load/fault
        // arbitration below wins over all intentions in the same cycle.
        if (video_ack && video_response[31:16] == epoch) begin
            if ((state == INIT || state == RETURNING) && video_response[7:6] == 0)
                next_state = MENU;
            if (state == STARTING && video_response[7:6] == 1)
                next_state = GAME;
        end
        if (state == STARTING && timer == TIMER_BITS'(START_TIMEOUT_CYCLES-1)) begin
            next_state = ERROR;
            next_epoch = epoch + 16'd1;
            next_error = 4'd15;
        end
        if (state == MENU && (navigation[3] || (navigation[0] && !focus)) && available) begin
            next_state = STARTING;
            next_epoch = epoch + 16'd1;
            next_error = 0;
        end
        if ((state == MENU || state == ERROR) && (navigation[2] ||
            (state == MENU && navigation[0] && focus))) begin
            next_state = DEVELOPER;
            next_epoch = epoch + 16'd1;
        end
        if ((state == DEVELOPER || state == ERROR || state == LOADING) && navigation[1]) begin
            next_state = RETURNING;
            next_epoch = epoch + 16'd1;
        end
        if (take_command) begin
            if (command_word[15:4] != 0 || command_word[3:0] > 5)
                next_result = 2'd2;
            else if (command_word[3:0] != 0 && command_word[31:16] != epoch)
                next_result = 2'd1;
            else case (command_word[3:0])
                0: begin end
                1: begin next_state = RETURNING; next_epoch = epoch + 16'd1; end
                2: begin
                    if (state != MENU && state != DEVELOPER) next_result = 2'd2;
                    else if (!available) next_result = 2'd3;
                    else begin
                        next_state = STARTING; next_epoch = epoch + 16'd1;
                        next_error = 0;
                    end
                end
                3: begin next_state = DEVELOPER; next_epoch = epoch + 16'd1; end
                4: begin
                    if (state != MENU && state != ERROR && state != DEVELOPER)
                        next_result = 2'd2;
                    else begin
                        next_state = LOADING; next_epoch = epoch + 16'd1;
                        next_error = 0;
                    end
                end
                5: begin
                    next_state = ERROR; next_epoch = epoch + 16'd1;
                    next_error = loader_state == 2'd3 ? loader_error_code : 4'd14;
                end
                default: next_result = 2'd2;
            endcase
        end
        if (activation_accepted) begin
            next_state = RETURNING;
            next_epoch = epoch + 16'd1;
            next_error = 0;
            if (take_command && command_word[3:0] != 0) next_result = 2'd1;
        end
        if (loader_begin) begin
            next_state = LOADING;
            next_epoch = epoch + 16'd1;
            next_error = 0;
            if (take_command && command_word[3:0] != 0) next_result = 2'd1;
        end
        if (loader_state == 2'd3 && (!loader_was_error || loader_begin)) begin
            next_state = ERROR;
            next_epoch = epoch + 16'd1;
            next_error = loader_error_code;
            if (take_command && command_word[3:0] != 0) next_result = 2'd1;
        end
        if (bridge_reset && !bridge_was_reset) begin
            next_state = INIT;
            next_error = 0;
            next_epoch = epoch + 16'd1;
            if (take_command && command_word[3:0] != 0) next_result = 2'd1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= INIT;
            epoch <= 16'd1;
            error_code <= 0;
            selected_source <= 0;
            timer <= 0;
            bridge_was_reset <= 0;
            loader_was_error <= 0;
            command_seen <= 0;
            command_done <= 0;
            command_result <= 0;
            command_status <= 0;
            input_armed <= 0;
            previous_buttons <= 0;
            focus <= 0;
        end else begin
            state <= next_state;
            epoch <= next_epoch;
            error_code <= next_error;
            bridge_was_reset <= bridge_reset;
            loader_was_error <= loader_state == 2'd3;
            command_seen <= command_valid;
            command_done <= take_command;
            if (take_command) begin
                command_result <= next_result;
                // Response describes the pre-request observation; STATUS
                // polling observes completion separately, never speculates.
                command_status <= status;
            end
            if (video_ack && video_response[31:16] == epoch)
                selected_source <= video_response[7:6];
            if (state == STARTING && next_state == STARTING)
                timer <= timer + 1'b1;
            else timer <= 0;
            previous_buttons <= buttons;
            // Stable presentation bit, captured with status by the existing mailbox.
            // UP wins simultaneous UP/DOWN; no held-button repeat.
            if (next_state != state || next_epoch != epoch) focus <= 0;
            else if (state == MENU) begin
                if (navigation[4]) focus <= 0;
                else if (navigation[5]) focus <= 1;
            end
            if (next_state != state || next_epoch != epoch)
                input_armed <= 0;
            else if (buttons == 0)
                input_armed <= 1;
        end
    end
endmodule
