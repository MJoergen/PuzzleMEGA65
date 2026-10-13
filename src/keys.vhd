-- This module turns the keys of the MEGA65 keyboard into the commands of the
-- search (see ctrl_pkg.vhd and control.vhd):
--   A  search all positions       N  search for the next solution
--   S  search slowly              O  one step
--   P  pause                      1 to 9  select a puzzle
--
-- The keyboard is read by the MiSTer2MEGA65 keyboard driver (m2m_keyb.vhd,
-- in src/keyboard/), here in the VGA clock domain, which cycles through all
-- the keys (key_num_i), and shows whether each of them is pressed
-- (key_pressed_n_i, active low). The keys that are used are stored here. At
-- the end of each cycle through the keys (key 79, about once a millisecond),
-- a key that has just been pressed (it was not pressed in the cycle before)
-- gives a command (cmd_valid_o for one clock cycle). If several keys have
-- just been pressed, the one listed first in C_KEYS wins, and the others are
-- ignored. The key numbers are those of the MiSTer2MEGA65 framework, see
-- matrix_to_keynum.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.ctrl_pkg.all;

entity keys is
   port (
      clk_i           : in  std_logic;

      -- From the keyboard driver
      key_num_i       : in  natural range 0 to 79;
      key_pressed_n_i : in  std_logic;

      cmd_valid_o     : out std_logic;
      cmd_o           : out cmd_t
   );
end entity keys;

architecture rtl of keys is

   -- The keys that are used: the key number, and the command
   type key_t is record
      num : natural range 0 to 79;
      cmd : cmd_t;
   end record key_t;

   type key_vector is array (natural range <>) of key_t;

   constant C_KEYS : key_vector := (
      (41, (C_CMD_PAUSE,  "0000")),   -- P
      (10, (C_CMD_ALL,    "0000")),   -- A
      (39, (C_CMD_NEXT,   "0000")),   -- N
      (13, (C_CMD_SLOW,   "0000")),   -- S
      (38, (C_CMD_STEP,   "0000")),   -- O
      (56, (C_CMD_PUZZLE, "0000")),   -- 1
      (59, (C_CMD_PUZZLE, "0001")),   -- 2
      ( 8, (C_CMD_PUZZLE, "0010")),   -- 3
      (11, (C_CMD_PUZZLE, "0011")),   -- 4
      (16, (C_CMD_PUZZLE, "0100")),   -- 5
      (19, (C_CMD_PUZZLE, "0101")),   -- 6
      (24, (C_CMD_PUZZLE, "0110")),   -- 7
      (27, (C_CMD_PUZZLE, "0111")),   -- 8
      (32, (C_CMD_PUZZLE, "1000")));  -- 9

   constant C_KEY_LAST : natural := 79;

   -- The keys that are pressed now, and in the last cycle through the keys
   signal pressed_r   : std_logic_vector(C_KEYS'range) := (others => '0');
   signal last_r      : std_logic_vector(C_KEYS'range) := (others => '0');

   signal cmd_valid_r : std_logic := '0';
   signal cmd_r       : cmd_t := (C_CMD_PAUSE, "0000");

begin

   p_keys : process (clk_i)
   begin
      if rising_edge(clk_i) then
         for k in C_KEYS'range loop
            if key_num_i = C_KEYS(k).num then
               pressed_r(k) <= not key_pressed_n_i;
            end if;
         end loop;
      end if;
   end process p_keys;

   p_cmd : process (clk_i)
   begin
      if rising_edge(clk_i) then
         cmd_valid_r <= '0';
         if key_num_i = C_KEY_LAST then
            last_r <= pressed_r;
            for k in C_KEYS'reverse_range loop
               if pressed_r(k) = '1' and last_r(k) = '0' then
                  cmd_valid_r <= '1';
                  cmd_r       <= C_KEYS(k).cmd;
               end if;
            end loop;
         end if;
      end if;
   end process p_cmd;

   cmd_valid_o <= cmd_valid_r;
   cmd_o       <= cmd_r;

end architecture rtl;
