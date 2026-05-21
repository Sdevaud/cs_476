`timescale 1ns/1ps

module hough_trig_tb();
    // Signals
    reg [7:0] theta_reg = 8'd0;
    wire [7:0] theta = theta_reg;
    wire signed [8:0] sin;
    wire signed [8:0] cos;

    // Instantiate UUT (Unit Under Test)
    houghAngleLUT uut (
        .theta(theta), .sin(sin), .cos(cos)
    );

    // Clock Generation
    reg clock = 0;
    always #5 clock = ~clock;   // 100MHz System Clock

    // Simulation Logic
    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, hough_tb);
        

        repeat (17) begin : pixel_loop
            @(posedge clock) theta_reg = theta_reg + 8'd10; // Fake pixel data
            #10; // Wait for LUT to update
            $display("Sin (%d): %d", theta, sin);
            $display("Cos (%d): %d", theta, cos);
        end


        #100 $finish;
    end
endmodule
