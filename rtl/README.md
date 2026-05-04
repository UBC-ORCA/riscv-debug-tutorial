# Debug Integration on the DDCA Single-Cycle Core

A working, simulated implementation of the CPU side of the RISC-V external
debug interface, integrated directly on top of the textbook `riscvsingle.v`
from *Digital Design & Computer Architecture* (Harris & Harris, Section 7.6).

Companion to the main tutorial in this repository — the tutorial walks through
the full debug stack from GDB down to the CPU debug interface; this folder is
the concrete answer to "what would the textbook DDCA core need in order to
support a real run-control debug flow?" implemented and tested end to end.

## What's here

The textbook core has been split into one module per file for readability.
Files are grouped below by whether they are textbook-original or new for the
debug integration.

### Textbook (Harris & Harris, Section 7.6) — split into per-module files

| File             | Module(s)                          |
|------------------|------------------------------------|
| `riscvsingle.sv` | `riscvsingle` — top-level processor wrapper (modified to plumb debug ports) |
| `top.sv`         | `top` — wraps processor + imem + dmem (modified to expose debug ports) |
| `controller.sv`  | `controller`, `maindec`, `aludec` (modified to decode SYSTEM and produce `is_ebreak` / `is_dret`) |
| `datapath.sv`    | `datapath` (modified: 2-bit `PCSrc`, new `dm_halt_addr_i` and `dpc` inputs, `pcmux` upgraded from 2:1 to 4:1) |
| `regfile.sv`     | `regfile` (unchanged) |
| `alu.sv`         | `alu` (unchanged) |
| `extend.sv`      | `extend` (unchanged) |
| `imem.sv`        | `imem` (unchanged — loads `riscvtest.txt`) |
| `dmem.sv`        | `dmem` (unchanged) |
| `cells.sv`       | `adder`, `flopr`, `mux2`, `mux3`, plus new `mux4` for the next-PC selector |

### New for debug

| File             | Purpose |
|------------------|---------|
| `debug_fsm.sv`   | Two-state FSM (`CPU_RUNNING` / `PARKED_LOOP`) with debug CSRs (`dpc`, `dcsr`, `dscratch0`, `dscratch1`). Latches `dpc` on entry, drives `enter_debug` / `exit_debug` to the wrapper, and writes `dcsr.cause` on entry. |
| `tb_debug.sv`    | Self-checking Verilator testbench. Plays the role of the Debug Module — asserts `debug_req_i`, waits for `debug_halted_o`, checks PC redirects to `dm_halt_addr_i`, waits for the DRET-driven resume, and confirms the program continues running afterward. |
| `riscvtest.txt`  | 4-instruction test program: a `x1++` loop in user code plus a `dret` stub at `0x0C` that the FSM redirects to. |

## How the integration works (one-paragraph version)

When `debug_req_i` (or an `ebreak` from user code) fires while the FSM is in
`CPU_RUNNING`, the FSM transitions to `PARKED_LOOP`, latches the current PC
into `dpc`, and raises `enter_debug`. The wrapper uses `enter_debug` to drive
`PCSrc = 2'b10`, which selects `dm_halt_addr_i` as the next PC source — the
core fetches from the Debug ROM on the next cycle. `enter_debug` also gates
`RegWrite` and `MemWrite` for that cycle so the interrupted instruction
doesn't retire. When the Debug ROM eventually executes `dret`, the FSM raises
`exit_debug`, the wrapper drives `PCSrc = 2'b11` to select `dpc`, the FSM
returns to `CPU_RUNNING`, and the user program resumes exactly where it left
off.

## How to run

Verilator >= 5.0 is required (we use `--binary` and `--timing`). On Ubuntu /
WSL2:

```bash
sudo apt install -y verilator gtkwave make g++   # one time
```

Build and run the testbench (from a path with no spaces — Make can't handle
spaces in paths):

```bash
# copy out of the spaced workspace path into a clean one:
rm -rf ~/debug-integration && mkdir ~/debug-integration && \
cp "/path/to/Debug Integration"/*.sv         ~/debug-integration/ && \
cp "/path/to/Debug Integration"/riscvtest.txt ~/debug-integration/ && \
rm  ~/debug-integration/testbench.sv && \
cd  ~/debug-integration && \
verilator --binary --trace --timing --top-module tb_debug \
  -Wall -Wno-fatal -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-SYNCASYNCNET \
  -Wno-DECLFILENAME -Wno-VARHIDDEN -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-EOFNEWLINE \
  *.sv && \
./obj_dir/Vtb_debug
```

To view the resulting waveform:

```bash
gtkwave waves.vcd &
```

Drag `clk`, `reset`, `debug_req_i`, `debug_halted_o`, `PC`, `Instr` into the
signals panel. The round trip is visible around cycles 23–25.

## What success looks like

A per-cycle trace followed by five `[PASS]` lines and an `ALL CHECKS PASSED`
banner. The phases are:

1. **Phase 1 — free-run.** The user program loops at `0x04` / `0x08`,
   incrementing `x1`. Confirms the modifications didn't break the textbook
   core.
2. **Phase 3 — halt.** After the testbench pulses `debug_req_i`, the FSM
   transitions to `PARKED_LOOP`, the wrapper redirects PC to
   `dm_halt_addr_i = 0x0C`, and `debug_halted_o` goes high. The interrupted
   instruction's writeback is suppressed.
3. **Phase 4 — resume.** Fetching `dret` at `0x0C` causes `is_dret` to fire,
   which combined with `debug_mode_o = 1` produces `exit_debug`. The wrapper
   redirects PC to `dpc`. The FSM returns to `CPU_RUNNING`.
4. **Phase 5 — sustained progress.** The program keeps incrementing `x1` for
   another 15 cycles, confirming the round trip didn't corrupt CPU state.

## Honest scope and limits

This is the **minimum CPU-side surface** required to demonstrate run-control
debug. Several things real cores do are deliberately out of scope:

- **No DM, DTM, or JTAG.** The testbench plays the role of the Debug Module
  by driving `debug_req_i` directly. Plumbing in `pulp-platform/riscv-dbg`
  over a real DMI master is the natural next step.
- **Park-loop is a stub.** The Debug ROM is a single `dret` at the halt
  address. A real CVE2/Ibex park loop polls a memory-mapped flag and jumps
  to `dret` when the DM clears it. That requires LW/SW (we have those) plus
  a memory-mapped DM region (we don't have a DM).
- **`dscratch0` / `dscratch1` are present but unused.** They are reset and
  declared per the spec, but the CPU has no `csrrw` / `csrrs` / `csrrc`
  instructions yet, so the debug ROM can't read or write them. Adding CSR
  instructions and a real abstract-command flow is the obvious extension.
- **`dcsr` only tracks `cause`.** The other fields (`step`, `ebreakm`/`s`/`u`,
  `mprven`, etc.) are tied off. Single-stepping is not implemented.
- **No exceptions or interrupts.** `dm_exception_addr_i` is wired through as
  a port for future exception handling but is not used today.

These are all conscious simplifications for the textbook context — the goal
is to show the run-control mechanism cleanly, not to ship a production core.

## Files modified vs. textbook

If you have the original `riscvsingle.sv` in front of you, the diff is small
and isolated:

- `controller.sv` — new SYSTEM case in `maindec` (treated as NOP from the
  datapath's POV), plus `is_ebreak` / `is_dret` outputs derived from
  `Instr[31:20]`.
- `datapath.sv` — `PCSrc` widened to 2 bits, two new inputs
  (`dm_halt_addr_i`, `dpc`), `mux2` pcmux replaced with `mux4`.
- `riscvsingle.sv` — debug ports added, `debug_fsm` instantiated, 2-bit
  `PCSrc_final` computed combinationally, `RegWrite` / `MemWrite` gated with
  `~enter_debug`.
- `cells.sv` — added `mux4`.
- `top.sv` — debug ports plumbed through.

Everything else is identical to the textbook.
