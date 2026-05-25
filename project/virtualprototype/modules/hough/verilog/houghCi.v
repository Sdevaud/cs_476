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

  reg [15:0] bankA [0:200];
  reg [15:0] bankB [0:200];
  reg [15:0] bankC [0:200];
  reg [15:0] bankD [0:200];
  reg [31:0] read_buf;

  // initialize memory
  integer i;
  initial begin
    for (i = 0; i < 201; i = i + 1) begin
      bankA[i] = 16'd0; bankB[i] = 16'd0;
      bankC[i] = 16'd0; bankD[i] = 16'd0;
    end
  end


  // ====== Rho Calculation Logic ======

  wire signed [31:0] rhoA, rhoA_corrected, rhoA_scaled;
  wire signed [31:0] rhoB, rhoB_corrected, rhoB_scaled;
  wire signed [31:0] rhoC, rhoC_corrected, rhoC_scaled;
  wire signed [31:0] rhoD, rhoD_corrected, rhoD_scaled;
  wire signed [7:0] rhoA8, rhoB8, rhoC8, rhoD8;
  
  wire [7:0] theta = valueA[7:0];
  wire signed [9:0] y = valueA[17:8];
  wire signed [9:0] xA = valueA[27:18];
  wire signed [9:0] xB = valueB[9:0];
  wire signed [9:0] xC = valueB[19:10];
  wire signed [9:0] xD = valueB[29:20];
  
  wire sobelBinValueA = valueA[28];
  wire sobelBinValueB = valueA[29];
  wire sobelBinValueC = valueA[30];
  wire sobelBinValueD = valueA[31];

  wire signed [9:0] sin;
  wire signed [9:0] cos;
  
  houghAngleLUT lutA ( .theta(theta), .sin(sin), .cos(cos) );
  
  assign rhoA = (xA * cos + y * sin) + 32'sd128; // This is done for rounding
  assign rhoA_corrected = rhoA >>> 8; // Sin/Cos LUT is scaled by 256, so we need to shift back
  assign rhoA_scaled = (rhoA_corrected + 32'sd800 + 32'sd4) >>> 3; // Scale rho from [-800, 800] to [0, 200], add 4 for rounding 
  assign rhoA8 = rhoA_scaled[7:0]; // Take the 8 LSBs as the final rho value
  
  assign rhoB = (xB * cos + y * sin) + 32'sd128;
  assign rhoB_corrected = rhoB >>> 8;
  assign rhoB_scaled = (rhoB_corrected + 32'sd800 + 32'sd4) >>> 3;
  assign rhoB8 = rhoB_scaled[7:0];
  
  assign rhoC = (xC * cos + y * sin) + 32'sd128;
  assign rhoC_corrected = rhoC >>> 8;
  assign rhoC_scaled = (rhoC_corrected + 32'sd800 + 32'sd4) >>> 3;
  assign rhoC8 = rhoC_scaled[7:0];
  
  assign rhoD = (xD * cos + y * sin) + 32'sd128;
  assign rhoD_corrected = rhoD >>> 8;
  assign rhoD_scaled = (rhoD_corrected + 32'sd800 + 32'sd4) >>> 3;
  assign rhoD8 = rhoD_scaled[7:0];
  
  wire [31:0] s_rhoValues = {rhoA8, rhoB8, rhoC8, rhoD8};

  // ====== Accumulation Logic ======

  wire [7:0]  read_index       = valueA[7:0]; // Re-use lower 8 bits for the readout index
  wire [31:0] total_read_votes = bankA[read_index] + bankB[read_index] + bankC[read_index] + bankD[read_index];
  
  assign done   = s_isMyIse;
  assign result = (s_isMyIse) ? ((op_mode == 2'b01) ? read_buf : s_rhoValues) : 32'd0;

  always @(posedge clock) begin
    if (reset) begin
      for (i = 0; i < 256; i = i + 1) begin
        bankA[i] <= 16'd0; bankB[i] = 16'd0;
        bankC[i] <= 16'd0; bankD[i] = 16'd0;
      end
    end else if (is_vote_mode) begin
      // all in parallel
      if (sobelBinValueA) bankA[rhoA8] <= bankA[rhoA8] + 1'b1;
      if (sobelBinValueB) bankB[rhoB8] <= bankB[rhoB8] + 1'b1;
      if (sobelBinValueC) bankC[rhoC8] <= bankC[rhoC8] + 1'b1;
      if (sobelBinValueD) bankD[rhoD8] <= bankD[rhoD8] + 1'b1;
    end else if (is_read_mode) begin
      read_buf <= total_read_votes; 
      bankA[read_index] <= 16'd0;
      bankB[read_index] <= 16'd0;
      bankC[read_index] <= 16'd0;
      bankD[read_index] <= 16'd0;
    end
  end


endmodule
