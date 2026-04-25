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
  output reg  [31:0] address_data_master,
  output reg  [7:0]  burst_size_master,
  output reg  [3:0]  byte_enable_master,
  output reg         request_master,
  output reg         read_not_write_master,
  output reg         begin_transaction_master
);

  wire       ci_selected      = start && (ci_n == custom_id);
  wire [2:0] ci_reg_select    = value_a[12:10];
  wire       ci_write_or_read = value_a[9]; // write == 1
  wire [8:0] ci_mem_addr      = value_a[8:0];
  wire       ci_mem_space     = (value_a[31:10] == 22'd0);

  wire write_mem_data = ci_selected && ci_mem_space && ci_write_or_read;
  wire read_mem_data  = ci_selected && !ci_write_or_read;

  reg read_mem_data_reg; // shadow read_mem_data wire

  always @(posedge clock) begin
    if (reset)
      read_mem_data_reg <= 1'b0;
    else
      read_mem_data_reg <= read_mem_data;
  end

  assign done = (ci_selected && ci_write_or_read) || read_mem_data_reg;

  // =========================================================
  // DMA configuration registers
  // =========================================================

  wire write_bus_addr = ci_selected && (value_a[12:9] == 4'b0011);
  wire write_mem_addr = ci_selected && (value_a[12:9] == 4'b0101);
  wire write_block_sz = ci_selected && (value_a[12:9] == 4'b0111);
  wire write_burst_sz = ci_selected && (value_a[12:9] == 4'b1001);
  wire write_control  = ci_selected && (value_a[12:9] == 4'b1011);

  reg [31:0] dma_bus_start_init;
  reg [8:0]  dma_mem_start_init;
  reg [9:0]  dma_block_size_init;
  reg [7:0]  dma_burst_size_init;

  always @(posedge clock) begin
    if (reset) begin
      dma_bus_start_init  <= 32'd0;
      dma_mem_start_init  <= 9'd0;
      dma_block_size_init <= 10'd0;
      dma_burst_size_init <= 8'd0;
    end else begin
      if (write_bus_addr) dma_bus_start_init  <= value_b;
      if (write_mem_addr) dma_mem_start_init  <= value_b[8:0];
      if (write_block_sz) dma_block_size_init <= value_b[9:0];
      if (write_burst_sz) dma_burst_size_init <= value_b[7:0];
    end
  end

  // =========================================================
  // registers of bus input
  // =========================================================

  reg        end_transaction_slave_reg;
  reg        data_valid_slave_reg;
  reg [31:0] address_data_slave_reg;

  always @(posedge clock) begin
    end_transaction_slave_reg <= end_transaction_slave;
    data_valid_slave_reg      <= data_valid_slave;
    address_data_slave_reg    <= address_data_slave;
  end

  // =========================================================
  // state machine of the dma
  // =========================================================

  localparam [2:0] IDLE             = 3'd0;
  localparam [2:0] INIT_DMA        = 3'd1;
  localparam [2:0] REQUEST_BUS      = 3'd2;
  localparam [2:0] INIT_TRANSACTION = 3'd3;
  localparam [2:0] READ             = 3'd4;
  localparam [2:0] ERROR            = 3'd5;

  wire request_slave = write_control && value_b[0];

  reg [2:0] current_state;
  reg [2:0] next_state;
  reg       bus_error;

  reg [31:0] dma_bus_start_iter;
  reg [8:0]  dma_mem_start_iter;
  reg [9:0]  dma_block_size_iter;

  wire dma_busy = (current_state != IDLE);

  wire dma_done =
    (dma_block_size_iter == 10'd0) ||
    ((dma_block_size_iter == 10'd1) &&
     end_transaction_slave_reg &&
     data_valid_slave_reg);

  wire write_enable_b = (current_state == READ) && data_valid_slave_reg;

  wire [9:0] max_burst_size     = {2'd0, dma_burst_size_init} + 10'd1;
  wire [9:0] resting_block_size = dma_block_size_iter - 10'd1;
  wire [7:0] used_burst_size    = (dma_block_size_iter > max_burst_size) ? dma_burst_size_init
                                                                          : resting_block_size[7:0];

  always @* begin
    next_state = current_state;

    request_master           = 1'b0;
    begin_transaction_master = 1'b0;
    read_not_write_master    = 1'b0;
    byte_enable_master       = 4'd0;
    burst_size_master        = 8'd0;
    address_data_master      = 32'd0;

    case (current_state)
      IDLE : begin
        if (request_slave)
          next_state = INIT_DMA;
      end

      INIT_DMA : begin
        next_state = REQUEST_BUS;
      end

      REQUEST_BUS : begin
        request_master = 1'b1;
        if (grant_arbiter)
          next_state = INIT_TRANSACTION;
      end

      INIT_TRANSACTION : begin
        begin_transaction_master = 1'b1;
        read_not_write_master    = 1'b1;
        byte_enable_master       = 4'hF;
        burst_size_master        = used_burst_size;
        address_data_master      = {dma_bus_start_iter[31:2], 2'd0};
        next_state               = READ;
      end

      READ : begin
        if (error_slave)
          next_state = ERROR;
        else if (end_transaction_slave_reg && dma_done)
          next_state = IDLE;
        else if (end_transaction_slave_reg)
          next_state = REQUEST_BUS;
      end

      ERROR : begin
        if (end_transaction_slave_reg)
          next_state = IDLE;
      end

      default : begin
        next_state = IDLE;
      end
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      current_state       <= IDLE;
      bus_error           <= 1'b0;
      dma_bus_start_iter  <= 32'd0;
      dma_mem_start_iter  <= 9'd0;
      dma_block_size_iter <= 10'd0;
    end else begin
      current_state <= next_state;

      if (current_state == INIT_DMA) begin
        dma_bus_start_iter  <= dma_bus_start_init;
        dma_mem_start_iter  <= dma_mem_start_init;
        dma_block_size_iter <= dma_block_size_init;
      end else if (write_enable_b) begin
        dma_bus_start_iter  <= dma_bus_start_iter + 32'd4;
        dma_mem_start_iter  <= dma_mem_start_iter + 9'd1;
        dma_block_size_iter <= dma_block_size_iter - 10'd1;
      end

      if (current_state == INIT_DMA)
        bus_error <= 1'b0;
      else if (current_state == ERROR)
        bus_error <= 1'b1;
    end
  end

  // =========================================================
  // local dual port ram
  // =========================================================

  wire [31:0] s_sramDataValue;

  dualPortSSRAM #( .bitwidth(32),
                   .nrOfEntries(512),
                   .readBeforWrite(0)) memory
                 ( .clockA(clock),
                   .clockB(~clock),
                   .writeEnableA(write_mem_data),
                   .writeEnableB(write_enable_b),
                   .addressA(ci_mem_addr),
                   .addressB(dma_mem_start_iter),
                   .dataInA(value_b),
                   .dataInB(address_data_slave_reg),
                   .dataOutA(s_sramDataValue),
                   .dataOutB());

  // =========================================================
  // assign result
  // =========================================================

  reg [31:0] intermediate_result;

  always @* begin
    case (ci_reg_select)
      3'b000  : intermediate_result = s_sramDataValue;
      3'b001  : intermediate_result = dma_bus_start_init;
      3'b010  : intermediate_result = {23'd0, dma_mem_start_init};
      3'b011  : intermediate_result = {22'd0, dma_block_size_init};
      3'b100  : intermediate_result = {24'd0, dma_burst_size_init};
      3'b101  : intermediate_result = {30'd0, bus_error, dma_busy};
      default : intermediate_result = 32'd0;
    endcase
  end

  assign result = read_mem_data_reg ? intermediate_result : 32'd0;

endmodule