`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v2.5
 * Module: boreal_pwm_gen
 * Description: 12-bit high-resolution PWM generator for robotic or external articulation commands.
 * Runs on 100MHz clock. Provides output mapping for inverse kinematics actuation.
 */

module boreal_pwm_gen (
    input  wire        clk,        // 100MHz clock
    input  wire        rst_n,      // Active-low reset
    input  wire [11:0] duty_cycle, // 12-bit duty cycle (0-4095)
    output reg         pwm_out     // PWM standard output signal
);

    reg [11:0] counter;
    reg [11:0] latched_duty; // v4.1: Synchronous stable baseline

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter      <= 12'd0;
            latched_duty <= 12'd0;
            pwm_out      <= 1'b0;
        end else begin
            counter <= counter + 1'b1; // Free running 0-4095 counter
            
            // Glitch prevention: Only latch new cycle values when counter wraps
            if (counter == 12'd0) begin
                latched_duty <= duty_cycle;
            end
            
            if (counter < latched_duty) begin
                pwm_out <= 1'b1;
            end else begin
                pwm_out <= 1'b0;
            end
        end
    end

endmodule
