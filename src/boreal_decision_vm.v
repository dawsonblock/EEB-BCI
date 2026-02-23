`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v6.0 (Layer 3 Expansion)
 * Module: boreal_decision_vm
 * Description: Deterministic Micro-ISA Policy Execution Engine.
 * Sits between the Apex Core (`mu_out`) and the Inverse Kinematics `theta_1, theta_2`.
 * Executes a hard-coded ROM policy to map inference goals to Cartesian IK points
 * while evaluating safety tier escalations in real-time.
 */

module boreal_decision_vm (
    input  wire        clk,
    input  wire        rst_n,
    
    // Safety Status
    input  wire [1:0]  safety_tier,
    
    // Inference Input (Triggered every sample)
    input  wire        data_valid,
    input  wire signed [15:0] mu_out,
    
    // Outputs to CORDIC IK and VNS
    output reg signed  [15:0] target_x,
    output reg signed  [15:0] target_y,
    output reg                vm_ik_enable,
    output reg                vm_vns_override
);

    // Micro-ISA Opcodes [31:28]
    localparam OPCODE_NOP       = 4'h0;
    localparam OPCODE_CMP_MU    = 4'h1; // Compare `mu_out` to immediate
    localparam OPCODE_JLT       = 4'h2; // Jump if Less Than
    localparam OPCODE_JGT       = 4'h3; // Jump if Greater Than
    localparam OPCODE_SET_X     = 4'h4; // Set target_x immediate
    localparam OPCODE_SET_Y     = 4'h5; // Set target_y immediate
    localparam OPCODE_HALT      = 4'hE; // End evaluation cycle
    localparam OPCODE_VNS_TRIG  = 4'hF; // Force therapeutic override
    
    // 64-word Policy ROM
    reg [31:0] policy_rom [0:63];
    reg [5:0]  pc;          // Program Counter
    reg [1:0]  state;       // 0: IDLE, 1: EXEC, 2: DONE
    reg        cmp_flag_lt; // Less than flag
    reg        cmp_flag_gt; // Greater than flag
    
    // Wire out structural components
    wire [3:0]  opcode = policy_rom[pc][31:28];
    wire signed [15:0] imm = policy_rom[pc][15:0];
    wire [5:0]  jmp_addr = policy_rom[pc][5:0];

    // Load simple test policy: If mu_out > 1000, move Arm UP. Else, move Arm DOWN.
    integer i;
    initial begin
        // Reset ALL to NOP first
        for (i = 0; i < 64; i = i + 1) policy_rom[i] = {OPCODE_NOP, 28'd0};
        
        // Setup simple deterministic evaluation tree
        policy_rom[0] = {OPCODE_CMP_MU,   12'd0, 16'sd1000}; // CMP mu_out, 1000
        policy_rom[1] = {OPCODE_JGT,      22'd0, 6'd10};     // IF > 1000 GOTO 10
        policy_rom[2] = {OPCODE_SET_X,    12'd0, 16'sd20};   // DOWN Policy (X = 20)
        policy_rom[3] = {OPCODE_SET_Y,    12'd0, 16'sd50};   // DOWN Policy (Y = 50)
        policy_rom[4] = {OPCODE_HALT,     28'd0};            // HALT
        
        // Addr 10: UP Policy
        policy_rom[10] = {OPCODE_SET_X,   12'd0, 16'sd120};  // UP Policy (X = 120)
        policy_rom[11] = {OPCODE_SET_Y,   12'd0, 16'sd120};  // UP Policy (Y = 120)
        policy_rom[12] = {OPCODE_HALT,    28'd0};            // HALT
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= 2'd0; // IDLE
            pc              <= 6'd0;
            cmp_flag_lt     <= 1'b0;
            cmp_flag_gt     <= 1'b0;
            target_x        <= 16'd0;
            target_y        <= 16'd0;
            vm_ik_enable    <= 1'b0;
            vm_vns_override <= 1'b0;
        end else begin
            case (state)
                2'd0: begin // IDLE
                    vm_ik_enable    <= 1'b0;
                    vm_vns_override <= 1'b0;
                    if (data_valid) begin
                        // Enforce Tier constraints structurally
                        if (safety_tier == 2'b11 || safety_tier == 2'b10) begin
                            // Freeze. Do not even evaluate policy on T2/T3.
                            state <= 2'd0; 
                        end else begin
                            pc    <= 6'd0;
                            state <= 2'd1; // EXEC
                        end
                    end
                end
                
                2'd1: begin // EXEC
                    case (opcode)
                        OPCODE_NOP: begin
                            pc <= pc + 1'b1;
                        end
                        
                        OPCODE_CMP_MU: begin
                            cmp_flag_lt <= (mu_out < imm);
                            cmp_flag_gt <= (mu_out > imm);
                            pc <= pc + 1'b1;
                        end
                        
                        OPCODE_JLT: begin
                            if (cmp_flag_lt) pc <= jmp_addr;
                            else pc <= pc + 1'b1;
                        end
                        
                        OPCODE_JGT: begin
                            if (cmp_flag_gt) pc <= jmp_addr;
                            else pc <= pc + 1'b1;
                        end
                        
                        OPCODE_SET_X: begin
                            target_x <= imm;
                            pc <= pc + 1'b1;
                        end
                        
                        OPCODE_SET_Y: begin
                            target_y <= imm;
                            pc <= pc + 1'b1;
                        end
                        
                        OPCODE_VNS_TRIG: begin
                            vm_vns_override <= 1'b1;
                            pc <= pc + 1'b1;
                        end
                        
                        OPCODE_HALT: begin
                            vm_ik_enable <= 1'b1; // Strobe downstream IK solver
                            state        <= 2'd2; // DONE
                        end
                        
                        default: pc <= pc + 1'b1;
                    endcase
                end
                
                2'd2: begin // DONE
                    vm_ik_enable <= 1'b0;
                    state        <= 2'd0; // Return to IDLE
                end
                
                default: state <= 2'd0;
            endcase
        end
    end

endmodule
