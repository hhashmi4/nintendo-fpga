`timescale 1ns/1ps

module nes_apu_mixer_phase5h_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [3:0] pulse1_output = '0;
    logic [3:0] pulse2_output = '0;
    logic [3:0] triangle_output = '0;
    logic [3:0] noise_output = '0;
    logic [6:0] dmc_output = '0;
    logic [19:0] mixed_audio;
    logic [19:0] expected;

    int vector_file;
    int scan_result;
    int unsigned vector_count = 0;
    int unsigned mismatch_count = 0;

    nes_apu_mixer dut (.*);

    always #5 clk <= !clk;

    initial begin
        $dumpfile("build/sim/nes_apu_mixer_phase5h.fst");
        $dumpvars(0, nes_apu_mixer_phase5h_tb);
        vector_file = $fopen("build/sim/nes_apu_mixer_phase5h_reference.txt", "r");
        if (vector_file == 0)
            $fatal(1, "Unable to open Phase 5H mixer vectors");

        @(posedge clk);
        #1;
        assert (mixed_audio == 0)
            else $fatal(1, "Mixer reset did not produce digital silence");
        reset = 1'b0;

        while (!$feof(vector_file)) begin
            @(negedge clk);
            scan_result = $fscanf(
                vector_file, "%d %d %d %d %d %d\n",
                pulse1_output, pulse2_output, triangle_output,
                noise_output, dmc_output, expected
            );
            if (scan_result == 6) begin
                @(posedge clk);
                #1;
                vector_count++;
                if ($isunknown(mixed_audio) || mixed_audio !== expected) begin
                    mismatch_count++;
                    $error(
                        "row=%0d p1=%0d p2=%0d t=%0d n=%0d d=%0d expected=%0d actual=%0d",
                        vector_count, pulse1_output, pulse2_output,
                        triangle_output, noise_output, dmc_output,
                        expected, mixed_audio
                    );
                end
            end else if (scan_result != -1) begin
                $fatal(1, "Malformed Phase 5H vector row after %0d vectors", vector_count);
            end
        end
        $fclose(vector_file);

        if (vector_count != 37137)
            $fatal(1, "Expected 37137 mixer vectors, saw %0d", vector_count);
        if (mismatch_count != 0)
            $fatal(1, "Phase 5H mixer mismatches: %0d", mismatch_count);
        $display(
            "PASS: Phase 5H nonlinear mixer rows=%0d mismatches=%0d",
            vector_count, mismatch_count
        );
        $finish;
    end
endmodule
