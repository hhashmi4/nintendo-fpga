`timescale 1ns/1ps
// Four immutable records per committed page. No paths, ROM parsing or loader.
module nes_library_control (
    input logic clk, reset,
    input logic [31:0] console_status,
    input logic [7:0] navigation,
    input logic focus, ownership_change,
    input logic command_valid,
    input logic [95:0] command_word,
    output logic command_done,
    output logic [127:0] command_response,
    output logic enabled, opened, load_request, cancel_request,
    output logic [927:0] packet
);
    import debug_font_pkg::*;
    logic [895:0] active_data, staging;
    logic [31:0] revision, status_word;
    logic [8:0] total, staged_total;
    logic [7:0] selected, target_index;
    logic [1:0] event_code;
    logic [3:0] stage, last_result;
    logic page_valid, truncated, staged_truncated, staging_valid, seen;
    logic [5:0] words_received;
    logic [15:0] previous_epoch;
    logic [3:0] previous_state;
    logic [31:0] selected_meta, payload;
    logic [7:0] opcode, word_index;
    logic take_command, busy, eligible, local_action;
    logic [31:0] result;
    assign opcode=command_word[7:0];
    assign word_index=command_word[15:8];
    assign payload=command_word[95:64];
    assign take_command=command_valid && !seen;
    assign busy=stage>=1 && stage<=4;
    assign selected_meta=active_data[int'(selected[1:0])*224+192 +: 32];
    assign eligible=page_valid && total!=0 && selected_meta[25:24]==2;
    assign load_request=enabled && opened && console_status[3:0]==1 && !busy &&
        event_code==0 && eligible && (navigation[0] || navigation[3]) && !navigation[2] && !navigation[1];
    assign cancel_request=enabled && opened &&
        (console_status[3:0]==1 || console_status[3:0]==2 || console_status[3:0]==6) &&
        navigation[1] && !navigation[2];
    assign local_action=enabled && navigation!=0;
    assign status_word={1'b0,last_result,truncated,stage,page_valid,opened,enabled,event_code,total,selected};
    assign packet={active_data,status_word};
    always_comb begin
        target_index=selected;
        if(navigation[4] && selected!=0) target_index=selected-1'b1;
        else if(!navigation[4] && navigation[5] && {1'b0,selected}+9'd1<total) target_index=selected+1'b1;
        else if(!navigation[4] && !navigation[5] && navigation[6])
            target_index=selected>=4 ? selected-8'd4 : 8'd0;
        else if(!navigation[4] && !navigation[5] && !navigation[6] && navigation[7] && total!=0)
            target_index={1'b0,selected}+9'd4<total ? selected+8'd4 : 8'(total-1'b1);
        result=0;
        if(opcode>6) result=2;
        else if(opcode!=0 && (command_word[31:16]!=console_status[31:16] ||
                command_word[63:32]!=revision || local_action || ownership_change ||
                previous_epoch!=console_status[31:16])) result=1;
        else case(opcode)
            0: begin end
            1: if(console_status[3:0]!=1 || busy || payload[31:10]!=0 || payload[8:0]>256 ||
                   (enabled && (payload[8:0]!=total || payload[9]!=truncated)) ||
                   (enabled && event_code!=1)) result=2;
            2: begin
                if(!staging_valid || word_index!={2'd0,words_received} || words_received>=28) result=2;
                else if(word_index%7==6 && (payload[31:27]!=0 || payload[25:24]==3 ||
                    (payload[25:24]==2 && (payload[7:0]!=0 || payload[26] ||
                     (payload[15:8]!=1 && payload[15:8]!=2) || payload[23:16]>1)))) result=2;
            end
            3: if(!staging_valid || words_received!=28) result=2;
            4: if(!enabled || event_code!=2 || console_status[3:0]!=2) result=3;
            5: if(!enabled || payload>10 || payload==1 ||
                  ((payload==2 || payload==3) && console_status[3:0]!=2) ||
                  (payload==4 && (console_status[3:0]!=1 || !console_status[9]))) result=2;
            6: if(console_status[3:0]!=1 && console_status[3:0]!=6 && console_status[3:0]!=7) result=2;
            default: result=2;
        endcase
        if(opcode!=0 && opcode!=2 && word_index!=0) result=2;
    end
    always_ff @(posedge clk) begin
        if(reset) begin
            active_data<=0; staging<=0; revision<=1; total<=0; staged_total<=0;
            selected<=0; event_code<=0; stage<=0; last_result<=0; enabled<=0; opened<=0;
            page_valid<=0; truncated<=0; staged_truncated<=0; staging_valid<=0;
            words_received<=0; seen<=0; command_done<=0; command_response<=0;
            previous_epoch<=0; previous_state<=0;
        end else begin
            seen<=command_valid; command_done<=take_command;
            previous_epoch<=console_status[31:16]; previous_state<=console_status[3:0];
            if(previous_epoch!=console_status[31:16]) staging_valid<=0;
            if(console_status[3:0]==4 && previous_state!=4 && enabled) begin
                stage<=11; last_result<=11; event_code<=0; revision<=revision+1'b1;
            end
            if(previous_state==4 && console_status[3:0]!=4) stage<=0;
            if(console_status[3:0]==7) begin opened<=0; event_code<=0; end
            if(enabled && navigation[1] && (console_status[3:0]==1 || console_status[3:0]==2 || console_status[3:0]==6)) begin
                opened<=0; event_code<=0; staging_valid<=0; revision<=revision+1'b1;
                if(console_status[3:0]==2) begin stage<=9; last_result<=9; end
                else stage<=0;
            end else if(enabled && console_status[3:0]==1 && !navigation[2]) begin
                if(!opened && (navigation[3] || (navigation[0] && !focus))) begin
                    opened<=1; revision<=revision+1'b1;
                    if(!page_valid) event_code<=1;
                end else if(opened && !busy && event_code==0) begin
                    if(load_request) begin event_code<=2; revision<=revision+1'b1; stage<=0; end
                    else if(!navigation[0] && !navigation[3] && target_index!=selected) begin
                        selected<=target_index; revision<=revision+1'b1; stage<=0; staging_valid<=0;
                        if(target_index[7:2]!=selected[7:2]) begin page_valid<=0; event_code<=1; end
                    end
                end
            end
            // Leaving a locally requested load by any system intention invalidates
            // its host claim. BEGIN stays LOADING; ACTIVATE has already been claimed.
            if(previous_state==2 && console_status[3:0]!=2 && event_code==2) begin
                event_code<=0; stage<=9; last_result<=9; revision<=revision+1'b1;
            end
            if(take_command) begin
                command_response<={revision,status_word,console_status,result};
                if(result==0) case(opcode)
                    1: begin staging_valid<=1; words_received<=0; staged_total<=payload[8:0]; staged_truncated<=payload[9]; end
                    2: begin
                        if(word_index%7==6) staging[int'(word_index)*32 +: 32]<=payload;
                        else for(int b=0;b<4;b++)
                            staging[int'(word_index)*32+b*8 +: 8]<=debug_font_supported(payload[b*8 +: 8]) ? payload[b*8 +: 8] : 8'h2e;
                        words_received<=words_received+1'b1;
                    end
                    3: begin
                        active_data<=staging; total<=staged_total; truncated<=staged_truncated;
                        page_valid<=1; enabled<=1; event_code<=0; staging_valid<=0; revision<=revision+1'b1;
                    end
                    4: begin event_code<=0; stage<=1; revision<=revision+1'b1; end
                    5: begin
                        stage<=payload[3:0]; revision<=revision+1'b1;
                        if(payload>=5) last_result<=payload[3:0];
                    end
                    6: begin
                        enabled<=0; opened<=0; total<=0; selected<=0; page_valid<=0;
                        event_code<=0; staging_valid<=0; stage<=0; last_result<=0;
                        revision<=revision+1'b1;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
