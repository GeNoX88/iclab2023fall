module Train (
  //Input Port
  input clk,
  input rst_n,
  input in_valid,
  input [3:0] data,
  //Output Port
  output reg out_valid,
  output reg result
);
  parameter IDLE = 0, EAT = 1, CALC = 2;
  integer i;
  reg [1:0] state;
  reg [3:0] eat_idx;
  reg [3:0] num;  // 3 ~ 10
  reg [3:0] Aleft;
  reg [3:0] ptr, target_ptr;  // 0 ~ 9
  reg [3:0] stack[0:9];
  reg [3:0] target[0:9];

  // 3 ~ 10 tracks => no.1 ~ no.N

  // state
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else begin
      case (1)
        out_valid: state <= IDLE;
        state == EAT: if (!in_valid) state <= CALC;
        state == IDLE: if (in_valid) state <= EAT;
        default: state <= state;
      endcase
    end
  end


  // eat_idx  - 0 eat num, 1 eat target[0], 2 eat target[1], ..., num eat target[num-1]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) eat_idx <= 0;
    else begin
      case (1)
        in_valid: eat_idx <= eat_idx + 1;
        state == IDLE: eat_idx <= 0;
        default: eat_idx <= 0;
      endcase
    end
  end

  // num  - number of tracks
  always @(posedge clk) begin
    if (state == IDLE && in_valid) num <= data;
  end

  // target[0:9]
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) for (i = 0; i < 10; i = i + 1) target[i] <= 0;
    else
      case (1)
        state == EAT && in_valid: target[eat_idx-1] <= data;  // [0] ~ [num-1]
        state == IDLE: for (i = 0; i < 10; i = i + 1) target[i] <= 0;
      endcase
  end

  // stack[0:9], ptr, Aleft, target_ptr
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      Aleft <= 1;
      for (i = 0; i < 10; i = i + 1) stack[i] <= 0;
      ptr <= 0;
      target_ptr <= 0;
    end else if(state==IDLE) begin
      Aleft <= 1;
      for (i = 0; i < 10; i = i + 1) stack[i] <= 0;
      ptr <= 0;
      target_ptr <= 0;
    end else if (state == CALC) begin
      if (target[target_ptr] >= Aleft) begin  // in A => push
        stack[ptr] <= Aleft;
        ptr <= ptr + 1;  // go to empty one
        Aleft <= Aleft + 1;
      end else begin  // already in station => pop
        // if (target[target_ptr] == stack[ptr-1]) begin  // pop
        target_ptr <= target_ptr + 1;
        stack[ptr-1] <= 0;
        ptr <= ptr - 1;
      end
    end
  end
  // // target_ptr
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) target_ptr <= 0;
  //   else
  //   if (state == CALC) begin

  //   end else if (state == IDLE) target_ptr <= 0;
  // end

  // // Aleft
  // always @(posedge clk, negedge rst_n) begin
  //   if (!rst_n) Aleft <= 1;
  //   else begin

  //   end
  // end

  // out_valid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (out_valid) out_valid <= 0;
    else if (state == CALC) begin
      if (target_ptr == num - 1 && target[target_ptr] == stack[ptr-1])
        out_valid <= 1;
      else if (target[target_ptr] < Aleft &&  // in station
        target[target_ptr] != stack[ptr-1]) begin  // stack fail
        out_valid <= 1;
      end
    end
  end

  // result
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) result <= 0;
    else if (out_valid) result <= 0;
    else if (state == CALC) begin
      if (target_ptr == num - 1 && target[target_ptr] == stack[ptr-1])
        result <= 1;
      else if (target[target_ptr] < Aleft &&  // in station
        target[target_ptr] != stack[ptr-1]  // stack fail
        ) begin
        result <= 0;
      end
    end
  end

endmodule
