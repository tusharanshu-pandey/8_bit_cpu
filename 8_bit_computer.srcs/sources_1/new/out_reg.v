// ============================================================
// Module  : output_register
// Project : SAP-1 8-bit CPU
// File    : output_register.v
//
// Latches bus value when oi=1. Never drives bus.
// ============================================================

module output_register (
    input  wire       clk,
    input  wire       rst,
    input  wire       oi,
    input  wire [7:0] bus,
    output wire [7:0] out_val
);

    reg [7:0] out_reg;

    always @(posedge clk or posedge rst) begin
        if (rst)      out_reg <= 8'b0;
        else if (oi)  out_reg <= bus;
    end

    assign out_val = out_reg;

endmodule