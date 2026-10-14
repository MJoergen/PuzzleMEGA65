-- This is a self-checking testbench of the drawing of the board (board.vhd).
-- For each test case it loads a board picture into a model of the board
-- memory (build/model/board_<n>.mem, the format of snapshot.vhd), lets
-- board.vhd draw one frame of 1280x1024 with the pixel counters of pix.vhd,
-- and compares every visible pixel with the picture of tools/render.py
-- (build/model/board_<n>.ppm, made by "make tbdata"), where a pixel that is
-- not on the board (on_o low) must be the background. The test cases cover
-- the largest and the smallest squares (8x8, 88 pixels, and 1x27, 44
-- pixels), and positions with empty squares (16x16 and 1x27).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

library std;
use std.textio.all;

use work.video_pkg.all;
use work.palette_pkg.all;

entity board_tb is
end entity board_tb;

architecture simulation of board_tb is

   constant C_MODE    : video_mode_t := C_VIDEO_1280X1024;

   -- The test cases: the number of the puzzle (1 to 9)
   type int_vector is array (natural range <>) of natural;
   constant C_CASES   : int_vector := (1, 9, 8);

   type mem_vector is array (0 to 511) of std_logic_vector(12 downto 0);

   signal clk         : std_logic := '0';
   signal running     : std_logic := '1';
   signal puzzle      : natural range 0 to 8 := 0;
   signal buf         : std_logic := '0';
   signal pix_x       : std_logic_vector(10 downto 0);
   signal pix_y       : std_logic_vector(10 downto 0);
   signal rd_addr     : std_logic_vector(8 downto 0);
   signal rd_data     : std_logic_vector(12 downto 0);
   signal col         : std_logic_vector(23 downto 0);
   signal on_b        : std_logic;
   signal mem         : mem_vector := (others => (others => '0'));

   -- The pixel counters, delayed by the latency of board.vhd
   type pix_vector is array (1 to C_BOARD_LATENCY) of std_logic_vector(10 downto 0);
   signal pix_x_d     : pix_vector;
   signal pix_y_d     : pix_vector;

begin

   clk <= running and not clk after 4.63 ns;

   i_pix : entity work.pix
      generic map (
         G_MODE => C_MODE
      )
      port map (
         clk_i   => clk,
         pix_x_o => pix_x,
         pix_y_o => pix_y
      ); -- i_pix

   i_board : entity work.board
      port map (
         clk_i     => clk,
         pix_x_i   => pix_x,
         pix_y_i   => pix_y,
         puzzle_i  => puzzle,
         buf_i     => buf,
         rd_addr_o => rd_addr,
         rd_data_i => rd_data,
         col_o     => col,
         on_o      => on_b
      ); -- i_board

   -- The board memory, with a read latency of one clock cycle
   p_mem : process (clk)
   begin
      if rising_edge(clk) then
         rd_data <= mem(to_integer(rd_addr));
      end if;
   end process p_mem;

   p_delay : process (clk)
   begin
      if rising_edge(clk) then
         pix_x_d <= pix_x & pix_x_d(1 to C_BOARD_LATENCY-1);
         pix_y_d <= pix_y & pix_y_d(1 to C_BOARD_LATENCY-1);
      end if;
   end process p_delay;

   p_test : process
      file     f_v      : text;
      variable l_v      : line;
      variable s_v      : string(1 to 2);
      variable w_v      : integer;
      variable h_v      : integer;
      variable m_v      : integer;
      variable r_v      : integer;
      variable g_v      : integer;
      variable b_v      : integer;
      variable exp_v    : std_logic_vector(23 downto 0);
      variable got_v    : std_logic_vector(23 downto 0);
      variable errors_v : natural;
      variable hex_v    : std_logic_vector(15 downto 0);
      variable name_v   : line;
   begin
      for n in C_CASES'range loop
         -- The board memory (buffer 1, so the buffer bit is tested too)
         buf <= '1';
         file_open(f_v, "build/model/board_" & integer'image(C_CASES(n)) & ".mem", read_mode);
         for i in 0 to 255 loop
            readline(f_v, l_v);
            hread(l_v, hex_v);
            mem(256 + i) <= hex_v(12 downto 0);
         end loop;
         file_close(f_v);
         puzzle <= C_CASES(n) - 1;

         -- Wait for the start of a frame (as seen at the output). The first
         -- time, wait for a whole frame first. After that, this is the next
         -- frame after the last one, so the new puzzle is set during the
         -- vertical blanking, and the whole frame is drawn with it.
         if n = 0 then
            wait until rising_edge(clk) and pix_x_d(C_BOARD_LATENCY) = 0 and
                       pix_y_d(C_BOARD_LATENCY) = 1;
         end if;
         wait until rising_edge(clk) and pix_x_d(C_BOARD_LATENCY) = 0 and
                    pix_y_d(C_BOARD_LATENCY) = 0;

         -- The picture
         file_open(f_v, "build/model/board_" & integer'image(C_CASES(n)) & ".ppm", read_mode);
         readline(f_v, l_v);
         read(l_v, s_v);
         assert s_v = "P3"
            report "Not a P3 file"
            severity failure;
         readline(f_v, l_v);
         read(l_v, w_v);
         read(l_v, h_v);
         readline(f_v, l_v);
         read(l_v, m_v);
         assert w_v = C_MODE.h_visible and h_v = C_MODE.v_visible
            report "The picture has the wrong size"
            severity failure;

         errors_v := 0;
         for y in 0 to C_MODE.v_visible-1 loop
            readline(f_v, l_v);
            for x in 0 to C_MODE.h_visible-1 loop
               assert to_integer(pix_x_d(C_BOARD_LATENCY)) = x and
                      to_integer(pix_y_d(C_BOARD_LATENCY)) = y
                  report "Out of step with the pixel counters"
                  severity failure;
               read(l_v, r_v);
               read(l_v, g_v);
               read(l_v, b_v);
               exp_v := to_slv(r_v, 8) & to_slv(g_v, 8) & to_slv(b_v, 8);
               got_v := col;
               if on_b = '0' then
                  got_v := C_BACKGROUND;
               end if;
               if got_v /= exp_v then
                  if errors_v < 10 then
                     report "Puzzle " & integer'image(C_CASES(n)) & ", pixel (" &
                            integer'image(x) & ", " & integer'image(y) & "): got " &
                            to_hstring(got_v) & ", expected " & to_hstring(exp_v)
                        severity error;
                  end if;
                  errors_v := errors_v + 1;
               end if;
               wait until rising_edge(clk);
            end loop;
            -- The horizontal blanking
            wait until rising_edge(clk) and pix_x_d(C_BOARD_LATENCY) = 0;
         end loop;
         file_close(f_v);
         assert errors_v = 0
            report "Puzzle " & integer'image(C_CASES(n)) & ": " & integer'image(errors_v) &
                   " pixels differ"
            severity failure;
         report "Puzzle " & integer'image(C_CASES(n)) & ": all pixels OK";
      end loop;

      report "board_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;

end architecture simulation;
