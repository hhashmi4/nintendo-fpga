`timescale 1ns/1ps
module nes_library_tb;
    logic clk=0,hclk=0,reset=1;
    always #10 clk=~clk;
    always #7 hclk=~hclk;
    logic [31:0] status=32'h00010101;
    logic [7:0] nav=0;
    logic focus=0, change_owner=0;
    logic enabled, opened, load_request, cancel_request;
    logic [927:0] packet;
    logic [5:0] address=0;
    logic rd=0,wr=0;
    logic [31:0] wd=0,rv;
    logic [3:0] be=15;
    logic waitreq,rvalid,submit,ready,ack,valid,done;
    logic [95:0] req,cmd;
    logic [127:0] resp,result;
    nes_library_mmio registers(.clk(hclk),.reset(reset),.avs_address(address),.avs_read(rd),.avs_write(wr),
        .avs_writedata(wd),.avs_byteenable(be),.avs_waitrequest(waitreq),.avs_readdatavalid(rvalid),
        .avs_readdata(rv),.submit(submit),.request_word(req),.channel_ready(ready),.channel_ack(ack),.channel_response(resp));
    nes_console_mailbox #(.REQUEST_BITS(96),.RESPONSE_BITS(128)) channel(
        .source_clk(hclk),.source_reset(reset),.source_valid(submit),.source_data(req),.source_ready(ready),
        .source_ack(ack),.source_response(resp),.destination_clk(clk),.destination_reset(reset),
        .destination_valid(valid),.destination_data(cmd),.destination_done(done),.destination_response(result));
    nes_library_control dut(.clk(clk),.reset(reset),.console_status(status),.navigation(nav),.focus(focus),
        .ownership_change(change_owner),.command_valid(valid),.command_word(cmd),.command_done(done),
        .command_response(result),.enabled(enabled),.opened(opened),.load_request(load_request),
        .cancel_request(cancel_request),.packet(packet));
    task automatic read_word(input logic [5:0] a,output logic [31:0] data);
        @(negedge hclk);address=a;rd=1;
        @(negedge hclk);assert(rvalid && !waitreq);data=rv;rd=0;
    endtask
    task automatic write_word(input logic [5:0] a,input logic [31:0] data);
        @(negedge hclk);address=a;wd=data;wr=1;
        @(negedge hclk);wr=0;
    endtask
    task automatic exchange(input logic [7:0] op,input logic [31:0] data=0,
                            input logic [7:0] index=0,input logic [31:0] expected=0,
                            input bit stale=0,input bit old_epoch=0);
        logic [31:0] count,value;
        read_word(24,count);
        write_word(40,data);write_word(44,stale ? dut.revision-1 : dut.revision);
        write_word(16,{16'(status[31:16]-(old_epoch ? 16'd1 : 16'd0)),index,op});
        value=count;
        for(int i=0;i<1000 && value==count;i++) read_word(24,value);
        assert(value==count+1) else $fatal(1,"library completion timeout");
        read_word(20,value);assert(value==expected) else $fatal(1,"library op=%d result=%d expected=%d",op,value,expected);
    endtask
    task automatic page(input logic [8:0] count,input bit unsupported=0);
        exchange(1,{23'd0,count});
        for(int i=0;i<28;i++) exchange(2,i%7==6 ? ((unsupported && i==6) ? 32'h01010102 : 32'h02010100) : 32'h41414141,8'(i));
        exchange(3);
    endtask
    task automatic press(input logic [7:0] buttons);
        @(negedge clk);nav=buttons;@(negedge clk);nav=0;
    endtask
    initial begin
        logic [31:0] value, before_count;
        repeat(10) @(negedge hclk);reset=0;
        repeat(10) @(negedge clk);
        read_word(0,value);assert(value==32'h4e45534c);
        read_word(4,value);assert(value==32'h10000);
        read_word(8,value);assert(value==32'h18040100);
        be=3;write_word(16,0);be=15;read_word(12,value);assert(value[2]);
        exchange(0);read_word(12,value);assert(!value[2]);
        read_word(24,before_count);write_word(16,0);write_word(16,0);
        repeat(30) @(negedge hclk);read_word(24,value);assert(value==before_count+1);
        read_word(12,value);assert(value[2]); // busy submission did not replace held command
        write_word(48,32'hffffffff);read_word(48,value);assert(value==0);
        exchange(1,0,0,1,0,1); // old console epoch
        change_owner=1;exchange(1,0,0,1);change_owner=0;
        exchange(1,257,0,2);exchange(3,0,0,2);
        exchange(1,0);exchange(2,0,1,2);exchange(3,0,0,2);
        page(0);assert(enabled && packet[16:8]==0 && !opened);
        press(1);assert(opened);press(8'h20);assert(packet[7:0]==0 && !load_request);
        press(2);assert(!opened);
        exchange(6);page(1,1);press(1);press(1);assert(dut.event_code==0);
        exchange(6);page(9);press(1);
        press(8'h20);assert(packet[7:0]==1);
        press(8'h10);assert(packet[7:0]==0);
        press(8'h80);assert(packet[7:0]==4 && !packet[21] && packet[18:17]==1);
        exchange(1,9);exchange(2,32'h41414141);exchange(3,0,0,2);
        exchange(2,32'h41414141,1,1,1); // stale revision
        page(9);assert(packet[21]);
        press(8'h80);assert(packet[7:0]==8 && packet[18:17]==1);
        page(9);press(8'h20);assert(packet[7:0]==8);
        press(8'h40);assert(packet[7:0]==4);page(9);
        @(negedge clk);nav=1;#1;assert(load_request);
        @(negedge clk);nav=0;status=32'h00020102;
        repeat(4) @(negedge clk);
        assert(packet[18:17]==2);exchange(4);assert(packet[25:22]==1 && packet[18:17]==0);
        exchange(4,0,0,3);exchange(5,3);assert(packet[25:22]==3);
        @(negedge clk);nav=6;#1;assert(!cancel_request); // SELECT priority
        nav=2;#1;assert(cancel_request); // cancellation is also exported while loading
        @(negedge clk);nav=0;assert(!opened && packet[25:22]==9);
        status=32'h00030101;repeat(4) @(negedge clk);
        exchange(6);exchange(1,4);
        for(int i=0;i<6;i++) exchange(2,32'h41414141,8'(i));
        exchange(2,32'h02010102,6,2); // mapper2 cannot claim supported
        exchange(2,32'h82010100,6,2); // reserved bits
        status=32'h00040101;repeat(4) @(negedge clk);exchange(3,0,0,2);
        write_word(16,0);reset=1;repeat(10) @(negedge hclk);reset=0;repeat(10) @(negedge clk);
        assert(!enabled && !opened && packet==0);
        read_word(24,value);assert(value==0);
        $display("PASS: Phase 8C library actual MMIO/CDC, page commit, empty/single/multiple, boundaries, unsupported, stale/partial/order/reset and launch claim");
        $finish;
    end
    initial begin #20_000_000;$fatal(1,"library watchdog");end
endmodule
