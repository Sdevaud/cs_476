`timescale 1ns / 1ps

module tb_hough_rho;

    reg         start;
    reg  [31:0] valueA, valueB;
    reg  [7:0]  iseId;
    wire        done;
    wire [31:0] result;

    // Instantiate UUT
    houghCi #(.customInstructionId(8'hA7)) uut (
        .start(start), .valueA(valueA), .valueB(valueB),
        .iseId(iseId), .done(done), .result(result)
    );

    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, tb_hough_rho);
        
        // Init
        start = 0; valueA = 0; valueB = 0; iseId = 0;
        #100;
        
        // Test 1: Wrong ID (Should ignore)
        iseId  = 8'd99; 
        valueA = {4'd0, 10'd50, 10'd100, 8'd0}; // y=50, x=100, th=0
        start  = 1; #10;
        $display("Test 1 (Wrong ID) -> done: %b, result: %h (Expected: 0, 0)", done, result);
        start  = 0; #10;

        // Test 2: Correct ID, Theta = 0 (Cos=256, Sin=0 -> result should equal X)
        iseId  = 8'hA7; 
        valueA = {4'd0, 10'd50, 10'd100, 8'd0};  // xA=100
        valueB = {4'd0, 10'd200, 10'd300, 8'd0}; // xB=300
        start  = 1; #10;
        $display("Test 2 (Th=0)     -> done: %b, rhoA: %0d, rhoB: %0d", done, result[31:16], result[15:0]);
        start  = 0; #10;


        valueA = {4'd0, 10'd50, 10'd100, 8'd90};  // xA=100
        valueB = {4'd0, 10'd200, 10'd300, 8'd135}; // xB=300
        start  = 1; #10;
        $display("Test 2 (Th=0)     -> done: %b, rhoA: %0d, rhoB: %0d", done, result[31:16], $signed(result[15:0]));
        start  = 0; #10;




        valueA = {4'd0, 10'd50, 10'd100, 8'd45};  // xA=100
        valueB = {4'd0, 10'd200, 10'd300, 8'd45}; // xB=300
        start  = 1; #10;
        $display("Test 2 (Th=0)     -> done: %b, rhoA: %0d, rhoB: %0d", done, result[31:16], result[15:0]);
        start  = 0; #10;

        $finish;
    end
endmodule
