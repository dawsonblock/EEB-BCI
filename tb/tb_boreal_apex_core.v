`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v3.0 Testbench
 * Tests the fundamental gradient updates, IIR filtering, and 
 * newly integrated IK / AD-Guard modules in the Apex core.
 */

module tb_boreal_apex_core;

    reg clk;
    reg rst_n;
    reg bite_switch_n;
    reg data_valid;
    reg signed [23:0] raw_eeg_in;
    reg signed [15:0] hrv_metric;
    reg signed [15:0] w_matrix;

    wire [9:0] w_addr;
    wire signed [15:0] mu_out;
    wire signed [15:0] theta_1;
    wire signed [15:0] theta_2;
    wire signed [15:0] current_epsilon;
    wire signed [15:0] current_mu;
    wire trigger_reward;
    wire ad_guard_active;

    // Instantiate Unit Under Test (UUT)
    boreal_apex_core uut (
        .clk(clk),
        .rst_n(rst_n),
        .bite_switch_n(bite_switch_n),
        .data_valid(data_valid),
        .raw_eeg_in(raw_eeg_in),
        .hrv_metric(hrv_metric),
        .w_matrix(w_matrix),
        .w_addr(w_addr),
        .mu_out(mu_out),
        .current_epsilon(current_epsilon),
        .current_mu(current_mu),
        .trigger_reward(trigger_reward),
        .ad_guard_active(ad_guard_active)
    );

    // 100MHz clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Simulation Sequence
    initial begin
        $dumpfile("boreal_apex_core_waves.vcd");
        $dumpvars(0, tb_boreal_apex_core);

        // Initialize Inputs
        rst_n = 0;
        bite_switch_n = 1;
        data_valid = 0;
        raw_eeg_in = 0;
        hrv_metric = 16'd120; // Normal HRV
        w_matrix = 16'h0100;

        #100;
        rst_n = 1;
        
        // Simulating incoming EEG signal
        #20;
        
        // Push a pulse of data (Simulating SPI completion)
        raw_eeg_in = 24'h00_8000;
        data_valid = 1;
        #10;
        data_valid = 0;
        
        #50;
        
        // Push next payload
        raw_eeg_in = 24'h00_8100;
        data_valid = 1;
        #10;
        data_valid = 0;
        
        #50;
        
        // Trigger Bite Switch emergency stop
        bite_switch_n = 0;
        #20;
        bite_switch_n = 1;
        
        // Push more data to rebuild manifold
        raw_eeg_in = 24'h00_8200;
        data_valid = 1;
        #10;
        data_valid = 0;

        #200;
        
        // Simulate Autonomic Dysreflexia (Massive Error + Massive HRV variance)
        hrv_metric = 16'd400; // Skyrocketing metric
        repeat (1024) begin   // Run through the AD window
            raw_eeg_in = 24'h7F_FFFF; // Extreme error value
            data_valid = 1;
            #10;
            data_valid = 0;
            #10;
        end

        #100;
        $finish;
    end

endmodule
