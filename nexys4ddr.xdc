# This file is specific for the Nexys 4 DDR board.
# See page 7 of the hardware schematic diagram at:
# https://digilent.com/reference/_media/reference/programmable-logic/nexys-4-ddr/nexys-4-ddr_sch.pdf

# Pin assignment
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk_i }];            # CLK100MHZ
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rstn_i }];           # CPU_RESETN

set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports { vga_red_o[0] }];     # VGA_R0
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports { vga_red_o[1] }];     # VGA_R1
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports { vga_red_o[2] }];     # VGA_R2
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports { vga_red_o[3] }];     # VGA_R3
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports { vga_green_o[0] }];   # VGA_G0
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports { vga_green_o[1] }];   # VGA_G1
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports { vga_green_o[2] }];   # VGA_G2
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports { vga_green_o[3] }];   # VGA_G3
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue_o[0] }];    # VGA_B0
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue_o[1] }];    # VGA_B1
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue_o[2] }];    # VGA_B2
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports { vga_blue_o[3] }];    # VGA_B3
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { vga_hs_o }];         # VGA_HS
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { vga_vs_o }];         # VGA_VS

set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { sw_i[0] }];          # SW0
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { sw_i[1] }];          # SW1
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports { sw_i[2] }];          # SW2
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports { sw_i[3] }];          # SW3

set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { btn_i[0] }];         # BTND
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { btn_i[1] }];         # BTNU
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { btn_i[2] }];         # BTNR
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports { btn_i[3] }];         # BTNL
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { btn_i[4] }];         # BTNC

# Clock definition
create_clock -name sys_clk -period 10.00 [get_ports {clk_i}];                          # 100 MHz

# The statistics are moved from the MAIN clock domain to the VGA clock domain,
# and the commands and the start of each frame from the VGA clock domain to
# the MAIN clock domain, each with a toggle signal, which is synchronized, see
# cdc_data.vhd. These are the only paths between the two clocks (the board
# memory is a block RAM with a port in each clock domain). Their delay only
# has to be shorter than the synchronizer (two clock cycles of the
# destination), so the relation between the two clocks is ignored.
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins i_clk_rst/i_mmcm_adv/CLKOUT0]] -to [get_clocks -of_objects [get_pins i_clk_rst/i_mmcm_adv/CLKOUT1]] 8.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins i_clk_rst/i_mmcm_adv/CLKOUT1]] -to [get_clocks -of_objects [get_pins i_clk_rst/i_mmcm_adv/CLKOUT0]] 8.000

# The inputs are asynchronous to the clocks of the design: they are
# synchronized with two registers (the reset in clk_rst.vhd, and the buttons
# and switches in buttons.vhd). So they have no input delay, and the paths
# from them are not timed.
set_false_path -from [get_ports {rstn_i btn_i[*] sw_i[*]}]

# Configuration Bank Voltage Select
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
