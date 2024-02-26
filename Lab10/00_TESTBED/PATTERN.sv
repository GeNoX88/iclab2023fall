/*
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NYCU Institute of Electronic
2023 Autumn IC Design Laboratory 
Lab09: SystemVerilog Design and Verification 
File Name   : PATTERN.sv
Module Name : PATTERN
Release version : v1.0 (Release Date: Nov-2023)
Author : Jui-Huang Tsai (erictsai.10@nycu.edu.tw)
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
*/

`include "Usertype_BEV.sv"

program PATTERN(input clk, INF.PATTERN inf);
// program automatic PATTERN(input clk, INF.PATTERN inf);
import usertype::*;

//================================================================
// parameters & integer
//================================================================
parameter DRAM_p_r = "../00_TESTBED/DRAM/dram.dat";
parameter PATNUM = 3600; // 8538 is enough for calculating {type, size} with randc int [0:23], 4174 is enough for calculating {type, size} with 1964 random actions + more Make_drink
parameter OFFSET = 'h10000;

int pat_cnt;
//================================================================
// wire & registers 
//================================================================
// logic [7:0] golden_DRAM [((65536+8*256)-1):(65536+0)];  // 256 box
logic [7:0] golden_DRAM [(65536+0):((65536+8*256)-1)];  // 256 box
int no_ing_cnt;

Action act_loop[9];
assign act_loop = '{Make_drink, Make_drink, Supply, Supply, Check_Valid_Date, Check_Valid_Date, Make_drink, Check_Valid_Date, Supply};

Action action;
Bev_Type _type;
Bev_Size size;
Date today;
Barrel_No box;
ING supply_black;
ING supply_green;
ING supply_milk;
ING supply_pi;
//================================================================
// class random
//================================================================
class rand_act;
    rand Action act;

    constraint act_constraint{
        act inside {Make_drink, Supply, Check_Valid_Date};
    }
endclass

class rand_drink;
    randc int drink;

    constraint drink_constraint{
        drink inside {[0:23]};
    }
endclass

// class rand_size;

//     constraint size_constraint{
//         size inside { L, M, S };
//     }
// endclass

class rand_date;
    randc Date date;

    constraint date_constraint{
        date.M inside {[1:12]};
        (date.M==1 || date.M==3 || date.M==5 || date.M==7 || 
        date.M==8 || date.M==10 || date.M==12) -> date.D inside {[1:31]};

        (date.M==4 || date.M==6 || date.M==9 || date.M==11) -> date.D inside {[1:30]};

        (date.M==2) -> date.D inside {[1:28]};
    }
endclass

class rand_box;
    randc Barrel_No box;

    constraint box_constraint{
        box inside {[1:255]};
    }
endclass

class rand_supply_ing;
    randc ING supply_ing;

    constraint supply_ing_constraint {
        supply_ing inside {[0:4095]};
    }
endclass

//================================================================
// initial
//================================================================

rand_act act_obj = new();
rand_drink drink_obj = new();
rand_date date_obj = new();
rand_box box_obj = new();
rand_supply_ing supply_ing_obj = new();

initial begin
    $readmemh(DRAM_p_r, golden_DRAM);
    reset_task;
    no_ing_cnt = 0;
    for(pat_cnt=0; pat_cnt < PATNUM; pat_cnt++) begin
        if(pat_cnt==0) begin
            action = act_loop[0];
            inf.sel_action_valid = 1;
            inf.D.d_act[0] = action;
        end else @(negedge clk);
        input_task;
        wait_task;
        verify_task;
        $display("                  PASS PATTERN NO.%d", pat_cnt);
    end
    $display("===============================================================");
    $display("                      Congratulations");
    $display("===============================================================");
    $finish;
end



task reset_task; begin
    inf.sel_action_valid = 0;
    inf.type_valid = 0;
    inf.size_valid = 0;
    inf.date_valid = 0;
    inf.box_no_valid = 0;
    inf.box_sup_valid = 0;
    inf.D = 'x;

    inf.rst_n = 1;
    #(5) inf.rst_n = 0;
    #(5) inf.rst_n = 1;

    // if(inf.out_valid !==0 || inf.err_msg !== No_Err || inf.complete !==0) begin
    //     $display("====================================================================");
    //     $display("                 Output from BEV should be 0 after rst              ");
    //     $display("====================================================================");
    //     $finish;
    // end
end endtask

task input_task; begin
    if(pat_cnt!==0) begin
        if(pat_cnt<1800) action = act_loop[pat_cnt%9];
        else action = Make_drink;
        inf.sel_action_valid = 1;
        inf.D.d_act[0] = action;
    end

    @(negedge clk);
    inf.sel_action_valid = 0;
    inf.D = 'x;
    // repeat($urandom_range(0,3)) @(negedge clk);

    if(action===Make_drink) begin
        void'(drink_obj.randomize());
        inf.type_valid = 1;
        _type = drink_obj.drink/3;
        inf.D.d_type[0] = _type;
        @(negedge clk);
        inf.type_valid = 0;
        inf.D = 'x;
        
        // repeat($urandom_range(0,3)) @(negedge clk);
        
        inf.size_valid = 1;
        if(drink_obj.drink%3==0) size = L;
        else if(drink_obj.drink%3==1) size = M;
        else if(drink_obj.drink%3==2) size = S;
        inf.D.d_size[0] = size;
        @(negedge clk);
        inf.size_valid = 0;
        inf.D = 'x;
        
        // repeat($urandom_range(0,3)) @(negedge clk);

        inf.date_valid = 1;
        today.M = 12;
        today.D = 31;
        inf.D.d_date[0] = today;
        @(negedge clk);
        inf.date_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);

        inf.box_no_valid = 1;
        if(no_ing_cnt<20) begin
            box = 0;
            no_ing_cnt++;
        end else begin
            void'(box_obj.randomize());
            box = box_obj.box;
        end
        inf.D.d_box_no[0] = box;
        @(negedge clk);
        inf.box_no_valid = 0;
        inf.D = 'x;

    end else if(action===Supply) begin
        inf.date_valid = 1;
        void'(date_obj.randomize());
        if(date_obj.date.M==12 && date_obj.date.D==31) void'(date_obj.randomize());
        today = date_obj.date;
        inf.D.d_date[0] = today;
        @(negedge clk);
        inf.date_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);

        inf.box_no_valid = 1;
        void'(box_obj.randomize());
        box = box_obj.box;
        inf.D.d_box_no[0] = box;
        @(negedge clk);
        inf.box_no_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);
        // supply black tea
        inf.box_sup_valid = 1;
        supply_black = $urandom_range(0,4095);
        inf.D.d_ing[0] = supply_black;
        @(negedge clk);
        inf.box_sup_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);
        // supply green tea
        inf.box_sup_valid = 1;
        supply_green = $urandom_range(0, 4095);
        inf.D.d_ing[0] = supply_green;
        @(negedge clk);
        inf.box_sup_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);
        // supply milk
        inf.box_sup_valid = 1;
        supply_milk = $urandom_range(0, 4095);
        inf.D.d_ing[0] = supply_milk;
        @(negedge clk);
        inf.box_sup_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);
        // supply pinapple juice
        inf.box_sup_valid = 1;
        supply_pi = $urandom_range(0, 4095);
        inf.D.d_ing[0] = supply_pi;
        @(negedge clk);
        inf.box_sup_valid = 0;
        inf.D = 'x;
    end else if(action===Check_Valid_Date) begin
        inf.date_valid = 1;
        void'(date_obj.randomize());
        today = date_obj.date;
        inf.D.d_date[0] = today;
        @(negedge clk);
        inf.date_valid = 0;
        inf.D = 'x;

        // repeat($urandom_range(0,3)) @(negedge clk);

        inf.box_no_valid = 1;
        void'(box_obj.randomize());
        box = box_obj.box;
        inf.D.d_box_no[0] = box;
        @(negedge clk);
        inf.box_no_valid = 0;
        inf.D = 'x;             
    end
end endtask

task wait_task; begin
    while(inf.out_valid===0) begin
        @(negedge clk);
    end
end endtask

task verify_task; begin
    Month dram_month;
    Day dram_day;
    ING ing_black;
    ING ing_green;
    ING ing_milk;
    ING ing_pi;
    ING dram_black;
    ING dram_green;
    ING dram_milk;
    ING dram_pi;

    dram_month = golden_DRAM[OFFSET+box*8+4];
    dram_day = golden_DRAM[OFFSET+box*8];
    dram_black = {golden_DRAM[OFFSET+box*8+7], golden_DRAM[OFFSET+box*8+6][7:4]};
    dram_green = {golden_DRAM[OFFSET+box*8+6][3:0], golden_DRAM[OFFSET+box*8+5]};
    dram_milk  = {golden_DRAM[OFFSET+box*8+3], golden_DRAM[OFFSET+box*8+2][7:4]};
    dram_pi  = {golden_DRAM[OFFSET+box*8+2][3:0], golden_DRAM[OFFSET+box*8+1]};
    if(action==Make_drink) begin
        cal_ing(_type, size, ing_black, ing_green, ing_milk, ing_pi);
        if(today.M>dram_month || (today.M==dram_month && today.D>dram_day)) begin
            if(inf.err_msg !== No_Exp || inf.complete !== 0) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Make_drink expired, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end else if(dram_black<ing_black || dram_green<ing_green || dram_milk<ing_milk || dram_pi<ing_pi) begin
            if(inf.err_msg !== No_Ing || inf.complete !== 0) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Make_drink no ing, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end else begin
            if(inf.err_msg !== No_Err || inf.complete !== 1) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Make_drink no err, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
            {golden_DRAM[OFFSET+box*8+7], golden_DRAM[OFFSET+box*8+6][7:4]}=dram_black-ing_black;
            {golden_DRAM[OFFSET+box*8+6][3:0], golden_DRAM[OFFSET+box*8+5]}=dram_green-ing_green;
            {golden_DRAM[OFFSET+box*8+3], golden_DRAM[OFFSET+box*8+2][7:4]}=dram_milk-ing_milk;
            {golden_DRAM[OFFSET+box*8+2][3:0], golden_DRAM[OFFSET+box*8+1]}=dram_pi-ing_pi;
        end
    end else if(action==Supply) begin
        if((supply_black>~dram_black) || (supply_green>~dram_green) || (supply_milk>~dram_milk) || (supply_pi>~dram_pi)) begin
            if(inf.err_msg !== Ing_OF || inf.complete !== 0) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Supply overflow, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end else begin
            if(inf.err_msg !== No_Err || inf.complete !== 1) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Supply no err, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end
        golden_DRAM[OFFSET+box*8+4] = today.M;
        golden_DRAM[OFFSET+box*8] = today.D;
        if(supply_black>~dram_black) {golden_DRAM[OFFSET+box*8+7], golden_DRAM[OFFSET+box*8+6][7:4]} = 12'hfff;
        else {golden_DRAM[OFFSET+box*8+7], golden_DRAM[OFFSET+box*8+6][7:4]} = (dram_black+supply_black);
        
        if(supply_green>~dram_green) {golden_DRAM[OFFSET+box*8+6][3:0], golden_DRAM[OFFSET+box*8+5]} = 12'hfff;
        else {golden_DRAM[OFFSET+box*8+6][3:0], golden_DRAM[OFFSET+box*8+5]} = (dram_green+supply_green);
        
        if(supply_milk>~dram_milk) {golden_DRAM[OFFSET+box*8+3], golden_DRAM[OFFSET+box*8+2][7:4]} = 12'hfff;
        else {golden_DRAM[OFFSET+box*8+3], golden_DRAM[OFFSET+box*8+2][7:4]} = (dram_milk+supply_milk);
        
        if(supply_pi>~dram_pi) {golden_DRAM[OFFSET+box*8+2][3:0], golden_DRAM[OFFSET+box*8+1]} = 12'hfff;
        else {golden_DRAM[OFFSET+box*8+2][3:0], golden_DRAM[OFFSET+box*8+1]} = (dram_pi+supply_pi);

    end else if(action==Check_Valid_Date) begin
        if(today.M>dram_month || (today.M==dram_month && today.D>dram_day)) begin
            if(inf.err_msg !== No_Exp || inf.complete !== 0) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Check_Valid_Date expired, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end else begin
            if(inf.err_msg !== No_Err || inf.complete !== 1) begin
                $display("===================================================");
                $display("                  Wrong Answer");
                $display("      Check_Valid_Date no err, but err_msg:%d, complete:%b", inf.err_msg, inf.complete);
                $display("===================================================");
                $finish;
            end
        end
    end
end endtask

task cal_ing(
    input Bev_Type _type,
    input Bev_Size size,
    output int black,
    output int green,
    output int milk,
    output int pi
    ); begin

    black = 0;
    green = 0;
    milk = 0;
    pi = 0;

    case(_type)
        Black_Tea: begin
            case(size)
                L:black = 960;
                M:black = 720;
                S:black = 480;
            endcase
        end
        Milk_Tea: begin
            case(size)
                L:begin
                    black = 720;
                    milk = 240;
                end
                M:begin
                    black = 540;
                    milk = 180;
                end
                S:begin
                    black = 360;
                    milk = 120;
                end
            endcase
        end
        Extra_Milk_Tea: begin
            case(size)
                L:begin
                    black = 480;
                    milk = 480;
                end
                M:begin
                    black = 360;
                    milk = 360;
                end
                S:begin
                    black = 240;
                    milk = 240;
                end
            endcase
        end
        Green_Tea: begin
            case(size)
                L:green = 960;
                M:green = 720;
                S:green = 480;
            endcase
        end
        Green_Milk_Tea: begin
            case(size)
                L:begin
                    green = 480;
                    milk = 480;
                end
                M:begin
                    green = 360;
                    milk = 360;
                end
                S:begin
                    green = 240;
                    milk = 240;
                end
            endcase
        end
        Pineapple_Juice: begin
            case(size)
                L:pi = 960;
                M:pi = 720;
                S:pi = 480;
            endcase
        end
        Super_Pineapple_Tea: begin
            case(size)
                L:begin
                    black = 480;
                    pi = 480;
                end
                M:begin
                    black = 360;
                    pi = 360;
                end
                S:begin
                    black = 240;
                    pi = 240;
                end
            endcase
        end
        Super_Pineapple_Milk_Tea: begin
            case(size)
                L:begin
                    black = 480;
                    milk = 240;
                    pi = 240;
                end
                M:begin
                    black = 360;
                    milk = 180;
                    pi = 180;
                end
                S:begin
                    black = 240;
                    milk = 120;
                    pi = 120;
                end
            endcase
        end
    endcase
end endtask


endprogram
