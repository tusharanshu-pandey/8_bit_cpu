`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.06.2026 03:03:29
// Design Name: 
// Module Name: reg_b
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


module reg_b (
    input  wire       clk,    // CPU clock
    input  wire       rst,    // Reset, active HIGH
    input  wire [7:0] bus,    // Shared W bus - input only
    input  wire       bi,     // B In - load from bus on clk edge
    output wire [7:0] b_out   // Direct output to ALU (always active)
);

    // --------------------------------------------------------
    // INTERNAL STORAGE
    // --------------------------------------------------------
    reg [7:0] b_reg;

    always @(posedge clk or posedge rst) begin
        if (rst)
            b_reg <= 8'b0;
        else if (bi)
            b_reg <= bus;
    end

    assign b_out = b_reg;

endmodule
