# Boreal Neuro-Core v4.0
# Physical Constraints File (XDC)
# Target Module: boreal_top
# Target Architecture: Xilinx Artix-7

# -------------------------------------------------------------
# Timing & Clocks
# -------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

set_property PACKAGE_PIN U18 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# -------------------------------------------------------------
# Bite Switch (Safety Interrupt)
# -------------------------------------------------------------
set_property PACKAGE_PIN T18 [get_ports bite_switch_n]
set_property IOSTANDARD LVCMOS33 [get_ports bite_switch_n]
set_property PULLUP true [get_ports bite_switch_n]

# -------------------------------------------------------------
# ADS1299 SPI Interface
# -------------------------------------------------------------
set_property PACKAGE_PIN A14 [get_ports sclk]
set_property IOSTANDARD LVCMOS33 [get_ports sclk]

set_property PACKAGE_PIN A15 [get_ports cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports cs_n]

set_property PACKAGE_PIN B15 [get_ports mosi]
set_property IOSTANDARD LVCMOS33 [get_ports mosi]

set_property PACKAGE_PIN B16 [get_ports miso]
set_property IOSTANDARD LVCMOS33 [get_ports miso]

set_property PACKAGE_PIN C15 [get_ports drdy_n]
set_property IOSTANDARD LVCMOS33 [get_ports drdy_n]

# -------------------------------------------------------------
# tVNS Stimulation Output
# -------------------------------------------------------------
set_property PACKAGE_PIN J1 [get_ports stim_out]
set_property IOSTANDARD LVCMOS33 [get_ports stim_out]

# -------------------------------------------------------------
# PWM Robotic Articulation
# -------------------------------------------------------------
set_property PACKAGE_PIN K2 [get_ports pwm_out_1]
set_property IOSTANDARD LVCMOS33 [get_ports pwm_out_1]

set_property PACKAGE_PIN L1 [get_ports pwm_out_2]
set_property IOSTANDARD LVCMOS33 [get_ports pwm_out_2]

# -------------------------------------------------------------
# v4.0: Debug LEDs
# -------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports led_ad_guard]
set_property IOSTANDARD LVCMOS33 [get_ports led_ad_guard]

set_property PACKAGE_PIN E19 [get_ports led_safety]
set_property IOSTANDARD LVCMOS33 [get_ports led_safety]

set_property PACKAGE_PIN U19 [get_ports led_wdt_fault]
set_property IOSTANDARD LVCMOS33 [get_ports led_wdt_fault]

# -------------------------------------------------------------
# v4.0: External T-Wave Inhibit
# -------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports t_wave_inhibit]
set_property IOSTANDARD LVCMOS33 [get_ports t_wave_inhibit]

# -------------------------------------------------------------
# Global Fabric Config
# -------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
