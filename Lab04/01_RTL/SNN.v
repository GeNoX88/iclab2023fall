//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2023 Fall
//   Lab04 Exercise		: Siamese Neural Network 
//   Author     		: Jia-Yu Lee (maggie8905121@gmail.com)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : SNN.v
//   Module Name : SNN
//   Release version : V1.0 (Release Date: 2023-09)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

module SNN (
  //Input Port
  clk,
  rst_n,
  in_valid,
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
  parameter inst_arch_type = 0;
  parameter inst_arch = 0;
  parameter inst_faithful_round = 0;
  parameter inst_rnd = 3'd0;  // 我加的

  input rst_n, clk, in_valid;
  input [inst_sig_width+inst_exp_width:0] Img;  // IEEE-754 ∓0.5~255.0
  input [inst_sig_width+inst_exp_width:0] Kernel, Weight;  // IEEE-754 ∓0~0.5
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
  reg [inst_sig_width+inst_exp_width:0] abc[0:4][0:2];  // 5個
  reg [inst_sig_width+inst_exp_width:0] sum3[0:4], subconv[0:2];
  reg [inst_sig_width+inst_exp_width:0] convsum[0:3][0:3];  // 4x4
  reg [inst_sig_width+inst_exp_width:0] mtxprod[0:3];
  wire [inst_sig_width+inst_exp_width:0] mtxprod_wire[0:3];
  wire [31:0] max01, min01, max23, min23, xmax, xmin;
  reg [31:0] _xmax, _xmin;
  reg [31:0] nua[0:1], nub[0:1], dea[0:1], deb[0:1], vec2[0:3], abs[0:1];
  reg [31:0] nu[0:1], de[0:1];
  wire [31:0] q[0:1];  // DW輸出
  reg [31:0] z, vec1[0:3];
  wire [31:0] expz;
  wire [31:0] big[0:3][0:1];
  reg [31:0] pool[0:3][0:3];
  wire [31:0] max[0:1][0:1];
  wire [31:0] one = 32'b0_01111111_00000000000000000000000;
  reg [31:0] exppz, nmnu, nmde, nm[0:3], _nu0, _de0, _nu1, _de1;
  wire [31:0] nu_wire[0:1], de_wire[0:1];
  // 50ns面積、極限slack：
  // DW_fp_add:17245, 6.39
  // DW_fp_addsub:17414,
  // DW_fp_mult:41384, 4.73
  // DW_fp_sum3:63530, 9.8(說明書說比兩個adder更快)
  // DW_fp_recip:99443, 13.69(倒數器) 
  // DW_fp_mac: (能藉由三個輸入a,b,c來計算ab+c，因為無窮精度加上最後才捨入的關係，準確度比mul+add還高得多)
  // DW_fp_exp:162517, 16.49
  // DW_fp_cmp:2000, 0.50 
  // DW_fp_div:149415, 16.16
  // DW_fp_dp3:360656, 20.76 (三積之和)(說明書說比mul+add更精確)


  // Img1(∓ 0.5~255.0) => CNN => Activation func => Encoding 1
  //                                                            => L1 distance => output
  // Img2(∓ 0.5~255.0) => CNN => Activation func => Encoding 2

  // 當in_valid拉起，Img依序輸入六張4x4圖像，Img1_1(16cc), Img1_2(16cc), Img1_3(16cc), Img2_1(16cc), Img2_2(16cc), Img2_3(16cc)(因為每張圖有RGB三個通道，所以各有三個4x4圖)，共需96 cycles
  // 當in_valid拉起，依序輸入 3x3 Kernel(∓ 0~0.5)三個，為Kernel1(9cc), Kernel2(9cc), Kernel3(9cc)，共27 cycles
  // 當in_valid拉起，輸入 2x2 Weight矩陣(∓ 0~0.5)(4cc) for the weight of the fully connected layer，共4 cycles

  // Img1跟Img2(∓ 0.5~255.0)被padding成6x6以後，前者被餵到upper sub-network，後者被餵到 lower sub-network
  // 在CNN sub-network中，
  // 第一步，先將6x6 images三張跟 3x3 kernel 1,2,3做卷積(每個卷積元素9個乘法，共9乘法x16格x3層=432個乘法)，三層加起來(16個sum3加法)得一層4x4
  // 第二步，將4x4 image每個2x2 window比出一個max(需3次比較)，最後形成 2x2
  // 第三步，將2x2 image以矩陣乘法乘上2x2 matrix(共需8個乘法)，拉成4x1，最後再歸一化(兩次exp、一減一加一除)
  // 最後將兩個4x1結果代入Sigmoid或tanh，再算出兩者之間的L1 distance(四減三加)
  // Sigmoid = 1/(1+exp(-z)), tanh = (exp(z)-exp(-z))/(exp(z)+exp(-z))
  // 速度型的瓶頸在矩陣乘法+歸一化+激活函數+距離
  // Igm2_3的最後一個元素會卡住四個卷積元素


  // busy
  reg busy;
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) busy <= 0;
    else if (out_valid) busy <= 0;
    else if (in_valid | busy) busy <= 1;
  end
  // cnt
  reg [6:0] cnt;  // 0~127, 0吃到Kernel[0][0][0], 8吃到Kernel[0][2][2], 26吃到Kernel[2][2][2]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else if (out_valid) cnt <= 0;
    else if (in_valid | busy) cnt <= cnt + 1;
  end
  // _Opt
  reg [1:0] _Opt;
  always @(posedge clk) begin
    if (in_valid && !busy) _Opt <= Opt;
  end
  // _Kernel[0:2][0:2][0:2]
  reg [inst_exp_width+inst_sig_width:0] _Kernel[0:2][0:2][0:2];
  always @(posedge clk) begin
    if (cnt < 27) begin
      _Kernel[cnt/9][(cnt%9)/3][cnt%3] <= Kernel;
    end
  end
  // _Img_[0:5][1:4][1:4]
  reg [inst_exp_width+inst_sig_width:0] _Img_[0:2][1:4][1:4];  // 每張圖有3張6x6, Img1跟Img2共用
  always @(posedge clk) begin
    if (cnt < 96) begin
      _Img_[cnt[6:4]%3][1+cnt[3:2]][1+cnt[1:0]] <= Img;
    end
  end
  // _Img[0:2][0:5][0:5]
  reg [inst_exp_width+inst_sig_width:0] _Img[0:2][0:5][0:5];  // 每張圖有3張6x6, Img1跟Img2共用
  always @(*) begin
    for (i = 0; i < 3; i = i + 1) begin
      for (j = 1; j <= 4; j = j + 1) begin
        for (k = 1; k <= 4; k = k + 1) begin
          _Img[i][j][k] = _Img_[i][j][k];
        end
        _Img[i][0][j] = _Opt[0] ? 0 : _Img_[i][1][j];  // 正上
        _Img[i][j][0] = _Opt[0] ? 0 : _Img_[i][j][1];  // 正左
        _Img[i][5][j] = _Opt[0] ? 0 : _Img_[i][4][j];  // 正下
        _Img[i][j][5] = _Opt[0] ? 0 : _Img_[i][j][4];  // 正右
      end
      _Img[i][0][0] = _Opt[0] ? 0 : _Img_[i][1][1];  // 左上
      _Img[i][0][5] = _Opt[0] ? 0 : _Img_[i][1][4];  // 右上
      _Img[i][5][0] = _Opt[0] ? 0 : _Img_[i][4][1];  // 左下
      _Img[i][5][5] = _Opt[0] ? 0 : _Img_[i][4][4];  // 右下
    end
  end
  // _Weight[0:1][0:1]
  reg [inst_exp_width+inst_sig_width:0] _Weight[0:1][0:1];
  always @(posedge clk) begin
    if (cnt[6:2] == 0) _Weight[cnt[1]][cnt[0]] <= Weight;
  end




  wire [6:0] cnt_91 = cnt - 91;
  wire [6:0] cnt_43 = cnt - 43;
  // abc[0:3][0:2]
  always @(*) begin
    abc[0][0] = prod[0];
    abc[0][1] = prod[1];
    abc[0][2] = prod[2];

    abc[1][0] = prod[3];
    abc[1][1] = prod[4];
    abc[1][2] = prod[5];

    abc[2][0] = prod[6];
    abc[2][1] = prod[7];
    abc[2][2] = prod[8];

    abc[3][0] = subconv[0];
    abc[3][1] = subconv[1];
    abc[3][2] = subconv[2];

    abc[4][0] = 91<=cnt? conv[0][cnt_91[6:2]][cnt_91[1:0]]:conv[0][cnt_43[6:2]][cnt_43[1:0]];
    abc[4][1] = 91<=cnt? conv[1][cnt_91[6:2]][cnt_91[1:0]]:conv[1][cnt_43[6:2]][cnt_43[1:0]];
    abc[4][2] = 91<=cnt? conv[2][cnt_91[6:2]][cnt_91[1:0]]:conv[2][cnt_43[6:2]][cnt_43[1:0]];
  end
  // subconv[0:2]
  always @(posedge clk) begin
    if (9 <= cnt && cnt <= 104)
      for (i = 0; i < 3; i = i + 1) subconv[i] <= sum3[i];
  end
  wire [6:0] subconvcnt = cnt - 9;
  wire [6:0] convcnt = cnt - 10;
  // conv[0:5][0:3][0:3]
  always @(posedge clk) begin
    if (10 <= cnt && cnt <= 105) begin
      conv[(convcnt>>4)%3][convcnt[3:2]][convcnt[1:0]] <= sum3[3];
    end
  end
  // m[0:8][0:1]
  always @(*) begin
    m[0][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]];
    m[0][1] = _Kernel[subconvcnt[6:4]%3][0][0];

    m[1][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]+1];
    m[1][1] = _Kernel[subconvcnt[6:4]%3][0][1];

    m[2][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]][subconvcnt[1:0]+2];
    m[2][1] = _Kernel[subconvcnt[6:4]%3][0][2];

    m[3][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]];
    m[3][1] = _Kernel[subconvcnt[6:4]%3][1][0];

    m[4][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]+1];
    m[4][1] = _Kernel[subconvcnt[6:4]%3][1][1];

    m[5][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+1][subconvcnt[1:0]+2];
    m[5][1] = _Kernel[subconvcnt[6:4]%3][1][2];

    m[6][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]];
    m[6][1] = _Kernel[subconvcnt[6:4]%3][2][0];

    m[7][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]+1];
    m[7][1] = _Kernel[subconvcnt[6:4]%3][2][1];

    m[8][0] = _Img[subconvcnt[6:4]%3][subconvcnt[3:2]+2][subconvcnt[1:0]+2];
    m[8][1] = _Kernel[subconvcnt[6:4]%3][2][2];
  end

  // cnt==103時得到一個組合邏輯conv
  // 8得conv[0][0][0], 24得conv[1][0][0], 40得conv[2][0][0], 56得conv[3][0][0], 72得conv[4][0][0], 89得conv[5][0][0], 103得conv[5][3][3]
  //timing更正版(零延遲input型)：10才有死的conv[0][0][0], 26才有死的conv[1][0][0], 42才有死的conv[2][0][0], 58才有死的conv[3][0][0], 74才得conv[4][0][0], 90才得conv[5][0][0], 105才得conv[5][3][3]
  //timing二更版(conv切成(mult+sum3) + (sum3)): 11才有死conv[0][0], 43才有死conv[2][0][0], 59才有死conv[3][0][0], 74有死conv[3][3][3], 91才有死conv[5][0][0], 106才得死conv[5][3][3], 107得死convsum[5][3][3]

  // convsum[0:3][0:3]
  always @(posedge clk) begin
    if (43 <= cnt && cnt <= 58) begin  // 57會完成Img1的convsum
      convsum[cnt_43[6:2]][cnt_43[1:0]] <= sum3[4];
    end else if (91 <= cnt && cnt <= 106) begin  // 105會完成Img2的convsum
      convsum[cnt_91[6:2]][cnt_91[1:0]] <= sum3[4];
    end
  end
  // pool[0:3][0:3]
  always @(*) begin
    pool[0][0] = convsum[0][0];
    pool[0][1] = convsum[0][1];
    pool[1][0] = convsum[1][0];
    pool[1][1] = convsum[1][1];

    pool[0][2] = convsum[0][2];
    pool[0][3] = convsum[0][3];
    pool[1][2] = convsum[1][2];
    pool[1][3] = convsum[1][3];

    pool[2][0] = convsum[2][0];
    pool[2][1] = convsum[2][1];
    pool[3][0] = convsum[3][0];
    pool[3][1] = convsum[3][1];

    pool[2][2] = convsum[2][2];
    pool[2][3] = convsum[2][3];
    pool[3][2] = convsum[3][2];
    pool[3][3] = convsum[3][3];
  end
  // // max_reg[0:1][0:1];
  // always @(posedge clk) begin
  //   case (cnt)
  //     80, 103: begin  // 80無硬性規定，因為Img1的convsum都存好了
  //       max_reg[0][0] <= max[0][0];
  //       max_reg[0][1] <= max[0][1];
  //       max_reg[1][0] <= max[1][0];
  //       max_reg[1][1] <= max[1][1];
  //     end
  //   endcase
  // end
  // mtxprod[0:3]
  always @(posedge clk) begin
    case (cnt)
      83, 107: begin
        mtxprod[0] <= mtxprod_wire[0];  // 用max進IP算出的矩陣元素
        mtxprod[1] <= mtxprod_wire[1];  // 用max進IP算出的矩陣元素
        mtxprod[2] <= mtxprod_wire[2];  // 用max進IP算出的矩陣元素
        mtxprod[3] <= mtxprod_wire[3];  // 用max進IP算出的矩陣元素
      end
    endcase
  end
  always @(posedge clk) begin
    case (cnt)
      84, 108: begin
        _xmax <= xmax;
        _xmin <= xmin;
      end
    endcase
  end

  // nu_wire[0:1], de_wire[0:1]
  always @(posedge clk) begin
    case (cnt)
      85, 86, 87, 88, 109, 110, 111, 112: begin
        _nu0 <= nu_wire[0];
        _de0 <= de_wire[0];
      end
    endcase
  end
  // nu1_wire, de1_wire
  always @(posedge clk) begin
    case (cnt)
      88, 89, 90, 91, 112, 113, 114, 115: begin
        _nu1 <= nu_wire[1];
        _de1 <= de_wire[1];
      end
    endcase
  end
  // nu[0], de[0] for 除法器的input
  always @(*) begin
    nu[0] = _nu0;
    de[0] = _de0;
    nu[1] = _nu1;
    de[1] = _de1;
  end
  // 歸一化
  // nua[0], nub[0], dea[0], deb[0]
  always @(*) begin
    case (cnt)
      85, 109: begin
        nua[0] = mtxprod[0];
        nub[0] = {~_xmin[31], _xmin[30:0]};
        dea[0] = _xmax;
        deb[0] = {~_xmin[31], _xmin[30:0]};
      end
      86, 110: begin
        nua[0] = mtxprod[1];
        nub[0] = {~_xmin[31], _xmin[30:0]};
        dea[0] = _xmax;
        deb[0] = {~_xmin[31], _xmin[30:0]};
      end
      87, 111: begin
        nua[0] = mtxprod[2];
        nub[0] = {~_xmin[31], _xmin[30:0]};
        dea[0] = _xmax;
        deb[0] = {~_xmin[31], _xmin[30:0]};
      end
      88, 112: begin
        nua[0] = mtxprod[3];
        nub[0] = {~_xmin[31], _xmin[30:0]};
        dea[0] = _xmax;
        deb[0] = {~_xmin[31], _xmin[30:0]};
      end
      117: begin  // 來幫忙算最終output
        nua[0] = abs[0];  // |220-221|+|0-149|
        nub[0] = sum2[1];  // |128-0|+|0-0|
        dea[0] = 32'dx;
        deb[0] = 32'dx;
      end
      default: begin
        nua[0] = 32'dx;
        nub[0] = 32'dx;
        dea[0] = 32'dx;
        deb[0] = 32'dx;
      end
    endcase
  end
  always @(*) begin
    case (cnt)
      88, 112: begin
        nua[1] = _Opt[1] ? exppz : one; // 87, 111有死的exppz 但除法器0沒空
        nub[1] = _Opt[1] ? {~one[31], one[30:0]} : 0;
        dea[1] = exppz;
        deb[1] = one;
      end
      89, 113: begin
        nua[1] = _Opt[1] ? exppz : one;
        nub[1] = _Opt[1] ? {~one[31], one[30:0]} : 0;
        dea[1] = exppz;
        deb[1] = one;
      end
      90, 114: begin
        nua[1] = _Opt[1] ? exppz : one;
        nub[1] = _Opt[1] ? {~one[31], one[30:0]} : 0;
        dea[1] = exppz;
        deb[1] = one;
      end
      91, 115: begin
        nua[1] = _Opt[1] ? exppz : one;
        nub[1] = _Opt[1] ? {~one[31], one[30:0]} : 0;
        dea[1] = exppz;
        deb[1] = one;
      end
      default: begin
        nua[1] = 32'dx;
        nub[1] = 32'dx;
        dea[1] = 32'dx;
        deb[1] = 32'dx;
      end
    endcase
  end

  //nm[0:3]
  always @(posedge clk) begin
    if (cnt == 86 || cnt == 87 || cnt == 88 || cnt == 89) nm[cnt-86] <= q[0];
    else if (cnt == 110 || cnt == 111 || cnt == 112 || cnt == 113)
      nm[cnt-110] <= q[0];
  end
  reg [7:0] twoz_expbit[0:3];
  always @(*) begin
    for (i = 0; i < 4; i = i + 1) twoz_expbit[i] = nm[i][30:23] + 1;
  end
  // z[0:3]
  always @(*) begin
    case (cnt)
      87, 111:
      z = !_Opt[1] ? nm[0]: (nm[0]==0)? 0:{nm[0][31], twoz_expbit[0], nm[0][22:0]};
      88, 112:
      z = !_Opt[1] ? nm[1]: (nm[1]==0)? 0:{nm[1][31], twoz_expbit[1], nm[1][22:0]};
      89, 113:
      z = !_Opt[1] ? nm[2]: (nm[2]==0)? 0:{nm[2][31], twoz_expbit[2], nm[2][22:0]};
      90, 114:
      z = !_Opt[1] ? nm[3]: (nm[3]==0)? 0:{nm[3][31], twoz_expbit[3], nm[3][22:0]};
      default: z = 32'dx;
    endcase
  end
  // exppz
  always @(posedge clk) begin
    case (cnt)
      87, 88, 89, 90, 111, 112, 113, 114: begin
        exppz <= expz;
      end
    endcase
  end
  // vec1[0:3];
  always @(posedge clk) begin
    case (cnt)
      89: vec1[0] <= q[1];
      90: vec1[1] <= q[1];
      91: vec1[2] <= q[1];
      92: vec1[3] <= q[1];
    endcase
  end
  // vec2[0:3]
  always @(posedge clk) begin
    case (cnt)
      113: vec2[0] <= q[1];  // 圖二ac[0]
      114: vec2[1] <= q[1];  // 圖二ac[1]
      115: vec2[2] <= q[1];  // 圖二ac[2]
      116: vec2[3] <= q[1];  // 圖二ac[3]
    endcase
  end

  // abs[0:1]
  always @(posedge clk) begin
    case (cnt)
      114: begin
        abs[0] <= {1'b0, sum2[0][30:0]};  // |220-221|
      end
      115: begin
        abs[0] <= sum2[1];  // |220-221|+|0-149|
      end
      116: begin
        abs[1] <= {1'b0, sum2[0][30:0]};  // |128-0|
      end
    endcase
  end
  // ab[0][0:1] for distance
  always @(*) begin
    case (cnt)
      114: begin
        ab[0][0] = vec1[0];  // 220
        ab[0][1] = {~vec2[0][31], vec2[0][30:0]};  // -221
      end
      115: begin
        ab[0][0] = vec1[1];  // 0
        ab[0][1] = {~vec2[1][31], vec2[1][30:0]};  // -149
      end
      116: begin
        ab[0][0] = vec1[2];  // 128
        ab[0][1] = {~vec2[2][31], vec2[2][30:0]};  // -0
      end
      117: begin
        ab[0][0] = vec1[3];  // 0
        ab[0][1] = {~vec2[3][31], vec2[3][30:0]};  // -0
      end
      default: begin
        ab[0][0] = 32'dx;
        ab[0][1] = 32'dx;
      end
    endcase
  end
  // ab[1][0:1] for distance
  always @(*) begin
    case (cnt)
      115: begin
        ab[1][0] = abs[0];  // |220-221|
        ab[1][1] = {1'b0, sum2[0][30:0]};  // |0-149|
      end
      117: begin
        ab[1][0] = abs[1];  // |128-0|
        ab[1][1] = {1'b0, sum2[0][30:0]};  // |0-0|
      end
      default: begin
        ab[1][0] = 32'dx;
        ab[1][1] = 32'dx;
      end
    endcase
  end

  // out
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out <= 0;
    else if (cnt == 117) out <= nu_wire[0];
    else out <= 0;
  end
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (cnt == 117) out_valid <= 1;
    else out_valid <= 0;
  end































  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP1 (
    .a(pool[0][0]),
    .b(pool[0][1]),
    .zctr(0),
    .z0(),
    .z1(big[0][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP2 (
    .a(pool[1][0]),
    .b(pool[1][1]),
    .zctr(0),
    .z0(),
    .z1(big[1][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP3 (
    .a(big[0][0]),
    .b(big[1][0]),
    .zctr(0),
    .z0(),
    .z1(max[0][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP4 (
    .a(pool[0][2]),
    .b(pool[0][3]),
    .zctr(0),
    .z0(),
    .z1(big[0][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP5 (
    .a(pool[1][2]),
    .b(pool[1][3]),
    .zctr(0),
    .z0(),
    .z1(big[1][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP6 (
    .a(big[0][1]),
    .b(big[1][1]),
    .zctr(0),
    .z0(),
    .z1(max[0][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP7 (
    .a(pool[2][0]),
    .b(pool[2][1]),
    .zctr(0),
    .z0(),
    .z1(big[2][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP8 (
    .a(pool[3][0]),
    .b(pool[3][1]),
    .zctr(0),
    .z0(),
    .z1(big[3][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP9 (
    .a(big[2][0]),
    .b(big[3][0]),
    .zctr(0),
    .z0(),
    .z1(max[1][0])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP10 (
    .a(pool[2][2]),
    .b(pool[2][3]),
    .zctr(0),
    .z0(),
    .z1(big[2][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP11 (
    .a(pool[3][2]),
    .b(pool[3][3]),
    .zctr(0),
    .z0(),
    .z1(big[3][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP12 (
    .a(big[2][1]),
    .b(big[3][1]),
    .zctr(0),
    .z0(),
    .z1(max[1][1])
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP13 (
    .a(mtxprod[0]),
    .b(mtxprod[1]),
    .zctr(0),
    .z0(min01),
    .z1(max01)

  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP14 (
    .a(mtxprod[2]),
    .b(mtxprod[3]),
    .zctr(0),
    .z0(min23),
    .z1(max23)

  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP15 (
    .a(max01),
    .b(max23),
    .zctr(0),
    .z0(),
    .z1(xmax)
  );
  DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) CMP16 (
    .a(min01),
    .b(min23),
    .zctr(0),
    .z0(xmin),
    .z1()
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_0 (
    .a  (max[0][0]),
    .b  (_Weight[0][0]),
    .c  (max[0][1]),
    .d  (_Weight[1][0]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[0])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_1 (
    .a  (max[0][0]),
    .b  (_Weight[0][1]),
    .c  (max[0][1]),
    .d  (_Weight[1][1]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[1])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_2 (
    .a  (max[1][0]),
    .b  (_Weight[0][0]),
    .c  (max[1][1]),
    .d  (_Weight[1][0]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[2])
  );
  DW_fp_dp2 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)DP2_3 (
    .a  (max[1][0]),
    .b  (_Weight[0][1]),
    .c  (max[1][1]),
    .d  (_Weight[1][1]),
    .rnd(inst_rnd),
    .z  (mtxprod_wire[3])
  );
  genvar g;
  generate
    for (g = 0; g < 9; g = g + 1) begin : mult_generate
      DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) MULT (
        .a  (m[g][0]),
        .b  (m[g][1]),
        .rnd(inst_rnd),
        .z  (prod[g])
      );
    end
    for (g = 0; g < 5; g = g + 1) begin
      DW_fp_sum3 #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch_type)SUM3 (
        .a  (abc[g][0]),
        .b  (abc[g][1]),
        .c  (abc[g][2]),
        .rnd(inst_rnd),
        .z  (sum3[g])
      );
    end
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

    DW_fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch) U1 (
      .a(z),
      .z(expz)
    );

    // for 分子
    DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) NU0 (
      .a  (nua[0]),
      .b  (nub[0]),
      .rnd(inst_rnd),
      .z  (nu_wire[0])
    );
    // for 分母
    DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DE0 (
      .a  (dea[0]),
      .b  (deb[0]),
      .rnd(inst_rnd),
      .z  (de_wire[0])
    );
    // for 分子
    DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) NU1 (
      .a  (nua[1]),
      .b  (nub[1]),
      .rnd(inst_rnd),
      .z  (nu_wire[1])
    );
    // for 分母
    DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DE1 (
      .a  (dea[1]),
      .b  (deb[1]),
      .rnd(inst_rnd),
      .z  (de_wire[1])
    );

    for (g = 0; g < 2; g = g + 1) begin
      DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DISTANCE (
        .a  (ab[g][0]),
        .b  (ab[g][1]),
        .rnd(inst_rnd),
        .z  (sum2[g])
      );
    end
  endgenerate

endmodule
