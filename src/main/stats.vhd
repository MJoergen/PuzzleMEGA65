-- This module counts the statistics of the search, in the MAIN clock domain:
-- * positions_o: the positions (nodes) considered, i.e. the counted passes
--   of the engines (count_i each clock cycle) plus the root. After a restart
--   it is one, the root (the empty board), as in the C++ program.
-- * solutions_o: the solutions found.
-- * rate_o: the positions in the last whole second (G_CLK_FREQ clock
--   cycles), i.e. the positions per second.
-- * time_o: the time of the search (while searching_i is high), in tenths
--   of a second.
-- * progress_o: an estimate of the progress, in per mille: the share of the
--   subtrees at the depth of the split that have been handed out to the
--   contexts (claimed_i, see solver.vhd), less one for each context (at the
--   start, every context has one), and 1000 when the search is finished.
--   It is the number of subtrees times a constant (1000 * 2**20 / frontier),
--   shifted right by 20 bits.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;

entity stats is
   generic (
      G_CLK_FREQ : positive;                       -- In Hz
      G_ENGINES  : natural_vector(0 to C_NUM_PUZZLES-1)
   );
   port (
      clk_i       : in  std_logic;
      restart_i   : in  std_logic;
      puzzle_i    : in  natural range 0 to C_NUM_PUZZLES-1;
      count_i     : in  natural range 0 to 32;
      sol_i       : in  natural range 0 to 32;
      claimed_i   : in  std_logic_vector(31 downto 0);
      searching_i : in  std_logic;
      finished_i  : in  std_logic;

      positions_o : out std_logic_vector(47 downto 0);
      solutions_o : out std_logic_vector(31 downto 0);
      rate_o      : out std_logic_vector(35 downto 0);
      time_o      : out std_logic_vector(23 downto 0);
      progress_o  : out std_logic_vector( 9 downto 0)
   );
end entity stats;

architecture rtl of stats is

   -- The constant of the progress of each puzzle
   type recip_vector is array (0 to C_NUM_PUZZLES-1) of std_logic_vector(31 downto 0);

   function recips return recip_vector is
      variable r_v : recip_vector;
   begin
      for p in 0 to C_NUM_PUZZLES-1 loop
         r_v(p) := to_slv(integer(1000.0 * 2.0**20 / real(C_PUZZLES(p).frontier)), 32);
      end loop;
      return r_v;
   end function recips;

   constant C_RECIP     : recip_vector := recips;

   signal positions_r   : std_logic_vector(47 downto 0);
   signal solutions_r   : std_logic_vector(31 downto 0);

   signal second_r      : natural range 0 to G_CLK_FREQ-1;
   signal start_r       : std_logic_vector(47 downto 0);  -- The positions a second ago
   signal rate_r        : std_logic_vector(35 downto 0);

   signal tenth_r       : natural range 0 to G_CLK_FREQ/10-1;
   signal time_r        : std_logic_vector(23 downto 0);

   signal claimed_r     : natural range 0 to 2**21-1;
   signal big_r         : std_logic;
   signal big_d         : std_logic;
   signal first_r       : natural range 0 to 255;
   signal frontier_r    : natural range 0 to 2**21-1;
   signal recip_r       : std_logic_vector(31 downto 0);
   signal diff_r        : integer range -255 to 2**21-1;
   signal subtrees_r    : std_logic_vector(20 downto 0);
   signal product_r     : std_logic_vector(52 downto 0);
   signal product_d     : std_logic_vector(52 downto 0);
   signal progress_r    : std_logic_vector( 9 downto 0);

begin

   p_count : process (clk_i)
   begin
      if rising_edge(clk_i) then
         positions_r <= positions_r + count_i;
         solutions_r <= solutions_r + sol_i;

         if restart_i = '1' then
            positions_r <= to_slv(1, 48);
            solutions_r <= (others => '0');
         end if;
      end if;
   end process p_count;

   p_rate : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if second_r = G_CLK_FREQ-1 then
            second_r <= 0;
            rate_r   <= resize(positions_r - start_r, 36);
            start_r  <= positions_r;
         else
            second_r <= second_r + 1;
         end if;

         if restart_i = '1' then
            start_r <= to_slv(1, 48);
         end if;
      end if;
   end process p_rate;

   p_time : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if searching_i = '1' then
            if tenth_r = G_CLK_FREQ/10-1 then
               tenth_r <= 0;
               time_r  <= time_r + 1;
            else
               tenth_r <= tenth_r + 1;
            end if;
         end if;

         if restart_i = '1' then
            tenth_r <= 0;
            time_r  <= (others => '0');
         end if;
      end if;
   end process p_time;

   -- The progress, in a pipeline of registers (it is shown once in each
   -- frame, so the latency does not matter): the constants of the puzzle and
   -- the claims, the subtrees less the contexts, the subtrees limited to the
   -- frontier, the product (two clock cycles, in DSPs), and the progress.
   p_progress : process (clk_i)
   begin
      if rising_edge(clk_i) then
         claimed_r  <= to_integer(claimed_i(20 downto 0));
         big_r      <= or claimed_i(31 downto 21);
         first_r    <= C_STAGES * G_ENGINES(puzzle_i);
         frontier_r <= C_PUZZLES(puzzle_i).frontier;
         recip_r    <= C_RECIP(puzzle_i);

         diff_r     <= claimed_r - first_r;
         big_d      <= big_r;

         if big_d = '1' then
            subtrees_r <= to_slv(frontier_r, 21);
         elsif diff_r < 0 then
            subtrees_r <= (others => '0');
         elsif diff_r > frontier_r then
            subtrees_r <= to_slv(frontier_r, 21);
         else
            subtrees_r <= to_slv(diff_r, 21);
         end if;

         product_r  <= subtrees_r * recip_r;
         product_d  <= product_r;

         progress_r <= product_d(29 downto 20);
         if finished_i = '1' then
            progress_r <= to_slv(1000, 10);
         end if;
      end if;
   end process p_progress;

   positions_o <= positions_r;
   solutions_o <= solutions_r;
   rate_o      <= rate_r;
   time_o      <= time_r;
   progress_o  <= progress_r;

end architecture rtl;
