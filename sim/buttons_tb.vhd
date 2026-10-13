-- This is a self-checking testbench of the buttons and switches of the Nexys
-- 4 DDR (buttons.vhd), with a short debounce time (G_DEBOUNCE = 50 clock
-- cycles). It checks:
-- * After power-on, the puzzle of the switches is selected once.
-- * Each button gives its command once, also when it bounces (changes faster
--   than the debounce time) when it is pressed and released.
-- * A short glitch (shorter than the debounce time) gives no command.
-- * The switches select the puzzles: 0 is puzzle 1, 1 to 9 are the puzzles
--   1 to 9, and 10 to 15 are puzzle 9. A change of the switches that does not
--   change the puzzle gives no command.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.ctrl_pkg.all;

entity buttons_tb is
end entity buttons_tb;

architecture simulation of buttons_tb is

   constant C_DEBOUNCE : positive := 50;

   signal clk       : std_logic := '0';
   signal running   : std_logic := '1';
   signal btn       : std_logic_vector(4 downto 0) := (others => '0');
   signal sw        : std_logic_vector(3 downto 0) := "0011";
   signal cmd_valid : std_logic;
   signal cmd       : cmd_t;

   signal count     : natural := 0;
   signal last      : cmd_t := (C_CMD_PAUSE, "1111");

   type btn_t is record
      bit : natural;
      cmd : cmd_t;
   end record btn_t;
   type btn_vector is array (natural range <>) of btn_t;

   -- "CLRUD"
   constant C_BTNS : btn_vector := (
      (1, (C_CMD_ALL,   "0000")),   -- BTNU
      (2, (C_CMD_NEXT,  "0000")),   -- BTNR
      (3, (C_CMD_SLOW,  "0000")),   -- BTNL
      (0, (C_CMD_STEP,  "0000")),   -- BTND
      (4, (C_CMD_PAUSE, "0000")));  -- BTNC

begin

   clk <= running and not clk after 5 ns;

   i_buttons : entity work.buttons
      generic map (
         G_DEBOUNCE => C_DEBOUNCE
      )
      port map (
         clk_i       => clk,
         btn_i       => btn,
         sw_i        => sw,
         cmd_valid_o => cmd_valid,
         cmd_o       => cmd
      ); -- i_buttons

   p_count : process (clk)
   begin
      if rising_edge(clk) then
         if cmd_valid = '1' then
            count <= count + 1;
            last  <= cmd;
         end if;
      end if;
   end process p_count;

   p_test : process
      procedure cycles (n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
      end procedure cycles;

      -- A press or a release that bounces three times
      procedure bounce (b : natural; v : std_logic) is
      begin
         for i in 1 to 3 loop
            btn(b) <= v;
            cycles(7);
            btn(b) <= not v;
            cycles(5);
         end loop;
         btn(b) <= v;
      end procedure bounce;

      procedure expect (n : natural; c : cmd_t; what : string) is
      begin
         assert count = n and last = c
            report what & ": " & integer'image(count) & " commands, the last " &
                   to_string(to_slv(last)) & ", expected " & integer'image(n) & " and " &
                   to_string(to_slv(c))
            severity failure;
      end procedure expect;

      variable n_v : natural;
   begin
      -- Power-on: the switches (3) select puzzle 3
      cycles(4 * C_DEBOUNCE);
      expect(1, (C_CMD_PUZZLE, "0010"), "Power-on");

      -- The buttons
      for i in C_BTNS'range loop
         n_v := count;
         bounce(C_BTNS(i).bit, '1');
         cycles(3 * C_DEBOUNCE);
         bounce(C_BTNS(i).bit, '0');
         cycles(3 * C_DEBOUNCE);
         expect(n_v + 1, C_BTNS(i).cmd, "Button " & integer'image(C_BTNS(i).bit));
      end loop;
      report "The buttons: OK";

      -- A glitch
      n_v    := count;
      btn(1) <= '1';
      cycles(C_DEBOUNCE / 2);
      btn(1) <= '0';
      cycles(3 * C_DEBOUNCE);
      expect(n_v, C_BTNS(4).cmd, "A glitch");
      report "A glitch: OK";

      -- The switches
      for v in 0 to 15 loop
         if v /= 3 then
            n_v := count;
            sw  <= to_slv(v, 4);
            cycles(3 * C_DEBOUNCE);
            if v = 0 then
               -- From 3 to 0: puzzle 1
               expect(n_v + 1, (C_CMD_PUZZLE, "0000"), "Switches 0");
            elsif v = 1 then
               -- From 0 to 1: still puzzle 1
               expect(n_v, (C_CMD_PUZZLE, "0000"), "Switches 1");
            elsif v <= 9 then
               expect(n_v + 1, (C_CMD_PUZZLE, to_slv(v - 1, 4)), "Switches " & integer'image(v));
            elsif v = 10 then
               -- From 9 to 10: still puzzle 9
               expect(n_v, (C_CMD_PUZZLE, "1000"), "Switches 10");
            else
               expect(n_v, (C_CMD_PUZZLE, "1000"), "Switches " & integer'image(v));
            end if;
         end if;
      end loop;
      report "The switches: OK";

      report "buttons_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;

end architecture simulation;
