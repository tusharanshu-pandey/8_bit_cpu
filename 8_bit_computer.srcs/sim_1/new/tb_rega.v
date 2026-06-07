`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.06.2026 02:58:15
// Design Name: 
// Module Name: tb_rega
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ============================================================
// Module  : reg_a_tb
// Project : SAP-1 8-bit CPU (Ben Eater architecture)
// File    : reg_a_tb.v
// ============================================================
//
// PURPOSE
//   Tests the A register in isolation. Five test cases:
//     1. Reset          - a_reg clears to 0x00
//     2. Load from bus  - AI=1 latches bus value on clk edge
//     3. No load        - AI=0 holds value (bus ignored)
//     4. Drive bus      - AO=1 puts a_reg onto bus
//     5. Tri-state      - AO=0 releases bus (bus becomes Z)
//
// BUS TRICK
//   The bus is an inout wire - both reg_a AND the testbench
//   connect to it. The testbench uses a separate driver:
//
//     reg  [7:0] tb_bus_data;   <- testbench data to put on bus
//     reg        tb_bus_en;     <- 1 = testbench drives bus
//     assign bus = tb_bus_en ? tb_bus_data : 8'bz;
//
//   When tb_bus_en=1 : testbench drives the bus (simulates
//                      another module like RAM putting data out)
//   When tb_bus_en=0 : testbench releases bus so reg_a can
//                      drive it (to test AO)
//
//   Never have tb_bus_en=1 AND ao=1 at the same time - that
//   is a bus conflict (two drivers → X in waveform).
// ============================================================

`timescale 1ns / 1ps

module reg_a_tb;

    // --------------------------------------------------------
    // TESTBENCH SIGNALS
    // --------------------------------------------------------
    reg        clk;
    reg        rst;
    reg        ai;
    reg        ao;

    // Bus driver (testbench side)
    reg  [7:0] tb_bus_data;   // data the testbench puts on bus
    reg        tb_bus_en;     // 1 = testbench is driving the bus

    wire [7:0] bus;           // the shared bus wire
    wire [7:0] a_out;         // direct output to ALU

    // --------------------------------------------------------
    // TESTBENCH BUS DRIVER
    // When tb_bus_en=0, testbench releases bus (high-Z)
    // so reg_a can drive it freely.
    // --------------------------------------------------------
    assign bus = tb_bus_en ? tb_bus_data : 8'bz;

    // --------------------------------------------------------
    // INSTANTIATE UUT
    // --------------------------------------------------------
    reg_a uut (
        .clk   (clk),
        .rst   (rst),
        .bus   (bus),
        .ai    (ai),
        .ao    (ao),
        .a_out (a_out)
    );

    // --------------------------------------------------------
    // CLOCK: 10 ns period (100 MHz)
    // --------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // --------------------------------------------------------
    // HELPER TASK: check and report
    // --------------------------------------------------------
    task check;
        input [7:0]   got;
        input [7:0]   expected;
        input [127:0] test_name;
        begin
            if (got === expected)
                $display("  [PASS] %s | got=0x%02h", test_name, got);
            else
                $display("  [FAIL] %s | got=0x%02h  expected=0x%02h",
                         test_name, got, expected);
        end
    endtask

    // --------------------------------------------------------
    // MAIN TEST SEQUENCE
    // --------------------------------------------------------
    initial begin
        // --- initialise everything ---
        rst        = 1;
        ai         = 0;
        ao         = 0;
        tb_bus_en  = 0;
        tb_bus_data= 8'h00;

        $display("============================================");
        $display("  SAP-1 A Register Testbench");
        $display("============================================");

        // ---- TEST 1: Reset ----
        // Keep rst=1 for two clock cycles, check a_out = 0
        $display("");
        $display("--- TEST 1: Reset ---");
        @(posedge clk); #1;    // wait for rising edge + 1ns settle
        @(posedge clk); #1;
        check(a_out, 8'h00, "a_out = 0x00 after reset");
        rst = 0;               // release reset

        // ---- TEST 2: Load value from bus (AI=1) ----
        // Put 0xAB on the bus from testbench, pulse AI=1
        $display("");
        $display("--- TEST 2: Load 0xAB from bus (AI=1) ---");
        tb_bus_data = 8'hAB;
        tb_bus_en   = 1;       // testbench drives bus
        ai          = 1;       // tell reg_a to latch on next edge
        @(posedge clk); #1;    // latch happens here
        ai          = 0;
        tb_bus_en   = 0;       // release bus
        check(a_out, 8'hAB, "a_out = 0xAB after load");

        // ---- TEST 3: No load when AI=0 (value must hold) ----
        // Put a different value on bus, but AI stays low
        $display("");
        $display("--- TEST 3: Bus changes but AI=0 (hold) ---");
        tb_bus_data = 8'hFF;
        tb_bus_en   = 1;       // bus has 0xFF on it
        ai          = 0;       // AI is low - reg_a must ignore bus
        @(posedge clk); #1;
        tb_bus_en   = 0;
        check(a_out, 8'hAB, "a_out still 0xAB (AI was low)");

        // ---- TEST 4: Drive bus (AO=1) ----
        // Release testbench bus driver, assert AO, check bus=a_out
        $display("");
        $display("--- TEST 4: Drive bus (AO=1) ---");
        tb_bus_en = 0;         // testbench releases bus
        ao        = 1;         // reg_a now drives bus
        #2;                    // small settle time (combinational)
        check(bus,   8'hAB, "bus = 0xAB when AO=1");
        check(a_out, 8'hAB, "a_out = 0xAB (unchanged)");

        // ---- TEST 5: Tri-state (AO=0 → bus must be Z) ----
        $display("");
        $display("--- TEST 5: Tri-state check (AO=0) ---");
        ao = 0;                // disconnect reg_a from bus
        #2;
        if (bus === 8'bz)
            $display("  [PASS] bus = Z when AO=0 (high impedance)");
        else
            $display("  [FAIL] bus = 0x%02h, expected Z", bus);

        // ---- TEST 6: Load a second value (0x42) ----
        $display("");
        $display("--- TEST 6: Load 0x42 ---");
        tb_bus_data = 8'h42;
        tb_bus_en   = 1;
        ai          = 1;
        @(posedge clk); #1;
        ai        = 0;
        tb_bus_en = 0;
        check(a_out, 8'h42, "a_out = 0x42 after second load");

        // ---- TEST 7: Reset clears loaded value ----
        $display("");
        $display("--- TEST 7: Reset clears register ---");
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        check(a_out, 8'h00, "a_out = 0x00 after reset");

        // ---- Done ----
        $display("");
        $display("============================================");
        $display("  Simulation complete.");
        $display("  Check waveform for:");
        $display("  - a_reg latches bus only on posedge when AI=1");
        $display("  - bus is Z (mid-rail blue line) when AO=0");
        $display("  - a_out always tracks a_reg directly");
        $display("============================================");
        #20 $finish;
    end

    // --------------------------------------------------------
    // MONITOR - prints every time any key signal changes
    // --------------------------------------------------------
    initial begin
        $monitor("t=%3t | clk=%b rst=%b ai=%b ao=%b | bus=0x%02h a_out=0x%02h",
                 $time, clk, rst, ai, ao, bus, a_out);
    end

endmodule