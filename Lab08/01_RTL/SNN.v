//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2023 Fall
//   Lab04 Exercise		: Siamese Neural Network
//   Author     		: Hsien-Chi Peng (jhpeng2012@gmail.com)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : SNN.v
//   Module Name : SNN
//   Release version : V1.0 (Release Date: 2023-10)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

// synopsys translate_off
`ifdef RTL
`include "GATED_OR.v"
`else
`include "Netlist/GATED_OR_SYN.v"
`endif
// synopsys translate_on


module SNN (
  //Input Port
  clk,
  rst_n,
  in_valid,
  cg_en,
  Img,
  Kernel,
  Weight,
  Opt,
  //Output Port
  out_valid,
  out
);
  // IEEE floating point parameter
  parameter inst_sig_width = 23;
  parameter inst_exp_width = 8;
  parameter inst_ieee_compliance = 0;
  parameter inst_arch_type = 1;
  parameter inst_arch = 0;
  parameter inst_faithful_round = 0;
  parameter inst_rnd = 3'd0;

  input rst_n, clk, in_valid, cg_en;
  reg busy;
  reg [9:0] cnt;  // 0 ~ 1023
  reg [1:0] _Opt;
  input [inst_sig_width+inst_exp_width:0] Img;  // IEEE-754 ∓0.5~255.0
  input [inst_sig_width+inst_exp_width:0] Kernel, Weight;  // IEEE-754 ∓0~0.5
  reg [inst_exp_width+inst_sig_width:0] _Img_[0:2][1:4][1:4];
  reg [inst_exp_width+inst_sig_width:0] _Img[0:2][0:5][0:5];
  reg [inst_exp_width+inst_sig_width:0] _Kernel[0:2][0:2][0:2];
  reg [inst_exp_width+inst_sig_width:0] _Weight[0:1][0:1];
  input [1:0] Opt;  // 0~3
  //********* Opt *****************
  // Sigmoid = 1/(1+exp(-z)), tanh = (exp(z)-exp(-z))/(exp(z)+exp(-z))
  // 2’b00 : Sigmoid & {Replication}
  // 2’b01 : Sigmoid & {Zero}
  // 2’b10 : tanh & {Replication}
  // 2’b11 : tanh & {Zero}
  //*******************************
  output reg out_valid;
  output reg [inst_sig_width+inst_exp_width:0] out;
  wire [7:0] status_inst;
  integer i, j, k;
  reg [inst_sig_width+inst_exp_width:0] conv[0:2][0:3][0:3];
  reg [inst_sig_width+inst_exp_width:0] m[0:8][0:1];
  reg [inst_sig_width+inst_exp_width:0] prod[0:8];
  reg [inst_sig_width+inst_exp_width:0] ab[0:1][0:1];  // for distance
  wire [inst_sig_width+inst_exp_width:0] sum2[0:1];  // for distance
  reg [inst_sig_width+inst_exp_width:0] abc[0:8][0:2];
  reg [inst_sig_width+inst_exp_width:0]
    sum3[0:8], subconv[0:2], eq_nu, eq_nu_top, eq_nu_mid, eq_nu_btm;
  reg [inst_sig_width+inst_exp_width:0] convsum[0:3][0:3];  // 4x4
  reg [inst_sig_width+inst_exp_width:0] convsum_p[0:5][0:5];  // 6x6
  reg [inst_sig_width+inst_exp_width:0] eq[0:3][0:3];  // 4x4
  reg [inst_sig_width+inst_exp_width:0] mtxprod[0:3];
  wire [inst_sig_width+inst_exp_width:0] mtxprod_wire[0:3];
  wire [31:0] max01, min01, max23, min23, xmax, xmin;
  reg [31:0] _xmax, _xmin;
  reg [31:0] nua[0:1], nub[0:1], dea[0:1], deb[0:1], vec2[0:3], abs[0:1];
  reg [31:0] nu[0:2], de[0:2];
  wire [31:0] q[0:2];
  reg [31:0] z, vec1[0:3];
  wire [31:0] expz;
  wire [31:0] big[0:3][0:1];
  reg [31:0] pool[0:3][0:3];
  wire [31:0] max[0:1][0:1];
  wire [31:0] one = 32'b0_01111111_00000000000000000000000;
  reg [31:0] exppz, nm[0:3], _nu0, _de0, _nu1, _de1, _nu2;
  wire [31:0] nu_wire[0:1], de_wire[0:1];


  // busy
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) busy <= 0;
    else if (out_valid) busy <= 0;
    else if (in_valid | busy) busy <= 1;
  end
  // cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else if (out_valid) cnt <= 0;
    else if (in_valid | busy) cnt <= cnt + 1;
  end
  // _Opt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) _Opt <= 0;
    else if (in_valid && !busy) _Opt <= Opt;
  end
  // _Kernel[0:2][0:2][0:2]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n)
      for (i = 0; i < 3; i = i + 1)
      for (j = 0; j < 3; j = j + 1)
      for (k = 0; k < 3; k = k + 1) _Kernel[i][j][k] <= 0;
    else if (cnt < 27) begin
      _Kernel[cnt/9][(cnt%9)/3][cnt%3] <= Kernel;
    end
  end

  // //==============================================================
  // //        fine-grained _Img_[0:2][1:4][1:4] clock-gating
  // //================================================================
  // wire _Img_011_CG;
  // GATED_OR _IMG_011 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 0 || cnt == 48))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_011_CG)
  // );
  // always @(posedge _Img_011_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][1][1] <= 0;
  //   else if ((cnt == 0 || cnt == 48)) _Img_[0][1][1] <= Img;
  // end
  // wire _Img_012_CG;
  // GATED_OR _IMG_012 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 1 || cnt == 49))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_012_CG)
  // );
  // always @(posedge _Img_012_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][1][2] <= 0;
  //   else if ((cnt == 1 || cnt == 49)) _Img_[0][1][2] <= Img;
  // end
  // wire _Img_013_CG;
  // GATED_OR _IMG_013 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 2 || cnt == 50))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_013_CG)
  // );
  // always @(posedge _Img_013_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][1][3] <= 0;
  //   else if ((cnt == 2 || cnt == 50)) _Img_[0][1][3] <= Img;
  // end
  // wire _Img_014_CG;
  // GATED_OR _IMG_014 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 3 || cnt == 51))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_014_CG)
  // );
  // always @(posedge _Img_014_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][1][4] <= 0;
  //   else if ((cnt == 3 || cnt == 51)) _Img_[0][1][4] <= Img;
  // end
  // wire _Img_021_CG;
  // GATED_OR _IMG_021 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 4 || cnt == 52))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_021_CG)
  // );
  // always @(posedge _Img_021_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][2][1] <= 0;
  //   else if ((cnt == 4 || cnt == 52)) _Img_[0][2][1] <= Img;
  // end
  // wire _Img_022_CG;
  // GATED_OR _IMG_022 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 5 || cnt == 53))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_022_CG)
  // );
  // always @(posedge _Img_022_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][2][2] <= 0;
  //   else if ((cnt == 5 || cnt == 53)) _Img_[0][2][2] <= Img;
  // end
  // wire _Img_023_CG;
  // GATED_OR _IMG_023 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 6 || cnt == 54))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_023_CG)
  // );
  // always @(posedge _Img_023_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][2][3] <= 0;
  //   else if ((cnt == 6 || cnt == 54)) _Img_[0][2][3] <= Img;
  // end
  // wire _Img_024_CG;
  // GATED_OR _IMG_024 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 7 || cnt == 55))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_024_CG)
  // );
  // always @(posedge _Img_024_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][2][4] <= 0;
  //   else if ((cnt == 7 || cnt == 55)) _Img_[0][2][4] <= Img;
  // end
  // wire _Img_031_CG;
  // GATED_OR _IMG_031 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 8 || cnt == 56))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_031_CG)
  // );
  // always @(posedge _Img_031_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][3][1] <= 0;
  //   else if ((cnt == 8 || cnt == 56)) _Img_[0][3][1] <= Img;
  // end
  // wire _Img_032_CG;
  // GATED_OR _IMG_032 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 9 || cnt == 57))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_032_CG)
  // );
  // always @(posedge _Img_032_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][3][2] <= 0;
  //   else if ((cnt == 9 || cnt == 57)) _Img_[0][3][2] <= Img;
  // end
  // wire _Img_033_CG;
  // GATED_OR _IMG_033 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 10 || cnt == 58))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_033_CG)
  // );
  // always @(posedge _Img_033_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][3][3] <= 0;
  //   else if ((cnt == 10 || cnt == 58)) _Img_[0][3][3] <= Img;
  // end
  // wire _Img_034_CG;
  // GATED_OR _IMG_034 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 11 || cnt == 59))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_034_CG)
  // );
  // always @(posedge _Img_034_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][3][4] <= 0;
  //   else if ((cnt == 11 || cnt == 59)) _Img_[0][3][4] <= Img;
  // end
  // wire _Img_041_CG;
  // GATED_OR _IMG_041 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 12 || cnt == 60))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_041_CG)
  // );
  // always @(posedge _Img_041_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][4][1] <= 0;
  //   else if ((cnt == 12 || cnt == 60)) _Img_[0][4][1] <= Img;
  // end
  // wire _Img_042_CG;
  // GATED_OR _IMG_042 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 13 || cnt == 61))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_042_CG)
  // );
  // always @(posedge _Img_042_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][4][2] <= 0;
  //   else if ((cnt == 13 || cnt == 61)) _Img_[0][4][2] <= Img;
  // end
  // wire _Img_043_CG;
  // GATED_OR _IMG_043 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 14 || cnt == 62))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_043_CG)
  // );
  // always @(posedge _Img_043_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][4][3] <= 0;
  //   else if ((cnt == 14 || cnt == 62)) _Img_[0][4][3] <= Img;
  // end
  // wire _Img_044_CG;
  // GATED_OR _IMG_044 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 15 || cnt == 63))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_044_CG)
  // );
  // always @(posedge _Img_044_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[0][4][4] <= 0;
  //   else if ((cnt == 15 || cnt == 63)) _Img_[0][4][4] <= Img;
  // end
  // wire _Img_111_CG;
  // GATED_OR _IMG_111 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 16 || cnt == 64))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_111_CG)
  // );
  // always @(posedge _Img_111_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][1][1] <= 0;
  //   else if ((cnt == 16 || cnt == 64)) _Img_[1][1][1] <= Img;
  // end
  // wire _Img_112_CG;
  // GATED_OR _IMG_112 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 17 || cnt == 65))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_112_CG)
  // );
  // always @(posedge _Img_112_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][1][2] <= 0;
  //   else if ((cnt == 17 || cnt == 65)) _Img_[1][1][2] <= Img;
  // end
  // wire _Img_113_CG;
  // GATED_OR _IMG_113 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 18 || cnt == 66))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_113_CG)
  // );
  // always @(posedge _Img_113_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][1][3] <= 0;
  //   else if ((cnt == 18 || cnt == 66)) _Img_[1][1][3] <= Img;
  // end
  // wire _Img_114_CG;
  // GATED_OR _IMG_114 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 19 || cnt == 67))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_114_CG)
  // );
  // always @(posedge _Img_114_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][1][4] <= 0;
  //   else if ((cnt == 19 || cnt == 67)) _Img_[1][1][4] <= Img;
  // end
  // wire _Img_121_CG;
  // GATED_OR _IMG_121 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 20 || cnt == 68))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_121_CG)
  // );
  // always @(posedge _Img_121_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][2][1] <= 0;
  //   else if ((cnt == 20 || cnt == 68)) _Img_[1][2][1] <= Img;
  // end
  // wire _Img_122_CG;
  // GATED_OR _IMG_122 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 21 || cnt == 69))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_122_CG)
  // );
  // always @(posedge _Img_122_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][2][2] <= 0;
  //   else if ((cnt == 21 || cnt == 69)) _Img_[1][2][2] <= Img;
  // end
  // wire _Img_123_CG;
  // GATED_OR _IMG_123 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 22 || cnt == 70))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_123_CG)
  // );
  // always @(posedge _Img_123_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][2][3] <= 0;
  //   else if ((cnt == 22 || cnt == 70)) _Img_[1][2][3] <= Img;
  // end
  // wire _Img_124_CG;
  // GATED_OR _IMG_124 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 23 || cnt == 71))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_124_CG)
  // );
  // always @(posedge _Img_124_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][2][4] <= 0;
  //   else if ((cnt == 23 || cnt == 71)) _Img_[1][2][4] <= Img;
  // end
  // wire _Img_131_CG;
  // GATED_OR _IMG_131 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 24 || cnt == 72))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_131_CG)
  // );
  // always @(posedge _Img_131_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][3][1] <= 0;
  //   else if ((cnt == 24 || cnt == 72)) _Img_[1][3][1] <= Img;
  // end
  // wire _Img_132_CG;
  // GATED_OR _IMG_132 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 25 || cnt == 73))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_132_CG)
  // );
  // always @(posedge _Img_132_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][3][2] <= 0;
  //   else if ((cnt == 25 || cnt == 73)) _Img_[1][3][2] <= Img;
  // end
  // wire _Img_133_CG;
  // GATED_OR _IMG_133 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 26 || cnt == 74))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_133_CG)
  // );
  // always @(posedge _Img_133_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][3][3] <= 0;
  //   else if ((cnt == 26 || cnt == 74)) _Img_[1][3][3] <= Img;
  // end
  // wire _Img_134_CG;
  // GATED_OR _IMG_134 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 27 || cnt == 75))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_134_CG)
  // );
  // always @(posedge _Img_134_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][3][4] <= 0;
  //   else if ((cnt == 27 || cnt == 75)) _Img_[1][3][4] <= Img;
  // end
  // wire _Img_141_CG;
  // GATED_OR _IMG_141 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 28 || cnt == 76))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_141_CG)
  // );
  // always @(posedge _Img_141_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][4][1] <= 0;
  //   else if ((cnt == 28 || cnt == 76)) _Img_[1][4][1] <= Img;
  // end
  // wire _Img_142_CG;
  // GATED_OR _IMG_142 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 29 || cnt == 77))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_142_CG)
  // );
  // always @(posedge _Img_142_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][4][2] <= 0;
  //   else if ((cnt == 29 || cnt == 77)) _Img_[1][4][2] <= Img;
  // end
  // wire _Img_143_CG;
  // GATED_OR _IMG_143 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 30 || cnt == 78))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_143_CG)
  // );
  // always @(posedge _Img_143_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][4][3] <= 0;
  //   else if ((cnt == 30 || cnt == 78)) _Img_[1][4][3] <= Img;
  // end
  // wire _Img_144_CG;
  // GATED_OR _IMG_144 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 31 || cnt == 79))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_144_CG)
  // );
  // always @(posedge _Img_144_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[1][4][4] <= 0;
  //   else if ((cnt == 31 || cnt == 79)) _Img_[1][4][4] <= Img;
  // end
  // wire _Img_211_CG;
  // GATED_OR _IMG_211 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 32 || cnt == 80))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_211_CG)
  // );
  // always @(posedge _Img_211_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][1][1] <= 0;
  //   else if ((cnt == 32 || cnt == 80)) _Img_[2][1][1] <= Img;
  // end
  // wire _Img_212_CG;
  // GATED_OR _IMG_212 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 33 || cnt == 81))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_212_CG)
  // );
  // always @(posedge _Img_212_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][1][2] <= 0;
  //   else if ((cnt == 33 || cnt == 81)) _Img_[2][1][2] <= Img;
  // end
  // wire _Img_213_CG;
  // GATED_OR _IMG_213 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 34 || cnt == 82))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_213_CG)
  // );
  // always @(posedge _Img_213_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][1][3] <= 0;
  //   else if ((cnt == 34 || cnt == 82)) _Img_[2][1][3] <= Img;
  // end
  // wire _Img_214_CG;
  // GATED_OR _IMG_214 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 35 || cnt == 83))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_214_CG)
  // );
  // always @(posedge _Img_214_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][1][4] <= 0;
  //   else if ((cnt == 35 || cnt == 83)) _Img_[2][1][4] <= Img;
  // end
  // wire _Img_221_CG;
  // GATED_OR _IMG_221 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 36 || cnt == 84))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_221_CG)
  // );
  // always @(posedge _Img_221_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][2][1] <= 0;
  //   else if ((cnt == 36 || cnt == 84)) _Img_[2][2][1] <= Img;
  // end
  // wire _Img_222_CG;
  // GATED_OR _IMG_222 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 37 || cnt == 85))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_222_CG)
  // );
  // always @(posedge _Img_222_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][2][2] <= 0;
  //   else if ((cnt == 37 || cnt == 85)) _Img_[2][2][2] <= Img;
  // end
  // wire _Img_223_CG;
  // GATED_OR _IMG_223 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 38 || cnt == 86))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_223_CG)
  // );
  // always @(posedge _Img_223_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][2][3] <= 0;
  //   else if ((cnt == 38 || cnt == 86)) _Img_[2][2][3] <= Img;
  // end
  // wire _Img_224_CG;
  // GATED_OR _IMG_224 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 39 || cnt == 87))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_224_CG)
  // );
  // always @(posedge _Img_224_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][2][4] <= 0;
  //   else if ((cnt == 39 || cnt == 87)) _Img_[2][2][4] <= Img;
  // end
  // wire _Img_231_CG;
  // GATED_OR _IMG_231 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 40 || cnt == 88))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_231_CG)
  // );
  // always @(posedge _Img_231_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][3][1] <= 0;
  //   else if ((cnt == 40 || cnt == 88)) _Img_[2][3][1] <= Img;
  // end
  // wire _Img_232_CG;
  // GATED_OR _IMG_232 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 41 || cnt == 89))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_232_CG)
  // );
  // always @(posedge _Img_232_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][3][2] <= 0;
  //   else if ((cnt == 41 || cnt == 89)) _Img_[2][3][2] <= Img;
  // end
  // wire _Img_233_CG;
  // GATED_OR _IMG_233 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 42 || cnt == 90))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_233_CG)
  // );
  // always @(posedge _Img_233_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][3][3] <= 0;
  //   else if ((cnt == 42 || cnt == 90)) _Img_[2][3][3] <= Img;
  // end
  // wire _Img_234_CG;
  // GATED_OR _IMG_234 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 43 || cnt == 91))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_234_CG)
  // );
  // always @(posedge _Img_234_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][3][4] <= 0;
  //   else if ((cnt == 43 || cnt == 91)) _Img_[2][3][4] <= Img;
  // end
  // wire _Img_241_CG;
  // GATED_OR _IMG_241 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 44 || cnt == 92))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_241_CG)
  // );
  // always @(posedge _Img_241_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][4][1] <= 0;
  //   else if ((cnt == 44 || cnt == 92)) _Img_[2][4][1] <= Img;
  // end
  // wire _Img_242_CG;
  // GATED_OR _IMG_242 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 45 || cnt == 93))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_242_CG)
  // );
  // always @(posedge _Img_242_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][4][2] <= 0;
  //   else if ((cnt == 45 || cnt == 93)) _Img_[2][4][2] <= Img;
  // end
  // wire _Img_243_CG;
  // GATED_OR _IMG_243 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 46 || cnt == 94))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_243_CG)
  // );
  // always @(posedge _Img_243_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][4][3] <= 0;
  //   else if ((cnt == 46 || cnt == 94)) _Img_[2][4][3] <= Img;
  // end
  // wire _Img_244_CG;
  // GATED_OR _IMG_244 (
  //   .CLOCK(clk),
  //   .SLEEP_CTRL(cg_en && !((cnt == 47 || cnt == 95))),
  //   .RST_N(rst_n),
  //   .CLOCK_GATED(_Img_244_CG)
  // );
  // always @(posedge _Img_244_CG, negedge rst_n) begin
  //   if (!rst_n) _Img_[2][4][4] <= 0;
  //   else if ((cnt == 47 || cnt == 95)) _Img_[2][4][4] <= Img;
  // end

  // =====================================================
  //              original _Img_[0:2][1:4][1:4]
  //=================================================================
  reg _Img__sleep;
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) _Img__sleep <= 0;
    else if (cnt[9:7]) _Img__sleep <= 1;
    else _Img__sleep <= 0;
  end
  // wire _Img__sleep = !(cnt < 96);  // care input delay
  wire _Img__CG;
  GATED_OR _IMG_ (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && _Img__sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(_Img__CG)
  );
  always @(posedge clk, negedge rst_n) begin  // _Img_CG might be unknown in GLS
    if (!rst_n)
      for (i = 0; i < 3; i = i + 1)
      for (j = 1; j < 5; j = j + 1)
      for (k = 1; k < 5; k = k + 1) _Img_[i][j][k] <= 0;
    else if (in_valid && cnt[9:7] == 0) begin
      _Img_[(cnt>>4)%3][1+cnt[3:2]][1+cnt[1:0]] <= Img;
    end
  end

  // _Img[0:2][0:5][0:5]
  always @(*) begin
    for (i = 0; i < 3; i = i + 1) begin
      for (j = 1; j <= 4; j = j + 1) begin
        for (k = 1; k <= 4; k = k + 1) begin
          _Img[i][j][k] = _Img_[i][j][k];
        end
        _Img[i][0][j] = _Opt[0] ? 0 : _Img_[i][1][j];
        _Img[i][j][0] = _Opt[0] ? 0 : _Img_[i][j][1];
        _Img[i][5][j] = _Opt[0] ? 0 : _Img_[i][4][j];
        _Img[i][j][5] = _Opt[0] ? 0 : _Img_[i][j][4];
      end
      _Img[i][0][0] = _Opt[0] ? 0 : _Img_[i][1][1];
      _Img[i][0][5] = _Opt[0] ? 0 : _Img_[i][1][4];
      _Img[i][5][0] = _Opt[0] ? 0 : _Img_[i][4][1];
      _Img[i][5][5] = _Opt[0] ? 0 : _Img_[i][4][4];
    end
  end

  // _Weight[0:1][0:1]
  wire _Weight_CG;
  wire _Weight_sleep = !(cnt[9:2] == 0);
  GATED_OR _WEIGHT (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && _Weight_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(_Weight_CG)
  );
  always @(posedge _Weight_CG, negedge rst_n) begin
    if (!rst_n)
      for (i = 0; i < 2; i = i + 1)
      for (j = 0; j < 2; j = j + 1) _Weight[i][j] <= 0;
    else if (cnt[9:2] == 0) _Weight[cnt[1]][cnt[0]] <= Weight;
  end




  wire [6:0] cnt_43 = cnt - 43;
  wire [6:0] cnt_91 = cnt - 91;

  always @(*) begin
    abc[0][0] = cnt[9:7] == 0 ? prod[0] : 0;
    abc[0][1] = cnt[9:7] == 0 ? prod[1] : 0;
    abc[0][2] = cnt[9:7] == 0 ? prod[2] : 0;
    abc[1][0] = cnt[9:7] == 0 ? prod[3] : 0;
    abc[1][1] = cnt[9:7] == 0 ? prod[4] : 0;
    abc[1][2] = cnt[9:7] == 0 ? prod[5] : 0;
    abc[2][0] = cnt[9:7] == 0 ? prod[6] : 0;
    abc[2][1] = cnt[9:7] == 0 ? prod[7] : 0;
    abc[2][2] = cnt[9:7] == 0 ? prod[8] : 0;

    abc[3][0] = subconv[0];
    abc[3][1] = subconv[1];
    abc[3][2] = subconv[2];

    abc[4][0] = cnt<91? conv[0][cnt_43[6:2]][cnt_43[1:0]]:cnt<=106? conv[0][cnt_91[6:2]][cnt_91[1:0]]:0;
    abc[4][1] = cnt<91? conv[1][cnt_43[6:2]][cnt_43[1:0]]:cnt<=106? conv[1][cnt_91[6:2]][cnt_91[1:0]]:0;
    abc[4][2] = cnt<91? conv[2][cnt_43[6:2]][cnt_43[1:0]]:cnt<=106? conv[2][cnt_91[6:2]][cnt_91[1:0]]:0;
  end

  // subconv[0:2]
  wire subconv_CG;
  wire subconv_sleep = !(9 <= cnt && cnt <= 104);
  GATED_OR SUBCONV (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && subconv_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(subconv_CG)
  );
  always @(posedge subconv_CG, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 3; i = i + 1) subconv[i] <= 0;
    else if (9 <= cnt && cnt <= 104)
      for (i = 0; i < 3; i = i + 1) subconv[i] <= sum3[i];
  end

  wire [6:0] subconvcnt = cnt - 9;
  wire [6:0] convcnt = cnt - 10;
  //===============================================================
  //                 original conv[0:2][0:3][0:3] 
  //===============================================================
  reg conv_sleep;
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) conv_sleep <= 0;
    else if (cnt[9:7]) conv_sleep <= 1;
    else conv_sleep <= 0;
  end
  wire conv_CG;
  // wire conv_sleep = !(cnt[9:7] == 0);
  GATED_OR CONV (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && conv_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(conv_CG)
  );
  always @(posedge clk, negedge rst_n) begin  // conv might be unknown in GLS
    if (!rst_n)
      for (i = 0; i < 3; i = i + 1)
      for (j = 0; j < 4; j = j + 1)
      for (k = 0; k < 4; k = k + 1) conv[i][j][k] <= 0;
    else if (cnt[9:7] == 0) begin
      conv[convcnt[6:4]%3][convcnt[3:2]][convcnt[1:0]] <= sum3[3];
    end
  end
  // m[0:8][0:1]
  always @(*) begin
    m[0][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]]:0;
    m[0][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][0][0] : 0;

    m[1][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]+1]:0;
    m[1][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][0][1] : 0;

    m[2][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]+2]:0;
    m[2][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][0][2] : 0;

    m[3][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]]:0;
    m[3][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][1][0] : 0;

    m[4][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]+1]:0;
    m[4][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][1][1] : 0;

    m[5][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]+2]:0;
    m[5][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][1][2] : 0;

    m[6][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]]:0;
    m[6][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][2][0] : 0;

    m[7][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]+1]:0;
    m[7][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][2][1] : 0;

    m[8][0] = (!cg_en || cnt[9:7]==0)? _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]+2]:0;
    m[8][1] = (!cg_en || cnt[9:7] == 0) ? _Kernel[subconvcnt[6:4]%3][2][2] : 0;
  end

  // convsum[0:3][0:3]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n)
      for (i = 0; i < 4; i = i + 1)
      for (j = 0; j < 4; j = j + 1) convsum[i][j] <= 0;
    else if (0 <= cnt_43 && cnt_43 <= 15) begin
      convsum[cnt_43[6:2]][cnt_43[1:0]] <= sum3[4];
    end else if (0 <= cnt_91 && cnt_91 <= 15) begin
      convsum[cnt_91[6:2]][cnt_91[1:0]] <= sum3[4];
    end
  end
  // convsum_p[0:5][0:5]
  always @(*) begin
    for (i = 1; i < 5; i = i + 1)
    for (j = 1; j < 5; j = j + 1) convsum_p[i][j] = convsum[i-1][j-1];
    convsum_p[0][0] = _Opt[0] ? 0 : convsum[0][0];  // upper-left
    convsum_p[0][5] = _Opt[0] ? 0 : convsum[0][3];  // upper-right
    convsum_p[5][0] = _Opt[0] ? 0 : convsum[3][0];  // bottom-left
    convsum_p[5][5] = _Opt[0] ? 0 : convsum[3][3];  // bottom-right
    for (i = 1; i < 5; i = i + 1)
    convsum_p[0][i] = _Opt[0] ? 0 : convsum[0][i-1];  // top
    for (i = 1; i < 5; i = i + 1)
    convsum_p[5][i] = _Opt[0] ? 0 : convsum[3][i-1];  // down
    for (i = 1; i < 5; i = i + 1)
    convsum_p[i][0] = _Opt[0] ? 0 : convsum[i-1][0];  // left
    for (i = 1; i < 5; i = i + 1)
    convsum_p[i][5] = _Opt[0] ? 0 : convsum[i-1][3];  // right
  end

  wire [6:0] cnt_49 = cnt - 49;
  wire [6:0] cnt_97 = cnt - 97;

  always @(*) begin
    abc[5][0] = cnt<=64? convsum_p[cnt_49[6:2]+0][cnt_49[1:0]+0]:cnt<=112? convsum_p[cnt_97[6:2]+0][cnt_97[1:0]+0]:0;
    abc[5][1] = cnt<=64? convsum_p[cnt_49[6:2]+0][cnt_49[1:0]+1]:cnt<=112? convsum_p[cnt_97[6:2]+0][cnt_97[1:0]+1]:0;
    abc[5][2] = cnt<=64? convsum_p[cnt_49[6:2]+0][cnt_49[1:0]+2]:cnt<=112? convsum_p[cnt_97[6:2]+0][cnt_97[1:0]+2]:0;
    abc[6][0] = cnt<=64? convsum_p[cnt_49[6:2]+1][cnt_49[1:0]+0]:cnt<=112? convsum_p[cnt_97[6:2]+1][cnt_97[1:0]+0]:0;
    abc[6][1] = cnt<=64? convsum_p[cnt_49[6:2]+1][cnt_49[1:0]+1]:cnt<=112? convsum_p[cnt_97[6:2]+1][cnt_97[1:0]+1]:0;
    abc[6][2] = cnt<=64? convsum_p[cnt_49[6:2]+1][cnt_49[1:0]+2]:cnt<=112? convsum_p[cnt_97[6:2]+1][cnt_97[1:0]+2]:0;
    abc[7][0] = cnt<=64? convsum_p[cnt_49[6:2]+2][cnt_49[1:0]+0]:cnt<=112? convsum_p[cnt_97[6:2]+2][cnt_97[1:0]+0]:0;
    abc[7][1] = cnt<=64? convsum_p[cnt_49[6:2]+2][cnt_49[1:0]+1]:cnt<=112? convsum_p[cnt_97[6:2]+2][cnt_97[1:0]+1]:0;
    abc[7][2] = cnt<=64? convsum_p[cnt_49[6:2]+2][cnt_49[1:0]+2]:cnt<=112? convsum_p[cnt_97[6:2]+2][cnt_97[1:0]+2]:0;

    abc[8][0] = eq_nu_top;
    abc[8][1] = eq_nu_mid;
    abc[8][2] = eq_nu_btm;
  end

  // eq_nu_part
  wire eq_nu_part_CG;
  wire eq_nu_part_sleep = !(49 <= cnt && cnt <= 64 || 97 <= cnt && cnt <= 112);
  GATED_OR EQ_NU_PART (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && eq_nu_part_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(eq_nu_part_CG)
  );
  always @(posedge eq_nu_part_CG, negedge rst_n) begin
    if (!rst_n) begin
      eq_nu_top <= 0;
      eq_nu_mid <= 0;
      eq_nu_btm <= 0;
    end else if (49 <= cnt && cnt <= 64 || 97 <= cnt && cnt <= 112) begin
      eq_nu_top <= sum3[5];
      eq_nu_mid <= sum3[6];
      eq_nu_btm <= sum3[7];
    end
  end

  // eq_nu
  wire eq_nu_CG;
  wire eq_nu_sleep = !(50 <= cnt && cnt <= 65 || 98 <= cnt && cnt <= 113);
  GATED_OR EQ_NU (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && eq_nu_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(eq_nu_CG)
  );
  always @(posedge eq_nu_CG, negedge rst_n) begin
    if (!rst_n) eq_nu <= 0;
    else if (50 <= cnt && cnt <= 65 || 98 <= cnt && cnt <= 113)
      eq_nu <= sum3[8];
  end
  wire [6:0] cnt_51 = cnt_49 - 2;
  wire [6:0] cnt_99 = cnt_97 - 2;

  // eq
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 4; i = i + 1) for (j = 0; j < 4; j = j + 1) eq[i][j] <= 0;
    end else if (51 <= cnt && cnt <= 66) begin
      eq[cnt_51[6:2]][cnt_51[1:0]] <= q[2];
    end else if (99 <= cnt && cnt <= 114) begin
      eq[cnt_99[6:2]][cnt_99[1:0]] <= q[2];
    end
  end
  // pool[0:3][0:3]
  always @(*) begin  // get mtxprod_wire instantly
    pool[0][0] = eq[0][0];
    pool[0][1] = eq[0][1];
    pool[1][0] = eq[1][0];
    pool[1][1] = eq[1][1];

    pool[0][2] = eq[0][2];
    pool[0][3] = eq[0][3];
    pool[1][2] = eq[1][2];
    pool[1][3] = eq[1][3];

    pool[2][0] = eq[2][0];
    pool[2][1] = eq[2][1];
    pool[3][0] = eq[3][0];
    pool[3][1] = eq[3][1];

    pool[2][2] = eq[2][2];
    pool[2][3] = eq[2][3];
    pool[3][2] = eq[3][2];
    pool[3][3] = eq[3][3];
  end

  // mtxprod[0:3]
  wire mtxprod_CG;
  reg mtxprod_sleep;
  always @(*) begin
    case (cnt)
      67, 115: mtxprod_sleep = 0;
      default: mtxprod_sleep = 1;
    endcase
  end
  GATED_OR MTXPROD (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && mtxprod_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(mtxprod_CG)
  );
  always @(posedge mtxprod_CG, negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 4; i = i + 1) mtxprod[i] <= 0;
    end else
      case (cnt)
        67, 115: begin
          mtxprod[0] <= mtxprod_wire[0];
          mtxprod[1] <= mtxprod_wire[1];
          mtxprod[2] <= mtxprod_wire[2];
          mtxprod[3] <= mtxprod_wire[3];
        end
      endcase
  end

  // _xmax, _xmin
  wire _x_CG;
  reg _x_sleep;
  always @(*) begin
    case (cnt)
      68, 116: _x_sleep = 0;
      default: _x_sleep = 1;
    endcase
  end
  GATED_OR _X (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && _x_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(_x_CG)
  );
  always @(posedge _x_CG, negedge rst_n) begin
    if (!rst_n) begin
      _xmax <= 0;
      _xmin <= 0;
    end else
      case (cnt)
        68, 116: begin
          _xmax <= xmax;  // from IP(mtxprod) 
          _xmin <= xmin;  // from IP(mtxprod)
        end
      endcase
  end

  // _nu0, _de0
  wire _q0_CG;
  reg _q0_sleep;
  always @(*) begin
    case (cnt)
      69, 70, 71, 72, 117, 118, 119, 120: _q0_sleep = 0;
      default: _q0_sleep = 1;
    endcase
  end
  GATED_OR _Q0 (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && _q0_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(_q0_CG)
  );
  always @(posedge _q0_CG, negedge rst_n) begin
    if (!rst_n) begin
      _nu0 <= 0;
      _de0 <= 0;
    end else
      case (cnt)
        69, 70, 71, 72, 117, 118, 119, 120: begin
          _nu0 <= nu_wire[0];  // nua[0]-nub[0]
          _de0 <= de_wire[0];  // dea[0]-deb[0]
        end
      endcase
  end

  // nu1_wire, de1_wire
  wire _q1_CG;
  reg _q1_sleep;
  always @(*) begin
    case (cnt)
      72, 73, 74, 75, 120, 121, 122, 123: _q1_sleep = 0;
      default: _q1_sleep = 1;
    endcase
  end
  GATED_OR _Q1 (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && _q1_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(_q1_CG)
  );
  reg [31:0] nu1_a, nu1_b, nu1_c;
  reg [31:0] de1_a, de1_b, de1_c;
  always @(*) begin
    nu1_a = _nu1 ^ (_nu1 << 13);
    nu1_b = nu1_a ^ (nu1_a >> 17);
    nu1_c = nu1_b ^ (nu1_b << 5);

    de1_a = _de1 ^ (_de1 << 13);
    de1_b = de1_a ^ (de1_a >> 17);
    de1_c = de1_b ^ (de1_b << 5);
  end
  always @(posedge _q1_CG, negedge rst_n) begin
    if (!rst_n) begin
      _nu1 <= 28825252;
      _de1 <= 123456789;
    end else
      case (cnt)
        72, 73, 74, 75, 120, 121, 122, 123: begin
          _nu1 <= nu_wire[1];
          _de1 <= de_wire[1];
        end
        // default: begin
        //   _nu1 <= nu1_c;
        //   _de1 <= de1_c;
        // end
      endcase
  end

  // nu[0], de[0]
  always @(*) begin
    nu[0] = _nu0;
    de[0] = _de0;
    nu[1] = _nu1;
    de[1] = _de1;
    nu[2] = eq_nu;
  end
  wire cnteq125 = cnt == 125;
  // nua[0], nub[0], dea[0], deb[0]
  always @(*) begin
    case (cnt)
      69, 117: nua[0] = mtxprod[0];
      70, 118: nua[0] = mtxprod[1];
      71, 119: nua[0] = mtxprod[2];
      72, 120: nua[0] = mtxprod[3];
      default: nua[0] = abs[0];  // |220-221|+|0-149|
    endcase
    nub[0] = cnteq125 ? sum2[1] : {~_xmin[31], _xmin[30:0]};
    dea[0] = _xmax;
    deb[0] = {~_xmin[31], _xmin[30:0]};
  end
  always @(*) begin
    nua[1] = _Opt[1] ? exppz : one;
    nub[1] = _Opt[1] ? {~one[31], one[30:0]} : 0;
    dea[1] = exppz;
    deb[1] = one;
  end

  //nm[0:3]
  wire nm_CG;
  reg nm_sleep;
  always @(*) begin
    case (cnt)
      70, 71, 72, 73, 118, 119, 120, 121: nm_sleep = 0;
      default: nm_sleep = 1;
    endcase
  end
  GATED_OR NM (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && nm_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(nm_CG)
  );
  reg [31:0] nm_a, nm_b, nm_c;
  always @(*) begin
    nm_a = nm[0] ^ (nm[0] << 13);
    nm_b = nm_a ^ (nm_a >> 17);
    nm_c = nm_b ^ (nm_b << 5);
  end
  always @(posedge nm_CG, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 4; i = i + 1) nm[i] <= 28825252;
    else
      case (cnt)
        70, 71, 72, 73: nm[cnt-70] <= q[0];
        118, 119, 120, 121: nm[cnt-118] <= q[0];
        // default: nm[0] <= nm_c;
      endcase
  end
  reg [7:0] twoz_expbit[0:3];
  always @(*) begin
    for (i = 0; i < 4; i = i + 1) twoz_expbit[i] = nm[i][30:23] + 1;
  end
  // z[0:3]
  always @(*) begin
    case (cnt)
      71, 119:
      z = _Opt[1]==0? nm[0]: (nm[0]==0)? 0:{nm[0][31], twoz_expbit[0], nm[0][22:0]};
      72, 120:
      z = _Opt[1]==0? nm[1]: (nm[1]==0)? 0:{nm[1][31], twoz_expbit[1], nm[1][22:0]};
      73, 121:
      z = _Opt[1]==0? nm[2]: (nm[2]==0)? 0:{nm[2][31], twoz_expbit[2], nm[2][22:0]};
      74, 122:
      z = _Opt[1]==0? nm[3]: (nm[3]==0)? 0:{nm[3][31], twoz_expbit[3], nm[3][22:0]};
      default: z = nm[0];
    endcase
  end

  // exppz
  wire exppz_CG;
  reg exppz_sleep;
  always @(*) begin
    case (cnt)
      71, 72, 73, 74, 119, 120, 121, 122: exppz_sleep = 0;
      default: exppz_sleep = 1;
    endcase
  end
  GATED_OR EXPPZ (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && exppz_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(exppz_CG)
  );
  reg [31:0] expz_a, expz_b, expz_c;
  always @(*) begin
    expz_a = exppz ^ (exppz << 13);
    expz_b = expz_a ^ (expz_a >> 17);
    expz_c = expz_b ^ (expz_b << 5);
  end
  always @(posedge exppz_CG, negedge rst_n) begin
    if (!rst_n) exppz <= 28825252;
    else
      case (cnt)
        71, 72, 73, 74, 119, 120, 121, 122: begin
          exppz <= expz;
        end
        // default: exppz <= expz_c;
      endcase
  end
  // vec1[0:3];
  wire vec1_CG;
  reg vec1_sleep;
  always @(*) begin
    case (cnt)
      73, 74, 75, 76: vec1_sleep = 0;
      default: vec1_sleep = 1;
    endcase
  end
  GATED_OR VEC1 (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && vec1_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(vec1_CG)
  );
  always @(posedge vec1_CG, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 4; i = i + 1) vec1[i] <= 0;
    else
      case (cnt)
        73: vec1[0] <= q[1];
        74: vec1[1] <= q[1];
        75: vec1[2] <= q[1];
        76: vec1[3] <= q[1];
      endcase
  end

  // vec2[0:3]
  wire vec2_CG;
  reg vec2_sleep;
  always @(*) begin
    case (cnt)
      121, 122, 123, 124: vec2_sleep = 0;
      default: vec2_sleep = 1;
    endcase
  end
  GATED_OR VEC2 (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && vec2_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(vec2_CG)
  );
  always @(posedge vec2_CG, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 4; i = i + 1) vec2[i] <= 0;
    else
      case (cnt)
        121: vec2[0] <= q[1];
        122: vec2[1] <= q[1];
        123: vec2[2] <= q[1];
        124: vec2[3] <= q[1];
      endcase
  end

  // abs[0:1]
  wire abs_CG;
  reg abs_sleep;
  always @(*) begin
    case (cnt)
      122, 123, 124: abs_sleep = 0;
      default: abs_sleep = 1;
    endcase
  end
  GATED_OR ABS (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && abs_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(abs_CG)
  );
  always @(posedge abs_CG, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 2; i = i + 1) abs[i] <= 0;
    else
      case (cnt)
        122: begin
          abs[0] <= {1'b0, sum2[0][30:0]};  // |220-221|
        end
        123: begin
          abs[0] <= sum2[1];  // |220-221|+|0-149|
        end
        124: begin
          abs[1] <= {1'b0, sum2[0][30:0]};  // |128-0|
        end
      endcase
  end
  // ab[0][0:1] for distance
  always @(*) begin
    case (cnt)
      122: begin
        ab[0][0] = vec1[0];  // 220
        ab[0][1] = {~vec2[0][31], vec2[0][30:0]};  // -221
      end
      123: begin
        ab[0][0] = vec1[1];  // 0
        ab[0][1] = {~vec2[1][31], vec2[1][30:0]};  // -149
      end
      124: begin
        ab[0][0] = vec1[2];  // 128
        ab[0][1] = {~vec2[2][31], vec2[2][30:0]};  // -0
      end
      125: begin
        ab[0][0] = vec1[3];  // 0
        ab[0][1] = {~vec2[3][31], vec2[3][30:0]};  // -0
      end
      default: begin
        ab[0][0] = 0;
        ab[0][1] = 0;
      end
    endcase
  end
  // ab[1][0:1] for distance
  always @(*) begin
    case (cnt)
      123: begin
        ab[1][0] = abs[0];  // |220-221|
      end
      125: begin
        ab[1][0] = abs[1];  // |128-0|
      end
      default: begin
        ab[1][0] = 0;
      end
    endcase
    ab[1][1] = {1'b0, sum2[0][30:0]};
  end

  // out_buf
  wire out_buf_CG;
  GATED_OR OUT_BUF (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && !(cnteq125)),
    .RST_N(rst_n),
    .CLOCK_GATED(out_buf_CG)
  );
  reg [31:0] out_buf;
  always @(posedge out_buf_CG, negedge rst_n) begin
    if (!rst_n) out_buf <= 0;
    else if (cnteq125) out_buf <= nu_wire[0];
  end
  // out_valid
  wire out_valid_CG;
  reg out_valid_sleep;
  always @(*) begin
    case (cnt)
      1023, 0: out_valid_sleep = 0;
      default: out_valid_sleep = 1;
    endcase
  end
  GATED_OR OUT_VALID (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && out_valid_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(out_valid_CG)
  );
  always @(posedge out_valid_CG, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (cnt == 1023) out_valid <= 1;
    else out_valid <= 0;
  end
  // out
  wire out_CG;
  GATED_OR OUT (
    .CLOCK(clk),
    .SLEEP_CTRL(cg_en && out_valid_sleep),
    .RST_N(rst_n),
    .CLOCK_GATED(out_CG)
  );
  always @(posedge out_valid_CG, negedge rst_n) begin
    if (!rst_n) out <= 0;
    else if (cnt == 1023) out <= out_buf;
    // else out <= 0;
  end

  reg [31:0] mtx00, mtx01, mtx10, mtx11;
  always @(*) begin
    mtx00 = max[0][0];
    mtx01 = max[0][1];
    mtx10 = max[1][0];
    mtx11 = max[1][1];
  end
  reg [31:0] big00, big01, big10, big11, big20, big21, big30, big31;
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP1 (
    .a(pool[0][0]),
    .b(pool[0][1]),
    .zctr(1'b0),
    .z0(),
    .z1(big00),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP2 (
    .a(pool[1][0]),
    .b(pool[1][1]),
    .zctr(1'b0),
    .z0(),
    .z1(big10),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP3 (
    .a(big00),
    .b(big10),
    .zctr(1'b0),
    .z0(),
    .z1(max[0][0]),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP4 (
    .a(pool[0][2]),
    .b(pool[0][3]),
    .zctr(1'b0),
    .z0(),
    .z1(big01),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP5 (
    .a(pool[1][2]),
    .b(pool[1][3]),
    .zctr(1'b0),
    .z0(),
    .z1(big11),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP6 (
    .a(big01),
    .b(big11),
    .zctr(1'b0),
    .z0(),
    .z1(max[0][1]),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP7 (
    .a(pool[2][0]),
    .b(pool[2][1]),
    .zctr(1'b0),
    .z0(),
    .z1(big20),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP8 (
    .a(pool[3][0]),
    .b(pool[3][1]),
    .zctr(1'b0),
    .z0(),
    .z1(big30),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP9 (
    .a(big20),
    .b(big30),
    .zctr(1'b0),
    .z0(),
    .z1(max[1][0]),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP10 (
    .a(pool[2][2]),
    .b(pool[2][3]),
    .zctr(1'b0),
    .z0(),
    .z1(big21),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP11 (
    .a(pool[3][2]),
    .b(pool[3][3]),
    .zctr(1'b0),
    .z0(),
    .z1(big31),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP12 (
    .a(big21),
    .b(big31),
    .zctr(1'b0),
    .z0(),
    .z1(max[1][1]),
    .aeqb()
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP13 (
    .a(mtxprod[0]),
    .b(mtxprod[1]),
    .zctr(1'b0),
    .z0(min01),
    .z1(max01)

  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP14 (
    .a(mtxprod[2]),
    .b(mtxprod[3]),
    .zctr(1'b0),
    .z0(min23),
    .z1(max23)

  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP15 (
    .a(max01),
    .b(max23),
    .zctr(1'b0),
    .z0(),
    .z1(xmax)
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP16 (
    .a(min01),
    .b(min23),
    .zctr(1'b0),
    .z0(xmin),
    .z1()
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_0 (
    .a  (mtx00),
    .b  (_Weight[0][0]),
    .c  (mtx01),
    .d  (_Weight[1][0]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[0])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_1 (
    .a  (mtx00),
    .b  (_Weight[0][1]),
    .c  (mtx01),
    .d  (_Weight[1][1]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[1])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_2 (
    .a  (mtx10),
    .b  (_Weight[0][0]),
    .c  (mtx11),
    .d  (_Weight[1][0]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[2])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_3 (
    .a  (mtx10),
    .b  (_Weight[0][1]),
    .c  (mtx11),
    .d  (_Weight[1][1]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[3])
  );

  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM30 (
    .a  (abc[0][0]),
    .b  (abc[0][1]),
    .c  (abc[0][2]),
    .rnd(inst_rnd),
    .z  (sum3[0])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM31 (
    .a  (abc[1][0]),
    .b  (abc[1][1]),
    .c  (abc[1][2]),
    .rnd(inst_rnd),
    .z  (sum3[1])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM32 (
    .a  (abc[2][0]),
    .b  (abc[2][1]),
    .c  (abc[2][2]),
    .rnd(inst_rnd),
    .z  (sum3[2])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM33 (
    .a  (abc[3][0]),
    .b  (abc[3][1]),
    .c  (abc[3][2]),
    .rnd(inst_rnd),
    .z  (sum3[3])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM34 (
    .a  (abc[4][0]),
    .b  (abc[4][1]),
    .c  (abc[4][2]),
    .rnd(inst_rnd),
    .z  (sum3[4])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM35 (
    .a  (abc[5][0]),
    .b  (abc[5][1]),
    .c  (abc[5][2]),
    .rnd(inst_rnd),
    .z  (sum3[5])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM36 (
    .a  (abc[6][0]),
    .b  (abc[6][1]),
    .c  (abc[6][2]),
    .rnd(inst_rnd),
    .z  (sum3[6])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM37 (
    .a  (abc[7][0]),
    .b  (abc[7][1]),
    .c  (abc[7][2]),
    .rnd(inst_rnd),
    .z  (sum3[7])
  );
  DW_fp_sum3 #(
    .sig_width(inst_sig_width),
    .exp_width(inst_exp_width),
    .ieee_compliance(inst_ieee_compliance),
    .arch_type(inst_arch_type)
  ) SUM38 (
    .a  (abc[8][0]),
    .b  (abc[8][1]),
    .c  (abc[8][2]),
    .rnd(inst_rnd),
    .z  (sum3[8])
  );

  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT0 (
    .a  (m[0][0]),
    .b  (m[0][1]),
    .rnd(inst_rnd),
    .z  (prod[0])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT1 (
    .a  (m[1][0]),
    .b  (m[1][1]),
    .rnd(inst_rnd),
    .z  (prod[1])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT2 (
    .a  (m[2][0]),
    .b  (m[2][1]),
    .rnd(inst_rnd),
    .z  (prod[2])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT3 (
    .a  (m[3][0]),
    .b  (m[3][1]),
    .rnd(inst_rnd),
    .z  (prod[3])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT4 (
    .a  (m[4][0]),
    .b  (m[4][1]),
    .rnd(inst_rnd),
    .z  (prod[4])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT5 (
    .a  (m[5][0]),
    .b  (m[5][1]),
    .rnd(inst_rnd),
    .z  (prod[5])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT6 (
    .a  (m[6][0]),
    .b  (m[6][1]),
    .rnd(inst_rnd),
    .z  (prod[6])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT7 (
    .a  (m[7][0]),
    .b  (m[7][1]),
    .rnd(inst_rnd),
    .z  (prod[7])
  );
  DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT8 (
    .a  (m[8][0]),
    .b  (m[8][1]),
    .rnd(inst_rnd),
    .z  (prod[8])
  );

  DW_fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round) DIV0 (
    .a  (nu[0]),
    .b  (de[0]),
    .rnd(inst_rnd),
    .z  (q[0])
  );
  DW_fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round) DIV1 (
    .a  (nu[1]),
    .b  (de[1]),
    .rnd(inst_rnd),
    .z  (q[1])
  );
  DW_fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round) DIV2 (
    .a  (nu[2]),
    .b  (32'b0_10000010_00100000000000000000000),
    .rnd(inst_rnd),
    .z  (q[2])
  );

  DW_fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch) U1 (
    .a(z),
    .z(expz)
  );


  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) NU0 (
    .a  (nua[0]),
    .b  (nub[0]),
    .rnd(inst_rnd),
    .z  (nu_wire[0])
  );

  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DE0 (
    .a  (dea[0]),
    .b  (deb[0]),
    .rnd(inst_rnd),
    .z  (de_wire[0])
  );

  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) NU1 (
    .a  (nua[1]),
    .b  (nub[1]),
    .rnd(inst_rnd),
    .z  (nu_wire[1])
  );

  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DE1 (
    .a  (dea[1]),
    .b  (deb[1]),
    .rnd(inst_rnd),
    .z  (de_wire[1])
  );
  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DISTANCE0 (
    .a  (ab[0][0]),
    .b  (ab[0][1]),
    .rnd(inst_rnd),
    .z  (sum2[0])
  );
  DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DISTANCE1 (
    .a  (ab[1][0]),
    .b  (ab[1][1]),
    .rnd(inst_rnd),
    .z  (sum2[1])
  );
endmodule
