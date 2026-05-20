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
      s_frameBufferBaseReg   <= (reset == 1'b1) ? 32'd0 : (s_isMyCi == 1'b1 && ciValueA[2:0] == 3'd5) ? {ciValueB[31:2],2'd0} : s_frameBufferBaseReg;
      s_grabberActiveReg     <= (reset == 1'b1) ? 1'b0 : (s_isMyCi == 1'b1 && ciValueA[2:0] == 3'd6) ? ciValueB[0]& ~ciValueB[1] : s_grabberActiveReg;
      s_grabberSingleShotReg <= (reset == 1'b1 || s_singleShotActionReg[0] == 1'b1) ? 1'b0 : (s_isMyCi == 1'b1 && ciValueA[2:0] == 3'd6) ? ciValueB[1]& ~ciValueB[0] : s_grabberSingleShotReg;
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

  /* ==== Added by Sebastien ==== */

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

  // ==== Added by Till ====  

  // Indices to keep track of which line buffer to write into
  reg [1:0] bufferSelectReg; // 0 -> 1 -> 2 -> 0 -> ...
  reg [1:0] bufferBeforeReg; // 2 -> 0 -> 1 -> 2 -> ...
  reg [1:0] bufferBeforeBeforeReg; // 1 -> 2 -> 0 -> 1 -> ...
  always @(posedge pclk) begin
      if (reset == 1'b1 || s_vsyncNegEdge == 1'b1)
      begin // Every time a new frame starts (vsync neg edge)
          bufferSelectReg <= 2'd0;
          bufferBeforeReg <= 2'd1;
          bufferBeforeBeforeReg <= 2'd2;
      end 
      else if (s_hsyncNegEdge == 1'b1)
      begin
          // Every time line ends (hsync neg edge)
          bufferSelectReg <= (bufferSelectReg == 2'd0) ? 2'd2 : bufferSelectReg - 2'd1;
          bufferBeforeReg <= (bufferBeforeReg == 2'd0) ? 2'd2 : bufferBeforeReg - 2'd1;
          bufferBeforeBeforeReg <= (bufferBeforeBeforeReg == 2'd0) ? 2'd2 : bufferBeforeBeforeReg - 2'd1;
      
      end
  end

  reg weBuffer0, weBuffer1, weBuffer2;
  reg [7:0] lineBufferAddr;
  always @(posedge pclk) begin
      weBuffer0 <= (subPixelCount == 3'b111 && bufferSelectReg == 2'd0) ? hsync : 1'b0;
      weBuffer1 <= (subPixelCount == 3'b111 && bufferSelectReg == 2'd1) ? hsync : 1'b0;
      weBuffer2 <= (subPixelCount == 3'b111 && bufferSelectReg == 2'd2) ? hsync : 1'b0;
      lineBufferAddr <= s_pixelCountReg[10:3];
  end

  wire [31:0] busPixelWord0, busPixelWord1, busPixelWord2;

  dualPortRam640 lineBuffer0 ( .address1 (lineBufferAddr),
                              .address2(lineBufferAddr),
                              .clock1(pclk), // Input clock (camera)
                              .clock2(pclk), // Output clock (cpu)
                              .writeEnable(weBuffer0),
                              .dataIn1(s_grayscalePixelWord),
                              .dataOut2(busPixelWord0));
  dualPortRam640 lineBuffer1 ( .address1 (lineBufferAddr),
                              .address2(lineBufferAddr),
                              .clock1(pclk), // Input clock (camera)
                              .clock2(pclk), // Output clock (cpu)
                              .writeEnable(weBuffer1),
                              .dataIn1(s_grayscalePixelWord),
                              .dataOut2(busPixelWord1));
  dualPortRam640 lineBuffer2 ( .address1 (lineBufferAddr),
                              .address2(lineBufferAddr),
                              .clock1(pclk), // Input clock (camera)
                              .clock2(pclk), // Output clock (cpu)
                              .writeEnable(weBuffer2),
                              .dataIn1(s_grayscalePixelWord),
                              .dataOut2(busPixelWord2));

  // Read from line buffers in correct order
  // [p11] [p12] [p13]
  // [p21] [p22] [p23]
  // [p31] [p32] [p33] <- new pixel from camera
  reg [7:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
  reg [1:0] groupCount;// = s_pixelCountReg[2:1]; // keeps track of which pixel in the current 4-pixel group we are at (00, 01, 10, 11)

  // 1. Pick the "current" grayscale pixel from the 4 available based on camera timing
  // This is going to be p33 in the 3x3 window
  reg [7:0] current_cam_gray;
  always @(posedge pclk) begin
          groupCount <= s_pixelCountReg[2:1];
  end
  always @* begin
      case (groupCount)
          2'b00: current_cam_gray = gray0;
          2'b01: current_cam_gray = gray1;
          2'b10: current_cam_gray = gray2;
          2'b11: current_cam_gray = gray3;
          default: current_cam_gray = 8'd0;
      endcase
  end

  // 2. Pick the corresponding pixels from the Top and Mid Line Buffers
  wire [31:0] busPixelWordBefore = (bufferBeforeReg == 2'd0) ? busPixelWord0 :
                                  (bufferBeforeReg == 2'd1) ? busPixelWord1 :
                                                              busPixelWord2;
  // p23
  wire [7:0] current_mid_gray = (groupCount == 2'b00) ? busPixelWordBefore[7:0]   :
                                (groupCount == 2'b01) ? busPixelWordBefore[15:8]  :
                                (groupCount == 2'b10) ? busPixelWordBefore[23:16] :
                                busPixelWordBefore[31:24];
                                                       
                                
  wire [31:0] busPixelWordBeforeBefore = (bufferBeforeBeforeReg == 2'd0) ? busPixelWord0 :
                                         (bufferBeforeBeforeReg == 2'd1) ? busPixelWord1 :
                                                                           busPixelWord2;
  // p13                                                                        
  wire [7:0] current_top_gray = (groupCount == 2'b00) ? busPixelWordBeforeBefore[7:0]   :
                                (groupCount == 2'b01) ? busPixelWordBeforeBefore[15:8]  :
                                (groupCount == 2'b10) ? busPixelWordBeforeBefore[23:16] :
                                                        busPixelWordBeforeBefore[31:24];


  reg shift_enable_delayed;

  always @(posedge pclk) begin
    // Delay shift signal by one to allow values to be pulled from line buffers  
    shift_enable_delayed <= (hsync && s_pixelCountReg[0] == 1'b1);
  end

  // 3. Shift the window every time a 16-bit pixel pair finishes (every 2nd camData byte)
  always @(posedge pclk) begin
        if (shift_enable_delayed) begin
          p11 <= p12; 
          p12 <= p13;
          p21 <= p22; 
          p22 <= p23;
          p31 <= p32; 
          p32 <= p33;

          p33 <= current_cam_gray; // Newest pixel from camera
          p23 <= current_mid_gray; // Corresponding pixel from 1 line ago
          p13 <= current_top_gray; // Corresponding pixel from 2 lines ago
      end
  end
  
  // Compute Sobel gradients
  // Gx = [-1  0  1]  Gy = [-1 -2 -1]
  //      [-2  0  2]       [ 0  0  0]
  //      [-1  0  1]       [ 1  2  1]

  // Extended to 9 bits to prevent overflow during multiplication by 2 (left shift)
  wire [8:0] p11e = {1'b0, p11};
  wire [8:0] p12e = {1'b0, p12};
  wire [8:0] p13e = {1'b0, p13};
  wire [8:0] p21e = {1'b0, p21};
  wire [8:0] p23e = {1'b0, p23};
  wire [8:0] p31e = {1'b0, p31};
  wire [8:0] p32e = {1'b0, p32};
  wire [8:0] p33e = {1'b0, p33};

  // Use signed arithmetic for gradient calculation to handle negative values
  wire signed [10:0] gx =
      $signed({1'b0, p13e}) +
      $signed({1'b0, p23e, 1'b0}) +
      $signed({1'b0, p33e}) -
      $signed({1'b0, p11e}) -
      $signed({1'b0, p21e, 1'b0}) -
      $signed({1'b0, p31e});

  // Use signed arithmetic for gradient calculation to handle negative values
  wire signed [10:0] gy =
      $signed({1'b0, p31e}) +
      $signed({1'b0, p32e, 1'b0}) +
      $signed({1'b0, p33e}) -
      $signed({1'b0, p11e}) -
      $signed({1'b0, p12e, 1'b0}) -
      $signed({1'b0, p13e});

  // Prevent overflow during addition of absolute values
  wire [11:0] magnitude =
      (gx < 0 ? -gx : gx) +
      (gy < 0 ? -gy : gy);

  wire isBorder = (s_lineCountReg <= 11'd1) || (s_pixelCountReg <= 11'd6); 

  wire [7:0] sobelActual = (magnitude > 12'd64) ? 8'hFF : 8'h00;

  // Final Result: If on border, force black. Otherwise, use Sobel.
  assign sobelResult = (isBorder) ? 8'h00 : sobelActual;
  // debug
  // wire [7:0] sobelResult = p23;

  // 4. Corrected Storage for the 4 results
  reg [7:0] sobelResult0, sobelResult1, sobelResult2, sobelResult3;
  always @(posedge pclk) begin
          case (groupCount)
              2'b01: sobelResult0 <= sobelResult;
              2'b10: sobelResult1 <= sobelResult;
              2'b11: sobelResult2 <= sobelResult;
              2'b00: sobelResult3 <= sobelResult;
          endcase
  end

  wire [31:0] sobelPixelWord = {sobelResult3, sobelResult2, sobelResult1, sobelResult0};

  // =======================

  // This is an ugly way of delaying by 3 cycles
  reg s_weLineBuffer_delay1, s_weLineBuffer_delay2, s_weLineBuffer_delay3;
  reg [8:0] s_writeAddressReg;

  always @(posedge pclk) begin
      // Only write to the 2k RAM when we have finished packing all 4 pixels (groupCount 3)
      s_weLineBuffer_delay1 <= groupCount == 2'b11;
      s_weLineBuffer_delay2 <= s_weLineBuffer_delay1;
      s_weLineBuffer_delay3 <= s_weLineBuffer_delay2;
      
      if (groupCount == 2'b11) begin
          s_writeAddressReg <= s_pixelCountReg[10:3] - 1;
      end
  end
  

  dualPortRam2k lineBuffer ( .address1(s_writeAddressReg),
                             .address2(s_busSelectReg),
                             .clock1(pclk),
                             .clock2(clock),
                             .writeEnable(s_weLineBuffer_delay3),
                             .dataIn1(sobelPixelWord),
                             .dataOut2(s_busPixelWord));

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
      s_singleShotDoneReg    <= (reset == 1'b1 || (s_isMyCi == 1'b1 && ciValueA[2:0] == 3'd7)) ? 1'b1 : (s_singleShotActionReg[1] == 1'b1) ? 1'b1 : s_singleShotDoneReg;
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
