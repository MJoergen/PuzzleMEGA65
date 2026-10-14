-- This is the top level module for the Nexys 4 DDR board. The ports on this
-- entity are mapped directly to pins on the FPGA, see nexys4ddr.xdc.
--
-- It is the same design as mega65.vhd (the design for the MEGA65), see the
-- description there, only the number of engines, the speed of the MAIN
-- clock, and the ports are different:
-- * The XC7A100T is smaller, and of the speed grade -1, so there are fewer
--   engines (C_ENGINES_NEXYS in puzzle_pkg.vhd), and the MAIN clock is
--   slower, see the constants below.
-- * The VGA output has 4 bits per colour (a resistor DAC), so the colours are
--   cut to their upper 4 bits. The picture is 1280x1024 @ 60 Hz, as on the
--   MEGA65. There is no HDMI output.
-- * The commands come from the buttons and the switches, see buttons.vhd.
--
-- The design itself is in core.vhd, as for the MEGA65. This module holds the
-- constants of the Nexys 4 DDR, and instantiates the clock and reset
-- generation, the buttons, and core. The constraints of the clock domain
-- crossings are in nexys4ddr.xdc.

library ieee;
use ieee.std_logic_1164.all;

use work.util_pkg.all;
use work.video_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity nexys4ddr is
   port (
      clk_i       : in  std_logic;                      -- 100 MHz
      rstn_i      : in  std_logic;

      btn_i       : in  std_logic_vector( 4 downto 0);  -- "CLRUD"
      sw_i        : in  std_logic_vector( 3 downto 0);

      vga_hs_o    : out std_logic;
      vga_vs_o    : out std_logic;
      vga_red_o   : out std_logic_vector( 3 downto 0);
      vga_green_o : out std_logic_vector( 3 downto 0);
      vga_blue_o  : out std_logic_vector( 3 downto 0)
   );
end entity nexys4ddr;

architecture structural of nexys4ddr is

   -- The number of engines of each puzzle, see puzzle_pkg.vhd
   constant C_ENGINES     : natural_vector(0 to C_NUM_PUZZLES-1) := C_ENGINES_NEXYS;

   -- The VCO of the MMCM (see clk_rst.vhd): 100 MHz / 5 * 54 = 1080 MHz, as
   -- on the MEGA65, and the 108 MHz pixel clock of 1280x1024.
   constant C_VCO_DIVIDE  : positive := 5;
   constant C_VCO_MULT    : real     := 54.0;

   constant C_VIDEO       : video_mode_t := C_VIDEO_1280X1024;
   constant C_VGA_DIVIDE  : positive := 10;
   constant C_VGA_FREQ    : natural  := 108_000_000;

   -- The divider of the MAIN clock (see clk_rst.vhd), and its frequency in Hz:
   -- 1080 MHz / 7.0 = 154.29 MHz, for the speed grade -1 (180 MHz and
   -- 166 MHz failed by 0.1 to 0.2 ns, in the 16x16 engine, mostly routing).
   constant C_MAIN_DIVIDE : real     := 7.0;
   constant C_MAIN_FREQ   : natural  :=
      natural(100.0E6 / real(C_VCO_DIVIDE) * C_VCO_MULT / C_MAIN_DIVIDE);

   -- The buttons, shown at the bottom of the screen (see status.vhd)
   constant C_HELP        : string :=
      "BTNU all  BTNR next solution  BTNL slow  BTND one step  BTNC pause  SW puzzle";

   signal main_clk  : std_logic;
   signal main_rst  : std_logic;
   signal vga_clk   : std_logic;

   signal cmd_valid : std_logic;
   signal cmd       : cmd_t;

   signal vga_col   : std_logic_vector(23 downto 0);

begin

   i_clk_rst : entity work.clk_rst
      generic map (
         G_VCO_DIVIDE  => C_VCO_DIVIDE,
         G_VCO_MULT    => C_VCO_MULT,
         G_MAIN_DIVIDE => C_MAIN_DIVIDE,
         G_VGA_DIVIDE  => C_VGA_DIVIDE
      )
      port map (
         clk_i      => clk_i,
         rstn_i     => rstn_i,
         main_clk_o => main_clk,
         main_rst_o => main_rst,
         vga_clk_o  => vga_clk,
         vga_rst_o  => open,      -- Only the HDMI output of the MEGA65 uses it
         tmds_clk_o => open
      ); -- i_clk_rst

   i_buttons : entity work.buttons
      generic map (
         G_DEBOUNCE => C_VGA_FREQ / 100
      )
      port map (
         clk_i       => vga_clk,
         btn_i       => btn_i,
         sw_i        => sw_i,
         cmd_valid_o => cmd_valid,
         cmd_o       => cmd
      ); -- i_buttons

   i_core : entity work.core
      generic map (
         G_CLK_FREQ    => C_MAIN_FREQ,
         G_ENGINES     => C_ENGINES,
         G_SLOW_CYCLES => C_MAIN_FREQ / 2,
         G_MODE        => C_VIDEO,
         G_HELP        => C_HELP
      )
      port map (
         main_clk_i  => main_clk,
         main_rst_i  => main_rst,
         vga_clk_i   => vga_clk,
         cmd_valid_i => cmd_valid,
         cmd_i       => cmd,
         vga_hs_o    => vga_hs_o,
         vga_vs_o    => vga_vs_o,
         vga_de_o    => open,
         vga_col_o   => vga_col
      ); -- i_core

   vga_red_o   <= vga_col(23 downto 20);
   vga_green_o <= vga_col(15 downto 12);
   vga_blue_o  <= vga_col( 7 downto  4);

end architecture structural;
