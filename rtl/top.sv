// =============================================================================
// top.sv
//
// Top-level wrapper. Stitches the processor together with its instruction
// memory and data memory, and exposes the debug interface to the testbench
// (which plays the role of the Debug Module).
// =============================================================================

module top(input  logic        clk, reset,
           // Debug interface (driven by the testbench / DM)
           input  logic        debug_req_i,
           input  logic [31:0] dm_halt_addr_i,
           input  logic [31:0] dm_exception_addr_i,
           output logic        debug_halted_o,
           // Original outputs
           output logic [31:0] WriteData, DataAdr,
           output logic        MemWrite);

  logic [31:0] PC, Instr, ReadData;

  // instantiate processor and memories
  riscvsingle rvsingle(.clk                 (clk),
                       .reset               (reset),
                       .PC                  (PC),
                       .Instr               (Instr),
                       .MemWrite            (MemWrite),
                       .ALUResult           (DataAdr),
                       .WriteData           (WriteData),
                       .ReadData            (ReadData),
                       .debug_req_i         (debug_req_i),
                       .dm_halt_addr_i      (dm_halt_addr_i),
                       .dm_exception_addr_i (dm_exception_addr_i),
                       .debug_halted_o      (debug_halted_o));

  imem imem(PC, Instr);
  dmem dmem(clk, MemWrite, DataAdr, WriteData, ReadData);
endmodule
