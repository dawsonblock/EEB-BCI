`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v4.0
 * Module: boreal_spi_chain
 * Description: 100MHz SPI state machine for ADS1299 ADC daisy chain.
 * v4.0: Proper 2-stage synchronizer + falling-edge detection for DRDY.
 */

module boreal_spi_chain (
    input  wire         clk,
    input  wire         rst_n,
    
    // SPI Interface
    output reg          sclk,
    output reg          cs_n,
    output reg          mosi,
    input  wire         miso,
    input  wire         drdy_n,
    
    // Internal Output Bus
    output reg  [791:0] data_out,
    output reg          data_valid,
    
    // v4.0: Transaction counter for debug
    output reg  [15:0]  txn_count
);

    // ── DRDY Synchronizer + Edge Detector ───────────────────
    // drdy_n crosses from the ADC clock domain. We must synchronize
    // it and then detect the falling edge to avoid re-triggering.
    reg drdy_sync1, drdy_sync2, drdy_prev;
    wire drdy_falling_edge = drdy_prev & ~drdy_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drdy_sync1 <= 1'b1;
            drdy_sync2 <= 1'b1;
            drdy_prev  <= 1'b1;
        end else begin
            drdy_sync1 <= drdy_n;
            drdy_sync2 <= drdy_sync1;
            drdy_prev  <= drdy_sync2;
        end
    end

    // ── State Machine ───────────────────────────────────────
    localparam IDLE     = 2'b00;
    localparam SETUP    = 2'b01;
    localparam SHIFT_IN = 2'b10;
    localparam DONE     = 2'b11;

    reg [1:0]   state;
    reg [9:0]   bit_counter;
    reg [791:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            sclk        <= 1'b0;
            cs_n        <= 1'b1;
            mosi        <= 1'b0;
            data_out    <= 792'd0;
            data_valid  <= 1'b0;
            bit_counter <= 10'd0;
            shift_reg   <= 792'd0;
            txn_count   <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    cs_n       <= 1'b1;
                    data_valid <= 1'b0;
                    sclk       <= 1'b0;
                    
                    // Trigger ONLY on synchronized falling edge
                    if (drdy_falling_edge) begin
                        state <= SETUP;
                    end
                end
                
                SETUP: begin
                    cs_n        <= 1'b0;       // Assert chip select
                    bit_counter <= 10'd792;    // Load payload size
                    state       <= SHIFT_IN;
                end
                
                SHIFT_IN: begin
                    sclk <= ~sclk; // 50MHz SCLK from 100MHz clock
                    
                    if (!sclk) begin
                        // Sample MISO on rising edge
                        shift_reg <= {shift_reg[790:0], miso};
                    end else begin
                        // Advance counter on falling edge
                        if (bit_counter == 10'd1) begin
                            state <= DONE;
                        end else begin
                            bit_counter <= bit_counter - 1'b1;
                        end
                    end
                end
                
                DONE: begin
                    cs_n       <= 1'b1;
                    data_out   <= shift_reg;
                    data_valid <= 1'b1;
                    txn_count  <= txn_count + 1'b1;
                    state      <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
