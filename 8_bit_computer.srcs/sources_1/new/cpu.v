// ============================================================
// Module  : cpu_top
// Project : SAP-1 8-bit CPU
// File    : cpu_top.v
//
// Wires all 10 modules together on the shared 8-bit W bus.
// PERIOD parameter passed to clock module (half-period in ns).
// Load program into u_ram.mem[] before simulation starts.
// ============================================================

module cpu_top #(
    parameter PERIOD = 5
)(
    input  wire       rst,
    output wire [7:0] out_val,
    output wire [2:0] t_state_out
);

    // ---- Internal wires ----
    wire        clk;
    wire [7:0]  bus;

    wire [7:0]  a_out;
    wire [7:0]  b_out;
    wire [3:0]  mar_addr;
    wire [3:0]  opcode;
    wire        carry_flag;
    wire        zero_flag;

    wire hlt, mi, ri, ro, io, ii;
    wire ai, ao, eo, su, bi;
    wire oi, ce, co, j,  fi;

    // ---- Clock ----
    clock #(.PERIOD(PERIOD)) u_clock (
        .rst    (rst),
        .hlt    (hlt),
        .clk_out(clk)
    );

    // ---- Control Unit ----
    control_unit u_ctrl (
        .clk        (clk),
        .rst        (rst),
        .opcode     (opcode),
        .carry_flag (carry_flag),
        .zero_flag  (zero_flag),
        .hlt(hlt), .mi(mi), .ri(ri), .ro(ro), .io(io), .ii(ii),
        .ai(ai),   .ao(ao), .eo(eo), .su(su), .bi(bi),
        .oi(oi),   .ce(ce), .co(co), .j(j),   .fi(fi),
        .t_state_out(t_state_out)
    );

    // ---- Program Counter ----
    program_counter u_pc (
        .clk(clk), .rst(rst),
        .ce(ce), .co(co), .j(j),
        .bus(bus)
    );

    // ---- MAR ----
    mar u_mar (
        .clk(clk), .rst(rst),
        .bus(bus), .mi(mi),
        .mar_out(mar_addr)
    );

    // ---- RAM ----
    ram u_ram (
        .clk    (clk),
        .mar_out(mar_addr),
        .ri(ri), .ro(ro),
        .bus(bus)
    );

    // ---- Instruction Register ----
    instruction_register u_ir (
        .clk(clk), .rst(rst),
        .ii(ii), .io(io),
        .bus(bus),
        .opcode(opcode)
    );

    // ---- A Register ----
    reg_a u_reg_a (
        .clk(clk), .rst(rst),
        .bus(bus),
        .ai(ai), .ao(ao),
        .a_out(a_out)
    );

    // ---- B Register ----
    reg_b u_reg_b (
        .clk(clk), .rst(rst),
        .bus(bus),
        .bi(bi),
        .b_out(b_out)
    );

    // ---- ALU ----
    alu u_alu (
        .clk(clk), .rst(rst),
        .a(a_out), .b(b_out),
        .su(su), .eo(eo), .fi(fi),
        .bus(bus),
        .carry_flag(carry_flag),
        .zero_flag (zero_flag)
    );

    // ---- Output Register ----
    output_register u_out (
        .clk(clk), .rst(rst),
        .oi(oi),
        .bus(bus),
        .out_val(out_val)
    );

endmodule