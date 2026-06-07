# SAP-1 — 8-Bit CPU in Verilog

A complete 8-bit CPU implemented in behavioural Verilog (Verilog 2001), designed for simulation in Xilinx Vivado. The CPU executes a fixed instruction set, operates on a single shared 8-bit bus, and is controlled entirely by a microcode ROM that drives 16 control signals across 5 clock steps per instruction.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [The Shared Bus](#the-shared-bus)
- [Clock](#clock)
- [Registers](#registers)
- [ALU](#alu)
- [Memory](#memory)
- [Program Counter](#program-counter)
- [Instruction Register](#instruction-register)
- [Control Unit](#control-unit)
- [Output Register](#output-register)
- [Instruction Set](#instruction-set)
- [Microcode — T-States](#microcode--t-states)
- [Control Signals](#control-signals)
- [File Structure](#file-structure)
- [How to Simulate in Vivado](#how-to-simulate-in-vivado)
- [Running the Full CPU](#running-the-full-cpu)
- [Example Program](#example-program)

---

## Architecture Overview

The CPU is built around a single shared 8-bit data bus called the **W bus**. Every module connects to this bus. Data moves between modules by having one module drive the bus while another reads it — never two drivers simultaneously.

```
                        ┌─────────────────────┐
                        │       CLOCK         │
                        │  auto / halt gated  │
                        └──────────┬──────────┘
                                   │ clk
         ┌─────────────────────────┼──────────────────────────┐
         │                         │                          │
   ┌─────┴──────┐           ┌──────┴──────┐           ┌──────┴──────┐
   │ Program    │           │     MAR     │           │  A Register │
   │ Counter    │◄──────────┤  4-bit addr │           │ accumulator │
   │  (4-bit)   │           └──────┬──────┘           └──────┬──────┘
   └─────┬──────┘                  │ mar_out                  │ a_out
         │                  ┌──────┴──────┐                  │
         │                  │    RAM      │           ┌──────┴──────┐
         │                  │  16 × 8    │           │     ALU     │
         │                  │  bytes      │           │  add / sub  │
         │                  └─────────────┘           └──────┬──────┘
         │                                                    │ b_out
         │                  ┌─────────────┐           ┌──────┴──────┐
         │                  │ Instruction │           │  B Register │
         │                  │  Register   │           │   operand   │
         │                  └──────┬──────┘           └─────────────┘
         │                         │ opcode
         │                  ┌──────┴──────┐
         │                  │   CONTROL   │
         └──────────────────┤    UNIT     ├──── 16 control signals ────►
                            │  microcode  │
                            └─────────────┘

                   All modules above share one 8-bit W bus
```

---

## The Shared Bus

The W bus is a single `wire [7:0] bus` declared in `cpu.v`. Every module that can drive data onto the bus uses a **tri-state assign**:

```verilog
assign bus = output_enable ? stored_value : 8'bz;
```

When `output_enable` is low, the module outputs `8'bz` — high impedance — which means it electrically disconnects from the bus and lets another module use it. Only one module may drive the bus at any given clock step. The control unit guarantees this through the microcode.

If two modules drive the bus simultaneously, Vivado's simulator shows `X` (unknown) on the bus wire. This is the most common integration bug and is easy to spot in the waveform viewer.

Modules that only read from the bus (B register, MAR, Output register) use a plain `input wire [7:0] bus` — no tri-state needed.

---

## Clock

**File:** `clock.v`

The clock module is a **behavioral, simulation-only** clock generator — it has no external clock input and uses Verilog `#` delay statements to toggle `clk_out`. It is not synthesizable and exists solely to drive simulation.

The `PERIOD` parameter sets the half-period in nanoseconds (default `5`). The full clock period is `2 × PERIOD`:

```
full period = 2 × PERIOD ns
```

With `PERIOD = 5` the clock runs at 100 MHz equivalent. Override it in the testbench instantiation:

```verilog
cpu_top #(.PERIOD(5)) cpu (...);   // 10 ns period
```

The `always` block loops forever. When `rst` or `hlt` is high it holds `clk_out = 0` and spins with a `#PERIOD` delay — no rising edges are produced. When both are low it toggles normally:

```verilog
always begin
    if (rst || hlt) begin
        clk_out = 1'b0;
        #(PERIOD);
    end else begin
        #(PERIOD) clk_out = 1'b1;
        #(PERIOD) clk_out = 1'b0;
    end
end
```

When the Control Unit asserts `hlt`, `clk_out` freezes at 0 and the entire CPU stops. No more rising edges means no more state changes — the CPU is frozen exactly as-is.

```
rst ──┐
hlt ──┼──► [always #PERIOD loop] ──► clk_out
      │    (toggle when free,
      └──── hold 0 when rst||hlt)
```

---

## Registers

### A Register (Accumulator)

**File:** `reg_a.v`

The A register is the CPU's primary working register. Every arithmetic result is stored here. It is an 8-bit D flip-flop array with two bus connections:

- **AI (A In):** on the rising clock edge, if `ai = 1`, the register latches whatever value is currently on the bus.
- **AO (A Out):** when `ao = 1`, the register drives its stored value onto the bus via tri-state logic.
- **`a_out`:** a direct 8-bit wire to the ALU that is always active, regardless of AO. The ALU reads A continuously without going through the bus.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)      a_reg <= 8'b0;
    else if (ai)  a_reg <= bus;
end
assign bus   = ao ? a_reg : 8'bz;
assign a_out = a_reg;
```

### B Register

**File:** `reg_b.v`

The B register holds the second operand for the ALU. It is simpler than A — it can only receive data from the bus, never drive it. There is no `bo` signal and the bus port is a plain `input wire`, not `inout`.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)      b_reg <= 8'b0;
    else if (bi)  b_reg <= bus;
end
assign b_out = b_reg;
```

The CPU loads a memory value into B during ADD or SUB, then the ALU computes `A ± B`.

---

## ALU

**File:** `ALU.v`

The ALU is purely combinational — it computes constantly with no internal clock. It takes `a_out` and `b_out` directly (not from the bus) and produces a result that can be placed on the bus when `eo = 1`.

### Add and Subtract

Subtraction is implemented using two's complement: XOR gates invert B when `su = 1`, and `su` itself feeds as carry-in. This is exactly equivalent to `A + (~B) + 1 = A - B`:

```verilog
wire [7:0] b_operand   = su ? ~b : b;
wire [8:0] full_result = {1'b0, a} + {1'b0, b_operand} + {8'b0, su};
```

The 9th bit of `full_result` is the carry out.

### Flags

Two flag flip-flops capture the state of the last arithmetic result:

- **Carry flag:** set when the result overflows 8 bits (addition), or when there is no borrow (subtraction). In subtraction, `carry = 1` means A ≥ B; `carry = 0` means A < B (borrow).
- **Zero flag:** set when the result is exactly `0x00`.

Flags only update when `fi = 1` (Flags In). This prevents fetch cycles and unrelated instructions from overwriting the flags. Only ADD and SUB assert `fi` in their microcode.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst) begin
        carry_flag <= 0; zero_flag <= 0;
    end else if (fi) begin
        carry_flag <= full_result[8];
        zero_flag  <= (full_result[7:0] == 8'b0);
    end
end
```

---

## Memory

### MAR — Memory Address Register

**File:** `mar.v`

The MAR is a 4-bit register that holds the RAM address for the current memory operation. The CPU's address space is 16 bytes, so 4 bits are sufficient. It reads only the lower nibble of the 8-bit bus (`bus[3:0]`); the upper nibble is ignored.

The MAR never drives the bus. Its single control signal is `mi` (MAR In).

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)      mar_reg <= 4'b0;
    else if (mi)  mar_reg <= bus[3:0];
end
```

### RAM

**File:** `ram.v`

The RAM is a 16 × 8-bit array. Address is sourced from `mar_out` (the MAR's direct output, not the bus). Two control signals:

- **RO (RAM Out):** drives `mem[mar_out]` onto the bus combinationally — no clock needed for reading.
- **RI (RAM In):** writes the bus value into `mem[mar_out]` on the rising clock edge.

```verilog
always @(posedge clk) begin
    if (ri) mem[mar_out] <= bus;
end
assign bus = ro ? mem[mar_out] : 8'bz;
```

The RAM has no reset. Its contents are loaded before simulation using hierarchical references from the testbench:

```verilog
cpu.u_ram.mem[0] = 8'b0001_1110; // LDA 14
```

---

## Program Counter

**File:** `pc.v`

The PC is a 4-bit up-counter. It tracks which instruction is next to execute. Three control signals:

- **CE (Count Enable):** increments PC by 1 on the rising clock edge.
- **CO (Counter Out):** drives `{4'b0, pc}` onto the bus — zero-padded to 8 bits so the upper nibble is always 0.
- **J (Jump):** loads PC from `bus[3:0]` on the rising clock edge, overriding increment.

Priority order: `rst > J > CE`. A jump always wins over an increment if both are asserted.

The counter wraps naturally: after `0xF`, the next increment produces `0x0` with no extra logic needed.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)       pc <= 4'b0;
    else if (j)    pc <= bus[3:0];
    else if (ce)   pc <= pc + 1'b1;
end
assign bus = co ? {4'b0, pc} : 8'bz;
```

---

## Instruction Register

**File:** `ir.v`

The IR holds the instruction currently being executed. It is 8 bits split into two nibbles:

- **`ir[7:4]`** — the opcode. Always driven directly to the Control Unit as `opcode`. Not gated.
- **`ir[3:0]`** — the operand (a memory address or immediate value).

Control signals:

- **II (IR In):** loads the full 8 bits from the bus on the rising clock edge.
- **IO (IR Out):** drives `{4'b0, ir[3:0]}` onto the bus — the operand address, zero-padded. Used when the CPU needs to put an instruction's address argument into MAR.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)      ir <= 8'b0;
    else if (ii)  ir <= bus;
end
assign bus    = io ? {4'b0, ir[3:0]} : 8'bz;
assign opcode = ir[7:4];
```

---

## Control Unit

**File:** `control_unit.v`

The Control Unit is the CPU's brain. It reads the current opcode and T-state, looks up the corresponding row in a microcode ROM, and outputs all 16 control signals simultaneously every clock cycle.

### Microcode ROM

The ROM has 128 entries indexed by `{opcode[3:0], t_state[2:0]}` — a 7-bit address. Each entry is a 16-bit control word where each bit corresponds to one control signal:

```
Bit: 15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
Sig: HLT  MI  RI  RO  IO  II  AI  AO  EO  SU  BI  OI  CE  CO   J  FI
```

The ROM is initialised in a Verilog `initial` block. T0 and T1 are identical for all 16 opcodes (fetch cycle). T2–T4 are unique per instruction.

```verilog
// T0 and T1 same for every opcode
for (k = 0; k < 16; k = k + 1) begin
    microcode[k*8 + 0] = 16'h4004;  // CO | MI
    microcode[k*8 + 1] = 16'h1408;  // RO | II | CE
end
```

### T-State Counter

A 3-bit register counts from 0 to 4, then wraps back to 0. It only advances when the CPU is not halted. When `hlt = 1`, the counter freezes at its current value.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst) t_state <= 3'b0;
    else if (!ctrl[15]) begin
        t_state <= (t_state == 3'd4) ? 3'b0 : t_state + 1'b1;
    end
end
```

### Conditional Jumps

JC (Jump if Carry) and JZ (Jump if Zero) store `IO|J` in the ROM like an unconditional jump. After the ROM lookup, a combinational block masks the J bit if the condition is not met:

```verilog
always @(*) begin
    ctrl = microcode[{opcode, t_state}];
    if (opcode == 4'd7 && !carry_flag) ctrl[1] = 1'b0; // JC: no carry
    if (opcode == 4'd8 && !zero_flag)  ctrl[1] = 1'b0; // JZ: no zero
end
```

---

## Output Register

**File:** `out_reg.v`

An 8-bit register that latches the bus value when `oi = 1`. It never drives the bus. The stored value is exposed as `out_val` — an always-active 8-bit output used to display the CPU's result in simulation.

```verilog
always @(posedge clk or posedge rst) begin
    if (rst)      out_reg <= 8'b0;
    else if (oi)  out_reg <= bus;
end
assign out_val = out_reg;
```

---

## Instruction Set

| Opcode | Mnemonic | Operation | Flags |
|--------|----------|-----------|-------|
| `0001` | `LDA addr` | A ← Mem[addr] | — |
| `0010` | `ADD addr` | A ← A + Mem[addr] | CF, ZF |
| `0011` | `SUB addr` | A ← A − Mem[addr] | CF, ZF |
| `0100` | `STA addr` | Mem[addr] ← A | — |
| `0101` | `LDI imm` | A ← immediate (lower 4 bits) | — |
| `0110` | `JMP addr` | PC ← addr | — |
| `0111` | `JC addr` | if carry: PC ← addr | — |
| `1000` | `JZ addr` | if zero: PC ← addr | — |
| `1110` | `OUT` | OutputReg ← A | — |
| `1111` | `HLT` | freeze clock | — |

All other opcodes produce no operation (all control signals low, T-state still advances).

---

## Microcode — T-States

Every instruction executes in exactly 5 clock steps (T0–T4). T0 and T1 are the **fetch cycle** — identical for every instruction. T2–T4 are the **execute cycle** — unique per opcode.

```
T0: CO | MI          Put PC value on bus, load into MAR
T1: RO | II | CE     RAM[MAR] → bus → IR; PC increments
T2–T4: instruction-specific (see table below)
```

| Instruction | T2 | T3 | T4 |
|---|---|---|---|
| LDA | IO\|MI | RO\|AI | — |
| ADD | IO\|MI | RO\|BI | EO\|AI\|FI |
| SUB | IO\|MI | RO\|BI | EO\|SU\|AI\|FI |
| STA | IO\|MI | AO\|RI | — |
| LDI | IO\|AI | — | — |
| JMP | IO\|J | — | — |
| JC | IO\|J *(if CF)* | — | — |
| JZ | IO\|J *(if ZF)* | — | — |
| OUT | AO\|OI | — | — |
| HLT | HLT | *(frozen)* | *(frozen)* |

---

## Control Signals

All 16 control signals are active HIGH. They are output by the Control Unit and consumed by each module as described:

| Signal | Full Name | Consumed By | Effect |
|--------|-----------|-------------|--------|
| `HLT` | Halt | Clock | Freezes `clk_out` at 0 |
| `MI` | MAR In | MAR | Loads `bus[3:0]` into MAR |
| `RI` | RAM In | RAM | Writes bus into `mem[MAR]` |
| `RO` | RAM Out | RAM | Drives `mem[MAR]` onto bus |
| `IO` | IR Out | IR | Drives `{0, ir[3:0]}` onto bus |
| `II` | IR In | IR | Loads bus into IR |
| `AI` | A In | A Register | Loads bus into A |
| `AO` | A Out | A Register | Drives A onto bus |
| `EO` | ALU Out | ALU | Drives ALU result onto bus |
| `SU` | Subtract | ALU | Selects subtraction mode |
| `BI` | B In | B Register | Loads bus into B |
| `OI` | Output In | Output Reg | Loads bus into output register |
| `CE` | Count Enable | PC | Increments PC |
| `CO` | Counter Out | PC | Drives PC onto bus |
| `J` | Jump | PC | Loads `bus[3:0]` into PC |
| `FI` | Flags In | ALU | Latches carry and zero flags |

---

## File Structure

```
8_bit_computer/
├── 8_bit_computer.xpr                   (Vivado project file)
├── 8_bit_computer.srcs/
│   ├── sources_1/new/                   (design sources)
│   │   ├── clock.v
│   │   ├── reg_a.v
│   │   ├── reg_b.v
│   │   ├── ALU.v
│   │   ├── mar.v
│   │   ├── ram.v
│   │   ├── pc.v                         (module: program_counter)
│   │   ├── ir.v                         (module: instruction_register)
│   │   ├── out_reg.v                    (module: output_register)
│   │   ├── control_unit.v
│   │   └── cpu.v                        (module: cpu_top — top level)
│   └── sim_1/new/                       (testbenches)
│       ├── clk_tb.v
│       ├── tb_rega.v
│       ├── tb_alu.v
│       ├── tb_control.v
│       └── tb_cpu.v
└── README.md
```

---

## How to Simulate in Vivado

### Individual module

1. Create a new RTL project in Vivado (Verilog, any device target)
2. Add Sources → add the module `.v` file and its `_tb.v` file
3. In the Sources panel under **Simulation Sources**, right-click the `_tb` module → **Set as Top**
4. Click **Run Behavioral Simulation**
5. Read `[PASS]` / `[FAIL]` lines in the Tcl console
6. Add signals to the waveform viewer to inspect timing

### Recommended simulation order

Simulate each module individually before integrating. Each one depends on no others except `cpu.v`, which requires all of them.

```
clk_tb → tb_rega → tb_alu → tb_control → tb_cpu
```

---

## Running the Full CPU

The full-CPU testbench `tb_cpu.v` loads a program into RAM using hierarchical references, releases reset, and waits for the `hlt` signal to go high:

```verilog
cpu.u_ram.mem[0]  = 8'b0001_1110; // LDA 14
cpu.u_ram.mem[1]  = 8'b0010_1111; // ADD 15
cpu.u_ram.mem[2]  = 8'b1110_0000; // OUT
cpu.u_ram.mem[3]  = 8'b1111_0000; // HLT
```

Set `cpu_tb` as the simulation top module and run. The Tcl console prints the state of every control signal at each clock tick. The simulation ends with either `[PASS]` or `[FAIL]` depending on `out_val`.

**Useful waveform signals to add:**

- `cpu.clk` — see the generated clock
- `cpu.bus` — watch which module is driving at each T-state
- `cpu.t_state_out` — see the T-state counter advancing
- `cpu.opcode` — see instructions being decoded
- `cpu.a_out` — watch the accumulator change
- `out_val` — the final output

### Common failure modes

| Symptom | Cause |
|---------|-------|
| `bus = X` in waveform | Two modules driving bus at same time — microcode conflict |
| CPU never halts | HLT instruction not at correct RAM address or wrong opcode |
| `out_val` never updates | OUT instruction not reaching the output register |
| Wrong result | Incorrect data values at RAM addresses 14/15 |
| T-state stuck at 0 | Clock not reaching modules — check `clk_out` from clock module |

---

## Example Program

The default testbench program computes **28 + 14 = 42**:

```
Addr  Instruction    Encoding     What happens
────  ───────────    ────────     ────────────────────────────────────
  0   LDA 14         0001 1110    A ← Mem[14] = 28
  1   ADD 15         0010 1111    A ← A + Mem[15] = 28 + 14 = 42
  2   OUT            1110 0000    OutputReg ← A = 42
  3   HLT            1111 0000    Clock freezes. out_val = 0x2A = 42.
  …
 14   (data)         0001 1100    28  (0x1C)
 15   (data)         0000 1110    14  (0x0E)
```

To run a different program, replace the values in `tb_cpu.v`'s `load_program` task. The CPU can address 16 bytes total — instructions and data share the same space, so a program plus its data must fit within addresses 0–15.

---

---

## Writing Your Own Programs

An instruction is one byte. The upper nibble is the opcode, the lower nibble is the operand (a memory address or an immediate value). Instructions and data share the same 16-byte address space, so they must be packed carefully.

### Encoding an instruction

```
LDA 14  →  opcode=0001  operand=1110  →  0001_1110  →  0x1E
ADD 15  →  opcode=0010  operand=1111  →  0010_1111  →  0x2F
OUT     →  opcode=1110  operand=0000  →  1110_0000  →  0xE0
HLT     →  opcode=1111  operand=0000  →  1111_0000  →  0xF0
```

Instructions with no operand (OUT, HLT) still fill the full byte — the lower nibble is simply unused and should be zero.

### Memory layout convention

Place instructions at low addresses (0 upward) and data at high addresses (15 downward). This avoids the PC accidentally running into data values and interpreting them as instructions.

```
Addr 0–N   : instructions
Addr 15 ↓  : data (counting down from 15)
```

### Example: counting down from 5 to 0

```
Addr  Content  Encoding    Comment
  0   LDA 15   0001 1111   A = 5
  1   OUT      1110 0000   display A
  2   SUB 14   0011 1110   A = A - 1
  3   JZ  5    1000 0101   if A == 0, jump to HLT
  4   JMP 1    0110 0001   loop back to OUT
  5   HLT      1111 0000   done
 14   0x01     0000 0001   constant 1 (subtractor)
 15   0x05     0000 0101   constant 5 (start value)
```

Load into the testbench:

```verilog
cpu.u_ram.mem[0]  = 8'b0001_1111; // LDA 15
cpu.u_ram.mem[1]  = 8'b1110_0000; // OUT
cpu.u_ram.mem[2]  = 8'b0011_1110; // SUB 14
cpu.u_ram.mem[3]  = 8'b1000_0101; // JZ 5
cpu.u_ram.mem[4]  = 8'b0110_0001; // JMP 1
cpu.u_ram.mem[5]  = 8'b1111_0000; // HLT
cpu.u_ram.mem[14] = 8'h01;        // 1
cpu.u_ram.mem[15] = 8'h05;        // 5
```

`out_val` will show `0x05`, then `0x04`, `0x03`, `0x02`, `0x01`, `0x00` before halting.

### Constraints to keep in mind

- Maximum program length including data: 16 bytes total
- Addresses are 4-bit — operands above 15 are invalid
- LDI only loads the lower nibble of the instruction byte — immediate values are limited to 0–15
- There is no stack and no subroutine call — JMP and conditional jumps are the only flow control

---

## Behavioural vs Structural Verilog

This project implements the CPU in **behavioural Verilog** — using `always` blocks and `assign` statements to describe what each module does, leaving it to the synthesiser to figure out the gates.

A second version of the same CPU can be written at the **structural level** — building each module from primitive gates and flip-flops. Both versions produce identical simulation results; the structural version just makes the underlying hardware explicit.

### What changes at the structural level

| Module | Behavioural | Structural equivalent |
|--------|------------|----------------------|
| A / B registers | `always @(posedge clk)` | 8× D flip-flop + 8× tri-state buffer |
| ALU | `+` and `~` operators | Chain of full adders from XOR/AND/OR gates |
| Program Counter | `pc + 1` | 4-bit ripple carry counter from JK flip-flops |
| Instruction Register | `always @(posedge clk)` | 8× D flip-flop with output enable |
| RAM | `reg [7:0] mem[0:15]` | Stays behavioural — memory arrays have no gate equivalent |
| Control Unit | `initial` + `case` | Stays behavioural — ROM has no meaningful gate expansion |

### Structural full adder

The building block of the structural ALU. Built entirely from logic primitives:

```verilog
module full_adder (
    input  a, b, cin,
    output sum, cout
);
    wire axb, ab, axbc;
    xor (axb,  a,   b  );
    xor (sum,  axb, cin);
    and (ab,   a,   b  );
    and (axbc, axb, cin);
    or  (cout, ab,  axbc);
endmodule
```

Eight of these chained together form the ripple carry adder. The XOR with `su` and the carry-in from `su` slot directly into this chain — no extra logic needed for subtraction.

### Structural D flip-flop

The building block of every register:

```verilog
module d_ff (
    input  clk, rst, d,
    output reg q
);
    always @(posedge clk or posedge rst) begin
        if (rst) q <= 1'b0;
        else     q <= d;
    end
endmodule
```

Eight of these with a shared clock, reset, and load enable form one register bit-slice. The load enable is implemented by multiplexing `d` and `q` — if load is low, `d_in = q` (hold); if load is high, `d_in = bus_bit` (load).

### Verifying equivalence

The cleanest way to confirm the structural version is correct is to run both in the same testbench and assert that `out_val` matches cycle for cycle:

```verilog
always @(posedge clk) begin
    if (cpu_behavioural.out_val !== cpu_structural.out_val)
        $display("[MISMATCH] t=%0t behavioural=0x%02h structural=0x%02h",
                 $time,
                 cpu_behavioural.out_val,
                 cpu_structural.out_val);
end
```

If no mismatches appear before HLT, the two implementations are functionally equivalent.

---

## How Data Moves — A Traced Example

To make the bus mechanics concrete, here is what happens cycle by cycle when the CPU executes `LDA 14`:

```
Instruction byte: 0001_1110
Stored at RAM address 0.
```

**T0 — Fetch address**
Control signals: `CO=1, MI=1`
- PC (currently 0) drives `0x00` onto the bus via CO
- MAR reads `bus[3:0] = 0` via MI
- Bus value: `0x00`

**T1 — Fetch instruction**
Control signals: `RO=1, II=1, CE=1`
- RAM reads `mem[0] = 0x1E` and drives it onto the bus via RO
- IR latches `0x1E` via II — opcode becomes `0001`, operand becomes `1110`
- PC increments to 1 via CE
- Bus value: `0x1E`

**T2 — Load operand address into MAR**
Control signals: `IO=1, MI=1`
- IR drives `{4'b0, 0xE} = 0x0E` onto bus via IO
- MAR reads `bus[3:0] = 14` via MI
- Bus value: `0x0E`

**T3 — Load data into A**
Control signals: `RO=1, AI=1`
- RAM reads `mem[14] = 0x1C` and drives it onto bus via RO
- A register latches `0x1C` via AI
- Bus value: `0x1C`

**T4 — No operation**
All control signals: `0`
- Bus: high-Z (nobody driving)
- T-state wraps to 0, next instruction begins

After T3, `a_out = 0x1C = 28`. The instruction is complete.

---

## Key Verilog Concepts Used

### Non-blocking assignment `<=`

Used inside every `always @(posedge clk)` block. All right-hand sides are evaluated from the current state before any assignments apply. This matches how real flip-flops behave — all bits in a register capture their inputs simultaneously on the same clock edge.

```verilog
// Both flags read full_result at the same instant
carry_flag <= full_result[8];
zero_flag  <= (full_result[7:0] == 8'b0);
```

### Blocking assignment `=`

Used inside `always @(*)` (combinational) blocks and inside `initial` blocks. Executes sequentially, line by line.

### Tri-state `8'bz`

High impedance — the module disconnects from the bus. Only meaningful on a shared `wire`. In simulation, Vivado renders an undriven bus wire as a mid-rail blue line. Any module that can drive the bus must output `8'bz` when its output-enable is low.

### Concatenation `{a, b}`

Joins two bit vectors. Used throughout to zero-pad narrower values onto the 8-bit bus:

```verilog
{4'b0, pc}       // 4-bit PC → 8-bit bus value
{4'b0, ir[3:0]}  // 4-bit operand → 8-bit bus value
{1'b0, a}        // 8-bit A → 9-bit for carry detection
```

### Parameter

Compile-time constant used to configure a module without editing its internals:

```verilog
cpu_top #(.PERIOD(5))  cpu (...);  // 10 ns period — for simulation
cpu_top #(.PERIOD(50)) cpu (...);  // 100 ns period — slower simulation
```

---

## Design Decisions

**Why synchronous write but combinational read for RAM?**
Real static RAM is asynchronous — data appears at the output immediately when the address changes, with no clock needed. The combinational `assign bus = ro ? mem[mar_out] : 8'bz` models this accurately. Write is made synchronous (clocked) to keep it well-behaved in simulation and to avoid race conditions.

**Why does the ALU have a clock if it is purely combinational?**
The ALU computation itself (`full_result`) is combinational and always live. The clock is only used by the flags register inside the ALU module. The flags need to be sampled at a specific moment (when `fi=1`) rather than fluctuating continuously as A and B change during other instructions.

**Why is `opcode` always driven from the IR, not gated by a control signal?**
The Control Unit needs to see the current opcode at every T-state to produce the correct microcode row. If `opcode` were gated and happened to be low during T0 or T1, the control unit would look up the wrong row for the fetch cycle. Keeping it always-on means the control unit always has accurate instruction information.

**Why does `j` take priority over `ce` in the Program Counter?**
During a JMP instruction at T2, the microcode sets `J=1` but not `CE`. There is no case where both should fire together in a correct program. However, making J win by priority is a defensive choice — if a microcode bug accidentally set both bits, the jump would execute and the increment would be silently ignored rather than corrupting the PC with an increment-then-jump sequence.

**Why 5 T-states per instruction when some need only 3?**
Simplicity. A fixed 5-step pipeline means the T-state counter logic is trivial — count 0 to 4, wrap. Instructions that need fewer steps (LDI, JMP, OUT, HLT) simply have NOP control words at their unused T-states. The cost is a few extra idle clock cycles per instruction, which is acceptable for a machine of this size.

---

*This CPU architecture is based on the SAP-1 (Simple As Possible) design described in "Digital Computer Electronics" by Malvino & Brown, popularised as a hands-on hardware build by Ben Eater.*
