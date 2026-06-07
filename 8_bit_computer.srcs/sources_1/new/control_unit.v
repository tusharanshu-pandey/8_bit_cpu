// ============================================================
// Module  : control_unit
// Project : SAP-1 8-bit CPU
// File    : control_unit.v
//
// Microcode ROM indexed by {opcode[3:0], t_state[2:0]} (7-bit).
// Outputs all 16 control signals every clock cycle.
// T-state counter runs 0→4 then wraps. Freezes on HLT.
//
// Control word bit mapping (MSB→LSB):
// [15]HLT [14]MI [13]RI [12]RO [11]IO [10]II [9]AI [8]AO
// [7]EO   [6]SU  [5]BI  [4]OI  [3]CE  [2]CO  [1]J  [0]FI
//
// Microcode hex values:
//   CO|MI       = 0x4004    RO|II|CE   = 0x1408
//   IO|MI       = 0x4800    RO|AI      = 0x1200
//   RO|BI       = 0x1020    EO|AI|FI   = 0x0281
//   EO|SU|AI|FI = 0x02C1   AO|RI      = 0x2100
//   IO|AI       = 0x0A00    IO|J       = 0x0802
//   AO|OI       = 0x0110    HLT        = 0x8000
// ============================================================

module control_unit (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] opcode,
    input  wire       carry_flag,
    input  wire       zero_flag,
    output wire       hlt,
    output wire       mi,  ri,  ro,  io,  ii,
    output wire       ai,  ao,  eo,  su,  bi,
    output wire       oi,  ce,  co,  j,   fi,
    output wire [2:0] t_state_out   // exposed for testbench / cpu_top
);

    reg [2:0]  t_state;
    reg [15:0] microcode [0:127];
    reg [15:0] ctrl;

    // ---- Microcode ROM initialisation ----
    integer k;
    initial begin
        // zero everything first
        for (k = 0; k < 128; k = k + 1)
            microcode[k] = 16'h0000;

        // T0: CO|MI  and  T1: RO|II|CE  same for all 16 opcodes
        for (k = 0; k < 16; k = k + 1) begin
            microcode[k*8 + 0] = 16'h4004;
            microcode[k*8 + 1] = 16'h1408;
        end

        // LDA 0001
        microcode[1*8 + 2] = 16'h4800; // IO|MI
        microcode[1*8 + 3] = 16'h1200; // RO|AI

        // ADD 0010
        microcode[2*8 + 2] = 16'h4800; // IO|MI
        microcode[2*8 + 3] = 16'h1020; // RO|BI
        microcode[2*8 + 4] = 16'h0281; // EO|AI|FI

        // SUB 0011
        microcode[3*8 + 2] = 16'h4800; // IO|MI
        microcode[3*8 + 3] = 16'h1020; // RO|BI
        microcode[3*8 + 4] = 16'h02C1; // EO|SU|AI|FI

        // STA 0100
        microcode[4*8 + 2] = 16'h4800; // IO|MI
        microcode[4*8 + 3] = 16'h2100; // AO|RI

        // LDI 0101
        microcode[5*8 + 2] = 16'h0A00; // IO|AI

        // JMP 0110
        microcode[6*8 + 2] = 16'h0802; // IO|J

        // JC 0111 - IO|J stored; J masked at runtime if carry=0
        microcode[7*8 + 2] = 16'h0802;

        // JZ 1000 - IO|J stored; J masked at runtime if zero=0
        microcode[8*8 + 2] = 16'h0802;

        // OUT 1110
        microcode[14*8 + 2] = 16'h0110; // AO|OI

        // HLT 1111
        microcode[15*8 + 2] = 16'h8000;
    end

    // ---- Combinational: ROM lookup + conditional jump masking ----
    always @(*) begin
        ctrl = microcode[{opcode, t_state}];
        if (opcode == 4'd7 && !carry_flag) ctrl[1] = 1'b0; // JC: no carry
        if (opcode == 4'd8 && !zero_flag)  ctrl[1] = 1'b0; // JZ: no zero
    end

    // ---- T-state counter ----
    always @(posedge clk or posedge rst) begin
        if (rst)
            t_state <= 3'b0;
        else if (!ctrl[15]) begin  // advance only when not halted
            if (t_state == 3'd4)
                t_state <= 3'b0;
            else
                t_state <= t_state + 1'b1;
        end
    end

    // ---- Output assignments ----
    assign hlt = ctrl[15];
    assign mi  = ctrl[14];
    assign ri  = ctrl[13];
    assign ro  = ctrl[12];
    assign io  = ctrl[11];
    assign ii  = ctrl[10];
    assign ai  = ctrl[9];
    assign ao  = ctrl[8];
    assign eo  = ctrl[7];
    assign su  = ctrl[6];
    assign bi  = ctrl[5];
    assign oi  = ctrl[4];
    assign ce  = ctrl[3];
    assign co  = ctrl[2];
    assign j   = ctrl[1];
    assign fi  = ctrl[0];

    assign t_state_out = t_state;

endmodule