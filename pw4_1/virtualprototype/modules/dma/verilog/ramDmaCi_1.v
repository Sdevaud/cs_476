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

  wire write_mem_data = ok && writeEnableA;
  wire read_mem_data  = ok && !writeEnableA;
  reg read_mem_data_reg;

  always @(posedge clock) begin
    if (reset)
      read_mem_data_reg <= 1'b0;
    else
      read_mem_data_reg <= read_mem_data;
  end

  assign done = (ok && writeEnableA) || read_mem_data_reg;

  dualPortSSRAM #(.bitwidth(32), .nrOfEntries(512)) ssram (
    .clockA(clock),
    .clockB(~clock),
    .writeEnableA(write_mem_data),
    .writeEnableB(1'b0), // Not used
    .addressA(addrA),
    .addressB(9'd0), // Not used
    .dataInA(dataInterface),
    .dataInB(32'd0), // Not used
    .dataOutA(buffer), // 
    .dataOutB() // Not used
  );


  // Read and Write from CPU
  always @* begin
    result_reg = buffer;
  end


  assign result = read_mem_data_reg ? result_reg : 32'd0;

endmodule
