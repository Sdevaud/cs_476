module ramDmaCi #( parameter [7:0] customId = 8'h00 )
                 ( input wire         start,
                                      clock,
                                      reset,
                   input wire [31:0]  valueA,
                                      valueB,
                   input wire [7:0]   ciN,
                   output wire        done ,
                   output wire [31:0] result );

  wire [31:0] s_sramDataValue;
  /*
   *
   * Here we define the custom instruction control signals
   *
   */
  wire s_isMyCi = (ciN == customId) ? start : 1'b0;
  wire s_isSramWrite = (valueA[31:10] == 22'd0) ? s_isMyCi & valueA[9] : 1'b0;
  wire s_isSramRead  = s_isMyCi & ~valueA[9];
  reg s_isSramReadReg;
  
  assign done   = (s_isMyCi & valueA[9]) | s_isSramReadReg;
  assign result = (s_isSramReadReg == 1'b1) ? s_sramDataValue : 32'd0;
  
  always @(posedge clock) s_isSramReadReg = ~reset & s_isSramRead;

  /*
   *
   * Here we map the dual-ported memory
   *
   */
  
  dualPortSSRAM #( .bitwidth(32),
                   .nrOfEntries(512),
                   .readAfterWrite(0) ) memory
                 ( .clockA(clock), 
                   .clockB(1'b0),
                   .writeEnableA(s_isSramWrite), 
                   .writeEnableB(1'b0),
                   .addressA(valueA[8:0]), 
                   .addressB(9'd0),
                   .dataInA(valueB), 
                   .dataInB(32'b0),
                   .dataOutA(s_sramDataValue), 
                   .dataOutB());
  
  
endmodule
