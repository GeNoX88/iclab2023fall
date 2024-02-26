`include "SORT_IP.v"

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
    //***************************************************************

    //****************** right-group(poor performance) *******************************
    {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5], idx[6], idx[7]} = {
      0, 1, 2, 3, 4, 5, 6, 7
    };

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
    //******************** right-group(better performance) ******************************
    // {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5], idx[6], idx[7]} = {
    //   0, 1, 2, 3, 4, 5, 6, 7
    // };
    // {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5], arr1[6], arr1[7]} = {
    //   arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
    // };
    // {w1[0], w1[1], w1[2], w1[3], w1[4], w1[5], w1[6], w1[7]} = {
    //   w0[0], w0[1], w0[2], w0[3], w0[4], w0[5], w0[6], w0[7]
    // };

    // if (w1[idx[1]] < w1[idx[3]]) begin  // [1,3]
    //   {arr1[idx[1]], arr1[idx[3]]} = {arr1[idx[3]], arr1[idx[1]]};
    //   {w1[idx[1]], w1[idx[3]]} = {w1[idx[3]], w1[idx[1]]};
    // end

    // if (w1[idx[5]] < w1[idx[7]]) begin  // [5,7]
    //   {arr1[idx[5]], arr1[idx[7]]} = {arr1[idx[7]], arr1[idx[5]]};
    //   {w1[idx[5]], w1[idx[7]]} = {w1[idx[7]], w1[idx[5]]};
    // end

    // if (w1[idx[3]] < w1[idx[7]]) begin
    //   {arr1[idx[1]], arr1[idx[3]], arr1[idx[5]], arr1[idx[7]]} = {
    //     arr1[idx[5]], arr1[idx[7]], arr1[idx[1]], arr1[idx[3]]
    //   };
    //   {w1[idx[1]], w1[idx[3]], w1[idx[5]], w1[idx[7]]} = {
    //     w1[idx[5]], w1[idx[7]], w1[idx[1]], w1[idx[3]]
    //   };
    // end
    // gold = idx[7];
    // case (1)
    //   w1[idx[3]] > w1[idx[5]]: r_silver = idx[5];
    //   w1[idx[3]] == w1[idx[5]]:
    //   r_silver = idx[3] < idx[5] ? idx[5] : idx[3];
    //   w1[idx[3]] < w1[idx[5]]: r_silver = idx[3];
    //   default: r_silver = 0;
    // endcase
    //***********************************************************************



    // // ***************** left-group(poor performance) ****************************
    //    left-group
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

    // **************** left-group(better performance) ***************************
    //    left-group
    // if (w1[idx[0]] < w1[idx[2]]) begin
    //   {arr1[idx[0]], arr1[idx[2]]} = {arr1[idx[2]], arr1[idx[0]]};
    //   {w1[idx[0]], w1[idx[2]]} = {w1[idx[2]], w1[idx[0]]};
    // end

    // if (w1[idx[4]] < w1[idx[6]]) begin
    //   {arr1[idx[4]], arr1[idx[6]]} = {arr1[idx[6]], arr1[idx[4]]};
    //   {w1[idx[4]], w1[idx[6]]} = {w1[idx[6]], w1[idx[4]]};
    // end

    // if (w1[idx[2]] < w1[idx[6]]) begin
    //   {arr1[idx[2]], arr1[idx[6]]} = {arr1[idx[6]], arr1[idx[2]]};
    //   {w1[idx[2]], w1[idx[6]]} = {w1[idx[6]], w1[idx[2]]};
    // end
    // l_gold = idx[6];

    // // sorting of left-group's 1st min and right-group's 2nd min
    // case (1)
    //   w1[r_silver] > w1[l_gold]: silver = l_gold;
    //   w1[r_silver] == w1[l_gold]:
    //   silver = r_silver < l_gold ? l_gold : r_silver;
    //   w1[r_silver] < w1[l_gold]: silver = r_silver;
    //   default: silver = 0;
    // endcase


    //**************** will generate latch (for arr1[31:8] all 24bit) **********
    // toBeInsert = 0;
    // i = 0;
    // for (i = 0; i < 8; i = i + 1) begin
    //   if (i != gold && i != silver) begin
    //     arr1[toBeInsert] = arr0[i];
    //     toBeInsert += 1;
    //   end
    // end
    //*************************************************************************

    case ({
      silver, gold
    })
      {
        0, 1
      }, {
        1, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[2], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        0, 2
      }, {
        2, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        0, 3
      }, {
        3, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        0, 4
      }, {
        4, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        0, 5
      }, {
        5, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        0, 6
      }, {
        6, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        0, 7
      }, {
        7, 0
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[1], arr0[2], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        1, 2
      }, {
        2, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[3], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        1, 3
      }, {
        3, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        1, 4
      }, {
        4, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        1, 5
      }, {
        5, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        1, 6
      }, {
        6, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        1, 7
      }, {
        7, 1
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[2], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        2, 3
      }, {
        3, 2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[4], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        2, 4
      }, {
        4, 2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        2, 5
      }, {
        5, 2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        2, 6
      }, {
        6, 2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        2, 7
      }, {
        7, 2
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[3], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        3, 4
      }, {
        4, 3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[5], arr0[6], arr0[7]
        };
      end
      {
        3, 5
      }, {
        5, 3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[6], arr0[7]
        };
      end
      {
        3, 6
      }, {
        6, 3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[5], arr0[7]
        };
      end
      {
        3, 7
      }, {
        7, 3
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[4], arr0[5], arr0[6]
        };
      end
      {
        4, 5
      }, {
        5, 4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[6], arr0[7]
        };
      end
      {
        4, 6
      }, {
        6, 4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[5], arr0[7]
        };
      end
      {
        4, 7
      }, {
        7, 4
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[5], arr0[6]
        };
      end
      {
        5, 6
      }, {
        6, 5
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[7]
        };
      end
      {
        5, 7
      }, {
        7, 5
      } : begin
        {arr1[0], arr1[1], arr1[2], arr1[3], arr1[4], arr1[5]} = {
          arr0[0], arr0[1], arr0[2], arr0[3], arr0[4], arr0[6]
        };
      end
      {
        6, 7
      }, {
        7, 6
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
