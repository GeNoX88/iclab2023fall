/*
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NYCU Institute of Electronic
2023 Autumn IC Design Laboratory 
Lab09: SystemVerilog Design and Verification 
File Name   : BEV.sv
Module Name : BEV
Release version : v1.0 (Release Date: Nov-2023)
Author : Jui-Huang Tsai (erictsai.10@nycu.edu.tw)
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
*/

module bridge(input clk, INF.bridge_inf inf);
import usertype::*;

//inf.B_READY
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.B_READY <= 0;
    else inf.B_READY <= 1;
end

// inf.AR_VALID
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.AR_VALID <= 0;
    else if(inf.C_in_valid && inf.C_r_wb) inf.AR_VALID <= 1;
    else if(inf.AR_READY) inf.AR_VALID <= 0;
end
// inf.AR_ADDR
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.AR_ADDR <= 0;
    else inf.AR_ADDR <= {6'b100000, inf.C_addr, 3'b000};
end
// inf.R_READY
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.R_READY <= 0;
    // else if(inf.AR_READY) inf.R_READY <= 1;
    // else if(inf.R_VALID) inf.R_READY <= 0;
    else inf.R_READY <= 1;
end
// inf.C_data_r
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.C_data_r <= 0;
    else inf.C_data_r <= inf.R_DATA;
end
// inf.C_out_valid
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.C_out_valid <= 0;
    else if(inf.R_VALID || inf.B_VALID) inf.C_out_valid <= 1;
    else inf.C_out_valid <= 0;
end
// inf.AW_VALID
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.AW_VALID <= 0;
    else if(inf.C_in_valid && inf.C_r_wb==0) inf.AW_VALID <= 1;
    else if(inf.AW_READY) inf.AW_VALID <= 0;
end
// inf.AW_ADDR
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.AW_ADDR <= 0;
    else inf.AW_ADDR <= {6'b100000, inf.C_addr, 3'b000};
end
// inf.W_VALID
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.W_VALID <= 0;
    else if(inf.AW_READY) inf.W_VALID <= 1;
    else if(inf.W_READY) inf.W_VALID <= 0;
end
// inf.W_DATA
always_ff@(posedge clk, negedge inf.rst_n) begin
    if(!inf.rst_n) inf.W_DATA <= 0;
    // else if(inf.C_in_valid) inf.W_DATA <= inf.C_data_w;
    else inf.W_DATA <= inf.C_data_w;
end


endmodule