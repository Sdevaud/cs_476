module voteCountCi #(parameter [7:0] customInstructionId = 8'hA6 )
                           (
                             input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );

    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;

    wire [31:0] pixelsTop = valueA;
    wire [31:0] pixelsBot = valueB;

    wire [7:0] p4 = pixelsTop[7:0];
    wire [7:0] p3 = pixelsTop[15:8];
    wire [7:0] p2 = pixelsTop[23:16];
    wire [7:0] p1 = pixelsTop[31:24];
    wire [7:0] p12 = pixelsBot[7:0];
    wire [7:0] p11 = pixelsBot[15:8];
    wire [7:0] p10 = pixelsBot[23:16];
    wire [7:0] p9 = pixelsBot[31:24];

    wire sobelA = (p1 | p2 | p9 | p10) ? 1'b1 : 1'b0;
    wire sobelB = (p3 | p4 | p11 | p12) ? 1'b1 : 1'b0;
    
    wire [31:0] votes = {sobelB, sobelA, 30'b0};

    assign done = s_isMyIse;
    assign result = s_isMyIse ? votes : 32'b0;

endmodule
