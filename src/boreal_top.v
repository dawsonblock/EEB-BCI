`timescale 1ns / 1ps

/*
 * Boreal Neuro-Core v4.0
 * Module: boreal_top
 * Description: System-level top module. Structurally instantiates and wires
 * all sub-modules into a single synthesis entry point for the Artix-7 FPGA.
 *
 * v4.0: Adds watchdog timer, debug status registers, configurable VNS intensity,
 *       and debug LED outputs.
 */

module boreal_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bite_switch_n,

    // ADS1299 SPI Interface
    output wire        sclk,
    output wire        cs_n,
    output wire        mosi,
    input  wire        miso,
    input  wire        drdy_n,

    // Physiological Monitoring
    input  wire signed [15:0] hrv_metric,

    // Configurable VNS (v4.0 — no longer hardcoded)
    input  wire [7:0]  vns_intensity,

    // External cardiac guardrail
    input  wire        t_wave_inhibit,

    // Debug Register Interface (JTAG / external MCU)
    input  wire [2:0]  dbg_addr,
    input  wire        dbg_rd_en,
    output wire [15:0] dbg_rd_data,

    // Outputs
    output wire        stim_out,
    output wire        pwm_out_1,
    output wire        pwm_out_2,

    // Debug LEDs
    output wire        led_ad_guard,
    output wire        led_safety,
    output wire        led_wdt_fault
);

    // ============================================================
    // Internal Wires
    // ============================================================
    wire [791:0] spi_data_payload;
    wire         spi_data_valid;
    wire [15:0]  spi_txn_count;

    wire signed [15:0] w_dout;
    wire        [9:0]  w_addr;
    wire               w_we;
    wire signed [15:0] w_din_learn;

    wire signed [15:0] mu_out;
    wire signed [15:0] theta_1, theta_2;
    wire signed [15:0] current_epsilon;
    wire signed [15:0] current_mu;
    wire               trigger_reward;
    wire               ad_guard_active;
    wire               safety_active;
    wire               wdt_fault;
    wire               wdt_reset;

    // ============================================================
    // 2.5) Structured Safety Escalation (Layer 3)
    // ============================================================
    wire [1:0] safety_tier;
    wire       pwm_inhibit_motion;
    wire       pwm_half_speed;
    wire       vns_inhibit_therapy;
    wire       freeze_learning;
    wire       local_rst_n;

    // High error without distress triggers Tier 1 escalation
    wire high_error_flag = (current_epsilon > 16'sd200_00) ? 1'b1 : 1'b0;

    boreal_safety_escalation safety_mgr (
        .clk(clk),
        .rst_n(rst_n),
        .ad_guard_active(ad_guard_active),
        .safety_active(safety_active),
        .wdt_fault(wdt_fault),
        .bite_switch_n(bite_switch_n),
        .high_error_flag(high_error_flag),
        .safety_tier(safety_tier),
        .pwm_inhibit_motion(pwm_inhibit_motion),
        .pwm_half_speed(pwm_half_speed),
        .vns_inhibit_therapy(vns_inhibit_therapy),
        .freeze_learning(freeze_learning)
    );
    
    // Watchdog fault triggers a full downstream initialization reset
    assign local_rst_n = rst_n & ~wdt_reset;


    // ============================================================
    // 3) Biopotential Ingestion (SPI Chain + FIFO)
    // ============================================================
    
    // Mock expansion for the 8-channel fusion block.
    // In hardware, this SPI payload would be 8x wider (192 bits).
    // For V6.0 MVP, we duplicate the single channel 8 times to satisfy the fusion bus.
    wire [191:0] raw_eeg_array = {8{spi_data_payload[23:0]}};
    wire [23:0]  fused_eeg;
    wire         fused_valid;
    boreal_spi_chain spi_chain_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso),
        .drdy_n(drdy_n),
        .data_out(spi_data_payload),
        .data_valid(spi_data_valid),
        .txn_count(spi_txn_count)
    );
    boreal_spi_fifo spi_fifo_inst (
        .wr_clk(clk),
        .wr_rst_n(local_rst_n),
        .wr_en(spi_data_valid),
        .din(spi_data_payload), // Will hold full array in future expansion
        .rd_clk(clk),
        .rd_rst_n(local_rst_n),
        .rd_en(1'b0),  // Unused in current continuous stream geometry
        .dout(),       // Unused
        .empty(),
        .full()
    );

    // ============================================================
    // 3.5) EEG Spatial Fusion Block (Layer 3)
    // ============================================================
    boreal_eeg_fusion fusion_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .data_valid(spi_data_valid),
        .raw_eeg_array(raw_eeg_array),
        .eeg_filtered_out(fused_eeg),
        .fusion_valid(fused_valid)
    );

    // ============================================================
    // 2) Active Inference Core
    // ============================================================
    
    wire signed [15:0] target_x;
    wire signed [15:0] target_y;
    wire               vm_ik_enable;
    wire               vm_vns_override;
    
    boreal_apex_core apex_core_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .bite_switch_n(bite_switch_n),
        .data_valid(fused_valid),
        .raw_eeg_in(fused_eeg), // Fed from Fusion block, not raw SPI
        .hrv_metric(hrv_metric),
        .w_matrix(w_dout),
        .w_addr(w_addr),
        .mu_out(mu_out),
        .current_epsilon(current_epsilon),
        .current_mu(current_mu),
        .trigger_reward(trigger_reward),
        .ad_guard_active(ad_guard_active)
    );

    // Layer 3: Wire CORDIC IK manually since Apex core integration was decoupled for VM
    boreal_cordic_ik cordic_solver (
        .clk(clk),
        .rst_n(local_rst_n),
        .enable(vm_ik_enable),
        .mu_x(target_x),
        .mu_y(target_y),
        .mu_z(16'd0),
        .valid_out(),
        .theta_1(theta_1),
        .theta_2(theta_2)
    );

    // ============================================================
    // 3.8) Hardware Replay Buffer (Layer 3)
    // ============================================================
    boreal_replay_buffer ledger_bram (
        .clk(clk),
        .rst_n(local_rst_n),
        .data_valid(fused_valid),
        .mu_t(current_mu),
        .epsilon(current_epsilon),
        .hrv_metric(hrv_metric),
        .read_addr(10'd0), // To be attached to SPI host in Layer 4
        .read_data()
    );

    // ============================================================
    // 3.9) Deterministic Decision VM (Layer 3)
    // ============================================================
    boreal_decision_vm policy_vm (
        .clk(clk),
        .rst_n(local_rst_n),
        .safety_tier(safety_tier),
        .data_valid(fused_valid), // Executed after inference provides a new state
        .mu_out(mu_out),
        .target_x(target_x),
        .target_y(target_y),
        .vm_ik_enable(vm_ik_enable),
        .vm_vns_override(vm_vns_override)
    );

    // ============================================================
    // 3) Synaptic Weight Memory
    // ============================================================
    boreal_memory #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(16)
    ) mem_inst (
        .clk(clk),
        .addr_a(w_addr),
        .dout_a(w_dout),
        .we_b(w_we),
        .addr_b(w_addr),
        .din_b(w_din_learn)
    );

    // ============================================================
    // 4) Hebbian Learning Engine
    // ============================================================
    boreal_learning learn_inst (
        .clk(clk),
        .enable_learning(fused_valid && !freeze_learning), // Gated by Safety Tier
        .epsilon(current_epsilon),
        .mu(current_mu),
        .w_old(w_dout),
        .we_b(w_we),
        .w_new(w_din_learn)
    );

    // ============================================================
    // 5) VNS Reward Controller (v4.0: configurable intensity)
    // ============================================================
    wire vns_trig = (trigger_reward || vm_vns_override) && !vns_inhibit_therapy;

    boreal_vns_control vns_control_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .trigger_in(vns_trig),
        .intensity(vns_intensity),
        .ad_guard_active(ad_guard_active),
        .t_wave_inhibit(t_wave_inhibit),
        .stim_out(stim_out),
        .safety_active(safety_active)
    );

    // ============================================================
    // 6) PWM Generators
    // ============================================================
    // Mux PWM output based on Tier escalations
    wire [15:0] pwm_safe_in_1 = pwm_inhibit_motion ? 16'd0 :
                                pwm_half_speed     ? {1'b0, theta_1[15:1]} : theta_1;
                                
    wire [15:0] pwm_safe_in_2 = pwm_inhibit_motion ? 16'd0 :
                                pwm_half_speed     ? {1'b0, theta_2[15:1]} : theta_2;

    boreal_pwm_gen pwm_gen_inst_1 (
        .clk(clk),
        .rst_n(local_rst_n),
        .duty_cycle(pwm_safe_in_1[11:0]), // Downcast base 16-bit to 12-bit PWM
        .pwm_out(pwm_out_1)
    );

    boreal_pwm_gen pwm_gen_inst_2 (
        .clk(clk),
        .rst_n(local_rst_n),
        .duty_cycle(pwm_safe_in_2[11:0]),
        .pwm_out(pwm_out_2)
    );

    // ============================================================
    // 7) Hardware Watchdog Timer (v4.0)
    // ============================================================
    boreal_watchdog #(
        .TIMEOUT_CYCLES(23'd5_000_000) // 50ms at 100MHz
    ) wdt_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .data_valid(spi_data_valid),
        .wdt_fault(wdt_fault),
        .wdt_reset(wdt_reset)
    );

    // ============================================================
    // 8) Debug Status Registers
    // ============================================================
    boreal_status_regs status_regs_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .system_safe(~pwm_inhibit_motion), // Map legacy bit back for backwards compatibility
        .addr(dbg_addr),
        .rd_en(dbg_rd_en),
        .rd_data(dbg_rd_data),
        .mu_out(mu_out),
        .epsilon(current_epsilon),
        .theta_1(theta_1),
        .theta_2(theta_2),
        .ad_guard_active(ad_guard_active),
        .safety_active(safety_active),
        .wdt_fault(wdt_fault),
        .bite_switch_n(bite_switch_n),
        .spi_txn_count(spi_txn_count)
    );

    // ============================================================
    // Debug LED Assignments
    // ============================================================
    assign led_ad_guard  = ad_guard_active;
    assign led_safety    = safety_active;
    assign led_wdt_fault = wdt_fault;

endmodule
