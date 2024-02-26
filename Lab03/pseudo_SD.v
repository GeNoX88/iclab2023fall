module pseudo_SD (
    input clk,
    input MOSI,  // active low
    output reg MISO  // active low
);
  integer i, j, unit_num;
  real CYCLE = 40.0;
  reg [5:0] Command;
  reg rw;
  reg [31:0] Argument;
  reg [6:0] crc7;
  reg [15:0] crc16;
  reg [63:0] SD[0:65535];
  reg [63:0] SD_reg;
  reg [7:0] SD_shift;
  parameter READ = 6'd17, WRITE = 6'd24;
  initial $readmemh("../00_TESTBED/SD_init.dat", SD);

  // Command (from host)
  //    Start bit + transmission bit = 2’b01
  //    Command: CMD17 = 6'd17|6'b010001(read), 6'd24|6'b011000(write)
  //    Argument: 32 bits address
  //    CRC: CRC-7 ({Start bit, Transmission bit, Command, Argument}) 40 bits input
  //    End bit: 1’b1
  // (wait 0~8 units, units = 8 cycles)
  // Response: 0x00 (8 bits)(from SD card)
  // (wait 1~32 units, units = 8 cycles)
  // Data (read:from SD card, write: from host)
  //    Start token: 0xFE|8'b11111110 (8 bits)
  //    Data block: 64 bits (differ from the original protocol)
  //    CRC: CRC-16-XMODEM (Data block) // 64 bits input

  // 如果是write則繼續做下面
  // (wait 0 units, units = 8 cycles)
  // Data response (from SD card)
  // Data_response: 8’b00000101
  // Busy: keep low until finish write. (wait 0~32 units, units = 8 cycles)

  initial begin
    MISO = 1'b1;
    while (1) begin
      Command = 'x;
      Argument = 'x;
      rw = 1'bx;
      crc7 = 'x;
      crc16 = 'x;
      //**************** Command *******************************
      @(posedge clk);
      if (MOSI !== 0) continue;  //等到出現0為止(start bit
      while (1) begin
        @(posedge clk);
        if (MOSI === 0) continue;
        else if (MOSI === 1) break;
      end

      for (i = 0; i < 6; i = i + 1) begin
        @(posedge clk);
        Command[5-i] = MOSI;
      end
      // 確認command合不合法
      if (Command === READ) rw = 0;  // SD要讀
      else if (Command === WRITE) rw = 1;  // SD要寫
      else begin
        $display("              SPEC SD-1 FAIL");
        $display("command is illegal: %0d", Command);
        #(CYCLE) $finish();
      end
      // $display("SD has received command %0d (0b%0b)", Command, Command);

      for (i = 0; i < 16; i = i + 1) begin  //吃address高16位
        @(posedge clk);
        Argument[31-i] = MOSI;
      end
      // 確認argument高位的16位是不是全0
      if (Argument[31:16] !== 0) begin
        $display("              SPEC SD-2 FAIL");
        $display("The address should be within the legal range (0~65535).");
        #(CYCLE) $finish();
      end
      for (i = 0; i < 16; i = i + 1) begin  //吃address低16位
        @(posedge clk);
        Argument[15-i] = MOSI;
      end
      // $display("SD has received argument %0d (0b%0b)", Argument, Argument);

      for (i = 0; i < 7; i = i + 1) begin
        @(posedge clk);
        crc7[6-i] = MOSI;
      end
      // 檢查crc7編碼對不對
      if (crc7 !== CRC7({1'b0, 1'b1, Command, Argument})) begin
        $display("              SPEC SD-3 FAIL");
        $display("CRC-7 check should be correct.");
        $display("Should be 0b%0b, get 0b%0b.", CRC7({1'b0, 1'b1, Command,
                                                      Argument}), crc7);
        #(CYCLE) $finish();
      end
      @(posedge clk);
      if (MOSI !== 1'b1) begin  // 檢查End bit有沒有給對
        $display("              SPEC SD-1 FAIL");
        $display("End bit in Command is illegal: %0d", MOSI);
        #(CYCLE) $finish();
      end
      //************** Response *************************
      repeat ($urandom_range(
          0, 8
      ) * 8)
      @(posedge clk);  // 拉高維持0~8 units
      MISO = 0;  // 降成0
      repeat (8) @(posedge clk);  // 讓bridge吃到0x00
      MISO = 1;  // 回到1

      //*************** Data block ***********************
      if (rw === 0) begin  //讀的部分
        unit_num = $urandom_range(1, 32);
        repeat (unit_num * 8) @(posedge clk);  // SD wait 1~32 units
        repeat (7) @(posedge clk);  // 發7個1
        MISO = 0;  // 發1個0作結尾
        for (i = 0; i < 64; i = i + 1) begin  //發data
          @(posedge clk);
          MISO = SD[Argument[15:0]][63-i];
        end
        crc16 = CRC16_XMODEM(SD[Argument[15:0]]);
        for (i = 0; i < 16; i = i + 1) begin  //發CRC16
          @(posedge clk);
          MISO = crc16[15-i];
        end
        @(posedge clk);
        MISO = 1;
      end else if (rw === 1) begin  //寫的部分
        // wait 1~32 units
        repeat (8) @(posedge clk);  // 先等一個unit
        for (
            i = 0; i < 32; i = i + 1
        ) begin  // bridgeSD再等(1-1=0)~(32-1=31) units (bridge決定)
          //******** 檢查8 cycles看有無符合start token *************************
          for (j = 0; j < 7; j = j + 1) begin  // 收7個1
            @(posedge clk);
            // $display("i:%0d, j:%0d, 在start token前7bit中SD吃到:%0b", i,
            //          j, MOSI);
            if (MOSI !== 1) begin
              $display("              SPEC SD-5 FAIL");
              $display("Time between each transmission should be correct.");
              $display(
                  "0 of start token from bridge appears in illegal timing(%8b)",
                  SD_shift);
              $finish();
            end
          end
          @(posedge clk);  //收末位
          // $display("for之後 SD吃到start token末位:%0b", MOSI);
          if (MOSI === 0) begin
            // if (i == 0) $display("SD只等一個unit就拿到11111110");
            break;  // unit的尾收到0表示已收到start token
          end else if (i == 31 && MOSI === 1) begin
            // 已等了1+(i=0~30)=32units，所以i=31一定要對
            $display("              SPEC SD-5 FAIL");
            $display("in i=31 for-loop round, still not get 0xFE token");
            $finish();
          end
          //****************************************
        end
        for (i = 0; i < 64; i = i + 1) begin  // 收data
          @(posedge clk);
          // $display("data第%0d個bit是%0b", i + 1, MOSI);
          SD_reg[63-i] = MOSI;
        end
        for (i = 0; i < 16; i = i + 1) begin  // 吃CRC16-XMODEM
          @(posedge clk);
          // $display("crc16第%0d個bit是%0b", i + 1, MOSI);
          crc16[15-i] = MOSI;
        end
        if (crc16 !== CRC16_XMODEM(SD_reg)) begin
          $display("              SPEC SD-4 FAIL");
          $display("CRC16-XMODEM from BRIDGE is illegal");
          $display(
              "64bit data: 0x%0h => CRC16-XMODEM should be 0x%0h, get 0x%0h",
              SD[Argument[15:0]], CRC16_XMODEM(SD[Argument[15:0]]), crc16);
          $display(
              "64bit data: 0x%0b => CRC16-XMODEM sbould be 0x%0b, get 0x%0b",
              SD[Argument[15:0]], CRC16_XMODEM(SD[Argument[15:0]]), crc16);
          #(CYCLE) $finish();
        end
        MISO = 0;
        repeat (5) @(posedge clk);  // 5個0
        MISO = 1;
        @(posedge clk);  // 1個1
        MISO = 0;
        @(posedge clk);  // 1個0
        MISO = 1;
        @(posedge clk);  // 1個1

        MISO = 0;
        repeat ($urandom_range(0, 32) * 8) @(posedge clk);  // Busy: 0~32 units
        SD[Argument[15:0]] = SD_reg;
      end
      MISO = 1;
      //*************************************************
    end
  end

  always @(posedge clk) begin
    SD_shift = {SD_shift, MOSI};
  end
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
