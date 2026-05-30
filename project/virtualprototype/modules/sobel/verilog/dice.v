/*
Date Created: 30.05.2026
source : https://en.wikipedia.org/wiki/Dice-S%C3%B8rensen_coefficient
main fomrula : Ds = 1 - DSC = 1 - 2|A ∩ B| / (|A| + |B|)

A : this is the actual frame
B : this is the previous frame (one step back in the pipeline)
so A and B are the esnemble of white pixels in the actual and previous frame respectively.

you cant set the threshold from the C code with valueA[31:24] == 8'hFF, threshold value is in valueB[7:0].
*/

module dice #(parameter [7:0] customInstructionId = 8'd43 )
                           ( input wire         clock,
                             input wire         reset,
                             input wire         start,
                             input wire [31:0]  valueA,
                                                valueB,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );

    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0; 
    wire s_writeThreshold = s_isMyIse && (valueA[31:24] == 8'hFF);

    reg [7:0] s_thresholdValue;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            s_thresholdValue <= 8'd35;
        end else if (s_writeThreshold) begin
            s_thresholdValue <= valueB[7:0];
        end
    end

    wire [31:0] s_whiteSum;
    wire [31:0] s_intersectionCount;
    wire [31:0] s_doubleIntersection;
    wire [31:0] s_diffCount;

    wire [63:0] s_diffCountExt;
    wire [63:0] s_whiteSumExt;
    wire [63:0] s_leftValue;
    wire [63:0] s_rightValue;

    wire [31:0] s_diceResult;

    assign s_whiteSum = valueA;
    assign s_intersectionCount = valueB;

    assign s_doubleIntersection = s_intersectionCount << 1;

    assign s_diffCount = (s_whiteSum >= s_doubleIntersection) ?
                         (s_whiteSum - s_doubleIntersection) :
                         32'd0;

    assign s_diffCountExt = {32'b0, s_diffCount};
    assign s_whiteSumExt = {32'b0, s_whiteSum};

    assign s_leftValue = (s_diffCountExt << 6) +
                         (s_diffCountExt << 5) +
                         (s_diffCountExt << 2);

    assign s_rightValue = s_whiteSumExt * {56'b0, s_thresholdValue};

    assign s_diceResult = ((s_whiteSum != 32'd0) && (s_leftValue > s_rightValue)) ?
                          32'd1 :
                          32'd0;

    assign done   = s_isMyIse;
    assign result = (s_isMyIse == 1'b1) ? s_diceResult : 32'b0;

endmodule