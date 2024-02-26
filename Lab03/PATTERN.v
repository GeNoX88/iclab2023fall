`ifdef RTL
`define CYCLE_TIME 40.0
`endif
`ifdef GATE
`define CYCLE_TIME 40.0
`endif

`include "../00_TESTBED/pseudo_DRAM.v"
`include "../00_TESTBED/pseudo_SD.v"

module PATTERN (
  // Input for design
  output reg clk,
  output reg rst_n,
  output reg in_valid,
  output reg direction,
  output reg [12:0] addr_dram,  // 0~8191
  output reg [15:0] addr_sd,  // 0~65535
  // Output for pattern
  input out_valid,
  input [7:0] out_data,
  // DRAM Signals
  // write address channel
  input AW_VALID,
  input [31:0] AW_ADDR,
  output AW_READY,
  // write data channel
  input W_VALID,
  input [63:0] W_DATA,
  output W_READY,
  // write response channel
  output B_VALID,
  output [1:0] B_RESP,
  input B_READY,
  // read address channel
  input AR_VALID,
  input [31:0] AR_ADDR,
  output AR_READY,
  // read data channel
  output R_VALID,
  output [63:0] R_DATA,
  input R_READY,
  output [1:0] R_RESP,
  // SD Signals
  input MOSI,
  output MISO
);
  // PATTERN的輸出有：
  // AR_READY
  // R_VALID
  // [63:0] R_DATA
  // [1:0] R_RESP
  // AW_READY
  // W_READY
  // B_VALID
  // [1:0] B_RESP
  // MISO

  real CYCLE = `CYCLE_TIME;
  integer pat_read;
  integer PAT_NUM;
  integer total_latency, latency;
  integer i_pat;
  integer out_valid_time;
  reg [63:0] DRAM_inP[0:8191];
  reg [63:0] SD_inP[0:65535];
  reg direg;
  reg [12:0] addr_dram_reg;  // 0~8191
  reg [15:0] addr_sd_reg;  // 0~65535
  reg [63:0] out_data_reg;
  always #(CYCLE / 2.0) clk = ~clk;  // 定義方波clock

  always @(negedge clk) begin  // SPEC MAIN-2
    if (out_valid === 0 && out_data !== 0) begin
      $display("              SPEC MAIN-2 FAIL");
      $display("out_data should be reset when your out_valid is low.");
      #(CYCLE) $finish();
    end
  end

  always @(negedge clk) begin  // SPEC MAIN-3
    if (latency > 10000) begin
      $display("              SPEC MAIN-3 FAIL");
      $display("The execution latency is limited in 10000 cycles.");
      $display("execution latency: %0d cycles", latency);
      $display("direction: %0d", direg);
      #(CYCLE) $finish();
    end
  end

  always @(negedge clk) begin  // SPEC MAIN-4
    if ((0<out_valid_time && out_valid_time<8 && out_valid !== 1) //太早降valid
      || (out_valid === 1 && out_valid_time == 9)) //拉到 9 cycle去了
      begin
      $display("              SPEC MAIN-4 FAIL");
      $display("out_valid and out_data must be asserted in exactly 8 cycles");
      $display("out_valid_time: %0d cycles", out_valid_time);
      $finish();
    end else if (out_valid === 1) out_valid_time = out_valid_time + 1;
    else out_valid_time = 0;
  end

  //*************** main program ***********************
  initial begin
    pat_read = $fopen("../00_TESTBED/Input.txt", "r");
    $readmemh("../00_TESTBED/DRAM_init.dat", DRAM_inP);  // 0~8191
    $readmemh("../00_TESTBED/SD_init.dat", SD_inP);  // 0~65535

    reset_signal_task;
    out_data_reg = 'x;
    addr_dram_reg = 'x;
    addr_sd_reg = 'x;
    i_pat = 0;
    total_latency = 0;
    $fscanf(pat_read, "%d",
            PAT_NUM);  // input.txt中第一行的數字就是pattern數
    for (i_pat = 1; i_pat <= PAT_NUM; i_pat = i_pat + 1) begin
      input_task;
      wait_out_valid_task;
      check_ans_task;
      $display("PASS PATTERN NO.%4d", i_pat);
    end
    $fclose(pat_read);

    $writememh("../00_TESTBED/DRAM_final.dat", u_DRAM.DRAM);
    $writememh("../00_TESTBED/SD_final.dat", u_SD.SD);
    YOU_PASS_task;
  end

  //***********************task 宣告專區*****************************
  task reset_signal_task;
    begin
      force clk = 0;
      rst_n = 1'b1;
      in_valid = 1'b0;
      direction = 1'bx;
      addr_dram = 13'dx;
      addr_sd = 16'dx;

      #(CYCLE) rst_n = 1'b0;
      #(2.5 * CYCLE);  // 等100ns
      if(out_valid!==0 || out_data!== 0 ||
         AW_ADDR!==0   || AW_VALID !==0 || 
         W_DATA!==0    || W_VALID!==0 ||
         B_READY!==0   ||
         AR_ADDR!==0   || AR_VALID!==0 ||
         R_READY!==0   || MOSI!==1)  // 共11個訊號
      begin
        $display("             SPEC MAIN-1 FAIL");
        $display("All outputs should be reset after rst_n is asserted.");
        #(CYCLE) $finish();
      end
      #(CYCLE) rst_n = 1'b1;
      #(3 * CYCLE);
      release clk;
    end
  endtask

  task input_task;
    begin
      @(negedge clk);
      $fscanf(pat_read, "%d", direction);
      $fscanf(pat_read, "%d", addr_dram);
      $fscanf(pat_read, "%d", addr_sd);
      in_valid = 1;
      if (direction == 0)  //DRAM讀 SD寫
        SD_inP[addr_sd] = DRAM_inP[addr_dram];
      else if (direction == 1)  // SD讀 DRAM寫
        // SD_inP[addr_sd] = DRAM_inP[addr_dram];
        DRAM_inP[addr_dram] = SD_inP[addr_sd];
      else begin
        $display("direction is not valid:%0d", direction);
        $finish();
      end
      if (addr_dram < 0 || 8191 < addr_dram) begin
        $display("addr_dram is not valid:%0d", addr_dram);
        $finish();
      end
      if (addr_sd < 0 || 65535 < addr_sd) begin
        $display("addr_sd is not valid:%0d", addr_sd);
        $finish();
      end
      @(negedge clk);
      direg = direction;
      direction = 'x;
      addr_dram_reg = addr_dram;
      addr_dram = 'x;
      addr_sd_reg = addr_sd;
      addr_sd = 'x;
      in_valid = 0;
      latency = 0;
    end
  endtask

  task wait_out_valid_task;
    begin
      while (out_valid !== 1) begin
        @(negedge clk);
        total_latency = total_latency + 1;
        latency = latency + 1;
      end
      if ((u_DRAM.DRAM[addr_dram_reg]!==DRAM_inP[addr_dram_reg]) ||
         (u_SD.SD[addr_sd_reg]!==SD_inP[addr_sd_reg])) begin
        $display("              SPEC MAIN-6 FAIL");
        $display(
          "The data in the DRAM and SD card should be correct when out_valid is high");
        $display("u_DRAM.DRAM[addr_dram_reg]:%20d", u_DRAM.DRAM[addr_dram_reg]);
        $display("DRAM_inP[addr_dram_reg]:   %20d", DRAM_inP[addr_dram_reg]);
        $display("u_SD.SD[addr_sd_reg]:      %20d", u_SD.SD[addr_sd_reg]);
        $display("SD_inP[addr_sd_reg]:       %20d", SD_inP[addr_sd_reg]);
        $finish();
      end
    end
  endtask

  task check_ans_task;
    integer i, head;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        head = 63 - i * 8;  // 63, 55, 47, 39, 31, 23, 15, 7
        // $display("head:%0d, direg: %0b, out_data:0x%0h, golden:0x%0h", head,
        //          direg, out_data, DRAM_inP[addr_dram_reg][head-:8]);
        if(out_valid===1 && 
        ((direg===0 && out_data !== DRAM_inP[addr_dram_reg][head-:8])
        || (direg===1 && out_data !== SD_inP[addr_sd_reg][head-:8]))) 
        begin
          $display("              SPEC MAIN-5 FAIL");
          $display("The out_data should be correct when out_valid is high");
          $display("head:%0d, direg: %0b, out_data:0x%0h, golden:0x%0h", head,
                   direg, out_data, DRAM_inP[addr_dram_reg][head-:8]);
          #(CYCLE) $finish();
        end
        @(negedge clk);
      end
      repeat ($urandom_range(0, 2)) @(negedge clk);
    end
  endtask

  task YOU_PASS_task;
    begin
      $display(
        "*************************************************************************");
      $display(
        "*                         Congratulations!                              *");
      $display("*                Your execution cycles = %5d cycles          *",
               total_latency);
      $display("*                Your clock period = %.1f ns          *",
               CYCLE);
      $display("*                Total Latency = %.1f ns          *",
               total_latency * CYCLE);
      $display(
        "*************************************************************************");
      $finish;
    end
  endtask

  pseudo_DRAM u_DRAM (
    .clk(clk),
    .rst_n(rst_n),
    // write address channel
    .AW_VALID(AW_VALID),
    .AW_ADDR(AW_ADDR),
    .AW_READY(AW_READY),
    // write data channel
    .W_VALID(W_VALID),
    .W_DATA(W_DATA),
    .W_READY(W_READY),
    // write response channel
    .B_VALID(B_VALID),
    .B_RESP(B_RESP),
    .B_READY(B_READY),
    // read address channel
    .AR_VALID(AR_VALID),
    .AR_ADDR(AR_ADDR),
    .AR_READY(AR_READY),
    // read data channel
    .R_VALID(R_VALID),
    .R_DATA(R_DATA),
    .R_RESP(R_RESP),
    .R_READY(R_READY)
  );

  pseudo_SD u_SD (
    .clk (clk),
    .MOSI(MOSI),
    .MISO(MISO)
  );

endmodule