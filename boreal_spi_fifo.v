`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0
 * Module: boreal_spi_fifo
 * Description: Asynchronous Dual-Clock FIFO for safe clock domain crossing.
 * Safely buffers incoming 792-bit payloads from the 50MHz SPI ingestion state machine
 * into the 100MHz Active Inference logic domain.
 */

module boreal_spi_fifo #(
    parameter DATA_WIDTH = 792,
    parameter ADDR_WIDTH = 4     // 16 entries deep
)(
    // Write Domain (SPI Clock 50MHz)
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,
    
    // Read Domain (System Clock 100MHz)
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  empty
);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];
    
    // Pointers (Binary for memory addressing, Gray for cross-domain)
    reg [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    
    // Synchronizer registers
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // Output assignment
    assign dout  = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    assign full  = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    // ----------------------------------------------------
    // Write Domain Logic
    // ----------------------------------------------------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
            wr_ptr_bin  <= wr_ptr_bin + 1;
            // Binary to Gray conversion
            wr_ptr_gray <= (wr_ptr_bin + 1) ^ ((wr_ptr_bin + 1) >> 1);
        end
    end

    // Synchronize Read Pointer to Write Domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // ----------------------------------------------------
    // Read Domain Logic
    // ----------------------------------------------------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr_bin  <= rd_ptr_bin + 1;
            // Binary to Gray conversion
            rd_ptr_gray <= (rd_ptr_bin + 1) ^ ((rd_ptr_bin + 1) >> 1);
        end
    end

    // Synchronize Write Pointer to Read Domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

endmodule
