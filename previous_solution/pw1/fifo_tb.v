/* set the time-units for simulation */
`timescale 1ps/1ps

module fifoTestbench;

  reg reset, clock;
  initial 
    begin
      reset = 1'b1;
      clock = 1'b0;                 /* set the initial values */
      repeat (4) #5 clock = ~clock; /* generate 2 clock periods */
      reset = 1'b0;                 /* de-activate the reset */
      forever #5 clock = ~clock;    /* generate a clock with a period of 10 time-units */
    end
  
  reg s_push, s_pop; 
  wire s_full, s_empty; /* define the signals for the DUT */
  reg [7:0] s_pushData;
  wire [7:0] s_popData;
  
  fifo #(.nrOfEntries(32), /* instantiate the DUT as component */
         .bitWidth(8)) DUT
        (.clock(clock),
         .reset(reset),
         .push(s_push),
         .pop(s_pop),
         .pushData(s_pushData),
         .full(s_full),
         .empty(s_empty),
         .popData(s_popData));
  
  initial
    begin
      $dumpfile("fifoSignals.vcd"); /* define the name of the .vcd file that can be viewed by GTKWAVE */
      $dumpvars(1,DUT);             /* dump all signals inside the DUT-component in the .vcd file */
    end

  initial
    begin
      s_push = 1'b0;
      s_pop = 1'b0;
      s_pushData = 8'd0;
      @(negedge reset);            /* wait for the reset period to end */
      repeat(2) @(negedge clock);  /* wait for 2 clock cycles */
      s_push = 1'b1;
      repeat(32) @(negedge clock) s_pushData = s_pushData + 8'd1;
      s_push = 1'b0;
      s_pop = 1'b1;
      repeat(32) @(negedge clock); /* wait for 32 clock cycles */
      s_pop = 1'b0;
      $finish;                     /* finish the simulation */
    end

endmodule

