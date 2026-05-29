module pixelComparaison( input wire [8:0] pixelA,
                         input wire [8:0] pixelB,
                         input wire [8:0] threshold,
                         output wire comparaisonResult );

  wire [8:0] absPixel, Pixel;
  assign Pixel = pixelA - pixelB;
  assign absPixel =  (Pixel < 0) ? -Pixel : Pixel;

  assign comparaisonResult = (absPixel > threshold) ? 1'b1 : 1'b0;

endmodule