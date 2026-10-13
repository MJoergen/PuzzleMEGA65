-- This is the MAIN clock domain: the search of the puzzles. It has
-- * the engines of all the puzzles (solver.vhd),
-- * the control of the modes (control.vhd), driven by the commands from the
--   keys (cmd_valid_i, cmd_i),
-- * the statistics (stats.vhd),
-- * and the picture of the board (snapshot.vhd), which is written to the
--   board memory once for each frame (frame_i, from the VGA clock domain).
-- Each time the picture is written, the statistics are sent to the VGA clock
-- domain (stats_o with stats_valid_o, see ctrl_pkg.vhd), with the number of
-- the buffer of the board memory that holds the picture. The statistics are
-- taken when the position of the picture is read (see snapshot.vhd), so they
-- belong to the position.
--
-- All the inputs and outputs are in the MAIN clock domain; they are moved to
-- and from the VGA clock domain in core.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity main is
   generic (
      G_CLK_FREQ    : positive;                         -- In Hz
      G_ENGINES     : natural_vector(0 to C_NUM_PUZZLES-1);
      G_SLOW_CYCLES : positive                          -- Clock cycles between slow steps
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;

      cmd_valid_i   : in  std_logic;
      cmd_i         : in  cmd_t;
      frame_i       : in  std_logic;

      -- Write port of the board memory
      wr_en_o       : out std_logic;
      wr_addr_o     : out std_logic_vector(8 downto 0);
      wr_data_o     : out std_logic_vector(12 downto 0);

      stats_o       : out stats_t;
      stats_valid_o : out std_logic
   );
end entity main;

architecture structural of main is

   signal puzzle      : natural range 0 to C_NUM_PUZZLES-1;
   signal restart     : std_logic;
   signal run         : std_logic;
   signal halt        : std_logic;
   signal credit      : std_logic;
   signal credit_ctx  : natural range 0 to 255;
   signal disp_ctx    : natural range 0 to 255;
   signal status      : std_logic_vector(2 downto 0);
   signal searching   : std_logic;

   signal count       : natural range 0 to 32;
   signal sol         : natural range 0 to 32;
   signal sol_ctx     : natural range 0 to 255;
   signal sol_any     : std_logic;
   signal claimed     : std_logic_vector(31 downto 0);
   signal busy        : std_logic_vector(0 to 255);
   signal ctx_done    : std_logic_vector(0 to 255);
   signal done        : std_logic;

   signal hold        : std_logic;
   signal hold_ctx    : natural range 0 to 255;
   signal path_ctx    : natural range 0 to 255;
   signal path_lvl    : std_logic_vector(4 downto 0);
   signal path_anchor : std_logic_vector(8 downto 0);
   signal path_slot   : std_logic_vector(7 downto 0);
   signal path_vis    : std_logic_vector(4 downto 0);

   signal positions   : std_logic_vector(47 downto 0);
   signal solutions   : std_logic_vector(31 downto 0);
   signal rate        : std_logic_vector(35 downto 0);
   signal time        : std_logic_vector(23 downto 0);
   signal progress    : std_logic_vector( 9 downto 0);

   signal latch       : std_logic;
   signal buf         : std_logic;
   signal stats_r     : stats_t := C_STATS_INIT;

begin

   i_control : entity work.control
      generic map (
         G_ENGINES     => G_ENGINES,
         G_SLOW_CYCLES => G_SLOW_CYCLES
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         cmd_valid_i  => cmd_valid_i,
         cmd_i        => cmd_i,
         sol_any_i    => sol_any,
         sol_i        => sol,
         sol_ctx_i    => sol_ctx,
         ctx_done_i   => ctx_done,
         done_i       => done,
         puzzle_o     => puzzle,
         restart_o    => restart,
         run_o        => run,
         halt_o       => halt,
         credit_o     => credit,
         credit_ctx_o => credit_ctx,
         disp_ctx_o   => disp_ctx,
         status_o     => status,
         searching_o  => searching
      ); -- i_control

   i_solver : entity work.solver
      generic map (
         G_ENGINES => G_ENGINES
      )
      port map (
         clk_i         => clk_i,
         rst_i         => restart,
         puzzle_i      => puzzle,
         run_i         => run,
         halt_i        => halt,
         credit_i      => credit,
         credit_ctx_i  => credit_ctx,
         hold_i        => hold,
         hold_ctx_i    => hold_ctx,
         count_o       => count,
         sol_o         => sol,
         sol_ctx_o     => sol_ctx,
         sol_any_o     => sol_any,
         claimed_o     => claimed,
         busy_o        => busy,
         ctx_done_o    => ctx_done,
         done_o        => done,
         path_ctx_i    => path_ctx,
         path_lvl_i    => path_lvl,
         path_anchor_o => path_anchor,
         path_slot_o   => path_slot,
         path_vis_o    => path_vis
      ); -- i_solver

   i_stats : entity work.stats
      generic map (
         G_CLK_FREQ => G_CLK_FREQ,
         G_ENGINES  => G_ENGINES
      )
      port map (
         clk_i       => clk_i,
         restart_i   => restart,
         puzzle_i    => puzzle,
         count_i     => count,
         sol_i       => sol,
         claimed_i   => claimed,
         searching_i => searching,
         finished_i  => to_sl(status = C_ST_FINISHED),
         positions_o => positions,
         solutions_o => solutions,
         rate_o      => rate,
         time_o      => time,
         progress_o  => progress
      ); -- i_stats

   i_snapshot : entity work.snapshot
      port map (
         clk_i         => clk_i,
         rst_i         => rst_i,
         frame_i       => frame_i,
         puzzle_i      => puzzle,
         disp_ctx_i    => disp_ctx,
         hold_o        => hold,
         hold_ctx_o    => hold_ctx,
         busy_i        => busy,
         path_ctx_o    => path_ctx,
         path_lvl_o    => path_lvl,
         path_anchor_i => path_anchor,
         path_slot_i   => path_slot,
         path_vis_i    => path_vis,
         wr_en_o       => wr_en_o,
         wr_addr_o     => wr_addr_o,
         wr_data_o     => wr_data_o,
         latch_o       => latch,
         stats_valid_o => stats_valid_o,
         buf_o         => buf
      ); -- i_snapshot

   -- The statistics of the position of the picture
   p_stats : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if latch = '1' then
            stats_r.positions <= positions;
            stats_r.solutions <= solutions;
            stats_r.rate      <= rate;
            stats_r.progress  <= progress;
            stats_r.time      <= time;
            stats_r.status    <= status;
         end if;
         if frame_i = '1' then
            stats_r.puzzle <= to_slv(puzzle, 4);
         end if;
      end if;
   end process p_stats;

   stats_o <= (positions => stats_r.positions,
               solutions => stats_r.solutions,
               rate      => stats_r.rate,
               progress  => stats_r.progress,
               time      => stats_r.time,
               status    => stats_r.status,
               puzzle    => stats_r.puzzle,
               buf       => buf);

end architecture structural;
