module sevenSegScanning (input wire        clock,
                                           reset,
                         input wire [23:0] threeDigits,
                         output wire [2:0] digitSelect,
                         output reg  [7:0] segmentSelect);

  reg [16:0] clockDivideReg;
  wire clockDivideZero = (clockDivideReg == 17'd0) ? 1'b1 : 1'b0;
  
  always @(posedge clock)
    clockDivideReg <= (reset == 1'b1 || clockDivideZero == 1'b1) ? 17'd74249 : clockDivideReg - 1;

  reg [3:0] digitSelectReg;
  
  always @(posedge clock)
    digitSelectReg <= ((digitSelectReg == 3'd0 && clockDivideZero == 1'b1) || reset == 1'b1) ? 3'd2 : 
                      (clockDivideZero == 1'b1) ? digitSelectReg - 1 : digitSelectReg;
  
  assign digitSelect = digitSelectReg;
  
  always @*
    case (digitSelectReg)
      2'd2    : segmentSelect <= ~threeDigits[7:0];
      2'd1    : segmentSelect <= ~threeDigits[15:8];
      default : segmentSelect <= ~threeDigits[23:16];
    endcase
endmodule
