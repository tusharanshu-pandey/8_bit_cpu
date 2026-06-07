// ============================================================
// Module  : instruction_register
// Project : SAP-1 8-bit CPU
// File    : ir.v
//
// Holds the current instruction: [7:4] opcode | [3:0] operand
// ii=1 : load full 8 bits from bus on posedge clk
// io=1 : drive zero-padded lower nibble onto bus
// opcode always output to control unit (not gated)
// ============================================================

module instruction_register (
    input  wire       clk,
    input  wire       rst,
    input  wire       ii,      // IR In  - load from bus
    input  wire       io,      // IR Out - lower nibble onto bus
    inout  wire [7:0] bus,
    output wire [3:0] opcode   // upper nibble → control unit (always live)
);

    reg [7:0] ir;

    always @(posedge clk or posedge rst) begin
        if (rst)      ir <= 8'b0;
        else if (ii)  ir <= bus;
    end

    assign bus    = io ? {4'b0, ir[3:0]} : 8'bz;
    assign opcode = ir[7:4];

endmodule