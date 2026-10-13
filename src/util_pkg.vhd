-- This package has the functions on bit vectors that are used in several
-- modules, e.g. for the widths of the signals, and for the priority logic of
-- the engine (engine.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

package util_pkg is

   -- The number of bits needed for the values 0 to n-1, e.g. 2 for 3 or 4,
   -- and 0 for 0 or 1
   function log2 (n : natural) return natural;

   -- The lowest bit that is set, as a one-hot vector (all zeros if no bit is
   -- set). This is v and -v, i.e. a carry chain.
   function lowest_one (v : std_logic_vector) return std_logic_vector;

   -- The index of the bit that is set in a one-hot vector (0 if no bit is
   -- set), as a binary number of the given number of bits. Each bit of the
   -- result is an OR of the bits of the one-hot vector (the OR of the indices
   -- of all the bits that are set).
   function encode (v : std_logic_vector; bits : natural) return std_logic_vector;

end package util_pkg;

package body util_pkg is

   function log2 (n : natural) return natural is
      variable r_v : natural := 0;
   begin
      while 2**r_v < n loop
         r_v := r_v + 1;
      end loop;
      return r_v;
   end function log2;

   function lowest_one (v : std_logic_vector) return std_logic_vector is
      variable v_v : std_logic_vector(v'length-1 downto 0);
   begin
      v_v := v;
      return v_v and ((not v_v) + 1);
   end function lowest_one;

   function encode (v : std_logic_vector; bits : natural) return std_logic_vector is
      variable v_v : std_logic_vector(v'length-1 downto 0);
      variable r_v : std_logic_vector(bits-1 downto 0);
   begin
      v_v := v;
      r_v := (others => '0');
      for i in 0 to v'length-1 loop
         if v_v(i) = '1' then
            r_v := r_v or to_slv(i, bits);
         end if;
      end loop;
      return r_v;
   end function encode;

end package body util_pkg;
