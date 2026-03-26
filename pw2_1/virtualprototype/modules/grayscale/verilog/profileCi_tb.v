/*
Author : Devaud Sébastien 11.03.2026 v1.0
some of the test was generate with copilot

this verilog file descripe a module for perform a test becnh of the file "profil.v"

for more information follow this PDF : 
https://moodle.epfl.ch/pluginfile.php/3323602/mod_resource/content/4/grayscale.pdf
from the course " CS-476 Embedded system design" of mister Kluter from EPFL

launch : 
iverilog -s profileCiTestbench -o testbench counter.v profileCi.v profileCi_tb.v
./testbench 
gtkwave profileCiSignals.vcd
*/
`timescale 1ps/1ps

module profileCiTestbench;

  reg         start;
  reg         clock;
  reg         reset;
  reg         stall;
  reg         busIdle;
  reg [31:0]  valueA;
  reg [31:0]  valueB;
  reg [7:0]   ciN;
  wire        done;
  wire [31:0] result;

  profileCi #(.customId(8'h42)) DUT (
    .start(start),
    .clock(clock),
    .reset(reset),
    .stall(stall),
    .busIdle(busIdle),
    .valueA(valueA),
    .valueB(valueB),
    .ciN(ciN),
    .done(done),
    .result(result)
  );

  initial begin
    clock   = 1'b0;
    reset   = 1'b1;
    start   = 1'b0;
    stall   = 1'b0;
    busIdle = 1'b0;
    valueA  = 32'd0;
    valueB  = 32'd0;
    ciN     = 8'd0;

    repeat (4) #5 clock = ~clock;
    reset = 1'b0;
    forever #5 clock = ~clock;
  end

  initial begin
    $dumpfile("profileCiSignals.vcd");
    $dumpvars(0, DUT);
  end

  task ci_cmd;
    input [31:0] a;
    input [31:0] b;
    begin
      @(negedge clock);
      start  = 1'b1;
      ciN    = 8'h42;
      valueA = a;
      valueB = b;
      @(negedge clock);
      start  = 1'b0;
      ciN    = 8'h00;
      valueA = 32'd0;
      valueB = 32'd0;
    end
  endtask

  task wrong_ci_cmd;
    input [31:0] a;
    input [31:0] b;
    begin
      @(negedge clock);
      start  = 1'b1;
      ciN    = 8'h24;
      valueA = a;
      valueB = b;
      @(negedge clock);
      start  = 1'b0;
      ciN    = 8'h00;
      valueA = 32'd0;
      valueB = 32'd0;
    end
  endtask

  task read_counter;
    input [1:0] sel;
    begin
      @(negedge clock);
      start  = 1'b1;
      ciN    = 8'h42;
      valueA = {30'd0, sel};
      valueB = 32'd0;
      #1;
      $display("[%0t] READ counter%0d -> result = %0d, done = %0b",
               $time, sel, result, done);
      @(negedge clock);
      start  = 1'b0;
      ciN    = 8'h00;
      valueA = 32'd0;
      valueB = 32'd0;
    end
  endtask

  task expect_result;
    input [31:0] expected;
    begin
      // #1;
      if (result !== expected)
        $display("[%0t] ERROR: expected %0d, got %0d", $time, expected, result);
      else
        $display("[%0t] OK: result = %0d", $time, result);
    end
  endtask

  task read_and_expect;
    input [1:0] sel;
    input [31:0] expected;
    begin
      @(negedge clock);
      start  = 1'b1;
      ciN    = 8'h42;
      valueA = {30'd0, sel};
      valueB = 32'd0;
      #1;
      $display("[%0t] READ counter%0d -> done = %0b",
               $time, sel, done);

      if (result !== expected)
        $display("[%0t] ERROR: expected %0d, got %0d", $time, expected, result);
      else
        $display("[%0t] OK: result = %0d", $time, result);

      @(negedge clock);
      start  = 1'b0;
      ciN    = 8'h00;
      valueA = 32'd0;
      valueB = 32'd0;
    end
  endtask

  initial begin
    @(negedge reset);
    repeat (2) @(negedge clock);

    // --------------------------------------------------
    // Test 0 : try a bad ciN, nothings have to happen
    // --------------------------------------------------
    $display("\n--- Test 0: wrong custom instruction should do nothing ---");
    wrong_ci_cmd(32'd0, 32'h1);
    repeat (3) @(negedge clock);
    // read_counter(2'd0);
    // expect_result(32'd0);
    read_and_expect(2'd0, 32'd0);

    // --------------------------------------------------
    // Test 1 : enable counter0, count all the cycles
    // --------------------------------------------------
    $display("\n--- Test 1: enable counter0 ---");
    ci_cmd(32'd0, 32'h1);
    repeat (5) @(negedge clock);
    read_and_expect(2'd0, 32'd6);

    // --------------------------------------------------
    // Test 2 : disable counter0, have to stop
    // --------------------------------------------------
    $display("\n--- Test 2: disable counter0 ---");
    ci_cmd(32'd0, 32'h1 << 4);
    repeat (5) @(negedge clock);
    read_and_expect(2'd0, 32'd9);

    // --------------------------------------------------
    // Test 3 : reset counter0
    // --------------------------------------------------
    $display("\n--- Test 3: reset counter0 ---");
    ci_cmd(32'd0, (32'h1 << 8));
    read_and_expect(2'd0, 32'd0);

    // --------------------------------------------------
    // Test 4 : enable counter1, count stall
    // --------------------------------------------------
    $display("\n--- Test 4: counter1 counts only stall cycles ---");
    ci_cmd(32'd0, 32'h1 << 1);

    stall = 1'b1; repeat (3) @(negedge clock);
    stall = 1'b0; repeat (40) @(negedge clock);
    stall = 1'b1; repeat (2) @(negedge clock);
    stall = 1'b0;

    read_and_expect(2'd1, 32'd5);

    // --------------------------------------------------
    // Test 5 : enable counter2
    // --------------------------------------------------
    $display("\n--- Test 5: counter2 counts only busIdle cycles ---");
    ci_cmd(32'd0, 32'h1 << 2);

    busIdle = 1'b1; repeat (4) @(negedge clock);
    busIdle = 1'b0; repeat (3) @(negedge clock);
    busIdle = 1'b1; repeat (1) @(negedge clock);
    busIdle = 1'b0;

    read_and_expect(2'd2, 32'd5);

    // --------------------------------------------------
    // Test 6 : enable counter3, count all the cycles
    // --------------------------------------------------
    $display("\n--- Test 6: enable counter3 ---");
    ci_cmd(32'd0, 32'h1 << 3);
    repeat (7) @(negedge clock);
    read_and_expect(2'd3, 32'd8);

    // --------------------------------------------------
    // Test 7 : reset counter1 and counter2
    // --------------------------------------------------
    $display("\n--- Test 7: individual reset counter1 and counter2 ---");
    ci_cmd(32'd0, (32'h1 << 9) | (32'h1 << 10));

    read_and_expect(2'd1, 32'd0);

    read_and_expect(2'd2, 32'd0);

    read_and_expect(2'd3, 32'd16);

    // --------------------------------------------------
    // Test 8 : reset global
    // --------------------------------------------------
    $display("\n--- Test 8: global reset ---");
    @(negedge clock);
    reset = 1'b1;
    @(negedge clock);
    reset = 1'b0;

    read_counter(2'd0);
    expect_result(32'd0);

    read_counter(2'd1);
    expect_result(32'd0);

    read_counter(2'd2);
    expect_result(32'd0);

    read_counter(2'd3);
    expect_result(32'd0);

    $display("\nAll tests completed.");
    $finish;
  end

endmodule
