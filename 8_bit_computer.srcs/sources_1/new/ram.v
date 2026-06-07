// ============================================================
// Module  : ram
// Project : SAP-1 8-bit CPU
// File    : ram.v
//
// 16 x 8-bit static RAM.
// Address sourced from MAR output (4-bit).
// Read  : combinational - bus driven immediately when ro=1
// Write : synchronous   - bus latched into mem on posedge clk when ri=1
// Pre-loaded with zeros; testbench or cpu_top initialises program.
// ============================================================

module ram (
    input  wire       clk,
    input  wire [3:0] mar_out,  // address from MAR
    input  wire       ri,       // RAM In  : write bus → mem[addr]
    input  wire       ro,       // RAM Out : drive bus ← mem[addr]
    inout  wire [7:0] bus
);

    reg [7:0] mem [0:15];

    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            mem[i] = 8'h00;
    end

    // Write
    always @(posedge clk) begin
        if (ri) mem[mar_out] <= bus;
    end

    // Read - combinational tri-state
    assign bus = ro ? mem[mar_out] : 8'bz;

endmodule