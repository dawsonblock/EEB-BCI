`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v6.0 (Layer 3 Expansion)
 * Module: boreal_safety_escalation
 * Description: Replaces the flat binary "system_safe" interlock with a
 * 4-Tier structured behavioral envelope.
 * 
 * TIER 0 (2'b00): Normal Operation.
 * TIER 1 (2'b01): Reduced Speed - Halves PWM duty cycle (Moderate Error).
 * TIER 2 (2'b10): Motion Freeze - PWM duty = 0, VNS active (Distress).
 * TIER 3 (2'b11): Halt - PWM = 0, VNS disabled, Learning frozen (Fault).
 */

module boreal_safety_escalation (
    input  wire        clk,
    input  wire        rst_n,
    
    // Status Flags (Triggers)
    input  wire        ad_guard_active, // Ext AD-Guard distress
    input  wire        safety_active,   // Internal VNS timer guard
    input  wire        wdt_fault,       // Watchdog timeout
    input  wire        bite_switch_n,   // Physical killswitch (active low)
    input  wire        high_error_flag, // High sustained epsilon without distress
    
    // Output Tiers and Constraints
    output reg  [1:0]  safety_tier,
    output reg         pwm_inhibit_motion,
    output reg         pwm_half_speed,
    output reg         vns_inhibit_therapy,
    output reg         freeze_learning
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            safety_tier         <= 2'b11; // Default to highest restriction on reset
            pwm_inhibit_motion  <= 1'b1;
            pwm_half_speed      <= 1'b0;
            vns_inhibit_therapy <= 1'b1;
            freeze_learning     <= 1'b1;
        end else begin
            // Evaluate from highest severity downward (Tier 3 -> Tier 0)

            // TIER 3: Critical Fault (Watchdog lapse or physical killswitch)
            if (wdt_fault || !bite_switch_n) begin
                safety_tier         <= 2'b11;
                pwm_inhibit_motion  <= 1'b1;
                pwm_half_speed      <= 1'b0;
                vns_inhibit_therapy <= 1'b1;
                freeze_learning     <= 1'b1;

            // TIER 2: Biological Distress (AD Guard triggered or VNS internal guard)
            end else if (ad_guard_active || safety_active) begin
                safety_tier         <= 2'b10;
                pwm_inhibit_motion  <= 1'b1;
                pwm_half_speed      <= 1'b0;
                vns_inhibit_therapy <= 1'b0; // Allowed to attempt therapeutic VNS
                freeze_learning     <= 1'b1; // Stop adapting during distress anomalies

            // TIER 1: Warning / Escalated Error (No distress, but high prediction gap)
            end else if (high_error_flag) begin
                safety_tier         <= 2'b01;
                pwm_inhibit_motion  <= 1'b0;
                pwm_half_speed      <= 1'b1; // Cut robotic joint speeds
                vns_inhibit_therapy <= 1'b0;
                freeze_learning     <= 1'b0;

            // TIER 0: Nominal Operation
            end else begin
                safety_tier         <= 2'b00;
                pwm_inhibit_motion  <= 1'b0;
                pwm_half_speed      <= 1'b0;
                vns_inhibit_therapy <= 1'b0;
                freeze_learning     <= 1'b0;
            end
        end
    end

endmodule
