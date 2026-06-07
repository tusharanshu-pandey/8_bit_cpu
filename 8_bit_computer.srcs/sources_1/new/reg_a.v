`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.06.2026 02:38:50
// Design Name: 
// Module Name: reg_a
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

module reg_a (
    input  wire       clk,    // CPU clock
    input  wire       rst,    // Reset, active HIGH
    inout  wire [7:0] bus,    // Shared 8-bit W bus (bidirectional)
    input  wire       ai,     // A In  - load from bus on clk edge
    input  wire       ao,     // A Out - drive value onto bus
    output wire [7:0] a_out   // Direct output to ALU (always active)
);
    reg [7:0] a_reg;

    always @(posedge clk or posedge rst) begin
        if (rst)
            a_reg <= 8'b0;        // clear on reset
        else if (ai)
            a_reg <= bus;         // latch bus value into register
    end

    assign bus = ao ? a_reg : 8'bz;

    assign a_out = a_reg;

endmodule