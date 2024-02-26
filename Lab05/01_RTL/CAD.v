module CAD (
  input clk,
  input rst_n,
  input in_valid,
  input in_valid2,
  input [1:0] matrix_size,  // 2'b00 8x8=64, 2'b01 16x16=256, 2'b10 32x32=1024
  input signed [7:0] matrix,
  input [3:0] matrix_idx,
  input mode,  // 1'b0: Conv + 2x2 Pooling   1'b1:Trans Conv
  output reg out_valid,
  output reg out_value
);

  integer i, j;
  reg IDLE;
  reg EATI;
  reg EATK;
  reg EAT2;
  reg CONV;
  reg DECONV;
  // reg r_mode;
  reg [2:0] log2_side;
  reg [5:0] side;
  reg i_WE;
  reg [10:0] img_addr;
  reg [10:0] r_img_addr;
  reg [63:0] i_DI;
  wire [63:0] i_DO;
  reg [2:0] i_eat_cnt;  // 0 ~ 7
  wire [3:0] i_eat_cnt_p1 = i_eat_cnt + 1;
  reg [3:0] i_idx;

  reg k_WE;
  reg [6:0] k_addr;
  reg [6:0] r_kaddr;
  reg [39:0] k_DI;
  wire [39:0] k_DO;
  reg [2:0] k_eat_cnt;
  reg [3:0] k_idx;

  reg [4:0] cnt_20;
  reg [4:0] conv_row_base;  // 0~31
  reg [4:0] conv_col_base;  // 0~31
  reg [5:0] deconv_row_base;  // 0 ~ 35
  reg [5:0] deconv_col_base;  // 0 ~ 35
  wire signed [15:0] prod[0:19];
  reg signed [15:0] r_prod[0:19];
  reg signed [7:0] m[0:19][0:1];
  reg [47:0] r_img_conv[0:1];
  reg [39:0] r_img_deconv;
  reg [39:0] r_kernel_conv;
  reg [39:0] r_kernel_deconv;
  reg signed [19:0] pool[0:1][0:1];
  reg signed [19:0] max[0:1];
  reg signed [19:0] MAX;
  reg signed [19:0] deconv;
  reg signed [19:0] output_buf;
  reg first_round;
  reg w_last;


  // 64 elements 16 matrix = 128 word
  // 256 elements 16 matrix = 512 word
  // 1024 elements 16 matrix = 2048 word

  // IDLE
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) IDLE <= 1;
    else if (in_valid || in_valid2 || CONV || DECONV) IDLE <= 0;
    else IDLE <= 1;
  end
  // EATI
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) EATI <= 0;
    else if (IDLE && in_valid) EATI <= 1;
    else if (r_img_addr == (1 << {log2_side, 1'b1}) - 1 && i_eat_cnt == 7)
      EATI <= 0;
  end
  // EATK
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) EATK <= 0;
    else if (r_kaddr == 79 && k_eat_cnt[2]) EATK <= 0;
    else if (r_img_addr == (1 << {log2_side, 1'b1}) - 1 && i_eat_cnt == 7)
      EATK <= 1;
  end
  // EAT2
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) EAT2 <= 0;
    else if (in_valid2) EAT2 <= ~EAT2;
  end
  // CONV
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) CONV <= 0;
    else if (IDLE && in_valid2 && mode == 0) CONV <= 1;
    else if (w_last) CONV <= 0;
  end
  // DECONV
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) DECONV <= 0;
    else if (IDLE && in_valid2 && mode == 1) DECONV <= 1;
    else if (w_last) DECONV <= 0;
  end
  // log2_side
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) log2_side <= 0;
    else if (IDLE && in_valid) log2_side <= matrix_size + 3;  // 3 or 4 or 5
  end
  // side
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) side <= 0;
    else if (IDLE && in_valid) side <= 1 << matrix_size + 3;  // 8 or 16 or 32
  end
  // i_WE
  always @(*) begin
    if (IDLE && in_valid || EATI) i_WE = 0;
    else i_WE = 1;
  end
  // i_DI
  always @(*) begin
    if (i_eat_cnt == 0) i_DI = {56'b0, matrix};
    else i_DI = {i_DO, matrix};
  end
  // i_eat_cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) i_eat_cnt <= 0;
    else if (in_valid) i_eat_cnt <= i_eat_cnt_p1;  // 3'd0 ~ 3'd7
  end

  // k_WE
  always @(*) begin
    k_WE = !EATK;
  end
  // k_eat_cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) k_eat_cnt <= 0;
    else if (EATK) k_eat_cnt <= k_eat_cnt[2] ? 0 : k_eat_cnt + 1;
  end

  // k_DI
  always @(*) begin
    k_DI = {k_DO, matrix};
  end

  // prod
  generate
    for (genvar gi = 0; gi < 20; gi = gi + 1) begin
      assign prod[gi] = m[gi][0] * m[gi][1];
    end
  endgenerate


  // i_idx
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) i_idx <= 0;
    else if (IDLE && in_valid2) begin
      i_idx <= matrix_idx;
    end
  end

  // k_idx
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) k_idx <= 0;
    else if (in_valid2) begin
      k_idx <= matrix_idx;
    end
  end



  // cnt_20
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt_20 <= 0;
    // else if(first_round) begin
    //   if(IDLE && in_valid2 && !mode || CONV) cnt_20 <= cnt_20==18? 0:cnt_20 + 2;
    // end
    else if (IDLE && in_valid2 && !mode || CONV) begin
      // if (first_round && cnt_20 == 18 || cnt_20 == 19) cnt_20 <= 0;
      if (cnt_20 == {4'b1001, !first_round}) cnt_20 <= 0;
      else cnt_20 <= cnt_20 + 1 + first_round;
      // if (first_round) cnt_20 <= cnt_20 == 20 ? 0 : cnt_20 + 2;
      // else cnt_20 <= cnt_20 == 19 ? 0 : cnt_20 + 1;
    end else if (IDLE && in_valid2 && mode || DECONV) begin
      if (first_round && cnt_20 == 2) cnt_20 <= 18;
      else cnt_20 <= (cnt_20 == 19) ? 0 : cnt_20 + 1;
    end
  end
  // conv_row_base, conv_col_base
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      conv_row_base <= 0;
      conv_col_base <= 0;
    end else if (CONV && cnt_20 == {4'b1001, !first_round}) begin
      if (w_last) begin
        conv_row_base <= 0;
        conv_col_base <= 0;
      end else begin
        conv_row_base <= conv_col_base == side - 6 ? conv_row_base + 2:conv_row_base;
        conv_col_base <= conv_col_base == side - 6 ? 0 : conv_col_base + 2;
      end
    end
  end
  // deconv_row_base, deconv_col_base
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      deconv_row_base <= 0;
      deconv_col_base <= 0;
    end else if (DECONV && cnt_20 == 19) begin
      if (w_last) begin
        deconv_row_base <= 0;
        deconv_col_base <= 0;
      end else begin
        deconv_row_base <= deconv_col_base == side + 3 ? deconv_row_base+1:deconv_row_base;
        deconv_col_base <= deconv_col_base == side + 3 ? 0 : deconv_col_base + 1;
      end
    end
  end
  // 第0格在63 第1格在(63-8) 第2格在(63-16) 阿6x6的第一行在conv_col_base[2:0]格
  // conv_col_base[2:0]=0,1,2 則取六格 3取五 4取四 5取三 6取二
  // 00餵地址 01讀0列左 02有生的 03時有死的
  // 01餵地址 02讀0列右 03有生的 04時有死的 07有r_prod
  // 02餵地址 03讀1列左 04有生的 05時有死的
  // 03餵地址 04讀1列右 05有生的 06時有死的 07有r_prod
  // 04餵地址 05讀2列左 06有生的 07時有死的
  // 05餵地址 06讀2列右 07有生的 08時有死的 09有r_prod
  // 06餵地址 07讀3列左 08有生的 09時有死的
  // 07餵地址 08讀3列右 09有生的 10時有死的 11有r_prod
  // 08餵地址 09讀4列左 10有生的 11時有死的
  // 09餵地址 10讀4列右 11有生的 12時有死的 13有r_prod
  // 10餵地址 11讀5列左 12有生的 13時有死的
  // 11餵地址 12讀5列右 13有生的 14時有死的 15有r_prod
  // 16有MAX

  // 02餵列0地址 03讀列0  04時有生的 05時有死的
  // 04餵列1地址 05讀列1  06時有生的 07時有死的
  // 06餵列2地址 07讀列2  08時有生的 09時有死的
  // 08餵列3地址 09讀列3  10時有生的 11時有死的
  // 10餵列4地址 11讀列4  12時有生的 13時有死的

  // first_round:
  // img：
  //             00讀0列 02有生的 04有r_img  08有r_prod
  // 00餵列1地址 02讀列1 04有生的 06有r_img  08有r_prod
  // 02餵列2地址 04讀列2 06有生的 08有r_img  10有r_prod
  // 04餵列3地址 06讀列3 08有生的 10有r_img  12有r_prod
  // 06餵列4地址 08讀列4 10有生的 12有r_img  14有r_prod
  // 08餵列5地址 10讀列5 12有生的 14有r_img  16有r_prod
  // 18有MAX

  // ker：
  //             02讀列0  04時有生的 06時有死的r_kernel 08有列0 r_prod
  // 02餵列1地址 04讀列1  06時有生的 08時有死的r_kernel 10有列1 r_prod
  // 04餵列2地址 06讀列2  08時有生的 10時有死的r_kernel 12有列2 r_prod
  // 06餵列3地址 08讀列3  10時有生的 12時有死的r_kernel 14有列3 r_prod
  // 08餵列4地址 10讀列4  12時有生的 14時有死的r_kernel 16有列4 r_prod





  //
  // 18有死的上排conv(pool[0]) 20有死的下排conv(pool[1])跟MAX

  // r_img_addr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) r_img_addr <= 0;
    else if (in_valid && i_eat_cnt_p1[3]) r_img_addr <= r_img_addr + 1;
    else if (IDLE && in_valid2)
      if (!mode)
        r_img_addr <= (matrix_idx << {log2_side, 1'b0} - 3) + (side >> 3);
      else r_img_addr <= matrix_idx << {log2_side, 1'b0} - 3;
    else if (w_last) r_img_addr <= 0;
    else if (CONV) begin
      r_img_addr <= 
      (i_idx << {log2_side, 1'b0} - 3) +
      (((conv_row_base+cnt_20[4:1]+first_round << log2_side) + conv_col_base) >> 3)
      + cnt_20[0];
    end else if (DECONV) begin
      r_img_addr <= 
      (i_idx << {log2_side, 1'b0} - 3) +
      ((deconv_row_base-cnt_20[4:1] << log2_side) + (deconv_col_base<4? 0:deconv_col_base-4) >> 3)
      + cnt_20[0];
    end
  end
  // r_kaddr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) r_kaddr <= 0;
    else if (in_valid && k_eat_cnt[2]) r_kaddr <= r_kaddr + 1;
    else if (CONV || DECONV) begin
      if (w_last) r_kaddr <= 0;
      else
        r_kaddr <= (in_valid2 ? matrix_idx : k_idx) * 5 + cnt_20[3:1] - (CONV && !first_round);
    end
  end
  // r_img_conv[1]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      r_img_conv[1] <= 48'b0;
    end else begin
      //   case (conv_col_base[2:0])
      //     0: begin
      //       if (!cnt_20[0])
      //         r_img_conv[1] <= i_DO[(63-{conv_col_base[2:0], 3'b0})-:48];
      //     end
      //     1: begin
      //       if (!cnt_20[0])
      //         r_img_conv[1] <= i_DO[(63-{conv_col_base[2:0], 3'b0})-:48];
      //     end
      //     2: begin
      //       if (!cnt_20[0])
      //         r_img_conv[1] <= i_DO[(63-{conv_col_base[2:0], 3'b0})-:48];
      //     end
      //     3: begin
      //       if (!cnt_20[0]) r_img_conv[1][47-:40] <= i_DO;
      //       else r_img_conv[1][7:0] <= i_DO[63-:8];
      //     end
      //     4: begin
      //       if (!cnt_20[0]) r_img_conv[1][47-:32] <= i_DO;
      //       else r_img_conv[1][15:0] <= i_DO[63-:16];
      //     end
      //     5: begin
      //       if (!cnt_20[0]) r_img_conv[1][47-:24] <= i_DO;
      //       else r_img_conv[1][23:0] <= i_DO[63-:24];
      //     end
      //     6: begin
      //       if (!cnt_20[0]) r_img_conv[1][47-:16] <= i_DO;
      //       else r_img_conv[1][31:0] <= i_DO[63-:32];
      //     end
      //     7: begin
      //       if (!cnt_20[0]) r_img_conv[1][47-:08] <= i_DO;
      //       else r_img_conv[1][39:0] <= i_DO[63-:40];
      //     end
      //   endcase
      if (!cnt_20[0]) begin
        r_img_conv[1] <= i_DO[(63-{conv_col_base[2:1], 4'b0})-:48];
      end else begin
        case (conv_col_base[2:0])
          3: begin
            r_img_conv[1][7:0] <= i_DO[63-:8];
          end
          4: begin
            r_img_conv[1][15:0] <= i_DO[63-:16];
          end
          5: begin
            r_img_conv[1][23:0] <= i_DO[63-:24];
          end
          6: begin
            r_img_conv[1][31:0] <= i_DO[63-:32];
          end
          7: begin
            r_img_conv[1][39:0] <= i_DO[63-:40];
          end
        endcase
      end
    end
  end
  // r_img_deconv
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) r_img_deconv <= 40'b0;
    else begin
      if (deconv_row_base - ((cnt_20-2) >> 1) < 0 || 
          deconv_row_base - ((cnt_20-2) >> 1) >= side)
        r_img_deconv <= 40'b0;
      else begin
        if (!cnt_20[0])
          case (deconv_col_base)
            8, 16, 24, 32, 40, 48, 56: begin
              r_img_deconv <= {i_DO[31-:32], 8'd0};
            end
            9, 17, 25, 33, 41, 49, 57: begin
              r_img_deconv <= {i_DO[23-:24], 16'd0};
            end
            10, 18, 26, 34, 42, 50, 58: begin
              r_img_deconv <= {i_DO[15-:16], 24'd0};
            end
            11, 19, 27, 35, 43, 51, 59: begin
              r_img_deconv <= {i_DO[7-:8], 32'd0};
            end
            0: begin
              r_img_deconv <= {32'b0, i_DO[63-:8]};
            end
            1: begin
              r_img_deconv <= {24'b0, i_DO[63-:16]};
            end
            2: begin
              r_img_deconv <= {16'b0, i_DO[63-:24]};
            end
            3: begin
              r_img_deconv <= {8'b0, i_DO[63-:32]};
            end
            4, 12, 20, 28, 36, 44, 52, 60: begin
              r_img_deconv <= i_DO[63-:40];
            end
            5, 13, 21, 29, 37, 45, 53, 61: begin
              r_img_deconv <= i_DO[55-:40];
            end
            6, 14, 22, 30, 38, 46, 54, 62: begin
              r_img_deconv <= i_DO[47-:40];
            end
            7, 15, 23, 31, 39, 47, 55, 63: begin
              r_img_deconv <= i_DO[39-:40];
            end
          endcase
        else
          case (deconv_col_base)
            side, side + 1, side + 2, side + 3: ;
            8, 16, 24, 32, 40, 48, 56: begin
              r_img_deconv[7:0] <= i_DO[63-:8];
            end
            9, 17, 25, 33, 41, 49, 57: begin
              r_img_deconv[15:0] <= i_DO[63-:16];
            end
            10, 18, 26, 34, 42, 50, 58: begin
              r_img_deconv[23:0] <= i_DO[63-:24];
            end
            11, 19, 27, 35, 43, 51, 59: begin
              r_img_deconv[31:0] <= i_DO[63-:32];
            end
          endcase
      end
    end
  end
  // r_img_conv[0]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) r_img_conv[0] <= 0;
    else if (!cnt_20[0]) r_img_conv[0] <= r_img_conv[1];
  end
  // r_kernel_conv
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      r_kernel_conv <= 40'b0;
    end else begin
      if (CONV && !cnt_20[0]) begin
        r_kernel_conv <= k_DO;  // fresh
      end
    end
  end
  // r_kernel_deconv
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      r_kernel_deconv <= 40'b0;
    end else if (DECONV && !cnt_20[0]) begin
      r_kernel_deconv <= {
        k_DO[0+:8], k_DO[8+:8], k_DO[16+:8], k_DO[24+:8], k_DO[32+:8]
      };
    end
  end
  // m[0:19]
  always @(*) begin
    if (DECONV) begin
      {m[00][0], m[01][0], m[02][0], m[03][0], m[04][0]} = r_img_deconv;
      {m[00][1], m[01][1], m[02][1], m[03][1], m[04][1]} = r_kernel_deconv;
    end else begin
      // 左上
      {m[00][0], m[01][0], m[02][0], m[03][0], m[04][0]} = r_img_conv[0][47:8];
      {m[00][1], m[01][1], m[02][1], m[03][1], m[04][1]} = r_kernel_conv;
    end
    // 右上
    {m[05][0], m[06][0], m[07][0], m[08][0], m[09][0]} = r_img_conv[0][39:0];
    {m[05][1], m[06][1], m[07][1], m[08][1], m[09][1]} = r_kernel_conv;
    // 左下
    {m[10][0], m[11][0], m[12][0], m[13][0], m[14][0]} = r_img_conv[1][47:8];
    {m[10][1], m[11][1], m[12][1], m[13][1], m[14][1]} = r_kernel_conv;
    // 右下
    {m[15][0], m[16][0], m[17][0], m[18][0], m[19][0]} = r_img_conv[1][39:0];
    {m[15][1], m[16][1], m[17][1], m[18][1], m[19][1]} = r_kernel_conv;
  end

  // r_prod
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 20; i = i + 1) r_prod[i] <= 0;
    end else begin
      for (i = 0; i < 20; i = i + 1) r_prod[i] <= prod[i];
    end
  end
  // pool
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 2; i = i + 1)
      for (j = 0; j < 2; j = j + 1) pool[i][j] <= 0;
    end else begin
      if (cnt_20[4:2] == 0) begin
        pool[0][0] <= 0;
        pool[0][1] <= 0;
        pool[1][0] <= 0;
        pool[1][1] <= 0;
      end else if (cnt_20==8-!first_round || cnt_20==10-!first_round || cnt_20==12-!first_round || cnt_20==14-!first_round || cnt_20==16-!first_round) begin
        pool[0][0] <= pool[0][0] + r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
        pool[0][1] <= pool[0][1] + r_prod[05] + r_prod[06] + r_prod[07] + r_prod[08] + r_prod[09];
        pool[1][0] <= pool[1][0] + r_prod[10] + r_prod[11] + r_prod[12] + r_prod[13] + r_prod[14];
        pool[1][1] <= pool[1][1] + r_prod[15] + r_prod[16] + r_prod[17] + r_prod[18] + r_prod[19];
      end
      // case (cnt_20)
      //   5: begin
      //     // pool[0][0] <= pool[0][0] + r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
      //     // pool[0][1] <= pool[0][1] + r_prod[05] + r_prod[06] + r_prod[07] + r_prod[08] + r_prod[09];
      //   end
      //   7, 9, 11, 13: begin
      //     // pool[0][0] <= pool[0][0] + r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
      //     // pool[0][1] <= pool[0][1] + r_prod[05] + r_prod[06] + r_prod[07] + r_prod[08] + r_prod[09];
      //     pool[1][0] <= pool[1][0] + r_prod[10] + r_prod[11] + r_prod[12] + r_prod[13] + r_prod[14];
      //     pool[1][1] <= pool[1][1] + r_prod[15] + r_prod[16] + r_prod[17] + r_prod[18] + r_prod[19];
      //   end
      //   15: begin
      //     pool[1][0] <= pool[1][0] + r_prod[10] + r_prod[11] + r_prod[12] + r_prod[13] + r_prod[14];
      //     pool[1][1] <= pool[1][1] + r_prod[15] + r_prod[16] + r_prod[17] + r_prod[18] + r_prod[19];
      //   end
      //   19: begin
      //     // pool[0][0] <= 0;
      //     // pool[0][1] <= 0;
      //     pool[1][0] <= 0;
      //     pool[1][1] <= 0;
      //   end
      // endcase
    end
  end
  always @* max[0] = pool[0][0] > pool[0][1] ? pool[0][0] : pool[0][1];
  always @* max[1] = pool[1][0] > pool[1][1] ? pool[1][0] : pool[1][1];
  always @* MAX = max[0] > max[1] ? max[0] : max[1];
  // // max
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) max[0] <= 0;
  //   else if (first_round && cnt_20 == 18 || cnt_20 == 14)
  //     max[0] <= pool[0][0] > pool[0][1] ? pool[0][0] : pool[0][1];
  // end
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) max[1] <= 0;
  //   else if (first_round && cnt_20 == 20 || cnt_20 == 16)
  //     max[1] <= pool[1][0] > pool[1][1] ? pool[1][0] : pool[1][1];
  // end

  // deconv
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) deconv <= 0;
    else if (cnt_20[4:2] == 0) deconv <= 0;
    else
      case (cnt_20)
        5, 7, 9, 11, 13:
        deconv <=  deconv + r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
      endcase
  end
  // output_buf
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) output_buf <= 0;
    else if (CONV) begin
      if (cnt_20 == 18) output_buf <= MAX;
    end else if (DECONV) begin
      if (first_round && cnt_20 == 19)
        output_buf <= r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
      else if (cnt_20 == 18) output_buf <= deconv;
    end
    // else if (cnt_20 == 19) begin
    //   if (CONV) output_buf <= max[0] > max[1] ? max[0] : max[1];
    //   else if (DECONV) output_buf <= deconv;
    // end
  end


  always @* begin
    if (IDLE && in_valid2) img_addr = matrix_idx << {log2_side, 1'b0} - 3;
    else img_addr = r_img_addr;
  end
  always @* begin
    if (EAT2) k_addr = matrix_idx * 5;
    else k_addr = r_kaddr;
  end
  // // last
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) last <= 0;
  //   else if((conv_row_base==(1<<log2_side)-4 || deconv_row_base==(1<<log2_side)+4) && cnt_20==19)
  //     last <= 1;
  //   else last <= 0;
  // end

  always @*
    w_last = ((conv_row_base==side-4 || deconv_row_base==side+4) && cnt_20==19);

  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) first_round <= 1;
    else if (CONV && first_round && cnt_20 == 18 || cnt_20 == 19)
      first_round <= w_last;
  end
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (CONV && first_round && cnt_20 == 18 || cnt_20 == 19)
      out_valid <= !w_last;
  end
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_value <= 0;
    // else if (CONV && first_round && cnt_20 == 18) begin
    //   out_value <= MAX;
    // end else if (DECONV && first_round) begin
    //   out_value <= r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
    else if (first_round) begin
      out_value <= CONV? MAX : r_prod[00] + r_prod[01] + r_prod[02] + r_prod[03] + r_prod[04];
    end else out_value <= output_buf[(cnt_20==19?0 : cnt_20+1)];  // 0~19
  end

  // wire [19:0] decimal_buf = output_buf;




















  SUMA180_2048X64X1BM1 IMAGE (
    .A0  (img_addr[00]),
    .A1  (img_addr[01]),
    .A2  (img_addr[02]),
    .A3  (img_addr[03]),
    .A4  (img_addr[04]),
    .A5  (img_addr[05]),
    .A6  (img_addr[06]),
    .A7  (img_addr[07]),
    .A8  (img_addr[08]),
    .A9  (img_addr[09]),
    .A10 (img_addr[10]),
    .DI0 (i_DI[00]),
    .DI1 (i_DI[01]),
    .DI2 (i_DI[02]),
    .DI3 (i_DI[03]),
    .DI4 (i_DI[04]),
    .DI5 (i_DI[05]),
    .DI6 (i_DI[06]),
    .DI7 (i_DI[07]),
    .DI8 (i_DI[08]),
    .DI9 (i_DI[09]),
    .DI10(i_DI[10]),
    .DI11(i_DI[11]),
    .DI12(i_DI[12]),
    .DI13(i_DI[13]),
    .DI14(i_DI[14]),
    .DI15(i_DI[15]),
    .DI16(i_DI[16]),
    .DI17(i_DI[17]),
    .DI18(i_DI[18]),
    .DI19(i_DI[19]),
    .DI20(i_DI[20]),
    .DI21(i_DI[21]),
    .DI22(i_DI[22]),
    .DI23(i_DI[23]),
    .DI24(i_DI[24]),
    .DI25(i_DI[25]),
    .DI26(i_DI[26]),
    .DI27(i_DI[27]),
    .DI28(i_DI[28]),
    .DI29(i_DI[29]),
    .DI30(i_DI[30]),
    .DI31(i_DI[31]),
    .DI32(i_DI[32]),
    .DI33(i_DI[33]),
    .DI34(i_DI[34]),
    .DI35(i_DI[35]),
    .DI36(i_DI[36]),
    .DI37(i_DI[37]),
    .DI38(i_DI[38]),
    .DI39(i_DI[39]),
    .DI40(i_DI[40]),
    .DI41(i_DI[41]),
    .DI42(i_DI[42]),
    .DI43(i_DI[43]),
    .DI44(i_DI[44]),
    .DI45(i_DI[45]),
    .DI46(i_DI[46]),
    .DI47(i_DI[47]),
    .DI48(i_DI[48]),
    .DI49(i_DI[49]),
    .DI50(i_DI[50]),
    .DI51(i_DI[51]),
    .DI52(i_DI[52]),
    .DI53(i_DI[53]),
    .DI54(i_DI[54]),
    .DI55(i_DI[55]),
    .DI56(i_DI[56]),
    .DI57(i_DI[57]),
    .DI58(i_DI[58]),
    .DI59(i_DI[59]),
    .DI60(i_DI[60]),
    .DI61(i_DI[61]),
    .DI62(i_DI[62]),
    .DI63(i_DI[63]),
    .DO0 (i_DO[00]),
    .DO1 (i_DO[01]),
    .DO2 (i_DO[02]),
    .DO3 (i_DO[03]),
    .DO4 (i_DO[04]),
    .DO5 (i_DO[05]),
    .DO6 (i_DO[06]),
    .DO7 (i_DO[07]),
    .DO8 (i_DO[08]),
    .DO9 (i_DO[09]),
    .DO10(i_DO[10]),
    .DO11(i_DO[11]),
    .DO12(i_DO[12]),
    .DO13(i_DO[13]),
    .DO14(i_DO[14]),
    .DO15(i_DO[15]),
    .DO16(i_DO[16]),
    .DO17(i_DO[17]),
    .DO18(i_DO[18]),
    .DO19(i_DO[19]),
    .DO20(i_DO[20]),
    .DO21(i_DO[21]),
    .DO22(i_DO[22]),
    .DO23(i_DO[23]),
    .DO24(i_DO[24]),
    .DO25(i_DO[25]),
    .DO26(i_DO[26]),
    .DO27(i_DO[27]),
    .DO28(i_DO[28]),
    .DO29(i_DO[29]),
    .DO30(i_DO[30]),
    .DO31(i_DO[31]),
    .DO32(i_DO[32]),
    .DO33(i_DO[33]),
    .DO34(i_DO[34]),
    .DO35(i_DO[35]),
    .DO36(i_DO[36]),
    .DO37(i_DO[37]),
    .DO38(i_DO[38]),
    .DO39(i_DO[39]),
    .DO40(i_DO[40]),
    .DO41(i_DO[41]),
    .DO42(i_DO[42]),
    .DO43(i_DO[43]),
    .DO44(i_DO[44]),
    .DO45(i_DO[45]),
    .DO46(i_DO[46]),
    .DO47(i_DO[47]),
    .DO48(i_DO[48]),
    .DO49(i_DO[49]),
    .DO50(i_DO[50]),
    .DO51(i_DO[51]),
    .DO52(i_DO[52]),
    .DO53(i_DO[53]),
    .DO54(i_DO[54]),
    .DO55(i_DO[55]),
    .DO56(i_DO[56]),
    .DO57(i_DO[57]),
    .DO58(i_DO[58]),
    .DO59(i_DO[59]),
    .DO60(i_DO[60]),
    .DO61(i_DO[61]),
    .DO62(i_DO[62]),
    .DO63(i_DO[63]),
    .CK  (clk),
    .WEB (i_WE),
    .OE  (1'b1),
    .CS  (1'b1)
  );

  SUMA180_80X40X1BM1 KERNEL (  // 0~4, 5~9, ...75~79
    .A0  (k_addr[0]),
    .A1  (k_addr[1]),
    .A2  (k_addr[2]),
    .A3  (k_addr[3]),
    .A4  (k_addr[4]),
    .A5  (k_addr[5]),
    .A6  (k_addr[6]),
    .DI0 (k_DI[0]),
    .DI1 (k_DI[1]),
    .DI2 (k_DI[2]),
    .DI3 (k_DI[3]),
    .DI4 (k_DI[4]),
    .DI5 (k_DI[5]),
    .DI6 (k_DI[6]),
    .DI7 (k_DI[7]),
    .DI8 (k_DI[8]),
    .DI9 (k_DI[9]),
    .DI10(k_DI[10]),
    .DI11(k_DI[11]),
    .DI12(k_DI[12]),
    .DI13(k_DI[13]),
    .DI14(k_DI[14]),
    .DI15(k_DI[15]),
    .DI16(k_DI[16]),
    .DI17(k_DI[17]),
    .DI18(k_DI[18]),
    .DI19(k_DI[19]),
    .DI20(k_DI[20]),
    .DI21(k_DI[21]),
    .DI22(k_DI[22]),
    .DI23(k_DI[23]),
    .DI24(k_DI[24]),
    .DI25(k_DI[25]),
    .DI26(k_DI[26]),
    .DI27(k_DI[27]),
    .DI28(k_DI[28]),
    .DI29(k_DI[29]),
    .DI30(k_DI[30]),
    .DI31(k_DI[31]),
    .DI32(k_DI[32]),
    .DI33(k_DI[33]),
    .DI34(k_DI[34]),
    .DI35(k_DI[35]),
    .DI36(k_DI[36]),
    .DI37(k_DI[37]),
    .DI38(k_DI[38]),
    .DI39(k_DI[39]),
    .DO0 (k_DO[0]),
    .DO1 (k_DO[1]),
    .DO2 (k_DO[2]),
    .DO3 (k_DO[3]),
    .DO4 (k_DO[4]),
    .DO5 (k_DO[5]),
    .DO6 (k_DO[6]),
    .DO7 (k_DO[7]),
    .DO8 (k_DO[8]),
    .DO9 (k_DO[9]),
    .DO10(k_DO[10]),
    .DO11(k_DO[11]),
    .DO12(k_DO[12]),
    .DO13(k_DO[13]),
    .DO14(k_DO[14]),
    .DO15(k_DO[15]),
    .DO16(k_DO[16]),
    .DO17(k_DO[17]),
    .DO18(k_DO[18]),
    .DO19(k_DO[19]),
    .DO20(k_DO[20]),
    .DO21(k_DO[21]),
    .DO22(k_DO[22]),
    .DO23(k_DO[23]),
    .DO24(k_DO[24]),
    .DO25(k_DO[25]),
    .DO26(k_DO[26]),
    .DO27(k_DO[27]),
    .DO28(k_DO[28]),
    .DO29(k_DO[29]),
    .DO30(k_DO[30]),
    .DO31(k_DO[31]),
    .DO32(k_DO[32]),
    .DO33(k_DO[33]),
    .DO34(k_DO[34]),
    .DO35(k_DO[35]),
    .DO36(k_DO[36]),
    .DO37(k_DO[37]),
    .DO38(k_DO[38]),
    .DO39(k_DO[39]),
    .CK  (clk),
    .WEB (k_WE),
    .OE  (1'b1),
    .CS  (1'b1)
  );
endmodule