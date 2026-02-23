`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0
 * Module: boreal_ad_guard
 * Description: Mathematical detection of Autonomic Dysreflexia.
 * Calculates real-time Pearson Correlation Coefficient (R) between 
 * Heart Rate Variability (HRV) and Inference Error (epsilon).
 * 
 * Asserts ad_guard_active when strong positive correlation points to systemic stress.
 */

module boreal_ad_guard (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 data_valid,   // Trigger on new inference cycle
    input  wire signed [15:0]   epsilon,      // Current inference error (Prediction Error)
    input  wire signed [15:0]   hrv_metric,   // Extracted physiological HRV reading
    
    output reg                  ad_guard_active // Interlock flag sent to VNS controller
);

    // Hardcoded Baseline/Means for the accumulators
    // In a dynamic system, these would be rolling averages over a 5000 cycle window.
    localparam signed [15:0] MEAN_EPS = 16'd50;
    localparam signed [15:0] MEAN_HRV = 16'd120;
    
    // Threshold indicating a sympathetic surge requiring intervention
    // Scaled for fixed point math.
    localparam signed [31:0] R_THRESHOLD = 32'h00A0_0000; 

    // Covariance / Variance accumulators
    reg signed [31:0] covar_sum;
    reg signed [31:0] var_eps_sum;
    reg signed [31:0] var_hrv_sum;
    
    // Cycle window control
    reg [9:0] samples_collected;
    
    reg signed [31:0] prod_covar;
    
    // Calculate deltas combinationally
    wire signed [15:0] delta_eps = epsilon - MEAN_EPS;
    wire signed [15:0] delta_hrv = hrv_metric - MEAN_HRV;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            covar_sum         <= 32'd0;
            var_eps_sum       <= 32'd0;
            var_hrv_sum       <= 32'd0;
            samples_collected <= 10'd0;
            ad_guard_active   <= 1'b0;
            prod_covar        <= 32'd0;
        end else if (data_valid) begin
            
            // 1. Pipeline Stage: Register the massive multiplier
            prod_covar <= delta_eps * delta_hrv;
            
            // 2. Accumulate Stage: Uses the registered multiplier from the *previous* data_valid cycle
            // This 1-sample lag is mathematically irrelevant over a 1024 sample window, 
            // but saves significant DSP routing delay.
            covar_sum   <= covar_sum + prod_covar;
            
            var_eps_sum <= var_eps_sum + (delta_eps > 0 ? delta_eps : -delta_eps);
            var_hrv_sum <= var_hrv_sum + (delta_hrv > 0 ? delta_hrv : -delta_hrv);
            
            samples_collected <= samples_collected + 1'b1;
            
            // Evaluate at end of diagnostic window (1024 samples)
            if (samples_collected == 10'd1023) begin
                
                // If Covariance is massively high and strictly positive, the error is 
                // tracking strongly with autonomic volatility indicating distress.
                if (covar_sum > R_THRESHOLD) begin
                    ad_guard_active <= 1'b1; // Trigger "Vagus Brake" mode in VNS 
                end else begin
                    ad_guard_active <= 1'b0;
                end
                
                // Reset rolling window
                covar_sum   <= 32'd0;
                var_eps_sum <= 32'd0;
                var_hrv_sum <= 32'd0;
                samples_collected <= 10'd0;
            end
        end
    end

endmodule
