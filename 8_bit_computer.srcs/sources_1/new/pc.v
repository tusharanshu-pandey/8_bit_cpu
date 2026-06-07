// ============================================================
// Module  : program_counter
// Project : SAP-1 8-bit CPU
// File    : pc.v
//
// 4-bit counter. Increments on posedge clk when ce=1.
// Loads from bus[3:0] when j=1 (jump).
// Drives zero-padded value onto bus when co=1.
// Priority: rst > j > ce
// ============================================================

module program_counter (
    input  wire       clk,
    input  wire       rst,
    input  wire       ce,   // count enable: increment PC
    input  wire       co,   // counter out: drive bus
    input  wire       j,    // jump: load PC from bus[3:0]
    inout  wire [7:0] bus
);

    reg [3:0] pc;

    always @(posedge clk or posedge rst) begin
        if (rst)       pc <= 4'b0;
        else if (j)    pc <= bus[3:0];  // jump overrides increment
        else if (ce)   pc <= pc + 1'b1;
    end

    // Zero-pad to 8 bits on bus - upper nibble always 0
    assign bus = co ? {4'b0, pc} : 8'bz;

endmodule