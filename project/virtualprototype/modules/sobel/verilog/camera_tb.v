`timescale 1ns/1ps

module tb_camera();
    // Signals
    reg clock = 0, pclk = 0, reset = 0;
    reg hsync = 0, vsync = 0;
    reg [7:0] camData = 0;
    
    // CI Interface
    reg ciStart = 0, ciCke = 1;
    reg [7:0] ciN = 8'd0;
    reg [31:0] ciValueA = 0, ciValueB = 0;
    wire [31:0] ciResult;
    wire ciDone;

    // Bus Interface
    wire requestBus, beginTransactionOut, endTransactionOut, dataValidOut;
    wire [31:0] addressDataOut;
    reg busGrant = 0, busyIn = 0, busErrorIn = 0;

    // Instantiate UUT (Unit Under Test)
    camera #(.customInstructionId(8'd0), .clockFrequencyInHz(2000)) uut (
        .clock(clock), .pclk(pclk), .reset(reset),
        .hsync(hsync), .vsync(vsync), .camData(camData),
        .ciStart(ciStart), .ciCke(ciCke), .ciN(ciN),
        .ciValueA(ciValueA), .ciValueB(ciValueB),
        .ciResult(ciResult), .ciDone(ciDone),
        .requestBus(requestBus), .busGrant(busGrant),
        .beginTransactionOut(beginTransactionOut), .addressDataOut(addressDataOut),
        .endTransactionOut(endTransactionOut), .busyIn(busyIn), .busErrorIn(busErrorIn)
    );

    // Clock Generation
    always #5 clock = ~clock;   // 100MHz System Clock
    always #25 pclk = ~pclk;    // 20MHz Camera Clock

    // Simulation Logic
    initial begin
        $dumpfile("simulation.vcd");
        $dumpvars(0, tb_camera);
        
        // 1. Reset
        reset = 1;
        #100 reset = 0;
        #100 hsync = 1;
        #100 hsync = 0;

        // 2. Mock a Video Frame (4 lines, 16 pixels each)
        vsync = 1; #200; vsync = 0; // Start Frame
        
        repeat (4) begin : line_loop
            #100 hsync = 1;
            repeat (16) begin : pixel_loop
                @(posedge pclk) camData = camData + 1; // Fake pixel data
            end
            hsync = 0;
            #500; // Gap between lines
        end
        
        #1000;
        
        // 3. Test Custom Instruction: Read Pixel Count (ciValueA = 0)
        ciN = 8'd0; ciValueA = 32'd0; ciStart = 1;
        #10 @(posedge clock);
        ciStart = 0;
        $display("CI Result (Pixel Count): %d", ciResult);

        #100 $finish;
    end

    // 4. Simple Bus Arbiter Logic
    always @(posedge clock) begin
        if (requestBus) begin
            #20 busGrant = 1;
        end
        if (endTransactionOut) begin
            busGrant = 0;
        end
    end

endmodule
