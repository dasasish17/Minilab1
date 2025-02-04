module Minilab1(
    // FPGA pins (example naming)
    input  wire        CLOCK_50,
    input  reg [3:0]  KEY,       // KEY[0] as active-low reset
    input  reg [9:0]  SW,
    output reg [9:0]  LEDR,
    output reg [6:0]  HEX0,
    output reg [6:0]  HEX1,
    output reg [6:0]  HEX2,
    output reg [6:0]  HEX3,
    output reg [6:0]  HEX4,
    output reg [6:0]  HEX5
);

parameter HEX_0 = 7'b1000000;		// zero
parameter HEX_1 = 7'b1111001;		// one
parameter HEX_2 = 7'b0100100;		// two
parameter HEX_3 = 7'b0110000;		// three
parameter HEX_4 = 7'b0011001;		// four
parameter HEX_5 = 7'b0010010;		// five
parameter HEX_6 = 7'b0000010;		// six
parameter HEX_7 = 7'b1111000;		// seven
parameter HEX_8 = 7'b0000000;		// eight
parameter HEX_9 = 7'b0011000;		// nine
parameter HEX_10 = 7'b0001000;	// ten
parameter HEX_11 = 7'b0000011;	// eleven
parameter HEX_12 = 7'b1000110;	// twelve
parameter HEX_13 = 7'b0100001;	// thirteen
parameter HEX_14 = 7'b0000110;	// fourteen
parameter HEX_15 = 7'b0001110;	// fifteen
parameter OFF   = 7'b1111111;		// all off

    //============================================================
    //  Wires/Regs for mem_wrapper
    //============================================================
    logic [31:0] address;
    logic        read;
    logic [63:0] readdata;
    logic        readdatavalid;
    logic        waitrequest;

    //============================================================
    //  Instantiate mem_wrapper
    //============================================================
    mem_wrapper u_mem (
        .clk           (CLOCK_50),
        .reset_n       (KEY[0]),
        .address       (address),
        .read          (read),
        .readdata      (readdata),
        .readdatavalid (readdatavalid),
        .waitrequest   (waitrequest)
    );

    // For simplicity, let’s make waitrequest=0 always in our mem_wrapper,
    // so no real stalls.  We can ignore it or tie logic low.

    //============================================================
    //  FIFOs for B and A
    //============================================================
    // Single FIFO for B (8 deep, 8 bits wide)
    logic         wren_B, rden_B;
    logic  [7:0]  fifoB_in, fifoB_out;
    logic         full_B, empty_B;

    FIFO #(
        .DEPTH(8),
        .DATA_WIDTH(8)
    ) fifoB (
        .clk    (CLOCK_50),
        .rst_n  (KEY[0]),
        .rden   (rden_B),
        .wren   (wren_B),
        .i_data (fifoB_in),
        .o_data (fifoB_out),
        .full   (full_B),
        .empty  (empty_B)
    );

    // 8 FIFOs for A (each row gets its own FIFO)
    logic         wren_A[7:0], rden_A[7:0];
    logic  [7:0]  fifoA_in [7:0], fifoA_out [7:0];
    logic         full_A[7:0],  empty_A[7:0];

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin: A_FIFOS
            FIFO #(
                .DEPTH(8),
                .DATA_WIDTH(8)
            ) fifoA (
                .clk    (CLOCK_50),
                .rst_n  (KEY[0]),
                .rden   (rden_A[i]),
                .wren   (wren_A[i]),
                .i_data (fifoA_in[i]),
                .o_data (fifoA_out[i]),
                .full   (full_A[i]),
                .empty  (empty_A[i])
            );
        end
    endgenerate

    //============================================================
    //  MAC array
    //============================================================
    // For each row, we have one MAC.  The MAC input is (fifoA_out[i], fifoB_out).
    // We'll drive En/Clr from an FSM.

    logic         En[7:0], Clr[7:0];
    logic [23:0]  Cout[7:0]; // 24-bit outputs

    generate
        for (i = 0; i < 8; i++) begin: MAC_ARRAY
            MAC #(
                .DATA_WIDTH(8)
            ) u_mac (
                .clk   (CLOCK_50),
                .rst_n (KEY[0]),
                .En    (En[i]),
                .Clr   (Clr[i]),
                .Ain   (fifoA_out[i]),
                .Bin   (fifoB_out),
                .Cout  (Cout[i])
            );
        end
    endgenerate

    //============================================================
    //  State Machine + Control
    //============================================================
    typedef enum logic [4:0] {
        S_IDLE,
        S_READ_B,   S_WAIT_B,
        S_WRITE_B,
        S_READ_A0,  S_WAIT_A0, S_WRITE_A0,
        S_READ_A1,  S_WAIT_A1, S_WRITE_A1,
        S_READ_A2,  S_WAIT_A2, S_WRITE_A2,
        S_READ_A3,  S_WAIT_A3, S_WRITE_A3,
        S_READ_A4,  S_WAIT_A4, S_WRITE_A4,
        S_READ_A5,  S_WAIT_A5, S_WRITE_A5,
        S_READ_A6,  S_WAIT_A6, S_WRITE_A6,
        S_READ_A7,  S_WAIT_A7, S_WRITE_A7,
        S_RUN_MAC,
        DONE
    } state_t;

    state_t current_state, next_state;

    // We’ll use counters to push the 8 bytes of each 64-bit word into the FIFO.
    logic [2:0] byte_counter; // goes from 0..7
    logic [63:0] data_latch;  // holds the readdata from memory

    // Registers for storing partial output, etc.
    always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0])
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            S_IDLE:    next_state = S_READ_B;
            
            //---------------- B read
            S_READ_B:  if (!waitrequest) next_state = S_WAIT_B;
            S_WAIT_B:  if (readdatavalid) next_state = S_WRITE_B;
            S_WRITE_B: if (byte_counter == 3'd7) next_state = S_READ_A0; 
            
            //---------------- A row0
            S_READ_A0:  if (!waitrequest) next_state = S_WAIT_A0;
            S_WAIT_A0:  if (readdatavalid) next_state = S_WRITE_A0;
            S_WRITE_A0: if (byte_counter == 3'd7) next_state = S_READ_A1;

            //---------------- A row1
            S_READ_A1:  if (!waitrequest) next_state = S_WAIT_A1;
            S_WAIT_A1:  if (readdatavalid) next_state = S_WRITE_A1;
            S_WRITE_A1: if (byte_counter == 3'd7) next_state = S_READ_A2;

            //---------------- A row2
            S_READ_A2:  if (!waitrequest) next_state = S_WAIT_A2;
            S_WAIT_A2:  if (readdatavalid) next_state = S_WRITE_A2;
            S_WRITE_A2: if (byte_counter == 3'd7) next_state = S_READ_A3;

            //---------------- A row3
            S_READ_A3:  if (!waitrequest) next_state = S_WAIT_A3;
            S_WAIT_A3:  if (readdatavalid) next_state = S_WRITE_A3;
            S_WRITE_A3: if (byte_counter == 3'd7) next_state = S_READ_A4;

            //---------------- A row4
            S_READ_A4:  if (!waitrequest) next_state = S_WAIT_A4;
            S_WAIT_A4:  if (readdatavalid) next_state = S_WRITE_A4;
            S_WRITE_A4: if (byte_counter == 3'd7) next_state = S_READ_A5;

            //---------------- A row5
            S_READ_A5:  if (!waitrequest) next_state = S_WAIT_A5;
            S_WAIT_A5:  if (readdatavalid) next_state = S_WRITE_A5;
            S_WRITE_A5: if (byte_counter == 3'd7) next_state = S_READ_A6;

            //---------------- A row6
            S_READ_A6:  if (!waitrequest) next_state = S_WAIT_A6;
            S_WAIT_A6:  if (readdatavalid) next_state = S_WRITE_A6;
            S_WRITE_A6: if (byte_counter == 3'd7) next_state = S_READ_A7;

            //---------------- A row7
            S_READ_A7:  if (!waitrequest) next_state = S_WAIT_A7;
            S_WAIT_A7:  if (readdatavalid) next_state = S_WRITE_A7;
            S_WRITE_A7: if (byte_counter == 3'd7) next_state = S_RUN_MAC;

            S_RUN_MAC:  next_state = DONE;
            DONE:     next_state = DONE;
            // DONE: next_state = DONE;
        endcase
    end

    // Output logic
    // Default signals
    integer r;
    always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            address       <= 0;
            read          <= 0;
            data_latch    <= 64'b0;
            byte_counter  <= 0;

            wren_B        <= 0;
            fifoB_in      <= 8'b0;
            rden_B        <= 0;

            for (r=0; r<8; r++) begin
                wren_A[r]     <= 0;
                fifoA_in[r]   <= 8'b0;
                rden_A[r]     <= 0;
                Clr[r]        <= 1; // Clear MAC accumulators by default
                En[r]         <= 0;
            end

        end else begin
            // defaults every cycle
            read       <= 0;
            wren_B     <= 0;
            rden_B     <= 0;
            for (r=0; r<8; r++) begin
                wren_A[r] <= 0;
                rden_A[r] <= 0;
                Clr[r]    <= 0; // only set when needed
                En[r]     <= 0;
            end

            //En[0] <= 1'b0;
            case (current_state)
                //--------------------------------------------------
                S_IDLE: begin
                    // Start by reading B from address=0
                    address      <= 0;
                    read         <= 1;
                    byte_counter <= 0;
                end

                //--------------------------------------------------
                // B
                S_READ_B: begin
                    address <= 0;
                    read    <= 1;
                end
                S_WAIT_B: begin
                    if (readdatavalid) begin
                        data_latch <= readdata; // store B
                    end
                end
                S_WRITE_B: begin
                    // push data_latch[63:56], then [55:48], ...
                    // byte_counter indicates which byte to push
                    wren_B    <= 1;
                    fifoB_in  <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    // e.g. for byte_counter=0 => data_latch[63:56]
                    //      for byte_counter=1 => data_latch[55:48], etc.

                    // increment
                    if (!full_B) byte_counter <= byte_counter + 1;
                end

                //--------------------------------------------------
                // A row0
                S_READ_A0: begin
                    address      <= 1; // row0
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A0: begin
                    if (readdatavalid) data_latch <= readdata;
                end
                S_WRITE_A0: begin
                   
                    wren_A[0]  <= 1;
                    fifoA_in[0] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[0]) byte_counter <= byte_counter + 1;
                    //else En[0] <= 1'b0;
                   
                end

                // A row1
                S_READ_A1: begin
                    //En[0] <= 1'b0;
                    address      <= 2; // row1
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A1: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A1: begin
                    wren_A[1]   <= 1;
                    fifoA_in[1] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[1]) byte_counter <= byte_counter + 1;
                end

                // row2
                S_READ_A2: begin
                    address      <= 3;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A2: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A2: begin
                    wren_A[2]   <= 1;
                    fifoA_in[2] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[2]) byte_counter <= byte_counter + 1;
                end

                // row3
                S_READ_A3: begin
                    address      <= 4;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A3: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A3: begin
                    wren_A[3]   <= 1;
                    fifoA_in[3] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[3]) byte_counter <= byte_counter + 1;
                end

                // row4
                S_READ_A4: begin
                    address      <= 5;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A4: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A4: begin
                    wren_A[4]   <= 1;
                    fifoA_in[4] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[4]) byte_counter <= byte_counter + 1;
                end

                // row5
                S_READ_A5: begin
                    address      <= 6;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A5: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A5: begin
                    wren_A[5]   <= 1;
                    fifoA_in[5] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[5]) byte_counter <= byte_counter + 1;
                end

                // row6
                S_READ_A6: begin
                    address      <= 7;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A6: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A6: begin
                    wren_A[6]   <= 1;
                    fifoA_in[6] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[6]) byte_counter <= byte_counter + 1;
                end

                // row7
                S_READ_A7: begin
                    address      <= 8;
                    read         <= 1;
                    byte_counter <= 0;
                end
                S_WAIT_A7: if (readdatavalid) data_latch <= readdata;
                S_WRITE_A7: begin
                    wren_A[7]   <= 1;
                    fifoA_in[7] <= data_latch[ (63 - (byte_counter*8)) -: 8 ];
                    if (!full_A[7]) byte_counter <= byte_counter + 1;
                end

                //--------------------------------------------------
                // Once B and A are loaded, run the MAC
                S_RUN_MAC: begin
                    // Clear accumulators
                    for (r=0; r<8; r++) begin
                        Clr[r] <= 1'b1; 
                        En[r] <= 1'b0;
                    end
                end

                //--------------------------------------------------
                // S_DONE: just do the actual multiply-accumulate
                // in normal operation.  For example, each clock,
                // we can read one element from each row’s FIFO
                // and from B’s FIFO, with En=1, until we finish.
                // For demonstration, do a single 8-cycle pass:
                DONE: begin
                    // read from A & B FIFOs
                    for (r=0; r<8; r++) begin
                        rden_A[r] <= 1; // read next element
                        En[r]     <= 1; // accumulate
                        if(empty_A[r]) En[r] <=0;
                    end
                    rden_B <= 1; // read next B
                    
                end

               
                // do nothing
            endcase
        end
    end

    //============================================================
    // Display or debug
    //============================================================
    // As an example, let's just show the output of the first MAC (Cout[0]) on LEDR
    // That is 24 bits -> too big for 10 LEDs.  We'll show the lower 10 bits:
    // assign LEDR = Cout[0][9:0];

    // // Seven-segment display left as an exercise. If desired, you could
    // // display Cout[0] in hex on HEX0/HEX1/HEX2, etc.

    // assign HEX0 = 7'b1111111; // blank
    // assign HEX1 = 7'b1111111;
    // assign HEX2 = 7'b1111111;
    // assign HEX3 = 7'b1111111;
    // assign HEX4 = 7'b1111111;
    // assign HEX5 = 7'b1111111;
    logic [2:0] sel;

    always @(*) begin
        case(SW[3:1]) 

            3'b000: sel = 3'd0;
            3'b001: sel = 3'd1;
            3'b010: sel = 3'd2;
            //3'b011: sel = 3'd3;
            default: sel = 3'd3;
           
        endcase

    end


    always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][3:0])
      4'd0: HEX0 = HEX_0;
	   4'd1: HEX0 = HEX_1;
	   4'd2: HEX0 = HEX_2;
	   4'd3: HEX0 = HEX_3;
	   4'd4: HEX0 = HEX_4;
	   4'd5: HEX0 = HEX_5;
	   4'd6: HEX0 = HEX_6;
	   4'd7: HEX0 = HEX_7;
	   4'd8: HEX0 = HEX_8;
	   4'd9: HEX0 = HEX_9;
	   4'd10: HEX0 = HEX_10;
	   4'd11: HEX0 = HEX_11;
	   4'd12: HEX0 = HEX_12;
	   4'd13: HEX0 = HEX_13;
	   4'd14: HEX0 = HEX_14;
	   4'd15: HEX0 = HEX_15;
    endcase
  end
  else begin
    HEX0 = OFF;
  end
end

always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][7:4])
      4'd0: HEX1 = HEX_0;
	   4'd1: HEX1 = HEX_1;
	   4'd2: HEX1 = HEX_2;
	   4'd3: HEX1 = HEX_3;
	   4'd4: HEX1 = HEX_4;
	   4'd5: HEX1 = HEX_5;
	   4'd6: HEX1 = HEX_6;
	   4'd7: HEX1 = HEX_7;
	   4'd8: HEX1 = HEX_8;
	   4'd9: HEX1 = HEX_9;
	   4'd10: HEX1 = HEX_10;
	   4'd11: HEX1 = HEX_11;
	   4'd12: HEX1 = HEX_12;
	   4'd13: HEX1 = HEX_13;
	   4'd14: HEX1 = HEX_14;
	   4'd15: HEX1 = HEX_15;
    endcase
  end
  else begin
    HEX1 = OFF;
  end
end

always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][11:8])
      4'd0: HEX2 = HEX_0;
	   4'd1: HEX2 = HEX_1;
	   4'd2: HEX2 = HEX_2;
	   4'd3: HEX2 = HEX_3;
	   4'd4: HEX2 = HEX_4;
	   4'd5: HEX2 = HEX_5;
	   4'd6: HEX2 = HEX_6;
	   4'd7: HEX2 = HEX_7;
	   4'd8: HEX2 = HEX_8;
	   4'd9: HEX2 = HEX_9;
	   4'd10: HEX2 = HEX_10;
	   4'd11: HEX2 = HEX_11;
	   4'd12: HEX2 = HEX_12;
	   4'd13: HEX2 = HEX_13;
	   4'd14: HEX2 = HEX_14;
	   4'd15: HEX2 = HEX_15;
    endcase
  end
  else begin
    HEX2 = OFF;
  end
end

always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][15:12])
      4'd0: HEX3 = HEX_0;
	   4'd1: HEX3 = HEX_1;
	   4'd2: HEX3 = HEX_2;
	   4'd3: HEX3 = HEX_3;
	   4'd4: HEX3 = HEX_4;
	   4'd5: HEX3 = HEX_5;
	   4'd6: HEX3 = HEX_6;
	   4'd7: HEX3 = HEX_7;
	   4'd8: HEX3 = HEX_8;
	   4'd9: HEX3 = HEX_9;
	   4'd10: HEX3 = HEX_10;
	   4'd11: HEX3 = HEX_11;
	   4'd12: HEX3 = HEX_12;
	   4'd13: HEX3 = HEX_13;
	   4'd14: HEX3 = HEX_14;
	   4'd15: HEX3 = HEX_15;
    endcase
  end
  else begin
    HEX3 = OFF;
  end
end

always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][19:16])
      4'd0: HEX4 = HEX_0;
	   4'd1: HEX4 = HEX_1;
	   4'd2: HEX4 = HEX_2;
	   4'd3: HEX4 = HEX_3;
	   4'd4: HEX4 = HEX_4;
	   4'd5: HEX4 = HEX_5;
	   4'd6: HEX4 = HEX_6;
	   4'd7: HEX4 = HEX_7;
	   4'd8: HEX4 = HEX_8;
	   4'd9: HEX4 = HEX_9;
	   4'd10: HEX4 = HEX_10;
	   4'd11: HEX4 = HEX_11;
	   4'd12: HEX4 = HEX_12;
	   4'd13: HEX4 = HEX_13;
	   4'd14: HEX4 = HEX_14;
	   4'd15: HEX4 = HEX_15;
    endcase
  end
  else begin
    HEX4 = OFF;
  end
end

always @(*) begin
  if (current_state == DONE & SW[0]) begin
    case(Cout[sel][23:20])
      4'd0: HEX5 = HEX_0;
	   4'd1: HEX5 = HEX_1;
	   4'd2: HEX5 = HEX_2;
	   4'd3: HEX5 = HEX_3;
	   4'd4: HEX5 = HEX_4;
	   4'd5: HEX5 = HEX_5;
	   4'd6: HEX5 = HEX_6;
	   4'd7: HEX5 = HEX_7;
	   4'd8: HEX5 = HEX_8;
	   4'd9: HEX5 = HEX_9;
	   4'd10: HEX5 = HEX_10;
	   4'd11: HEX5 = HEX_11;
	   4'd12: HEX5 = HEX_12;
	   4'd13: HEX5 = HEX_13;
	   4'd14: HEX5 = HEX_14;
	   4'd15: HEX5 = HEX_15;
    endcase
  end
  else begin
    HEX5 = OFF;
  end
end

assign LEDR = {{8{1'b0}}, current_state};

endmodule
