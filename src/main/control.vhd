-- This module controls the search, in the MAIN clock domain: it takes the
-- commands (from the keys, see ctrl_pkg.vhd), and drives the solver
-- (solver.vhd). The modes are:
-- * Paused (P, and after power-on): no context starts a pass.
-- * All (A): all the contexts search at full speed, until the search is
--   finished (all positions searched, i.e. all solutions found).
-- * Next (N): like "all", but the search stops at the next solution: halt_o
--   is set in the clock cycle after the solution, so no other pass is
--   committed (see engine.vhd), and the solution is shown.
-- * Slow (S): one step every G_SLOW_CYCLES clock cycles (half a second).
-- * One step (O): one step, then paused.
-- A step is a credit for the context that is shown (disp_ctx_o, see
-- engine.vhd), i.e. the next position of that context. When the shown
-- context is done, another one that is not done is shown. In the mode
-- "next", the context that found the solution is shown.
--
-- When the search is finished, the modes A, N, S, and O start it again from
-- the beginning (the counters start again), and then do what they do. The
-- keys 1 to 9 (C_CMD_PUZZLE) select a puzzle, start its search again, and
-- pause it. A search is started again by a reset of the solver (restart_o,
-- for C_RESTART clock cycles, which also resets the statistics: the engines
-- of the old puzzle still commit a few passes, until their reset arrives,
-- and the counts take a few more clock cycles through the solver, which
-- must not be counted), and the outputs of the solver are only used again
-- C_SETTLE clock cycles later, when they have been updated by every context
-- (the done flags of the contexts are updated once in eight clock cycles).
--
-- status_o is the status shown on the screen (ctrl_pkg.vhd), and searching_o
-- is high while the search runs (for the time of the search).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity control is
   generic (
      G_ENGINES     : natural_vector(0 to C_NUM_PUZZLES-1) := C_ENGINES_MEGA65;
      G_SLOW_CYCLES : positive := 100             -- Clock cycles between slow steps
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;

      cmd_valid_i  : in  std_logic;
      cmd_i        : in  cmd_t;

      -- From the solver
      sol_any_i    : in  std_logic;               -- Combinational, for the halt
      sol_i        : in  natural range 0 to 32;   -- Two clock cycles later
      sol_ctx_i    : in  natural range 0 to 255;
      ctx_done_i   : in  std_logic_vector(0 to 255);
      done_i       : in  std_logic;

      -- To the solver
      puzzle_o     : out natural range 0 to C_NUM_PUZZLES-1;
      restart_o    : out std_logic;
      run_o        : out std_logic;
      halt_o       : out std_logic;
      credit_o     : out std_logic;
      credit_ctx_o : out natural range 0 to 255;

      disp_ctx_o   : out natural range 0 to 255;  -- The context that is shown
      status_o     : out std_logic_vector(2 downto 0);
      searching_o  : out std_logic
   );
end entity control;

architecture rtl of control is

   constant C_RESTART : natural := 8;
   constant C_SETTLE  : natural := 32;

   type mode_t is (PAUSE_ST, ALL_ST, NEXT_ST, SLOW_ST);

   signal mode_r      : mode_t := PAUSE_ST;
   signal puzzle_r    : natural range 0 to C_NUM_PUZZLES-1 := 0;
   signal halt_r      : std_logic := '0';
   signal finished_r  : std_logic := '0';
   signal solution_r  : std_logic := '0';    -- Stopped at a solution (mode "next")
   signal shown_r     : std_logic := '0';    -- ... and its context is shown
   signal disp_r      : natural range 0 to 255 := 0;
   signal disp_done_r : std_logic := '0';    -- The shown context is done
   signal disp_new_r  : std_logic := '1';    -- ... not valid yet, disp_r has changed

   -- The restart: the reset of the solver, and the time until its outputs are
   -- valid. A step that is asked for during a restart is done after it.
   signal restart_r   : std_logic_vector(C_RESTART-1 downto 0) := (others => '1');
   signal settle_r    : natural range 0 to C_SETTLE := C_SETTLE;
   signal step_r      : std_logic := '0';

   signal credit_r    : std_logic := '0';
   signal slow_r      : natural range 0 to G_SLOW_CYCLES-1 := 0;

   -- The number of contexts of a puzzle
   function num_ctx (p : natural) return positive is
   begin
      return maximum(C_STAGES * G_ENGINES(p), 1);
   end function num_ctx;

begin

   p_control : process (clk_i)
      procedure restart is
      begin
         restart_r  <= (others => '1');
         settle_r   <= C_SETTLE;
         finished_r <= '0';
         solution_r <= '0';
         disp_r     <= 0;
         disp_new_r <= '1';
      end procedure restart;
   begin
      if rising_edge(clk_i) then
         credit_r    <= '0';
         restart_r   <= restart_r(C_RESTART-2 downto 0) & '0';
         disp_done_r <= ctx_done_i(disp_r);
         disp_new_r  <= '0';
         if settle_r /= 0 then
            settle_r <= settle_r - 1;
         end if;

         if settle_r = 0 then
            -- A step that was asked for during a restart
            if step_r = '1' then
               credit_r <= '1';
               step_r   <= '0';
            end if;

            -- A solution in the mode "next": stop at once, and show it (the
            -- context of the solution comes two clock cycles later)
            if sol_any_i = '1' and mode_r = NEXT_ST then
               halt_r     <= '1';
               mode_r     <= PAUSE_ST;
               solution_r <= '1';
            end if;
            if sol_i /= 0 and solution_r = '1' and halt_r = '1' and shown_r = '0' then
               disp_r     <= sol_ctx_i;
               disp_new_r <= '1';
               shown_r    <= '1';
            end if;

            -- The end of the search
            if done_i = '1' and finished_r = '0' then
               finished_r <= '1';
               mode_r     <= PAUSE_ST;
            end if;

            -- Show another context when the shown one is done (the done
            -- flag is registered, so it is not used in the clock cycle
            -- after the shown context changes)
            if disp_done_r = '1' and disp_new_r = '0' and done_i = '0' then
               disp_new_r <= '1';
               if disp_r + 1 >= num_ctx(puzzle_r) then
                  disp_r <= 0;
               else
                  disp_r <= disp_r + 1;
               end if;
            end if;

            -- The steps of the mode "slow"
            if mode_r = SLOW_ST then
               if slow_r = G_SLOW_CYCLES-1 then
                  slow_r   <= 0;
                  credit_r <= '1';
               else
                  slow_r <= slow_r + 1;
               end if;
            end if;
         end if;

         -- The commands
         if cmd_valid_i = '1' then
            halt_r     <= '0';
            solution_r <= '0';
            shown_r    <= '0';
            slow_r     <= 0;
            case cmd_i.code is
               when C_CMD_PAUSE =>
                  mode_r <= PAUSE_ST;

               when C_CMD_ALL | C_CMD_NEXT | C_CMD_SLOW =>
                  if finished_r = '1' then
                     restart;
                  end if;
                  if cmd_i.code = C_CMD_ALL then
                     mode_r <= ALL_ST;
                  elsif cmd_i.code = C_CMD_NEXT then
                     mode_r <= NEXT_ST;
                  else
                     mode_r <= SLOW_ST;
                  end if;

               when C_CMD_STEP =>
                  mode_r <= PAUSE_ST;
                  step_r <= '1';
                  if finished_r = '1' then
                     restart;
                  end if;

               when C_CMD_PUZZLE =>
                  if to_integer(cmd_i.puzzle) < C_NUM_PUZZLES then
                     puzzle_r <= to_integer(cmd_i.puzzle);
                     mode_r   <= PAUSE_ST;
                     restart;
                  end if;

               when others =>
                  null;
            end case;
         end if;

         if rst_i = '1' then
            mode_r     <= PAUSE_ST;
            puzzle_r   <= 0;
            halt_r     <= '0';
            step_r     <= '0';
            restart;
         end if;
      end if;
   end process p_control;

   -- The status shown on the screen
   p_status : process (all)
   begin
      if finished_r = '1' then
         status_o <= C_ST_FINISHED;
      elsif solution_r = '1' then
         status_o <= C_ST_SOLUTION;
      else
         case mode_r is
            when ALL_ST  => status_o <= C_ST_ALL;
            when NEXT_ST => status_o <= C_ST_NEXT;
            when SLOW_ST => status_o <= C_ST_SLOW;
            when others  => status_o <= C_ST_PAUSED;
         end case;
      end if;
   end process p_status;

   puzzle_o     <= puzzle_r;
   restart_o    <= restart_r(C_RESTART-1);
   run_o        <= '1' when (mode_r = ALL_ST or mode_r = NEXT_ST) and finished_r = '0' and
                            settle_r = 0 else
 '0';
   halt_o       <= halt_r;
   credit_o     <= credit_r and not finished_r when settle_r = 0 else '0';
   credit_ctx_o <= disp_r;
   disp_ctx_o   <= disp_r;
   searching_o  <= '1' when mode_r /= PAUSE_ST and finished_r = '0' else '0';

end architecture rtl;
