// ============================================================
// Module  : alu
// Project : SAP-1 8-bit CPU
// File    : alu.v
//
// Reads A and B directly (not from bus).
// Computes A+B (su=0) or A-B (su=1) using XOR+adder,
// matching Ben Eater's hardware exactly.
// Drives result onto bus when eo=1 (tri-state).
// Latches carry and zero flags on posedge clk when fi=1.
// ============================================================

module alu (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] a,          // from reg_a a_out
    input  wire [7:0] b,          // from reg_b b_out
    input  wire       su,         // 0=add, 1=subtract
    input  wire       eo,         // ALU out: drive bus
    input  wire       fi,         // flags in: latch flags on clk edge
    inout  wire [7:0] bus,        // shared W bus
    output reg        carry_flag,
    output reg        zero_flag
);

    // su=1: XOR inverts b, su feeds as carry-in → two's complement subtract
    // Matches Ben's XOR gate array + 74LS283 adder exactly
    wire [7:0] b_operand   = su ? ~b : b;
    wire [8:0] full_result = {1'b0, a} + {1'b0, b_operand} + {8'b0, su};

    // Drive bus with lower 8 bits when eo=1
    assign bus = eo ? full_result[7:0] : 8'bz;

    // Flags register - only updates when fi=1
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            carry_flag <= 1'b0;
            zero_flag  <= 1'b0;
        end else if (fi) begin
            carry_flag <= full_result[8];
            zero_flag  <= (full_result[7:0] == 8'b0);
        end
    end

endmodule