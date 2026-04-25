/*
Author : Till Beyer 14.04.2026
*/


`timescale 1ps/1ps

module ramDmaCi_tb;

	localparam [7:0] CUSTOM_ID = 8'hA5;

	reg start;
	reg clock;
	reg reset;
	reg [31:0] valueA;
	reg [31:0] valueB;
	reg [7:0] ciN;

	wire done;
	wire [31:0] result;

	ramDmaCi #(.customId(CUSTOM_ID)) dut (
		.start(start),
		.clock(clock),
		.reset(reset),
		.valueA(valueA),
		.valueB(valueB),
		.ciN(ciN),
		.done(done),
		.result(result)
	);

	always #5 clock = ~clock;

	task automatic issue_cmd(
		input [31:0] valueA_i,
		input [31:0] valueB_i,
		input [7:0] ciN_i
	);
	begin
		@(negedge clock);
		start = 1'b1;
		valueA = valueA_i;
		valueB = valueB_i;
		ciN = ciN_i;
        
        @(negedge clock); // wait one cycle

		@(negedge clock);
		start = 1'b0;
		valueA = 32'd0;
		valueB = 32'd0;
		ciN = 8'd0;
	end
	endtask

	task automatic dma_write(
		input [8:0] addr,
		input [31:0] data
	);
	begin
		issue_cmd({22'd0, 1'b1, addr}, data, CUSTOM_ID);
		@(posedge clock);
	end
	endtask

	task automatic dma_read_and_check(
		input [8:0] addr,
		input [31:0] expected
	);
	begin
		issue_cmd({22'd0, 1'b0, addr}, 32'd0, CUSTOM_ID);
		repeat (2) @(posedge clock);

		if (result !== expected) begin
			$display("ERROR  addr=%0d expected=0x%08h got=0x%08h", addr, expected, result);
		end else begin
			$display("OK     addr=%0d value=0x%08h", addr, result);
		end
	end
	endtask

	initial begin
		clock = 1'b0;
		start = 1'b0;
		reset = 1'b1;
		valueA = 32'd0;
		valueB = 32'd0;
		ciN = 8'd0;

		repeat (3) @(posedge clock);
		reset = 1'b0;

		@(negedge clock);
		start = 1'b1;
		valueA = {22'd0, 1'b1, 9'd12};
		valueB = 32'h1111_2223;
		ciN = 8'h00;
		#1;
		if (done !== 1'b0) begin
			$display("ERROR  done even though wrong custom instruction ID");
		end

		@(negedge clock);
		start = 1'b0;
		valueA = 32'd0;
		valueB = 32'd0;
		ciN = 8'd0;

		dma_write(9'd5, 32'h1111_1111);
		dma_write(9'd9, 32'h1234_5678);

		dma_read_and_check(9'd5, 32'h1111_1111);
		dma_read_and_check(9'd9, 32'h1234_5678);

		dma_write(9'd5, 32'h3333_3333);
		dma_read_and_check(9'd5, 32'h3333_3333);

        dma_read_and_check(9'd8, 32'h1234_5678); // Wrong address -> this should throw an error

		$finish;
	end

    initial begin
        $dumpfile("ramDmaCiSignals.vcd"); /* define the name of the .vcd file that can be viewed by GTKWAVE */
        $dumpvars(1, dut); /* dump all signals inside the DUT-component in the .vcd file */
    end

endmodule
