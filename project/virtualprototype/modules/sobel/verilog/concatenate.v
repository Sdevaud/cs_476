module concatenate_line1xline2 #(parameter [7:0] customInstructionId = 8'd0 )
                           ( input wire         start,
                             input wire [31:0]  pixel1,
                                                pixel2,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );


    
    /* We concatenate pixel here*/
    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;
    assign done   = s_isMyIse;
    wire [31:0] concatenate = {pixel1[31:24], pixel1[23:16], pixel1[15:8], pixel2[31:24]};
    assign result = (s_isMyIse == 1'b1) ? concatenate : 32'd0;

endmodule

module concatenate_line2xline3 #(parameter [7:0] customInstructionId = 8'd0 )
                           ( input wire         start,
                             input wire [31:0]  pixel1,
                                                pixel2,
                             input wire [7:0]   iseId,
                             output wire        done,
                             output wire [31:0] result );


    
    /* We concatenate pixel here*/
    wire s_isMyIse = (iseId == customInstructionId) ? start : 1'b0;
    assign done   = s_isMyIse;
    wire [31:0] concatenate = {pixel1[15:8], pixel2[31:24], pixel1[23:16], pixel2[15:8]};
    assign result = (s_isMyIse == 1'b1) ? concatenate : 32'd0;

endmodule