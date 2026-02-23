`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v2.5
 * Module: boreal_memory
 * Description: Dual-Port Block RAM (BRAM) for storing synaptic weight matrices.
 * Enables simultaneous read (inference) and write (Hebbian plasticity updates).
 */

module boreal_memory #(
    parameter ADDR_WIDTH = 10,  // 1024 addresses default
    parameter DATA_WIDTH = 16   // 16-bit fixed point weights
)(
    input  wire                  clk,
    
    // Port A (Read-only for Inference / Initial Weight Fetch)
    input  wire [ADDR_WIDTH-1:0] addr_a,
    output reg  [DATA_WIDTH-1:0] dout_a,
    
    // Port B (Write-only for Hebbian Plasticity Updates)
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] din_b
);

    // Infer Block RAM in synthesis
    reg [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1];

    // Initialization (optional, could load fixed weights via $readmemh)
    integer i;
    initial begin
        for (i = 0; i < (2**ADDR_WIDTH); i = i + 1) begin
            ram[i] = {DATA_WIDTH{1'b0}}; 
        end
    end

    // Port A: Synchronous Read with Secondary Pipeline Register
    // Ensures Xilinx synthesis infers dedicated Block RAM with optimal output registers
    reg [DATA_WIDTH-1:0] dout_a_pipe;
    
    always @(posedge clk) begin
        dout_a_pipe <= ram[addr_a];
        dout_a      <= dout_a_pipe; // Added one cycle of read latency
    end

    // Port B: Synchronous Write
    always @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= din_b;
        end
    end

endmodule
