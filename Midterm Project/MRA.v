module MRA #(
  parameter ID_WIDTH   = 4,
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 128
) (
  // << CHIP io port with system >>
  input             clk,
  input             rst_n,
  input             in_valid,
  input      [ 4:0] frame_id,
  input      [ 3:0] net_id,
  input      [ 5:0] loc_x,
  input      [ 5:0] loc_y,
  output reg [13:0] cost,
  output reg        busy,

  // AXI Interface wire connecttion for pseudo DRAM read/write
  /* Hint:
       Your AXI-4 interface could be designed as a bridge in submodule,
	   therefore I declared output of AXI as wire.  
	   Ex: AXI4_interface AXI4_INF(...);
*/
  // ------------------------
  // <<<<< AXI READ >>>>>
  // ------------------------
  // (1)	axi read address channel 
  output wire [  ID_WIDTH-1:0] arid_m_inf,     // We use 0
  output wire [           1:0] arburst_m_inf,  // We use INCR(2'b01)
  output wire [           2:0] arsize_m_inf,   // we use 3'b100(16B)
  output wire [           7:0] arlen_m_inf,    // 127
  output wire                  arvalid_m_inf,
  input  wire                  arready_m_inf,
  output wire [ADDR_WIDTH-1:0] araddr_m_inf,
  // ------------------------
  // (2)	axi read data channel 
  input  wire [  ID_WIDTH-1:0] rid_m_inf,
  input  wire                  rvalid_m_inf,
  output wire                  rready_m_inf,
  input  wire [DATA_WIDTH-1:0] rdata_m_inf,
  input  wire                  rlast_m_inf,
  input  wire [           1:0] rresp_m_inf,    // TA use OKAY(2'b00)
  // ------------------------
  // <<<<< AXI WRITE >>>>>
  // ------------------------
  // (1) 	axi write address channel 
  output wire [  ID_WIDTH-1:0] awid_m_inf,     // We use 0
  output wire [           1:0] awburst_m_inf,
  output wire [           2:0] awsize_m_inf,   // we use 3'b100(16B)
  output wire [           7:0] awlen_m_inf,    // 127
  output wire                  awvalid_m_inf,
  input  wire                  awready_m_inf,
  output wire [ADDR_WIDTH-1:0] awaddr_m_inf,
  // -------------------------
  // (2)	axi write data channel 
  output wire                  wvalid_m_inf,
  input  wire                  wready_m_inf,
  output wire [DATA_WIDTH-1:0] wdata_m_inf,
  output wire                  wlast_m_inf,
  // -------------------------
  // (3)	axi write response channel 
  input  wire [  ID_WIDTH-1:0] bid_m_inf,      // TA use OKAY(2'b00)
  input  wire                  bvalid_m_inf,
  output wire                  bready_m_inf,
  input  wire [           1:0] bresp_m_inf     // TA use OKAY(2'b00)
);
  wire arready, wready, rvalid, rlast, awready, bvalid;
  reg arvalid, awvalid, rready, wvalid, wlast, bready;
  reg [ADDR_WIDTH-1:0] araddr, awaddr;
  wire [DATA_WIDTH-1:0] rdata;
  reg [DATA_WIDTH-1:0] wdata;
  //-------------------------------------
  assign arid_m_inf    = 0;  // No.0 process
  assign awid_m_inf    = 0;  // No.0 process
  assign arburst_m_inf = 1;  // INCR
  assign awburst_m_inf = 1;  // INCR
  assign arsize_m_inf  = 3'd4;  // 2^4 bytes = 16 bytes
  assign awsize_m_inf  = 3'd4;  // 2^4 bytes = 16 bytes
  assign arlen_m_inf   = 8'd127;  // 128 transfer per transaction
  assign awlen_m_inf   = 8'd127;  // 128 transfer per transaction
  assign bready_m_inf = bready;
  //--------------------------------------
  assign arvalid_m_inf = arvalid;
  assign arready = arready_m_inf;
  assign araddr_m_inf = araddr;
  //---------------------------------------
  assign rvalid = rvalid_m_inf;
  assign rready_m_inf  = rready;
  assign rdata = rdata_m_inf;
  assign rlast = rlast_m_inf;
  //------------------------------------
  assign awvalid_m_inf = awvalid;
  assign awready = awready_m_inf;
  assign awaddr_m_inf = awaddr;
  //------------------------------------
  assign wvalid_m_inf  = wvalid;
  assign wready  = wready_m_inf;
  assign wdata_m_inf  = wdata;
  assign wlast_m_inf  = wlast;
  //------------------------------------
  assign bvalid  = bvalid_m_inf;

  localparam IDLE = 0, EAT = 1, FILL = 2, RETRACE = 3;
  localparam source = 0, sink = 1;
  localparam LOCATION = 1'b0, WEIGHT = 1'b1;

  integer i, j;
  reg WE_L, WE_W;
  reg [1:0] state;
  reg [3:0] tgt_No;
  reg miss_map, filling, retracing;
  reg [4:0] _frame_id;
  reg [3:0] _net_id[0:14];
  reg [5:0]
    src_x[0:15],
    src_y[0:15],
    sink_x[0:15],
    sink_y[0:15],
    cur_x,
    cur_y,
    mux_y,
    mux_x;
  wire [5:0] cur_y_p_1 = cur_y + 6'd1, cur_y_m_1 = cur_y - 6'd1;
  wire [5:0] cur_x_p_1 = cur_x + 6'd1, cur_x_m_1 = cur_x - 6'd1;
  reg [4:0] cnt;
  reg [6:0] A_L_reg, A_L, A_W_reg, A_W;
  reg [127:0] DI_L, DI_W, DO_L, DO_W;
  reg [1:0] map[0:63][0:63];
  reg [1:0] Akers_cnt;
  reg got_weight;
  reg zero[0:63][0:63], seq_match[0:63][0:63], filling_value[0:63][0:63];
  reg [3:0] tgt_num;
  reg filled_beside[1:62][1:62];
  reg down_match, up_match, left_match, right_match;
  wire [1:0] seq[0:3];
  assign seq[0] = 2;
  assign seq[1] = 2;
  assign seq[2] = 3;
  assign seq[3] = 3;
  wire reading_location = miss_map == LOCATION && (rready & rvalid);
  wire reading_weight = miss_map == WEIGHT && (rready & rvalid);
  wire src_retraced = {cur_y, cur_x} == {src_y[tgt_No], src_x[tgt_No]};
  // One Location map called a Frame(range in No. 0 ~ No. 31), with a 64x64 4-bit net_id array(2048bytes, 256bits/row), 0 represent empty region, margin would be outermost 2 rows and 2 columns
  // Location map include several routing Target, # of targets would range in 1~15
  // Each Target owns its NET_ID, NET_ID would range from 1~15
  // One Target consisted of 2 Macro, one is Source, the other is Sink
  // Macro height and width: 2 ~ 6 for target # < 11, 2 ~ 4 for 11 ~ 15 (too many macro so they are smaller)
  // Macro has one Terminal, which must be located at the outermost region of the Macro
  // Location of Terminal would be send by input loc_x and loc_y, first is Source, followed by Sink
  // Location map record all Macro location, identified by a 4-bit value NET_ID, while 0 represent empty region
  // Target is routed means only one path is highlighted with NET_ID from Source to Sink in Location map
  // Length means path grid number from Source to Sink exclusive itself when Target is routed
  // Length of each Target is limited within 1000 units, i.e. no case over 1000 units
  // Weight means path weighted sum from Source to Sink exclusive itself when Target is routed
  // Location map routing success means all Target is routed in Location map (not unique solution)
  // Location map must be routing success with given approach
  // Cost of routing result means the accumulation Weight when Location map routing success

  //************ DRAM *****************
  // one frame = 2048 byte(0x800 bytes), each address store 1 byte, so frame No.0 = 0x0001_0000 to 0x0001_07FF, frame No.1 = 0x0001_0800 to 0x0001_0FFF, ...
  // Every frame is in raster scan order in DRAM, each byte in DRAM represent 2 position value, where [3:0] means 1st element, and [7:4] means 2nd element.
  // 64 x 64, 4-bit Weight Map are also in raster scan order in DRAM. Weight No.0 = 0x0002_0000 to 0x0002_07FF, No.1 is = 0x0002_0800 to 0x0002_0FFF, ...
  // One burst = ($len +1) transfers(aka beats), One transfer = 2^($size) bytes
  // We use INCR(2'b01) burst type, so max burst len is 256
  // We use size = 3'b100, so as 16B per transfer
  // addr 1 ~ 10 cyc delay, read data 300 ~ 500 cycles delay, write data 1 ~ 10 cyc delay
  //************** Input ********************
  // when input_valid is asserted:
  // (num of net_id) * 2 cycles for frames_id[4:0]
  // 2 cycles for each net_id, total 2 * (num of net_id) cycles
  // 2 * (num of net_id) cycles for loc_x[5:0], loc_y[5:0], source at 1st cycle and sink at 2nd cycle for each net_id target
  // only 1 reset before the first pattern
  // The next input pattern will come in 3 cycles after busy falls

  //************** Output **************************
  // Your routed result should be written back to DRAM. After busy is pulled low, pattern will check the correctness of the value inside DRAM.
  // All outputs are synchronized at clock positive edge.
  // busy should be low after initial reset.
  // busy should not be raised when in_valid is high.
  // The test pattern will check whether your data in DRAM and cost is correct or not at the first clock negative edge after busy pulled low.


  // The total cell area should not larger than 2,500,000 μ𝑚^2. 
  // The latency of your design in each pattern should not be larger than 1,000,000 cycles
  // The maximum clock period is set to 15 ns

  // Retrace priority: Down => Up => Right => Left

  always @(*) begin
    for (i = 1; i < 63; i = i + 1) begin
      for (j = 1; j < 63; j = j + 1) begin
        filled_beside[i][j] = 
        map[i+1][j][1] | map[i-1][j][1] | map[i][j+1][1] | map[i][j-1][1];
        // (map[i][j+1][1] | map[i+1][j][1]) | (map[i][j-1][1] | map[i-1][j][1]);
      end
    end
    for (i = 0; i < 64; i = i + 1) begin
      for (j = 0; j < 64; j = j + 1) begin
        zero[i][j] = map[i][j] == 0;
        // zero[i][j] = !(|map[i][j]);

        // filling_value[i][j] = {  // no need to check zero
        //   map[i][j][1] | !map[i][j][0], !(|map[i][j]) & cnt[1] | map[i][j][0]
        // };
        // filling_value[i][j] = {1'b1, cnt[1]};  // play with zero

        // seq_match[i][j] = map[i][j][1] & (map[i][j][0] ~^ cnt[2]);
        seq_match[i][j] = (map[i][j] == seq[cnt[2:1]]);
      end
    end
    down_match = cur_y_p_1 != 0 && seq_match[cur_y_p_1][cur_x];
    up_match = cur_y != 0 && seq_match[cur_y_m_1][cur_x];
    left_match = cur_x_p_1 != 0 && seq_match[cur_y][cur_x_p_1];
    right_match = cur_x != 0 && seq_match[cur_y][cur_x_m_1];
  end
  // busy
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) busy <= 0;
    else if (bvalid) busy <= 0;
    else if (state == EAT) begin
      if (!in_valid) busy <= 1;
    end
  end
  wire sink_filled_beside = filled_beside[sink_y[tgt_No]][sink_x[tgt_No]];
  // cnt
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else if (in_valid) cnt <= cnt + 1;
    else if (~busy) cnt <= 0;
    else if (state == FILL) begin
      if (!sink_filled_beside)
        // sink's neighbor not filled yet
        cnt <= cnt + 5'd1;
      else cnt <= {cnt - 5'd1, 1'b1};
    end else if (state == RETRACE) begin
      if (src_retraced)
        // src been blocked
        cnt <= 0;
      else cnt <= cnt - 1;
    end
  end
  // state
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else begin
      case (1'b1)
        rlast: state <= (miss_map == LOCATION) ? FILL : RETRACE;
        in_valid: state <= EAT;
        !busy: state <= IDLE;
        state == FILL: begin
          if (filled_beside[sink_y[tgt_No]][sink_x[tgt_No]])
            // sink's neighbor filled
            state <= got_weight ? RETRACE : IDLE;
        end
        state == RETRACE: begin
          if (src_retraced)  // src just setted to blocked
            state <= (tgt_No != tgt_num - 1) ? FILL : IDLE;
        end
      endcase
    end
  end
  //--------------------  FSM simplify  --------------------------
  // // state
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) state <= IDLE;
  //   else begin
  //     case (1'b1)  // state[0]
  //       rlast: state <= {1'b1, miss_map};
  //       in_valid | !busy: state <= in_valid;
  //       state == FILL: begin
  //         if (tgt_No != tgt_num && sink_filled_beside)  // sink can be x 
  //           // sink's neighbor filled
  //           state <= {
  //             got_weight, got_weight
  //           };
  //       end
  //       state == RETRACE: begin
  //         if (src_retraced)  // src just setted to blocked
  //           state <= FILL;  // 2'b10
  //       end
  //     endcase
  //   end
  // end
  //-----------------------------------------------------------
  // tgt_num
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) tgt_num <= 0;
    else if (!busy) tgt_num <= cnt[4:1];
  end
  // tgt_No
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) tgt_No <= 0;
    else if (!busy) tgt_No <= 0;
    else if (state == RETRACE)
      if (src_retraced) begin
        // src blocked
        tgt_No <= tgt_No + 1;
      end
  end
  // _frame_id, _net_id[0:14], src_x[0:15], src_y[0:15], sink_x[0:15], sink_y[0:15]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      _frame_id <= 0;
      for (i = 0; i < 15; i = i + 1) _net_id[i] <= 0;
      for (i = 0; i < 16; i = i + 1) src_x[i] <= 0;
      for (i = 0; i < 16; i = i + 1) src_y[i] <= 0;
      for (i = 0; i < 16; i = i + 1) sink_x[i] <= 0;
      for (i = 0; i < 16; i = i + 1) sink_y[i] <= 0;
    end else if (in_valid) begin
      _frame_id <= frame_id;
      _net_id[cnt[4:1]] <= net_id;
      if (~cnt[0]) begin
        src_x[cnt[4:1]] <= loc_x;
        src_y[cnt[4:1]] <= loc_y;
      end else begin
        sink_x[cnt[4:1]] <= loc_x;
        sink_y[cnt[4:1]] <= loc_y;
      end
      // case (cnt[0])
      //   1'b0: begin
      //     src_x[cnt[4:1]] <= loc_x;
      //     src_y[cnt[4:1]] <= loc_y;
      //   end
      //   1'b1: begin
      //     sink_x[cnt[4:1]] <= loc_x;
      //     sink_y[cnt[4:1]] <= loc_y;
      //   end
      // endcase
    end
    // else if (tgt_No == tgt_num) begin
    //   sink_x[tgt_num][3] <= 1'bx;
    // end
  end
  // arvalid, araddr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      arvalid <= 0;
      araddr  <= 0;
    end else if (arvalid & arready) begin
      arvalid <= 0;
    end else if (state == IDLE && in_valid) begin
      arvalid <= 1;
      araddr  <= {16'h0001, frame_id, 11'h0};
    end else if (miss_map == LOCATION)
      if (rlast) begin  // reading location map finish
        arvalid <= 1;
        araddr  <= {16'h0002, _frame_id, 11'h0};
      end
  end
  // rready
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) rready <= 0;
    else if (rlast) rready <= 0;
    else if (arready && arvalid) rready <= 1;
  end
  // miss_map
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) miss_map <= 0;
    else if (!busy) miss_map <= LOCATION;
    else if (miss_map == LOCATION) begin
      if (rlast) miss_map <= WEIGHT;
    end
  end
  // got_weight
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) got_weight <= 0;
    else if (in_valid) got_weight <= 0;
    else if (miss_map == WEIGHT) begin
      if (rlast) got_weight <= 1;
    end
  end

  // mux_y, mux_x
  always @(*) begin
    if (reading_location) begin
      mux_y = src_y[0];
      mux_x = src_x[0];
    end else if (src_retraced) begin
      mux_y = src_y[tgt_No+1];
      mux_x = src_x[tgt_No+1];
    end else begin
      if (down_match) mux_y = cur_y_p_1;
      else if (up_match) mux_y = cur_y_m_1;
      else mux_y = cur_y;

      if (down_match || up_match) mux_x = cur_x;
      else if (left_match) mux_x = cur_x_p_1;
      else mux_x = cur_x_m_1;
    end
  end
  // map[0:63][0:63]
  always @(posedge clk) begin
    if (reading_location) begin
      // if (miss_map == LOCATION) begin
      //   if (rready & rvalid) begin
      //--------------- mine arch ---------------------------
      for (i = 0; i < 32; i = i + 1)
      map[A_L>>1][i+32*A_L[0]] <= {1'b0, |rdata[(i*4)+:4]};
      //--------------- God Hao's arch --------------------
      // for (i = 32; i < 64; i = i + 1)  // row[63]-left half
      // map[i][63] <= {1'b0, |rdata[((i-32)*4)+:4]};
      // for (j = 0; j < 63; j = j + 1) begin  // left half except row[63]
      //   for (i = 32; i < 64; i = i + 1) map[i][j] <= map[i-32][j+1];
      // end
      // for (j = 0; j < 64; j = j + 1) begin  // right half
      //   for (i = 0; i < 32; i = i + 1) map[i][j] <= map[i+32][j];
      // end
      //---------------------------------------------------
      for (i = 2; i < 62; i = i + 1)
      for (j = 2; j < 62; j = j + 1)
      if (i == mux_y && j == mux_x) map[i][j] <= 2'd3;

      // map[src_y[0]][src_x[0]] <= 2'd3;
      // map[sink_y[0]][sink_x[0]] <= 0;
      // end
    end else if (state == FILL) begin
      //-------------------------------------------------
      if (zero[0][0] && (map[1][0][1] | map[0][1][1]))  // upper-left
        map[0][0] <= seq[cnt[1:0]];
      if (zero[0][63] && (map[1][63][1] | map[0][62][1]))  // upper-right
        map[0][63] <= seq[cnt[1:0]];
      if (zero[63][0] && (map[62][0][1] | map[63][1][1]))  // bottom-left
        map[63][0] <= seq[cnt[1:0]];
      if (zero[63][63] && (map[62][63][1] | map[63][62][1]))  // bottom-right
        map[63][63] <= seq[cnt[1:0]];

      for (i = 1; i <= 62; i = i + 1)  // top
      if (zero[0][i] && (map[1][i][1] | map[0][i+1][1] | map[0][i-1][1]))
        map[0][i] <= seq[cnt[1:0]];
      for (i = 1; i <= 62; i = i + 1)  // bottom
      if (zero[63][i] && (map[62][i][1] | map[63][i+1][1] | map[63][i-1][1]))
        map[63][i] <= seq[cnt[1:0]];
      for (i = 1; i <= 62; i = i + 1)  // left
      if (zero[i][0] && (map[i+1][0][1] | map[i-1][0][1] | map[i][1][1]))
        map[i][0] <= seq[cnt[1:0]];
      for (i = 1; i <= 62; i = i + 1)  // right
      if (zero[i][63] && (map[i+1][63][1] | map[i-1][63][1] | map[i][62][1]))
        map[i][63] <= seq[cnt[1:0]];
      for (i = 1; i < 63; i = i + 1) begin
        for (j = 1; j < 63; j = j + 1) begin
          if (zero[i][j] && filled_beside[i][j]) map[i][j] <= seq[cnt[1:0]];
        end
      end
    end else if (state == RETRACE) begin
      if (src_retraced) begin
        // src just setted to blocked
        //----------------- God Hao's arch -----------------------------
        // for (i = 2; i < 62; i = i + 1)
        // for (j = 2; j < 62; j = j + 1)
        // if (i == src_y[tgt_No+1] && j == src_x[tgt_No+1])
        //   map[src_y[tgt_No+1]][src_x[tgt_No+1]] <= 2'd3;
        // else if (map[i][j][1]) map[i][j] <= 0;

        // for (i = 0; i < 2; i = i + 1)
        // for (j = 0; j < 64; j = j + 1) if (map[i][j][1]) map[i][j] <= 0;
        // for (i = 62; i < 64; i = i + 1)
        // for (j = 0; j < 64; j = j + 1) if (map[i][j][1]) map[i][j] <= 0;
        // for (i = 2; i < 64; i = i + 1)
        // for (j = 0; j < 2; j = j + 1) if (map[i][j][1]) map[i][j] <= 0;
        // for (i = 2; i < 64; i = i + 1)
        // for (j = 62; j < 64; j = j + 1) if (map[i][j][1]) map[i][j] <= 0;
        //----------------------------------------------------------
        for (i = 0; i < 64; i = i + 1) begin
          for (j = 0; j < 64; j = j + 1) begin
            // map[i][j] <= {
            //   1'b0, ~map[i][j][1] & map[i][j][0]
            // };  // set filled to empty (larger area)
            if (map[i][j][1]) map[i][j] <= 0;  // set filled to empty
          end
        end
        for (i = 2; i < 62; i = i + 1)
        for (j = 2; j < 62; j = j + 1)
        if (i == mux_y && j == mux_x) map[i][j] <= {1'b1, 1'b1};

        // map[src_y[tgt_No+1]][src_x[tgt_No+1]] <= 2'd3;
        // // map[sink_y[tgt_No+1]][sink_x[tgt_No+1]] <= 2'd0;
      end else if (!cnt[0]) begin  // set next grid to blocked
        for (i = 0; i < 64; i = i + 1)
        for (j = 0; j < 64; j = j + 1)
        if (i == mux_y && j == mux_x) map[i][j] <= {1'b0, 1'b1};

        // if (down_match) map[cur_y_p_1][cur_x] <= 1;
        // else if (up_match) map[cur_y_m_1][cur_x] <= 1;
        // else if (left_match) map[cur_y][cur_x_p_1] <= 1;
        // else if (right_match) map[cur_y][cur_x_m_1] <= 1;
        // case (1)
        //   down_match: map[cur_y_p_1][cur_x] <= 1;
        //   up_match: map[cur_y_m_1][cur_x] <= 1;
        //   left_match: map[cur_y][cur_x_p_1] <= 1;
        //   right_match: map[cur_y][cur_x_m_1] <= 1;
        // endcase
      end
    end
  end

  // WE_L
  always @(*) begin
    WE_L = 1;
    if (miss_map == LOCATION) begin
      if (rready & rvalid) WE_L = 0;
    end else if (state == RETRACE) begin
      WE_L = cnt[0];
    end
  end
  // A_L_reg
  always @(posedge clk, negedge rst_n) begin
    if(!rst_n) A_L_reg <= 0;
    else if ((rready & rvalid) || (wvalid & wready)) A_L_reg <= A_L_reg + 1;
    else if (arvalid | awvalid) begin
      A_L_reg <= 0;
    end
  end
  // A_L
  always @(*) begin
    A_L = 0;
    if (state != RETRACE) begin
      // A_L = A_L_reg;
      A_L = A_L_reg + (wvalid & wready);
      // end else A_L = 5;
    end else begin
      if (down_match) begin
        A_L = {cur_y_p_1, cur_x[5]};
      end else if (up_match) begin
        A_L = {cur_y_m_1, cur_x[5]};
      end else if (left_match) begin
        A_L = {cur_y, cur_x_p_1[5]};
      end else if (right_match) begin
        A_L = {cur_y, cur_x_m_1[5]};
      end
    end
  end
  // DI_L
  always @(*) begin
    DI_L = 128'b0;
    if (miss_map == LOCATION) begin
      if (rready & rvalid) DI_L = rdata;
    end else if (state == RETRACE) begin
      DI_L = DO_L;
      if (down_match) begin
        DI_L[(cur_x[4:0]*4)+:4] = _net_id[tgt_No];
      end else if (up_match) begin
        DI_L[(cur_x[4:0]*4)+:4] = _net_id[tgt_No];
      end else if (left_match) begin
        DI_L[(cur_x_p_1[4:0]*4)+:4] = _net_id[tgt_No];
      end else if (right_match) begin
        DI_L[(cur_x_m_1[4:0]*4)+:4] = _net_id[tgt_No];
      end
    end
  end
  // WE_W
  always @(*) begin
    WE_W = 1'b1;
    if (miss_map == WEIGHT) begin
      if (rready & rvalid) WE_W = 1'b0;
    end
  end
  // A_W_reg
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) A_W_reg <= 0;
    else if (rready && rvalid) A_W_reg <= A_W_reg + 7'd1;
    else if (arready) A_W_reg <= 0;
  end
  // A_W
  always @(*) begin
    A_W = A_W_reg;
    // if (miss_map == WEIGHT && rready && rvalid) A_W = A_W_reg;
    if (state == RETRACE) begin
      // if (down_match) A_W = {(cur_y + 6'd1), cur_x[5]};
      // else if (up_match) A_W = {(cur_y - 6'd1), cur_x[5]};
      // else if (left_match) A_W = {cur_y, cur_x_p_1[5]};
      // else if (right_match) A_W = {cur_y, cur_x_m_1[5]};
      A_W = {mux_y, mux_x[5]};
    end
  end
  // DI_W
  always @(*) begin
    DI_W = 128'b0;
    if (miss_map == WEIGHT) begin
      if (rready & rvalid) DI_W = rdata;
    end
  end


  // cost
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) cost <= 0;
    else if (in_valid) cost <= 0;
    else if (state == RETRACE) begin
      if (!cnt[0]) begin
        // if (down_match) cost <= cost + DO_W[(cur_x[4:0]*4)+:4];
        // else if (up_match) cost <= cost + DO_W[(cur_x[4:0]*4)+:4];
        // else if (left_match) cost <= cost + DO_W[(cur_x_p_1[4:0]*4)+:4];
        // else if (right_match) cost <= cost + DO_W[(cur_x_m_1[4:0]*4)+:4];
        if (down_match && {cur_y_p_1, cur_x} != {src_y[tgt_No], src_x[tgt_No]})
          cost <= cost + DO_W[(cur_x[4:0]*4)+:4];
        else if (up_match && {cur_y_m_1, cur_x} != {src_y[tgt_No], src_x[tgt_No]})
          cost <= cost + DO_W[(cur_x[4:0]*4)+:4];
        else if (left_match && {cur_y, cur_x_p_1} != {src_y[tgt_No], src_x[tgt_No]})
          cost <= cost + DO_W[(cur_x_p_1[4:0]*4)+:4];
        else if (right_match && {cur_y, cur_x_m_1} != {src_y[tgt_No], src_x[tgt_No]})
          cost <= cost + DO_W[(cur_x_m_1[4:0]*4)+:4];
      end
    end
  end
  // cur_x, cur_y
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      cur_x <= 0;
      cur_y <= 0;
    end else if (state == FILL) begin
      cur_x <= sink_x[tgt_No];
      cur_y <= sink_y[tgt_No];
    end else if (state == RETRACE) begin
      if (!cnt[0]) begin
        cur_y <= mux_y;
        cur_x <= mux_x;
        // if (down_match) cur_y <= cur_y_p_1;
        // else if (up_match) cur_y <= cur_y_m_1;
        // else if (left_match) cur_x <= cur_x_p_1;
        // else if (right_match) cur_x <= cur_x_m_1;
      end
    end
  end

  // awaddr
  always @(*) begin
    awaddr = {16'h0001, _frame_id, 11'h0};
  end
  // awvalid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) awvalid <= 0;
    else if (awvalid && awready) begin
      awvalid <= 0;
    end else if (state == RETRACE)
      if (src_retraced) awvalid <= (tgt_No == tgt_num - 1);
  end
  // wvalid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) wvalid <= 0;
    else if (awvalid & awready) wvalid <= 1;
    else if (wlast) wvalid <= 0;
  end
  // wdata
  always @(*) begin
    wdata = DO_L;
  end
  // wlast
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) wlast <= 0;
    else if (wvalid & wready) begin
      wlast <= (A_L == 7'd127);
    end
  end
  // bready
  always @(*) begin
    bready = 1;
    // if (!rst_n) bready <= 0;
    // else if (bvalid) bready <= 0;
    // else if (awvalid & awready) bready <= 1;
  end


  SUMA180_128X128X1BM1 LOCATION_MAP (
    .A0(A_L[0]),
    .A1(A_L[1]),
    .A2(A_L[2]),
    .A3(A_L[3]),
    .A4(A_L[4]),
    .A5(A_L[5]),
    .A6(A_L[6]),
    .DI0(DI_L[0]),
    .DI1(DI_L[1]),
    .DI2(DI_L[2]),
    .DI3(DI_L[3]),
    .DI4(DI_L[4]),
    .DI5(DI_L[5]),
    .DI6(DI_L[6]),
    .DI7(DI_L[7]),
    .DI8(DI_L[8]),
    .DI9(DI_L[9]),
    .DI10(DI_L[10]),
    .DI11(DI_L[11]),
    .DI12(DI_L[12]),
    .DI13(DI_L[13]),
    .DI14(DI_L[14]),
    .DI15(DI_L[15]),
    .DI16(DI_L[16]),
    .DI17(DI_L[17]),
    .DI18(DI_L[18]),
    .DI19(DI_L[19]),
    .DI20(DI_L[20]),
    .DI21(DI_L[21]),
    .DI22(DI_L[22]),
    .DI23(DI_L[23]),
    .DI24(DI_L[24]),
    .DI25(DI_L[25]),
    .DI26(DI_L[26]),
    .DI27(DI_L[27]),
    .DI28(DI_L[28]),
    .DI29(DI_L[29]),
    .DI30(DI_L[30]),
    .DI31(DI_L[31]),
    .DI32(DI_L[32]),
    .DI33(DI_L[33]),
    .DI34(DI_L[34]),
    .DI35(DI_L[35]),
    .DI36(DI_L[36]),
    .DI37(DI_L[37]),
    .DI38(DI_L[38]),
    .DI39(DI_L[39]),
    .DI40(DI_L[40]),
    .DI41(DI_L[41]),
    .DI42(DI_L[42]),
    .DI43(DI_L[43]),
    .DI44(DI_L[44]),
    .DI45(DI_L[45]),
    .DI46(DI_L[46]),
    .DI47(DI_L[47]),
    .DI48(DI_L[48]),
    .DI49(DI_L[49]),
    .DI50(DI_L[50]),
    .DI51(DI_L[51]),
    .DI52(DI_L[52]),
    .DI53(DI_L[53]),
    .DI54(DI_L[54]),
    .DI55(DI_L[55]),
    .DI56(DI_L[56]),
    .DI57(DI_L[57]),
    .DI58(DI_L[58]),
    .DI59(DI_L[59]),
    .DI60(DI_L[60]),
    .DI61(DI_L[61]),
    .DI62(DI_L[62]),
    .DI63(DI_L[63]),
    .DI64(DI_L[64]),
    .DI65(DI_L[65]),
    .DI66(DI_L[66]),
    .DI67(DI_L[67]),
    .DI68(DI_L[68]),
    .DI69(DI_L[69]),
    .DI70(DI_L[70]),
    .DI71(DI_L[71]),
    .DI72(DI_L[72]),
    .DI73(DI_L[73]),
    .DI74(DI_L[74]),
    .DI75(DI_L[75]),
    .DI76(DI_L[76]),
    .DI77(DI_L[77]),
    .DI78(DI_L[78]),
    .DI79(DI_L[79]),
    .DI80(DI_L[80]),
    .DI81(DI_L[81]),
    .DI82(DI_L[82]),
    .DI83(DI_L[83]),
    .DI84(DI_L[84]),
    .DI85(DI_L[85]),
    .DI86(DI_L[86]),
    .DI87(DI_L[87]),
    .DI88(DI_L[88]),
    .DI89(DI_L[89]),
    .DI90(DI_L[90]),
    .DI91(DI_L[91]),
    .DI92(DI_L[92]),
    .DI93(DI_L[93]),
    .DI94(DI_L[94]),
    .DI95(DI_L[95]),
    .DI96(DI_L[96]),
    .DI97(DI_L[97]),
    .DI98(DI_L[98]),
    .DI99(DI_L[99]),
    .DI100(DI_L[100]),
    .DI101(DI_L[101]),
    .DI102(DI_L[102]),
    .DI103(DI_L[103]),
    .DI104(DI_L[104]),
    .DI105(DI_L[105]),
    .DI106(DI_L[106]),
    .DI107(DI_L[107]),
    .DI108(DI_L[108]),
    .DI109(DI_L[109]),
    .DI110(DI_L[110]),
    .DI111(DI_L[111]),
    .DI112(DI_L[112]),
    .DI113(DI_L[113]),
    .DI114(DI_L[114]),
    .DI115(DI_L[115]),
    .DI116(DI_L[116]),
    .DI117(DI_L[117]),
    .DI118(DI_L[118]),
    .DI119(DI_L[119]),
    .DI120(DI_L[120]),
    .DI121(DI_L[121]),
    .DI122(DI_L[122]),
    .DI123(DI_L[123]),
    .DI124(DI_L[124]),
    .DI125(DI_L[125]),
    .DI126(DI_L[126]),
    .DI127(DI_L[127]),
    .DO0(DO_L[0]),
    .DO1(DO_L[1]),
    .DO2(DO_L[2]),
    .DO3(DO_L[3]),
    .DO4(DO_L[4]),
    .DO5(DO_L[5]),
    .DO6(DO_L[6]),
    .DO7(DO_L[7]),
    .DO8(DO_L[8]),
    .DO9(DO_L[9]),
    .DO10(DO_L[10]),
    .DO11(DO_L[11]),
    .DO12(DO_L[12]),
    .DO13(DO_L[13]),
    .DO14(DO_L[14]),
    .DO15(DO_L[15]),
    .DO16(DO_L[16]),
    .DO17(DO_L[17]),
    .DO18(DO_L[18]),
    .DO19(DO_L[19]),
    .DO20(DO_L[20]),
    .DO21(DO_L[21]),
    .DO22(DO_L[22]),
    .DO23(DO_L[23]),
    .DO24(DO_L[24]),
    .DO25(DO_L[25]),
    .DO26(DO_L[26]),
    .DO27(DO_L[27]),
    .DO28(DO_L[28]),
    .DO29(DO_L[29]),
    .DO30(DO_L[30]),
    .DO31(DO_L[31]),
    .DO32(DO_L[32]),
    .DO33(DO_L[33]),
    .DO34(DO_L[34]),
    .DO35(DO_L[35]),
    .DO36(DO_L[36]),
    .DO37(DO_L[37]),
    .DO38(DO_L[38]),
    .DO39(DO_L[39]),
    .DO40(DO_L[40]),
    .DO41(DO_L[41]),
    .DO42(DO_L[42]),
    .DO43(DO_L[43]),
    .DO44(DO_L[44]),
    .DO45(DO_L[45]),
    .DO46(DO_L[46]),
    .DO47(DO_L[47]),
    .DO48(DO_L[48]),
    .DO49(DO_L[49]),
    .DO50(DO_L[50]),
    .DO51(DO_L[51]),
    .DO52(DO_L[52]),
    .DO53(DO_L[53]),
    .DO54(DO_L[54]),
    .DO55(DO_L[55]),
    .DO56(DO_L[56]),
    .DO57(DO_L[57]),
    .DO58(DO_L[58]),
    .DO59(DO_L[59]),
    .DO60(DO_L[60]),
    .DO61(DO_L[61]),
    .DO62(DO_L[62]),
    .DO63(DO_L[63]),
    .DO64(DO_L[64]),
    .DO65(DO_L[65]),
    .DO66(DO_L[66]),
    .DO67(DO_L[67]),
    .DO68(DO_L[68]),
    .DO69(DO_L[69]),
    .DO70(DO_L[70]),
    .DO71(DO_L[71]),
    .DO72(DO_L[72]),
    .DO73(DO_L[73]),
    .DO74(DO_L[74]),
    .DO75(DO_L[75]),
    .DO76(DO_L[76]),
    .DO77(DO_L[77]),
    .DO78(DO_L[78]),
    .DO79(DO_L[79]),
    .DO80(DO_L[80]),
    .DO81(DO_L[81]),
    .DO82(DO_L[82]),
    .DO83(DO_L[83]),
    .DO84(DO_L[84]),
    .DO85(DO_L[85]),
    .DO86(DO_L[86]),
    .DO87(DO_L[87]),
    .DO88(DO_L[88]),
    .DO89(DO_L[89]),
    .DO90(DO_L[90]),
    .DO91(DO_L[91]),
    .DO92(DO_L[92]),
    .DO93(DO_L[93]),
    .DO94(DO_L[94]),
    .DO95(DO_L[95]),
    .DO96(DO_L[96]),
    .DO97(DO_L[97]),
    .DO98(DO_L[98]),
    .DO99(DO_L[99]),
    .DO100(DO_L[100]),
    .DO101(DO_L[101]),
    .DO102(DO_L[102]),
    .DO103(DO_L[103]),
    .DO104(DO_L[104]),
    .DO105(DO_L[105]),
    .DO106(DO_L[106]),
    .DO107(DO_L[107]),
    .DO108(DO_L[108]),
    .DO109(DO_L[109]),
    .DO110(DO_L[110]),
    .DO111(DO_L[111]),
    .DO112(DO_L[112]),
    .DO113(DO_L[113]),
    .DO114(DO_L[114]),
    .DO115(DO_L[115]),
    .DO116(DO_L[116]),
    .DO117(DO_L[117]),
    .DO118(DO_L[118]),
    .DO119(DO_L[119]),
    .DO120(DO_L[120]),
    .DO121(DO_L[121]),
    .DO122(DO_L[122]),
    .DO123(DO_L[123]),
    .DO124(DO_L[124]),
    .DO125(DO_L[125]),
    .DO126(DO_L[126]),
    .DO127(DO_L[127]),
    .CK(clk),
    .OE(1'b1),
    .CS(1'b1),
    .WEB(WE_L)
  );

  SUMA180_128X128X1BM1 WEIGHT_MAP (
    .A0(A_W[0]),
    .A1(A_W[1]),
    .A2(A_W[2]),
    .A3(A_W[3]),
    .A4(A_W[4]),
    .A5(A_W[5]),
    .A6(A_W[6]),
    .DI0(DI_W[0]),
    .DI1(DI_W[1]),
    .DI2(DI_W[2]),
    .DI3(DI_W[3]),
    .DI4(DI_W[4]),
    .DI5(DI_W[5]),
    .DI6(DI_W[6]),
    .DI7(DI_W[7]),
    .DI8(DI_W[8]),
    .DI9(DI_W[9]),
    .DI10(DI_W[10]),
    .DI11(DI_W[11]),
    .DI12(DI_W[12]),
    .DI13(DI_W[13]),
    .DI14(DI_W[14]),
    .DI15(DI_W[15]),
    .DI16(DI_W[16]),
    .DI17(DI_W[17]),
    .DI18(DI_W[18]),
    .DI19(DI_W[19]),
    .DI20(DI_W[20]),
    .DI21(DI_W[21]),
    .DI22(DI_W[22]),
    .DI23(DI_W[23]),
    .DI24(DI_W[24]),
    .DI25(DI_W[25]),
    .DI26(DI_W[26]),
    .DI27(DI_W[27]),
    .DI28(DI_W[28]),
    .DI29(DI_W[29]),
    .DI30(DI_W[30]),
    .DI31(DI_W[31]),
    .DI32(DI_W[32]),
    .DI33(DI_W[33]),
    .DI34(DI_W[34]),
    .DI35(DI_W[35]),
    .DI36(DI_W[36]),
    .DI37(DI_W[37]),
    .DI38(DI_W[38]),
    .DI39(DI_W[39]),
    .DI40(DI_W[40]),
    .DI41(DI_W[41]),
    .DI42(DI_W[42]),
    .DI43(DI_W[43]),
    .DI44(DI_W[44]),
    .DI45(DI_W[45]),
    .DI46(DI_W[46]),
    .DI47(DI_W[47]),
    .DI48(DI_W[48]),
    .DI49(DI_W[49]),
    .DI50(DI_W[50]),
    .DI51(DI_W[51]),
    .DI52(DI_W[52]),
    .DI53(DI_W[53]),
    .DI54(DI_W[54]),
    .DI55(DI_W[55]),
    .DI56(DI_W[56]),
    .DI57(DI_W[57]),
    .DI58(DI_W[58]),
    .DI59(DI_W[59]),
    .DI60(DI_W[60]),
    .DI61(DI_W[61]),
    .DI62(DI_W[62]),
    .DI63(DI_W[63]),
    .DI64(DI_W[64]),
    .DI65(DI_W[65]),
    .DI66(DI_W[66]),
    .DI67(DI_W[67]),
    .DI68(DI_W[68]),
    .DI69(DI_W[69]),
    .DI70(DI_W[70]),
    .DI71(DI_W[71]),
    .DI72(DI_W[72]),
    .DI73(DI_W[73]),
    .DI74(DI_W[74]),
    .DI75(DI_W[75]),
    .DI76(DI_W[76]),
    .DI77(DI_W[77]),
    .DI78(DI_W[78]),
    .DI79(DI_W[79]),
    .DI80(DI_W[80]),
    .DI81(DI_W[81]),
    .DI82(DI_W[82]),
    .DI83(DI_W[83]),
    .DI84(DI_W[84]),
    .DI85(DI_W[85]),
    .DI86(DI_W[86]),
    .DI87(DI_W[87]),
    .DI88(DI_W[88]),
    .DI89(DI_W[89]),
    .DI90(DI_W[90]),
    .DI91(DI_W[91]),
    .DI92(DI_W[92]),
    .DI93(DI_W[93]),
    .DI94(DI_W[94]),
    .DI95(DI_W[95]),
    .DI96(DI_W[96]),
    .DI97(DI_W[97]),
    .DI98(DI_W[98]),
    .DI99(DI_W[99]),
    .DI100(DI_W[100]),
    .DI101(DI_W[101]),
    .DI102(DI_W[102]),
    .DI103(DI_W[103]),
    .DI104(DI_W[104]),
    .DI105(DI_W[105]),
    .DI106(DI_W[106]),
    .DI107(DI_W[107]),
    .DI108(DI_W[108]),
    .DI109(DI_W[109]),
    .DI110(DI_W[110]),
    .DI111(DI_W[111]),
    .DI112(DI_W[112]),
    .DI113(DI_W[113]),
    .DI114(DI_W[114]),
    .DI115(DI_W[115]),
    .DI116(DI_W[116]),
    .DI117(DI_W[117]),
    .DI118(DI_W[118]),
    .DI119(DI_W[119]),
    .DI120(DI_W[120]),
    .DI121(DI_W[121]),
    .DI122(DI_W[122]),
    .DI123(DI_W[123]),
    .DI124(DI_W[124]),
    .DI125(DI_W[125]),
    .DI126(DI_W[126]),
    .DI127(DI_W[127]),
    .DO0(DO_W[0]),
    .DO1(DO_W[1]),
    .DO2(DO_W[2]),
    .DO3(DO_W[3]),
    .DO4(DO_W[4]),
    .DO5(DO_W[5]),
    .DO6(DO_W[6]),
    .DO7(DO_W[7]),
    .DO8(DO_W[8]),
    .DO9(DO_W[9]),
    .DO10(DO_W[10]),
    .DO11(DO_W[11]),
    .DO12(DO_W[12]),
    .DO13(DO_W[13]),
    .DO14(DO_W[14]),
    .DO15(DO_W[15]),
    .DO16(DO_W[16]),
    .DO17(DO_W[17]),
    .DO18(DO_W[18]),
    .DO19(DO_W[19]),
    .DO20(DO_W[20]),
    .DO21(DO_W[21]),
    .DO22(DO_W[22]),
    .DO23(DO_W[23]),
    .DO24(DO_W[24]),
    .DO25(DO_W[25]),
    .DO26(DO_W[26]),
    .DO27(DO_W[27]),
    .DO28(DO_W[28]),
    .DO29(DO_W[29]),
    .DO30(DO_W[30]),
    .DO31(DO_W[31]),
    .DO32(DO_W[32]),
    .DO33(DO_W[33]),
    .DO34(DO_W[34]),
    .DO35(DO_W[35]),
    .DO36(DO_W[36]),
    .DO37(DO_W[37]),
    .DO38(DO_W[38]),
    .DO39(DO_W[39]),
    .DO40(DO_W[40]),
    .DO41(DO_W[41]),
    .DO42(DO_W[42]),
    .DO43(DO_W[43]),
    .DO44(DO_W[44]),
    .DO45(DO_W[45]),
    .DO46(DO_W[46]),
    .DO47(DO_W[47]),
    .DO48(DO_W[48]),
    .DO49(DO_W[49]),
    .DO50(DO_W[50]),
    .DO51(DO_W[51]),
    .DO52(DO_W[52]),
    .DO53(DO_W[53]),
    .DO54(DO_W[54]),
    .DO55(DO_W[55]),
    .DO56(DO_W[56]),
    .DO57(DO_W[57]),
    .DO58(DO_W[58]),
    .DO59(DO_W[59]),
    .DO60(DO_W[60]),
    .DO61(DO_W[61]),
    .DO62(DO_W[62]),
    .DO63(DO_W[63]),
    .DO64(DO_W[64]),
    .DO65(DO_W[65]),
    .DO66(DO_W[66]),
    .DO67(DO_W[67]),
    .DO68(DO_W[68]),
    .DO69(DO_W[69]),
    .DO70(DO_W[70]),
    .DO71(DO_W[71]),
    .DO72(DO_W[72]),
    .DO73(DO_W[73]),
    .DO74(DO_W[74]),
    .DO75(DO_W[75]),
    .DO76(DO_W[76]),
    .DO77(DO_W[77]),
    .DO78(DO_W[78]),
    .DO79(DO_W[79]),
    .DO80(DO_W[80]),
    .DO81(DO_W[81]),
    .DO82(DO_W[82]),
    .DO83(DO_W[83]),
    .DO84(DO_W[84]),
    .DO85(DO_W[85]),
    .DO86(DO_W[86]),
    .DO87(DO_W[87]),
    .DO88(DO_W[88]),
    .DO89(DO_W[89]),
    .DO90(DO_W[90]),
    .DO91(DO_W[91]),
    .DO92(DO_W[92]),
    .DO93(DO_W[93]),
    .DO94(DO_W[94]),
    .DO95(DO_W[95]),
    .DO96(DO_W[96]),
    .DO97(DO_W[97]),
    .DO98(DO_W[98]),
    .DO99(DO_W[99]),
    .DO100(DO_W[100]),
    .DO101(DO_W[101]),
    .DO102(DO_W[102]),
    .DO103(DO_W[103]),
    .DO104(DO_W[104]),
    .DO105(DO_W[105]),
    .DO106(DO_W[106]),
    .DO107(DO_W[107]),
    .DO108(DO_W[108]),
    .DO109(DO_W[109]),
    .DO110(DO_W[110]),
    .DO111(DO_W[111]),
    .DO112(DO_W[112]),
    .DO113(DO_W[113]),
    .DO114(DO_W[114]),
    .DO115(DO_W[115]),
    .DO116(DO_W[116]),
    .DO117(DO_W[117]),
    .DO118(DO_W[118]),
    .DO119(DO_W[119]),
    .DO120(DO_W[120]),
    .DO121(DO_W[121]),
    .DO122(DO_W[122]),
    .DO123(DO_W[123]),
    .DO124(DO_W[124]),
    .DO125(DO_W[125]),
    .DO126(DO_W[126]),
    .DO127(DO_W[127]),
    .CK(clk),
    .OE(1'b1),
    .CS(1'b1),
    .WEB(WE_W)
  );
endmodule