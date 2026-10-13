`timescale 1ns/1ps
module usbc_power_cdc_tb;
    logic source_clk=0, destination_clk=0, reset_n=0, source_valid=0;
    logic [63:0] source_data=0, destination_data;
    logic source_ready, destination_reset, destination_valid;
    logic [63:0] expected_queue[$];
    logic [63:0] expected_word;
    integer source_half=7, destination_half=10;
    integer sent=0, received=0, epoch_sent=0, source_cycles=0, destination_cycles=0;
    logic [31:0] source_rng=32'h6ecd2027, destination_rng=32'h6ecd2028;
    logic [31:0] rng=32'h6ecd2026;
    usbc_power_status_cdc dut(.*);
    always begin
        #(source_half + int'(source_rng[1:0])) source_clk=!source_clk;
        source_rng={source_rng[30:0],source_rng[31]^source_rng[21]^source_rng[1]^source_rng[0]};
    end
    always begin
        #(destination_half + int'(destination_rng[1:0])) destination_clk=!destination_clk;
        destination_rng={destination_rng[30:0],destination_rng[31]^destination_rng[21]^destination_rng[1]^destination_rng[0]};
    end
    always @(posedge source_clk) begin
        source_cycles++;
        if (source_valid && source_ready) begin
            expected_queue.push_back(source_data);
            sent++; epoch_sent++;
        end
    end
    always @(posedge destination_clk) begin
        destination_cycles++;
        #1;
        if (!destination_reset && destination_valid) begin
            assert (expected_queue.size()>0) else $fatal(1,"spurious CDC packet");
            expected_word=expected_queue.pop_front();
            assert (destination_data===expected_word) else $fatal(1,"torn CDC packet");
            received++;
        end
    end
    initial begin
        for (integer epoch=0; epoch<4; epoch++) begin
            reset_n=0; source_valid=0;
            #200;
            expected_queue.delete(); epoch_sent=0;
            source_half=5+epoch*3; destination_half=13-epoch*2;
            reset_n=1;
            while (epoch_sent<1000) begin
                @(negedge source_clk);
                // Hold a backpressured report; vary the next data atomically.
                if (source_ready || !source_valid) begin
                    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                    source_valid=rng[0] || rng[3];
                    source_data={rng,~rng};
                end
            end
            @(negedge source_clk); source_valid=0;
            #500;
            assert (expected_queue.size()==0) else $fatal(1,"CDC did not drain");
            // Reset an accepted/in-flight report: shared epoch cancels it.
            @(negedge source_clk); source_valid=1;
            @(posedge source_clk); #1; reset_n=0; source_valid=0;
            #200; expected_queue.delete();
        end
        assert (received>=4000) else $fatal(1,"CDC coverage incomplete");
        $display("PASS: Phase 6E CDC seed=6ecd2026 sent=%0d received=%0d source_cycles=%0d destination_cycles=%0d reset_epochs=4 mismatches=0",sent,received,source_cycles,destination_cycles);
        $finish;
    end
    initial begin #1000000; $fatal(1,"CDC timeout"); end
endmodule
