module rgb565GrayscaleIlse #(parameter [7:0] customInstructionId = 8'h0A)
(
    input  wire        start,
    input  wire [31:0] valueA,
    input  wire [31:0] valueB,
    input  wire [7:0]  iseId,
    output wire        done,
    output wire [31:0] result
);

  wire execute = (customInstructionId == iseId) ? start : 1'b0;

  /* Convert RGB565 to Grayscale using the formula: Gray = 0.299 * R + 0.587 * G + 0.114 * B
   * We can approximate the coefficients as follows:
   * R coefficient (0.299) ≈ 54/256
   * G coefficient (0.587) ≈ 183/256
   * B coefficient (0.114) ≈ 19/256
   * This allows us to use integer arithmetic and bit shifts for efficient computation.
   */
  function [7:0] rgb565_to_gray;
    input [15:0] rgb;

    reg [7:0] r8; // shift left by 3 to convert 5 bits to 8 bits
    reg [7:0] g8; // shift left by 2 to convert 6 bits to 8 bits
    reg [7:0] b8; // shift left by 3 to convert 5 bits to 8 bits

    /* red : 54 = 32 + 16 + 4 + 2 */ 
    reg [8:0] r8_2x; // max = 248 * 2 = 496 => 9 bits
    reg [9:0] r8_4x; // max = 248 * 4 = 992 => 10 bits
    reg [11:0] r8_16x; // max = 248 * 16 = 3968 => 12 bits
    reg [12:0] r8_32x; // max = 248 * 32 = 7936 => 13 bits
    reg [13:0] sum_red; // max = 248 * 54 = 13392 => 14 bits


    /* green : 183 = 128 + 32 + 16 + 4 + 2 + 1 */

    reg [8:0] g8_2x;   // max = 252 * 2 = 504 => 9 bits
    reg [9:0] g8_4x;   // max = 252 * 4 = 1008 => 10 bits
    reg [10:0] g8_8x;  // max = 252 * 8 = 2016 => 11 bits
    reg [11:0] g8_16x; // max = 252 * 16 = 4032 => 12 bits
    reg [12:0] g8_32x; // max = 252 * 32 = 8064 => 13 bits
    reg [13:0] g8_64x; // max = 252 * 64 = 16128 => 14 bits
    reg [15:0] sum_green; // max = 252 * 183 = 46056 => 16 bits

    /* blue : 19 = 16 + 2 + 1 */
    reg [8:0] b8_2x; // max = 248 * 2 = 496 => 9 bits
    reg [11:0] b8_16x; // max = 248 * 16 = 3968 => 12 bits
    reg [12:0] sum_blue; // max = 248 * 19 = 4712 => 13 bits

    reg [15:0] sum; // max = 13392 + 46056 + 4712 = 64160 => 16 bits
    begin
      r8 = rgb[15:11] << 3; 
      g8 = rgb[10:5] << 2;
      b8 = rgb[4:0] << 3;

      /* red */
      r8_2x = r8 << 1;
      r8_4x = r8 << 2;
      r8_16x = r8 << 4;
      r8_32x = r8 << 5;
      sum_red = r8 + r8_2x + r8_4x + r8_16x + r8_32x;

      /* green */
      g8_2x = g8 << 1;
      g8_4x = g8 << 2;
      g8_8x = g8 << 3;
      g8_16x = g8 << 4;
      g8_32x = g8 << 5;
      g8_64x = g8 << 6;
      sum_green = g8 + g8_2x + g8_4x + g8_8x + g8_16x + g8_32x + g8_64x;

      /* blue */
      b8_2x = b8 << 1;
      b8_16x = b8 << 4;
      sum_blue = b8 + b8_2x + b8_16x;

      rgb565_to_gray = (sum_red + sum_green + sum_blue) >> 8; // divide by 256 to get the final grayscale value


    end
  endfunction

  wire [7:0] gray0 = rgb565_to_gray({valueA[7:0], valueA[15:8]});
  wire [7:0] gray1 = rgb565_to_gray({valueA[23:16], valueA[31:24]});
  wire [7:0] gray2 = rgb565_to_gray({valueB[7:0], valueB[15:8]});
  wire [7:0] gray3 = rgb565_to_gray({valueB[23:16], valueB[31:24]});

  assign result = execute ? {gray1, gray0, gray3, gray2} : 32'd0;
  assign done   = execute;

endmodule