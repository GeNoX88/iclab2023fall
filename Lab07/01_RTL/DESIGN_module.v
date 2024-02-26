module CLK_1_MODULE (
  clk,
  rst_n,
  in_valid,
  seed_in,
  out_idle,
  out_valid,
  seed_out,

  clk1_handshake_flag1,
  clk1_handshake_flag2,
  clk1_handshake_flag3,
  clk1_handshake_flag4
);
  // You can change the input / output of the custom flag ports
  input clk1_handshake_flag1;  // sack
  output clk1_handshake_flag2;  // sreq
  input clk1_handshake_flag3;
  output clk1_handshake_flag4;




  input clk;  // 14.1ns
  input rst_n;
  input in_valid;
  input [31:0] seed_in;
  input out_idle;  // from Handshake_syn's sidle
  output reg out_valid;  // to Handshake_syn's sready
  output reg [31:0] seed_out;  // to Handshake_syn's din
  reg got;
  reg [31:0] seed_buf;

  //got
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) got <= 0;
    else if (clk1_handshake_flag1) got <= 0;
    else if (in_valid) got <= 1;
  end
  //seed_buf
  always @(posedge clk) begin
    if (in_valid) seed_buf <= seed_in;
  end
  //seed_out
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) seed_out <= 0;
    else if (clk1_handshake_flag1) seed_out <= 0;
    else if (in_valid && !got) seed_out <= seed_in;
  end
  //out_valid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (clk1_handshake_flag1) out_valid <= 0;  // sack
    else if (in_valid) out_valid <= 1;
  end
endmodule

module CLK_2_MODULE (
  // You can change the input / output of the custom flag ports
  output handshake_clk2_flag1,
  input  handshake_clk2_flag2,  // wfull from Handshake
  output handshake_clk2_flag3,
  output handshake_clk2_flag4,
  input  clk2_fifo_flag1,
  input  clk2_fifo_flag2,
  output clk2_fifo_flag3,
  output clk2_fifo_flag4,


  input             clk,        // 3.9ns
  input             rst_n,
  input             in_valid,   // from Handshake_syn's dvalid
  input      [31:0] seed,       // from Handshake_syn's dout
  input             fifo_full,  // from FIFO_syn's wfull
  output reg        busy,       // to Handshake_syn's dbusy
  output            out_valid,  // to FIFO_syn's winc
  output reg [31:0] rand_num    // to FIFO_syn's wdata
);
  wire almost_full = clk2_fifo_flag2;
  wire wfull_comb = clk2_fifo_flag1;
  reg [31:0] seed_a, seed_b, seed_c, seed_reg;
  //   reg use_reg;
  reg [7:0] cnt;
  //   always @(posedge clk, negedge rst_n) begin
  //     if (!rst_n) use_reg <= 0;
  //     else if (out_valid) use_reg <= 1;
  //   end
  reg [31:0] rand_num_buf;
  reg state;
  localparam notFULL = 0, FULL = 1;
  always @(*) begin
    seed_a = busy ? rand_num ^ (rand_num << 13) : seed ^ (seed << 13);
    seed_b = seed_a ^ (seed_a >> 17);
    seed_c = seed_b ^ (seed_b << 5);
  end
  reg wi;

  //busy (to Handshake_syn)
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) busy <= 0;
    else begin
      if (in_valid) busy <= 1;
      else if (cnt == 0 && out_valid) busy <= 0;
    end
  end
  //cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else begin
      if (cnt == 0 && in_valid || cnt != 0 && out_valid) cnt <= cnt + 1;
    end
  end
  // wi
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) wi <= 0;
    else if (in_valid || busy) begin  // I am Master
      wi <= 1;
    end else wi <= 0;
  end
  //state
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= notFULL;
    else if (state == notFULL && almost_full) state <= FULL;
    else if (state == FULL && almost_full) state <= notFULL;
    else if (in_valid) state <= notFULL;
  end
  //out_valid
  assign out_valid = wi && ((state==notFULL && !almost_full) || (state==FULL && almost_full));

  // rand_num
  always @(posedge clk) begin
    if (cnt == 0 && in_valid || cnt != 0 && out_valid) rand_num <= seed_c;
  end
endmodule

module CLK_3_MODULE (
  clk,
  rst_n,
  fifo_empty,
  fifo_rdata,
  fifo_rinc,
  out_valid,
  rand_num,

  fifo_clk3_flag1,
  fifo_clk3_flag2,
  fifo_clk3_flag3,
  fifo_clk3_flag4
);
  // You can change the input / output of the custom flag ports
  input fifo_clk3_flag1;
  input fifo_clk3_flag2;
  output fifo_clk3_flag3;
  output fifo_clk3_flag4;






  input clk;  // 20.7ns
  input rst_n;
  input fifo_empty;  // rempty from FIFO_syn
  input [31:0] fifo_rdata;  // rdata from FIFO_syn
  output fifo_rinc;  // to FIFO_syn's rinc
  output reg out_valid;  // to pattern
  output reg [31:0] rand_num;  // to pattern
  reg out_valid_q;
  reg ri;
  reg [7:0] cnt;

  assign fifo_rinc = !fifo_empty;
  //out_valid_q
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid_q <= 0;
    else begin
      if (~fifo_empty) out_valid_q <= 1;
      else out_valid_q <= 0;
    end
  end
  //out_valid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else out_valid <= cnt == 255 ? 0 : out_valid_q;
  end
  //cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else if (out_valid) cnt <= cnt + 1;
  end
  //rand_num
  always @(*) begin
    rand_num = out_valid ? fifo_rdata : 0;
  end

endmodule
