`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v4.0
 * Module: boreal_status_regs
 * Description: Read-only debug register file exposing internal system state
 * for JTAG, logic analyzer, or external MCU observation.
 *
 * Address Map (active on read strobe):
 *   0x0: mu_out         (16-bit, current manifold state)
 *   0x1: epsilon        (16-bit, current prediction error)
 *   0x2: status_flags   (8-bit: [0]=ad_guard, [1]=safety, [2]=wdt_fault, [3]=bite_sw)
 *   0x3: spi_txn_count  (16-bit, SPI transaction counter)
 *   0x4: theta_1        (16-bit, shoulder angle)
 *   0x5: theta_2        (16-bit, elbow angle)
 */

module boreal_status_regs (
    input  wire        clk,
    input  wire        rst_n,
    
    // Register select
    input  wire [2:0]  addr,
    input  wire        rd_en,
    output reg  [15:0] rd_data,
    
    // System observation inputs
    input  wire signed [15:0] mu_out,
    input  wire signed [15:0] epsilon,
    input  wire signed [15:0] theta_1,
    input  wire signed [15:0] theta_2,
    input  wire        system_safe,     // v5.0: Global safety interlock
    input  wire               ad_guard_active,
    input  wire               safety_active,
    input  wire               wdt_fault,
    input  wire               bite_switch_n,
    input  wire        [15:0] spi_txn_count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data <= 16'd0;
        end else if (rd_en) begin
            case (addr)
                3'd0: rd_data <= mu_out;
                3'd1: rd_data <= epsilon;
                3'd2: rd_data <= {12'd0, ~bite_switch_n, wdt_fault, safety_active, ad_guard_active, system_safe};
                3'd3: rd_data <= spi_txn_count;
                3'd4: rd_data <= theta_1;
                3'd5: rd_data <= theta_2;
                default: rd_data <= 16'hDEAD;
            endcase
        end
    end

endmodule
