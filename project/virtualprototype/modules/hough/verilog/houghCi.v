module houghCi #(parameter [7:0] customInstructionId = 8'hA7 )
                           ( input wire         clock,
                             input wire         reset,
                             input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );
                             
  /*
    The CI operates in two modes: Vote Mode and Read Mode

    VOTE:
    The Ci processes 4 pixels at a time provided the same y and theta values. The format is
    valueA [0:31] = {theta(8bit), y(10bit), x1(10bit), sobelBin1(1bit), sobelBin2(1bit), sobelBin3(1bit), sobelBin4(1bit)}
    valueB [0:31] = {x2(10bit), x3(10bit), x4(10bit), reserved(2bit)}
    The corresponding rho values for the 4 pixels are calculated and stored in an internal accumulator.clock

    READ:
    The accumulated votes for a given rho value are read out and the accumulator for that rho value is cleared.
    
    Last 2 bits of valueB determine the mode of operation:
    2'b00 = Vote Mode (Accumulate pixels)
    2'b01 = Read-and-Clear Mode (Extract total votes and reset slot to 0)

    The RHO is scaled by a factor of 8. With a 640x480 image rho can be in the range [-800, 800].
    This is converted into a range of [0, 200] with the scaling so the resulting rho values can
    be represented in 8 bit.
  */

  // ====== Setup ======
  wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;

  wire [1:0] op_mode   = valueB[31:30];
  wire is_vote_mode    = (s_isMyIse && (op_mode == 2'b00));
  wire is_read_mode    = (s_isMyIse && (op_mode == 2'b01));
  reg s_isReadReg;
  reg s_isVoteReg;
  always @(posedge clock) s_isReadReg <= ~reset & is_read_mode;
  always @(posedge clock) s_isVoteReg <= ~reset & is_vote_mode;

  reg [15:0] bankA [0:255];
  reg [15:0] bankB [0:255];
  reg [15:0] bankC [0:255];
  reg [15:0] bankD [0:255];
  reg [31:0] read_buf;

  // initialize memory
  integer i;
  initial begin
    for (i = 0; i < 256; i = i + 1) begin
      bankA[i] = 16'd0; bankB[i] = 16'd0;
      bankC[i] = 16'd0; bankD[i] = 16'd0;
    end
  end


  // ====== Rho Calculation Logic ======

  wire signed [31:0] rhoA, rhoA_corrected;
  wire signed [31:0] rhoB, rhoB_corrected;
  wire signed [31:0] rhoC, rhoC_corrected;
  wire signed [31:0] rhoD, rhoD_corrected;
  wire signed [7:0] rhoA8, rhoB8, rhoC8, rhoD8;
  reg signed [31:0] rhoA_scaled, rhoB_scaled, rhoC_scaled, rhoD_scaled; 
  
  wire [7:0] theta = valueA[7:0];
  wire signed [10:0] y = {1'b0, valueA[17:8]};
  wire signed [10:0] xA = {1'b0, valueA[27:18]};
  wire signed [10:0] xB = xA + 11'sd2;
  wire signed [10:0] xC = xA + 11'sd4;
  wire signed [10:0] xD = xA + 11'sd6;
  
  wire sobelBinValueA = valueA[28];
  wire sobelBinValueB = valueA[29];
  wire sobelBinValueC = valueA[30];
  wire sobelBinValueD = valueA[31];
  reg voteA, voteB, voteC, voteD;

  wire signed [9:0] sin;
  wire signed [9:0] cos;
  
  houghAngleLUT lutA ( .theta(theta), .sin(sin), .cos(cos) );
  
  assign rhoA = (xA * cos + y * sin) + 32'sd128; // This is done for rounding
  assign rhoA_corrected = rhoA >>> 8; // Sin/Cos LUT is scaled by 256, so we need to shift back
  assign rhoA8 = rhoA_scaled[7:0]; // Take the 8 LSBs as the final rho value
  
  assign rhoB = (xB * cos + y * sin) + 32'sd128;
  assign rhoB_corrected = rhoB >>> 8;
  assign rhoB8 = rhoB_scaled[7:0];
  
  assign rhoC = (xC * cos + y * sin) + 32'sd128;
  assign rhoC_corrected = rhoC >>> 8;
  assign rhoC8 = rhoC_scaled[7:0];
  
  assign rhoD = (xD * cos + y * sin) + 32'sd128;
  assign rhoD_corrected = rhoD >>> 8;
  assign rhoD8 = rhoD_scaled[7:0];

  always @(posedge clock) begin
    if (reset) begin
      rhoA_scaled <= 32'd0;
      rhoB_scaled <= 32'd0;
      rhoC_scaled <= 32'd0;
      rhoD_scaled <= 32'd0;
      voteA <= 1'b0; voteB <= 1'b0; voteC <= 1'b0; voteD <= 1'b0;
    end else begin
      rhoA_scaled <= (rhoA_corrected + 32'sd800 + 32'sd4) >>> 3;
      rhoB_scaled <= (rhoB_corrected + 32'sd800 + 32'sd4) >>> 3;
      rhoC_scaled <= (rhoC_corrected + 32'sd800 + 32'sd4) >>> 3;
      rhoD_scaled <= (rhoD_corrected + 32'sd800 + 32'sd4) >>> 3;
      voteA <= sobelBinValueA;
      voteB <= sobelBinValueB;
      voteC <= sobelBinValueC;
      voteD <= sobelBinValueD;
    end
  end
  
  wire [31:0] s_rhoValues = {rhoA8, rhoB8, rhoC8, rhoD8};

  // ====== Accumulation Logic ======

  wire [7:0]  read_index = valueA[7:0]; // Re-use lower 8 bits for the readout index
  reg [31:0] read_buffer;
  reg clear_pulse;
  reg [7:0] clear_index;

  // assign done   = s_isMyIse ? s_isVoteReg : s_isReadReg;
  assign done   = s_isVoteReg || s_isReadReg;
  assign result = s_isReadReg ? read_buffer : (is_vote_mode ? s_rhoValues : 32'd0);

  always @(posedge clock) begin
    if (reset) begin
      read_buffer <= 32'd0;
    end
    if (is_read_mode) begin
      // 1. Capture the current data combinationally into the register.
      // In Read-First BRAM, the output latch holds the OLD value before the 0 is written!
      read_buffer    <= bankA[read_index] + bankB[read_index] + bankC[read_index] + bankD[read_index];

      // 2. Clear the target registers instantly on this exact same clock edge
      clear_pulse <= 1'b1;
      clear_index <= read_index;
    end else begin
      clear_pulse <= 1'b0;
    end

    if (s_isVoteReg & !is_vote_mode) begin
      // Accumulate edge markers in parallel
      if (voteA) bankA[rhoA8] <= bankA[rhoA8] + 1'b1;
      if (voteB) bankB[rhoB8] <= bankB[rhoB8] + 1'b1;
      if (voteC) bankC[rhoC8] <= bankC[rhoC8] + 1'b1;
      if (voteD) bankD[rhoD8] <= bankD[rhoD8] + 1'b1;
    end else if (clear_pulse) begin
      // Clear the accumulator slot after reading
      bankA[clear_index] <= 16'd0;
      bankB[clear_index] <= 16'd0;
      bankC[clear_index] <= 16'd0;
      bankD[clear_index] <= 16'd0;
    end
  end


endmodule
