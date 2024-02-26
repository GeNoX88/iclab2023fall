//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//    (C) Copyright System Integration and Silicon Implementation Laboratory
//    All Right Reserved
//		Date		: 2023/10
//		Version		: v1.0
//   	File Name   : SORT_IP.v
//   	Module Name : SORT_IP
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################
module SORT_IP #(
  parameter IP_WIDTH = 8  // the number of nodes to be sorted
) (
  // Input signals
  IN_character,  // 4 bits node
  IN_weight,  // 5 bits weight
  // Output signals
  OUT_character
);
  input [IP_WIDTH*4-1:0] IN_character;  // 4 bits node
  input [IP_WIDTH*5-1:0] IN_weight;  // 5 bits weight
  output reg [IP_WIDTH*4-1:0] OUT_character;

  integer i, j, toBeInsert;

  generate
    case (IP_WIDTH)  // the number of nodes to be sorted
      2: begin : _7_9
        reg [3:0] ary0[0:1];
        reg [4:0] w0[0:1];
        always @(*) begin
          for (i = 0; i < 2; i = i + 1) begin
            ary0[i] = IN_character[4*(1-i)+:4];
            w0[i]   = IN_weight[5*(1-i)+:5];
          end
          if (w0[0] < w0[1]) OUT_character = {ary0[1], ary0[0]};
          else OUT_character = {ary0[0], ary0[1]};
        end
      end
      3: begin : _11_14
        reg [3:0] ary0[0:2], ary1[0:2];
        reg [4:0] w0[0:2], w1[0:2];
        always @(*) begin
          for (i = 0; i < 3; i = i + 1) begin
            ary0[i] = IN_character[4*(2-i)+:4];
            w0[i]   = IN_weight[5*(2-i)+:5];
          end

          // first merge level
          if (w0[0] < w0[1]) begin  // [0,1]
            {ary0[0], ary0[1]} = {ary0[1], ary0[0]};
            {w0[0], w0[1]} = {w0[1], w0[0]};
          end

          // second merge level 2v1
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 3) begin  // [0,1,2]
            if (1 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (2 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end
          OUT_character = {ary1[0], ary1[1], ary1[2]};
        end
      end
      4: begin : _15_19
        reg [3:0] ary0[0:3], ary1[0:3];
        reg [4:0] w0[0:3], w1[0:3];

        always @(*) begin
          for (i = 0; i < 4; i = i + 1) begin
            ary0[i] = IN_character[4*(3-i)+:4];
            w0[i]   = IN_weight[5*(3-i)+:5];
          end

          // first merge level
          if (w0[0] < w0[1]) begin  // [0,1]
            {ary0[0], ary0[1]} = {ary0[1], ary0[0]};
            {w0[0], w0[1]} = {w0[1], w0[0]};
          end
          if (w0[2] < w0[3]) begin  //[2,3]
            {ary0[2], ary0[3]} = {ary0[3], ary0[2]};
            {w0[2], w0[3]} = {w0[3], w0[2]};
          end

          // second merge level 2v2
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 4) begin  // [0,1,2,3]
            if (1 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (3 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end
          OUT_character = {ary1[0], ary1[1], ary1[2], ary1[3]};
        end
      end
      5: begin : _19_24
        reg [3:0] ary0[0:4], ary1[0:4], ary2[0:4];
        reg [4:0] w0[0:4], w1[0:4], w2[0:4];

        always @(*) begin
          for (i = 0; i < 5; i = i + 1) begin
            ary0[i] = IN_character[4*(4-i)+:4];
            w0[i]   = IN_weight[5*(4-i)+:5];
          end

          {ary1[0], ary1[1]} = {ary0[0], ary0[1]};  // early ary1
          {w1[0], w1[1]} = {w0[0], w0[1]};  // early w1

          // first merge level 1v1
          if (w1[0] < w1[1]) begin  // [0,1]
            {ary1[0], ary1[1]} = {ary1[1], ary1[0]};  // early ary1
            {w1[0], w1[1]} = {w1[1], w1[0]};  // early w1
          end
          if (w0[2] < w0[3]) begin  // [2,3]
            {ary0[2], ary0[3]} = {ary0[3], ary0[2]};
            {w0[2], w0[3]} = {w0[3], w0[2]};
          end

          // second merge level 2v1
          i = 2;
          j = 4;
          toBeInsert = 2;
          while (toBeInsert < 5) begin  // [2,3,4]
            if (3 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (4 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          // third merge level 2v3
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 5) begin  // [0,1,2,3,4]
            if (1 < i) begin
              ary2[toBeInsert] = ary1[j];
              w2[toBeInsert] = w1[j];
              j = j + 1;
            end else if (4 < j) begin
              ary2[toBeInsert] = ary1[i];
              w2[toBeInsert] = w1[i];
              i = i + 1;
            end else begin
              if (w1[i] < w1[j]) begin
                ary2[toBeInsert] = ary1[j];
                w2[toBeInsert] = w1[j];
                j = j + 1;
              end else begin
                ary2[toBeInsert] = ary1[i];
                w2[toBeInsert] = w1[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          OUT_character = {ary2[0], ary2[1], ary2[2], ary2[3], ary2[4]};
        end
      end
      6: begin : _19_24
        reg [3:0] ary0[0:5], ary1[0:5], ary2[0:5];
        reg [4:0] w0[0:5], w1[0:5], w2[0:5];

        always @(*) begin
          for (i = 0; i < 6; i = i + 1) begin
            ary0[i] = IN_character[4*(5-i)+:4];
            w0[i]   = IN_weight[5*(5-i)+:5];
          end

          // first merge level 1v1
          if (w0[0] < w0[1]) begin  // [0,1]
            {ary0[0], ary0[1]} = {ary0[1], ary0[0]};
            {w0[0], w0[1]} = {w0[1], w0[0]};
          end
          if (w0[3] < w0[4]) begin  // [3,4]
            {ary0[3], ary0[4]} = {ary0[4], ary0[3]};
            {w0[3], w0[4]} = {w0[4], w0[3]};
          end

          // second merge level 2v1
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 3) begin  // [0,1,2]
            if (1 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (2 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          i = 3;
          j = 5;
          toBeInsert = 3;
          while (toBeInsert < 6) begin  // [3,4,5]
            if (4 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (5 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          // third merge level 3v3
          i = 0;
          j = 3;
          toBeInsert = 0;
          while (toBeInsert < 6) begin  // [0,1,2,3,4,5]
            if (2 < i) begin
              ary2[toBeInsert] = ary1[j];
              w2[toBeInsert] = w1[j];
              j = j + 1;
            end else if (5 < j) begin
              ary2[toBeInsert] = ary1[i];
              w2[toBeInsert] = w1[i];
              i = i + 1;
            end else begin
              if (w1[i] < w1[j]) begin
                ary2[toBeInsert] = ary1[j];
                w2[toBeInsert] = w1[j];
                j = j + 1;
              end else begin
                ary2[toBeInsert] = ary1[i];
                w2[toBeInsert] = w1[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          OUT_character = {
            ary2[0], ary2[1], ary2[2], ary2[3], ary2[4], ary2[5]
          };
        end
      end
      7: begin : _23_29
        reg [3:0] ary0[0:6], ary1[0:6], ary2[0:6];
        reg [4:0] w0[0:6], w1[0:6], w2[0:6];

        always @(*) begin
          for (i = 0; i < 7; i = i + 1) begin
            ary0[i] = IN_character[4*(6-i)+:4];
            w0[i]   = IN_weight[5*(6-i)+:5];
          end

          // first merge level 1v1
          if (w0[0] < w0[1]) begin  // [0,1]
            {ary0[0], ary0[1]} = {ary0[1], ary0[0]};
            {w0[0], w0[1]} = {w0[1], w0[0]};
          end
          if (w0[2] < w0[3]) begin  // [2,3]
            {ary0[2], ary0[3]} = {ary0[3], ary0[2]};
            {w0[2], w0[3]} = {w0[3], w0[2]};
          end
          if (w0[4] < w0[5]) begin  // [4,5]
            {ary0[4], ary0[5]} = {ary0[5], ary0[4]};
            {w0[4], w0[5]} = {w0[5], w0[4]};
          end

          // second merge level 2v2 & 2v1
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 4) begin  // [0,1,2,3]
            if (1 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (3 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          i = 4;
          j = 6;
          toBeInsert = 4;
          while (toBeInsert < 7) begin  // [4,5,6]
            if (5 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (6 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          // third merge level 4v3 (0123 vs 456)
          i = 0;
          j = 4;
          toBeInsert = 0;
          while (toBeInsert < 7) begin  // [0,1,2,3,4,5,6]
            if (3 < i) begin
              ary2[toBeInsert] = ary1[j];
              w2[toBeInsert] = w1[j];
              j = j + 1;
            end else if (6 < j) begin
              ary2[toBeInsert] = ary1[i];
              w2[toBeInsert] = w1[i];
              i = i + 1;
            end else begin
              if (w1[i] < w1[j]) begin
                ary2[toBeInsert] = ary1[j];
                w2[toBeInsert] = w1[j];
                j = j + 1;
              end else begin
                ary2[toBeInsert] = ary1[i];
                w2[toBeInsert] = w1[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          OUT_character = {
            ary2[0], ary2[1], ary2[2], ary2[3], ary2[4], ary2[5], ary2[6]
          };
        end
      end
      8: begin : _27_34
        reg [3:0] ary0[0:7], ary1[0:7], ary2[0:7];
        reg [4:0] w0[0:7], w1[0:7], w2[0:7];

        always @(*) begin
          for (i = 0; i < 8; i = i + 1) begin
            ary0[i] = IN_character[4*(7-i)+:4];
            w0[i]   = IN_weight[5*(7-i)+:5];
          end

          // first merge level 1v1
          if (w0[0] < w0[1]) begin  // [0,1]
            {ary0[0], ary0[1]} = {ary0[1], ary0[0]};
            {w0[0], w0[1]} = {w0[1], w0[0]};
          end
          if (w0[2] < w0[3]) begin  // [2,3]
            {ary0[2], ary0[3]} = {ary0[3], ary0[2]};
            {w0[2], w0[3]} = {w0[3], w0[2]};
          end
          if (w0[4] < w0[5]) begin  // [4,5]
            {ary0[4], ary0[5]} = {ary0[5], ary0[4]};
            {w0[4], w0[5]} = {w0[5], w0[4]};
          end
          if (w0[6] < w0[7]) begin  // [6,7]
            {ary0[6], ary0[7]} = {ary0[7], ary0[6]};
            {w0[6], w0[7]} = {w0[7], w0[6]};
          end

          // second merge level 2v2
          i = 0;
          j = 2;
          toBeInsert = 0;
          while (toBeInsert < 4) begin  // [0,1,2,3]
            if (1 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (3 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          i = 4;
          j = 6;
          toBeInsert = 4;
          while (toBeInsert < 8) begin  // [4,5,6,7]
            if (5 < i) begin
              ary1[toBeInsert] = ary0[j];
              w1[toBeInsert] = w0[j];
              j = j + 1;
            end else if (7 < j) begin
              ary1[toBeInsert] = ary0[i];
              w1[toBeInsert] = w0[i];
              i = i + 1;
            end else begin
              if (w0[i] < w0[j]) begin
                ary1[toBeInsert] = ary0[j];
                w1[toBeInsert] = w0[j];
                j = j + 1;
              end else begin
                ary1[toBeInsert] = ary0[i];
                w1[toBeInsert] = w0[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          // third merge level 4v4 0123 vs 4567
          i = 0;
          j = 4;
          toBeInsert = 0;
          while (toBeInsert < 8) begin  // [0,1,2,3,4,5,6,7]
            if (3 < i) begin
              ary2[toBeInsert] = ary1[j];
              w2[toBeInsert] = w1[j];
              j = j + 1;
            end else if (7 < j) begin
              ary2[toBeInsert] = ary1[i];
              w2[toBeInsert] = w1[i];
              i = i + 1;
            end else begin
              if (w1[i] < w1[j]) begin
                ary2[toBeInsert] = ary1[j];
                w2[toBeInsert] = w1[j];
                j = j + 1;
              end else begin
                ary2[toBeInsert] = ary1[i];
                w2[toBeInsert] = w1[i];
                i = i + 1;
              end
            end
            toBeInsert = toBeInsert + 1;
          end

          OUT_character = {
            ary2[0],
            ary2[1],
            ary2[2],
            ary2[3],
            ary2[4],
            ary2[5],
            ary2[6],
            ary2[7]
          };
        end
      end
    endcase
  endgenerate
endmodule
