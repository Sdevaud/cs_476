module sobelCompute (
    input  wire [31:0] pixel1,
    input  wire [31:0] pixel2,

    output wire [31:0]  sobel
);

    reg [11:0] thresholdValue = 12'd64; // Example threshold value for edge detection
    // Compute Sobel gradients
    // Gx = [-1  0  1]  Gy = [-1 -2 -1]
    //      [-2  0  2]       [ 0  0  0]
    //      [-1  0  1]       [ 1  2  1]

    // Extended to 9 bits to prevent overflow 
    // during multiplication by 2 (left shift)
    wire [8:0] p11e = {1'b0, pixel1[31:24]};
    wire [8:0] p12e = {1'b0, pixel1[23:16]};
    wire [8:0] p13e = {1'b0, pixel1[15:8]};
    wire [8:0] p21e = {1'b0, pixel1[7:0]};
    wire [8:0] p23e = {1'b0, pixel2[15:8]};
    wire [8:0] p31e = {1'b0, pixel2[23:16]};
    wire [8:0] p32e = {1'b0, pixel2[15:8]};
    wire [8:0] p33e = {1'b0, pixel2[7:0]};

    // Use signed arithmetic for gradient calculation 
    // to handle negative values
    wire signed [10:0] gx =
        $signed({1'b0, p13e}) +
        $signed({1'b0, p23e, 1'b0}) +
        $signed({1'b0, p33e}) -
        $signed({1'b0, p11e}) -
        $signed({1'b0, p21e, 1'b0}) -
        $signed({1'b0, p31e});

    // Use signed arithmetic for gradient calculation 
    // to handle negative values
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

    wire [7:0] sobelActual = (magnitude > thresholdValue) ? 8'hFF : 8'h00;

    assign sobel = {24'b0, sobelActual};

endmodule