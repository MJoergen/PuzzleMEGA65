-- This is a self-checking testbench of the keys of the MEGA65 (keys.vhd). A
-- model of the keyboard driver (m2m_keyb.vhd) cycles through the 80 keys,
-- one per clock cycle, and shows whether each is pressed. The testbench
-- presses each of the 14 keys in turn, and checks that exactly one command
-- comes, the right one, while the key is held for a while, and none when it
-- is released. Then it presses two keys at once (the one listed first in
-- keys.vhd wins), and keys that are not used.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.ctrl_pkg.all;

entity keys_tb is
end entity keys_tb;

architecture simulation of keys_tb is

   signal clk           : std_logic := '0';
   signal running       : std_logic := '1';
   signal key_num       : natural range 0 to 79 := 0;
   signal key_pressed_n : std_logic;
   signal pressed       : std_logic_vector(0 to 79) := (others => '0');
   signal cmd_valid     : std_logic;
   signal cmd           : cmd_t;

   -- The commands seen
   signal count         : natural := 0;
   signal last          : cmd_t := (C_CMD_PAUSE, "0000");

   type key_t is record
      num : natural;
      cmd : cmd_t;
   end record key_t;
   type key_vector is array (natural range <>) of key_t;

   constant C_KEYS : key_vector := (
      (10, (C_CMD_ALL,    "0000")),   -- A
      (13, (C_CMD_SLOW,   "0000")),   -- S
      (41, (C_CMD_PAUSE,  "0000")),   -- P
      (38, (C_CMD_STEP,   "0000")),   -- O
      (39, (C_CMD_NEXT,   "0000")),   -- N
      (56, (C_CMD_PUZZLE, "0000")),   -- 1
      (59, (C_CMD_PUZZLE, "0001")),   -- 2
      ( 8, (C_CMD_PUZZLE, "0010")),   -- 3
      (11, (C_CMD_PUZZLE, "0011")),   -- 4
      (16, (C_CMD_PUZZLE, "0100")),   -- 5
      (19, (C_CMD_PUZZLE, "0101")),   -- 6
      (24, (C_CMD_PUZZLE, "0110")),   -- 7
      (27, (C_CMD_PUZZLE, "0111")),   -- 8
      (32, (C_CMD_PUZZLE, "1000")));  -- 9

begin

   clk <= running and not clk after 5 ns;

   -- The keyboard driver: one key in each clock cycle
   p_driver : process (clk)
   begin
      if rising_edge(clk) then
         key_num <= (key_num + 1) mod 80;
      end if;
   end process p_driver;

   key_pressed_n <= not pressed(key_num);

   i_keys : entity work.keys
      port map (
         clk_i           => clk,
         key_num_i       => key_num,
         key_pressed_n_i => key_pressed_n,
         cmd_valid_o     => cmd_valid,
         cmd_o           => cmd
      ); -- i_keys

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
      -- Wait for some cycles through the keys
      procedure scans (n : natural) is
      begin
         for i in 1 to 80 * n loop
            wait until rising_edge(clk);
         end loop;
      end procedure scans;

      variable count_v : natural;
   begin
      scans(2);
      assert count = 0 report "A command without a key" severity failure;

      for k in C_KEYS'range loop
         count_v := count;
         pressed(C_KEYS(k).num) <= '1';
         scans(5);
         assert count = count_v + 1 and last = C_KEYS(k).cmd
            report "Key " & integer'image(C_KEYS(k).num) & ": " &
                   integer'image(count - count_v) & " commands, the last " &
                   to_string(to_slv(last))
            severity failure;
         pressed(C_KEYS(k).num) <= '0';
         scans(5);
         assert count = count_v + 1
            report "A command when key " & integer'image(C_KEYS(k).num) & " was released"
            severity failure;
      end loop;
      report "Each key: OK";

      -- Two keys at once: P is listed before 5
      count_v := count;
      pressed(16) <= '1';
      pressed(41) <= '1';
      scans(5);
      assert count = count_v + 1 and last = (C_CMD_PAUSE, "0000")
         report "P and 5: wrong command" severity failure;
      pressed(16) <= '0';
      pressed(41) <= '0';
      scans(2);
      report "Two keys: OK";

      -- Keys that are not used
      count_v := count;
      for k in 0 to 79 loop
         pressed(k) <= '1';
         for i in C_KEYS'range loop
            if C_KEYS(i).num = k then
               pressed(k) <= '0';
            end if;
         end loop;
      end loop;
      scans(5);
      assert count = count_v report "A command for a key that is not used" severity failure;
      report "Keys that are not used: OK";

      report "keys_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;

end architecture simulation;
