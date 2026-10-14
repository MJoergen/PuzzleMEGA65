-- This module turns the buttons and switches of the Nexys 4 DDR into the
-- commands of the search (see ctrl_pkg.vhd and control.vhd), in the VGA
-- clock domain:
--   BTNU  search all positions        BTNR  search for the next solution
--   BTNL  search slowly               BTND  one step
--   BTNC  pause
--   SW3 to SW0  the puzzle, as a binary number: 1 to 9 select the puzzles
--               1 to 9, 0 selects puzzle 1, and 10 to 15 select puzzle 9.
--
-- The buttons and switches are asynchronous, so they are synchronized with
-- two registers, and then debounced: a new value is only taken when it has
-- been the same for G_DEBOUNCE clock cycles (about 10 ms). A button gives a
-- command when it has just been pressed, and the switches give a command
-- when the puzzle they select changes. The switches are also taken once
-- after power-on (so the puzzle of the switches is selected). If several
-- commands come in the same clock cycle, the switches win, then the buttons in
-- the order above.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.ctrl_pkg.all;

entity buttons is
   generic (
      G_DEBOUNCE : positive                          -- Clock cycles
   );
   port (
      clk_i       : in  std_logic;
      btn_i       : in  std_logic_vector(4 downto 0); -- "CLRUD"
      sw_i        : in  std_logic_vector(3 downto 0);
      cmd_valid_o : out std_logic;
      cmd_o       : out cmd_t
   );
end entity buttons;

architecture rtl of buttons is

   -- The inputs: the buttons (4 downto 0) and the switches (8 downto 5)
   signal in_meta     : std_logic_vector(8 downto 0) := (others => '0');
   signal in_sync     : std_logic_vector(8 downto 0) := (others => '0');
   signal last_r      : std_logic_vector(8 downto 0) := (others => '0');
   signal cnt_r       : natural range 0 to G_DEBOUNCE-1 := 0;
   signal stable_r    : std_logic_vector(8 downto 0) := (others => '0');
   signal stable_d    : std_logic_vector(8 downto 0) := (others => '0');
   signal first_r     : std_logic := '1';   -- Until the first stable value
   signal init_r      : std_logic := '0';   -- The first stable value is there

   signal cmd_valid_r : std_logic := '0';
   signal cmd_r       : cmd_t := (C_CMD_PAUSE, "0000");

   attribute async_reg : string;
   attribute async_reg of in_meta : signal is "true";
   attribute async_reg of in_sync : signal is "true";

   -- The puzzle (0 to 8) of the switches
   function puzzle (sw : std_logic_vector(3 downto 0)) return std_logic_vector is
   begin
      if sw = "0000" then
         return "0000";
      elsif sw > 9 then
         return "1000";
      end if;
      return sw - 1;
   end function puzzle;

begin

   p_debounce : process (clk_i)
   begin
      if rising_edge(clk_i) then
         in_meta <= sw_i & btn_i;
         in_sync <= in_meta;
         last_r  <= in_sync;
         init_r  <= '0';
         if in_sync /= last_r then
            cnt_r <= 0;
         elsif cnt_r = G_DEBOUNCE-1 then
            stable_r <= in_sync;
            init_r   <= first_r;
            first_r  <= '0';
         else
            cnt_r <= cnt_r + 1;
         end if;
         stable_d <= stable_r;
      end if;
   end process p_debounce;

   p_cmd : process (clk_i)
   begin
      if rising_edge(clk_i) then
         cmd_valid_r <= '0';
         if stable_r(3) = '1' and stable_d(3) = '0' then                                      -- BTNL
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_SLOW, "0000");
         end if;
         if stable_r(4) = '1' and stable_d(4) = '0' then                                      -- BTNC
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_PAUSE, "0000");
         end if;
         if stable_r(0) = '1' and stable_d(0) = '0' then                                      -- BTND
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_STEP, "0000");
         end if;
         if stable_r(2) = '1' and stable_d(2) = '0' then                                      -- BTNR
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_NEXT, "0000");
         end if;
         if stable_r(1) = '1' and stable_d(1) = '0' then                                      -- BTNU
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_ALL, "0000");
         end if;
         if puzzle(stable_r(8 downto 5)) /= puzzle(stable_d(8 downto 5)) or init_r = '1' then
            cmd_valid_r <= '1';
            cmd_r       <= (C_CMD_PUZZLE, puzzle(stable_r(8 downto 5)));
         end if;
      end if;
   end process p_cmd;

   cmd_valid_o <= cmd_valid_r;
   cmd_o       <= cmd_r;

end architecture rtl;
