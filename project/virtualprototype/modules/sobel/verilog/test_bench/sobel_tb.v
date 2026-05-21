`timescale 1ns / 1ps

/*
iverilog -s tb_sobelCompute -o sobel_tb ../sobel.v sobel_tb.v
./sobel_tb
gtkwave sobelSignals.vcd
*/

module tb_sobelCompute;

    // Inputs
    reg [7:0] p11;
    reg [7:0] p12;
    reg [7:0] p13;
    reg [7:0] p21;
    reg [7:0] p23;
    reg [7:0] p31;
    reg [7:0] p32;
    reg [7:0] p33;

    reg [10:0] s_lineCountReg;
    reg [10:0] s_pixelCountReg;

    // Output
    wire [7:0] sobelResult;

    // Instantiate DUT
    sobelCompute dut (
        .p11(p11),
        .p12(p12),
        .p13(p13),
        .p21(p21),
        .p23(p23),
        .p31(p31),
        .p32(p32),
        .p33(p33),

        .s_lineCountReg(s_lineCountReg),
        .s_pixelCountReg(s_pixelCountReg),
        .thresholdValue(11'd60), // Seuil de détection

        .sobelResult(sobelResult)
    );

    // Task pour appliquer un motif 3x3
    task apply_pixels;
        input [7:0] t_p11;
        input [7:0] t_p12;
        input [7:0] t_p13;
        input [7:0] t_p21;
        input [7:0] t_p23;
        input [7:0] t_p31;
        input [7:0] t_p32;
        input [7:0] t_p33;
        begin
            p11 = t_p11;
            p12 = t_p12;
            p13 = t_p13;
            p21 = t_p21;
            p23 = t_p23;
            p31 = t_p31;
            p32 = t_p32;
            p33 = t_p33;
        end
    endtask

    initial begin
        // Génération du fichier pour GTKWave
        $dumpfile("sobelSignals.vcd");
        $dumpvars(0, tb_sobelCompute);

        $display("========================================");
        $display(" Debut du testbench sobelCompute");
        $display("========================================");

        // Initialisation
        p11 = 8'd0;
        p12 = 8'd0;
        p13 = 8'd0;
        p21 = 8'd0;
        p23 = 8'd0;
        p31 = 8'd0;
        p32 = 8'd0;
        p33 = 8'd0;

        s_lineCountReg  = 11'd0;
        s_pixelCountReg = 11'd0;

        #10;

        // ------------------------------------------------------------
        // Test 1 : bordure ligne <= 1
        // Résultat attendu : 0x00
        // ------------------------------------------------------------
        $display("\nTest 1 : bordure ligne");

        s_lineCountReg  = 11'd1;
        s_pixelCountReg = 11'd10;

        apply_pixels(
            8'd0,   8'd0,   8'd255,
            8'd0,           8'd255,
            8'd0,   8'd0,   8'd255
        );

        #10;

        if (sobelResult !== 8'h00)
            $display("ERREUR Test 1 : sobelResult = %h, attendu = 00", sobelResult);
        else
            $display("OK Test 1 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Test 2 : bordure pixel <= 6
        // Résultat attendu : 0x00
        // ------------------------------------------------------------
        $display("\nTest 2 : bordure pixel");

        s_lineCountReg  = 11'd10;
        s_pixelCountReg = 11'd6;

        apply_pixels(
            8'd0,   8'd0,   8'd255,
            8'd0,           8'd255,
            8'd0,   8'd0,   8'd255
        );

        #10;

        if (sobelResult !== 8'h00)
            $display("ERREUR Test 2 : sobelResult = %h, attendu = 00", sobelResult);
        else
            $display("OK Test 2 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Test 3 : image uniforme
        // Gx = 0, Gy = 0
        // Résultat attendu : 0x00
        // ------------------------------------------------------------
        $display("\nTest 3 : image uniforme");

        s_lineCountReg  = 11'd10;
        s_pixelCountReg = 11'd10;

        apply_pixels(
            8'd100, 8'd100, 8'd100,
            8'd100,         8'd100,
            8'd100, 8'd100, 8'd100
        );

        #10;

        if (sobelResult !== 8'h00)
            $display("ERREUR Test 3 : sobelResult = %h, attendu = 00", sobelResult);
        else
            $display("OK Test 3 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Test 4 : contour vertical fort
        //
        // Matrice :
        // 0   0   255
        // 0   x   255
        // 0   0   255
        //
        // Résultat attendu : 0xFF
        // ------------------------------------------------------------
        $display("\nTest 4 : contour vertical fort");

        s_lineCountReg  = 11'd10;
        s_pixelCountReg = 11'd10;

        apply_pixels(
            8'd0, 8'd0, 8'd255,
            8'd0,       8'd255,
            8'd0, 8'd0, 8'd255
        );

        #10;

        if (sobelResult !== 8'hFF)
            $display("ERREUR Test 4 : sobelResult = %h, attendu = FF", sobelResult);
        else
            $display("OK Test 4 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Test 5 : contour horizontal fort
        //
        // Matrice :
        // 0    0    0
        // x    x    x
        // 255  255  255
        //
        // Résultat attendu : 0xFF
        // ------------------------------------------------------------
        $display("\nTest 5 : contour horizontal fort");

        s_lineCountReg  = 11'd10;
        s_pixelCountReg = 11'd10;

        apply_pixels(
            8'd0,   8'd0,   8'd0,
            8'd0,           8'd0,
            8'd255, 8'd255, 8'd255
        );

        #10;

        if (sobelResult !== 8'hFF)
            $display("ERREUR Test 5 : sobelResult = %h, attendu = FF", sobelResult);
        else
            $display("OK Test 5 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Test 6 : petite variation sous le seuil
        // Résultat attendu : 0x00
        // ------------------------------------------------------------
        $display("\nTest 6 : petite variation");

        s_lineCountReg  = 11'd10;
        s_pixelCountReg = 11'd10;

        apply_pixels(
            8'd10, 8'd10, 8'd15,
            8'd10,        8'd15,
            8'd10, 8'd10, 8'd15
        );

        #10;

        if (sobelResult !== 8'h00)
            $display("ERREUR Test 6 : sobelResult = %h, attendu = 00", sobelResult);
        else
            $display("OK Test 6 : sobelResult = %h", sobelResult);

        // ------------------------------------------------------------
        // Fin simulation
        // ------------------------------------------------------------
        $display("\n========================================");
        $display(" Fin du testbench sobelCompute");
        $display("========================================");

        $finish;
    end

endmodule