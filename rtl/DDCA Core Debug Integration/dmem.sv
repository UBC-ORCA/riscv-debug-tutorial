// =============================================================================
// dmem.sv
//
// Data memory. 64 words, word-aligned. Combinational read; writes on the
// rising edge of clk when `we` is high.
// =============================================================================

module dmem(input  logic        clk, we,
            input  logic [31:0] a, wd,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  assign rd = RAM[a[31:2]]; // word aligned

  always_ff @(posedge clk)
    if (we) RAM[a[31:2]] <= wd;
endmodule
