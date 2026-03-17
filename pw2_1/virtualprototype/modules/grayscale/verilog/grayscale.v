module rgb565GrayscaleIlse #(parameter customInstructionId = 8'd0 )
                            ( input wire          start,
                              input wire [31:0]   valueA,
                                                  valueB,
                              input wire [7:0]    iseId,
                              output wire         done,
                              output wire [31:0]  result);

wire execute = (customInstructionId == iseId) ? start : 1'b0;

function [7:0] rgb565_to_gray;
  input [4:0] r;
  input [5:0] g;
  input [4:0] b;
  reg [15:0] sum;
  begin
    sum = (16'd54 * r) + (16'd183 * g) + (16'd19 * b);
    rgb565_to_gray = sum >> 8;
  end
endfunction

wire [7:0] gray0 = rgb565_to_gray(valueA[15:11], valueA[10:5], valueA[4:0]);
wire [7:0] gray1 = rgb565_to_gray(valueA[31:27], valueA[26:21], valueA[20:16]);
wire [7:0] gray2 = rgb565_to_gray(valueB[15:11], valueB[10:5], valueB[4:0]);
wire [7:0] gray3 = rgb565_to_gray(valueB[31:27], valueB[26:21], valueB[20:16]);

assign result = execute ? {gray3, gray2, gray1, gray0} : 32'd0;
assign done   = execute;

endmodule

