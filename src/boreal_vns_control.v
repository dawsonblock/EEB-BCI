`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v2.5
 * Module: boreal_vns_control
 * Description: Drives Transcutaneous Vagus Nerve Stimulation (tVNS) to close the sensory-reward loop.
 * Integrates direct physiological interlocks including the "Leaky Bucket" timer and Cardiac/AD-Guard.
 */

module boreal_vns_control (
    input  wire       clk,             // 100MHz system clock
    input  wire       rst_n,           // Active low reset
    input  wire       trigger_in,      // Event match trigger from Active Inference
    input  wire [7:0] intensity,       // Pulse width scaler 0-255 (microseconds)
    
    // Safety & Physiological Overlays
    input  wire       ad_guard_active, // v5.0: Distress interlock signal
    input  wire       t_wave_inhibit,  // Cardiac guardrail block flag
    
    // Outputs
    output reg        stim_out,        // Physical biphasic current drive signal
    output wire       safety_active    // Interlock state flag
);

    // Constant Parameters
    // 100M cycles = 1 exact second at 100MHz
    localparam MAX_ACTIVE_CYCLES = 32'd100_000_000;
    
    // Pulse sequence defined in specification
    localparam PERIOD_CYCLES = 32'd4_000_000;  // 40ms period = 25Hz frequency
    localparam BURST_MAX     = 8'd15;          // 15 total pulses per reward event

    reg [31:0] global_safety_timer;
    reg [21:0] pulse_timer; // Reduced from 32-bit (4,000,000 max requires only 22 bits)
    reg [7:0]  pulse_count;
    reg        burst_active;

    // The "Leaky Bucket" hardware interlock evaluation
    assign safety_active = (global_safety_timer >= MAX_ACTIVE_CYCLES);

    // ----------------------------------------------------
    // SAFETY: Global Duty Cycle Integrator
    // ----------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_safety_timer <= 32'd0;
        end else begin
            if (stim_out) begin
                // Increment timer when active
                if (global_safety_timer < {32{1'b1}}) // ceiling logic
                    global_safety_timer <= global_safety_timer + 1'b1;
            end else begin
                // Safely decrement down to floor when inactive
                if (global_safety_timer > 32'd0)
                    global_safety_timer <= global_safety_timer - 1'b1;
            end
        end
    end

    // ----------------------------------------------------
    // CONTROL: Biphasic Burst Engine
    // ----------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stim_out     <= 1'b0;
            burst_active <= 1'b0;
            pulse_timer  <= 32'd0;
            pulse_count  <= 8'd0;
        end else begin
            // Reward match logic
            // v5.0: Safety Interlock injected: Prevent burst if AD-Guard detected distress
            if (trigger_in && !safety_active && !burst_active && !ad_guard_active) begin
                burst_active <= 1'b1;
                pulse_count  <= 8'd0;
                pulse_timer  <= 32'd0;
            end

            if (burst_active) begin
                pulse_timer <= pulse_timer + 1'b1;

                // Dynamic Intensity: 1 unit = 1 microsecond. 
                // At 100MHz, 1 microsecond is 100 clock cycles.
                if (pulse_timer < (intensity * 100)) begin
                    
                    // Cardiac Guardrail Implementation: Wholly eliminates risk of 
                    // stimulating during vulnerable T-wave phase.
                    if (!t_wave_inhibit) begin
                        stim_out <= 1'b1;
                    end else begin
                        stim_out <= 1'b0;
                    end

                end else begin
                    stim_out <= 1'b0; // Output goes low after intensity Window
                end

                // Wrap-around logic for next pulse in burst string
                if (pulse_timer >= PERIOD_CYCLES - 1) begin
                    pulse_timer <= 32'd0;
                    pulse_count <= pulse_count + 1'b1;
                    
                    if (pulse_count >= BURST_MAX - 1) begin
                        burst_active <= 1'b0; // End burst
                    end
                end

            end else begin
                stim_out <= 1'b0;
            end
        end
    end

endmodule
