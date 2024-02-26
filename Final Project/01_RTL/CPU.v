//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2021 Final Project: Customized ISA Processor 
//   Author              : Hsi-Hao Huang
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : CPU.v
//   Module Name : CPU.v
//   Release version : V1.0 (Release Date: 2021-May)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

module CPU (

  clk,
  rst_n,

  IO_stall,

  awid_m_inf,
  awaddr_m_inf,
  awsize_m_inf,
  awburst_m_inf,
  awlen_m_inf,
  awvalid_m_inf,
  awready_m_inf,

  wdata_m_inf,
  wlast_m_inf,
  wvalid_m_inf,
  wready_m_inf,

  bid_m_inf,
  bresp_m_inf,
  bvalid_m_inf,
  bready_m_inf,

  arid_m_inf,
  araddr_m_inf,
  arlen_m_inf,
  arsize_m_inf,
  arburst_m_inf,
  arvalid_m_inf,

  arready_m_inf,
  rid_m_inf,
  rdata_m_inf,
  rresp_m_inf,
  rlast_m_inf,
  rvalid_m_inf,
  rready_m_inf

);
  // Input port
  input wire clk, rst_n;
  // Output port
  output reg IO_stall;

  parameter ID_WIDTH = 4 , ADDR_WIDTH = 32, DATA_WIDTH = 16, DRAM_NUMBER=2, WRIT_NUMBER=1;

  // AXI Interface wire connecttion for pseudo DRAM read/write
  /* Hint:
  your AXI-4 interface could be designed as convertor in submodule(which used reg for output signal),
  therefore I declared output of AXI as wire in CPU
*/



  // axi write address channel 
  output wire [WRIT_NUMBER * ID_WIDTH-1:0] awid_m_inf;  // 0
  output wire [WRIT_NUMBER * ADDR_WIDTH-1:0] awaddr_m_inf;
  output wire [WRIT_NUMBER * 3 -1:0] awsize_m_inf;  // 3'd1 (2 bytes)
  output wire [WRIT_NUMBER * 2 -1:0] awburst_m_inf;  // 2'b01 (INCR)
  output wire [WRIT_NUMBER * 7 -1:0] awlen_m_inf;
  output wire [WRIT_NUMBER-1:0] awvalid_m_inf;
  input wire [WRIT_NUMBER-1:0] awready_m_inf;
  // axi write data channel 
  output wire [WRIT_NUMBER * DATA_WIDTH-1:0] wdata_m_inf;
  output wire [WRIT_NUMBER-1:0] wlast_m_inf;
  output wire [WRIT_NUMBER-1:0] wvalid_m_inf;
  input wire [WRIT_NUMBER-1:0] wready_m_inf;
  // axi write response channel
  input wire [WRIT_NUMBER * ID_WIDTH-1:0] bid_m_inf;
  input wire [WRIT_NUMBER * 2 -1:0] bresp_m_inf;  // TA use 2'b00 (OKAY)
  input wire [WRIT_NUMBER-1:0] bvalid_m_inf;
  output wire [WRIT_NUMBER-1:0] bready_m_inf;
  // -----------------------------
  // axi read address channel 
  output wire [DRAM_NUMBER * ID_WIDTH-1:0] arid_m_inf;  // 0
  output [DRAM_NUMBER * ADDR_WIDTH-1:0] araddr_m_inf;
  output wire [DRAM_NUMBER * 7 -1:0] arlen_m_inf;  // 7'd127
  output wire [DRAM_NUMBER * 3 -1:0] arsize_m_inf;  // 3'd1 (2 bytes)
  output wire [DRAM_NUMBER * 2 -1:0] arburst_m_inf;  // 2'b01 (INCR)
  output [DRAM_NUMBER-1:0] arvalid_m_inf;
  input wire [DRAM_NUMBER-1:0] arready_m_inf;
  // -----------------------------
  // axi read data channel 
  input wire [DRAM_NUMBER * ID_WIDTH-1:0] rid_m_inf;
  input wire [DRAM_NUMBER * DATA_WIDTH-1:0] rdata_m_inf;
  input wire [DRAM_NUMBER * 2 -1:0] rresp_m_inf;  // TA use 2'b00 (OKAY)
  input wire [DRAM_NUMBER-1:0] rlast_m_inf;
  input wire [DRAM_NUMBER-1:0] rvalid_m_inf;
  output [DRAM_NUMBER-1:0] rready_m_inf;
  // -----------------------------

  //
  //
  // 
  /* Register in each core:
  There are sixteen registers in your CPU. You should not change the name of those registers.
  TA will check the value in each register when your core is not busy.
  If you change the name of registers below, you must get the fail in this lab.
*/

  reg signed [15:0] core_r0, core_r1, core_r2, core_r3;
  reg signed [15:0] core_r4, core_r5, core_r6, core_r7;
  reg signed [15:0] core_r8, core_r9, core_r10, core_r11;
  reg signed [15:0] core_r12, core_r13, core_r14, core_r15;

  reg signed [11:0] PC;
  reg signed [15:0] rs, rt, rs_imm_x2;
  wire [31:0] prod;
  wire signed [4:0] imm;
  wire inst_arready, data_arready, inst_rvalid, data_rvalid, inst_rlast, data_rlast;
  wire awready, wready, bvalid;
  reg wready_delay1, wready_delay2;
  reg first_cycle, first_block_allocate, second_block_allocate;
  reg [3:0] data$_lower_block, inst$_lower_block;
  reg inst_arvalid, data_arvalid, awvalid;
  reg [11:0] inst_araddr, data_araddr, awaddr;
  reg awready_delay1, awready_delay2, wvalid, wlast;
  reg [6:0] awlen;
  reg inst_rready, data_rready;
  reg [7:0] inst_A, inst_A_inc, data_A, data_A_inc;
  reg [15:0]
    inst_DI, data_DI, inst_DO, inst_DO_reg, data_DO, data_DO_reg, data_DO_buf;
  wire [15:0] inst_rdata, data_rdata;
  reg [15:0] wdata;
  reg [15:0] inst_reg;
  reg [3:0] inst_cnt;
  reg [1:0] delay_cnt, delay_cnt_reg;
  reg delay_cnt_pulse;
  reg dirty, write_back, inst_mem_stall;
  reg [11:0] lowest_dirty_addr, highest_dirty_addr;
  reg lowest_dirty_addr_update, highest_dirty_addr_update;
  reg inst$_hit, data$_hit, data$_hit_reg, data$_hit_pulse;
  reg inst_last, inst_in_reg, inst_in_reg_delay, in_pulse, rsrt_in_reg;
  reg Add, Sub, SLT, Mult, Load, Store, BEQ, Jump, ASS, ASSBEQ, LS;
  reg inst_WEB, data_WEB;
  assign awid_m_inf = 0;
  assign arid_m_inf = 0;
  assign awsize_m_inf = 3'b001;
  assign arsize_m_inf[5:3] = 3'b001;
  assign arsize_m_inf[2:0] = 3'b001;
  assign awlen_m_inf = awlen;
  assign awburst_m_inf = 2'b01;
  assign arburst_m_inf[3:2] = 2'b01;
  assign arburst_m_inf[1:0] = 2'b01;
  assign arlen_m_inf[13:7] = 7'd127;
  assign arlen_m_inf[6:0] = 7'd127;
  assign arvalid_m_inf = {inst_arvalid, data_arvalid};
  assign araddr_m_inf = {20'd1, inst_araddr, 20'd1, data_araddr};
  assign awaddr_m_inf = {20'd1, awaddr};
  assign bready_m_inf = 1;
  assign rready_m_inf = {inst_rready, data_rready};
  assign {inst_arready, data_arready} = arready_m_inf;
  assign {inst_rvalid, data_rvalid} = rvalid_m_inf;
  assign {inst_rdata, data_rdata} = rdata_m_inf;
  assign {inst_rlast, data_rlast} = rlast_m_inf;
  assign awvalid_m_inf = awvalid;
  assign awready = awready_m_inf;
  assign wvalid_m_inf = wvalid;
  assign wready = wready_m_inf;
  assign wlast_m_inf = wlast;
  assign wdata_m_inf = wdata;
  assign bvalid = bvalid_m_inf;
  assign imm = inst_reg[4:0];

  reg data_WEB_reg, inst_WEB_reg;
  reg data_rvalid_reg, inst_rvalid_reg;
  reg [15:0] data_rdata_reg, inst_rdata_reg;
  reg data_rlast_reg, inst_rlast_reg;
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      data_WEB_reg <= 1;
      inst_WEB_reg <= 1;
      data_rvalid_reg <= 0;
      inst_rvalid_reg <= 0;
      data_rdata_reg <= 0;
      inst_rdata_reg <= 0;
      data_rlast_reg <= 0;
      inst_rlast_reg <= 0;
    end else begin
      data_WEB_reg <= data_WEB;
      inst_WEB_reg <= inst_WEB;
      data_rvalid_reg <= data_rvalid;
      inst_rvalid_reg <= inst_rvalid;
      data_rdata_reg <= data_rdata;
      inst_rdata_reg <= inst_rdata;
      data_rlast_reg <= data_rlast;
      inst_rlast_reg <= inst_rlast;
    end
  end
  always @(*) begin
    rs_imm_x2 = (rs + imm) <<< 1;
    Add = {inst_reg[15:13], inst_reg[0]} == 4'b0000;
    Sub = {inst_reg[15:13], inst_reg[0]} == 4'b0001;
    SLT = {inst_reg[15:13], inst_reg[0]} == 4'b0010;
    ASS = inst_reg[15:14] == 2'b00 && {inst_reg[13], inst_reg[0]} != 2'b11;
    ASSBEQ = {inst_reg[15], inst_reg[13]} == 2'b10  // BEQ
    || inst_reg[15:14] == 2'b00 && {inst_reg[13], inst_reg[0]} != 2'b11; // Add, Sub
    Mult = {inst_reg[15:13], inst_reg[0]} == 4'b0011;
    Load = inst_reg[15:13] == 3'b010;
    Store = inst_reg[15:13] == 3'b011;
    LS = inst_reg[15:14] == 2'b01;
    BEQ = {inst_reg[15], inst_reg[13]} == 2'b10;
    Jump = {inst_reg[15], inst_reg[13]} == 2'b11;
    data$_hit = delay_cnt!=0 && (rs_imm_x2[11:8] == data$_lower_block || rs_imm_x2[11:8] == data$_lower_block+1);
    inst$_hit = PC[11:8] == inst$_lower_block || PC[11:8] == inst$_lower_block+1;
    lowest_dirty_addr_update = rs_imm_x2[11:1] < lowest_dirty_addr[11:1];
    highest_dirty_addr_update = highest_dirty_addr < rs_imm_x2[11:0];
    inst_rready = 1;
    delay_cnt_pulse = delay_cnt != delay_cnt_reg;
    in_pulse = inst_in_reg != inst_in_reg_delay;
  end
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) delay_cnt_reg <= 0;
    else delay_cnt_reg <= delay_cnt;
  end

  always @(posedge clk, negedge rst_n) begin  // first_block_allocate
    if (!rst_n) first_block_allocate <= 1;
    else if (inst_rlast_reg) first_block_allocate <= 0;
  end


  always @(posedge clk, negedge rst_n) begin  // second_block_allocate
    if (!rst_n) second_block_allocate <= 0;
    else if (inst_rlast_reg) second_block_allocate <= first_block_allocate;
  end


  always @(posedge clk, negedge rst_n) begin  // rs
    if (!rst_n) rs <= 0;
    else if (inst_in_reg) begin
      case (inst_reg[12:9])
        4'd00: rs <= core_r0;
        4'd01: rs <= core_r1;
        4'd02: rs <= core_r2;
        4'd03: rs <= core_r3;
        4'd04: rs <= core_r4;
        4'd05: rs <= core_r5;
        4'd06: rs <= core_r6;
        4'd07: rs <= core_r7;
        4'd08: rs <= core_r8;
        4'd09: rs <= core_r9;
        4'd10: rs <= core_r10;
        4'd11: rs <= core_r11;
        4'd12: rs <= core_r12;
        4'd13: rs <= core_r13;
        4'd14: rs <= core_r14;
        4'd15: rs <= core_r15;
      endcase
    end
  end

  always @(posedge clk, negedge rst_n) begin  // rt
    if (!rst_n) rt <= 0;
    else if (inst_in_reg) begin
      case (inst_reg[8:5])
        4'd00: rt <= core_r0;
        4'd01: rt <= core_r1;
        4'd02: rt <= core_r2;
        4'd03: rt <= core_r3;
        4'd04: rt <= core_r4;
        4'd05: rt <= core_r5;
        4'd06: rt <= core_r6;
        4'd07: rt <= core_r7;
        4'd08: rt <= core_r8;
        4'd09: rt <= core_r9;
        4'd10: rt <= core_r10;
        4'd11: rt <= core_r11;
        4'd12: rt <= core_r12;
        4'd13: rt <= core_r13;
        4'd14: rt <= core_r14;
        4'd15: rt <= core_r15;
      endcase
    end
  end

  always @(posedge clk, negedge rst_n) begin  // core_r
    if (!rst_n) begin
      core_r0  <= 0;
      core_r1  <= 0;
      core_r2  <= 0;
      core_r3  <= 0;
      core_r4  <= 0;
      core_r5  <= 0;
      core_r6  <= 0;
      core_r7  <= 0;
      core_r8  <= 0;
      core_r9  <= 0;
      core_r10 <= 0;
      core_r11 <= 0;
      core_r12 <= 0;
      core_r13 <= 0;
      core_r14 <= 0;
      core_r15 <= 0;
    end else if (inst_in_reg && delay_cnt_pulse) begin
      if (delay_cnt == 1) begin
        if (Add) begin
          core_r0  <= inst_reg[4:1] == 0 ? rs + rt : core_r0;
          core_r1  <= inst_reg[4:1] == 1 ? rs + rt : core_r1;
          core_r2  <= inst_reg[4:1] == 2 ? rs + rt : core_r2;
          core_r3  <= inst_reg[4:1] == 3 ? rs + rt : core_r3;
          core_r4  <= inst_reg[4:1] == 4 ? rs + rt : core_r4;
          core_r5  <= inst_reg[4:1] == 5 ? rs + rt : core_r5;
          core_r6  <= inst_reg[4:1] == 6 ? rs + rt : core_r6;
          core_r7  <= inst_reg[4:1] == 7 ? rs + rt : core_r7;
          core_r8  <= inst_reg[4:1] == 8 ? rs + rt : core_r8;
          core_r9  <= inst_reg[4:1] == 9 ? rs + rt : core_r9;
          core_r10 <= inst_reg[4:1] == 10 ? rs + rt : core_r10;
          core_r11 <= inst_reg[4:1] == 11 ? rs + rt : core_r11;
          core_r12 <= inst_reg[4:1] == 12 ? rs + rt : core_r12;
          core_r13 <= inst_reg[4:1] == 13 ? rs + rt : core_r13;
          core_r14 <= inst_reg[4:1] == 14 ? rs + rt : core_r14;
          core_r15 <= inst_reg[4:1] == 15 ? rs + rt : core_r15;
        end else if (Sub) begin
          core_r0  <= inst_reg[4:1] == 0 ? rs - rt : core_r0;
          core_r1  <= inst_reg[4:1] == 1 ? rs - rt : core_r1;
          core_r2  <= inst_reg[4:1] == 2 ? rs - rt : core_r2;
          core_r3  <= inst_reg[4:1] == 3 ? rs - rt : core_r3;
          core_r4  <= inst_reg[4:1] == 4 ? rs - rt : core_r4;
          core_r5  <= inst_reg[4:1] == 5 ? rs - rt : core_r5;
          core_r6  <= inst_reg[4:1] == 6 ? rs - rt : core_r6;
          core_r7  <= inst_reg[4:1] == 7 ? rs - rt : core_r7;
          core_r8  <= inst_reg[4:1] == 8 ? rs - rt : core_r8;
          core_r9  <= inst_reg[4:1] == 9 ? rs - rt : core_r9;
          core_r10 <= inst_reg[4:1] == 10 ? rs - rt : core_r10;
          core_r11 <= inst_reg[4:1] == 11 ? rs - rt : core_r11;
          core_r12 <= inst_reg[4:1] == 12 ? rs - rt : core_r12;
          core_r13 <= inst_reg[4:1] == 13 ? rs - rt : core_r13;
          core_r14 <= inst_reg[4:1] == 14 ? rs - rt : core_r14;
          core_r15 <= inst_reg[4:1] == 15 ? rs - rt : core_r15;
        end else if (SLT) begin
          core_r0  <= inst_reg[4:1] == 0 ? rs < rt : core_r0;
          core_r1  <= inst_reg[4:1] == 1 ? rs < rt : core_r1;
          core_r2  <= inst_reg[4:1] == 2 ? rs < rt : core_r2;
          core_r3  <= inst_reg[4:1] == 3 ? rs < rt : core_r3;
          core_r4  <= inst_reg[4:1] == 4 ? rs < rt : core_r4;
          core_r5  <= inst_reg[4:1] == 5 ? rs < rt : core_r5;
          core_r6  <= inst_reg[4:1] == 6 ? rs < rt : core_r6;
          core_r7  <= inst_reg[4:1] == 7 ? rs < rt : core_r7;
          core_r8  <= inst_reg[4:1] == 8 ? rs < rt : core_r8;
          core_r9  <= inst_reg[4:1] == 9 ? rs < rt : core_r9;
          core_r10 <= inst_reg[4:1] == 10 ? rs < rt : core_r10;
          core_r11 <= inst_reg[4:1] == 11 ? rs < rt : core_r11;
          core_r12 <= inst_reg[4:1] == 12 ? rs < rt : core_r12;
          core_r13 <= inst_reg[4:1] == 13 ? rs < rt : core_r13;
          core_r14 <= inst_reg[4:1] == 14 ? rs < rt : core_r14;
          core_r15 <= inst_reg[4:1] == 15 ? rs < rt : core_r15;
        end
      end else if (delay_cnt == 2 && inst_reg[13]) begin
        core_r0  <= inst_reg[4:1] == 0 ? prod : core_r0;
        core_r1  <= inst_reg[4:1] == 1 ? prod : core_r1;
        core_r2  <= inst_reg[4:1] == 2 ? prod : core_r2;
        core_r3  <= inst_reg[4:1] == 3 ? prod : core_r3;
        core_r4  <= inst_reg[4:1] == 4 ? prod : core_r4;
        core_r5  <= inst_reg[4:1] == 5 ? prod : core_r5;
        core_r6  <= inst_reg[4:1] == 6 ? prod : core_r6;
        core_r7  <= inst_reg[4:1] == 7 ? prod : core_r7;
        core_r8  <= inst_reg[4:1] == 8 ? prod : core_r8;
        core_r9  <= inst_reg[4:1] == 9 ? prod : core_r9;
        core_r10 <= inst_reg[4:1] == 10 ? prod : core_r10;
        core_r11 <= inst_reg[4:1] == 11 ? prod : core_r11;
        core_r12 <= inst_reg[4:1] == 12 ? prod : core_r12;
        core_r13 <= inst_reg[4:1] == 13 ? prod : core_r13;
        core_r14 <= inst_reg[4:1] == 14 ? prod : core_r14;
        core_r15 <= inst_reg[4:1] == 15 ? prod : core_r15;
      end else if (delay_cnt == 3) begin
        core_r0  <= inst_reg[8:5] == 0 ? data_DO_reg : core_r0;
        core_r1  <= inst_reg[8:5] == 1 ? data_DO_reg : core_r1;
        core_r2  <= inst_reg[8:5] == 2 ? data_DO_reg : core_r2;
        core_r3  <= inst_reg[8:5] == 3 ? data_DO_reg : core_r3;
        core_r4  <= inst_reg[8:5] == 4 ? data_DO_reg : core_r4;
        core_r5  <= inst_reg[8:5] == 5 ? data_DO_reg : core_r5;
        core_r6  <= inst_reg[8:5] == 6 ? data_DO_reg : core_r6;
        core_r7  <= inst_reg[8:5] == 7 ? data_DO_reg : core_r7;
        core_r8  <= inst_reg[8:5] == 8 ? data_DO_reg : core_r8;
        core_r9  <= inst_reg[8:5] == 9 ? data_DO_reg : core_r9;
        core_r10 <= inst_reg[8:5] == 10 ? data_DO_reg : core_r10;
        core_r11 <= inst_reg[8:5] == 11 ? data_DO_reg : core_r11;
        core_r12 <= inst_reg[8:5] == 12 ? data_DO_reg : core_r12;
        core_r13 <= inst_reg[8:5] == 13 ? data_DO_reg : core_r13;
        core_r14 <= inst_reg[8:5] == 14 ? data_DO_reg : core_r14;
        core_r15 <= inst_reg[8:5] == 15 ? data_DO_reg : core_r15;
      end
    end
  end

  always @(*) begin  // inst_last
    inst_last = inst_in_reg && ((!dirty || {inst_cnt[3], inst_cnt[0]} != 3) &&
    (Jump || 
    delay_cnt[0] && (ASSBEQ || Store && data$_hit) || 
    delay_cnt[1] && Mult ||
    delay_cnt==3) ||
    bvalid);
  end


  always @(*) begin  // inst_mem_stall
    if (first_block_allocate || second_block_allocate ||
    !inst_in_reg && !inst$_hit)
      inst_mem_stall = 1;
    else inst_mem_stall = 0;
  end


  always @(posedge clk, negedge rst_n) begin  // delay_cnt
    if (!rst_n) delay_cnt <= 0;
    else if (inst_last) delay_cnt <= 0;
    else if (inst$_hit) begin
      if (!inst_in_reg) delay_cnt <= delay_cnt == 2 ? 0 : delay_cnt + 1;
      else begin
        if(!(first_block_allocate || second_block_allocate ||
          ({inst_cnt[3],inst_cnt[0]}==3) && dirty &&
          (Jump ||
          delay_cnt[0] && (ASSBEQ || Store && data$_hit) ||
          delay_cnt[1] && Mult ||
          delay_cnt==3) || (delay_cnt[0] && LS && !data$_hit)))
          delay_cnt <= delay_cnt + 1;
      end
    end
  end

  always @(posedge clk, negedge rst_n) begin  // inst_reg
    if (!rst_n) inst_reg <= 16'h4000;
    else if (!inst_in_reg && delay_cnt[1]) inst_reg <= inst_DO_reg;
  end

  always @(posedge clk, negedge rst_n) begin  // inst_in_reg
    if (!rst_n) inst_in_reg <= 0;
    else if (!inst_in_reg && delay_cnt[1]) inst_in_reg <= 1;
    else if (inst_last) inst_in_reg <= 0;
  end

  always @(posedge clk, negedge rst_n) begin  // inst_in_reg_delay
    if (!rst_n) inst_in_reg_delay <= 0;
    else inst_in_reg_delay <= inst_in_reg;
  end



  always @(posedge clk, negedge rst_n) begin  // PC
    if (!rst_n) PC <= 0;
    else if (dirty && {inst_cnt[3], inst_cnt[0]} == 3) begin
      if (bvalid) begin
        if (Jump) PC <= {inst_reg[12:1], 1'b0};
        else if (BEQ && rs == rt) PC <= PC + (1 + imm <<< 1);
        else PC <= PC + 2;
      end
    end else if (inst_in_reg) begin
      case (delay_cnt)
        0: if (Jump) PC <= {inst_reg[12:1], 1'b0};
        1: begin
          if (ASS || Store && data$_hit) PC <= PC + 2;
          else if (BEQ) PC <= rs == rt ? PC + (1 + imm <<< 1) : PC + 2;
        end
        2: if (Mult) PC <= PC + 2;
        3: PC <= PC + 2;
      endcase
    end
  end

  // imm is a 5-bit signed number

  // R-type   
  // rd = rs + rt                       000-rs-rt-rd-0 (Add)
  // rd = rs – rt                       000-rs-rt-rd-1 (Sub)
  // if(rs<rt) rd=1 else rd=0           001-rs-rt-rd-0 (Set less than)
  // rd = rs * rt                       001-rs-rt-rd-1 (Mult)

  // I-type
  // rt = DRAM[(rs+imm)×2+offset]       010-rs-rt-iiiii (Load)
  // DRAM[sign(rs+imm)×2+offset] = rt   011-rs-rt-iiiii (Store)
  // pc=(rs==rt)? pc+(1+imm)x2:pc+2     100-rs-rt-iiiii (Branch on equal)

  // J-type
  // pc = address                       101-address (Jump)


  always @(posedge clk, negedge rst_n) begin  // data$_lower_block
    if (!rst_n) data$_lower_block <= 2;
    else if (data_rlast_reg) begin
      if (second_block_allocate) data$_lower_block <= 0;
      else if (rs_imm_x2[11:8] == data$_lower_block + 2)
        data$_lower_block <= data$_lower_block + 1;
      else if (!first_block_allocate) data$_lower_block <= rs_imm_x2[11:8];
    end
  end

  always @(posedge clk, negedge rst_n) begin  // inst$_lower_block
    if (!rst_n) inst$_lower_block <= 2;
    else if (inst_rlast_reg) begin
      if (second_block_allocate) inst$_lower_block <= 0;
      else if (PC[11:8] == inst$_lower_block + 2)
        inst$_lower_block <= inst$_lower_block + 1;
      else if (!first_block_allocate) inst$_lower_block <= PC[11:8];
    end
  end



  always @(posedge clk, negedge rst_n) begin  // data_arvalid
    if (!rst_n) data_arvalid <= 1;
    else if (data_arready) data_arvalid <= 0;
    else if (first_block_allocate && data_rlast_reg ||
    inst_in_reg && delay_cnt[0] && LS && !data$_hit && delay_cnt_pulse)
      data_arvalid <= 1;
  end

  always @(posedge clk, negedge rst_n) begin  // data_araddr
    if (!rst_n) data_araddr <= 0;
    else if (first_block_allocate) data_araddr <= 12'b0001_0000_0000;
    else data_araddr <= {rs_imm_x2[11:8], 8'b0};
  end

  always @(posedge clk, negedge rst_n) begin  // data_rready
    if (!rst_n) data_rready <= 0;
    else if (data_arready) data_rready <= 1;
    else if (data_rlast_reg) data_rready <= 0;
  end

  integer debug_inst_cnt;
  always @(posedge clk, negedge rst_n) begin  // debug_inst_cnt
    if (!rst_n) debug_inst_cnt <= 0;
    else if (debug_inst_cnt % 10 == 9 && dirty) begin
      if (bvalid) debug_inst_cnt <= debug_inst_cnt + 1;
    end else if (inst_in_reg) begin
      if(Jump || 
        delay_cnt[0] && (ASSBEQ || Store && data$_hit) || 
        delay_cnt[1] && Mult ||
        delay_cnt==3)
        debug_inst_cnt <= debug_inst_cnt + 1;
    end
  end

  always @(posedge clk, negedge rst_n) begin  // awvalid
    if (!rst_n) awvalid <= 0;
    else if (awready) awvalid <= 0;
    else if (dirty && {inst_cnt[3], inst_cnt[0]} == 3 &&  // write back
      inst_in_reg && delay_cnt_pulse && (Jump || delay_cnt[0] && (ASSBEQ || Store && data$_hit) || delay_cnt[1] && Mult ||
    delay_cnt==3))
      awvalid <= 1;
  end

  always @(*) begin  // awaddr
    awaddr = lowest_dirty_addr;
  end

  always @(posedge clk, negedge rst_n) begin  // awlen
    if (!rst_n) awlen <= 0;
    else awlen <= highest_dirty_addr[7:1] - lowest_dirty_addr[7:1];
  end


  always @(posedge clk, negedge rst_n) begin  // wvalid
    if (!rst_n) wvalid <= 0;
    else if (awready) wvalid <= 1;
    else if (wlast && wready) wvalid <= 0;
  end
  reg [15:0] data_DO_buf1, data_DO_buf2;

  always @(posedge clk, negedge rst_n) begin  // data_DO_buf1
    if (!rst_n) data_DO_buf1 <= 0;
    else if (awready_delay1) data_DO_buf1 <= data_DO_reg;
  end
  always @(posedge clk, negedge rst_n) begin  // data_DO_buf2
    if (!rst_n) data_DO_buf2 <= 0;
    else if (awready_delay2) data_DO_buf2 <= data_DO_reg;
  end

  always @(posedge clk, negedge rst_n) begin  // data_DO_reg
    if (!rst_n) data_DO_reg <= 0;
    else data_DO_reg <= data_DO;
  end

  always @(posedge clk, negedge rst_n) begin  // inst_DO_reg
    if (!rst_n) inst_DO_reg <= 0;
    else inst_DO_reg <= inst_DO;
  end

  always @(posedge clk, negedge rst_n) begin  // wready_delay
    if (!rst_n) begin
      wready_delay1 <= 0;
      wready_delay2 <= 0;
    end else begin
      wready_delay1 <= wready;
      wready_delay2 <= wready_delay1;
    end
  end

  always @(*) begin
    if (!wready_delay1) wdata = data_DO_buf1;
    else if (!wready_delay2) wdata = data_DO_buf2;
    else wdata = data_DO_reg;
  end

  always @(posedge clk, negedge rst_n) begin  // wlast
    if (!rst_n) wlast <= 0;
    else if (awready_delay1 && awlen == 0 || wvalid && data_A_inc == (highest_dirty_addr[8:1] + 1))
      wlast <= 1;
    else if (wready) wlast <= 0;
  end

  always @(posedge clk, negedge rst_n) begin  // inst_arvalid
    if (!rst_n) inst_arvalid <= 1;
    else if (inst_arready) inst_arvalid <= 0;
    else if (first_block_allocate || second_block_allocate) begin
      if (first_block_allocate && inst_rlast_reg) inst_arvalid <= 1;
    end else if (!inst_in_reg && !inst$_hit && in_pulse) inst_arvalid <= 1;
  end

  always @(posedge clk, negedge rst_n) begin  // inst_araddr
    if (!rst_n) inst_araddr <= 0;
    else if (first_block_allocate || second_block_allocate) begin
      if (inst_rlast_reg) inst_araddr <= 12'b0001_0000_0000;
    end else if (!inst_in_reg && !inst$_hit) inst_araddr <= {PC[11:8], 8'b0};
  end

  always @(posedge clk, negedge rst_n) begin  // awready_delay
    if (!rst_n) begin
      awready_delay1 <= 0;
      awready_delay2 <= 0;
    end else begin
      awready_delay1 <= awready;
      awready_delay2 <= awready_delay1;
    end
  end

  always @(posedge clk, negedge rst_n) begin  // data_A_inc
    if (!rst_n) data_A_inc <= 0;
    else if (data_rvalid_reg || awready || wready) data_A_inc <= data_A_inc + 1;
    else if (awvalid) data_A_inc <= lowest_dirty_addr[8:1];  // write back
    else if (inst_in_reg && delay_cnt_pulse)  // allocate
      data_A_inc <= {rs_imm_x2[8], 7'b0};
  end

  always @* data$_hit_pulse = data$_hit != data$_hit_reg;
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) data$_hit_reg <= 0;
    else data$_hit_reg <= data$_hit;
  end

  always @(*) begin  // data_WEB
    if (!(inst_in_reg && delay_cnt[0] && Store && data$_hit_pulse)) begin
      data_WEB = !data_rvalid_reg;
    end else data_WEB = 0;
  end
  always @(*) begin  // data_A
    if (awvalid || wvalid || data_rready) data_A = data_A_inc;
    else data_A = rs_imm_x2[8:1];
  end
  always @(*) begin  // data_DI
    if (data_rvalid_reg) data_DI = data_rdata_reg;
    else data_DI = rt;
  end

  always @(*) begin  // inst_WEB
    inst_WEB = !inst_rvalid_reg;
  end
  always @(*) begin  //inst_DI
    inst_DI = inst_rdata_reg;
  end
  always @(*) begin  // inst_A
    if (!inst$_hit) inst_A = inst_A_inc;
    else inst_A = PC[8:1];
  end

  always @(posedge clk, negedge rst_n) begin  // inst_A_inc
    if (!rst_n) inst_A_inc <= 0;
    else if (inst_rvalid_reg) inst_A_inc <= inst_A_inc + 1;
    else if (!first_block_allocate && !second_block_allocate)
      inst_A_inc <= {PC[8], 7'd0};
  end
  // lowest_dirty_addr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) lowest_dirty_addr <= 12'hFFE;
    else if (bvalid) lowest_dirty_addr <= 12'hFFE;
    else if (inst_in_reg && delay_cnt[0] && Store && lowest_dirty_addr_update) begin
      lowest_dirty_addr <= rs_imm_x2[11:0];
    end
  end

  // highest_dirty_addr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) highest_dirty_addr <= 12'h000;
    else if (bvalid) highest_dirty_addr <= 12'h000;
    else if (inst_in_reg && delay_cnt[0] && Store && highest_dirty_addr_update)
      highest_dirty_addr <= rs_imm_x2[11:0];
  end
  // dirty
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) dirty <= 0;
    else if (bvalid) dirty <= 0;
    else if (inst_in_reg && Store) dirty <= 1;
  end

  // inst_cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) inst_cnt <= 9;
    else if (({inst_cnt[3], inst_cnt[0]} == 2'b11) && dirty) begin
      if (bvalid) inst_cnt <= 0;
    end else if (inst_in_reg) begin
      if(Jump || 
      delay_cnt[0] && (ASSBEQ || Store && data$_hit) || 
      delay_cnt[1] && Mult ||
      delay_cnt==3)
        inst_cnt <= ({inst_cnt[3], inst_cnt[0]} == 2'b11) ? 0 : inst_cnt + 1;
    end
  end

  // IO_stall
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) IO_stall <= 1;
    else if (({inst_cnt[3], inst_cnt[0]} != 3 || !dirty) &&
    inst_in_reg && (Jump || 
    delay_cnt[0] && (ASSBEQ || Store && data$_hit) || 
    delay_cnt[1] && Mult ||
    delay_cnt==3) || 
    bvalid)
      IO_stall <= 0;
    else IO_stall <= 1;
  end






























  SUMA180_256X16X1BM1 INST_CACHE ( // 0000_0000 ~ 0111_1111, 1000_0000 ~ 1111_1111
    .A0  (inst_A[0]),
    .A1  (inst_A[1]),
    .A2  (inst_A[2]),
    .A3  (inst_A[3]),
    .A4  (inst_A[4]),
    .A5  (inst_A[5]),
    .A6  (inst_A[6]),
    .A7  (inst_A[7]),
    .DI0 (inst_DI[0]),
    .DI1 (inst_DI[1]),
    .DI2 (inst_DI[2]),
    .DI3 (inst_DI[3]),
    .DI4 (inst_DI[4]),
    .DI5 (inst_DI[5]),
    .DI6 (inst_DI[6]),
    .DI7 (inst_DI[7]),
    .DI8 (inst_DI[8]),
    .DI9 (inst_DI[9]),
    .DI10(inst_DI[10]),
    .DI11(inst_DI[11]),
    .DI12(inst_DI[12]),
    .DI13(inst_DI[13]),
    .DI14(inst_DI[14]),
    .DI15(inst_DI[15]),
    .DO0 (inst_DO[0]),
    .DO1 (inst_DO[1]),
    .DO2 (inst_DO[2]),
    .DO3 (inst_DO[3]),
    .DO4 (inst_DO[4]),
    .DO5 (inst_DO[5]),
    .DO6 (inst_DO[6]),
    .DO7 (inst_DO[7]),
    .DO8 (inst_DO[8]),
    .DO9 (inst_DO[9]),
    .DO10(inst_DO[10]),
    .DO11(inst_DO[11]),
    .DO12(inst_DO[12]),
    .DO13(inst_DO[13]),
    .DO14(inst_DO[14]),
    .DO15(inst_DO[15]),
    .CK  (clk),
    .WEB (inst_WEB),
    .OE  (1'b1),
    .CS  (1'b1)
  );
  SUMA180_256X16X1BM1 DATA_CACHE ( // 0000_0000 ~ 0111_1111, 1000_0000 ~ 1111_1111
    .A0  (data_A[0]),
    .A1  (data_A[1]),
    .A2  (data_A[2]),
    .A3  (data_A[3]),
    .A4  (data_A[4]),
    .A5  (data_A[5]),
    .A6  (data_A[6]),
    .A7  (data_A[7]),
    .DI0 (data_DI[0]),
    .DI1 (data_DI[1]),
    .DI2 (data_DI[2]),
    .DI3 (data_DI[3]),
    .DI4 (data_DI[4]),
    .DI5 (data_DI[5]),
    .DI6 (data_DI[6]),
    .DI7 (data_DI[7]),
    .DI8 (data_DI[8]),
    .DI9 (data_DI[9]),
    .DI10(data_DI[10]),
    .DI11(data_DI[11]),
    .DI12(data_DI[12]),
    .DI13(data_DI[13]),
    .DI14(data_DI[14]),
    .DI15(data_DI[15]),
    .DO0 (data_DO[0]),
    .DO1 (data_DO[1]),
    .DO2 (data_DO[2]),
    .DO3 (data_DO[3]),
    .DO4 (data_DO[4]),
    .DO5 (data_DO[5]),
    .DO6 (data_DO[6]),
    .DO7 (data_DO[7]),
    .DO8 (data_DO[8]),
    .DO9 (data_DO[9]),
    .DO10(data_DO[10]),
    .DO11(data_DO[11]),
    .DO12(data_DO[12]),
    .DO13(data_DO[13]),
    .DO14(data_DO[14]),
    .DO15(data_DO[15]),
    .CK  (clk),
    .WEB (data_WEB),
    .OE  (1'b1),
    .CS  (1'b1)
  );

  DW02_mult_2_stage_inst MULT (  // 1 cycle latency
    .inst_A(rs),
    .inst_B(rt),
    .inst_TC(1'b1),
    .inst_CLK(clk),
    .PRODUCT_inst(prod)
  );
endmodule

module DW02_mult_2_stage_inst (
  inst_A,
  inst_B,
  inst_TC,
  inst_CLK,
  PRODUCT_inst
);
  parameter Width = 16;
  input [Width-1 : 0] inst_A;
  input [Width-1 : 0] inst_B;
  input inst_TC;
  input inst_CLK;
  output [Width+Width-1 : 0] PRODUCT_inst;
  // Instance of DW02_mult_6_stage
  DW02_mult_2_stage #(Width, Width) U1 (
    .A(inst_A),
    .B(inst_B),
    .TC(inst_TC),
    .CLK(inst_CLK),
    .PRODUCT(PRODUCT_inst)
  );
endmodule






