module Handshake_syn #(
  parameter WIDTH = 32
) (
  sclk,
  dclk,
  rst_n,
  sready,
  din,
  dbusy,
  sidle,
  dvalid,
  dout,
  clk1_handshake_flag1,
  clk1_handshake_flag2,
  clk1_handshake_flag3,
  clk1_handshake_flag4,
  handshake_clk2_flag1,
  handshake_clk2_flag2,
  handshake_clk2_flag3,
  handshake_clk2_flag4
);
  // You can change the input / output of the custom flag ports
  output clk1_handshake_flag1;
  input clk1_handshake_flag2;
  output clk1_handshake_flag3;
  output clk1_handshake_flag4;
  input handshake_clk2_flag1;  // wfull
  output handshake_clk2_flag2;  // wfull
  output handshake_clk2_flag3;
  output handshake_clk2_flag4;

  // NDFF_syn WFULL (
  //   .clk(dclk),
  //   .rst_n(rst_n),
  //   .D(handshake_clk2_flag1),
  //   .Q(handshake_clk2_flag2)
  // );

  assign handshake_clk2_flag2 = handshake_clk2_flag1;

  // Remember:
  //   Don't modify the signal name
  reg sreq;
  wire dreq;
  reg dack;
  wire sack;

  input sclk, dclk;  // 14.1ns, 3.9ns
  input rst_n;
  input sready;  // from clk1's out_valid
  input dbusy;  // from clk2's busy
  input [WIDTH-1:0] din;  // from clk1's seed_out
  output sidle;  // to clk1's out_idle
  output reg dvalid;  // to clk 2's in_valid
  output reg [WIDTH-1:0] dout;  //to clk2's seed

  reg flag;
  always @(posedge dclk, negedge rst_n) begin
    if (!rst_n) flag <= 0;
    else if (dreq) flag <= 1;
    else flag <= 0;
  end

  // sreq
  always @(*) begin
    sreq = sready;
  end

  //dack
  always @(posedge dclk, negedge rst_n) begin
    if (!rst_n) dack <= 0;
    else if (dreq && !dbusy) dack <= 1;
    else if (!dreq) dack <= 0;
  end

  //dout
  always @(posedge dclk, negedge rst_n) begin
    if (!rst_n) dout <= 0;
    // else if(dreq) dout <= din;
    else if (dreq & !flag) dout <= din;
  end
  //clk1_handshake_flag1
  assign clk1_handshake_flag1 = sack;


  //dvalid
  always @(posedge dclk, negedge rst_n) begin
    if (!rst_n) dvalid <= 0;
    else if (dbusy) dvalid <= 0;
    else if (dreq & !flag) dvalid <= 1;
  end



  NDFF_syn REQ (
    .clk(dclk),
    .rst_n(rst_n),
    .D(sreq),
    .Q(dreq)
  );
  NDFF_syn ACK (
    .clk(sclk),
    .rst_n(rst_n),
    .D(dack),
    .Q(sack)
  );
endmodule
