`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0
 * Module: boreal_apex_core
 * Description: Primary mathematical hub of the architecture.
 * Implements Active Inference via Gradient Descent, Temporal Predictive Coding
 * for wireless lag cancellation, and IIR DC-Block filtering via fixed-point math.
 * v3.0 Upgrade includes AD-Guard and CORDIC Inverse Kinematics integration.
 */

module boreal_apex_core (
    input  wire                 clk,          // 100MHz system clock
    input  wire                 rst_n,        // Active low reset
    input  wire                 bite_switch_n,// Hardware interrupt (Active Low)
    
    // Intrinsic data path from SPI Ingestion
    input  wire                 data_valid,   
    input  wire signed [23:0]   raw_eeg_in,   // Ingested target channel
    
    // Physiological monitoring inputs
    input  wire signed [15:0]   hrv_metric,   // Monitored Heart Rate Variability for AD-Guard
    
    // Synaptic Weight Interface (BRAM)
    input  wire signed [15:0]   w_matrix,
    output wire [9:0]           w_addr,
    
    // Decoded Outputs
    output wire signed [15:0]   mu_out,       // The "Time Machine" predicted manifold state
    
    // Peripheral routing for Hebbian plasticity and tVNS reward
    output wire signed [15:0]   current_epsilon,
    output wire signed [15:0]   current_mu,
    output wire                 trigger_reward,
    output wire                 ad_guard_active // Interlock to bypass normal VNS mode
);

    // ----------------------------------------------------
    // Hardcoded Biological Constants (System tuning)
    // ----------------------------------------------------
    // Alpha for IIR high-pass (~0.995 in Q8.16 formatted approximation)
    localparam signed [23:0] ALPHA_IIR    = 24'h7F_3333; 
    
    // Inference learning rate (η)
    localparam signed [15:0] ETA_LR       = 16'h00_80;   
    
    // Regularization / Manifold decay prior (λ)
    localparam signed [15:0] LAMBDA_DECAY = 16'h00_08;   
    
    // Lag Compensation / "Lead" factor (k)
    // Scaled specifically to nullify the measured ~30ms EPOC X Bluetooth latency
    localparam signed [15:0] LEAD_K       = 16'h00_20;   

    // ----------------------------------------------------
    // 1) Signal Conditioning: IIR DC-Blocker
    // ----------------------------------------------------
    reg signed [23:0] x_n, x_n_minus_1;
    reg signed [23:0] y_n_minus_1;
    reg signed [23:0] eeg_filtered;

    wire signed [47:0] iir_mult = ALPHA_IIR * y_n_minus_1;
    wire signed [24:0] iir_diff = x_n - x_n_minus_1;
    wire signed [24:0] iir_calc = iir_diff + iir_mult[39:16]; // Right-shift alignment

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_n          <= 24'd0;
            x_n_minus_1  <= 24'd0;
            y_n_minus_1  <= 24'd0;
            eeg_filtered <= 24'd0;
        end else if (data_valid) begin
            x_n_minus_1 <= x_n;
            x_n         <= raw_eeg_in;
            
            // Saturation logic implementation
            if (iir_calc > 24'h7FFFFF) begin
                eeg_filtered <= 24'h7FFFFF;   // Max positive clamp
            end else if (iir_calc < -24'h800000) begin
                eeg_filtered <= -24'h800000;  // Max negative clamp
            end else begin
                eeg_filtered <= iir_calc[23:0];
            end
            
            y_n_minus_1 <= eeg_filtered;
        end
    end

    // ----------------------------------------------------
    // 2) Active Inference Engine (Free Energy gradient descent)
    // ----------------------------------------------------
    reg signed [15:0] mu_t, mu_t_minus_1;
    wire signed [15:0] epsilon;
    wire signed [15:0] sigma_val, sigma_prime;
    
    // Instantiate LUT ROM for non-linear derivations
    reg [31:0] sigmoid_lut [0:1023];
    initial $readmemh("sigmoid_lut.mem", sigmoid_lut); // Make sure the path is correct
    
    // Non-linear derivation index mapping
    wire [9:0] rom_addr = mu_t[15:6]; 
    assign sigma_val   = sigmoid_lut[rom_addr][15:0];
    assign sigma_prime = sigmoid_lut[rom_addr][31:16];

    // Prediction Error: ϵ = y - sigma(W * mu)
    wire signed [31:0] w_mu = w_matrix * mu_t;
    // Map observed and expected down to 16-bit Q space for comparison
    assign epsilon = (eeg_filtered[23:8] - (w_mu[25:10])); 

    // Calculate Manifold Gradient
    wire signed [31:0] err_scaled   = epsilon * sigma_prime;
    wire signed [31:0] decay_scaled = LAMBDA_DECAY * mu_t;
    
    // DSP Pipeline Registers
    reg signed [31:0] err_scaled_reg;
    reg signed [31:0] decay_scaled_reg;

    wire signed [31:0] gradient     = err_scaled_reg[25:10] - decay_scaled_reg[25:10];
    
    // Proper Fractional Scaling (Q15 Right-Shift)
    // Avoids truncating significant bits under high gradients
    wire signed [47:0] pre_delta    = ETA_LR * gradient;
    wire signed [15:0] delta_mu     = pre_delta >>> 15;

    // ----------------------------------------------------
    // 3) Temporal Predictive Coding ("Time Machine")
    // ----------------------------------------------------
    wire signed [15:0] velocity     = mu_t - mu_t_minus_1;
    wire signed [31:0] lag_comp     = LEAD_K * velocity;
    wire signed [15:0] mu_predicted = mu_t + lag_comp[15:0];

    wire signed [16:0] temp_mu      = mu_t + delta_mu;

    // System Update
    // Due to the DSP pipelining added above, the `delta_mu` relies on registered 
    // values from the previous cycle. This behaves natively like a standard stochastic mapping.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mu_t             <= 16'd0;
            mu_t_minus_1     <= 16'd0;
            err_scaled_reg   <= 32'd0;
            decay_scaled_reg <= 32'd0;
        end 
        else if (!bite_switch_n) begin 
            mu_t             <= 16'd0; 
            mu_t_minus_1     <= 16'd0;
            err_scaled_reg   <= 32'd0;
            decay_scaled_reg <= 32'd0;
        end 
        else if (data_valid) begin
            // Register multipliers
            err_scaled_reg   <= err_scaled;
            decay_scaled_reg <= decay_scaled;
            
            // Advance state with 17-bit anti-wrap-around saturation clamping
            mu_t_minus_1 <= mu_t;
            
            if (temp_mu > 17'sd32767) begin
                mu_t <= 16'sd32767;
            end else if (temp_mu < -17'sd32768) begin
                mu_t <= -16'sd32768;
            end else begin
                mu_t <= temp_mu[15:0];
            end
        end
    end

    // ----------------------------------------------------
    // 4) INTEGRATION: Autonomic Dysreflexia Guard
    // ----------------------------------------------------
    boreal_ad_guard ad_guard_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_valid(data_valid),
        .epsilon(epsilon),
        .hrv_metric(hrv_metric),
        .ad_guard_active(ad_guard_active)
    );

    // Signal Routing
    assign mu_out          = mu_predicted; 
    assign current_epsilon = epsilon;
    assign current_mu      = mu_t;
    assign w_addr          = rom_addr;
    
    // Reward Evaluation
    assign trigger_reward  = (epsilon > -16'd100 && epsilon < 16'd100);

endmodule
