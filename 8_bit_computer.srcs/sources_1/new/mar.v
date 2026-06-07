// ============================================================
// Module  : mar (Memory Address Register)
// Project : SAP-1 8-bit CPU
// File    : mar.v
//
// 4-bit register. Holds the RAM address for the current
// memory operation. Only latches bus[3:0] - lower nibble.
// Never drives the bus. Direct 4-bit output to RAM.
// ============================================================

module mar (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] bus,     // 8-bit bus - only [3:0] used
    input  wire       mi,      // MAR In: latch on posedge clk
    output wire [3:0] mar_out  // 4-bit address output to RAM
);

    reg [3:0] mar_reg;

    always @(posedge clk or posedge rst) begin
        if (rst)      mar_reg <= 4'b0;
        else if (mi)  mar_reg <= bus[3:0];
    end

    assign mar_out = mar_reg;

endmodule