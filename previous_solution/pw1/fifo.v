module fifo #(parameter nrOfEntries = 16,
              parameter bitWidth = 32)
             (input wire                 clock,
                                         reset,
                                         push,
                                         pop,
              input wire [bitWidth-1:0]  pushData,
              output wire                full,
                                         empty,
              output wire [bitWidth-1:0] popData);
  /*
   *
   * Here we define the control signals
   *
   */
  localparam nrOfPointerBits = $clog2(nrOfEntries);
  wire [nrOfPointerBits-1:0] s_pushPointer, s_popPointer;
  wire s_empty  = (s_pushPointer == s_popPointer) ? 1'b1 : 1'b0;
  wire s_full   = (s_pushPointer == (s_popPointer - { {(nrOfPointerBits-1){1'b0}}, 1'b1})) ? 1'b1 : 1'b0;
  wire s_doPush = push & ~s_full;
  wire s_doPop  = pop & ~s_empty;
  
  assign full = s_full;
  assign empty = s_empty;
  
  /*
   *
   * Here we instantiate the counters
   *
   */
  counter #(.WIDTH(nrOfPointerBits)) pushCounter
           (.reset(reset),
            .clock(clock),
            .enable(s_doPush),
            .direction(1'b1), /* a 1 is counting up, a 0 is counting down */
            .counterValue(s_pushPointer));

  counter #(.WIDTH(nrOfPointerBits)) popCounter
           (.reset(reset),
            .clock(clock),
            .enable(s_doPop),
            .direction(1'b1), /* a 1 is counting up, a 0 is counting down */
            .counterValue(s_popPointer));

  /*
   *
   * Here we instantiate the memory
   *
   */

  semiDualPortSSRAM #(.bitwidth(bitWidth),
                      .nrOfEntries(nrOfEntries),
                      .readAfterWrite(1)) fifoMemory
                     (.clockA(clock), 
                      .clockB(clock),
                      .writeEnable(s_doPush),
                      .addressA(s_pushPointer), 
                      .addressB(s_popPointer),
                      .dataIn(pushData),
                      .dataOutA(), 
                      .dataOutB(popData));
endmodule

