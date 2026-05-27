`timescale 1ns/1ps

module vote_count_tb();

    reg         start;
    reg  [31:0] valueA, valueB;
    reg  [7:0]  iseId;
    wire        done;
    wire [31:0] result;

    // Instantiate UUT with clk and rst connected
    voteCountCi #(.customInstructionId(8'hA6)) uut (
        .start(start), .valueA(valueA), .valueB(valueB),
        .iseId(iseId), .done(done), .result(result)
    );

    initial begin
        iseId  = 8'd99; 
        valueA = {4'b0000, 10'd100, 10'd50, 8'd0}; 
        start  = 1; #20;
        $display("Test 1 (Wrong ID) -> done: %b, result: %h (Expected: 0, 0)", done, result);
        start  = 0; #20;

        iseId  = 8'hA6; 
        valueA = 32'h00000000;  
        valueB = 32'h0000FF00; 
        start  = 1; #10;
        $display("Test 2 SobelA = %b, SobelB = %b", result[30], result[31]);
        start  = 0; #20;

    end

endmodule
