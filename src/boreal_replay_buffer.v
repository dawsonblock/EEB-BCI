`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v6.0 (Layer 3 Expansion)
 * Module: boreal_replay_buffer
 * Description: 1024-entry deep circular ledger storing neural telemetry.
 * Maps to a single RAMB36E1 Block RAM on Artix-7.
 * Records: {mu_t [15:0], epsilon [15:0], hrv_metric [15:0]} = 48 bits per entry.
 */

module boreal_replay_buffer (
    input  wire        clk,
    input  wire        rst_n,
    
    // Write Interface (From Apex/AD Guard)
    input  wire        data_valid,
    input  wire signed [15:0] mu_t,
    input  wire signed [15:0] epsilon,
    input  wire signed [15:0] hrv_metric,
    
    // Read Interface (Host / SPI extraction)
    input  wire [9:0]  read_addr,
    output reg  [47:0] read_data
);

    // 1024 entries x 48 bits
    // This utilizes exactly 1.33 x RAMB36E1 or 2.66 x RAMB18E1 slices natively
    (* ram_style = "block" *)
    reg [47:0] bram [0:1023];
    reg [9:0]  write_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 10'd0;
        end else begin
            if (data_valid) begin
                write_ptr <= write_ptr + 1'b1; // Auto-wrapping circular buffer
            end
        end
    end

    // RAM Inference Block (Strictly Synchronous, No Resets)
    always @(posedge clk) begin
        if (data_valid) begin
            bram[write_ptr] <= {mu_t, epsilon, hrv_metric};
        end
        // Read Port (1 cycle latency standard BRAM)
        read_data <= bram[read_addr];
    end

endmodule
