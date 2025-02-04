module FIFO
#(
  parameter DEPTH=8,
  parameter DATA_WIDTH=8
)
(
  input  clk,
  input  rst_n,
  input  rden,
  input  wren,
  input  [DATA_WIDTH-1:0] i_data,
  output logic [DATA_WIDTH-1:0] o_data,
  output full,
  output empty
);

  logic [$clog2(DEPTH):0] wr_ptr, rd_ptr;
  logic [DATA_WIDTH-1:0] fifo[DEPTH];
 
  // Default values on reset.
//  always@(posedge clk) begin
//    if(!rst_n) begin
//      wr_ptr <= 0; 
//		rd_ptr <= 0;
 //     o_data <= 0;
 //   end
//  end
 
  // Write data to FIFO
  always@(posedge clk) begin
  
    if(!rst_n) begin
      wr_ptr <= 0;
    end
  
    else if(wren & !full)begin
      fifo[wr_ptr] <= i_data;
      wr_ptr <= wr_ptr + 1;
    end
  end
 
  // Read data from FIFO
  always@(posedge clk) begin
  
    if(!rst_n) begin
		rd_ptr <= 0;
      o_data <= 0;
    end
	 
    else if(rden & !empty) begin
      o_data <= fifo[rd_ptr];
      rd_ptr <= rd_ptr + 1;
    end
  end
 
  assign full = ((wr_ptr - rd_ptr) == DEPTH);
  assign empty = (wr_ptr == rd_ptr);


endmodule