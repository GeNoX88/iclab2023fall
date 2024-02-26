module FIFO_syn #(
  parameter WIDTH = 32,
  parameter WORDS = 64
) (
  wclk,
  rclk,
  rst_n,
  winc,
  wdata,
  wfull,
  rinc,
  rdata,
  rempty,
  clk2_fifo_flag1,
  clk2_fifo_flag2,
  clk2_fifo_flag3,
  clk2_fifo_flag4,
  fifo_clk3_flag1,
  fifo_clk3_flag2,
  fifo_clk3_flag3,
  fifo_clk3_flag4
);
  // You can change the input / output of the custom flag ports
  output clk2_fifo_flag1;
  output clk2_fifo_flag2;
  output clk2_fifo_flag3;
  output clk2_fifo_flag4;
  input fifo_clk3_flag1;
  input fifo_clk3_flag2;
  output fifo_clk3_flag3;
  output fifo_clk3_flag4;

  localparam addr_width = $clog2(WORDS);
  input wclk, rclk;  // 3.9ns, 20.7ns
  input rst_n;
  input winc;  // from clk2's out_valid
  input [WIDTH-1:0] wdata;  // from clk2's rand_num
  input rinc;  // from clk3's fifo_rinc
  output reg rempty;  // to clk3's fifo_empty
  output reg wfull;  // to clk2's fifo_full
  output reg [WIDTH-1:0] rdata;  // to clk3's fifo_rdata
  // Remember: 
  //   wptr and rptr should be gray coded
  //   Don't modify the signal name
  reg [addr_width:0] wptr;
  reg [addr_width:0] rptr;

  reg [addr_width:0] wp, wptr_rr, rp, rptr_rr;
  wire [WIDTH-1:0] wdata_DOA;
  wire [WIDTH-1:0] rdata_q;
  reg almost_full;
  wire [addr_width:0] wptr_nxt;
  wire wfull_comb = wptr == {~rptr_rr[addr_width:addr_width-1], rptr_rr[addr_width-2:0]};
  assign clk2_fifo_flag1 = wfull_comb;
  assign clk2_fifo_flag2 = almost_full;

  assign wptr_nxt = ((wp + 7'd1) >> 1) ^ (wp + 7'd1);
  always @(posedge wclk) begin
    // almost_full <= wptr_nxt == {~rptr_rr[addr_width:addr_width-1], rptr_rr[addr_width-2:0]};
  end
  //wptr, rptr
  always @* begin
    wptr = (wp >> 1) ^ wp;
    rptr = (rp >> 1) ^ rp;
  end
  always @(*) begin
    rempty = rptr == wptr_rr;
    wfull  = ~winc;
    // wfull = (wptr == {~rptr_rr[addr_width:addr_width-1], rptr_rr[addr_width-2:0]});
  end
  always @(posedge wclk) begin
    almost_full <= (wptr_nxt == {~rptr_rr[addr_width:addr_width-1], rptr_rr[addr_width-2:0]});
  end
  //wp
  always @(posedge wclk, negedge rst_n) begin
    if (!rst_n) wp <= 0;
    else if (winc) wp <= wp + 1;
  end
  //rp
  always @(posedge rclk, negedge rst_n) begin
    if (!rst_n) rp <= 0;
    else if (rinc) rp <= rp + 1;
  end


  // rdata
  //  Add one more register stage to rdata
  always @(posedge rclk) begin
    rdata <= rdata_q;
  end
  NDFF_BUS_syn #(
    .WIDTH(addr_width + 1)
  ) W (
    .clk(wclk),
    .rst_n(rst_n),
    .D(rptr),
    .Q(rptr_rr)
  );
  NDFF_BUS_syn #(
    .WIDTH(addr_width + 1)
  ) R (
    .clk(rclk),
    .rst_n(rst_n),
    .D(wptr),
    .Q(wptr_rr)
  );
  DUAL_64X32X1BM1 u_dual_sram (  // 64 words, 32bits/word
    .CKA(wclk),
    .CKB(rclk),
    .WEAN(~winc),  //write port
    .WEBN(1'b1),  // read port
    .CSA(1'b1),
    .CSB(1'b1),
    .OEA(1'b1),
    .OEB(1'b1),
    .A0(wp[0]),
    .A1(wp[1]),
    .A2(wp[2]),
    .A3(wp[3]),
    .A4(wp[4]),
    .A5(wp[5]),
    .B0(rp[0]),
    .B1(rp[1]),
    .B2(rp[2]),
    .B3(rp[3]),
    .B4(rp[4]),
    .B5(rp[5]),
    .DIA0(wdata[0]),
    .DIA1(wdata[1]),
    .DIA2(wdata[2]),
    .DIA3(wdata[3]),
    .DIA4(wdata[4]),
    .DIA5(wdata[5]),
    .DIA6(wdata[6]),
    .DIA7(wdata[7]),
    .DIA8(wdata[8]),
    .DIA9(wdata[9]),
    .DIA10(wdata[10]),
    .DIA11(wdata[11]),
    .DIA12(wdata[12]),
    .DIA13(wdata[13]),
    .DIA14(wdata[14]),
    .DIA15(wdata[15]),
    .DIA16(wdata[16]),
    .DIA17(wdata[17]),
    .DIA18(wdata[18]),
    .DIA19(wdata[19]),
    .DIA20(wdata[20]),
    .DIA21(wdata[21]),
    .DIA22(wdata[22]),
    .DIA23(wdata[23]),
    .DIA24(wdata[24]),
    .DIA25(wdata[25]),
    .DIA26(wdata[26]),
    .DIA27(wdata[27]),
    .DIA28(wdata[28]),
    .DIA29(wdata[29]),
    .DIA30(wdata[30]),
    .DIA31(wdata[31]),
    .DIB0(),
    .DIB1(),
    .DIB2(),
    .DIB3(),
    .DIB4(),
    .DIB5(),
    .DIB6(),
    .DIB7(),
    .DIB8(),
    .DIB9(),
    .DIB10(),
    .DIB11(),
    .DIB12(),
    .DIB13(),
    .DIB14(),
    .DIB15(),
    .DIB16(),
    .DIB17(),
    .DIB18(),
    .DIB19(),
    .DIB20(),
    .DIB21(),
    .DIB22(),
    .DIB23(),
    .DIB24(),
    .DIB25(),
    .DIB26(),
    .DIB27(),
    .DIB28(),
    .DIB29(),
    .DIB30(),
    .DIB31(),
    .DOA0(wdata_DOA[0]),
    .DOA1(wdata_DOA[1]),
    .DOA2(wdata_DOA[2]),
    .DOA3(wdata_DOA[3]),
    .DOA4(wdata_DOA[4]),
    .DOA5(wdata_DOA[5]),
    .DOA6(wdata_DOA[6]),
    .DOA7(wdata_DOA[7]),
    .DOA8(wdata_DOA[8]),
    .DOA9(wdata_DOA[9]),
    .DOA10(wdata_DOA[10]),
    .DOA11(wdata_DOA[11]),
    .DOA12(wdata_DOA[12]),
    .DOA13(wdata_DOA[13]),
    .DOA14(wdata_DOA[14]),
    .DOA15(wdata_DOA[15]),
    .DOA16(wdata_DOA[16]),
    .DOA17(wdata_DOA[17]),
    .DOA18(wdata_DOA[18]),
    .DOA19(wdata_DOA[19]),
    .DOA20(wdata_DOA[20]),
    .DOA21(wdata_DOA[21]),
    .DOA22(wdata_DOA[22]),
    .DOA23(wdata_DOA[23]),
    .DOA24(wdata_DOA[24]),
    .DOA25(wdata_DOA[25]),
    .DOA26(wdata_DOA[26]),
    .DOA27(wdata_DOA[27]),
    .DOA28(wdata_DOA[28]),
    .DOA29(wdata_DOA[29]),
    .DOA30(wdata_DOA[30]),
    .DOA31(wdata_DOA[31]),
    .DOB0(rdata_q[0]),
    .DOB1(rdata_q[1]),
    .DOB2(rdata_q[2]),
    .DOB3(rdata_q[3]),
    .DOB4(rdata_q[4]),
    .DOB5(rdata_q[5]),
    .DOB6(rdata_q[6]),
    .DOB7(rdata_q[7]),
    .DOB8(rdata_q[8]),
    .DOB9(rdata_q[9]),
    .DOB10(rdata_q[10]),
    .DOB11(rdata_q[11]),
    .DOB12(rdata_q[12]),
    .DOB13(rdata_q[13]),
    .DOB14(rdata_q[14]),
    .DOB15(rdata_q[15]),
    .DOB16(rdata_q[16]),
    .DOB17(rdata_q[17]),
    .DOB18(rdata_q[18]),
    .DOB19(rdata_q[19]),
    .DOB20(rdata_q[20]),
    .DOB21(rdata_q[21]),
    .DOB22(rdata_q[22]),
    .DOB23(rdata_q[23]),
    .DOB24(rdata_q[24]),
    .DOB25(rdata_q[25]),
    .DOB26(rdata_q[26]),
    .DOB27(rdata_q[27]),
    .DOB28(rdata_q[28]),
    .DOB29(rdata_q[29]),
    .DOB30(rdata_q[30]),
    .DOB31(rdata_q[31])
  );

endmodule
