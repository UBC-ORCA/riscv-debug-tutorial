// =============================================================================
// Self-checking testbench for the debug-enabled DDCA core. Plays the role
// of the DM (Debug Module) — drives `debug_req_i`, watches `debug_halted_o` and
// the PC, and verifies the full halt -> resume round trip.
//
// Test program (loaded into imem from riscvtest.txt):
//   0x000: addi x1, x0, 0      ; x1 = 0
//   0x004: addi x1, x1, 1      ; x1++
//   0x008: jal  x0, -4         ; loop back to 0x004 forever
//   0x00C: dret                ; debug ROM "stub": immediate resume
//
// dm_halt_addr_i is set to 0x0C, so when the testbench raises debug_req_i,
// the FSM redirects PC to 0x0C, fetches the DRET, and resumes back to dpc.
// =============================================================================

module tb_debug;

  logic        clk;
  logic        reset = 1;
  logic        debug_req_i = 0;
  logic [31:0] dm_halt_addr_i      = 32'h0000_000C;
  logic [31:0] dm_exception_addr_i = 32'h0000_0010;
  logic        debug_halted_o;
  logic [31:0] WriteData, DataAdr;
  logic        MemWrite;


  logic [31:0] PC, Instr, ReadData;

  initial begin 
    clk=0;
    forever begin 
        clk = ~clk;
        #5;
    end 
  end 


  // DUT
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

  // Trace
  int unsigned cycle = 0;
  always @(posedge clk) begin 
     cycle <= cycle + 1;
  end

  always @(posedge clk) begin
    if (cycle >= 4 && cycle < 80) begin
      $display("cyc=%0d  pc=%h  instr=%h  halted=%b  dreq=%b",
               cycle, PC, Instr, debug_halted_o, debug_req_i);
    end
  end

  // Stimulus + checks
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_debug);

    // Release reset after a few clocks
    repeat (3) @(posedge clk);
    reset = 0;

    // Check that the cpu is still running the user program (not halted) 
    repeat (20) @(posedge clk);
    if (PC > 32'h0000_0008) begin
      $display("[FAIL] Phase 1: PC=%h, expected user program (0x00..0x08)", PC);
      $fatal(1);
    end
    $display("[PASS] Phase 1: free-run looping in user program, PC=%h", PC);

    // assert debug_req for one cycle ----
    @(posedge clk);
    debug_req_i = 1;
    @(posedge clk);
    debug_req_i = 0;

    //wait for halt to be visible ----
    wait (debug_halted_o == 1'b1);
    $display("[PASS] Phase 3: HALTED, PC=%h, debug_halted_o high", PC);
    if (PC !== dm_halt_addr_i) begin
      $display("[FAIL] Phase 3: PC=%h, expected %h", PC, dm_halt_addr_i);
      $fatal(1);
    end

    // wait for resume ----
    wait (debug_halted_o == 1'b0);
    $display("[PASS] Phase 4: RESUMED, PC=%h, debug_halted_o low", PC);
    if (PC > 32'h0000_0008) begin
      $display("[FAIL] Phase 4: PC=%h, expected user program after resume", PC);
      $fatal(1);
    end

    // verify the program is still running ----
    repeat (15) @(posedge clk);
    if (PC > 32'h0000_0008) begin
      $display("[FAIL] Phase 5: PC=%h after extra time, lost program", PC);
      $fatal(1);
    end
    $display("[PASS] Phase 5: program still ticking, PC=%h", PC);

    $display("");
    $display("==================================================");
    $display("  ALL CHECKS PASSED");
    $display("    halt -> resume round trip works");
    $display("==================================================");
    $finish;
  end

endmodule
