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
  wire ok = (start && ciN == customId);

  // DMA registers
  reg [31:0] busAddr, memAddr;
  reg [9:0] blockSize;
  reg [7:0] burstSize;
  reg [1:0] status;
  reg [1:0] control; // 1 bus > men, 2 mem > bus

  dualPortSSRAM #(.bitwidth(32), .nrOfEntries(512)) ssram (
    .clockA(clock),
    .clockB(~clock),
    .writeEnableA(ok & writeEnableA),
    .writeEnableB(1'b0), // No writes from port B
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

    else if (ok && !writeEnableA)
    begin
      result_reg <= buffer;
    end
  end


  // // DMA control logic
  // always @(negedge clock or posedge reset) begin
  //     if (reset) begin
  //         // Reset DMA registers
  //     end else if (control[0] && !status[0]) begin
  //         // Start DMA transfer (bus → mem)
  //         // Handle burst mode, auto-increment addresses
  //     end
  // end

  // // Bus interface (simplified)
  // assign s_busRequests[27] = (status[0] && !status[1]);  // Request bus
  // always @(posedge clock) begin
  //     if (s_busGrants[27]) begin
  //         // Perform bus read/write
  //     end
  // end


  assign result = result_reg;
  assign done = ok;

endmodule
