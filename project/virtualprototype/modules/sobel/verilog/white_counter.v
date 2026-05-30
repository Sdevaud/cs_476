/*
Date Created: 30.05.2026
main fomrula : we basicly compue the number of white pixels in a 32 bit word (4 pixels) 
*/

module whiteCounter #(parameter [7:0] customInstructionId = 8'd41 )
                           ( input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );


    wire [2:0] s_comparaisonResult;
    wire s_whitePixel1, s_whitePixel2, s_whitePixel3, s_whitePixel4;
    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;

    assign s_whitePixel1 = (valueA[7:0] == 8'hFF);
    assign s_whitePixel2 = (valueA[15:8] == 8'hFF);
    assign s_whitePixel3 = (valueA[23:16] == 8'hFF);
    assign s_whitePixel4 = (valueA[31:24] == 8'hFF);

    assign s_comparaisonResult =
        {2'b00, s_whitePixel1} +
        {2'b00, s_whitePixel2} +
        {2'b00, s_whitePixel3} +
        {2'b00, s_whitePixel4};

    assign done   = s_isMyIse;
    assign result = (s_isMyIse == 1'b1) ? {29'b0, s_comparaisonResult} : 32'b0;
    
endmodule