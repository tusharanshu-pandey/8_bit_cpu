// ============================================================
// Module  : clock_tb
// Project : SAP-1 8-bit CPU (Ben Eater architecture)
// File    : clock_tb.v
// ============================================================
//
// PURPOSE
//   Testbench for the clock module.
//   Tests four scenarios in order:
//     1. Auto mode    - verifies clock toggles at the right rate
//     2. HLT          - verifies clock stops when hlt=1
//     3. HLT release  - verifies clock resumes after hlt=0
//     4. Manual mode  - verifies one pulse per button press,
//                       and no output between presses
//
// HOW TO RUN IN VIVADO
//   1. Add clock.v and clock_tb.v as sources
//   2. Set clock_tb as the simulation top module
//   3. Run Behavioral Simulation
//   4. Watch the Tcl console for PASS/FAIL messages
//   5. Add clk_out and auto_clk to the waveform viewer
// ============================================================

`timescale 1ns / 1ps   // 1 ns resolution, 1 ps precision

module clock_tb;

    // --------------------------------------------------------
    // TESTBENCH SIGNALS
    // --------------------------------------------------------
    reg  clk_in;        // We drive the fast clock ourselves
    reg  rst;
    reg  hlt;
    reg  manual_mode;
    reg  manual_step;

    wire clk_out;       // Observe this output

    // --------------------------------------------------------
    // INSTANTIATE UUT (Unit Under Test)
    // CLK_DIV = 2 so auto_clk toggles every 2 clk_in cycles
    // → auto_clk period = 4 * 5ns = 20ns (easy to count)
    // --------------------------------------------------------
    clock #(
        .CLK_DIV(2)
    ) uut (
        .clk_in     (clk_in),
        .rst        (rst),
        .hlt        (hlt),
        .manual_mode(manual_mode),
        .manual_step(manual_step),
        .clk_out    (clk_out)
    );

    // --------------------------------------------------------
    // FAST REFERENCE CLOCK: 100 MHz → period = 10 ns
    // --------------------------------------------------------
    initial clk_in = 0;
    always  #5 clk_in = ~clk_in;   // toggle every 5 ns

    // --------------------------------------------------------
    // HELPER TASK: assert a condition and print PASS or FAIL
    // --------------------------------------------------------
    task check;
        input condition;
        input [127:0] test_name;
        begin
            if (condition)
                $display("  [PASS] %s", test_name);
            else
                $display("  [FAIL] %s  ← check waveform", test_name);
        end
    endtask

    // --------------------------------------------------------
    // EDGE COUNTERS - count rising edges on clk_out
    // --------------------------------------------------------
    integer auto_edges;
    integer manual_edges;

    always @(posedge clk_out) begin
        if (!manual_mode)
            auto_edges   = auto_edges   + 1;
        else
            manual_edges = manual_edges + 1;
    end

    // --------------------------------------------------------
    // MAIN TEST SEQUENCE
    // --------------------------------------------------------
    initial begin
        // ---- Init ----
        rst         = 1;
        hlt         = 0;
        manual_mode = 0;
        manual_step = 0;
        auto_edges  = 0;
        manual_edges= 0;

        $display("============================================");
        $display("  SAP-1 Clock Module Testbench");
        $display("============================================");

        // Hold reset for 20 ns, then release
        #20;
        rst = 0;
        $display("");
        $display("--- TEST 1: Auto mode (CLK_DIV=2) ---");
        $display("  Expecting clk_out to toggle every 20 ns");

        // Wait long enough to observe several auto_clk edges
        // With CLK_DIV=2 and 10ns clk_in, auto_clk period = 20ns
        // In 200ns we expect ~10 rising edges on clk_out
        #200;
        $display("  auto_edges counted = %0d (expected ~10)", auto_edges);
        check(auto_edges >= 8, "auto mode produces edges");

        // ---- TEST 2: HLT freezes the clock ----
        $display("");
        $display("--- TEST 2: HLT - clock must stop ---");
        hlt = 1;
        #10;  // Let any in-progress edge settle
        begin : hlt_test
            reg snapshot;
            snapshot = clk_out;
            #60;    // Wait 60 ns - would be 3 edges if clock were running
            check(clk_out === 1'b0, "HLT holds clk_out LOW");
            $display("  clk_out during HLT = %b (expected 0)", clk_out);
        end

        // ---- TEST 3: HLT release - clock resumes ----
        $display("");
        $display("--- TEST 3: HLT released - clock resumes ---");
        hlt = 0;
        auto_edges = 0;   // reset counter
        #200;
        $display("  auto_edges after release = %0d (expected ~10)", auto_edges);
        check(auto_edges >= 8, "clock resumes after HLT release");

        // ---- TEST 4: Manual mode - one pulse per press ----
        $display("");
        $display("--- TEST 4: Manual mode ---");
        manual_mode = 1;
        #20;

        // Button press 1
        $display("  Pressing step button (press 1)...");
        manual_step = 1;
        #10;              // hold for 1 clk_in cycle
        manual_step = 0;
        #30;              // wait between presses

        // Button press 2
        $display("  Pressing step button (press 2)...");
        manual_step = 1;
        #10;
        manual_step = 0;
        #30;

        // Button press 3
        $display("  Pressing step button (press 3)...");
        manual_step = 1;
        #10;
        manual_step = 0;
        #30;

        $display("  manual_edges counted = %0d (expected 3)", manual_edges);
        check(manual_edges == 3, "manual mode: 3 presses → 3 edges");

        // ---- TEST 5: HLT in manual mode ----
        $display("");
        $display("--- TEST 5: HLT in manual mode ---");
        hlt = 1;
        manual_step = 1;
        #10;
        manual_step = 0;
        #20;
        check(clk_out === 1'b0, "HLT overrides manual step");
        hlt = 0;

        // ---- Done ----
        $display("");
        $display("============================================");
        $display("  Simulation complete.");
        $display("  Open the waveform and verify:");
        $display("  1. clk_out toggles freely in auto mode");
        $display("  2. clk_out = 0 flat during HLT");
        $display("  3. clk_out has exactly 3 short pulses");
        $display("     in manual mode (one per button press)");
        $display("============================================");
        #20;
        $finish;
    end

    // --------------------------------------------------------
    // CONTINUOUS MONITOR - prints every time clk_out changes
    // --------------------------------------------------------
    initial begin
        $monitor("t=%4t ns | clk_in=%b hlt=%b manual=%b step=%b | clk_out=%b",
                 $time, clk_in, hlt, manual_mode, manual_step, clk_out);
    end

endmodule