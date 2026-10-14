-- This package has the types and constants that are used in both clock
-- domains: the commands from the keyboard (or the buttons) to the search, the
-- status of the search, and the statistics of the search that are shown on
-- the screen.
--
-- A command (cmd_t) is a code and, for C_CMD_PUZZLE, the number of the puzzle
-- (0 to 8, for the keys 1 to 9). The commands are made in the VGA clock
-- domain (keys.vhd on the MEGA65, buttons.vhd on the Nexys 4 DDR), and moved
-- to the MAIN clock domain in core.vhd, see control.vhd.
--
-- The statistics (stats_t) are made in the MAIN clock domain once for each
-- frame, together with the picture of the board, and moved to the VGA clock
-- domain in core.vhd, see snapshot.vhd and status.vhd.

library ieee;
use ieee.std_logic_1164.all;

package ctrl_pkg is

   -- The commands, see control.vhd
   constant C_CMD_PAUSE  : std_logic_vector(2 downto 0) := "000";  -- P
   constant C_CMD_ALL    : std_logic_vector(2 downto 0) := "001";  -- A
   constant C_CMD_NEXT   : std_logic_vector(2 downto 0) := "010";  -- N
   constant C_CMD_SLOW   : std_logic_vector(2 downto 0) := "011";  -- S
   constant C_CMD_STEP   : std_logic_vector(2 downto 0) := "100";  -- O
   constant C_CMD_PUZZLE : std_logic_vector(2 downto 0) := "101";  -- 1 to 9

   type cmd_t is record
      code   : std_logic_vector(2 downto 0);
      puzzle : std_logic_vector(3 downto 0);
   end record cmd_t;

   constant C_CMD_BITS : natural := 7;

   function to_slv (c : cmd_t) return std_logic_vector;
   function to_cmd (v : std_logic_vector) return cmd_t;

   -- The status of the search, as shown on the screen
   constant C_ST_PAUSED   : std_logic_vector(2 downto 0) := "000";
   constant C_ST_ALL      : std_logic_vector(2 downto 0) := "001";  -- Searching (A)
   constant C_ST_NEXT     : std_logic_vector(2 downto 0) := "010";  -- Searching (N)
   constant C_ST_SLOW     : std_logic_vector(2 downto 0) := "011";  -- Searching slowly (S)
   constant C_ST_SOLUTION : std_logic_vector(2 downto 0) := "100";  -- Stopped at a solution
   constant C_ST_FINISHED : std_logic_vector(2 downto 0) := "101";  -- All solutions found

   -- The statistics of the search
   type stats_t is record
      positions : std_logic_vector(47 downto 0);  -- Positions considered
      solutions : std_logic_vector(31 downto 0);  -- Solutions found
      rate      : std_logic_vector(35 downto 0);  -- Positions in the last second
      progress  : std_logic_vector( 9 downto 0);  -- Per mille
      time      : std_logic_vector(23 downto 0);  -- Time searching, in tenths of seconds
      status    : std_logic_vector( 2 downto 0);
      puzzle    : std_logic_vector( 3 downto 0);
      buf       : std_logic;                      -- The buffer of the board picture
   end record stats_t;

   constant C_STATS_BITS : natural := 48 + 32 + 36 + 10 + 24 + 3 + 4 + 1;

   constant C_STATS_INIT : stats_t := (positions => (others => '0'),
      solutions => (others => '0'),
      rate      => (others => '0'),
      progress  => (others => '0'),
      time      => (others => '0'),
      status    => C_ST_PAUSED,
      puzzle    => (others => '0'),
      buf       => '1');

   function to_slv (s : stats_t) return std_logic_vector;
   function to_stats (v : std_logic_vector) return stats_t;

end package ctrl_pkg;

package body ctrl_pkg is

   function to_slv (c : cmd_t) return std_logic_vector is
   begin
      return c.code & c.puzzle;
   end function to_slv;

   function to_cmd (v : std_logic_vector) return cmd_t is
      variable v_v : std_logic_vector(C_CMD_BITS-1 downto 0);
      variable r_v : cmd_t;
   begin
      v_v      := v;
      r_v.code := v_v(6 downto 4);
      r_v.puzzle := v_v(3 downto 0);
      return r_v;
   end function to_cmd;

   function to_slv (s : stats_t) return std_logic_vector is
   begin
      return s.positions & s.solutions & s.rate & s.progress & s.time & s.status & s.puzzle &
             s.buf;
   end function to_slv;

   function to_stats (v : std_logic_vector) return stats_t is
      variable v_v : std_logic_vector(C_STATS_BITS-1 downto 0);
      variable r_v : stats_t;
   begin
      v_v           := v;
      r_v.positions := v_v(157 downto 110);
      r_v.solutions := v_v(109 downto 78);
      r_v.rate      := v_v( 77 downto 42);
      r_v.progress  := v_v( 41 downto 32);
      r_v.time      := v_v( 31 downto  8);
      r_v.status    := v_v(  7 downto  5);
      r_v.puzzle    := v_v(  4 downto  1);
      r_v.buf       := v_v(0);
      return r_v;
   end function to_stats;

end package body ctrl_pkg;
