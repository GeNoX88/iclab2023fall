//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//    (C) Copyright System Integration and Silicon Implementation Laboratory
//    All Right Reserved
//		Date		: 2023/10
//		Version		: v1.0
//   	File Name   : HT_TOP.v
//   	Module Name : HT_TOP
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################


//*********************  performance version  ************************
`include "SORT_IP.v"

module HT_TOP (
  // Input signals
  input clk,
  input rst_n,
  input in_valid,
  input [2:0] in_weight,  // 0~7 for leaf but 5bits weight for parent node
  input out_mode,
  // Output signals
  output reg out_valid,
  output reg out_code
);

  parameter IDLE = 0, EAT = 1, CALC = 2, OUTPUT = 3;
  integer i;
  reg [1:0] state;
  reg [2:0] char;  // 0 ~ 7 for A ~ V
  reg [3:0] cnt;  // 0 ~ 15
  reg [3:0] node_reg[0:7];  // to be sorted for node 0 ~ node 8
  wire [3:0] node_wire[0:7];
  reg [4:0] _weight[0:7];  // 8 nodes without root, 0~31 each
  reg [4:0] weight[0:8];  // 9 nodes with dummy node, 0~31 each
  reg mode;
  reg [6:0] encode[0:7];
  reg [2:0] set[0:7], ptr[0:7];
  reg flag;
  reg zero[0:7];

  TWO_MIN_IP FIND (
    .IN_character({
      node_reg[0],
      node_reg[1],
      node_reg[2],
      node_reg[3],
      node_reg[4],
      node_reg[5],
      node_reg[6],
      node_reg[7]
    }),
    .IN_weight({
      weight[node_reg[0]],
      weight[node_reg[1]],
      weight[node_reg[2]],
      weight[node_reg[3]],
      weight[node_reg[4]],
      weight[node_reg[5]],
      weight[node_reg[6]],
      weight[node_reg[7]]
    }),
    .OUT_character({
      node_wire[0],
      node_wire[1],
      node_wire[2],
      node_wire[3],
      node_wire[4],
      node_wire[5],
      node_wire[6],
      node_wire[7]
    })
  );

  // A, B, C, E, I, L, O, V
  localparam A = 0;
  localparam B = 1;
  localparam C = 2;
  localparam E = 3;
  localparam I = 4;
  localparam L = 5;
  localparam O = 6;
  localparam V = 7;

  // mode    0 for "ILOVE", 1 for "ICLAB"
  always @(posedge clk) begin
    if (state == IDLE) if (in_valid) mode <= out_mode;
  end
  // _weight[0:13]
  always @(posedge clk) begin
    if (cnt[3] == 0)  // 0 ~ 7 for node[0] ~ [7]
      _weight[cnt] <= {2'b0, in_weight};
    else begin  // 8 ~ 13
      case (cnt)
        8, 9, 10, 11, 12, 13:
        _weight[node_wire[7]] <= _weight[node_wire[6]] + _weight[node_wire[7]];
      endcase
    end
  end

  // cnt
  always @(posedge clk) begin
    if (state == IDLE && !in_valid) begin
      cnt <= 0;
    end else cnt <= cnt + 1;
    // 0 behind A,..., 7 behind V and 8 when in_valid deasserted
  end

  // zero[0:7]
  always @(*) begin
    for (i = 0; i < 8; i = i + 1) zero[i] = ptr[i] == 0;
  end

  // node_reg[0:7]
  always @(posedge clk) begin
    if (state == IDLE) for (i = 0; i < 8; i = i + 1) node_reg[i] <= i;  // 0 ~ 7
    else if (state == CALC) begin  // 8 ~ 14
      {node_reg[0], node_reg[1], node_reg[2], node_reg[3], 
      node_reg[4], node_reg[5], node_reg[6], node_reg[7]} <= 
    {
        4'd8,  // dummy node
        node_wire[0],
        node_wire[1],
        node_wire[2],
        node_wire[3],
        node_wire[4],
        node_wire[5],
        node_wire[7]  // new node
      };
    end
  end

  // weight[0:8]
  always @(*) begin
    for (i = 0; i < 8; i = i + 1) weight[i] = _weight[i];
    weight[8] = 31;  // dummy node
  end

  // char
  always @(posedge clk) begin
    if (state == IDLE) char <= I;
    else if (char == E && zero[E] || char == B && zero[B]) char <= I;
    else if (state == OUTPUT) begin
      case (1)
        char == I: if (zero[I]) char <= mode == 0 ? L : C;
        char == A: if (zero[A]) char <= B;
        char == C: if (zero[C]) char <= L;
        char == L: if (zero[L]) char <= mode == 0 ? O : A;
        char == O: if (zero[O]) char <= V;
        char == V: if (zero[V]) char <= E;
        default:   char <= char;
      endcase
    end
  end

  // state
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else begin
      case (1)
        state == OUTPUT: begin
          if (char == E && zero[E] || char == B && zero[B]) state <= IDLE;
        end
        state == CALC: begin
          if (cnt == 14) state <= OUTPUT;
        end
        state == EAT: if (cnt == 7) state <= CALC;
        in_valid: state <= EAT;
      endcase
    end
  end

  // encode[0:7], ptr[0:7]
  always @(posedge clk) begin
    if (state == IDLE) begin
      for (i = 0; i < 8; i = i + 1) begin
        encode[i] <= 8'b0;
        ptr[i] <= 3'd0;
      end
    end else if (state == CALC) begin
      for (i = 0; i < 8; i = i + 1) begin
        if (set[i] == set[node_wire[6]]) begin  // who is in left set
          if (cnt != 14) ptr[i] <= ptr[i] + 1;
        end else if (set[i] == set[node_wire[7]]) begin  // who is in right set
          encode[i][ptr[i]] <= 1'b1;
          if (cnt != 14) ptr[i] <= ptr[i] + 1;
        end else begin  // who is not in the two sets
          if (cnt == 14) begin
            ptr[i] <= ptr[i] - 1;  // go back to head
          end
        end
      end
    end else if (state == OUTPUT) begin
      if (!zero[char]) ptr[char] <= ptr[char] - 1;
    end
  end

  // set[0:7]
  always @(posedge clk) begin
    if (state == IDLE) begin
      for (i = 0; i < 8; i = i + 1) begin
        set[i] <= i;
      end
    end else begin
      case (cnt)
        8, 9, 10, 11, 12, 13: begin
          for (i = 0; i < 8; i = i + 1) begin  // char node's set update
            if (set[i] == set[node_wire[6]]) begin  // who is in left set
              set[i] <= set[node_wire[7]];  // join to right set
            end
          end
        end
      endcase
    end
  end

  // out_valid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (state == CALC) begin
      if (cnt == 14) out_valid <= 1;
    end else if (char == E && zero[E] || char == B && zero[B]) out_valid <= 0;
  end
  // out_code
  always @(*) begin
    if (state != OUTPUT) out_code = 0;
    else out_code = encode[char][ptr[char]];
  end
endmodule





module TWO_MIN_IP (
  // Input signals
  input [31:0] IN_character,  // 4 bits node
  input [39:0] IN_weight,  // 5 bits weight
  // Output signals
  output reg [31:0] OUT_character
);
  integer i, toBeInsert;
  wire [3:0] prearr0[0:1];
  reg [3:0] arr0[0:7], arr1[0:7];
  reg [4:0] w0[0:7], w1[0:7];
  integer
    r_gold_candidate13,
    r_gold_loser13,
    r_gold_candidate57,
    r_gold_loser57,
    r_gold,
    r_subgold,
    r_best_silver,
    r_silver,
    l_gold_candidate02,
    l_gold_candidate46,
    l_gold,
    silver,
    gold,
    idx[0:7];

  SORT_IP #(  // [0,1] in order to demo
    .IP_WIDTH(2)
  ) SORT (
    .IN_character(IN_character[31:24]),
    .IN_weight(IN_weight[39:30]),
    .OUT_character({prearr0[0], prearr0[1]})
  );


  always @(*) begin
    {arr0[0], arr0[1]} = {prearr0[0], prearr0[1]};
    for (i = 2; i < 8; i = i + 1) arr0[i] = IN_character[4*(7-i)+:4];
    for (i = 0; i < 8; i = i + 1) w0[i] = IN_weight[5*(7-i)+:5];



    // //*************** pure idx operation (poor performance) ***********************
    //     {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5], idx[6], idx[7]} = {
    //       0, 1, 2, 3, 4, 5, 6, 7
    //     };
    //     // first merge level 1v1
    //     // if (w0[0] < w0[1]) begin  // [0,1]
    //     // {arr0[0], arr0[1]} = {arr0[1], arr0[0]}; // done by SORT_IP
    //     // {idx[0], idx[1]} = {idx[1], idx[0]};
    //     // {w0[0], w0[1]}   = {w0[1], w0[0]};
    //     // end
    //     if (w0[2] < w0[3]) begin  // [2,3]
    //       // {arr0[2], arr0[3]} = {arr0[3], arr0[2]};
    //       {idx[2], idx[3]} = {idx[3], idx[2]};
    //       // {w0[2], w0[3]} = {w0[3], w0[2]};
    //     end
    //     if (w0[4] < w0[5]) begin  // [4,5]
    //       // {arr0[4], arr0[5]} = {arr0[5], arr0[4]};
    //       {idx[4], idx[5]} = {idx[5], idx[4]};
    //       // {w0[4], w0[5]} = {w0[5], w0[4]};
    //     end
    //     if (w0[6] < w0[7]) begin  // [6,7]
    //       // {arr0[6], arr0[7]} = {arr0[7], arr0[6]};
    //       {idx[6], idx[7]} = {idx[7], idx[6]};
    //       // {w0[6], w0[7]} = {w0[7], w0[6]};
    //     end
    // //***************************************************************



    //******************* w and arr 1-1 swap (better performance) ************************
    // first merge level 1v1
    if (w0[0] < w0[1]) begin  // [0,1]
      // {arr0[0], arr0[1]} = {arr0[1], arr0[0]}; // done by SORT_IP
      {w0[0], w0[1]} = {w0[1], w0[0]};
    end
    if (w0[2] < w0[3]) begin  // [2,3]
      {arr0[2], arr0[3]} = {arr0[3], arr0[2]};
      {w0[2], w0[3]} = {w0[3], w0[2]};
    end
    if (w0[4] < w0[5]) begin  // [4,5]
      {arr0[4], arr0[5]} = {arr0[5], arr0[4]};
      {w0[4], w0[5]} = {w0[5], w0[4]};
    end
    if (w0[6] < w0[7]) begin  // [6,7]
      {arr0[6], arr0[7]} = {arr0[7], arr0[6]};
      {w0[6], w0[7]} = {w0[7], w0[6]};
    end
    {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5], idx[6], idx[7]} = {
      0, 1, 2, 3, 4, 5, 6, 7
    };
    //***************************************************************

    //****************** right-group(poor performance) *******************************

    r_gold_candidate13 = idx[3];
    r_gold_loser13 = idx[1];
    r_gold_candidate57 = idx[7];
    r_gold_loser57 = idx[5];

    if (w0[idx[1]] < w0[idx[3]]) begin  // [1,3]
      r_gold_candidate13 = idx[1];
      r_gold_loser13 = idx[3];
      {idx[1], idx[3]} = {idx[3], idx[1]};
    end

    if (w0[idx[5]] < w0[idx[7]]) begin  // [5,7]
      r_gold_candidate57 = idx[5];
      r_gold_loser57 = idx[7];
      {idx[5], idx[7]} = {idx[7], idx[5]};
    end

    gold = r_gold_candidate57;
    r_subgold = r_gold_candidate13;
    r_best_silver = r_gold_loser57;

    if (w0[idx[3]] < w0[idx[7]]) begin
      gold = r_gold_candidate13;
      r_subgold = r_gold_candidate57;
      r_best_silver = r_gold_loser13;
    end

    case (1)
      w0[r_subgold] > w0[r_best_silver]: r_silver = r_best_silver;
      w0[r_subgold] == w0[r_best_silver]:
      r_silver = r_subgold < r_best_silver ? r_best_silver : r_subgold;
      w0[r_subgold] < w0[r_best_silver]: r_silver = r_subgold;
      default: r_silver = 0;
    endcase
    //***********************************************************************



    // ***************** left-group(poor performance) ****************************
    if (w0[idx[0]] < w0[idx[2]]) begin
      l_gold_candidate02 = idx[0];
    end else l_gold_candidate02 = idx[2];

    if (w0[idx[4]] < w0[idx[6]]) begin
      l_gold_candidate46 = idx[4];
    end else l_gold_candidate46 = idx[6];

    if (w0[l_gold_candidate02] < w0[l_gold_candidate46]) begin
      l_gold = l_gold_candidate02;
    end else l_gold = l_gold_candidate46;

    // sorting of left-group's 1st min and right-group's 2nd min
    case (1)
      w0[r_silver] > w0[l_gold]: silver = l_gold;
      w0[r_silver] == w0[l_gold]:
      silver = r_silver < l_gold ? l_gold : r_silver;
      w0[r_silver] < w0[l_gold]: silver = r_silver;
      default: silver = 0;
    endcase

    case ({
      silver, gold
    })
      {
        32'd0, 32'd1
      }, {
        32'd1, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[2], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd0, 32'd2
      }, {
        32'd2, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd0, 32'd3
      }, {
        32'd3, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd0, 32'd4
      }, {
        32'd4, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd0, 32'd5
      }, {
        32'd5, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        32'd0, 32'd6
      }, {
        32'd6, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        32'd0, 32'd7
      }, {
        32'd7, 32'd0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        32'd1, 32'd2
      }, {
        32'd2, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd1, 32'd3
      }, {
        32'd3, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd1, 32'd4
      }, {
        32'd4, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd1, 32'd5
      }, {
        32'd5, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        32'd1, 32'd6
      }, {
        32'd6, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        32'd1, 32'd7
      }, {
        32'd7, 32'd1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        32'd2, 32'd3
      }, {
        32'd3, 32'd2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd2, 32'd4
      }, {
        32'd4, 32'd2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd2, 32'd5
      }, {
        32'd5, 32'd2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        32'd2, 32'd6
      }, {
        32'd6, 32'd2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        32'd2, 32'd7
      }, {
        32'd7, 32'd2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        32'd3, 32'd4
      }, {
        32'd4, 32'd3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        32'd3, 32'd5
      }, {
        32'd5, 32'd3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        32'd3, 32'd6
      }, {
        32'd6, 32'd3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        32'd3, 32'd7
      }, {
        32'd7, 32'd3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        32'd4, 32'd5
      }, {
        32'd5, 32'd4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[6], arr0[7]
        };
      end
      {
        32'd4, 32'd6
      }, {
        32'd6, 32'd4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[5], arr0[7]
        };
      end
      {
        32'd4, 32'd7
      }, {
        32'd7, 32'd4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[5], arr0[6]
        };
      end
      {
        32'd5, 32'd6
      }, {
        32'd6, 32'd5
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[7]
        };
      end
      {
        32'd5, 32'd7
      }, {
        32'd7, 32'd5
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[6]
        };
      end
      {
        32'd6, 32'd7
      }, {
        32'd7, 32'd6
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[5]
        };
      end
      default: begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = 24'b0;
      end
    endcase

    arr1[6] = arr0[silver];
    arr1[7] = arr0[gold];

    OUT_character = {
      arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5], arr1[6], arr1[7]
    };
  end
endmodule
