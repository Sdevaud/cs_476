module jaccard #(parameter [7:0] customInstructionId = 8'd42 )
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

    wire [31:0] s_unionCount;
    wire [31:0] s_intersectionCount;
    wire [31:0] s_diffCount;

    wire [63:0] s_diffCountExt;
    wire [63:0] s_unionCountExt;
    wire [63:0] s_leftValue;
    wire [63:0] s_rightValue;

    wire [31:0] s_jaccardResult;

    assign s_unionCount = valueA;
    assign s_intersectionCount = valueB;

    assign s_diffCount = (s_unionCount >= s_intersectionCount) ?
                         (s_unionCount - s_intersectionCount) :
                         32'd0;

    assign s_diffCountExt = {32'b0, s_diffCount};
    assign s_unionCountExt = {32'b0, s_unionCount};

    assign s_leftValue = (s_diffCountExt << 6) +
                         (s_diffCountExt << 5) +
                         (s_diffCountExt << 2);

    assign s_rightValue = s_unionCountExt * {56'b0, s_thresholdValue};

    assign s_jaccardResult = ((s_unionCount != 32'd0) && (s_leftValue > s_rightValue)) ?
                             32'd1 :
                             32'd0;

    assign done   = s_isMyIse;
    assign result = (s_isMyIse == 1'b1) ? s_jaccardResult : 32'b0;

endmodule