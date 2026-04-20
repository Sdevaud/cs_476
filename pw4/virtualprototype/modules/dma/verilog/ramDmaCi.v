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
  reg [31:0] mem [511:0];
  reg [31:0] dataA;
  wire writeEnableA = valueA[9];
  wire [8:0] addrA = valueA[8:0];
  reg [31:0] result_reg;
  wire ok = (start && ciN == customId);
  wire test = 0;

  // Write, 1 cycle
  always @(posedge clock or posedge reset)
  begin
    if (reset) 
    begin
        dataA <= 32'd0;
        result_reg <= 32'd0;
    end

    else if (ok && writeEnableA)
    begin
      mem[addrA] <= valueB; // write to memory
    end

    else if (ok && !writeEnableA)
    begin
      dataA <= mem[addrA]; // read from memory
      result_reg <= dataA;
    end
  end

  assign result = result_reg;
  assign done = ok;

endmodule
