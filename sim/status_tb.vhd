-- This is a self-checking testbench of the text of the screen (status.vhd).
-- It gives the module statistics (see ctrl_pkg.vhd), sends frame_i, collects
-- the writes to the text memory, and checks the text and the colours at the
-- positions of the fields and the labels:
-- * typical values: 8x8, all solutions found (green), 853,260,456 positions,
--   129,168 solutions, 97.3 % and 12.3 s,
-- * the smallest values: one position, zeros everywhere (0.0), paused,
-- * the largest values of each field (all ones), solution found (yellow),
--   16x16,
-- and that the whole screen (2560 characters) is written in the first frame.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.ctrl_pkg.all;

entity status_tb is
end entity status_tb;

architecture simulation of status_tb is

   constant C_HELP  : string := "A all   N next solution   S slow   O one step   P pause   1-9 puzzle";

   type text_vector is array (0 to 2559) of std_logic_vector(8 downto 0);

   signal clk       : std_logic := '0';
   signal running   : std_logic := '1';
   signal frame     : std_logic := '0';
   signal stats     : stats_t := C_STATS_INIT;
   signal wr_en     : std_logic;
   signal wr_addr   : std_logic_vector(11 downto 0);
   signal wr_data   : std_logic_vector( 8 downto 0);

   signal screen    : text_vector := (others => (others => '1'));
   signal writes    : natural := 0;

begin

   clk <= running and not clk after 4.63 ns;

   i_status : entity work.status
      generic map (
         G_HELP => C_HELP
      )
      port map (
         clk_i     => clk,
         frame_i   => frame,
         stats_i   => stats,
         wr_en_o   => wr_en,
         wr_addr_o => wr_addr,
         wr_data_o => wr_data
      ); -- i_status

   p_mem : process (clk)
   begin
      if rising_edge(clk) then
         if wr_en = '1' then
            screen(to_integer(wr_addr)) <= wr_data;
            writes                      <= writes + 1;
         end if;
      end if;
   end process p_mem;

   p_test : process
      procedure show (s : stats_t) is
      begin
         stats <= s;
         wait until rising_edge(clk);
         frame <= '1';
         wait until rising_edge(clk);
         frame <= '0';
         -- The conversions and the writes
         for i in 1 to 4000 loop
            wait until rising_edge(clk);
         end loop;
      end procedure show;

      -- The text and the colour at a position
      procedure expect (row : natural; col : natural; s : string; colour : natural) is
         variable got_v : string(1 to s'length);
         variable ok_v  : boolean := true;
      begin
         for i in 0 to s'length-1 loop
            got_v(i + 1) := character'val(to_integer(screen(row * 80 + col + i)(6 downto 0)));
            if to_integer(screen(row * 80 + col + i)(8 downto 7)) /= colour and
               s(s'low + i) /= ' '
            then
               ok_v := false;
            end if;
         end loop;
         assert got_v = s and ok_v
            report "At row " & integer'image(row) & ", column " & integer'image(col) & ": """ &
                   got_v & """, expected """ & s & """ in colour " & integer'image(colour)
            severity failure;
      end procedure expect;

      variable s_v : stats_t;
   begin
      wait until rising_edge(clk);

      -- Typical values
      s_v           := C_STATS_INIT;
      s_v.positions := to_slv(853260456, 48);
      s_v.solutions := to_slv(129168, 32);
      s_v.rate      := X"0" & to_slv(1500123456, 32);
      s_v.progress  := to_slv(973, 10);
      s_v.time      := to_slv(123, 24);
      s_v.status    := C_ST_FINISHED;
      s_v.puzzle    := "0000";
      show(s_v);
      assert writes = 2560
         report "Wrote " & integer'image(writes) & " characters" severity failure;
      expect( 1,  2, "Puzzle", 1);
      expect( 1,  9, "1", 0);
      expect( 1, 13, "8x8", 0);
      expect( 1, 20, "12 pentominoes and a square", 0);
      expect( 1, 51, "        ALL SOLUTIONS FOUND", 2);
      expect(26,  2, "Positions considered", 1);
      expect(26, 23, "        853,260,456", 0);
      expect(26, 47, "Solutions found", 1);
      expect(26, 63, "      129,168", 0);
      expect(27,  2, "Positions per second", 1);
      expect(27, 28, " 1,500,123,456", 0);
      expect(27, 47, "Progress", 1);
      expect(27, 69, " 97.3", 0);
      expect(27, 75, "%", 1);
      expect(28,  2, "Time searching", 1);
      expect(28, 31, "     12.3", 0);
      expect(28, 41, "s", 1);
      expect(30,  2, C_HELP, 1);
      expect( 0,  0, (1 to 80 => ' '), 1);
      report "Typical values: OK";

      -- The smallest values
      s_v           := C_STATS_INIT;
      s_v.positions := to_slv(1, 48);
      s_v.puzzle    := "0101";
      show(s_v);
      expect( 1,  9, "6", 0);
      expect( 1, 13, "5x5  ", 0);
      expect( 1, 51, "                     Paused", 0);
      expect(26, 23, "                  1", 0);
      expect(26, 63, "            0", 0);
      expect(27, 28, "             0", 0);
      expect(27, 69, "  0.0", 0);
      expect(28, 31, "      0.0", 0);
      report "The smallest values: OK";

      -- The largest values
      s_v.positions := (others => '1');
      s_v.solutions := (others => '1');
      s_v.rate      := (others => '1');
      s_v.progress  := to_slv(1000, 10);
      s_v.time      := (others => '1');
      s_v.status    := C_ST_SOLUTION;
      s_v.puzzle    := "1000";
      show(s_v);
      expect( 1,  9, "9", 0);
      expect( 1, 13, "16x16", 0);
      expect( 1, 20, "19 large pieces", 0);
      expect( 1, 51, "             Solution found", 3);
      expect(26, 23, "281,474,976,710,655", 0);
      expect(26, 63, "4,294,967,295", 0);
      expect(27, 28, "68,719,476,735", 0);
      expect(27, 69, "100.0", 0);
      expect(28, 31, "1677721.5", 0);
      report "The largest values: OK";

      -- The other status texts
      for st in 1 to 3 loop
         s_v.status := to_slv(st, 3);
         show(s_v);
         case st is
            when 1      => expect(1, 51, "    Searching all positions", 0);
            when 2      => expect(1, 51, "Searching for next solution", 0);
            when others => expect(1, 51, "           Searching slowly", 0);
         end case;
      end loop;
      report "The status texts: OK";

      report "status_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;

end architecture simulation;
