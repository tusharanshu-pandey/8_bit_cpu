// ============================================================
// Module  : alu_tb
// Project : SAP-1 8-bit CPU
// File    : alu_tb.v
// ============================================================

`timescale 1ns / 1ps

module alu_tb;

    reg        clk, rst;
    reg  [7:0] a, b;
    reg        su, eo, fi;
    wire [7:0] bus;
    wire       carry_flag, zero_flag;

    // Testbench bus driver - ALU is the only one driving here
    // so bus is left floating (Z) unless eo=1
    assign bus = 8'bz;   // placeholder - alu drives when eo=1

    alu uut (
        .clk        (clk),
        .rst        (rst),
        .a          (a),
        .b          (b),
        .su         (su),
        .eo         (eo),
        .fi         (fi),
        .bus        (bus),
        .carry_flag (carry_flag),
        .zero_flag  (zero_flag)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    task check;
        input [8:0]   got;
        input [8:0]   expected;
        input [127:0] label;
        begin
            if (got === expected)
                $display("  [PASS] %s | got=0x%02h", label, got);
            else
                $display("  [FAIL] %s | got=0x%02h  expected=0x%02h",
                         label, got, expected);
        end
    endtask

    initial begin
        rst = 1; su = 0; eo = 0; fi = 0;
        a = 8'h00; b = 8'h00;

        $display("============================================");
        $display("  SAP-1 ALU Testbench");
        $display("============================================");

        @(posedge clk); #1;
        rst = 0;

        // --- TEST 1: Basic addition ---
        $display("\n--- TEST 1: 0x0F + 0x01 = 0x10 ---");
        a = 8'h0F; b = 8'h01; su = 0; eo = 1; fi = 1;
        @(posedge clk); #1;
        check(bus,        8'h10, "bus = 0x10");
        check(carry_flag, 1'b0,  "carry = 0");
        check(zero_flag,  1'b0,  "zero  = 0");

        // --- TEST 2: Subtraction ---
        $display("\n--- TEST 2: 0x0F - 0x01 = 0x0E ---");
        a = 8'h0F; b = 8'h01; su = 1; eo = 1; fi = 1;
        @(posedge clk); #1;
        check(bus,        8'h0E, "bus = 0x0E");
        check(carry_flag, 1'b1,  "carry = 1 (no borrow)");
        check(zero_flag,  1'b0,  "zero  = 0");

        // --- TEST 3: Zero flag ---
        $display("\n--- TEST 3: 0x05 - 0x05 = 0x00 (zero flag) ---");
        a = 8'h05; b = 8'h05; su = 1; eo = 1; fi = 1;
        @(posedge clk); #1;
        check(bus,        8'h00, "bus = 0x00");
        check(zero_flag,  1'b1,  "zero  = 1");
        check(carry_flag, 1'b1,  "carry = 1 (no borrow)");

        // --- TEST 4: Carry flag on addition overflow ---
        $display("\n--- TEST 4: 0xFF + 0x01 = overflow (carry flag) ---");
        a = 8'hFF; b = 8'h01; su = 0; eo = 1; fi = 1;
        @(posedge clk); #1;
        check(bus,        8'h00, "bus = 0x00 (wrapped)");
        check(carry_flag, 1'b1,  "carry = 1 (overflow)");
        check(zero_flag,  1'b1,  "zero  = 1");

        // --- TEST 5: Borrow (A < B in subtraction) ---
        $display("\n--- TEST 5: 0x01 - 0x05 (borrow, carry=0) ---");
        a = 8'h01; b = 8'h05; su = 1; eo = 1; fi = 1;
        @(posedge clk); #1;
        check(carry_flag, 1'b0, "carry = 0 (borrow occurred)");

        // --- TEST 6: EO=0 bus must be Z ---
        $display("\n--- TEST 6: EO=0, bus must be Z ---");
        eo = 0;
        #2;
        if (bus === 8'bz)
            $display("  [PASS] bus = Z when eo=0");
        else
            $display("  [FAIL] bus = 0x%02h, expected Z", bus);

        // --- TEST 7: FI=0, flags must not update ---
        $display("\n--- TEST 7: FI=0, flags hold previous value ---");
        a = 8'hAA; b = 8'hBB; su = 0; eo = 0; fi = 0;
        @(posedge clk); #1;
        // carry and zero should still reflect TEST 5 result
        check(carry_flag, 1'b0, "carry unchanged (fi was 0)");

        // --- TEST 8: Reset clears flags ---
        $display("\n--- TEST 8: Reset clears flags ---");
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        check(carry_flag, 1'b0, "carry = 0 after reset");
        check(zero_flag,  1'b0, "zero  = 0 after reset");

        $display("\n============================================");
        $display("  Simulation complete.");
        $display("============================================");
        #20 $finish;
    end

    initial begin
        $monitor("t=%3t | su=%b eo=%b fi=%b a=0x%02h b=0x%02h | bus=0x%02h carry=%b zero=%b",
                 $time, su, eo, fi, a, b, bus, carry_flag, zero_flag);
    end

endmodule