module BRIDGE (
  //*******Input Signals*************
  input clk,
  input rst_n,
  input in_valid,
  input direction,
  input [12:0] addr_dram,
  input [15:0] addr_sd,
  //*********Output Signals************
  output reg out_valid,
  output reg [7:0] out_data,
  //******DRAM Signals********
  //Read Address Channel
  output reg AR_VALID,
  output reg [31:0] AR_ADDR,  // 0~8191
  input AR_READY,
  //Read Data Channel
  input R_VALID,
  output reg R_READY,
  input [63:0] R_DATA,
  input [1:0] R_RESP,
  //Write Address Channel
  output reg AW_VALID,
  output reg [31:0] AW_ADDR,  //0~8191
  input AW_READY,
  //Write Data Channel
  output reg W_VALID,
  input W_READY,
  output reg [63:0] W_DATA,
  // Write Response Channel
  input B_VALID,
  output reg B_READY,
  input [1:0] B_RESP,
  //********SD Signals************
  input MISO,
  output reg MOSI
);
  parameter IDEL = 0, DtoS = 1, StoD = 2;
  reg [1:0] state;
  // parameter DRAMing = 0, SDing = 1;
  // reg who;
  reg [31:0] addr_dram_reg;
  reg [31:0] addr_sd_reg;
  reg [63:0] data_reg;
  reg [6:0] SDcnt;
  reg [5:0] data_index;  // 63~0
  reg [3:0] crc16_index;  // 15~0
  reg inst_ok;
  reg [2:0] unit;
  reg [5:0] out_index;  // 63~0
  wire [6:0] crc7 = CRC7(
    {4'b0101, state == DtoS, 2'b00, state == StoD, addr_sd_reg}
  );
  wire [15:0] crc16 = CRC16_XMODEM(data_reg);

  //unit
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) unit <= 0;
    else begin
      if ((SDcnt == 74 && inst_ok == 1 && unit == 0) ||
          (SDcnt==73 && state==DtoS && crc16_index==0) ||
          (SDcnt == 75 && unit == 1 && MISO == 1))
        unit <= 0;
      else unit <= unit + 1;
    end
  end

  //state
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDEL;
    else if (state == IDEL && in_valid) state <= direction == 0 ? DtoS : StoD;
    else if ((SDcnt == 75 && unit == 0 && MISO == 1) || (B_READY & B_VALID))
      state <= IDEL;
    // else state <= IDEL;
  end
  //addr_dram_reg
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) addr_dram_reg <= 0;
    else if (state == IDEL && in_valid) addr_dram_reg <= {19'b0, addr_dram};
  end
  //addr_sd_reg
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) addr_sd_reg <= 0;
    else if (state == IDEL && in_valid) addr_sd_reg <= {16'b0, addr_sd};
  end
  //AR_VALID
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) AR_VALID <= 0;
    else if (AR_VALID & AR_READY) AR_VALID <= 0;
    else if (state == IDEL && in_valid && direction == 0) begin
      AR_VALID <= 1;
    end
  end
  //AR_ADDR
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) AR_ADDR <= 0;
    else if (AR_VALID & AR_READY) AR_ADDR <= 0;
    else if (state == IDEL && in_valid && direction == 0) begin
      AR_ADDR <= addr_dram;
    end
  end
  //R_READY
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) R_READY <= 0;
    else if (R_READY & R_VALID) R_READY <= 0;
    else if (AR_VALID & AR_READY) begin
      R_READY <= 1;
    end
  end
  // data_reg
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) data_reg <= 0;
    else if (R_READY & R_VALID) data_reg <= R_DATA;
    else if (SDcnt == 72 || SDcnt == 78) begin
      case (state)
        StoD: data_reg[data_index] <= MISO;
      endcase
    end
  end
  //AW_VALID
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) AW_VALID <= 0;
    else if (AW_VALID == 1 && AW_READY == 1) AW_VALID <= 0;
    else if (state == StoD && SDcnt == 79 && crc16_index == 0) begin
      AW_VALID <= 1;
    end
  end
  //AW_ADDR 
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) AW_ADDR <= 0;
    else if (AW_VALID == 1 && AW_READY == 1) AW_ADDR <= 0;
    else if (state == StoD && SDcnt == 79 && crc16_index == 0) begin
      AW_ADDR <= addr_dram_reg;
    end
  end
  //W_VALID
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) W_VALID <= 0;
    else if (W_VALID & W_READY) W_VALID <= 0;
    else if (AW_VALID & AW_READY) begin
      W_VALID <= 1;
    end
  end
  //W_DATA
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) W_DATA <= 0;
    else if (W_VALID & W_READY) W_DATA <= 0;
    else if (AW_VALID & AW_READY) begin
      W_DATA <= data_reg;
    end
  end
  //B_READY
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) B_READY <= 0;
    else if (B_READY & B_VALID) B_READY <= 0;
    else if (AW_VALID & AW_READY) B_READY <= 1;
  end

  //MOSI, SDcnt, inst_ok
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      MOSI <= 1;
      SDcnt <= 0;
      inst_ok <= 1;
    end else begin
      case (SDcnt)
        0: begin  // 拿到DRAM的數據||開始跟SD拿數據
          if ((R_READY && R_VALID) || (state==IDEL && in_valid && direction == 1)) begin
            MOSI  <= 0;  // start bit 0
            SDcnt <= SDcnt + 1;
          end
          inst_ok <= 1;
        end
        1: begin
          MOSI  <= 1;  // transmission bit 1
          SDcnt <= SDcnt + 1;
        end
        2: begin  // command的第一個bit
          MOSI  <= 0;
          SDcnt <= SDcnt + 1;
        end
        3: begin  // command的第二個bit
          MOSI  <= 1;
          SDcnt <= SDcnt + 1;
        end
        4: begin  // command的第三個bit
          if (state == DtoS) MOSI <= 1;  //011
          else if (state == StoD) MOSI <= 0;  //010
          SDcnt <= SDcnt + 1;
        end
        5: begin  // command的第四個bit
          MOSI  <= 0;
          SDcnt <= SDcnt + 1;
        end
        6: begin  // command的第五個bit
          MOSI  <= 0;
          SDcnt <= SDcnt + 1;
        end
        7: begin  // command的第六個bit
          if (state == DtoS) MOSI <= 0;  //011000
          else if (state == StoD) MOSI <= 1;  //010001
          SDcnt <= SDcnt + 1;
        end
        8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,
        24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39:
        begin // 傳address給SD
          MOSI  <= addr_sd_reg[39-SDcnt];  // 31~0
          SDcnt <= SDcnt + 1;
        end
        40, 41, 42, 43, 44, 45, 46: begin  //傳CRC-7給SD
          MOSI  <= crc7[46-SDcnt];  // 6~0
          SDcnt <= SDcnt + 1;
        end
        47: begin
          MOSI  <= 1;  //發End bit
          SDcnt <= SDcnt + 1;
        end
        48: begin
          // $display("SDcnt: %0d, MISO:%b", SDcnt, MISO);
          SDcnt <= SDcnt + 1;  //再等一個cycle讓SD降MISO
        end
        49, 50, 51, 52, 53, 54, 55, 56: begin  //接收SD resp 沒連8 low就失敗
          // $display("SDcnt: %0d, MISO:%b", SDcnt, MISO);
          if (SDcnt != 56) begin  // SDcnt < 56
            if (MISO == 1) inst_ok <= 0;
            SDcnt <= SDcnt + 1;
          end else begin  // SDcnt == 56
            case (state)
              DtoS: begin
                SDcnt   <= (inst_ok && !MISO) ? SDcnt + 1 : 49;
                inst_ok <= 1;
              end
              StoD: begin
                SDcnt   <= (inst_ok && !MISO) ? 77 : 49; // bridge收token的態在77
                inst_ok <= 1;
              end
            endcase
          end
          // MOSI此處會是1
        end
        // wait 1~32 units以後傳start token
        57, 58, 59, 60, 61, 62, 63: begin  //這邊我只等一個unit
          // $display("SDcnt: %0d, MOSI:%b", SDcnt, MOSI);
          SDcnt   <= SDcnt + 1;
          inst_ok <= 1;
          // MOSI此處會是1
        end
        64, 65, 66, 67, 68, 69, 70, 71: begin  // 收發start token
          // $display("SDcnt: %0d, MOSI:%b", SDcnt, MOSI);
          if (state == DtoS) begin  // 前面有等一個unit了，不用多等直接給
            MOSI  <= SDcnt == 71 ? 0 : 1;  // 8'b1111_1110
            SDcnt <= SDcnt + 1;
          end else if (state == StoD) begin  //再等0~31units
            if (SDcnt == 71) inst_ok <= 1;
            else if (MISO == 0) inst_ok <= 0;
            SDcnt <= (SDcnt == 71 && (!inst_ok | MISO)) ? 64 : SDcnt + 1;
            // MOSI此處會是1
          end
        end
        72: begin
          case (state)
            DtoS: MOSI <= data_reg[data_index];  // 寫
            // StoD: data_reg[data_index] <= MISO;  // 讀
          endcase
          if (data_index == 0) begin
            SDcnt <= SDcnt + 1;  //持續8cycles
          end
        end
        73: begin  // data block剛傳完，開始傳CRC16-XMODEM
          case (state)
            DtoS: begin  // 寫入CRC-16-XMODEM到SD
              MOSI <= crc16[crc16_index];
              SDcnt <= SDcnt + (crc16_index == 0);
              inst_ok <= 0;
            end
            StoD: begin  //接收SD傳來的正確CRC-16-XMODEM編碼
              if (crc16_index == 0) SDcnt <= 0;  // SD Read的終點
            end
          endcase
        end
        74: begin  // WRITE 要收data resp 8'b0000_0101
          MOSI <= 1;
          inst_ok <= 1;
          if (inst_ok == 1 && unit == 0) SDcnt <= SDcnt + 1;
        end
        75: begin  // busy是0
          if (unit == 0 && MISO == 1) begin  // 在該發現的edge發現busy結束
            SDcnt <= SDcnt + 1;
          end
        end
        76: begin
          if (out_index == 0) SDcnt <= 0;  // DtoS的out_data會輸出完
        end
        77: begin
          if (MISO == 0) SDcnt <= SDcnt + 1;
        end
        78: begin
          if (data_index == 0) begin
            SDcnt   <= SDcnt + 1;
            inst_ok <= 1;
          end
        end
        79: begin  // 吃CRC16-XMODEM
          inst_ok <= 0;
          if (!inst_ok && crc16_index == 0) SDcnt <= SDcnt + 1;  //會吃完
        end
        80: begin  //寫入DRAM
          if (B_VALID & B_READY) SDcnt <= SDcnt + 1;  //DRAM會寫入完
        end
        81: begin
          if (out_index == 0) SDcnt <= 0;  // DtoS的out_data會輸出完
        end
      endcase
    end
  end

  //out_data
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_data <= 0;
    else if (out_valid && out_index == 56) out_data <= 0;
    else if (
      (SDcnt == 75 && unit == 0 && MISO == 1) || 
      (SDcnt==76) || 
      (SDcnt == 80 && B_READY && B_VALID) || 
      (SDcnt==81))
      out_data <= data_reg[out_index+:8];
  end
  //out_valid
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_valid <= 0;
    else if (out_valid && out_index == 56) out_valid <= 0;
    else if ((SDcnt == 75 && unit == 0 && MISO == 1) || (B_READY & B_VALID))
      out_valid <= 1;
  end
  //out_index
  always @(posedge clk, negedge rst_n) begin
    if (!rst_n) out_index <= 0;
    else if (
    (SDcnt == 75 && unit == 0 && MISO == 1) || 
    SDcnt == 76 ||
    (B_VALID & B_READY) ||
    (SDcnt==81))
      out_index <= out_index - 8;
    else out_index <= 56;
  end
  // data block index
  always @(posedge clk) begin
    if (SDcnt == 71 || SDcnt == 77) data_index <= 63;
    else data_index <= data_index - 1;
  end
  // CRC16_XMODEM index
  always @(posedge clk) begin
    if ((SDcnt == 72 || SDcnt == 78) && data_index == 0) crc16_index <= 15;
    else crc16_index <= crc16_index - 1;
  end
  // Command (from host)
  // Start bit + transmission bit = 2’b01
  // Command: CMD17 = 6'd17|6'b010001(read), 6'd24|6'b011000(write)
  // Argument: 32 bits address
  // CRC: CRC-7 ({Start bit, Transmission bit, Command, Argument}) 40 bits input
  // End bit: 1’b1
  // (wait 0~8 units, units = 8 cycles)
  // Response (from SD card)
  // Response: 0x00 (8 bits)
  // (wait 1~32 units, units = 8 cycles)
  // Data (read:from SD card, write: from host)
  // Start token: 0xFE|8'b11111110 (8 bits)
  // Data block: 64 bits (differ from the original protocol)
  // CRC: CRC-16-XMODEM (Data block) // 64 bits input
  // 如果是write則繼續做下面
  // (wait 0 units, units = 8 cycles)
  // Data response (from SD card)
  // Data_response: 8’b00000101
  // Busy: keep low until finish write. (wait 0~32 units, units = 8 cycles)


  function automatic [6:0] CRC7;  // Return 7-bit result
    input [39:0] data;  // 40-bit data input
    reg [6:0] crc;
    integer i;
    reg data_in, data_out;
    parameter polynomial = 7'h9;  // x^7 + x^3 + 1
    begin
      crc = 7'd0;
      for (i = 0; i < 40; i = i + 1) begin
        data_in = data[39-i];
        data_out = crc[6];
        crc = crc << 1;  // Shift the CRC
        if (data_in ^ data_out) begin
          crc = crc ^ polynomial;
        end
      end
      CRC7 = crc;
    end
  endfunction
  function automatic [15:0] CRC16_XMODEM;
    input [63:0] data;  // 64-bit data input
    reg [15:0] crc;
    integer i, j, index;
    reg out_bit;
    parameter polynomial = 16'h1021;  // x^16 + x^12 + x^5 + 1
    begin
      crc = 16'h0000;
      for (i = 0; i < 8; i = i + 1) begin  //把8個byte都處理完
        index = 63 - i * 8;  // 63, 55, 47, 39, ..., 7
        crc[15:8] = data[index-:8] ^ crc[15:8];
        for (j = 0; j < 8; j = j + 1) begin  //右移8位
          out_bit = crc[15];
          crc = crc << 1;
          if (out_bit === 1'b1) crc = crc ^ polynomial;
        end
      end
      // crc = {crc[7:0], crc[15:8]}; // CCITT
      CRC16_XMODEM = crc;
    end
  endfunction
endmodule


//   // Input Signals
//   input clk, rst_n;
//   input in_valid;
//   input direction;
//   input [12:0] addr_dram;
//   input [15:0] addr_sd;

//   // Output Signals
//   output reg out_valid;
//   output reg [7:0] out_data;

//   // DRAM Signals
//   // write address channel
//   output reg [31:0] AW_ADDR;
//   output reg AW_VALID;
//   input AW_READY;
//   // write data channel
//   output reg W_VALID;
//   output reg [63:0] W_DATA;
//   input W_READY;
//   // write response channel
//   input B_VALID;
//   input [1:0] B_RESP;
//   output reg B_READY;
//   // read address channel
//   output reg [31:0] AR_ADDR;
//   output reg AR_VALID;
//   input AR_READY;
//   // read data channel
//   input [63:0] R_DATA;
//   input R_VALID;
//   input [1:0] R_RESP;
//   output reg R_READY;

//   // SD Signals
//   input MISO;
//   output reg MOSI;
