module debug_fsm (input logic clk, reset,
                   input logic debug_req_i,
                   input logic [31:0] dm_halt_addr_i,
                   input logic [31:0] dm_exception_addr_i,
                   input logic is_ebreak,
                   input logic is_dret,
                   input logic [31:0] pc,
                   output logic debug_halted_o,

                    // signals that go the datapath mux 
                    output logic        debug_mode_o,
                    output logic        enter_debug,
                    output logic        exit_debug,

                    output logic [31:0] dpc,

                    // Debug-specific CSRs (RISC-V Debug Spec Section 4)
                    output logic [31:0] dcsr,
                    output logic [31:0] dscratch0,
                    output logic [31:0] dscratch1);


logic [1:0] state;

parameter CPU_RUNNING = 2'b00, PARKED_LOOP = 2'b11;

assign enter_debug = (debug_req_i | is_ebreak) && !debug_mode_o; 
assign exit_debug  =  is_dret && debug_mode_o;



always_ff @(posedge clk) begin


    if (reset) begin
        state     <= CPU_RUNNING;
        dpc       <= 32'h0;
        dcsr      <= 32'h0;
        dscratch0 <= 32'h0;
        dscratch1 <= 32'h0;
    end
    

    else begin
        case (state)
            CPU_RUNNING: begin
                if (enter_debug) begin
                    state     <= PARKED_LOOP;
                    dpc       <= pc;                              // Save current PC to DPC
                    dcsr[8:6] <= is_ebreak ? 3'd1 : 3'd3;         // dcsr.cause: 1 = ebreak, 3 = debug_req
                end

                else state <= CPU_RUNNING;

            end

            PARKED_LOOP: begin
                
                if (exit_debug) begin 

                    state <= CPU_RUNNING;

                end 

                else state <= PARKED_LOOP;

            end

            default : state <= CPU_RUNNING; // safe recovery

        endcase
    end

end


always_comb begin
    
    case (state)
        CPU_RUNNING: begin
            // state = 2'b00;
            debug_mode_o = state[0];
            debug_halted_o = state[1];
        end

        PARKED_LOOP: begin
            // state = 2'b11;
            debug_mode_o = state[0];
            debug_halted_o = state[1];
        end


        default: begin
            debug_mode_o = 1'bx;
            debug_halted_o = 1'bx;
            end
        

    endcase
    
end


endmodule