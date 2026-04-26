/*
Author : Till Beyer 14.04.2026
*/

module ramDmaCi #(parameter [7:0]customId=8'hA5)

  (input wire start,
   clock,
   reset,
   input wire [31:0]valueA,
   valueB,
   input wire [7:0]ciN,
   output wire done,
   output wire [31:0]result);

  // Dual-ported SSRAM 512x32
  wire [31:0] buffer;
  wire writeEnableA = valueA[9];
  wire [8:0] addrA = valueA[8:0];
  wire [31:0] dataInterface = valueB;
  reg [31:0] result_reg;
  wire ok = start && (ciN == customId);

  dualPortSSRAM #(.bitwidth(32), .nrOfEntries(512)) ssram (
    .clockA(clock),
    .clockB(~clock),
    .writeEnableA(ok && writeEnableA),
    .writeEnableB(1'b0), // Not used
    .addressA(addrA),
    .addressB(9'd0), // Not used
    .dataInA(dataInterface),
    .dataInB(32'd0), // Not used
    .dataOutA(buffer), // 
    .dataOutB() // Not used
  );


  // Read and Write from CPU
  always @(posedge clock or posedge reset)
  begin
    if (reset) 
    begin
        result_reg <= 32'd0;
    end

    else if (ok)
    begin
      result_reg <= buffer;
    end
  end


  assign result = !writeEnableA ? result_reg : 32'd0;
  assign done = ok;

endmodule
