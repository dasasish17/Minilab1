`timescale 1ns/1ps

module Minilab1_tb;

    //------------------------------------------------------------
    // Testbench signals
    //------------------------------------------------------------
    reg         CLOCK_50;
    reg  [3:0]  KEY;      // KEY[0] is active-low reset
    reg  [9:0]  SW;
    wire [9:0]  LEDR;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    //------------------------------------------------------------
    // Instantiate DUT (Device Under Test)
    //------------------------------------------------------------
    Minilab1 dut (
        .CLOCK_50 (CLOCK_50),
        .KEY      (KEY),
        .SW       (SW),
        .LEDR     (LEDR),
        .HEX0     (HEX0),
        .HEX1     (HEX1),
        .HEX2     (HEX2),
        .HEX3     (HEX3),
        .HEX4     (HEX4),
        .HEX5     (HEX5)
    );

    //------------------------------------------------------------
    // Clock generation
    //------------------------------------------------------------
    initial begin
        CLOCK_50 = 1'b0;
        forever #5 CLOCK_50 = ~CLOCK_50;  // 100 MHz period = 10 ns
    end

    //------------------------------------------------------------
    // Test sequence
    //------------------------------------------------------------
    initial begin
        // Optionally dump waveforms for viewing in a viewer like gtkwave:
        $dumpfile("Minilab1_tb.vcd");
        $dumpvars(0, Minilab1_tb);

        // Use $monitor to print key signals every time they change
        // In SystemVerilog, you can directly reference "dut.signal"
        // to look inside the DUT for internal signals (e.g., state).
        $monitor($time, 
                 " CLOCK=%b | KEY=%b | SW=%h | LEDR=%h | state=%0d | address=%0d | read=%b | readdata=%h | valid=%b | waitreq=%b",
                 CLOCK_50,
                 KEY,
                 SW,
                 LEDR,
                 dut.current_state,       // enumerated type is printed as a decimal
                 dut.address,
                 dut.read,
                 dut.readdata,
                 dut.readdatavalid,
                 dut.waitrequest
        );

        // Initialize inputs
        KEY = 4'b1111;  // KEY[0] is active-low reset, so '1' means not in reset
        SW  = 10'b0;

        // Assert reset for a bit
        #10 KEY[0] = 1'b0;   // Put the design into reset
        #20 KEY[0] = 1'b1;   // Release reset

        // Run simulation for a while to let the state machine load data, etc.
        #3000;

        // End the simulation
        $stop;
    end

endmodule
