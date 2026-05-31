module threshold #(parameter [7:0] customInstructionId = 8'd45 )
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
            s_thresholdValue <= 8'd20;
        end else if (s_writeThreshold) begin
            s_thresholdValue <= valueB[7:0];
        end
    end

    wire [31:0] s_difference;
    wire [31:0] s_differenceTimes100;
    wire [31:0] s_thresholdLimit;
    wire [31:0] s_thresholdResult;

    assign s_difference = (valueA > valueB) ? valueA - valueB : valueB - valueA;

    // s_difference * 100 = s_difference * 64 + s_difference * 32 + s_difference * 4
    assign s_differenceTimes100 = (s_difference << 6) + (s_difference << 5) + (s_difference << 2);

    assign s_thresholdLimit = valueA * s_thresholdValue;

    assign s_thresholdResult = (s_differenceTimes100 > s_thresholdLimit) ? 32'd1 : 32'd0;

    assign done   = s_isMyIse;
    assign result = (s_isMyIse == 1'b1 && s_writeThreshold == 1'b0) ? s_thresholdResult : 32'b0;

endmodule