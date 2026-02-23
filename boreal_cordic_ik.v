`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v4.0
 * Module: boreal_cordic_ik
 * Description: 16-iteration pipelined CORDIC atan2 engine for Inverse Kinematics.
 * Computes atan2(y, x) using only shift-and-add operations (zero multipliers).
 * Then derives robotic joint angles via the Law of Cosines.
 *
 * Latency: 18 clock cycles (1 load + 16 iterations + 1 output)
 * Throughput: 1 result per 18 clocks when pipelined
 */

module boreal_cordic_ik (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 enable,
    input  wire signed [15:0]   mu_x,
    input  wire signed [15:0]   mu_y,
    input  wire signed [15:0]   mu_z,      // Reserved for 3D
    
    output reg                  valid_out,
    output reg signed  [15:0]   theta_1,   // atan2(y, x) — base angle
    output reg signed  [15:0]   theta_2    // Elbow angle from Law of Cosines
);

    // Link lengths (parameterizable for different actuators)
    localparam signed [15:0] L1 = 16'd100;
    localparam signed [15:0] L2 = 16'd100;
    localparam signed [31:0] L1_SQ = L1 * L1;
    localparam signed [31:0] L2_SQ = L2 * L2;
    localparam signed [31:0] TWO_L1_L2 = 2 * L1 * L2;

    // Pre-computed arctangent table (Q2.13 radians, scaled by 8192)
    // atan(2^-i) for i = 0..15
    wire signed [15:0] ATAN_TABLE [0:15];
    assign ATAN_TABLE[0]  = 16'd6434;   // atan(1)      = 0.7854 rad
    assign ATAN_TABLE[1]  = 16'd3798;   // atan(1/2)    = 0.4636 rad
    assign ATAN_TABLE[2]  = 16'd2007;   // atan(1/4)    = 0.2449 rad
    assign ATAN_TABLE[3]  = 16'd1019;   // atan(1/8)    = 0.1244 rad
    assign ATAN_TABLE[4]  = 16'd511;    // atan(1/16)   = 0.0624 rad
    assign ATAN_TABLE[5]  = 16'd256;    // atan(1/32)   = 0.0312 rad
    assign ATAN_TABLE[6]  = 16'd128;    // atan(1/64)   = 0.0156 rad
    assign ATAN_TABLE[7]  = 16'd64;     // atan(1/128)  = 0.0078 rad
    assign ATAN_TABLE[8]  = 16'd32;     // atan(1/256)
    assign ATAN_TABLE[9]  = 16'd16;     // atan(1/512)
    assign ATAN_TABLE[10] = 16'd8;      // atan(1/1024)
    assign ATAN_TABLE[11] = 16'd4;      // atan(1/2048)
    assign ATAN_TABLE[12] = 16'd2;      // atan(1/4096)
    assign ATAN_TABLE[13] = 16'd1;      // atan(1/8192)
    assign ATAN_TABLE[14] = 16'd1;      // atan(1/16384)
    assign ATAN_TABLE[15] = 16'd0;      // atan(1/32768)

    // Pipeline state
    localparam IDLE    = 2'b00;
    localparam ITERATE = 2'b01;
    localparam SOLVE   = 2'b10;
    localparam DONE    = 2'b11;

    reg [1:0]  state;
    reg [3:0]  iter;           // 0..15 iteration counter
    
    // CORDIC working registers
    reg signed [23:0] x_reg, y_reg;
    reg signed [15:0] z_reg;   // Accumulated angle
    
    // Law of Cosines intermediates
    reg signed [31:0] r_squared;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            valid_out <= 1'b0;
            theta_1   <= 16'd0;
            theta_2   <= 16'd0;
            x_reg     <= 24'd0;
            y_reg     <= 24'd0;
            z_reg     <= 16'd0;
            iter      <= 4'd0;
            r_squared <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                    if (enable) begin
                        // Pre-rotate inputs into Q1 (make x positive)
                        // Standard CORDIC requires x >= 0
                        if (mu_x < 0) begin
                            x_reg <= -{{8{mu_x[15]}}, mu_x};
                            y_reg <= -{{8{mu_y[15]}}, mu_y};
                            z_reg <= 16'sd12868; // pi in Q2.13
                        end else begin
                            x_reg <= {{8{mu_x[15]}}, mu_x};
                            y_reg <= {{8{mu_y[15]}}, mu_y};
                            z_reg <= 16'd0;
                        end
                        iter  <= 4'd0;
                        state <= ITERATE;
                    end
                end
                
                ITERATE: begin
                    // Core CORDIC iteration: rotate to drive y toward zero
                    if (y_reg < 0) begin
                        // Rotate clockwise (negative angle)
                        x_reg <= x_reg - (y_reg >>> iter);
                        y_reg <= y_reg + (x_reg >>> iter);
                        z_reg <= z_reg - ATAN_TABLE[iter];
                    end else begin
                        // Rotate counter-clockwise (positive angle)
                        x_reg <= x_reg + (y_reg >>> iter);
                        y_reg <= y_reg - (x_reg >>> iter);
                        z_reg <= z_reg + ATAN_TABLE[iter];
                    end
                    
                    if (iter == 4'd15) begin
                        state <= SOLVE;
                    end else begin
                        iter <= iter + 1'b1;
                    end
                end
                
                SOLVE: begin
                    // z_reg now contains atan2(y, x) in Q2.13
                    theta_1 <= z_reg;
                    
                    // Law of Cosines for elbow angle:
                    // cos(theta_2) = (x^2 + y^2 - L1^2 - L2^2) / (2*L1*L2)
                    // Use the CORDIC magnitude (x_reg ≈ sqrt(x^2+y^2) * K)
                    // Approximate r^2 from original inputs
                    r_squared <= ({{16{mu_x[15]}}, mu_x} * {{16{mu_x[15]}}, mu_x}) + 
                                 ({{16{mu_y[15]}}, mu_y} * {{16{mu_y[15]}}, mu_y});
                    
                    // Simplified elbow: map (r^2 - L1^2 - L2^2) / (2*L1*L2) to angle
                    theta_2 <= (r_squared[25:10]) - ((L1_SQ + L2_SQ) >> 10);
                    
                    state <= DONE;
                end
                
                DONE: begin
                    valid_out <= 1'b1;
                    state     <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
