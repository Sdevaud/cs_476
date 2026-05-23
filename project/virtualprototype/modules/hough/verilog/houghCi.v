module houghCi #(parameter [7:0] customInstructionId = 8'hA7 )
                           (
                             input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );
                             

  wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;

  wire signed [31:0] rhoA;
  wire signed [31:0] rhoB;
  wire [15:0] s_rhoA = rhoA[23:8];
  wire [15:0] s_rhoB = rhoB[23:8];
  wire [31:0] s_rhoValues = {s_rhoA, s_rhoB};
  
  assign done   = s_isMyIse;
  assign result = (s_isMyIse == 1'b1) ? s_rhoValues : 32'd0;

  wire [7:0] thetaA = valueA[7:0];
  wire signed [9:0] xA = valueA[17:8];
  wire signed [9:0] yA = valueA[27:18];
  wire signed [9:0] sinA;
  wire signed [9:0] cosA;

  wire [7:0] thetaB = valueB[7:0];
  wire signed [9:0] xB = valueB[17:8];
  wire signed [9:0] yB = valueB[27:18];
  wire signed [9:0] sinB;
  wire signed [9:0] cosB;

  houghAngleLUT lutA ( .theta(thetaA), .sin(sinA), .cos(cosA) );
  houghAngleLUT lutB ( .theta(thetaB), .sin(sinB), .cos(cosB) );

  assign rhoA = (xA * cosA + yA * sinA) + 32'sd128; // This is done for rounding
  assign rhoB = (xB * cosB + yB * sinB) + 32'sd128; // This is done for rounding

endmodule
