`timescale 1ns/1ps
module usbc_power_tb;
    logic clk=0, reset=1, status_valid=0, fault_clear=0;
    logic [63:0] status_data=0;
    logic [3:0] state;
    logic system_ready, video_power_permit, audio_power_permit, downstream_disable_request;
    logic [415:0] diagnostics, expected;
    integer fd, fields, cycles=0;
    logic rst, valid, clear, ready, video, audio;
    always #10 clk = !clk;
    usbc_power_supervisor #(.PD_CYCLES(12), .STARTUP_CYCLES(40),
        .RECOVERY_CYCLES(20), .STABLE_CYCLES(3), .STALE_CYCLES(15),
        .COUNTER_MAX(255)) dut(.*);
    initial begin
        fd=$fopen("build/sim/phase6e_power_vectors.txt", "r");
        if (fd == 0) $fatal(1, "missing vectors");
        while (!$feof(fd)) begin
            fields=$fscanf(fd, "%h %h %h %h %h %h %h %h\n",
                rst, valid, clear, status_data, expected, ready, video, audio);
            if (fields != 8) $fatal(1, "malformed vector row");
            reset=1'(rst); status_valid=1'(valid); fault_clear=1'(clear);
            @(posedge clk); #1;
            if (diagnostics !== expected || system_ready != 1'(ready) ||
                video_power_permit != 1'(video) || audio_power_permit != 1'(audio) ||
                downstream_disable_request == system_ready || state != expected[227:224]) begin
                $display("row=%0d state=%0d expected=%h actual=%h ready=%b/%0d",
                    cycles,state,expected,diagnostics,system_ready,ready);
                $fatal(1,"Phase 6E model mismatch");
            end
            cycles++;
            @(negedge clk);
        end
        $fclose(fd);
        // Illegal encoded state must fail closed, independent of the model.
        reset=0; status_valid=1; status_data=64'h0bb823280000ffcf;
        dut.state=4'hf;
        @(posedge clk); #1;
        assert (state==9 && !system_ready && diagnostics[8*32+21])
            else $fatal(1,"illegal state did not fault");
        $display("PASS: Phase 6E supervisor cycles=%0d mismatches=0; illegal state fail-closed",cycles);
        $finish;
    end
endmodule
