/*
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NYCU Institute of Electronic
2023 Autumn IC Design Laboratory 
Lab10: SystemVerilog Coverage & Assertion
File Name   : CHECKER.sv
Module Name : CHECKER
Release version : v1.0 (Release Date: Nov-2023)
Author : Jui-Huang Tsai (erictsai.10@nycu.edu.tw)
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
*/

`include "Usertype_BEV.sv"
module Checker(input clk, INF.CHECKER inf);
import usertype::*;

/*
    Coverage Part
*/


/*
1. Each case of Beverage_Type should be select at least 100 times.
*/

Bev_Type bev_type;
always_ff @(posedge clk iff inf.type_valid) begin
    bev_type = inf.D.d_type[0];
end


/*
2.	Each case of Bererage_Size should be select at least 100 times.
*/

/*
3.	Create a cross bin for the SPEC1 and SPEC2. Each combination should be selected at least 100 times. 
(Black Tea, Milk Tea, Extra Milk Tea, Green Tea, Green Milk Tea, Pineapple Juice, Super Pineapple Tea, Super Pineapple Tea) x (L, M, S)
*/

covergroup CG_1_2_3 @(posedge clk iff inf.size_valid);
    option.at_least = 100;
    btype: coverpoint bev_type {
        bins b_bev_type[] = {[Black_Tea:Super_Pineapple_Milk_Tea]};
    }
    bsize: coverpoint inf.D.d_size[0] {
        bins b_bev_size[] = {L, M, S};
    }
    btype_X_bsize: cross btype, bsize;
endgroup

CG_1_2_3 CG_1_2_3_inst = new();

/*
4.	Output signal inf.err_msg should be No_Err, No_Exp, No_Ing and Ing_OF, each at least 20 times. (Sample the value when inf.out_valid is high)
*/

covergroup CG_4 @(posedge clk iff inf.out_valid);
    option.at_least = 20;
    msg: coverpoint inf.err_msg {
        bins b_msg[] = {No_Err, No_Exp, No_Ing, Ing_OF};
    }
endgroup

CG_4 CG_4_inst = new();

/*
5.	Create the transitions bin for the inf.D.act[0] signal from [0:2] to [0:2]. Each transition should be hit at least 200 times. (sample the value at posedge clk iff inf.sel_action_valid)
*/

// Action act_now;
// Action act_previous;
// always_ff @(posedge clk) begin
//     if (inf.sel_action_valid) begin
//         act_previous = act_now;
//         act_now = inf.D.d_act[0];
//     end
// end

covergroup CG_5 @(posedge clk iff inf.sel_action_valid);
    option.at_least = 200;
    // act_previous: coverpoint act_previous {
    //     bins b_act_previous[] = {[Make_drink:Check_Valid_Date]};
    // }
    // act_now: coverpoint act_now {
    //     bins b_act_now[] = {[Make_drink:Check_Valid_Date]};
    // }
    // act_X_act: cross act_previous, act_now;
    act_X_act: coverpoint inf.D.d_act[0] {
        bins b_act[] = ([Make_drink:Check_Valid_Date]=>[Make_drink:Check_Valid_Date]);
    }
endgroup

CG_5 CG_5_inst = new();

/*
6.	Create a covergroup for material of supply action with auto_bin_max = 32, and each bin have to hit at least one time.
*/

/*
    Create instances of Spec1, Spec2, Spec3, Spec4, Spec5, and Spec6
*/
// Spec1_2_3 cov_inst_1_2_3 = new();

covergroup CG_6 @(posedge clk iff inf.box_sup_valid);
    option.at_least = 1;
    option.auto_bin_max = 32;
    supply_ing: coverpoint inf.D.d_ing[0];
endgroup

CG_6 CG_6_inst = new();







/*
    Asseration
*/

/*
    If you need, you can declare some FSM, logic, flag, and etc. here.
*/

/*
    1. All outputs signals (including BEV.sv and bridge.sv) should be zero after reset.
*/

property SPEC_1;
    @(posedge inf.rst_n) 1 |-> @(posedge clk)
    (inf.out_valid===0 &&
    inf.complete===0 &&
    inf.err_msg===0 &&
    inf.C_addr===0 &&
    inf.C_r_wb===0 &&
    inf.C_in_valid===0 &&
    inf.C_data_w===0 &&
    inf.C_out_valid===0 &&
    inf.C_data_r===0 &&
    inf.AR_VALID===0 && 
    inf.AR_ADDR===0 && 
    inf.R_READY===0 && 
    inf.AW_VALID===0 && 
    inf.AW_ADDR===0 && 
    inf.W_VALID===0 && 
    inf.W_DATA===0 && 
    inf.B_READY===0 &&
    inf.AR_READY===0 && 
    inf.R_VALID===0 && 
    inf.R_RESP===0 && 
    inf.R_DATA===0 && 
    inf.AW_READY===0 && 
    inf.W_READY===0 && 
    inf.B_VALID===0 && 
    inf.B_RESP===0);
endproperty

assert property(SPEC_1) else begin
    $display("=============================================================");
    $display("                 Assertion 1 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    2.	Latency should be less than 1000 cycles for each operation.
*/

property SPEC_2_Make_drink;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Make_drink)  
    ##[1:4] inf.type_valid ##[1:4] inf.size_valid ##[1:4] inf.date_valid ##[1:4] inf.box_no_valid
    |-> ##[1:999] inf.out_valid;
endproperty

assert property(SPEC_2_Make_drink) else begin
    $display("=============================================================");
    $display("                    SPEC_2_Make_drink                        ");
    $display("                 Assertion 2 is violated                     ");
    $display("=============================================================");
    $fatal;
end

property SPEC_2_Supply;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Supply)  
    ##[1:4] inf.date_valid
    ##[1:4] inf.box_no_valid
    ##[1:4] (inf.box_sup_valid[->4])
    |-> ##[1:999] inf.out_valid;
endproperty

assert property(SPEC_2_Supply) else begin
    $display("=============================================================");
    $display("                     SPEC_2_Supply                           ");
    $display("                 Assertion 2 is violated                     ");
    $display("=============================================================");
    $fatal;
end
property SPEC_2_Check_Valid_Date;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Check_Valid_Date)  
    ##[1:4] inf.date_valid ##[1:4] inf.box_no_valid
    |-> ##[1:999] inf.out_valid;
endproperty

assert property(SPEC_2_Check_Valid_Date) else begin
    $display("=============================================================");
    $display("                 SPEC_2_Check_Valid_Date                     ");
    $display("                 Assertion 2 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    3. If action is completed (complete=1), err_msg should be 2’b0 (no_err).
*/
property SPEC_3;
    @(negedge clk) (inf.out_valid!==0 && inf.complete) |-> inf.err_msg===No_Err; 
endproperty

assert property(SPEC_3) else begin
    $display("=============================================================");
    $display("                 Assertion 3 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    4. Next input valid will be valid 1-4 cycles after previous input valid fall.
*/

property SPEC_4_Make_drink;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Make_drink) |-> 
    ##[1:4] inf.type_valid 
    ##[1:4] inf.size_valid 
    ##[1:4] inf.date_valid 
    ##[1:4] inf.box_no_valid; 
endproperty
property SPEC_4_Supply;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Supply) |-> 
    ##[1:4] inf.date_valid 
    ##[1:4] inf.box_no_valid 
    ##[1:4] inf.box_sup_valid 
    ##[1:4] inf.box_sup_valid 
    ##[1:4] inf.box_sup_valid 
    ##[1:4] inf.box_sup_valid; 
endproperty
property SPEC_4_Check_Valid_Date;
    @(posedge clk) (inf.sel_action_valid && inf.D.d_act[0]===Check_Valid_Date) |-> 
    ##[1:4] inf.date_valid 
    ##[1:4] inf.box_no_valid; 
endproperty

assert property(SPEC_4_Make_drink) else begin
    $display("=============================================================");
    $display("                   SPEC_4_Make_drink                         ");
    $display("                 Assertion 4 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_4_Supply) else begin
    $display("=============================================================");
    $display("                     SPEC_4_Supply                           ");
    $display("                 Assertion 4 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_4_Check_Valid_Date) else begin
    $display("=============================================================");
    $display("                 SPEC_4_Check_Valid_Date                     ");
    $display("                 Assertion 4 is violated                     ");
    $display("=============================================================");
    $fatal;
end






/*
    5. All input valid signals won't overlap with each other. 
*/
property SPEC_5_sel_action_valid;
    @(posedge clk) inf.sel_action_valid |-> 
    !inf.type_valid && !inf.size_valid && !inf.date_valid && !inf.box_no_valid && !inf.box_sup_valid; 
endproperty
property SPEC_5_type_valid;
    @(posedge clk) inf.type_valid |-> 
    !inf.sel_action_valid && !inf.size_valid && !inf.date_valid && !inf.box_no_valid && !inf.box_sup_valid; 
endproperty
property SPEC_5_size_valid;
    @(posedge clk) inf.size_valid |-> 
    !inf.type_valid && !inf.sel_action_valid && !inf.date_valid && !inf.box_no_valid && !inf.box_sup_valid; 
endproperty
property SPEC_5_date_valid;
    @(posedge clk) inf.date_valid |-> 
    !inf.type_valid && !inf.size_valid && !inf.sel_action_valid && !inf.box_no_valid && !inf.box_sup_valid; 
endproperty
property SPEC_5_box_no_valid;
    @(posedge clk) inf.box_no_valid |-> 
    !inf.type_valid && !inf.size_valid && !inf.date_valid && !inf.sel_action_valid && !inf.box_sup_valid; 
endproperty
property SPEC_5_box_sup_valid;
    @(posedge clk) inf.box_sup_valid |-> 
    !inf.type_valid && !inf.size_valid && !inf.date_valid && !inf.box_no_valid && !inf.sel_action_valid; 
endproperty

assert property(SPEC_5_sel_action_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_5_type_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_5_size_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_5_date_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_5_box_no_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_5_box_sup_valid) else begin
    $display("=============================================================");
    $display("                 Assertion 5 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    6. Out_valid can only be high for exactly one cycle.
*/
property SPEC_6;
    @(posedge clk) inf.out_valid!==0 |=> !inf.out_valid; 
endproperty

assert property(SPEC_6) else begin
    $display("=============================================================");
    $display("                 Assertion 6 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    7. Next operation will be valid 1-4 cycles after out_valid fall.
*/
property SPEC_7;
    @(posedge clk) inf.out_valid ##1 !inf.out_valid |-> ##[0:3] inf.sel_action_valid; 
endproperty

assert property(SPEC_7) else begin
    $display("=============================================================");
    $display("                 Assertion 7 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    8. The input date from pattern should adhere to the real calendar. (ex: 2/29, 3/0, 4/31, 13/1 are illegal cases)
*/
property SPEC_8_MONTH;
    @(posedge clk) 
    inf.date_valid |-> inf.D.d_date[0].M inside {[1:12]}; 
endproperty
property SPEC_8_JAN;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==1 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_FEB;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==2 |-> inf.D.d_date[0].D inside {[1:28]}; 
endproperty
property SPEC_8_MAR;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==3 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_APR;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==4 |-> inf.D.d_date[0].D inside {[1:30]}; 
endproperty
property SPEC_8_MAY;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==5 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_JUN;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==6 |-> inf.D.d_date[0].D inside {[1:30]}; 
endproperty
property SPEC_8_JUL;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==7 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_AUG;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==8 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_SEP;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==9 |-> inf.D.d_date[0].D inside {[1:30]}; 
endproperty
property SPEC_8_OCT;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==10 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty
property SPEC_8_NOV;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==11 |-> inf.D.d_date[0].D inside {[1:30]}; 
endproperty
property SPEC_8_DEC;
    @(posedge clk) 
    inf.date_valid && inf.D.d_date[0].M==12 |-> inf.D.d_date[0].D inside {[1:31]}; 
endproperty

assert property(SPEC_8_MONTH) else begin
    $display("=============================================================");
    $display("                       SPEC_8_MONTH                          ");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_JAN) else begin
    $display("=============================================================");
    $display("                       SPEC_8_JAN                            ");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_FEB) else begin
    $display("=============================================================");
    $display("                        SPEC_8_FEB                           ");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_MAR) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_APR) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_MAY) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_JUN) else begin
    $display("=============================================================");
    $display("                       SPEC_8_JUN                            ");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_JUL) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_AUG) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_SEP) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_OCT) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_NOV) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end
assert property(SPEC_8_DEC) else begin
    $display("=============================================================");
    $display("                 Assertion 8 is violated                     ");
    $display("=============================================================");
    $fatal;
end

/*
    9. C_in_valid can only be high for one cycle and can't be pulled high again before C_out_valid
*/

property SPEC_9_one_cycle;
    @(posedge clk) 
    inf.C_in_valid!==0 |=> inf.C_in_valid===0; 
endproperty

assert property(SPEC_9_one_cycle) else begin
    $display("=============================================================");
    $display("                     SPEC_9_one_cycle                        ");
    $display("                 Assertion 9 is violated                     ");
    $display("=============================================================");
    $fatal;
end
property SPEC_9_wait_C_out_valid;
    @(posedge clk) 
    inf.C_in_valid!==0 |=> inf.C_in_valid===0 until_with inf.C_out_valid!==0; 
endproperty
assert property(SPEC_9_wait_C_out_valid) else begin
    $display("=============================================================");
    $display("                 SPEC_9_wait_C_out_valid                     ");
    $display("                 Assertion 9 is violated                     ");
    $display("=============================================================");
    $fatal;
end

endmodule