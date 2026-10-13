-- This is the design that is the same on all the boards: the MAIN clock
-- domain (main.vhd, the search), the VGA clock domain (vga.vhd, the screen),
-- and the crossings between them:
-- * the commands (from the keys, in the VGA clock domain) to the MAIN clock
--   domain, by cdc_data.vhd,
-- * the start of each frame to the MAIN clock domain, by cdc_data.vhd
--   (only its m_valid_o is used),
-- * the statistics of the search (ctrl_pkg.vhd) to the VGA clock domain, by
--   cdc_data.vhd, once for each frame,
-- * and the picture of the board, by the board memory (board_mem.vhd), a
--   block RAM with a write port in the MAIN clock domain and a read port in
--   the VGA clock domain.
-- These are the only signals between the clock domains. The top levels of the
-- boards (mega65.vhd and nexys4ddr.vhd) are left with the clocks and resets
-- (clk_rst.vhd), the keyboard or the buttons, the video outputs, and the
-- pins.
--
-- This module has no Xilinx primitives, so the whole design from the
-- commands to the VGA output can be simulated with GHDL (core_tb.vhd).
--
-- The commands must come at most once in a few clock cycles of the MAIN
-- clock (they come from keys, i.e. much more seldom), see cdc_data.vhd.

library ieee;
use ieee.std_logic_1164.all;

use work.util_pkg.all;
use work.video_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity core is
   generic (
      G_CLK_FREQ    : positive;                         -- The MAIN clock, in Hz
      G_ENGINES     : natural_vector(0 to C_NUM_PUZZLES-1);
      G_SLOW_CYCLES : positive;                         -- MAIN clock cycles between slow steps
      G_MODE        : video_mode_t;
      G_HELP        : string                            -- The keys, see status.vhd
   );
   port (
      main_clk_i  : in  std_logic;
      main_rst_i  : in  std_logic;
      vga_clk_i   : in  std_logic;

      -- The commands, in the VGA clock domain
      cmd_valid_i : in  std_logic;
      cmd_i       : in  cmd_t;

      vga_hs_o    : out std_logic;
      vga_vs_o    : out std_logic;
      vga_de_o    : out std_logic;
      vga_col_o   : out std_logic_vector(23 downto 0)   -- RRGGBB
   );
end entity core;

architecture structural of core is

   -- The MAIN clock domain
   signal main_cmd_valid   : std_logic;
   signal main_cmd         : std_logic_vector(C_CMD_BITS-1 downto 0);
   signal main_frame       : std_logic;
   signal main_stats       : stats_t;
   signal main_stats_valid : std_logic;
   signal main_wr_en       : std_logic;
   signal main_wr_addr     : std_logic_vector(8 downto 0);
   signal main_wr_data     : std_logic_vector(12 downto 0);

   -- The VGA clock domain
   signal vga_frame        : std_logic;
   signal vga_stats        : std_logic_vector(C_STATS_BITS-1 downto 0);
   signal vga_rd_addr      : std_logic_vector(8 downto 0);
   signal vga_rd_data      : std_logic_vector(12 downto 0);

begin

   --------------------------------------------------
   -- The commands and the frames to the MAIN clock domain
   --------------------------------------------------

   i_cdc_cmd : entity work.cdc_data
      generic map (
         G_DATA_SIZE => C_CMD_BITS,
         G_INIT      => (C_CMD_BITS-1 downto 0 => '0')
      )
      port map (
         s_clk_i   => vga_clk_i,
         s_data_i  => to_slv(cmd_i),
         s_valid_i => cmd_valid_i,
         m_clk_i   => main_clk_i,
         m_data_o  => main_cmd,
         m_valid_o => main_cmd_valid
      ); -- i_cdc_cmd

   i_cdc_frame : entity work.cdc_data
      generic map (
         G_DATA_SIZE => 1,
         G_INIT      => "0"
      )
      port map (
         s_clk_i   => vga_clk_i,
         s_data_i  => "0",
         s_valid_i => vga_frame,
         m_clk_i   => main_clk_i,
         m_data_o  => open,
         m_valid_o => main_frame
      ); -- i_cdc_frame


   --------------------------------------------------
   -- The MAIN clock domain
   --------------------------------------------------

   i_main : entity work.main
      generic map (
         G_CLK_FREQ    => G_CLK_FREQ,
         G_ENGINES     => G_ENGINES,
         G_SLOW_CYCLES => G_SLOW_CYCLES
      )
      port map (
         clk_i         => main_clk_i,
         rst_i         => main_rst_i,
         cmd_valid_i   => main_cmd_valid,
         cmd_i         => to_cmd(main_cmd),
         frame_i       => main_frame,
         wr_en_o       => main_wr_en,
         wr_addr_o     => main_wr_addr,
         wr_data_o     => main_wr_data,
         stats_o       => main_stats,
         stats_valid_o => main_stats_valid
      ); -- i_main


   --------------------------------------------------
   -- The board and the statistics to the VGA clock domain
   --------------------------------------------------

   i_board_mem : entity work.board_mem
      port map (
         wr_clk_i  => main_clk_i,
         wr_en_i   => main_wr_en,
         wr_addr_i => main_wr_addr,
         wr_data_i => main_wr_data,
         rd_clk_i  => vga_clk_i,
         rd_addr_i => vga_rd_addr,
         rd_data_o => vga_rd_data
      ); -- i_board_mem

   i_cdc_stats : entity work.cdc_data
      generic map (
         G_DATA_SIZE => C_STATS_BITS,
         G_INIT      => to_slv(C_STATS_INIT)
      )
      port map (
         s_clk_i   => main_clk_i,
         s_data_i  => to_slv(main_stats),
         s_valid_i => main_stats_valid,
         m_clk_i   => vga_clk_i,
         m_data_o  => vga_stats,
         m_valid_o => open
      ); -- i_cdc_stats


   --------------------------------------------------
   -- The VGA clock domain
   --------------------------------------------------

   i_vga : entity work.vga
      generic map (
         G_MODE => G_MODE,
         G_HELP => G_HELP
      )
      port map (
         clk_i     => vga_clk_i,
         stats_i   => to_stats(vga_stats),
         frame_o   => vga_frame,
         rd_addr_o => vga_rd_addr,
         rd_data_i => vga_rd_data,
         vga_hs_o  => vga_hs_o,
         vga_vs_o  => vga_vs_o,
         vga_de_o  => vga_de_o,
         vga_col_o => vga_col_o
      ); -- i_vga

end architecture structural;
