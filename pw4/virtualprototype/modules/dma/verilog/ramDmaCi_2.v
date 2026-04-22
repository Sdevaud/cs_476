/*
Author : Devaud Sébastien 20.04.2026
*/

module ramDmaCi #(
  parameter [7:0] custom_id = 8'hA5
)(
  // CPU <-> DMA custom instruction interface
  input  wire        start,
  input  wire        clock,
  input  wire        reset,
  input  wire [31:0] value_a,
  input  wire [31:0] value_b,
  input  wire [7:0]  ci_n,
  output wire        done,
  output wire [31:0] result,

  // Arbiter <-> DMA interface
  input  wire        grant_arbiter,

  // Slave -> DMA interface
  input  wire [31:0] address_data_slave,
  input  wire        end_transaction_slave,
  input  wire        data_valid_slave,
  input  wire        error_slave,
  input  wire        busy_slave,

  // DMA -> bus / master interface
  output wire [31:0] address_data_master,
  output wire [7:0]  burst_size_master,
  output wire [3:0]  byte_enable_master,
  output wire        request_master,
  output wire        read_not_write_master,
  output wire        begin_transaction_master
);

  wire       ci_selected        = start && (ci_n == custom_id);
  wire [2:0] ci_reg_select      = value_a[12:10];
  wire       ci_write_or_read   = value_a[9]; // write == 1
  wire [8:0] ci_mem_addr        = value_a[8:0];

  // =========================================================
  // DMA configuration registers
  // =========================================================

  wire write_bus_addr = ci_selected && (valueA[12:9] == 4'b0011);
  wire write_mem_addr = ci_selected && (valueA[12:9] == 4'b0101);
  wire write_block_sz = ci_selected && (valueA[12:9] == 4'b0111);
  wire write_burst_sz = ci_selected && (valueA[12:9] == 4'b1001);
  wire write_control  = ci_selected && (valueA[12:9] == 4'b1011);

  reg [31:0] dma_bus_start_reg;
  reg [8:0]  dma_mem_start_reg;
  reg [9:0]  dma_block_size_reg;
  reg [7:0]  dma_burst_size_reg;

  always @(posedge clock) begin
    if (reset) begin
      dma_bus_start_reg  <= 32'd0;
      dma_mem_start_reg  <= 9'd0;
      dma_block_size_reg <= 10'd0;
      dma_burst_size_reg <= 8'd0;
    end else begin
      if (write_bus_addr) dma_bus_start_reg  <= valueB;
      if (write_mem_addr) dma_mem_start_reg  <= valueB[8:0];
      if (write_block_sz) dma_block_size_reg <= valueB[9:0];
      if (write_burst_sz) dma_burst_size_reg <= valueB[7:0];
    end
  end




  assign done = (ci_selected && !reset);
  



  // =========================================================
  // reset
  // =========================================================



  if (read_action) begin
    
  end

  dualPortSSRAM #(.bitwidth(32), 
                  .nrOfEntries(512),
                  .readBeforWrite(0)) ramDma 
                 (.clockA(clock),
                  .clockB(~clock),
                  .writeEnableA(writeEnableA),
                  .writeEnableB(writeEnableB),
                  .addressA(addrA),
                  .addressB(addrB),
                  .dataInA(valueA),
                  .dataInB(valueB),
                  .dataOutA(dataA),
                  .dataOutB(dataB));


endmodule