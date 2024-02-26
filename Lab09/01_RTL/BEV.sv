module BEV(input clk, INF.BEV_inf inf);
import usertype::*;
// This file contains the definition of several state machines used in the BEV (Beverage) System RTL design.
// The state machines are defined using SystemVerilog enumerated types.
// The state machines are:
// - state_t: used to represent the overall state of the BEV system
//
// Each enumerated type defines a set of named states that the corresponding process can be in.

// REGISTERS
Bev_Type r_type;
Bev_Size r_size;
Month r_month;
Day r_day;
Month r_month_exp;
Day r_day_exp;
Barrel_No r_box_no;
Barrel_No r_addr;


ING vol_black;
ING vol_green;
ING vol_milk;
ING vol_pi;
ING r_sup_black;
ING r_sup_green;
ING r_sup_milk;
ING r_sup_pi;

logic black_less_than;
logic green_less_than;
logic milk_less_than ;
logic pi_less_than;
logic bg_less_than;
logic mp_less_than;
logic bgmp;
logic check_date;
logic make;
logic make_err;
logic make_comp;
logic supply;
logic got_supply_data;
logic got_pi;
logic last_sup;
logic data_r;
logic DRAM_writing;
logic checking_date;
logic is_expired;
logic checking_ing;
logic checking_black;
logic checking_green;
logic checking_milk;
logic checking_pi;
logic wait_for_r;
logic wait_for_data;
logic [1:0] supply_cnt;
logic checking_0;
logic checking_0_r;
logic checking_1;
logic checking_2;
logic checking_3;
logic checking_4;
logic ing_ok;
ING mux_black;
ING mux_green;
ING mux_milk;
ING mux_pi;
ING r_mux_black;
ING r_mux_green;
ING r_mux_milk;
ING r_mux_pi;

logic [11:0] cmp[0:1];
logic [11:0] cmp_black[0:1];
logic [11:0] cmp_green[0:1];
logic [11:0] cmp_milk[0:1];
logic [11:0] cmp_pi[0:1];
logic [11:0] add[0:1];
logic [11:0] sum;
logic checking_black_r;
logic r_cmp_black;
logic r_cmp_green;
logic r_cmp_milk ;
logic r_cmp_pi;
logic r_supply;
logic trig_wait_for_data;
assign trig_wait_for_data = wait_for_r && !DRAM_writing;

assign inf.C_data_w = {vol_black, vol_green, {4'd0, r_month_exp}, vol_milk, vol_pi, {3'd0, r_day_exp}};
assign is_expired = r_month > r_month_exp || r_month==r_month_exp && r_day>r_day_exp;

// RCAS_12bit(add[0],add[1],1'b0,sum);

assign sum = add[0]+add[1];
assign bgmp = bg_less_than || mp_less_than;
assign black_less_than = cmp_black[0] < cmp_black[1];
assign green_less_than = cmp_green[0] < cmp_green[1];
assign milk_less_than = cmp_milk[0] < cmp_milk[1];
assign pi_less_than = cmp_pi[0] < cmp_pi[1];
assign last_sup = supply_cnt==3 && inf.box_sup_valid;
assign data_r = wait_for_data && inf.C_out_valid;

// cmp_black[0:1]
always_comb begin
    cmp_black[0] = make? vol_black[11:0]:~vol_black[11:0];
    cmp_black[1] = make? r_mux_black[11:0]:r_sup_black[11:0];
end
// cmp_green[0:1]
always_comb begin
    cmp_green[0] = make? vol_green[11:0]:~vol_green[11:0];
    cmp_green[1] = make? r_mux_green[11:0]:r_sup_green[11:0];
end
// cmp_milk[0:1]
always_comb begin
    cmp_milk[0] = make? vol_milk[11:0]:~vol_milk[11:0];
    cmp_milk[1] = make? r_mux_milk[11:0]:r_sup_milk[11:0];
end
// cmp_pi[0:1]
always_comb begin
    cmp_pi[0] = make? vol_pi[11:0]:~vol_pi[11:0];
    cmp_pi[1] = make? r_mux_pi[11:0]:r_sup_pi[11:0];
end

always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        bg_less_than <= 0;
    end else if(checking_0)
        bg_less_than <= black_less_than || green_less_than;
end
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        mp_less_than <= 0;
    end else if(checking_0)
        mp_less_than <= milk_less_than || pi_less_than;
end
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        r_cmp_black <= 0;
        r_cmp_green <= 0;
        r_cmp_milk <= 0;
        r_cmp_pi <= 0;
    end else if(checking_0) begin
        r_cmp_black <= black_less_than;
        r_cmp_green <= green_less_than;
        r_cmp_milk <= milk_less_than;
        r_cmp_pi <= pi_less_than;
    end
end
// add[0:1]
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        add[0] <= 0;
        add[1] <= 0;
    end else if(checking_0) begin
        add[0] <= vol_black;
        add[1] <= supply? r_sup_black:(~r_mux_black+1);
    end else if(checking_0_r) begin
        add[0] <= vol_green;
        add[1] <= supply? r_sup_green:(~r_mux_green+1);
    end else if(checking_1) begin
        add[0] <= vol_milk;
        add[1] <= supply? r_sup_milk:(~r_mux_milk+1);
    end else if(checking_2) begin
        add[0] <= vol_pi;
        add[1] <= supply? r_sup_pi:(~r_mux_pi+1);
    end
end

// check_date
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) check_date <= 0;
    else if(inf.sel_action_valid) begin
        if(!inf.D.d_act[0][0]) check_date <= 1;
        else check_date <= 0;
    end
end
// make
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) make <= 0;
    else if(inf.sel_action_valid) begin
        if(inf.D.d_act[0]==Make_drink) make <= 1;
        else make <= 0;
    end
end
// supply
assign supply = !check_date;
// r_supply
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) r_supply <= 0;
    else if(checking_0) begin
        r_supply <= supply;
    end 
end
// wait_for_r
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) wait_for_r <= 0;
    else if(inf.box_no_valid) begin
        wait_for_r <= 1;
    end else if(!DRAM_writing)
        wait_for_r <= 0;
end
// wait_for_data
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) wait_for_data <= 0;
    else if(trig_wait_for_data) wait_for_data <= 1;
    else if(data_r) wait_for_data <= 0;
end
// got_pi
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) got_pi <= 0;
    else if(last_sup) got_pi <= 1;
    else if(got_supply_data) got_pi <= 0;
end
// got_supply_data
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) got_supply_data <= 0;
    else if(supply && data_r) got_supply_data <= 1;
    else if(got_pi) got_supply_data <= 0;
end
// supply_cnt
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) supply_cnt <= 0;
    else if(inf.box_sup_valid) supply_cnt <= supply_cnt+1;
end
// checking_0
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_0 <= 0;
    else if(!supply && data_r 
    || last_sup && data_r
    || got_pi && data_r
    || last_sup && got_supply_data)
        checking_0 <= 1;
    else checking_0 <= 0;
end
// checking_0_r
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_0_r <= 0;
    else checking_0_r <= checking_0;
end
// checking_1
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_1 <= 0;
    else if(checking_0_r && 
    (make && !(is_expired || (bgmp)) || supply)) 
        checking_1 <= 1;
    else checking_1 <= 0;
end
// checking_2
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_2 <= 0;
    else if(checking_1) checking_2 <= 1;
    else checking_2 <= 0;
end
// checking_3
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_3 <= 0;
    else if(checking_2) checking_3 <= 1;
    else checking_3 <= 0;
end
// checking_4
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) checking_4 <= 0;
    else if(checking_3) checking_4 <= 1;
    else checking_4 <= 0;
end



// 4096-960=3136
// 4096-720=3376
// 4096-480=3616
// 4096-360=3736
// 4096-240=3856
// 4096-180=3916
// 4096-120=3976

// r_type
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) r_type <= Black_Tea;
    else if(inf.type_valid) r_type <= inf.D.d_type[0]; 
end
// r_size
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) r_size <= L; // L=2'b00
    else if(inf.size_valid) r_size <= inf.D.d_size[0]; 
end
// {r_month, r_day}
always_ff @(posedge clk) begin
    if(inf.date_valid) {r_month, r_day} <= inf.D.d_date[0];
end
// {r_month_exp, r_day_exp}
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) {r_month_exp, r_day_exp} <= 0;
    else if(data_r) begin
        r_month_exp <= inf.C_data_r[39:32]; // 8 bits
        r_day_exp <= inf.C_data_r[7:0]; // 8 bits
    end else if(supply && checking_0) {r_month_exp, r_day_exp} <= {r_month, r_day};
end
// r_box_no
always_ff @(posedge clk) begin
    if(inf.box_no_valid) r_box_no <= inf.D.d_box_no[0]; 
end

// r_sup_black
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        r_sup_black <= 0;
    end else if(inf.box_sup_valid && supply_cnt==0) begin
        r_sup_black <= inf.D.d_ing[0];
    end
end
// r_sup_green
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        r_sup_green <= 0;
    end else if(inf.box_sup_valid && supply_cnt==1) begin
        r_sup_green <= inf.D.d_ing[0];
    end
end
// r_sup_milk
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        r_sup_milk <= 0;
    end else if(inf.box_sup_valid && supply_cnt==2) begin
        r_sup_milk <= inf.D.d_ing[0];
    end
end
// r_sup_pi
always_ff @(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        r_sup_pi <= 0;
    end else if(last_sup) begin
        r_sup_pi <= inf.D.d_ing[0];
    end
end

// inf.C_in_valid
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.C_in_valid <= 0;
    end else if(trig_wait_for_data || checking_4) begin
        inf.C_in_valid <= 1;
    end else begin
        inf.C_in_valid <= 0;
    end
end
// inf.C_addr
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.C_addr <= 0;
    end else if(checking_1 || trig_wait_for_data) begin
        inf.C_addr <= r_box_no;
    end
end
// assign inf.C_addr = r_box_no;

// inf.C_r_wb
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.C_r_wb <= 0;
    end else if(trig_wait_for_data) begin
        inf.C_r_wb <= 1;
    end else begin
        inf.C_r_wb <= 0;
    end
end
// vol_black
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        vol_black <= 0;
    end else if(inf.C_out_valid)  begin
        vol_black <= inf.C_data_r[63:52];
    end else if(checking_0_r) begin
        if(r_supply && r_cmp_black) vol_black <= 12'hfff;
        else vol_black <= sum;
    end
end
// vol_green
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        vol_green <= 0;
    end else if(inf.C_out_valid)  begin
        vol_green <= inf.C_data_r[51:40];
    end else if(checking_1) begin
        if(r_supply && r_cmp_green) vol_green <= 12'hfff;
        else vol_green <= sum;
    end
end
// vol_milk
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        vol_milk <= 0;
    end else if(inf.C_out_valid)  begin
        vol_milk <= inf.C_data_r[31:20];
    end else if(checking_2) begin
        if(r_supply && r_cmp_milk) vol_milk <= 12'hfff;
        else vol_milk <= sum;
    end
end
// vol_pi
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        vol_pi <= 0;
    end else if(inf.C_out_valid)  begin
        vol_pi <= inf.C_data_r[19:8];
    end else if(checking_3) begin
        if(r_supply && r_cmp_pi) vol_pi <= 12'hfff;
        else vol_pi <= sum;
    end
end

// inf.out_valid
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.out_valid <= 0;
    end else if(checking_0_r) begin
        inf.out_valid <= 1;
    end else begin
        inf.out_valid <= 0;
    end
end

// inf.err_msg
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.err_msg <= No_Err;
    end else if(checking_0_r) begin
        if(check_date && is_expired) begin
            inf.err_msg <= No_Exp;
        end else if(make && (bgmp) ) begin
            inf.err_msg <= No_Ing;
        end else if(supply && (bgmp))begin
            inf.err_msg <= Ing_OF;
        end else begin
            inf.err_msg <= No_Err;
        end
    end
end
// inf.complete
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) begin
        inf.complete <= 0;
    end else if(checking_0_r) begin
        if(!(check_date && is_expired ||
        (make || supply) && (bgmp)))
            inf.complete <= 1;
        else inf.complete <= 0;
    end
end

// DRAM_writing
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) DRAM_writing <= 0;
    else if(checking_1) begin
        DRAM_writing <= 1;
    end else if(DRAM_writing && inf.C_out_valid) DRAM_writing <= 0;
end
// r_mux
always_ff@(posedge clk) begin
    r_mux_black <= mux_black;
    r_mux_green <= mux_green;
    r_mux_milk <= mux_milk ;
    r_mux_pi <= mux_pi;
end
// mux
always_comb begin
    mux_black = 0;
    mux_green = 0;
    mux_milk = 0;
    mux_pi = 0;
    case(r_type)
        Black_Tea: begin
            casez(r_size)
                2'bz0:mux_black = 960;
                2'b1z:mux_black = 480;
                default:mux_black = 720;
            endcase
        end
        Milk_Tea: begin
            casez(r_size)
                2'bz0:begin
                    mux_black = 720;
                    mux_milk = 240;
                end
                2'b1z:begin
                    mux_black = 360;
                    mux_milk = 120;
                end
                default:begin
                    mux_black = 540;
                    mux_milk = 180;
                end
            endcase
        end
        Extra_Milk_Tea: begin
            casez(r_size)
                2'bz0:begin
                    mux_black = 480;
                    mux_milk = 480;
                end
                2'b1z:begin
                    mux_black = 240;
                    mux_milk = 240;
                end
                default:begin
                    mux_black = 360;
                    mux_milk = 360;
                end
            endcase
        end
        Green_Tea: begin
            casez(r_size)
                2'bz0:mux_green = 960;
                2'b1z:mux_green = 480;
                default:mux_green = 720;
            endcase
        end
        Green_Milk_Tea: begin
            casez(r_size)
                2'bz0:begin
                    mux_green = 480;
                    mux_milk = 480;
                end
                2'b1z:begin
                    mux_green = 240;
                    mux_milk = 240;
                end
                default:begin
                    mux_green = 360;
                    mux_milk = 360;
                end
            endcase
        end
        Pineapple_Juice: begin
            casez(r_size)
                2'bz0:mux_pi = 960;
                2'b1z:mux_pi = 480;
                default:mux_pi = 720;
            endcase
        end
        Super_Pineapple_Tea: begin
            casez(r_size)
                2'bz0:begin
                    mux_black = 480;
                    mux_pi = 480;
                end
                2'b1z:begin
                    mux_black = 240;
                    mux_pi = 240;
                end
                default:begin
                    mux_black = 360;
                    mux_pi = 360;
                end
            endcase
        end
        Super_Pineapple_Milk_Tea: begin
            casez(r_size)
                2'bz0:begin
                    mux_black = 480;
                    mux_milk = 240;
                    mux_pi = 240;
                end
                2'b1z:begin
                    mux_black = 240;
                    mux_milk = 120;
                    mux_pi = 120;
                end
                default:begin
                    mux_black = 360;
                    mux_milk = 180;
                    mux_pi = 180;
                end
            endcase
        end
    endcase
end
endmodule