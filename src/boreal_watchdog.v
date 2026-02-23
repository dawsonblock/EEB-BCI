`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v4.0
 * Module: boreal_watchdog
 * Description: Hardware watchdog timer. Asserts a fault flag if no data_valid
 * pulse arrives within a configurable timeout window, indicating the SPI
 * ingestion pipeline or ADC has stalled.
 */

module boreal_watchdog #(
    parameter TIMEOUT_CYCLES = 23'd5_000_000  // 50ms at 100MHz
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        data_valid,   // Kick signal — resets the timer
    
    output reg         wdt_fault,    // Asserted when timeout expires
    output reg         wdt_reset     // Single-cycle pulse to reset downstream logic
);

    reg [22:0] counter;
    reg        fault_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter    <= 23'd0;
            wdt_fault  <= 1'b0;
            wdt_reset  <= 1'b0;
            fault_prev <= 1'b0;
        end else begin
            wdt_reset  <= 1'b0;  // Default: no reset pulse
            fault_prev <= wdt_fault;
            
            if (data_valid) begin
                // Kick: data arrived, reset the watchdog
                counter   <= 23'd0;
                wdt_fault <= 1'b0;
            end else if (counter >= TIMEOUT_CYCLES) begin
                // Timeout expired — assert fault
                wdt_fault <= 1'b1;
                
                // Generate a single-cycle reset pulse on the rising edge of fault
                if (!fault_prev) begin
                    wdt_reset <= 1'b1;
                end
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule
