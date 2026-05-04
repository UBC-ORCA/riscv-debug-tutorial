# Debug Integration on the DDCA Single-Cycle Core

A working, simulated implementation of the CPU side of the RISC-V external
debug interface, integrated directly on top of the textbook's `riscvsingle.v`.

---

### Textbook (Harris & Harris, Section 7.6) — split into per-module files

| File             | Module(s)                                                                                                     |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| `riscvsingle.sv` | `riscvsingle` — top-level processor wrapper (modified to plumb debug ports)                                   |
| `top.sv`         | `top` — wraps processor + imem + dmem (modified to expose debug ports)                                        |
| `controller.sv`  | `controller`, `maindec`, `aludec` (modified to decode SYSTEM and produce `is_ebreak` / `is_dret`)             |
| `datapath.sv`    | `datapath` (modified: 2-bit `PCSrc`, new `dm_halt_addr_i` and `dpc` inputs, `pcmux` upgraded from 2:1 to 4:1) |
| `regfile.sv`     | `regfile` (unchanged)                                                                                         |
| `alu.sv`         | `alu` (unchanged)                                                                                             |
| `extend.sv`      | `extend` (unchanged)                                                                                          |
| `imem.sv`        | `imem` (unchanged — loads `riscvtest.txt`)                                                                    |
| `dmem.sv`        | `dmem` (unchanged)                                                                                            |
| `cells.sv`       | `adder`, `flopr`, `mux2`, `mux3`, plus new `mux4` for the next-PC selector                                    |

---

### New for debug

| File            | Purpose                                                                                                                                                                                                         |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `debug_fsm.sv`  | Two-state FSM (`CPU_RUNNING` / `PARKED_LOOP`) with debug CSRs (`dpc`, `dcsr`, `dscratch0`, `dscratch1`). Latches `dpc` on entry, drives `enter_debug` / `exit_debug`, and writes `dcsr.cause` on entry.         |
| `tb_debug.sv`   | Self-checking Verilator testbench acting as the Debug Module — asserts `debug_req_i`, waits for `debug_halted_o`, checks PC redirect to `dm_halt_addr_i`, waits for DRET resume, and confirms forward progress. |
| `riscvtest.txt` | 4-instruction test program: a `x1++` loop plus a `dret` stub at `0x0C`.                                                                                                                                         |

---

## How the integration works 

When `debug_req_i` (or an `ebreak`) fires while the FSM is in `CPU_RUNNING`, the FSM transitions to `PARKED_LOOP`, latches the current PC into `dpc`, and raises `enter_debug`.

The wrapper uses `enter_debug` to drive `PCSrc = 2'b10`, selecting `dm_halt_addr_i` as the next PC. The core fetches from the Debug ROM on the next cycle. `enter_debug` also gates `RegWrite` and `MemWrite` so the interrupted instruction does not retire.

When the Debug ROM stub executes `dret`, the FSM raises `exit_debug`. The wrapper then drives `PCSrc = 2'b11` to select `dpc`, the FSM returns to `CPU_RUNNING`, and execution resumes exactly where it left off.

