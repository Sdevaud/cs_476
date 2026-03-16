module profileCi #( parameter [7:0] customId = 8'h0B) // Example ID 0x0B
  ( input wire start,
    clock,
    reset,
    stall,
    busIdle,
    input wire [31:0] valueA,
    valueB,
    input wire [7:0] ciN,
    output wire done,
    output wire [31:0] result );

  reg counter0_on, counter1_on, counter2_on, counter3_on;
  wire execute = (ciN == customId) && start;

  always @(posedge clock)
  begin
    if (reset)
    begin
      counter0_on <= 1'b0;
      counter1_on <= 1'b0;
      counter2_on <= 1'b0;
      counter3_on <= 1'b0;
    end
    else if (execute)
    begin
      counter0_on <= (counter0_on | valueB[0]) & ~valueB[4];
      counter1_on <= (counter1_on | valueB[1]) & ~valueB[5];
      counter2_on <= (counter2_on | valueB[2]) & ~valueB[6];
      counter3_on <= (counter3_on | valueB[3]) & ~valueB[7];
    end
  end

  wire [31:0] counter0, counter1, counter2, counter3;

  wire reset_counter0 = (reset) ? 1'b1 : (valueB[8]) ? execute : 1'b0;
  wire reset_counter1 = (reset) ? 1'b1 : (valueB[9]) ? execute : 1'b0;
  wire reset_counter2 = (reset) ? 1'b1 : (valueB[10]) ? execute : 1'b0;
  wire reset_counter3 = (reset) ? 1'b1 : (valueB[11]) ? execute : 1'b0;

  counter #(.WIDTH(32)) Counter0
          (.reset(reset_counter0),
           .clock(clock),
           .enable(counter0_on),
           .direction(1'b1),
           .counterValue(counter0));

  counter #(.WIDTH(32)) Counter1
          (.reset(reset_counter1),
           .clock(clock),
           .enable(counter1_on & stall),
           .direction(1'b1),
           .counterValue(counter1));

  counter #(.WIDTH(32)) Counter2
          (.reset(reset_counter2),
           .clock(clock),
           .enable(counter2_on & busIdle),
           .direction(1'b1),
           .counterValue(counter2));

  counter #(.WIDTH(32)) Counter3
          (.reset(reset_counter3),
           .clock(clock),
           .enable(counter3_on),
           .direction(1'b1),
           .counterValue(counter3));

  // Output      
  wire [31:0] selected_val =
       (valueA[1:0] == 2'd0) ? counter0 :
       (valueA[1:0] == 2'd1) ? counter1 :
       (valueA[1:0] == 2'd2) ? counter2 : counter3;

  assign done = (ciN == customId) && start;
  assign result = (done) ? selected_val : 32'h0;

endmodule
