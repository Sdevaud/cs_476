module sobelCompute (
    input  wire [7:0]  p11,
    input  wire [7:0]  p12,
    input  wire [7:0]  p13,
    input  wire [7:0]  p21,
    input  wire [7:0]  p23,
    input  wire [7:0]  p31,
    input  wire [7:0]  p32,
    input  wire [7:0]  p33,

    input  wire [10:0] s_lineCountReg,
    input  wire [10:0] s_pixelCountReg,
    input  wire [10:0] thresholdValue,

    output wire [7:0]  sobelResult
);

    // Compute Sobel gradients
    // Gx = [-1  0  1]  Gy = [-1 -2 -1]
    //      [-2  0  2]       [ 0  0  0]
    //      [-1  0  1]       [ 1  2  1]

    // Extended to 9 bits to prevent overflow during multiplication by 2 (left shift)
    wire [8:0] p11e = {1'b0, p11};
    wire [8:0] p12e = {1'b0, p12};
    wire [8:0] p13e = {1'b0, p13};
    wire [8:0] p21e = {1'b0, p21};
    wire [8:0] p23e = {1'b0, p23};
    wire [8:0] p31e = {1'b0, p31};
    wire [8:0] p32e = {1'b0, p32};
    wire [8:0] p33e = {1'b0, p33};

    // Use signed arithmetic for gradient calculation to handle negative values
    wire signed [10:0] gx =
        $signed({1'b0, p13e}) +
        $signed({1'b0, p23e, 1'b0}) +
        $signed({1'b0, p33e}) -
        $signed({1'b0, p11e}) -
        $signed({1'b0, p21e, 1'b0}) -
        $signed({1'b0, p31e});

    // Use signed arithmetic for gradient calculation to handle negative values
    wire signed [10:0] gy =
        $signed({1'b0, p31e}) +
        $signed({1'b0, p32e, 1'b0}) +
        $signed({1'b0, p33e}) -
        $signed({1'b0, p11e}) -
        $signed({1'b0, p12e, 1'b0}) -
        $signed({1'b0, p13e});

    // Prevent overflow during addition of absolute values
    wire [11:0] magnitude =
        (gx < 0 ? -gx : gx) +
        (gy < 0 ? -gy : gy);

    wire isBorder = (s_lineCountReg <= 11'd1) || (s_pixelCountReg <= 11'd6); 

    wire [7:0] sobelActual = (magnitude > thresholdValue) ? 8'hFF : 8'h00;

    // Final Result: If on border, force black. Otherwise, use Sobel.
    assign sobelResult = (isBorder) ? 8'h00 : sobelActual;

endmodule