`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0
 * Module: boreal_ad_guard
 * Description: Mathematical detection of Autonomic Dysreflexia.
 * Calculates real-time covariance-like accumulation between
 * Heart Rate Variability (HRV) and Inference Error (epsilon)
 * using Exponential Moving Average (EMA) means.
 * 
 * Asserts ad_guard_active when strong positive covariance points to systemic stress.
 */

module boreal_ad_guard (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 data_valid,   // Trigger on new inference cycle
    input  wire signed [15:0]   epsilon,      // Current inference error (Prediction Error)
    input  wire signed [15:0]   hrv_metric,   // Extracted physiological HRV reading
    
    output reg                  ad_guard_active // Interlock flag sent to VNS controller
);

    // Configurable thresholds
    localparam signed [31:0] R_THRESHOLD = 32'h00A0_0000; 

    // Covariance / Variance accumulators
    reg signed [31:0] covar_sum;
    reg signed [31:0] var_eps_sum;
    reg signed [31:0] var_hrv_sum;
    
    // Cycle window control
    reg [9:0] samples_collected;
    
    reg signed [31:0] prod_covar;
    reg               enable_guard;

    // v5.0: Online Exponential Mean Estimators
    reg signed [15:0] mean_eps;
    reg signed [15:0] mean_hrv;

    // Registers for deltas (calculated from dynamic means)
    reg signed [15:0] delta_eps;
    reg signed [15:0] delta_hrv;
    
    // ============================================================
    // State machine and Accumulators
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            covar_sum         <= 32'd0;
            var_eps_sum       <= 32'd0;
            var_hrv_sum       <= 32'd0;
            samples_collected <= 10'd0;
            ad_guard_active   <= 1'b0;
            prod_covar        <= 32'd0;
            enable_guard      <= 1'b0; // Initialize enable_guard
            mean_eps          <= 16'd0; // Initialize mean_eps
            mean_hrv          <= 16'd0; // Initialize mean_hrv
            delta_eps         <= 16'd0;
            delta_hrv         <= 16'd0;
        end else if (data_valid) begin
            // 1) Update Dynamic Means (EMA: ~1/256 smoothing factor)
            if (samples_collected == 10'd0 && !enable_guard) begin
                // Fast-track initialization during startup for the first sample
                mean_eps <= epsilon;
                mean_hrv <= hrv_metric;
                enable_guard <= 1'b1; // Enable EMA after first sample
            end else if (enable_guard) begin
                mean_eps <= mean_eps + ((epsilon - mean_eps) >>> 8);
                mean_hrv <= mean_hrv + ((hrv_metric - mean_hrv) >>> 8);
            end
            
            // 2) Compute deltas vs dynamic means
            delta_eps <= epsilon - mean_eps;
            delta_hrv <= hrv_metric - mean_hrv;
            
            // 3. Pipeline Stage: Register the massive multiplier
            prod_covar <= delta_eps * delta_hrv;
            
            // 4. Accumulate Stage: Uses the registered multiplier from the *previous* data_valid cycle
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
