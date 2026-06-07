// ============================================================
// Module  : cpu_tb
// Project : SAP-1 8-bit CPU
// File    : cpu_tb.v
//
// Program: LDA 14 / ADD 15 / OUT / HLT
// Expected: out_val = 0x2A (42 decimal)
// ============================================================

`timescale 1ns / 1ps

module cpu_tb;

    reg        rst;
    wire [7:0] out_val;
    wire [2:0] t_state_out;

    // PERIOD=5 → full clock period = 10ns
    cpu_top #(.PERIOD(5)) cpu (
        .rst        (rst),
        .out_val    (out_val),
        .t_state_out(t_state_out)
    );

    task load_program;
        begin
            cpu.u_ram.mem[0]  = 8'b0001_1110; // LDA 14
            cpu.u_ram.mem[1]  = 8'b0010_1111; // ADD 15
            cpu.u_ram.mem[2]  = 8'b1110_0000; // OUT
            cpu.u_ram.mem[3]  = 8'b1111_0000; // HLT
            cpu.u_ram.mem[4]  = 8'h00;
            cpu.u_ram.mem[5]  = 8'h00;
            cpu.u_ram.mem[6]  = 8'h00;
            cpu.u_ram.mem[7]  = 8'h00;
            cpu.u_ram.mem[8]  = 8'h00;
            cpu.u_ram.mem[9]  = 8'h00;
            cpu.u_ram.mem[10] = 8'h00;
            cpu.u_ram.mem[11] = 8'h00;
            cpu.u_ram.mem[12] = 8'h00;
            cpu.u_ram.mem[13] = 8'h00;
            cpu.u_ram.mem[14] = 8'h1C; // 28
            cpu.u_ram.mem[15] = 8'h0E; // 14
            $display("  Program loaded.");
        end
    endtask

    integer cycle_count;

    initial begin
        rst         = 1;
        cycle_count = 0;

        $display("============================================");
        $display("  SAP-1 CPU Simulation");
        $display("  Program: LDA 14 / ADD 15 / OUT / HLT");
        $display("  Expected out_val = 0x2A (42 decimal)");
        $display("============================================");

        #10;
        load_program;
        #10 rst = 0;
        $display("\n  Reset released. CPU running...\n");

        // Wait for HLT - check on every rising cpu clock edge
        begin : wait_for_halt
            integer i;
            for (i = 0; i < 200; i = i + 1) begin
                @(posedge cpu.clk); #1;
                cycle_count = cycle_count + 1;
                if (cpu.hlt) disable wait_for_halt;
            end
        end

        #20;

        $display("  CPU halted after %0d CPU clock cycles.", cycle_count);
        $display("  t_state at halt : %0d", t_state_out);
        $display("  out_val         = 0x%02h (%0d decimal)", out_val, out_val);

        if (out_val === 8'h2A)
            $display("\n  [PASS] out_val = 0x2A (42) - correct!");
        else
            $display("\n  [FAIL] out_val = 0x%02h - expected 0x2A", out_val);

        $display("\n============================================");
        #10 $finish;
    end

    // Print state on every CPU clock tick
    always @(posedge cpu.clk) begin
        $display("  T%0d opcode=%04b bus=0x%02h a=0x%02h out=0x%02h | co=%b mi=%b ro=%b ii=%b ce=%b io=%b ai=%b bi=%b eo=%b ao=%b oi=%b hlt=%b",
            t_state_out, cpu.opcode,
            cpu.bus, cpu.a_out, out_val,
            cpu.co, cpu.mi, cpu.ro, cpu.ii, cpu.ce,
            cpu.io, cpu.ai, cpu.bi, cpu.eo, cpu.ao,
            cpu.oi, cpu.hlt);
    end

endmodule