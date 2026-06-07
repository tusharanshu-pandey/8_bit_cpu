// ============================================================
// Module  : control_unit_tb
// Project : SAP-1 8-bit CPU
// File    : control_unit_tb.v
// ============================================================

`timescale 1ns / 1ps

module control_unit_tb;

    reg        clk, rst;
    reg  [3:0] opcode;
    reg        carry_flag, zero_flag;

    wire       hlt, mi, ri, ro, io, ii;
    wire       ai, ao, eo, su, bi;
    wire       oi, ce, co, j, fi;
    wire [2:0] t_state_out;

    control_unit uut (
        .clk        (clk),
        .rst        (rst),
        .opcode     (opcode),
        .carry_flag (carry_flag),
        .zero_flag  (zero_flag),
        .hlt(hlt), .mi(mi),  .ri(ri),  .ro(ro), .io(io), .ii(ii),
        .ai(ai),   .ao(ao),  .eo(eo),  .su(su), .bi(bi),
        .oi(oi),   .ce(ce),  .co(co),  .j(j),   .fi(fi),
        .t_state_out(t_state_out)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    // Print all active signals for the current t_state
    task show_state;
        input [63:0] label;
        begin
            $display("  %s T%0d: hlt=%b mi=%b ri=%b ro=%b io=%b ii=%b ai=%b ao=%b eo=%b su=%b bi=%b oi=%b ce=%b co=%b j=%b fi=%b",
                label, t_state_out,
                hlt, mi, ri, ro, io, ii, ai, ao, eo, su, bi, oi, ce, co, j, fi);
        end
    endtask

    task check_sig;
        input       got;
        input       expected;
        input [127:0] label;
        begin
            if (got === expected)
                $display("    [PASS] %s = %b", label, got);
            else
                $display("    [FAIL] %s = %b (expected %b)", label, got, expected);
        end
    endtask

    // Run one clock and show state before and after
    task tick;
        begin
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst = 1; opcode = 4'h0; carry_flag = 0; zero_flag = 0;

        $display("============================================");
        $display("  SAP-1 Control Unit Testbench");
        $display("============================================");

        tick; rst = 0;

        // ---- TEST 1: Fetch cycle (T0, T1) same for all opcodes ----
        $display("\n--- TEST 1: Fetch cycle ---");
        // T0: CO|MI
        show_state("FETCH");
        check_sig(co, 1'b1, "T0: co=1");
        check_sig(mi, 1'b1, "T0: mi=1");
        check_sig(ro, 1'b0, "T0: ro=0");
        tick;
        // T1: RO|II|CE
        show_state("FETCH");
        check_sig(ro, 1'b1, "T1: ro=1");
        check_sig(ii, 1'b1, "T1: ii=1");
        check_sig(ce, 1'b1, "T1: ce=1");
        check_sig(co, 1'b0, "T1: co=0");

        // ---- TEST 2: LDA (opcode 0001) T2-T4 ----
        $display("\n--- TEST 2: LDA microcode ---");
        opcode = 4'b0001;
        tick; show_state("LDA");  // T2: IO|MI
        check_sig(io, 1'b1, "T2: io=1");
        check_sig(mi, 1'b1, "T2: mi=1");
        tick; show_state("LDA");  // T3: RO|AI
        check_sig(ro, 1'b1, "T3: ro=1");
        check_sig(ai, 1'b1, "T3: ai=1");
        tick; show_state("LDA");  // T4: NOP
        check_sig(ro, 1'b0, "T4: ro=0 (NOP)");

        // ---- TEST 3: ADD (opcode 0010) full sequence ----
        $display("\n--- TEST 3: ADD microcode (full 5 T-states) ---");
        opcode = 4'b0010;
        rst = 1; tick; rst = 0;  // reset to T0
        tick; show_state("ADD"); // T0
        tick; show_state("ADD"); // T1
        opcode = 4'b0010;
        tick; show_state("ADD"); // T2: IO|MI
        check_sig(io, 1'b1, "T2: io=1");
        check_sig(mi, 1'b1, "T2: mi=1");
        tick; show_state("ADD"); // T3: RO|BI
        check_sig(ro, 1'b1, "T3: ro=1");
        check_sig(bi, 1'b1, "T3: bi=1");
        tick; show_state("ADD"); // T4: EO|AI|FI
        check_sig(eo, 1'b1, "T4: eo=1");
        check_sig(ai, 1'b1, "T4: ai=1");
        check_sig(fi, 1'b1, "T4: fi=1");
        check_sig(su, 1'b0, "T4: su=0 (add not sub)");

        // ---- TEST 4: SUB (opcode 0011) - check SU=1 at T4 ----
        $display("\n--- TEST 4: SUB - SU=1 at T4 ---");
        opcode = 4'b0011;
        rst = 1; tick; rst = 0;
        tick; tick;              // T0, T1
        opcode = 4'b0011;
        tick; tick;              // T2, T3
        tick; show_state("SUB"); // T4: EO|SU|AI|FI
        check_sig(su, 1'b1, "T4: su=1");
        check_sig(eo, 1'b1, "T4: eo=1");
        check_sig(fi, 1'b1, "T4: fi=1");

        // ---- TEST 5: JMP (opcode 0110) - J=1 at T2 ----
        $display("\n--- TEST 5: JMP --- J=1 at T2 ---");
        opcode = 4'b0110;
        rst = 1; tick; rst = 0;
        tick; tick;
        opcode = 4'b0110;
        tick; show_state("JMP");  // T2: IO|J
        check_sig(j,  1'b1, "T2: j=1");
        check_sig(io, 1'b1, "T2: io=1");

        // ---- TEST 6: JC - carry=0, J must be masked ----
        $display("\n--- TEST 6: JC carry=0 → J masked ---");
        opcode = 4'b0111; carry_flag = 0;
        rst = 1; tick; rst = 0;
        tick; tick;
        opcode = 4'b0111;
        tick; show_state("JC");
        check_sig(j, 1'b0, "T2: j=0 (carry=0, no jump)");

        // ---- TEST 7: JC - carry=1, J must fire ----
        $display("\n--- TEST 7: JC carry=1 → J fires ---");
        carry_flag = 1;
        rst = 1; tick; rst = 0;
        tick; tick;
        opcode = 4'b0111;
        tick; show_state("JC");
        check_sig(j, 1'b1, "T2: j=1 (carry=1, jump)");

        // ---- TEST 8: JZ ----
        $display("\n--- TEST 8: JZ zero=0 → J masked ---");
        opcode = 4'b1000; zero_flag = 0; carry_flag = 0;
        rst = 1; tick; rst = 0;
        tick; tick;
        opcode = 4'b1000;
        tick; show_state("JZ");
        check_sig(j, 1'b0, "T2: j=0 (zero=0)");

        $display("\n--- TEST 9: JZ zero=1 → J fires ---");
        zero_flag = 1;
        rst = 1; tick; rst = 0;
        tick; tick;
        opcode = 4'b1000;
        tick; show_state("JZ");
        check_sig(j, 1'b1, "T2: j=1 (zero=1)");

        // ---- TEST 10: HLT freezes T-state ----
        $display("\n--- TEST 10: HLT freezes counter ---");
        opcode = 4'b1111; zero_flag = 0;
        rst = 1; tick; rst = 0;
        tick; tick;          // T0, T1
        opcode = 4'b1111;
        tick;                // T2: HLT asserted
        show_state("HLT");
        check_sig(hlt, 1'b1, "T2: hlt=1");
        tick; tick; tick;    // counter must stay frozen
        check_sig(hlt, 1'b1, "T2+3: hlt still 1 (frozen)");
        if (t_state_out == 3'd2)
            $display("    [PASS] t_state frozen at 2");
        else
            $display("    [FAIL] t_state = %0d, expected 2", t_state_out);

        // ---- TEST 11: T-state wraps 4 → 0 ----
        $display("\n--- TEST 11: T-state wraps 4 → 0 ---");
        opcode = 4'b0000;
        rst = 1; tick; rst = 0;
        tick; tick; tick; tick; // T0-T3
        if (t_state_out == 3'd4)
            $display("  t_state = 4 ✓");
        tick;                    // T4 → should wrap to T0
        if (t_state_out == 3'd0)
            $display("    [PASS] t_state wrapped to 0");
        else
            $display("    [FAIL] t_state = %0d, expected 0", t_state_out);

        $display("\n============================================");
        $display("  Simulation complete.");
        $display("============================================");
        #20 $finish;
    end

    initial begin
        $monitor("t=%3t | opcode=%04b T=%0d | co=%b mi=%b ro=%b ii=%b ce=%b io=%b ai=%b bi=%b eo=%b su=%b fi=%b ao=%b oi=%b j=%b hlt=%b",
                 $time, opcode, t_state_out,
                 co, mi, ro, ii, ce, io, ai, bi, eo, su, fi, ao, oi, j, hlt);
    end

endmodule