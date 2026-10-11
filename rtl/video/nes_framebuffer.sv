`timescale 1ns/1ps

// Three complete 256x240x9 frame stores. A toggle/acknowledge handshake
// transfers ownership only after the NES writer completes a frame and only at
// VGA frame end. The third bank lets the NES begin its next frame while one
// completed frame is pending and another is being scanned, avoiding the phase-
// dependent every-other-frame capture that a two-bank design can exhibit.
module nes_framebuffer (
    input  logic        write_clk,
    input  logic        write_reset,
    input  logic        write_frame_start,
    input  logic        write_valid,
    input  logic [7:0]  write_x,
    input  logic [7:0]  write_y,
    input  logic [5:0]  write_color,
    input  logic [2:0]  write_emphasis,
    input  logic        capture_freeze,
    output logic        capture_active,
    output logic        capture_complete,
    output logic        capture_pending,
    output logic [1:0]  write_bank,
    output logic [15:0] captured_frames,
    output logic        write_range_error,
    output logic        write_sequence_error,

    input  logic        read_clk,
    input  logic        read_reset,
    input  logic        read_frame_end,
    input  logic [15:0] read_address,
    output logic [8:0]  read_pixel,
    output logic        display_valid,
    output logic        swap_complete,
    output logic [1:0]  read_bank,
    output logic [15:0] displayed_frames
);
    localparam int unsigned PIXELS_PER_FRAME = 256 * 240;

    (* ramstyle = "M10K, no_rw_check" *) logic [8:0] framebuffer0
        [0:PIXELS_PER_FRAME-1];
    (* ramstyle = "M10K, no_rw_check" *) logic [8:0] framebuffer1
        [0:PIXELS_PER_FRAME-1];
    (* ramstyle = "M10K, no_rw_check" *) logic [8:0] framebuffer2
        [0:PIXELS_PER_FRAME-1];

    logic [15:0] write_address;
    logic [15:0] expected_write_address;
    logic [1:0] completed_bank;
    logic request_toggle;
    logic acknowledge_toggle;
    logic [8:0] read_pixel0;
    logic [8:0] read_pixel1;
    logic [8:0] read_pixel2;
    logic start_capture;
    logic accept_write;
    logic [1:0] selected_write_bank;
    logic [15:0] selected_expected_address;
    logic completed_waiting;

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] acknowledge_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [2:0] request_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] completed_bank_meta;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] completed_bank_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] read_bank_meta;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] read_bank_sync;

    function automatic logic [1:0] free_bank(
        input logic [1:0] active_read_bank,
        input logic [1:0] pending_bank,
        input logic       pending
    );
        begin
            free_bank = 2'd0;
            if (active_read_bank != 2'd0 && (!pending || pending_bank != 2'd0))
                free_bank = 2'd0;
            else if (active_read_bank != 2'd1 &&
                     (!pending || pending_bank != 2'd1))
                free_bank = 2'd1;
            else
                free_bank = 2'd2;
        end
    endfunction

    assign write_address = {write_y, write_x};
    assign capture_pending = request_toggle != acknowledge_sync[1];
    always_comb begin
        case (read_bank)
            2'd1: read_pixel = read_pixel1;
            2'd2: read_pixel = read_pixel2;
            default: read_pixel = read_pixel0;
        endcase
    end
    assign start_capture = write_frame_start && !capture_active &&
                           !completed_waiting &&
                           !capture_freeze;
    assign accept_write = write_valid && (capture_active || start_capture);
    assign selected_write_bank = capture_active ? write_bank :
                                 free_bank(read_bank_sync, completed_bank,
                                           capture_pending);
    assign selected_expected_address = capture_active ?
                                       expected_write_address : 16'd0;

    always_ff @(posedge write_clk) begin
        acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
        read_bank_meta <= read_bank;
        read_bank_sync <= read_bank_meta;
        capture_complete <= 1'b0;

        if (write_reset) begin
            acknowledge_sync <= 2'b00;
            read_bank_meta <= 2'd0;
            read_bank_sync <= 2'd0;
            capture_active <= 1'b0;
            capture_complete <= 1'b0;
            write_bank <= 2'd1;
            completed_bank <= 2'd0;
            request_toggle <= 1'b0;
            captured_frames <= 16'd0;
            write_range_error <= 1'b0;
            write_sequence_error <= 1'b0;
            expected_write_address <= 16'd0;
            completed_waiting <= 1'b0;
        end else begin
            // Debugger pauses can shift source/video phase enough that a
            // second frame completes before the first handoff is acknowledged.
            // Retain it in the third bank and publish after that acknowledgement.
            // Skip capture starts while waiting; never stall NES progression or
            // overwrite a queued/displayed bank, and never publish a partial frame.
            if (completed_waiting && !capture_pending) begin
                completed_bank <= write_bank;
                request_toggle <= !request_toggle;
                capture_complete <= 1'b1;
                captured_frames <= captured_frames + 16'd1;
                completed_waiting <= 1'b0;
            end
            if (start_capture) begin
                write_bank <= free_bank(read_bank_sync, completed_bank,
                                        capture_pending);
                capture_active <= 1'b1;
                expected_write_address <= 16'd0;
            end

            if (accept_write) begin
                if (write_address != selected_expected_address)
                    write_sequence_error <= 1'b1;
                if (write_y < 8'd240) begin
                    case (selected_write_bank)
                        2'd1: framebuffer1[write_address] <= {
                            write_emphasis, write_color
                        };
                        2'd2: framebuffer2[write_address] <= {
                            write_emphasis, write_color
                        };
                        default: framebuffer0[write_address] <= {
                            write_emphasis, write_color
                        };
                    endcase
                end else begin
                    write_range_error <= 1'b1;
                end

                if (write_x == 8'd255 && write_y == 8'd239) begin
                    capture_active <= 1'b0;
                    if (!capture_pending) begin
                        completed_bank <= selected_write_bank;
                        request_toggle <= !request_toggle;
                        capture_complete <= 1'b1;
                        captured_frames <= captured_frames + 16'd1;
                    end else begin
                        completed_waiting <= 1'b1;
                    end
                end else
                    expected_write_address <= selected_expected_address +
                                              16'd1;
            end
        end
    end

    always_ff @(posedge read_clk) begin
        request_sync <= {request_sync[1:0], request_toggle};
        completed_bank_meta <= completed_bank;
        completed_bank_sync <= completed_bank_meta;
        read_pixel0 <= framebuffer0[read_address];
        read_pixel1 <= framebuffer1[read_address];
        read_pixel2 <= framebuffer2[read_address];
        swap_complete <= 1'b0;

        if (read_reset) begin
            request_sync <= 3'b000;
            completed_bank_meta <= 2'd0;
            completed_bank_sync <= 2'd0;
            acknowledge_toggle <= 1'b0;
            read_bank <= 2'd0;
            display_valid <= 1'b0;
            swap_complete <= 1'b0;
            displayed_frames <= 16'd0;
        end else if (read_frame_end &&
                     request_sync[2] != acknowledge_toggle) begin
            read_bank <= completed_bank_sync;
            acknowledge_toggle <= request_sync[2];
            display_valid <= 1'b1;
            swap_complete <= 1'b1;
            displayed_frames <= displayed_frames + 16'd1;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge write_clk) begin
        if (!write_reset && accept_write) begin
            assert (write_y <= 8'd239);
            assert (write_address < 16'd61440);
            assert (write_address == selected_expected_address);
            assert (selected_write_bank != read_bank_sync);
            if (capture_pending)
                assert (selected_write_bank != completed_bank);
        end
        if (!write_reset && capture_complete)
            assert (request_toggle != acknowledge_sync[1]);
    end

    always_ff @(posedge read_clk) begin
        if (!read_reset) begin
            assert (read_address < 16'd61440);
            if (swap_complete)
                assert (display_valid && read_bank <= 2'd2);
        end
    end
`endif
endmodule
