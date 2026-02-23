`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v2.5
 * Module: boreal_learning
 * Description: Dedicated hardware-level learning block that executes continuous, real-time 
 * synaptic weight updates natively utilizing a localized Hebbian mechanism.
 * Function: W_new = W_old + η(ϵ · μ)
 */

module boreal_learning (
    input  wire                 clk,
    input  wire                 enable_learning,  // Global context flag allowing updates
    input  wire signed [15:0]   epsilon,          // Inference Error / Prediction Error (ϵ)
    input  wire signed [15:0]   mu,               // Internal Manifold State (μ)
    input  wire signed [15:0]   w_old,            // Synaptic weight fetched from BRAM Port A
    
    output wire                 we_b,             // Write Enable flag to BRAM Port B
    output wire signed [15:0]   w_new             // New calculated synaptic weight for BRAM
);

    reg signed [31:0] product;
    wire signed [15:0] delta_w;
    reg               enable_learning_q;

    // 1) 32-Bit Signed Multiplier (Registered for DSP Inference)
    // Multiplies Error (ϵ) by State (μ) cleanly mapping to hardware DSP slices
    always @(posedge clk) begin
        product <= epsilon * mu;
        enable_learning_q <= enable_learning;
    end

    // 2) Fixed-point Scaling (η adjustment)
    // Targeting slice [25:10] effectively shifts right by 10
    assign delta_w = product[25:10];

    // 3) Weight Accumulator with Anti-Wrap-Around Saturation
    // BRAM Write Enable relies on the delayed global learning flag
    assign we_b = enable_learning_q;
    
    // Perform 17-bit intermediate signed addition to detect overflow/underflow
    wire signed [16:0] sum = w_old + delta_w;
    
    // Clamp to 16-bit signed boundaries [-32768, 32767]
    assign w_new = (sum > 17'sd32767)  ? 16'sd32767 :
                   (sum < -17'sd32768) ? -16'sd32768 : 
                   sum[15:0];

endmodule
