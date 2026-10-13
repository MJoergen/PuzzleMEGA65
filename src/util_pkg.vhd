-- This package has the functions on bit vectors that are used in several
-- modules, e.g. for the widths of the signals, and for the priority logic of
-- the engine (engine.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

package util_pkg is

   type natural_vector is array (natural range <>) of natural;

   -- The largest element
   function max_of (v : natural_vector) return natural;

   -- The number of bits needed for the values 0 to n-1, e.g. 2 for 3 or 4,
   -- and 0 for 0 or 1
   function log2 (n : natural) return natural;

   -- The lowest bit that is set, as a one-hot vector (all zeros if no bit is
   -- set). A vector of up to 32 bits is done as v and -v, i.e. a carry chain.
   -- A longer vector is split into groups of 8 bits, so that the carry chains
   -- are short: the lowest group with a bit set, and the lowest bit in each
   -- group.
   function lowest_one (v : std_logic_vector) return std_logic_vector;

   -- The number of trailing ones of v, i.e. the index of its lowest zero, where
   -- a zero is appended beyond v, so the result is v'length if all the bits
   -- are set. The vector is split into groups of 8 bits: the lowest group
   -- that is not full, and the number of trailing ones of each group.
   function trailing_ones (v : std_logic_vector) return natural;

   -- The index of the bit that is set in a one-hot vector (0 if no bit is
   -- set), as a binary number of the given number of bits. Each bit of the
   -- result is an OR of the bits of the one-hot vector (the OR of the indices
   -- of all the bits that are set).
   function encode (v : std_logic_vector; bits : natural) return std_logic_vector;

   -- '1' for true, '0' for false
   function to_sl (b : boolean) return std_logic;

end package util_pkg;

package body util_pkg is

   function max_of (v : natural_vector) return natural is
      variable r_v : natural := 0;
   begin
      for i in v'range loop
         if v(i) > r_v then
            r_v := v(i);
         end if;
      end loop;
      return r_v;
   end function max_of;

   function log2 (n : natural) return natural is
      variable r_v : natural := 0;
   begin
      while 2**r_v < n loop
         r_v := r_v + 1;
      end loop;
      return r_v;
   end function log2;

   function lowest_one (v : std_logic_vector) return std_logic_vector is
      constant C_LEN : natural := v'length;
      constant C_NG  : natural := (C_LEN + 7) / 8;
      variable v_v   : std_logic_vector(8*C_NG-1 downto 0);
      variable g_v   : std_logic_vector(7 downto 0);
      variable any_v : std_logic_vector(C_NG-1 downto 0);
      variable sel_v : std_logic_vector(C_NG-1 downto 0);
      variable r_v   : std_logic_vector(8*C_NG-1 downto 0);
   begin
      v_v                   := (others => '0');
      v_v(C_LEN-1 downto 0) := v;
      if C_LEN <= 32 then
         return v_v(C_LEN-1 downto 0) and ((not v_v(C_LEN-1 downto 0)) + 1);
      end if;
      for g in 0 to C_NG-1 loop
         any_v(g) := or v_v(8*g+7 downto 8*g);
      end loop;
      sel_v := any_v and ((not any_v) + 1);
      for g in 0 to C_NG-1 loop
         g_v                   := v_v(8*g+7 downto 8*g);
         r_v(8*g+7 downto 8*g) := g_v and ((not g_v) + 1) and (7 downto 0 => sel_v(g));
      end loop;
      return r_v(C_LEN-1 downto 0);
   end function lowest_one;

   function trailing_ones (v : std_logic_vector) return natural is
      constant C_NG  : natural := v'length / 8 + 1;  -- With the appended zero
      variable v_v   : std_logic_vector(8*C_NG-1 downto 0);
      variable nf_v  : std_logic_vector(C_NG-1 downto 0);
      variable sel_v : std_logic_vector(C_NG-1 downto 0);
      variable lo_v  : std_logic_vector(2 downto 0);
      variable n_v   : natural range 0 to 7;
   begin
      v_v                      := (others => '0');
      v_v(v'length-1 downto 0) := v;
      for g in 0 to C_NG-1 loop
         nf_v(g) := not (and v_v(8*g+7 downto 8*g));
      end loop;
      sel_v := lowest_one(nf_v);
      lo_v  := "000";
      for g in 0 to C_NG-1 loop
         -- The trailing ones of the group (it is not full when it is selected),
         -- ORed in for the selected group
         n_v := 0;
         for i in 7 downto 0 loop
            if v_v(8*g + i) = '0' then
               n_v := i;
            end if;
         end loop;
         lo_v := lo_v or (to_slv(n_v, 3) and (2 downto 0 => sel_v(g)));
      end loop;
      if C_NG = 1 then
         return to_integer(lo_v);
      end if;
      return to_integer(encode(sel_v, log2(C_NG)) & lo_v);
   end function trailing_ones;

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

   function to_sl (b : boolean) return std_logic is
   begin
      if b then
         return '1';
      end if;
      return '0';
   end function to_sl;

end package body util_pkg;
