`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v6.0 (Layer 3 Expansion)
 * Module: boreal_eeg_fusion
 * Description: 8-Channel Spatial EEG Filter and DC Blocker array.
 * Replaces the single-channel `raw_eeg_in` with a parallel processing block.
 * Uses individual first-order IIR filters on all 8 channels simultaneously
 * before generating a spatially weighted composite output (`eeg_filtered_out`).
 */

module boreal_eeg_fusion (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        data_valid,
    
    // Flat array of 8x 24-bit AD7999 unipolar AD converter outputs
    input  wire [191:0] raw_eeg_array,
    
    output reg  [23:0]  eeg_filtered_out,
    output reg          fusion_valid
);

    // Filter coefficient (Same as single-channel Apex core α)
    localparam signed [15:0] ALPHA = 16'd102; // Roughly ~0.99 in Q15

    (* ram_style = "logic" *)
    reg signed [23:0] ch_raw      [0:7];
    (* ram_style = "logic" *)
    reg signed [31:0] ch_filtered [0:7];
    
    // DSP Sum Pipeline Registers
    (* ram_style = "logic" *)
    reg signed [31:0] sum_stage_0 [0:3];
    (* ram_style = "logic" *)
    reg signed [31:0] sum_stage_1 [0:1];
    reg signed [31:0] final_sum;
    
    integer i;

    // Spatial weights (Arbitrary static weights. Can be mapped to BRAM or Registers later)
    // Q8 format (e.g., 256 = 1.0)
    wire signed [15:0] s_weight [0:7];
    assign s_weight[0] = 16'd256;  // Primary cortex
    assign s_weight[1] = 16'd128;  // Adjacent A
    assign s_weight[2] = 16'd128;  // Adjacent B
    assign s_weight[3] = 16'd64;
    assign s_weight[4] = 16'd64;
    assign s_weight[5] = 16'd32;
    assign s_weight[6] = 16'd32;
    assign s_weight[7] = 16'd32;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                ch_raw[i]      <= 24'd0;
                ch_filtered[i] <= 32'd0;
            end
            
            for (i = 0; i < 4; i = i + 1) sum_stage_0[i] <= 32'd0;
            for (i = 0; i < 2; i = i + 1) sum_stage_1[i] <= 32'd0;
            
            final_sum        <= 32'd0;
            eeg_filtered_out <= 24'd0;
            fusion_valid     <= 1'b0;
            
        end else if (data_valid) begin
            
            // Step 1: Unpack and DC Block all 8 channels in parallel
            for (i = 0; i < 8; i = i + 1) begin
                // Extract 24-bit slices
                ch_raw[i] <= raw_eeg_array[(i*24) +: 24];
                
                // IIR High-Pass
                ch_filtered[i] <= ch_filtered[i] + (((ch_raw[i] - ch_filtered[i][31:8]) * ALPHA) >>> 15);
            end

            // Step 2: Spatial Weighting & Stage 0 Addition (Pipeline Clock 1)
            // Note: In real synthesis, the multipliers map to DSP48s.
            sum_stage_0[0] <= (ch_filtered[0] * s_weight[0]) + (ch_filtered[1] * s_weight[1]);
            sum_stage_0[1] <= (ch_filtered[2] * s_weight[2]) + (ch_filtered[3] * s_weight[3]);
            sum_stage_0[2] <= (ch_filtered[4] * s_weight[4]) + (ch_filtered[5] * s_weight[5]);
            sum_stage_0[3] <= (ch_filtered[6] * s_weight[6]) + (ch_filtered[7] * s_weight[7]);
            
            // Step 3: Stage 1 Addition (Pipeline Clock 2)
            sum_stage_1[0] <= sum_stage_0[0] + sum_stage_0[1];
            sum_stage_1[1] <= sum_stage_0[2] + sum_stage_0[3];
            
            // Step 4: Final Accumulation (Pipeline Clock 3)
            final_sum <= sum_stage_1[0] + sum_stage_1[1];
            
            // Normalizing out the Q8 scaling from the spatial weights
            eeg_filtered_out <= final_sum[31:8];
            fusion_valid     <= 1'b1;
            
        end else begin
            fusion_valid <= 1'b0;
        end
    end

endmodule
