`timescale 1ns / 1ps

module tb_hough_rho;

    reg         clk;   // Minimal Change: Added clock
    reg         rst;   // Minimal Change: Added reset
    reg         start;
    reg  [31:0] valueA, valueB;
    reg  [7:0]  iseId;
    wire        done;
    wire [31:0] result;

    // Instantiate UUT with clk and rst connected
    houghCi #(.customInstructionId(8'hA7)) uut (
        .clock(clk), .reset(rst), // Minimal Change: Connected new ports
        .start(start), .valueA(valueA), .valueB(valueB),
        .iseId(iseId), .done(done), .result(result)
    );

    // Minimal Change: 10ns Clock Generator
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, tb_hough_rho);
        
        // Init
        clk = 0; rst = 1; start = 0; valueA = 0; valueB = 0; iseId = 0;
        #20;
        rst = 0; // Drop reset after a couple clock cycles
        #80;
        
        // Test 1: Wrong ID (Should ignore)
        iseId  = 8'd99; 
        // Fixed concatenation layout: {sobel(4b), xA(10b), y(10b), theta(8b)}
        valueA = {4'b0000, 10'd100, 10'd50, 8'd0}; 
        start  = 1; #10;
        $display("Test 1 (Wrong ID) -> done: %b, result: %h (Expected: 0, 0)", done, result);
        start  = 0; #10;

        // Test 2: Correct ID, Theta = 0 (Vote mode - outputs raw rhos)
        iseId  = 8'hA7; 
        // valueA: Sobel=4'b0111, xA=20, y=40, theta=0
        valueA = {4'b1111, 10'd40, 10'd20, 8'd0};  
        // valueB: OpMode=2'b00, xD=42, xC=44, xB=46
        valueB = {2'b00, 10'd42, 10'd44, 10'd46}; 
        start  = 1; #10;
        $display("Test 2 (Th=0)     -> done: %b, rhoA: %d, rhoB: %d,  rhoC: %d, rhoD: %d", done, result[31:24], result[23:16], result[15:8], result[7:0]);
        start  = 0; #10;

        // Test 3: Correct ID, Theta = 135
        valueA = {4'b1111, 10'd100, 10'd50, 8'd135};  
        valueB = {2'b00, 10'd40, 10'd300, 10'd200};
        start  = 1; #10;
        $display("Test 3 (Th=135)   -> done: %b, rhoA: %0d, rhoB: %0d,  rhoC: %0d, rhoD: %0d", done, result[31:24], result[23:16], result[15:8], result[7:0]);
        start  = 0; #10;

        // Test 3.2: Correct ID, Theta = 135
        valueA = {4'b1111, 10'd100, 10'd50, 8'd135};  
        valueB = {2'b00, 10'd40, 10'd300, 10'd200};
        start  = 1; #10;
        $display("Test 3.2 (Th=135) -> done: %b, rhoA: %0d, rhoB: %0d,  rhoC: %0d, rhoD: %0d", done, result[31:24], result[23:16], result[15:8], result[7:0]);
        start  = 0; #10;

        // Test 3.3: Correct ID, Theta = 135
        valueA = 32'h60040000; // Sobel=4'b0110, xA=0, y=0, theta=0  
        valueB = 32'h00701403;
        start  = 1; #10;
        $display("Real Test 3.3 (Th=0) -> done: %b, rhoA: %0d, rhoB: %0d,  rhoC: %0d, rhoD: %0d", done, result[31:24], result[23:16], result[15:8], result[7:0]);
        start  = 0; #10;

        // Test 3.4: Correct ID, Theta = 0
        valueA = {4'b1111, 10'd100, 10'd50, 8'd90};  
        valueB = {2'b00, 10'd40, 10'd300, 10'd200};
        start  = 1; #10;
        $display("Test 3.4 (Th=0) -> done: %b, rhoA: %0d, rhoB: %0d,  rhoC: %0d, rhoD: %0d", done, result[31:24], result[23:16], result[15:8], result[7:0]);
        start  = 0; #10;

        // Test 4: Minimal addition to verify Read-and-Clear feature!
        // Read index 110 (Let's see total accumulated votes stored here)
        valueA = {24'd0, 8'd101}; 
        valueB = {2'b01, 30'd0}; // OpMode 2'b01 triggers Read-and-Clear
        start  = 1; #10;
        $display("Test 4 (Readback) -> Total Accumulated votes at Rho index 101: %d", result);
        start  = 0; #5;

        rst = 1; #20; // Reset the accumulator to clear previous votes
        rst = 0; #20;

        // Test 4: Minimal addition to verify Read-and-Clear feature!
        // Read index 110 (Let's see total accumulated votes stored here)
        valueA = {24'd0, 8'd101}; 
        valueB = {2'b01, 30'd1}; // OpMode 2'b01 triggers Read-and-Clear
        start  = 1; #10;
        $display("Test 4.2 (Readback) -> Total Accumulated votes at Rho index 101: %d", result);
        start  = 0; #5;

        $finish;
    end
endmodule
