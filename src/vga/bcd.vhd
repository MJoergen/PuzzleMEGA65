-- This module converts a binary number (bin_i, G_BITS bits) to decimal
-- (bcd_o, G_DIGITS digits of 4 bits, the lowest digit in the lowest bits),
-- with the double dabble algorithm: one bit per clock cycle, so it takes
-- G_BITS clock cycles after start_i, and then done_o is high for one clock
-- cycle. A start during a conversion starts a new one. In each clock cycle,
-- every digit that is 5 or more gets 3 added, and then the digits and the
-- remaining bits of the number are shifted left by one bit. G_DIGITS must be
-- large enough for the number, i.e. 10**G_DIGITS >= 2**G_BITS.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

entity bcd is
   generic (
      G_BITS   : positive;
      G_DIGITS : positive
   );
   port (
      clk_i   : in  std_logic;
      start_i : in  std_logic;
      bin_i   : in  std_logic_vector(G_BITS-1 downto 0);
      bcd_o   : out std_logic_vector(4*G_DIGITS-1 downto 0);
      done_o  : out std_logic
   );
end entity bcd;

architecture rtl of bcd is

   signal bin_r  : std_logic_vector(G_BITS-1 downto 0);
   signal bcd_r  : std_logic_vector(4*G_DIGITS-1 downto 0);
   signal cnt_r  : natural range 0 to G_BITS := 0;
   signal done_r : std_logic := '0';

begin

   assert 10.0**G_DIGITS >= 2.0**G_BITS
      report "Too few digits"
      severity failure;

   p_bcd : process (clk_i)
      variable bcd_v : std_logic_vector(4*G_DIGITS-1 downto 0);
   begin
      if rising_edge(clk_i) then
         done_r <= '0';
         if cnt_r /= 0 then
            bcd_v := bcd_r;
            for d in 0 to G_DIGITS-1 loop
               if bcd_v(4*d+3 downto 4*d) >= 5 then
                  bcd_v(4*d+3 downto 4*d) := bcd_v(4*d+3 downto 4*d) + 3;
               end if;
            end loop;
            bcd_r <= bcd_v(4*G_DIGITS-2 downto 0) & bin_r(G_BITS-1);
            bin_r <= bin_r(G_BITS-2 downto 0) & '0';
            cnt_r <= cnt_r - 1;
            if cnt_r = 1 then
               done_r <= '1';
            end if;
         end if;

         -- A start also stops a conversion, without done_o
         if start_i = '1' then
            bin_r  <= bin_i;
            bcd_r  <= (others => '0');
            cnt_r  <= G_BITS;
            done_r <= '0';
         end if;
      end if;
   end process p_bcd;

   bcd_o  <= bcd_r;
   done_o <= done_r;

end architecture rtl;
