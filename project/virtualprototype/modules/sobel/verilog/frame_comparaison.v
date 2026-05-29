module frameComparaison #(parameter [7:0] customInstructionId = 8'd40 )
                           ( input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );

  /* we compensate here for the big/little endian problem */

    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;
    wire s_comparaisonResult1, s_comparaisonResult2, s_comparaisonResult3, s_comparaisonResult4, s_comparaisonResult;
    wire [7:0] threshold;
    assign threshold = 8'd64;

    pixelComparaison pixel1 ( .pixelA(valueA[7:0]),
                            .pixelB(valueB[7:0]),
                            .threshold(threshold),
                            .comparaisonResult(s_comparaisonResult1));

    pixelComparaison pixel2 ( .pixelA(valueA[15:8]),
                            .pixelB(valueB[15:8]),
                            .threshold(threshold),
                            .comparaisonResult(s_comparaisonResult2));

    pixelComparaison pixel3 ( .pixelA(valueA[23:16]),
                            .pixelB(valueB[23:16]),
                            .threshold(threshold),
                            .comparaisonResult(s_comparaisonResult3));  

    pixelComparaison pixel4 ( .pixelA(valueA[31:24]),
                            .pixelB(valueB[31:24]),
                            .threshold(threshold),
                            .comparaisonResult(s_comparaisonResult4));

    assign s_comparaisonResult = s_comparaisonResult1 & s_comparaisonResult2 & s_comparaisonResult3 & s_comparaisonResult4;
  
    assign done   = s_isMyIse;
    assign result = (s_isMyIse == 1'b1) ? ((s_comparaisonResult) ? 32'b10 : 32'b0) : 32'b0;

endmodule
