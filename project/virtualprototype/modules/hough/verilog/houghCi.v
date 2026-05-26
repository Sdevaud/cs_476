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
  always @(posedge clock) s_isReadReg = ~reset & is_read_mode;

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
  // reg resetBank;
  // reg is_read_mode_reg;
  // reg [7:0] read_index_reg; // latched read index for destructive clear
  // wire [31:0] read_sum_wire; // combinational read sum for immediate response

  // assign done   = s_isMyIse | s_isReadReg;
  // If we're performing a read this cycle, return the combinational sum immediately.
  // Otherwise, if we're in the follow-up cycle (is_read_mode_reg) return the latched read_buf.
  // assign read_sum_wire = bankA[read_index] + bankB[read_index] + bankC[read_index] + bankD[read_index];
  // assign result = (s_isMyIse) ?
  //                 ((is_read_mode | is_read_mode_reg) ?
  //                 (is_read_mode ? read_sum_wire : read_buf) : s_rhoValues)
  //                 : 32'd0;

  // always @(posedge clock) begin
  //   if (reset) begin
  //     read_buf <= 32'd0;
  //     is_read_mode_reg <= 1'b0;
  //     resetBank <= 1'b0;
  //   end else if (is_vote_mode) begin
  //     // all in parallel
  //     is_read_mode_reg <= 1'b0;
  //     resetBank <= 1'b0; // Clear reset flag in case we were in read mode in the previous cycle
  //     if (sobelBinValueA) bankA[rhoA8] <= bankA[rhoA8] + 1'b1;
  //     if (sobelBinValueB) bankB[rhoB8] <= bankB[rhoB8] + 1'b1;
  //     if (sobelBinValueC) bankC[rhoC8] <= bankC[rhoC8] + 1'b1;
  //     if (sobelBinValueD) bankD[rhoD8] <= bankD[rhoD8] + 1'b1;
  //   end else if (is_read_mode) begin
  //     // latch the read index so the destructive clear in the next cycle uses the correct slot
  //     read_index_reg <= read_index;
  //     // also capture the current bank sum into read_buf for the follow-up cycle
  //     read_buf <= bankA[read_index] + bankB[read_index] + bankC[read_index] + bankD[read_index];
  //     is_read_mode_reg <= 1'b1;
  //     resetBank <= 1'b1; // Set flag to reset the bank in the next cycle
  //   end else if (resetBank) begin
  //     bankA[read_index_reg] <= 16'd0;
  //     bankB[read_index_reg] <= 16'd0;
  //     bankC[read_index_reg] <= 16'd0;
  //     bankD[read_index_reg] <= 16'd0;
  //   end
  // end
  assign done   = s_isMyIse ? is_vote_mode : s_isReadReg;
  assign result = (is_read_mode |s_isReadReg) ? read_buf : s_rhoValues;

  always @(posedge clock) begin
    if (reset) begin
      read_buf         <= 32'd0;
    end else begin

      // ==========================================
      // ATOMIC READ-AND-CLEAR + VOTE HANDLING
      // ==========================================
      if (is_read_mode) begin
        // 1. Capture the current data combinationally into the register.
        // In Read-First BRAM, the output latch holds the OLD value before the 0 is written!
        read_buf    <= bankA[read_index] + bankB[read_index] + bankC[read_index] + bankD[read_index];

        // 2. Clear the target registers instantly on this exact same clock edge
        bankA[read_index] <= 16'd0;
        bankB[read_index] <= 16'd0;
        bankC[read_index] <= 16'd0;
        bankD[read_index] <= 16'd0;

      end else if (is_vote_mode) begin
        // Accumulate edge markers in parallel
        if (sobelBinValueA) bankA[rhoA8] <= bankA[rhoA8] + 1'b1;
        if (sobelBinValueB) bankB[rhoB8] <= bankB[rhoB8] + 1'b1;
        if (sobelBinValueC) bankC[rhoC8] <= bankC[rhoC8] + 1'b1;
        if (sobelBinValueD) bankD[rhoD8] <= bankD[rhoD8] + 1'b1;
      end
    end
  end


endmodule
