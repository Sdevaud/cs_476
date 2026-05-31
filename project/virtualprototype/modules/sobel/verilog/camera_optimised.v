module camera #(parameter [7:0] customInstructionId = 8'd0,
                parameter clockFrequencyInHz = 2000)
               (input wire         clock,
                                   pclk,
                                   reset,
                                   hsync,
                                   vsync,
                                   ciStart,
                                   ciCke,
                input wire [7:0]   ciN,
                                   camData,
                input wire [31:0]  ciValueA,
                                   ciValueB,
                output wire [31:0] ciResult,
                output wire        ciDone,
                // here the bus master interface is defined
                output wire        requestBus,
                input wire         busGrant,
                output reg         beginTransactionOut,
                output wire [31:0] addressDataOut,
                output reg         endTransactionOut,
                output reg  [3:0]  byteEnablesOut,
                output wire        dataValidOut,
                output reg  [7:0]  burstSizeOut,
                input wire         busyIn,
                                   busErrorIn);

  /*
   *
   * this module provides an interface to the OV7670 camera module
   *
   * different ci commands:
   * ciValueA:    Description:
   *     0        Read Nr. of Bytes per line
   *     1        Read Nr. of Lines per image
   *     2        Read PCLK frequency in kHz
   *     3        Read Frames per second (wait at least 2 s after initializing the camera for a valid value)
   *     4        Read frame buffer address
   *     5        Write frame buffer address (ciValueB)
   *     6        Start/stop image aquisition (ciValueb[1..0] = "01")
   *     6        Take single image (ciValueb[1..0] = "10")
   *     7        Read (self clearing): Single image grabbing done.
   *     8        Read Sobel threshold
   *     9        Write Sobel threshold (ciValueB[7..0])
   *
   */

  reg [1:0] s_singleShotActionReg;

  function integer clog2;
    input integer value;
    begin
      for (clog2 = 0; value > 0 ; clog2= clog2 + 1)
      value = value >> 1;
    end
  endfunction
  
  localparam khzDivideValue = clockFrequencyInHz/1000;
  localparam khzNrOfBits = clog2(khzDivideValue);
  localparam [2:0] IDLE         = 3'd0;
  localparam [2:0] REQUEST_BUS1 = 3'd1;
  localparam [2:0] INIT_BURST1  = 3'd2;
  localparam [2:0] DO_BURST1    = 3'd3;
  localparam [2:0] END_TRANS1   = 3'd4;
  localparam [2:0] END_TRANS2   = 3'd5;
  
  reg [2:0] s_stateMachineReg, s_stateMachineNext;
  reg s_singleShotDoneReg;
  
  wire s_isMyCi = (ciN == customInstructionId) ? ciStart & ciCke : 1'b0;
  /*
   *
   * Here we define the counters for the 1KHz pulse and 1Hz pulse
   *
   */
  reg [khzNrOfBits-1:0] s_khzCountReg;
  reg [9:0] s_hzCountReg;
  wire s_khzCountZero = (s_khzCountReg == {khzNrOfBits{1'b0}}) ? 1'b1 : 1'b0;
  wire s_hzCountZero  = (s_hzCountReg == 10'd0) ? s_khzCountZero : 1'b0;
  wire [khzNrOfBits-1:0] s_khzCountNext = (reset == 1'b1 || s_khzCountZero == 1'b1) ? khzDivideValue - 1 : s_khzCountReg - 1;
  wire [9:0] s_hzCountNext = (reset == 1'b1 || s_hzCountZero == 1'b1) ? 10'd999 : (s_khzCountZero == 1'b1) ? s_hzCountReg - 10'd1 : s_hzCountReg;
  
  always @(posedge clock)
    begin
      s_khzCountReg <= s_khzCountNext;
      s_hzCountReg  <= s_hzCountNext;
    end
  
  /*
   *
   * Here we define the frame buffer parameters
   *
   */
  reg[31:0] s_frameBufferBaseReg;
  reg s_grabberActiveReg,s_grabberSingleShotReg;
  
  always @(posedge clock)
    begin
      s_frameBufferBaseReg   <= (reset == 1'b1) ? 32'd0 : (s_isMyCi == 1'b1 && ciValueA[3:0] == 4'd5) ? {ciValueB[31:2],2'd0} : s_frameBufferBaseReg;
      s_grabberActiveReg     <= (reset == 1'b1) ? 1'b0 : (s_isMyCi == 1'b1 && ciValueA[3:0] == 4'd6) ? ciValueB[0]& ~ciValueB[1] : s_grabberActiveReg;
      s_grabberSingleShotReg <= (reset == 1'b1 || s_singleShotActionReg[0] == 1'b1) ? 1'b0 : (s_isMyCi == 1'b1 && ciValueA[3:0] == 4'd6) ? ciValueB[1]& ~ciValueB[0] : s_grabberSingleShotReg;
    end

  /* ==== Added by Till ====
   *
   * Here we add the threshold parameter used by the Sobel operator (default: 128)
   *
   */

  reg [7:0] s_sobelThresholdReg;
  always @(posedge clock)
    begin
      s_sobelThresholdReg <= (reset == 1'b1) ? 8'd128 : (s_isMyCi == 1'b1 && ciValueA[3:0] == 4'd9) ? ciValueB[7:0] : s_sobelThresholdReg;
    end
  
  /*
   *
   * Here we do the measurements on the camera interface
   *
   */
  reg[1:0]  s_vsyncDetectReg;
  reg[1:0]  s_hsyncDetectReg;
  reg[10:0] s_pixelCountReg, s_pixelCountValueReg;
  reg[10:0] s_lineCountReg, s_lineCountValueReg;
  reg[16:0] s_pclkCountReg, s_pclkCountValueReg;
  reg[7:0]  s_fpsCountReg, s_fpsCountValueReg;
  wire      s_clockPclkValue, s_clockFPS;
  
  wire s_vsyncNegEdge = ~s_vsyncDetectReg[0] & s_vsyncDetectReg[1];
  wire s_hsyncNegEdge = ~s_hsyncDetectReg[0] & s_hsyncDetectReg[1];
  
  always @(posedge pclk)
    begin
      s_vsyncDetectReg     <= {s_vsyncDetectReg[0],vsync};
      s_hsyncDetectReg     <= {s_hsyncDetectReg[0],hsync};
      s_pixelCountValueReg <= (s_hsyncNegEdge == 1'b1) ? s_pixelCountReg : s_pixelCountValueReg;
      s_pixelCountReg      <= (s_hsyncNegEdge == 1'b1) ? 11'd0 : (hsync == 1'b1) ? s_pixelCountReg + 11'd1 : s_pixelCountReg;
      s_lineCountValueReg  <= (s_vsyncNegEdge == 1'b1) ? s_lineCountReg : s_lineCountValueReg;
      s_lineCountReg       <= (s_vsyncNegEdge == 1'b1) ? 11'd0 : (s_hsyncNegEdge == 1'b1) ? s_lineCountReg + 11'd1 : s_lineCountReg;
      s_pclkCountReg       <= (reset == 1'b1 || s_clockPclkValue == 1'b1) ? 17'd0 : s_pclkCountReg + 17'd1;
      s_pclkCountValueReg  <= (reset == 1'b1) ? 17'd0 : (s_clockPclkValue == 1'b1) ? s_pclkCountReg : s_pclkCountValueReg;
      s_fpsCountReg        <= (reset == 1'b1 || s_clockFPS == 1'b1) ? 8'd0 : (s_vsyncNegEdge == 1'b1) ? s_fpsCountReg + 8'd1 : s_fpsCountReg;
      s_fpsCountValueReg   <= (reset == 1'b1) ? 8'd0 : (s_clockFPS == 1'b1) ? s_fpsCountReg : s_fpsCountValueReg;
    end
  
   synchroFlop spclk ( .clockIn(clock),
                       .clockOut(pclk),
                       .reset(reset),
                       .D(s_khzCountZero),
                       .Q(s_clockPclkValue) );
   synchroFlop sfps ( .clockIn(clock),
                      .clockOut(pclk),
                      .reset(reset),
                      .D(s_hzCountZero),
                      .Q(s_clockFPS) );
  /*
   *
   * here the ci interface is defined
   *
   */
  reg [31:0] s_selectedResult;
  
  assign ciDone   = s_isMyCi;
  assign ciResult = (s_isMyCi == 1'b0) ? 32'd0 : s_selectedResult;

  always @*
    case (ciValueA[3:0])
      4'd0    : s_selectedResult <= {21'd0,s_pixelCountValueReg};
      4'd1    : s_selectedResult <= {21'd0,s_lineCountValueReg};
      4'd2    : s_selectedResult <= {15'd0,s_pclkCountValueReg};
      4'd3    : s_selectedResult <= {24'd0,s_fpsCountValueReg};
      4'd4    : s_selectedResult <= s_frameBufferBaseReg;
      4'd7    : s_selectedResult <= {31'd0,s_singleShotDoneReg};
      4'd8    : s_selectedResult <= {24'd0, s_sobelThresholdReg};
      default : s_selectedResult <= 32'd0;
    endcase

  /*
   *
   * Here the grabber is defined
   *
   */
  reg [7:0] s_byte7Reg, s_byte6Reg,s_byte5Reg,s_byte4Reg, s_byte3Reg,s_byte2Reg,s_byte1Reg,s_byte0Reg;
  reg [8:0] s_busSelectReg;
  wire [31:0] s_busPixelWord;


  wire [7:0] gray0, gray1, gray2, gray3;
  rgb565Grayscale Gray0 (.rgb565({s_byte7Reg, s_byte6Reg}),
                         .grayscale(gray0));
  rgb565Grayscale Gray1 (.rgb565({s_byte5Reg, s_byte4Reg}),
                          .grayscale(gray1));
  rgb565Grayscale Gray2 (.rgb565({s_byte3Reg, s_byte2Reg}),
                         .grayscale(gray2));
  rgb565Grayscale Gray3 (.rgb565({s_byte1Reg, s_byte0Reg}),
                          .grayscale(gray3));                        

  // Convert again into RGB565 format but grayscale
  wire [31:0] s_grayscalePixelWord = {gray3, gray2, gray1, gray0}; 
  /* =======================*/
  wire [2:0] subPixelCount = s_pixelCountReg[2:0];
  wire s_weLineBuffer = (s_pixelCountReg[2:0] == 3'b111) ? hsync : 1'b0;
  
  always @(posedge pclk)
    begin
      s_byte7Reg <= (subPixelCount == 3'b000 && hsync == 1'b1) ? camData : s_byte7Reg;
      s_byte6Reg <= (subPixelCount == 3'b001 && hsync == 1'b1) ? camData : s_byte6Reg;
      s_byte5Reg <= (subPixelCount == 3'b010 && hsync == 1'b1) ? camData : s_byte5Reg;
      s_byte4Reg <= (subPixelCount == 3'b011 && hsync == 1'b1) ? camData : s_byte4Reg;
      s_byte3Reg <= (subPixelCount == 3'b100 && hsync == 1'b1) ? camData : s_byte3Reg;
      s_byte2Reg <= (subPixelCount == 3'b101 && hsync == 1'b1) ? camData : s_byte2Reg;
      s_byte1Reg <= (subPixelCount == 3'b110 && hsync == 1'b1) ? camData : s_byte1Reg;
      s_byte0Reg <= (subPixelCount == 3'b111 && hsync == 1'b1) ? camData : s_byte0Reg;
    end

  // circular selection of the 3 line buffers
  reg [1:0] writeLineReg;
  reg [1:0] midLineReg;
  reg [1:0] topLineReg;

  wire [1:0] nextWriteLine = (writeLineReg == 2'd0) ? 2'd2 : writeLineReg - 2'd1;
  wire [1:0] nextMidLine   = (midLineReg   == 2'd0) ? 2'd2 : midLineReg   - 2'd1;
  wire [1:0] nextTopLine   = (topLineReg   == 2'd0) ? 2'd2 : topLineReg   - 2'd1;

  always @(posedge pclk)
    begin
      if (reset == 1'b1 || s_vsyncNegEdge == 1'b1)
        begin
          writeLineReg <= 2'd0;
          midLineReg   <= 2'd1;
          topLineReg   <= 2'd2;
        end
      else if (s_hsyncNegEdge == 1'b1)
        begin
          writeLineReg <= nextWriteLine;
          midLineReg   <= nextMidLine;
          topLineReg   <= nextTopLine;
        end
    end


  // write grayscale words into the selected line buffer
  wire writeGrayWord = hsync && (subPixelCount == 3'b111);

  reg       weLine0Reg;
  reg       weLine1Reg;
  reg       weLine2Reg;
  reg [7:0] lineAddressReg;

  always @(posedge pclk)
    begin
      weLine0Reg    <= writeGrayWord && (writeLineReg == 2'd0);
      weLine1Reg    <= writeGrayWord && (writeLineReg == 2'd1);
      weLine2Reg    <= writeGrayWord && (writeLineReg == 2'd2);
      lineAddressReg <= s_pixelCountReg[10:3];
    end

  wire [31:0] line0Word;
  wire [31:0] line1Word;
  wire [31:0] line2Word;

  // we load 3 full line for computing the 3x3 Sobel window

  dualPortRam640 lineBuffer0 (
    .address1    (lineAddressReg),
    .address2    (lineAddressReg),
    .clock1      (pclk),
    .clock2      (pclk),
    .writeEnable (weLine0Reg),
    .dataIn1     (s_grayscalePixelWord),
    .dataOut2    (line0Word)
  );

  dualPortRam640 lineBuffer1 (
    .address1    (lineAddressReg),
    .address2    (lineAddressReg),
    .clock1      (pclk),
    .clock2      (pclk),
    .writeEnable (weLine1Reg),
    .dataIn1     (s_grayscalePixelWord),
    .dataOut2    (line1Word)
  );

  dualPortRam640 lineBuffer2 (
    .address1    (lineAddressReg),
    .address2    (lineAddressReg),
    .clock1      (pclk),
    .clock2      (pclk),
    .writeEnable (weLine2Reg),
    .dataIn1     (s_grayscalePixelWord),
    .dataOut2    (line2Word)
  );


  // select the two previous lines
  wire [31:0] midLineWord = (midLineReg == 2'd0) ? line0Word :
                            (midLineReg == 2'd1) ? line1Word :
                                                    line2Word;

  wire [31:0] topLineWord = (topLineReg == 2'd0) ? line0Word :
                            (topLineReg == 2'd1) ? line1Word :
                                                    line2Word;


  // select one pixel inside the current 32-bit word
  reg [1:0] pixelSelectReg;

  always @(posedge pclk)
    pixelSelectReg <= s_pixelCountReg[2:1];

  wire [7:0] camGrayPixel = (pixelSelectReg == 2'd0) ? gray0 :
                            (pixelSelectReg == 2'd1) ? gray1 :
                            (pixelSelectReg == 2'd2) ? gray2 :
                                                        gray3;

  wire [7:0] midGrayPixel = (pixelSelectReg == 2'd0) ? midLineWord[7:0]   :
                            (pixelSelectReg == 2'd1) ? midLineWord[15:8]  :
                            (pixelSelectReg == 2'd2) ? midLineWord[23:16] :
                                                        midLineWord[31:24];

  wire [7:0] topGrayPixel = (pixelSelectReg == 2'd0) ? topLineWord[7:0]   :
                            (pixelSelectReg == 2'd1) ? topLineWord[15:8]  :
                            (pixelSelectReg == 2'd2) ? topLineWord[23:16] :
                                                        topLineWord[31:24];


  // 3x3 Sobel window
  reg [7:0] p11Reg, p12Reg, p13Reg;
  reg [7:0] p21Reg, p22Reg, p23Reg;
  reg [7:0] p31Reg, p32Reg, p33Reg;

  reg shiftWindowReg;

  always @(posedge pclk)
    shiftWindowReg <= hsync && s_pixelCountReg[0];

  always @(posedge pclk)
    begin
      if (shiftWindowReg == 1'b1)
        begin
          p11Reg <= p12Reg;
          p12Reg <= p13Reg;
          p13Reg <= topGrayPixel;

          p21Reg <= p22Reg;
          p22Reg <= p23Reg;
          p23Reg <= midGrayPixel;

          p31Reg <= p32Reg;
          p32Reg <= p33Reg;
          p33Reg <= camGrayPixel;
        end
    end


  wire [10:0] sobelThreshold = {5'd0, s_sobelThresholdReg};
  wire [7:0]  sobelResult;

  sobelCompute sobel(
    .p11             (p11Reg),
    .p12             (p12Reg),
    .p13             (p13Reg),
    .p21             (p21Reg),
    .p23             (p23Reg),
    .p31             (p31Reg),
    .p32             (p32Reg),
    .p33             (p33Reg),

    .s_lineCountReg  (s_lineCountReg),
    .s_pixelCountReg (s_pixelCountReg),
    .thresholdValue  (sobelThreshold),

    .sobelResult     (sobelResult)
  );


  // pack 4 Sobel results
  reg [7:0] sobel0Reg;
  reg [7:0] sobel1Reg;
  reg [7:0] sobel2Reg;
  reg [7:0] sobel3Reg;

  always @(posedge pclk)
    begin
      sobel0Reg <= (pixelSelectReg == 2'd1) ? sobelResult : sobel0Reg;
      sobel1Reg <= (pixelSelectReg == 2'd2) ? sobelResult : sobel1Reg;
      sobel2Reg <= (pixelSelectReg == 2'd3) ? sobelResult : sobel2Reg;
      sobel3Reg <= (pixelSelectReg == 2'd0) ? sobelResult : sobel3Reg;
    end

  wire [31:0] sobelWord = {sobel3Reg, sobel2Reg, sobel1Reg, sobel0Reg};


  // delayed write to output RAM
  reg       sobelWeDelay0Reg;
  reg       sobelWeDelay1Reg;
  reg       sobelWeDelay2Reg;
  reg [8:0] sobelWriteAddressReg;

  always @(posedge pclk)
    begin
      sobelWeDelay0Reg <= (pixelSelectReg == 2'd3);
      sobelWeDelay1Reg <= sobelWeDelay0Reg;
      sobelWeDelay2Reg <= sobelWeDelay1Reg;

      sobelWriteAddressReg <= (pixelSelectReg == 2'd3) ? s_pixelCountReg[10:3] - 1'b1
                                                       : sobelWriteAddressReg;
    end


  dualPortRam2k lineBuffer(
    .address1    (sobelWriteAddressReg),
    .address2    (s_busSelectReg),
    .clock1      (pclk),
    .clock2      (clock),
    .writeEnable (sobelWeDelay2Reg),
    .dataIn1     (sobelWord),
    .dataOut2    (s_busPixelWord)
  );

  /*
   *
   * Here the bus interface is defined
   *
   */
  reg [31:0] s_busAddressReg, s_addressDataOutReg;
  reg [8:0] s_nrOfPixelsPerLineReg;

  reg s_dataValidReg;
  reg [8:0] s_burstCountReg;
  reg  s_grabberRunningReg;
  wire s_newScreen, s_newLine;
  wire s_doWrite = ((s_stateMachineReg == DO_BURST1) && s_burstCountReg[8] == 1'b0) ? ~busyIn : 1'b0;
  wire [31:0] s_busAddressNext = (reset == 1'b1 || s_newScreen == 1'b1) ? s_frameBufferBaseReg : 
                                 (s_doWrite == 1'b1) ? s_busAddressReg + 32'd4 : s_busAddressReg;
  wire [7:0] s_burstSizeNext = ((s_stateMachineReg == INIT_BURST1) && s_nrOfPixelsPerLineReg > 9'd16) ? 8'd16 : s_nrOfPixelsPerLineReg[7:0];
  
  assign requestBus        = (s_stateMachineReg == REQUEST_BUS1) ? 1'b1 : 1'b0;
  assign addressDataOut    = s_addressDataOutReg;
  assign dataValidOut      = s_dataValidReg;
  
  always @*
    case (s_stateMachineReg)
      IDLE            : s_stateMachineNext <= ((s_grabberRunningReg == 1'b1 || s_singleShotActionReg[0] == 1'b1) && s_newLine == 1'b1) ? REQUEST_BUS1 : IDLE;
      REQUEST_BUS1    : s_stateMachineNext <= (busGrant == 1'b1) ? INIT_BURST1 : REQUEST_BUS1;
      INIT_BURST1     : s_stateMachineNext <= DO_BURST1;
      DO_BURST1       : s_stateMachineNext <= (busErrorIn == 1'b1) ? END_TRANS2 :
                                              (s_burstCountReg[8] == 1'b1 && busyIn == 1'b0) ? END_TRANS1 : DO_BURST1;
      END_TRANS1      : s_stateMachineNext <= (s_nrOfPixelsPerLineReg != 9'd0) ? REQUEST_BUS1 : IDLE;
      default         : s_stateMachineNext <= IDLE;
    endcase
  
  always @(posedge clock)
    begin
      s_busAddressReg        <= s_busAddressNext;
      s_grabberRunningReg    <= (reset == 1'b1) ? 1'b0 : (s_newScreen == 1'b1) ? s_grabberActiveReg : s_grabberRunningReg;
      s_singleShotActionReg  <= (reset == 1'b1 || s_singleShotActionReg[1] == 1'b1) ? 2'b0 : (s_newScreen == 1'b1) ? {1'b0,s_grabberSingleShotReg} : s_singleShotActionReg;
      s_singleShotDoneReg    <= (reset == 1'b1 || (s_isMyCi == 1'b1 && ciValueA[3:0] == 3'd7)) ? 1'b1 : (s_singleShotActionReg[1] == 1'b1) ? 1'b1 : s_singleShotDoneReg;
      s_stateMachineReg      <= (reset == 1'b1) ? IDLE : s_stateMachineNext;
      beginTransactionOut    <= (s_stateMachineReg == INIT_BURST1) ? 1'd1 : 1'd0;
      byteEnablesOut         <= (s_stateMachineReg == INIT_BURST1) ? 4'hF : 4'd0;
      s_addressDataOutReg    <= (s_stateMachineReg == INIT_BURST1) ? s_busAddressReg : 
                                (s_doWrite == 1'b1) ? s_busPixelWord :
                                (busyIn == 1'b1) ? s_addressDataOutReg : 32'd0;
      s_dataValidReg         <= (s_doWrite == 1'b1) ? 1'b1 : (busyIn == 1'b1) ? s_dataValidReg : 1'b0;
      endTransactionOut      <= (s_stateMachineReg == END_TRANS1 || s_stateMachineReg == END_TRANS2) ? 1'b1 : 1'b0;
      burstSizeOut           <= (s_stateMachineReg == INIT_BURST1) ? s_burstSizeNext - 8'd1 : 8'd0;
      s_burstCountReg        <= (s_stateMachineReg == INIT_BURST1) ? s_burstSizeNext - 8'd1 :
                                (s_doWrite == 1'b1) ? s_burstCountReg - 9'd1 : s_burstCountReg;
      s_busSelectReg         <= (s_stateMachineReg == IDLE) ? 9'd0 : (s_doWrite == 1'b1) ? s_busSelectReg + 9'd1 : s_busSelectReg;
      s_nrOfPixelsPerLineReg <= (s_newLine == 1'b1) ? {1'b0, s_pixelCountValueReg[10:3]} : 
                                (s_stateMachineReg == INIT_BURST1) ? s_nrOfPixelsPerLineReg - {1'b0,s_burstSizeNext} : s_nrOfPixelsPerLineReg;
    end
  
  synchroFlop sns ( .clockIn(pclk),
                    .clockOut(clock),
                    .reset(reset),
                    .D(s_vsyncNegEdge),
                    .Q(s_newScreen) );
  
  synchroFlop snl ( .clockIn(pclk),
                    .clockOut(clock),
                    .reset(reset),
                    .D(s_hsyncNegEdge),
                    .Q(s_newLine) );
  
endmodule
