`timescale 1ns/1ps

module nes_720p_scaler_tb;
    logic [10:0] video_x;
    logic [9:0] video_y;
    logic active_video;
    logic developer_layout;
    logic canvas_region, nes_region, panel_region;
    logic [7:0] nes_x, nes_y;
    logic [9:0] panel_x, panel_y;
    logic [15:0] framebuffer_address;
    integer unsigned hits [0:61439];
    longint unsigned normal_pixels, normal_checksum, border_pixels;
    longint unsigned developer_nes_pixels, developer_panel_pixels;
    longint unsigned panel_checksum;
    integer x_index, y_index, address_index, random_index;
    integer expected_x, expected_y;
    integer artifact;

    nes_720p_scaler dut (
        .video_x(video_x),
        .video_y(video_y),
        .active_video(active_video),
        .developer_layout(developer_layout),
        .canvas_region(canvas_region),
        .nes_region(nes_region),
        .panel_region(panel_region),
        .nes_x(nes_x),
        .nes_y(nes_y),
        .panel_x(panel_x),
        .panel_y(panel_y),
        .framebuffer_address(framebuffer_address)
    );

    initial begin
        for (address_index = 0; address_index < 61440;
             address_index = address_index + 1)
            hits[address_index] = 0;
        normal_pixels = 0;
        normal_checksum = 0;
        border_pixels = 0;
        developer_layout = 1'b0;
        active_video = 1'b1;

        for (y_index = 0; y_index < 720; y_index = y_index + 1) begin
            for (x_index = 0; x_index < 1280; x_index = x_index + 1) begin
                video_x = 11'(x_index);
                video_y = 10'(y_index);
                #1;
                if (x_index < 160 || x_index >= 1120) begin
                    border_pixels += 1;
                    if (canvas_region || nes_region || panel_region)
                        $fatal(1, "normal border marked as content");
                end else begin
                    expected_x = ((x_index - 160) * 4) / 15;
                    expected_y = y_index / 3;
                    if (!canvas_region || !nes_region || panel_region ||
                        nes_x !== 8'(expected_x) ||
                        nes_y !== 8'(expected_y) ||
                        framebuffer_address !==
                            16'(expected_y * 256 + expected_x))
                        $fatal(1, "normal mapping mismatch at %0d,%0d",
                               x_index, y_index);
                    hits[framebuffer_address] += 1;
                    normal_pixels += 1;
                    normal_checksum += 64'(framebuffer_address);
                end
            end
        end
        if (normal_pixels != 960 * 720 || border_pixels != 320 * 720)
            $fatal(1, "normal region pixel totals are incorrect");
        for (address_index = 0; address_index < 61440;
             address_index = address_index + 1)
            if (hits[address_index] != 9 && hits[address_index] != 12)
                $fatal(1, "source pixel %0d has %0d output hits",
                       address_index, hits[address_index]);

        developer_layout = 1'b1;
        developer_nes_pixels = 0;
        developer_panel_pixels = 0;
        panel_checksum = 0;
        for (y_index = 0; y_index < 720; y_index = y_index + 1) begin
            for (x_index = 160; x_index < 1120; x_index = x_index + 1) begin
                video_x = 11'(x_index);
                video_y = 10'(y_index);
                #1;
                if (x_index < 928) begin
                    expected_x = (x_index - 160) / 3;
                    expected_y = y_index / 3;
                    if (!nes_region || panel_region ||
                        nes_x !== 8'(expected_x) ||
                        nes_y !== 8'(expected_y))
                        $fatal(1, "developer game mapping mismatch");
                    developer_nes_pixels += 1;
                end else begin
                    expected_x = 512 + ((x_index - 928) * 2) / 3;
                    expected_y = (y_index * 2) / 3;
                    if (nes_region || !panel_region ||
                        panel_x !== 10'(expected_x) ||
                        panel_y !== 10'(expected_y))
                        $fatal(1, "developer panel mapping mismatch");
                    developer_panel_pixels += 1;
                    panel_checksum += 64'(expected_y * 640 + expected_x);
                end
            end
        end
        if (developer_nes_pixels != 768 * 720 ||
            developer_panel_pixels != 192 * 720)
            $fatal(1, "developer region pixel totals are incorrect");

        // Randomized inactive and blanking coordinates must fail closed.
        for (random_index = 0; random_index < 10000;
             random_index = random_index + 1) begin
            video_x = 11'($urandom_range(1649, 0));
            video_y = 10'($urandom_range(749, 0));
            active_video = video_x < 1280 && video_y < 720 &&
                           $urandom_range(7, 0) == 0;
            #1;
            if (!active_video &&
                (canvas_region || nes_region || panel_region))
                $fatal(1, "inactive coordinate entered a content region");
        end

        artifact = $fopen("build/sim/phase6b_shared_video_rtl.txt", "a");
        $fwrite(artifact, "SCALER %0d %0d %0d %0d %0d %0d\n",
                normal_pixels, border_pixels, normal_checksum,
                developer_nes_pixels, developer_panel_pixels,
                panel_checksum);
        $fclose(artifact);
        $display("PASS: normal and Developer Mode 720p scaling exhaustively checked");
        $finish;
    end
endmodule
