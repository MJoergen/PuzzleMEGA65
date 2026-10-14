-- This is a self-checking testbench of the conversion to decimal (bcd.vhd),
-- with 48 bits and 15 digits, as in status.vhd. It converts the edge cases
-- (0, 1, 9, 10, the powers of ten and one less, and 2**48-1) and 1000 random
-- numbers, and compares the digits with a reference (repeated division by
-- ten), and checks that done_o comes 48 clock cycles after the clock cycle in
-- which start_i is high.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity bcd_tb is
end entity bcd_tb;

architecture simulation of bcd_tb is

   constant C_BITS   : natural := 48;
   constant C_DIGITS : natural := 15;

   signal clk     : std_logic := '0';
   signal running : std_logic := '1';
   signal start   : std_logic := '0';
   signal bin     : std_logic_vector(C_BITS-1 downto 0) := (others => '0');
   signal bcd     : std_logic_vector(4*C_DIGITS-1 downto 0);
   signal done    : std_logic;

   function to_bcd (v : unsigned) return std_logic_vector is
      variable v_v : unsigned(v'length-1 downto 0);
      variable r_v : std_logic_vector(4*C_DIGITS-1 downto 0);
   begin
      v_v := v;
      for d in 0 to C_DIGITS-1 loop
         r_v(4*d+3 downto 4*d) := std_logic_vector(resize(v_v mod 10, 4));
         v_v                   := v_v / 10;
      end loop;
      return r_v;
   end function to_bcd;

begin

   clk <= running and not clk after 5 ns;

   i_bcd : entity work.bcd
      generic map (
         G_BITS   => C_BITS,
         G_DIGITS => C_DIGITS
      )
      port map (
         clk_i   => clk,
         start_i => start,
         bin_i   => bin,
         bcd_o   => bcd,
         done_o  => done
      ); -- i_bcd

   p_test : process
      variable seed1_v : positive := 1;
      variable seed2_v : positive := 2;
      variable r_v     : real;
      variable v_v     : unsigned(C_BITS-1 downto 0);
      variable p_v     : unsigned(C_BITS-1 downto 0);
      variable n_v     : natural := 0;

      procedure convert (v : unsigned) is
         variable cycles_v : natural;
      begin
         bin   <= std_logic_vector(v);
         start <= '1';
         wait until rising_edge(clk);
         start    <= '0';
         cycles_v := 0;
         loop
            wait until rising_edge(clk);
            cycles_v := cycles_v + 1;
            exit when done = '1';
         end loop;
         -- The loop sees done_o one clock cycle after it is set
         assert cycles_v = C_BITS + 1
            report "done_o after " & integer'image(cycles_v - 1) & " clock cycles"
            severity failure;
         assert bcd = to_bcd(v)
            report "The conversion of " & to_hstring(v) & " is " & to_hstring(bcd) &
                   ", expected " & to_hstring(to_bcd(v))
            severity failure;
         n_v := n_v + 1;
      end procedure convert;
   begin
      wait until rising_edge(clk);

      -- The edge cases
      convert(to_unsigned(0, C_BITS));
      p_v := to_unsigned(1, C_BITS);
      for i in 0 to 14 loop
         convert(p_v);
         if p_v > 1 then
            convert(p_v - 1);
         end if;
         exit when i = 14;
         p_v := resize(p_v * 10, C_BITS);
      end loop;
      convert((C_BITS-1 downto 0 => '1'));

      -- Random numbers, with a random number of bits
      for i in 1 to 1000 loop
         for b in 0 to C_BITS-1 loop
            uniform(seed1_v, seed2_v, r_v);
            v_v(b) := '0';
            if r_v > 0.5 then
               v_v(b) := '1';
            end if;
         end loop;
         uniform(seed1_v, seed2_v, r_v);
         v_v := shift_right(v_v, integer(trunc(r_v * real(C_BITS))));
         convert(v_v);
      end loop;

      report "Converted " & integer'image(n_v) & " numbers";
      report "bcd_tb: finished";
      running <= '0';
      std.env.finish;
   end process p_test;

end architecture simulation;
