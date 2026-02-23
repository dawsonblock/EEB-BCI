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
    // 2.5) System Safety Backbone (v5.0)
    // ============================================================
    wire system_safe;
    wire local_rst_n;

    assign system_safe = !ad_guard_active && !safety_active && !wdt_fault && bite_switch_n;
    
    // Watchdog fault triggers a full downstream initialization reset
    assign local_rst_n = rst_n & ~wdt_reset;


    // ============================================================
    // 3) Biopotential Ingestion (SPI Chain + FIFO, edge-detected DRDY)
    // ============================================================
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

    // ============================================================
    // 2) Active Inference Core
    // ============================================================
    boreal_apex_core apex_core_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .bite_switch_n(bite_switch_n),
        .data_valid(spi_data_valid),
        .raw_eeg_in(spi_data_payload[23:0]),
        .hrv_metric(hrv_metric),
        .w_matrix(w_dout),
        .w_addr(w_addr),
        .mu_out(mu_out),
        .theta_1(theta_1),
        .theta_2(theta_2),
        .current_epsilon(current_epsilon),
        .current_mu(current_mu),
        .trigger_reward(trigger_reward),
        .ad_guard_active(ad_guard_active)
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
        .enable_learning(spi_data_valid),
        .epsilon(current_epsilon),
        .mu(current_mu),
        .w_old(w_dout),
        .we_b(w_we),
        .w_new(w_din_learn)
    );

    // ============================================================
    // 5) VNS Reward Controller (v4.0: configurable intensity)
    // ============================================================
    boreal_vns_control vns_control_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .trigger_in(trigger_reward),
        .intensity(vns_intensity),
        .ad_guard_active(ad_guard_active),
        .t_wave_inhibit(t_wave_inhibit),
        .stim_out(stim_out),
        .safety_active(safety_active)
    );

    // ============================================================
    // 6) PWM Generators
    // ============================================================
    // Mux PWM output based on global safety interlock
    wire [15:0] pwm_safe_in_1 = system_safe ? theta_1 : 16'd0;
    wire [15:0] pwm_safe_in_2 = system_safe ? theta_2 : 16'd0;

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
    // 8) Debug Status Registers (v4.0)
    // ============================================================
    boreal_status_regs status_regs_inst (
        .clk(clk),
        .rst_n(local_rst_n),
        .system_safe(system_safe),
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
