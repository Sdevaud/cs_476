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
  output reg  [31:0] address_data_master,
  output reg  [7:0]  burst_size_master,
  output reg  [3:0]  byte_enable_master,
  output reg         request_master,
  output reg         read_not_write_master,
  output reg         begin_transaction_master,
  output reg         end_transaction_master,
  output wire        data_valid_master
);

  wire       ci_selected      = start && (ci_n == custom_id);
  wire [2:0] ci_reg_select    = value_a[12:10];
  wire       ci_write_or_read = value_a[9]; // write == 1
  wire [8:0] ci_mem_addr      = value_a[8:0];
  wire       ci_mem_space     = (value_a[31:10] == 22'd0);

  wire write_mem_data = ci_selected && ci_mem_space &&  ci_write_or_read;
  wire read_mem_data  = ci_selected && !ci_write_or_read;

  reg read_mem_data_reg;

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

  localparam [3:0] IDLE                  = 4'd0;
  localparam [3:0] INIT_DMA              = 4'd1;
  localparam [3:0] REQUEST_BUS           = 4'd2;
  localparam [3:0] INIT_TRANSACTION      = 4'd3;
  localparam [3:0] READ                  = 4'd4;
  localparam [3:0] ERROR                 = 4'd5;
  localparam [3:0] WRITE                 = 4'd6;
  localparam [3:0] END_TRANSACTION_ERROR = 4'd7;
  localparam [3:0] END_WRITE_TRANSACTION = 4'd8;

  wire request_slave_in  = write_control && value_b[0] && !value_b[1];
  wire request_slave_out = write_control && !value_b[0] && value_b[1];

  reg [3:0] current_state;
  reg [3:0] next_state;
  reg       bus_error;
  reg       is_read_burst;

  reg [31:0] dma_bus_start_iter;
  reg [8:0]  dma_mem_start_iter;
  reg [9:0]  dma_block_size_iter;
  reg [8:0]  words_written;

  wire dma_busy = (current_state != IDLE);

  wire dma_done =
    (dma_block_size_iter == 10'd0) ||
    ((dma_block_size_iter == 10'd1) &&
     end_transaction_slave_reg &&
     data_valid_slave_reg);

  wire write_enable_b = (current_state == READ) && data_valid_slave_reg;
  wire do_bus_write   = (current_state == WRITE) ? (!busy_slave && !words_written[8]) : 1'b0;

  wire [9:0] max_burst_size     = {2'd0, dma_burst_size_init} + 10'd1;
  wire [9:0] resting_block_size = dma_block_size_iter - 10'd1;
  wire [7:0] used_burst_size    = (dma_block_size_iter > max_burst_size) ? dma_burst_size_init
                                                                          : resting_block_size[7:0];

  reg        data_valid_master_reg;
  reg [31:0] address_data_master_reg;

  assign data_valid_master = data_valid_master_reg;

  // Perfrom the rotation with the State
  always @* begin
    next_state = current_state;

    request_master           = 1'b0;
    begin_transaction_master = 1'b0;
    read_not_write_master    = 1'b0;
    end_transaction_master   = 1'b0;
    byte_enable_master       = 4'd0;
    burst_size_master        = 8'd0;
    address_data_master      = address_data_master_reg;

    case (current_state)
      IDLE : begin
        if (request_slave_in || request_slave_out)
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
        read_not_write_master    = is_read_burst;
        byte_enable_master       = 4'hF;
        burst_size_master        = used_burst_size;
        address_data_master      = {dma_bus_start_iter[31:2], 2'd0};
        next_state               = is_read_burst ? READ : WRITE;
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

      WRITE : begin
        if (error_slave)
          next_state = END_TRANSACTION_ERROR;
        else if (words_written[8] && !busy_slave)
          next_state = END_WRITE_TRANSACTION;
      end

      END_TRANSACTION_ERROR : begin
        end_transaction_master = 1'b1;
        next_state             = IDLE;
      end

      END_WRITE_TRANSACTION : begin
        end_transaction_master = 1'b1;
        if (dma_done)
          next_state = IDLE;
        else
          next_state = REQUEST_BUS;
      end

      default : begin
        next_state = IDLE;
      end
    endcase
  end

  // State register: update current state from next_state
  always @(posedge clock) begin
    if (reset)
      current_state <= IDLE;
    else
      current_state <= next_state;
  end

  // Read/Write mode register: keep the transfer direction
  // (read from bus or write to bus) when DMA starts
  always @(posedge clock) begin
    if (reset)
      is_read_burst <= 1'b0;
    else if (current_state == IDLE)
      is_read_burst <= request_slave_in;
  end

  // DMA registers: error flag, address iteration,
  // block size countdown, and write burst word counter
  always @(posedge clock) begin
    if (reset) begin
      bus_error           <= 1'b0;
      dma_bus_start_iter  <= 32'd0;
      dma_mem_start_iter  <= 9'd0;
      dma_block_size_iter <= 10'd0;
      words_written       <= 9'd0;
    end else begin
      if (current_state == INIT_DMA) begin
        bus_error           <= 1'b0;
        dma_bus_start_iter  <= dma_bus_start_init;
        dma_mem_start_iter  <= dma_mem_start_init;
        dma_block_size_iter <= dma_block_size_init;
      end else begin
        if (current_state == ERROR || current_state == END_TRANSACTION_ERROR)
          bus_error <= 1'b1;

        if (write_enable_b || do_bus_write) begin
          dma_bus_start_iter  <= dma_bus_start_iter + 32'd4;
          dma_mem_start_iter  <= dma_mem_start_iter + 9'd1;
          dma_block_size_iter <= dma_block_size_iter - 10'd1;
        end
      end

      if (current_state == INIT_TRANSACTION)
        words_written <= {1'b0, used_burst_size};
      else if (do_bus_write)
        words_written <= words_written - 9'd1;
    end
  end
  
  // Bus write data path: control outgoing data and valid signal
  // during memory-to-bus transfers (write bursts)
  always @(posedge clock) begin
    if (reset) begin
      address_data_master_reg <= 32'd0;
      data_valid_master_reg   <= 1'b0;
    end else begin
      if (current_state == WRITE && busy_slave)
        address_data_master_reg <= address_data_master_reg;
      else if (do_bus_write)
        address_data_master_reg <= bus_ram_data;
      else if (current_state == INIT_TRANSACTION)
        address_data_master_reg <= {dma_bus_start_iter[31:2], 2'd0};
      else
        address_data_master_reg <= 32'd0;

      if (busy_slave && current_state == WRITE)
        data_valid_master_reg <= data_valid_master_reg;
      else
        data_valid_master_reg <= do_bus_write;
    end
  end

  // =========================================================
  // local dual port ram
  // =========================================================

  wire [31:0] s_sramDataValue;
  wire [31:0] bus_ram_data;

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
                   .dataOutB(bus_ram_data));

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
