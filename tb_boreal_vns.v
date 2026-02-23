`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0 Testbench
 * Tests the VNS control duty cycles, T-wave inhibition, and 
 * the 25Hz hardware burst pulse trains.
 */

module tb_boreal_vns;

    reg clk;
    reg rst_n;
    reg trigger_in;
    reg [7:0] intensity;
    reg ad_guard_active;
    reg t_wave_inhibit;

    wire stim_out;
    wire safety_active;

    // Instantiate UUT
    boreal_vns_control uut (
        .clk(clk),
        .rst_n(rst_n),
        .trigger_in(trigger_in),
        .intensity(intensity),
        .ad_guard_active(ad_guard_active),
        .t_wave_inhibit(t_wave_inhibit),
        .stim_out(stim_out),
        .safety_active(safety_active)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz 
    end

    initial begin
        $dumpfile("boreal_vns_waves.vcd");
        $dumpvars(0, tb_boreal_vns);

        rst_n = 0;
        trigger_in = 0;
        intensity = 8'd200; // 200us pulse
        ad_guard_active = 0;
        t_wave_inhibit = 0;
        
        #100;
        rst_n = 1;

        // Fire a standard reward match
        #20;
        trigger_in = 1;
        #10;
        trigger_in = 0;

        // Fast forward 50ms to see the first pulse complete
        #50_000;

        // Induce T-wave cardiac inhibition
        t_wave_inhibit = 1;
        #1_000_000;
        t_wave_inhibit = 0;
        
        #10_000;
        
        $finish; // End quick diagnostic sim
    end

endmodule
