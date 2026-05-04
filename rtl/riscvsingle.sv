// =============================================================================
// riscvsingle.sv
//
// Single-cycle implementation of RISC-V (RV32I subset).
// From Section 7.6 of Digital Design & Computer Architecture
// (Harris & Harris, 2020), with the CPU-side of the RISC-V external debug
// interface integrated.
//
// Debug additions vs. textbook:
//   - New ports: debug_req_i, dm_halt_addr_i, dm_exception_addr_i,
//     debug_halted_o.
//   - Instantiates debug_fsm to track debug mode and produce
//     enter_debug / exit_debug pulses + dpc.
//   - Extends PCSrc from 1 bit to 2 bits and routes dm_halt_addr_i / dpc
//     into the datapath's pcmux.
//   - Gates RegWrite and MemWrite with ~enter_debug so the interrupted
//     instruction doesn't retire on the cycle the core enters debug.
// =============================================================================

module riscvsingle(input  logic        clk, reset,
                   output logic [31:0] PC,
                   input  logic [31:0] Instr,
                   output logic        MemWrite,
                   output logic [31:0] ALUResult, WriteData,
                   input  logic [31:0] ReadData,
                   // Debug interface ports
                   input  logic        debug_req_i,
                   input  logic [31:0] dm_halt_addr_i,
                   input  logic [31:0] dm_exception_addr_i,
                   output logic        debug_halted_o);

  // Original control wires
  logic       ALUSrc, RegWrite, Jump, Zero;
  logic [1:0] ResultSrc, ImmSrc;
  logic [2:0] ALUControl;
  logic       PCSrc_branch_jump;     // controller's 1-bit PCSrc (branch/jump)
  logic       MemWrite_internal;     // ungated MemWrite from controller
  logic [1:0] PCSrc_final;           // 2-bit selector to datapath

  // Debug wires
  logic        is_ebreak, is_dret;
  logic        debug_mode_o, enter_debug, exit_debug;
  logic [31:0] dpc;
  logic [31:0] dcsr, dscratch0, dscratch1;

  // Gated retire signals
  logic        RegWrite_gated, MemWrite_gated;

  // ---------------------------------------------------------------------------
  // Controller
  // ---------------------------------------------------------------------------
  controller c(.op         (Instr[6:0]),
               .funct3     (Instr[14:12]),
               .funct7b5   (Instr[30]),
               .Zero       (Zero),
               .Instr      (Instr[31:20]),
               .ResultSrc  (ResultSrc),
               .MemWrite   (MemWrite_internal),
               .PCSrc      (PCSrc_branch_jump),
               .ALUSrc     (ALUSrc),
               .RegWrite   (RegWrite),
               .Jump       (Jump),
               .ImmSrc     (ImmSrc),
               .ALUControl (ALUControl),
               .is_ebreak  (is_ebreak),
               .is_dret    (is_dret));

  // ---------------------------------------------------------------------------
  // Debug FSM
  // ---------------------------------------------------------------------------
  debug_fsm debug_fsm_inst(.clk                 (clk),
                           .reset               (reset),
                           .debug_req_i         (debug_req_i),
                           .dm_halt_addr_i      (dm_halt_addr_i),
                           .dm_exception_addr_i (dm_exception_addr_i),
                           .is_ebreak           (is_ebreak),
                           .is_dret             (is_dret),
                           .pc                  (PC),
                           .debug_halted_o      (debug_halted_o),
                           .debug_mode_o        (debug_mode_o),
                           .enter_debug         (enter_debug),
                           .exit_debug          (exit_debug),
                           .dpc                 (dpc),
                           .dcsr                (dcsr),
                           .dscratch0           (dscratch0),
                           .dscratch1           (dscratch1));

  // ---------------------------------------------------------------------------
  // PC source selection — extend 1-bit branch/jump signal to 2-bit selector,
  // with debug overrides taking priority.
  //   2'b00 sequential, 2'b01 branch/jal, 2'b10 halt, 2'b11 resume(dret)
  // ---------------------------------------------------------------------------
  always_comb begin
      if      (enter_debug)        PCSrc_final = 2'b10;
      else if (exit_debug)         PCSrc_final = 2'b11;
      else if (PCSrc_branch_jump)  PCSrc_final = 2'b01;
      else                         PCSrc_final = 2'b00;
  end

  // ---------------------------------------------------------------------------
  // Retire gating — suppress writeback the cycle we enter debug so the
  // interrupted instruction re-executes cleanly on resume from dpc.
  // ---------------------------------------------------------------------------
  assign RegWrite_gated = RegWrite          & ~enter_debug;
  assign MemWrite_gated = MemWrite_internal & ~enter_debug;
  assign MemWrite       = MemWrite_gated;       // top-level output

  // ---------------------------------------------------------------------------
  // Datapath
  // ---------------------------------------------------------------------------
  datapath dp(.clk            (clk),
              .reset          (reset),
              .ResultSrc      (ResultSrc),
              .PCSrc          (PCSrc_final),
              .ALUSrc         (ALUSrc),
              .RegWrite       (RegWrite_gated),
              .ImmSrc         (ImmSrc),
              .ALUControl     (ALUControl),
              .dm_halt_addr_i (dm_halt_addr_i),
              .dpc            (dpc),
              .Zero           (Zero),
              .PC             (PC),
              .Instr          (Instr),
              .ALUResult      (ALUResult),
              .WriteData      (WriteData),
              .ReadData       (ReadData));
endmodule
