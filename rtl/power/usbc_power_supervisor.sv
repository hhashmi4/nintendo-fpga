`timescale 1ns/1ps

// Post-configuration observer. No CC/PD PHY, regulator enables or board reset.
// status_data is a coherent, synchronous normalized packet (see Phase 6E doc).
module usbc_power_supervisor #(
    parameter integer PD_CYCLES = 100_000_000,
    parameter integer STARTUP_CYCLES = 250_000_000,
    parameter integer RECOVERY_CYCLES = 50_000_000,
    parameter integer STABLE_CYCLES = 250_000,
    parameter integer STALE_CYCLES = 5_000_000,
    parameter logic [31:0] COUNTER_MAX = 32'hffffffff,
    parameter bit SIMULATED = 1'b1
) (
    input logic clk, reset,
    input logic status_valid,
    input logic [63:0] status_data,
    input logic fault_clear,
    output logic [3:0] state,
    output logic system_ready, video_power_permit, audio_power_permit,
    output logic downstream_disable_request,
    output logic [415:0] diagnostics
);
    localparam logic [3:0] POWER_OFF=0, ATTACHED=1, CONTRACT_PENDING=2,
        CONTRACT_VALID=3, INPUT_PROTECTED=4, RAILS_STARTING=5,
        RAILS_STABLE=6, FPGA_RELEASE=7, SYSTEM_READY=8, FAULT=9,
        SHUTDOWN=10, RECOVERY=11;
    logic [63:0] packet, observed;
    wire unused_observed_av_clocks = ^observed[11:10];
    logic [31:0] age, next_age, startup_elapsed, pending_elapsed;
    logic [31:0] recovery_elapsed, stable_elapsed;
    logic [31:0] active_faults, previous_faults, sticky_faults;
    logic [31:0] fault_count, detach_count, recovery_count;
    logic seen_packet, was_attached;
    logic attached, protocol_valid, sufficient, protected_input, rails_ready;
    logic prerequisites, healthy, startup, fresh;
    logic [15:0] mv, ma;
    logic [5:0] current_digit_sum;
    logic current_units_valid;
    logic [3:0] next_state;

    function automatic logic [31:0] increment(input logic [31:0] value);
        return value < COUNTER_MAX ? value + 32'd1 : value;
    endfunction

    initial begin
        assert (PD_CYCLES > 0 && STARTUP_CYCLES > 0 && RECOVERY_CYCLES > 0 &&
                STABLE_CYCLES > 0 && STALE_CYCLES > 0 && COUNTER_MAX > 0)
            else $error("Power observer parameters must be positive");
    end

    always_comb begin
        observed = status_valid ? status_data : packet;
        next_age = status_valid ? 32'd0 :
                   (age < STALE_CYCLES ? age + 32'd1 : age);
        fresh = (seen_packet || status_valid) && next_age < STALE_CYCLES;
        attached = observed[0];
        mv = observed[47:32];
        ma = observed[63:48];
        // 16 == 1 (mod 5): sum hexadecimal digits, then test mod 5 and even.
        // This bounds the current-unit check to six bits instead of synthesizing
        // a long 16-bit remainder divider on the fault/recovery path.
        current_digit_sum = {2'd0, ma[15:12]} + {2'd0, ma[11:8]} +
                            {2'd0, ma[7:4]} + {2'd0, ma[3:0]};
        case (current_digit_sum)
            0,5,10,15,20,25,30,35,40,45,50,55,60: current_units_valid = !ma[0];
            default: current_units_valid = 1'b0;
        endcase
        // A completed PD contract supersedes Type-C current advertisement.
        // Default USB current is deliberately not inferred as 500mA or 3A.
        protocol_valid = observed[3] && (
            (observed[2] && (mv == 5000 || mv == 9000) &&
             ma >= 10 && ma <= 3000 && current_units_valid) ||
            (!observed[2] && mv == 5000 &&
             ((observed[4] && !observed[5] && ma == 3000) ||
              (observed[5] && !observed[4] && ma == 1500))));
        // Only this exact full-load policy is qualified by the budget.
        sufficient = protocol_valid && observed[2] && mv == 9000 && ma == 3000;
        protected_input = observed[1] && observed[6];
        rails_ready = &observed[15:12];
        prerequisites = attached && sufficient && protected_input &&
                        rails_ready && (&observed[9:7]) && fresh;
        startup = state >= ATTACHED && state <= FPGA_RELEASE;
        active_faults = {22'd0, observed[25:16]};
        if (was_attached && !attached) active_faults[10] = 1'b1;
        if (attached && ((observed[3] && !protocol_valid) ||
                         (state == SYSTEM_READY && !sufficient)))
            active_faults[11] = 1'b1;
        if (attached && protocol_valid && !sufficient)
            active_faults[12] = 1'b1;
        if (state == CONTRACT_PENDING && !sufficient &&
            pending_elapsed >= PD_CYCLES-1) active_faults[13] = 1'b1;
        if (startup && startup_elapsed >= STARTUP_CYCLES-1)
            active_faults[14] = 1'b1;
        if (attached && !fresh) active_faults[16] = 1'b1;
        if (observed[31:26] != 0) active_faults[17] = 1'b1;
        if (state == SYSTEM_READY) begin
            if (!protected_input || !rails_ready) active_faults[7] = 1'b1;
            if (!observed[7]) active_faults[18] = 1'b1;
            if (!observed[8]) active_faults[19] = 1'b1;
            if (!observed[9]) active_faults[20] = 1'b1;
        end
        if (state > RECOVERY) active_faults[21] = 1'b1;
        healthy = prerequisites && active_faults == 0;
        if (state == RECOVERY && recovery_elapsed >= RECOVERY_CYCLES-1 &&
            !(healthy && stable_elapsed >= STABLE_CYCLES-1))
            active_faults[15] = 1'b1;

        next_state = state;
        if (!attached) begin
            next_state = was_attached ? SHUTDOWN : POWER_OFF;
        end else if (state == FAULT) begin
            if (fault_clear) next_state = RECOVERY;
        end else if (state == RECOVERY) begin
            if (active_faults[15]) next_state = FAULT;
            else if (healthy && stable_elapsed >= STABLE_CYCLES-1)
                next_state = ATTACHED;
        end else if (active_faults != 0) begin
            next_state = FAULT;
        end else begin
            case (state)
                POWER_OFF, SHUTDOWN: next_state = ATTACHED;
                ATTACHED: next_state = CONTRACT_PENDING;
                CONTRACT_PENDING: if (sufficient) next_state = CONTRACT_VALID;
                CONTRACT_VALID: if (protected_input) next_state = INPUT_PROTECTED;
                INPUT_PROTECTED: next_state = RAILS_STARTING;
                RAILS_STARTING: if (rails_ready) next_state = RAILS_STABLE;
                RAILS_STABLE: begin
                    if (!rails_ready || !protected_input) next_state = RAILS_STARTING;
                    else if (healthy && stable_elapsed >= STABLE_CYCLES-1)
                        next_state = FPGA_RELEASE;
                end
                FPGA_RELEASE: next_state = healthy ? SYSTEM_READY : RAILS_STARTING;
                SYSTEM_READY: next_state = SYSTEM_READY;
                default: next_state = FAULT;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            packet <= '0;
            seen_packet <= 1'b0;
            age <= '0;
            state <= POWER_OFF;
            startup_elapsed <= '0;
            pending_elapsed <= '0;
            recovery_elapsed <= '0;
            stable_elapsed <= '0;
            was_attached <= 1'b0;
            previous_faults <= '0;
            sticky_faults <= '0;
            fault_count <= '0;
            detach_count <= '0;
            recovery_count <= '0;
        end else begin
            if (status_valid) begin
                packet <= status_data;
                seen_packet <= 1'b1;
            end
            age <= next_age;
            state <= next_state;
            was_attached <= attached;
            previous_faults <= active_faults;
            sticky_faults <= (fault_clear ? 32'd0 : sticky_faults) | active_faults;
            if (|(active_faults & ~previous_faults)) fault_count <= increment(fault_count);
            if (was_attached && !attached) detach_count <= increment(detach_count);
            if (state != RECOVERY && next_state == RECOVERY)
                recovery_count <= increment(recovery_count);
            startup_elapsed <= startup ? startup_elapsed + 32'd1 : 32'd0;
            pending_elapsed <= state == CONTRACT_PENDING ? pending_elapsed + 32'd1 : 32'd0;
            recovery_elapsed <= state == RECOVERY ? recovery_elapsed + 32'd1 : 32'd0;
            stable_elapsed <= ((state == RAILS_STABLE || state == RECOVERY) && healthy)
                              ? stable_elapsed + 32'd1 : 32'd0;
        end
    end

    // Outputs depend only on captured status/state, never on asynchronous pins.
    // Power permissions are requests for later hardware wrappers, not resets.
    always_comb begin
        system_ready = !reset && state == SYSTEM_READY && age < STALE_CYCLES &&
            packet[0] && packet[1] && packet[2] && packet[3] && packet[6] &&
            (&packet[9:7]) && (&packet[15:12]) && packet[31:16] == 0 &&
            packet[47:32] == 9000 && packet[63:48] == 3000;
        video_power_permit = system_ready && packet[10];
        audio_power_permit = system_ready && packet[11];
        downstream_disable_request = !system_ready;
        diagnostics = '0;
        diagnostics[0*32 +: 32] = {31'd0, packet[0]};
        diagnostics[1*32 +: 32] = {31'd0, packet[0] && packet[2] && packet[3]};
        if (packet[0] && packet[3]) begin
            diagnostics[2*32 +: 32] = {16'd0, packet[47:32]};
            diagnostics[3*32 +: 32] = {16'd0, packet[63:48]};
            // Nominal contract capacity, NOT measured consumption.
            if (packet[47:32] == 9000)
                diagnostics[4*32 +: 32] = 32'd9 * {16'd0, packet[63:48]};
            else if (packet[47:32] == 5000)
                diagnostics[4*32 +: 32] = 32'd5 * {16'd0, packet[63:48]};
        end
        diagnostics[5*32 +: 32] = {31'd0, packet[1] && packet[6]};
        diagnostics[6*32 +: 32] = {31'd0, &packet[15:12]};
        diagnostics[7*32 +: 32] = {28'd0, state};
        diagnostics[8*32 +: 32] = sticky_faults;
        diagnostics[9*32 +: 32] = fault_count;
        diagnostics[10*32 +: 32] = detach_count;
        diagnostics[11*32 +: 32] = recovery_count;
        // bit0 simulated; bit1 configured values; bit2 calculated capacity.
        // No measured-voltage/current capability exists.
        diagnostics[12*32 +: 32] = {29'd0, 2'b11, SIMULATED};
    end
endmodule
