-- This is a self-checking testbench of the whole design (core.vhd), from the
-- commands (as from keys.vhd, in the VGA clock domain) to the VGA output,
-- with the VGA clock of 108 MHz and a MAIN clock of 54 MHz (the MEGA65 has
-- 227.37 MHz, but a slower clock makes the simulation of the frames faster,
-- and the design works with any ratio of the clocks; cdc_data_tb.vhd tests
-- the real ratios). Only the puzzles
-- 8x8, 5x5, 1x16, and 1x27 (1, 6, 7, and 8) have an engine; the others have
-- none, so they are finished at once. The clock frequency given to the design is
-- 1 MHz, so that a "second" of the speed and the time is 1 microsecond.
--
-- It checks the modes of control.vhd with the counts of the model
-- (model_pkg.vhd), from the signals of main.vhd (external names):
-- * After the reset: puzzle 1, paused, one position (the root).
-- * Select 5x5: paused, one position. Four single steps: five positions.
-- * Next: stops at the first solution, with exactly one solution (the
--   passes after the solution are not committed). Next again: two.
-- * All: finishes with all the positions and solutions of the model.
-- * Next after the end: starts again, and stops at the first solution.
-- * Select 1x27, slow: about one step in each slow period. Then all: the
--   counts of the model. Pause.
-- * The statistics in the VGA clock domain (after a frame), and the text of
--   the screen (status.vhd): the status and the number of positions.
--
-- With G_PICTURES it also selects other puzzles and saves pictures of the
-- screen for the README (build/core/*.ppm, see "make pictures"), which takes
-- several minutes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

library std;
use std.textio.all;

use work.util_pkg.all;
use work.video_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;
use work.model_pkg.all;

entity core_tb is
   generic (
      G_PICTURES : boolean := false
   );
end entity core_tb;

architecture simulation of core_tb is

   constant C_MAIN_PERIOD : time := 18.518 ns;
   constant C_VGA_PERIOD  : time := 9.259 ns;
   constant C_SLOW        : positive := 4000;          -- MAIN clock cycles

   -- The engines: only 8x8 and the small puzzles, and for the pictures also
   -- 6x10 and 16x16
   function engines return natural_vector is
   begin
      if G_PICTURES then
         return (1, 1, 0, 0, 0, 1, 1, 1, 1);
      end if;
      return (1, 0, 0, 0, 0, 1, 1, 1, 0);
   end function engines;

   signal main_clk  : std_logic := '0';
   signal main_rst  : std_logic := '1';
   signal vga_clk   : std_logic := '0';
   signal running   : std_logic := '1';

   signal cmd_valid : std_logic := '0';
   signal cmd       : cmd_t := (C_CMD_PAUSE, "0000");

   signal vga_hs    : std_logic;
   signal vga_vs    : std_logic;
   signal vga_de    : std_logic;
   signal vga_col   : std_logic_vector(23 downto 0);


   -- Saving a picture of the next frame
   signal save      : std_logic := '0';
   signal saved     : std_logic := '0';
   signal save_name : string(1 to 32) := (others => ' ');

begin

   main_clk <= running and not main_clk after C_MAIN_PERIOD / 2;
   vga_clk  <= running and not vga_clk after C_VGA_PERIOD / 2;
   main_rst <= '1', '0' after 100 ns;

   i_core : entity work.core
      generic map (
         G_CLK_FREQ    => 1_000_000,
         G_ENGINES     => engines,
         G_SLOW_CYCLES => C_SLOW,
         G_MODE        => C_VIDEO_1280X1024,
         G_HELP        => "A all   N next solution   S slow   O one step   P pause   1-9 puzzle"
      )
      port map (
         main_clk_i  => main_clk,
         main_rst_i  => main_rst,
         vga_clk_i   => vga_clk,
         cmd_valid_i => cmd_valid,
         cmd_i       => cmd,
         vga_hs_o    => vga_hs,
         vga_vs_o    => vga_vs,
         vga_de_o    => vga_de,
         vga_col_o   => vga_col
      ); -- i_core


   p_test : process
      -- Inside the design (after i_core is elaborated)
      alias positions is << signal .core_tb.i_core.i_main.positions : std_logic_vector(47 downto 0) >>;
      alias solutions is << signal .core_tb.i_core.i_main.solutions : std_logic_vector(31 downto 0) >>;
      alias status    is << signal .core_tb.i_core.i_main.status : std_logic_vector(2 downto 0) >>;
      alias puzzle    is << signal .core_tb.i_core.i_main.puzzle : natural range 0 to C_NUM_PUZZLES-1 >>;
      alias vga_stats is << signal .core_tb.i_core.vga_stats : std_logic_vector(C_STATS_BITS-1 downto 0) >>;
      alias text_mem  is << signal .core_tb.i_core.i_vga.i_text.mem : text_mem_t >>;

      -- Send a command, as keys.vhd does, and wait for it to arrive
      procedure send (code : std_logic_vector(2 downto 0); p : natural := 0) is
      begin
         wait until rising_edge(vga_clk);
         cmd_valid <= '1';
         cmd       <= (code, to_slv(p, 4));
         wait until rising_edge(vga_clk);
         cmd_valid <= '0';
         wait for 1 us;
      end procedure send;

      -- Wait until the search is finished or stopped at a solution
      procedure wait_stop is
      begin
         wait for 1 us;
         while status /= C_ST_FINISHED and status /= C_ST_SOLUTION loop
            wait for 1 us;
         end loop;
      end procedure wait_stop;

      procedure expect (pos : natural; sol : natural; st : std_logic_vector(2 downto 0);
                        what : string) is
      begin
         assert to_integer(positions) = pos and to_integer(solutions) = sol and status = st
            report what & ": " & integer'image(to_integer(positions)) & " positions, " &
                   integer'image(to_integer(solutions)) & " solutions, status " &
                   to_string(status) & ", expected " & integer'image(pos) & ", " &
                   integer'image(sol) & ", " & to_string(st)
            severity failure;
         report what & ": OK";
      end procedure expect;

      -- The text at a position of the screen
      function text_at (mem : text_mem_t; row : natural; col : natural; len : natural)
      return string is
         variable r_v : string(1 to len);
      begin
         for i in 0 to len-1 loop
            r_v(i + 1) := character'val(to_integer(mem(row * 80 + col + i)(6 downto 0)));
         end loop;
         return r_v;
      end function text_at;

      -- Wait for two frames, so the statistics and the text are new
      procedure wait_frames (n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(vga_clk) and vga_vs = '1';
            wait until rising_edge(vga_clk) and vga_vs = '0';
         end loop;
         wait for 100 us;
      end procedure wait_frames;

      -- Save a picture of the next frame
      procedure picture (name : string) is
      begin
         save_name                   <= (others => ' ');
         save_name(1 to name'length) <= name;
         save                        <= '1';
         wait until saved = '1';
         save <= '0';
         wait until saved = '0';
      end procedure picture;

      variable pos_v : natural;
      variable st_v  : stats_t;
   begin
      wait for 2 us;
      expect(1, 0, C_ST_PAUSED, "After the reset");
      assert puzzle = 0 report "Not puzzle 1 after the reset" severity failure;

      -- 5x5: steps
      send(C_CMD_PUZZLE, 5);
      assert puzzle = 5 report "Not puzzle 6" severity failure;
      expect(1, 0, C_ST_PAUSED, "5x5 selected");
      for i in 1 to 4 loop
         send(C_CMD_STEP);
      end loop;
      expect(5, 0, C_ST_PAUSED, "5x5 after four steps");

      -- Next solution, twice
      send(C_CMD_NEXT);
      wait_stop;
      assert to_integer(solutions) = 1 and status = C_ST_SOLUTION
         report "5x5: not stopped at the first solution" severity failure;
      report "5x5 next: stopped at " & integer'image(to_integer(positions)) & " positions";
      send(C_CMD_NEXT);
      wait_stop;
      assert to_integer(solutions) = 2 and status = C_ST_SOLUTION
         report "5x5: not stopped at the second solution" severity failure;
      report "5x5 next: stopped at " & integer'image(to_integer(positions)) & " positions";

      -- All
      send(C_CMD_ALL);
      wait_stop;
      expect(C_MODEL(5).nodes, C_MODEL(5).solutions, C_ST_FINISHED, "5x5 all");

      -- Next after the end: it starts again
      send(C_CMD_NEXT);
      wait_stop;
      assert to_integer(solutions) = 1 and status = C_ST_SOLUTION and
             to_integer(positions) < C_MODEL(5).nodes
         report "5x5: next after the end did not start again" severity failure;
      report "5x5 next after the end: OK, stopped at " & integer'image(to_integer(positions)) &
             " positions";

      -- 1x27: slow, then all
      send(C_CMD_PUZZLE, 7);
      expect(1, 0, C_ST_PAUSED, "1x27 selected");
      send(C_CMD_SLOW);
      assert status = C_ST_SLOW report "Not slow" severity failure;
      wait for 10 * C_SLOW * C_MAIN_PERIOD;
      pos_v := to_integer(positions);
      assert pos_v >= 1 + 8 and pos_v <= 1 + 11
         report "1x27 slow: " & integer'image(pos_v) & " positions after ten periods"
         severity failure;
      report "1x27 slow: " & integer'image(pos_v) & " positions after ten periods, OK";
      send(C_CMD_ALL);
      wait_stop;
      expect(C_MODEL(7).nodes, C_MODEL(7).solutions, C_ST_FINISHED, "1x27 all");

      -- The statistics and the text in the VGA clock domain
      wait_frames(2);
      st_v := to_stats(vga_stats);
      assert to_integer(st_v.positions) = C_MODEL(7).nodes and
             to_integer(st_v.solutions) = C_MODEL(7).solutions and
             st_v.status = C_ST_FINISHED and to_integer(st_v.puzzle) = 7 and
             to_integer(st_v.progress) = 1000
         report "The statistics in the VGA clock domain are wrong" severity failure;
      assert text_at(text_mem, 1, 51, 27) = "        ALL SOLUTIONS FOUND"
         report "The status on the screen is """ & text_at(text_mem, 1, 51, 27) & """"
         severity failure;
      assert text_at(text_mem, 26, 23, 19) = "              3,106" and
             text_at(text_mem, 26, 63, 13) = "            6" and
             text_at(text_mem, 27, 69, 5) = "100.0"
         report "The statistics on the screen are """ & text_at(text_mem, 26, 23, 19) &
                """, """ & text_at(text_mem, 26, 63, 13) & """, and """ &
                text_at(text_mem, 27, 69, 5) & """"
         severity failure;
      assert text_at(text_mem, 1, 2, 16) = "Puzzle 8   1x27 "
         report "The puzzle on the screen is """ & text_at(text_mem, 1, 2, 16) & """"
         severity failure;
      report "The statistics and the text on the screen: OK";

      if G_PICTURES then
         picture("puzzle_1x27_finished");

         -- 8x8: a few steps, then the first solution
         send(C_CMD_PUZZLE, 0);
         wait_frames(2);
         picture("puzzle_8x8_start");
         for i in 1 to 7 loop
            send(C_CMD_STEP);
         end loop;
         wait_frames(2);
         picture("puzzle_8x8_steps");
         send(C_CMD_NEXT);
         wait_stop;
         wait_frames(2);
         picture("puzzle_8x8_solution");

         -- 6x10: the first solution
         send(C_CMD_PUZZLE, 1);
         send(C_CMD_NEXT);
         wait_stop;
         wait_frames(2);
         picture("puzzle_6x10_solution");

         -- 16x16: searching
         send(C_CMD_PUZZLE, 8);
         send(C_CMD_ALL);
         wait_frames(3);
         picture("puzzle_16x16_search");

         -- 5x5: finished
         send(C_CMD_PUZZLE, 5);
         send(C_CMD_ALL);
         wait_stop;
         wait_frames(2);
         picture("puzzle_5x5_finished");
      end if;

      report "core_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;


   -- Save the next frame as a picture (P6), when save is set
   p_save : process
      type char_file is file of character;
      constant C_HEADER : string := "P6" & LF & "1280 1024" & LF & "255" & LF;
      file     f_v    : char_file;
      variable name_v : line;
   begin
      saved <= '0';
      wait until save = '1';
      -- The start of the next frame: the first visible pixel
      wait until rising_edge(vga_clk) and vga_vs = '1';
      wait until rising_edge(vga_clk) and vga_de = '1';
      name_v := new string'("build/core/");
      for i in save_name'range loop
         if save_name(i) /= ' ' then
            write(name_v, save_name(i));
         end if;
      end loop;
      write(name_v, string'(".ppm"));
      file_open(f_v, name_v.all, write_mode);
      for i in C_HEADER'range loop
         write(f_v, C_HEADER(i));
      end loop;
      for y in 0 to 1023 loop
         for x in 0 to 1279 loop
            assert vga_de = '1' report "Out of step with the video" severity failure;
            write(f_v, character'val(to_integer(vga_col(23 downto 16))));
            write(f_v, character'val(to_integer(vga_col(15 downto  8))));
            write(f_v, character'val(to_integer(vga_col( 7 downto  0))));
            wait until rising_edge(vga_clk);
         end loop;
         if y < 1023 then
            wait until rising_edge(vga_clk) and vga_de = '1';
         end if;
      end loop;
      file_close(f_v);
      report "Saved " & name_v.all;
      saved <= '1';
      wait until save = '0';
   end process p_save;

end architecture simulation;
