// =============================================================================
// controller.sv
//
// Control unit. Splits into:
//   - controller : top-level control wrapper
//   - maindec    : main decoder driven by opcode
//   - aludec     : ALU decoder driven by ALUOp/funct3/funct7b5
//
// PCSrc is computed locally as (Branch & Zero) | Jump.
//
// Debug additions:
//   - SYSTEM opcode (1110011) is decoded as a NOP by maindec (no RegWrite,
//     no MemWrite, no Branch, no Jump).
//   - is_ebreak / is_dret are produced separately from imm12 (Instr[31:20])
//     and exposed for the debug FSM, since maindec only sees the opcode.
// =============================================================================

module controller(input  logic [6:0]   op,
                  input  logic [2:0]   funct3,
                  input  logic         funct7b5,
                  input  logic         Zero,
                  input  logic [31:20] Instr,        // imm12 slice for SYSTEM decode
                  output logic [1:0]   ResultSrc,
                  output logic         MemWrite,
                  output logic         PCSrc, ALUSrc,
                  output logic         RegWrite, Jump,
                  output logic [1:0]   ImmSrc,
                  output logic [2:0]   ALUControl,
                  output logic         is_ebreak,
                  output logic         is_dret);

  logic [1:0] ALUOp;
  logic       Branch;
  logic       system_instr;   // internal — not a port

  // SYSTEM-instruction decode for the debug FSM
  assign system_instr = (op == 7'b1110011);
  assign is_ebreak    = system_instr & (Instr[31:20] == 12'b000000000001);
  assign is_dret      = system_instr & (Instr[31:20] == 12'b011110110010);

  maindec md(op, ResultSrc, MemWrite, Branch,
             ALUSrc, RegWrite, Jump, ImmSrc, ALUOp);
  aludec  ad(op[5], funct3, funct7b5, ALUOp, ALUControl);

  assign PCSrc = Branch & Zero | Jump;
endmodule

module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  logic [10:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
      7'b1110011: controls = 11'b0_00_0_0_00_0_00_0; // SYSTEM (ebreak, dret) — NOP from datapath POV
      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // non-implemented instruction
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5,
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // addition
      2'b01:                ALUControl = 3'b001; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub)
                            ALUControl = 3'b001; // sub
                          else
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // ???
               endcase
    endcase
endmodule
