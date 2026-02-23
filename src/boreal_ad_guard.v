`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v6.0 (Layer 3)
 * Module: boreal_ad_guard
 * Description: Mathematical detection of Autonomic Dysreflexia.
 *
 * Computes a normalized correlation metric between Heart Rate
 * Variability (HRV) and Inference Error (epsilon) over a rolling
 * 1024-sample diagnostic window.
 *
 * Uses the Cauchy-Schwarz inequality to avoid square root:
 *   |R| > Threshold  ⟺  Cov² > Threshold² · Var(eps) · Var(hrv)
 *
 * Variance accumulators use true squared deviations from EMA means.
 * DSP pipeline registers are inserted for timing closure on Artix-7.
 *
 * Asserts ad_guard_active when strong positive correlation between
 * inference error and HRV volatility indicates systemic distress.
 */

module boreal_ad_guard (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 data_valid,   // Trigger on new inference cycle
    input  wire signed [15:0]   epsilon,      // Current inference error (Prediction Error)
    input  wire signed [15:0]   hrv_metric,   // Extracted physiological HRV reading
    
    output reg                  ad_guard_active // Interlock flag sent to VNS controller
);

    // ============================================================
    // Configuration
    // ============================================================
    
    // Correlation threshold squared (R²).
    // For R > ~0.6 detection: R² ≈ 0.36, in Q30 ≈ 32'h1700_0000
    // For R > ~0.5 detection: R² ≈ 0.25, in Q30 ≈ 32'h1000_0000
    // Tunable per deployment based on acceptable false-positive rate.
    localparam [31:0] R_SQUARED_THRESH = 32'h1700_0000; // ~0.36 in Q30

    // ============================================================
    // Accumulators
    // ============================================================
    
    // Covariance accumulator: Σ(Δε · Δhrv)
    reg signed [31:0] covar_sum;
    
    // True variance accumulators: Σ(Δε²) and Σ(Δhrv²)
    reg signed [31:0] var_eps_sum;
    reg signed [31:0] var_hrv_sum;
    
    // Cycle window control
    reg [9:0] samples_collected;
    
    // DSP pipeline registers
    reg signed [31:0] prod_covar;     // Δε · Δhrv (1-cycle latency)
    reg signed [31:0] prod_var_eps;   // Δε² (1-cycle latency)
    reg signed [31:0] prod_var_hrv;   // Δhrv² (1-cycle latency)
    
    reg enable_guard;

    // Online Exponential Mean Estimators (EMA, α ≈ 1/256)
    reg signed [15:0] mean_eps;
    reg signed [15:0] mean_hrv;

    // Deviation registers (computed from EMA-tracked means)
    reg signed [15:0] delta_eps;
    reg signed [15:0] delta_hrv;
    
    // Evaluation pipeline registers (Cauchy-Schwarz comparison)
    // covar_sum² vs R² · var_eps_sum · var_hrv_sum
    reg signed [63:0] lhs_cov_sq;       // covar_sum * covar_sum
    reg signed [63:0] rhs_var_product;  // var_eps_sum * var_hrv_sum
    reg signed [63:0] rhs_scaled;       // (var_eps * var_hrv) >> 30 * R²

    // ============================================================
    // Main Pipeline
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            covar_sum         <= 32'd0;
            var_eps_sum       <= 32'd0;
            var_hrv_sum       <= 32'd0;
            samples_collected <= 10'd0;
            ad_guard_active   <= 1'b0;
            prod_covar        <= 32'd0;
            prod_var_eps      <= 32'd0;
            prod_var_hrv      <= 32'd0;
            enable_guard      <= 1'b0;
            mean_eps          <= 16'd0;
            mean_hrv          <= 16'd0;
            delta_eps         <= 16'd0;
            delta_hrv         <= 16'd0;
            lhs_cov_sq        <= 64'd0;
            rhs_var_product   <= 64'd0;
            rhs_scaled        <= 64'd0;
        end else if (data_valid) begin
        
            // ── Stage 1: Update Dynamic Means (EMA, α ≈ 1/256) ──
            if (samples_collected == 10'd0 && !enable_guard) begin
                // Fast-track initialization: seed means with first sample
                mean_eps <= epsilon;
                mean_hrv <= hrv_metric;
                enable_guard <= 1'b1;
            end else if (enable_guard) begin
                mean_eps <= mean_eps + ((epsilon    - mean_eps) >>> 8);
                mean_hrv <= mean_hrv + ((hrv_metric - mean_hrv) >>> 8);
            end
            
            // ── Stage 2: Compute deviations from tracked means ──
            delta_eps <= epsilon    - mean_eps;
            delta_hrv <= hrv_metric - mean_hrv;
            
            // ── Stage 3: DSP Pipeline — register all products ──
            prod_covar   <= delta_eps * delta_hrv;   // Cross-product
            prod_var_eps <= delta_eps * delta_eps;    // Squared deviation (ε)
            prod_var_hrv <= delta_hrv * delta_hrv;    // Squared deviation (HRV)
            
            // ── Stage 4: Accumulate (uses registered products, 1-sample lag) ──
            covar_sum   <= covar_sum   + prod_covar;
            var_eps_sum <= var_eps_sum  + prod_var_eps;
            var_hrv_sum <= var_hrv_sum  + prod_var_hrv;
            
            samples_collected <= samples_collected + 1'b1;
            
            // ── Stage 5: Window Evaluation (every 1024 samples) ──
            if (samples_collected == 10'd1023) begin
                
                // Cauchy-Schwarz normalization (avoids sqrt):
                //   Cov² > R² · Var(ε) · Var(HRV)
                //
                // LHS: covar_sum * covar_sum
                // RHS: R_SQUARED_THRESH * (var_eps_sum * var_hrv_sum) >> 30
                //
                // This is computed combinatorially here for evaluation.
                // The 1-cycle result is acceptable since it only fires once
                // every 1024 samples.
                
                lhs_cov_sq      <= covar_sum * covar_sum;
                rhs_var_product <= var_eps_sum * var_hrv_sum;
                
                // Decision: positive covariance AND normalized magnitude exceeds R threshold
                // Uses previous window's evaluation pipeline results (1-window lag on first window)
                if (covar_sum > 0 && lhs_cov_sq > rhs_scaled) begin
                    ad_guard_active <= 1'b1;
                end else begin
                    ad_guard_active <= 1'b0;
                end
                
                // Reset rolling window
                covar_sum         <= 32'd0;
                var_eps_sum       <= 32'd0;
                var_hrv_sum       <= 32'd0;
                samples_collected <= 10'd0;
            end
            
            // ── Continuous: Scale RHS for next evaluation ──
            // Pipelined: rhs_scaled = R² * (var_eps * var_hrv) (Q30 scaling)
            rhs_scaled <= (rhs_var_product * R_SQUARED_THRESH) >>> 30;
            
        end
    end

endmodule
