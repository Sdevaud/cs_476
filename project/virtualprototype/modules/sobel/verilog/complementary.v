/*
Date Created: 30.05.2026
main fomrula : |A △ B| = number of pixels that are white in either A or B but not in both

A : this is the actual frame
B : this is the previous frame (one step back in the pipeline)
so A and B are the esnemble of white pixels in the actual and previous frame respectively.

this module compute for a word of 32 bits (4 pixels) 
*/

module complementary #(parameter [7:0] customInstructionId = 8'd40 )
                           ( input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );

  wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;
  wire s_comparaisonResult1, s_comparaisonResult2, s_comparaisonResult3, s_comparaisonResult4;
  wire [2:0] s_comparaisonResult;


  assign s_comparaisonResult1 = (valueA[7:0] != valueB[7:0]);
  assign s_comparaisonResult2 = (valueA[15:8] != valueB[15:8]);
  assign s_comparaisonResult3 = (valueA[23:16] != valueB[23:16]);
  assign s_comparaisonResult4 = (valueA[31:24] != valueB[31:24]);

  assign s_comparaisonResult =
    {2'b00, s_comparaisonResult1} +
    {2'b00, s_comparaisonResult2} +
    {2'b00, s_comparaisonResult3} +
    {2'b00, s_comparaisonResult4};

  assign done   = s_isMyIse;
  assign result = (s_isMyIse == 1'b1) ? {29'b0, s_comparaisonResult} : 32'b0;

endmodule
