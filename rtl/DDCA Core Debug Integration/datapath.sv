// =============================================================================
// datapath.sv
//
// Datapath for the single-cycle RV32I core. Wires together:
//   - PC register and next-PC adders / mux
//   - register file
//   - immediate extender
//   - ALU and result mux
//
// Debug additions:
//   - PCSrc is now 2 bits and the next-PC mux is 4:1, so the FSM can
//     redirect the PC to the Debug ROM (dm_halt_addr_i) on halt and back to
//     dpc on dret.
// =============================================================================

module datapath(input  logic        clk, reset,
                input  logic [1:0]  ResultSrc,
                input  logic [1:0]  PCSrc,                  // now 2 bits
                input  logic        ALUSrc,
                input  logic        RegWrite,
                input  logic [1:0]  ImmSrc,
                input  logic [2:0]  ALUControl,
                input  logic [31:0] dm_halt_addr_i,         // new — halt target
                input  logic [31:0] dpc,                    // new — dret target
                output logic        Zero,
                output logic [31:0] PC,
                input  logic [31:0] Instr,
                output logic [31:0] ALUResult, WriteData,
                input  logic [31:0] ReadData);

  logic [31:0] PCNext, PCPlus4, PCTarget;
  logic [31:0] ImmExt;
  logic [31:0] SrcA, SrcB;
  logic [31:0] Result;

  // next PC logic — pcmux is now 4:1
  // PCSrc encoding:
  //   2'b00 -> PCPlus4         (sequential)
  //   2'b01 -> PCTarget        (branch / jal)
  //   2'b10 -> dm_halt_addr_i  (entering debug)
  //   2'b11 -> dpc             (resuming via dret)
  flopr #(32) pcreg(clk, reset, PCNext, PC);
  adder       pcadd4(PC, 32'd4, PCPlus4);
  adder       pcaddbranch(PC, ImmExt, PCTarget);
  mux4 #(32)  pcmux(PCPlus4, PCTarget, dm_halt_addr_i, dpc, PCSrc, PCNext);

  // register file logic
  regfile     rf(clk, RegWrite, Instr[19:15], Instr[24:20],
                 Instr[11:7], Result, SrcA, WriteData);
  extend      ext(Instr[31:7], ImmSrc, ImmExt);

  // ALU logic
  mux2 #(32)  srcbmux(WriteData, ImmExt, ALUSrc, SrcB);
  alu         alu(SrcA, SrcB, ALUControl, ALUResult, Zero);
  mux3 #(32)  resultmux(ALUResult, ReadData, PCPlus4, ResultSrc, Result);
endmodule
