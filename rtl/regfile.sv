// =============================================================================
// regfile.sv
//
// Three-ported register file:
//   - two combinational read ports (A1/RD1, A2/RD2)
//   - one write port on the rising edge of clk (A3/WD3/WE3)
// Register x0 is hardwired to 0.
// =============================================================================

module regfile(input  logic        clk,
               input  logic        we3,
               input  logic [ 4:0] a1, a2, a3,
               input  logic [31:0] wd3,
               output logic [31:0] rd1, rd2);

  logic [31:0] rf[31:0];

  always_ff @(posedge clk)
    if (we3) rf[a3] <= wd3;

  assign rd1 = (a1 != 0) ? rf[a1] : 0;
  assign rd2 = (a2 != 0) ? rf[a2] : 0;
endmodule
