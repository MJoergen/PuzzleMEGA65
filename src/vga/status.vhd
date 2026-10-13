-- This module writes the text of the screen to the text memory of text.vhd,
-- in the VGA clock domain, once for each frame (frame_i, at the start of the
-- vertical blanking): the puzzle and the status at the top, the statistics
-- below the board (see ctrl_pkg.vhd), and the keys (G_HELP) at the bottom.
-- The screen has 32 rows of 80 characters (16x32 pixels each, see text.vhd).
--
-- First the five numbers are converted to decimal, one after the other, by
-- bcd.vhd (48 clock cycles each). Then all 2560 characters are written, one
-- per clock cycle: each is either from the template (C_TEMPLATE, the labels)
-- or from a field (C_FIELDS), which is a number (right-aligned, with the
-- leading zeros blanked, and commas between the groups of three digits, or
-- a decimal point), or a text (the puzzle and the status). This takes less
-- than 3,000 clock cycles, much less than the vertical blanking (45,000).
--
-- Each character has a colour (the upper two bits of the entry of the text
-- memory, see text.vhd): 0 white for the values, 1 grey for the labels, 2
-- green for "ALL SOLUTIONS FOUND", and 3 yellow for "Solution found".

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity status is
   generic (
      G_HELP    : string                             -- The keys, at most 76 characters
   );
   port (
      clk_i     : in  std_logic;
      frame_i   : in  std_logic;
      stats_i   : in  stats_t;

      -- Write port of the text memory
      wr_en_o   : out std_logic;
      wr_addr_o : out std_logic_vector(11 downto 0);  -- row * 80 + column
      wr_data_o : out std_logic_vector( 8 downto 0)   -- Colour & character
   );
end entity status;

architecture rtl of status is

   constant C_COLS   : natural := 80;
   constant C_ROWS   : natural := 32;

   subtype row_t is string(1 to C_COLS);
   type template_t is array (0 to C_ROWS-1) of row_t;

   -- A row with the text s at the column col (counted from 0)
   function at (r : row_t; col : natural; s : string) return row_t is
      variable r_v : row_t;
   begin
      r_v := r;
      for i in 0 to s'length-1 loop
         r_v(col + 1 + i) := s(s'low + i);
      end loop;
      return r_v;
   end function at;

   constant C_BLANK  : row_t := (others => ' ');

   function template return template_t is
      variable t_v : template_t;
   begin
      t_v     := (others => C_BLANK);
      t_v(1)  := at(C_BLANK, 2, "Puzzle");
      t_v(26) := at(at(C_BLANK, 2, "Positions considered"), 47, "Solutions found");
      t_v(27) := at(at(at(C_BLANK, 2, "Positions per second"), 47, "Progress"), 75, "%");
      t_v(28) := at(at(C_BLANK, 2, "Time searching"), 41, "s");
      t_v(30) := at(C_BLANK, 2, G_HELP);
      return t_v;
   end function template;

   constant C_TEMPLATE : template_t := template;

   -- The fields: the row, the first column, the width, and the kind
   constant F_NONE   : natural := 0;
   constant F_NUM    : natural := 1;   -- The number of the puzzle (1 to 9)
   constant F_NAME   : natural := 2;   -- The size, e.g. "8x8"
   constant F_TITLE  : natural := 3;   -- The pieces
   constant F_STATUS : natural := 4;
   constant F_POS    : natural := 5;   -- Positions considered
   constant F_SOL    : natural := 6;   -- Solutions found
   constant F_RATE   : natural := 7;   -- Positions per second
   constant F_PROG   : natural := 8;   -- Progress, in per mille, as 100.0
   constant F_TIME   : natural := 9;   -- Time, in tenths of seconds, as 12.3

   type field_t is record
      row   : natural;
      col   : natural;
      width : natural;
      kind  : natural;
   end record field_t;

   type field_vector is array (natural range <>) of field_t;

   constant C_FIELDS : field_vector := (
      ( 1,  9,  1, F_NUM),
      ( 1, 13,  5, F_NAME),
      ( 1, 20, 30, F_TITLE),
      ( 1, 51, 27, F_STATUS),
      (26, 23, 19, F_POS),
      (26, 63, 13, F_SOL),
      (27, 28, 14, F_RATE),
      (27, 69,  5, F_PROG),
      (28, 31,  9, F_TIME));

   -- The texts of the status (see ctrl_pkg.vhd), right-aligned
   type status_vector is array (0 to 7) of string(1 to 27);

   constant C_STATUS : status_vector := (
      "                     Paused",
      "    Searching all positions",
      "Searching for next solution",
      "           Searching slowly",
      "             Solution found",
      "        ALL SOLUTIONS FOUND",
      "                           ",
      "                           ");

   -- The numbers, as decimal digits (4 bits each, the lowest digit lowest)
   constant C_DIGITS : natural := 15;
   type digits_vector is array (0 to 4) of std_logic_vector(4*C_DIGITS-1 downto 0);

   type state_t is (IDLE_ST, CONV_ST, WRITE_ST);

   signal state_r    : state_t := IDLE_ST;
   signal stats_r    : stats_t := C_STATS_INIT;
   signal num_r      : natural range 0 to 4;
   signal start_r    : std_logic := '0';
   signal bin_r      : std_logic_vector(47 downto 0);
   signal bcd        : std_logic_vector(4*C_DIGITS-1 downto 0);
   signal bcd_done   : std_logic;
   signal digits_r   : digits_vector;

   signal row_r      : natural range 0 to C_ROWS-1;
   signal col_r      : natural range 0 to C_COLS-1;
   signal addr_r     : natural range 0 to C_ROWS*C_COLS-1;

   -- The pipeline of the writing: the position, and the field there
   signal valid_d    : std_logic := '0';
   signal addr_d     : natural range 0 to C_ROWS*C_COLS-1;
   signal tmpl_d     : character;
   signal kind_d     : natural range 0 to 9;
   signal index_d    : natural range 0 to 31;     -- From the left of the field
   signal from_r_d   : natural range 0 to 31;     -- From the right of the field

   signal wr_en_r    : std_logic := '0';
   signal wr_addr_r  : std_logic_vector(11 downto 0);
   signal wr_data_r  : std_logic_vector( 8 downto 0);

   -- The character of a number at the position k from the right of its
   -- field: digits with commas between the groups of three, and the leading
   -- zeros (and their commas) blank
   function number_char (d : std_logic_vector; k : natural) return character is
      variable d_v   : std_logic_vector(4*C_DIGITS-1 downto 0);
      variable n_v   : natural;                    -- The significant digits
      variable i_v   : natural;
   begin
      d_v := d;
      n_v := 1;
      for i in 0 to C_DIGITS-1 loop
         if d_v(4*i+3 downto 4*i) /= "0000" then
            n_v := i + 1;
         end if;
      end loop;
      if k mod 4 = 3 then
         i_v := 3 * (k / 4 + 1);                   -- The digit after the comma
         if i_v < n_v then
            return ',';
         end if;
         return ' ';
      end if;
      i_v := 3 * (k / 4) + k mod 4;
      if i_v < n_v and i_v < C_DIGITS then
         return character'val(48 + to_integer(d_v(4*i_v+3 downto 4*i_v)));
      end if;
      return ' ';
   end function number_char;

   -- The same for a number with one decimal, e.g. 12.3 for 123: the decimal
   -- point is at the position 1 from the right, and there is always a digit
   -- before it
   function decimal_char (d : std_logic_vector; k : natural) return character is
      variable d_v   : std_logic_vector(4*C_DIGITS-1 downto 0);
      variable n_v   : natural;
      variable i_v   : natural;
   begin
      d_v := d;
      n_v := 2;
      for i in 0 to C_DIGITS-1 loop
         if d_v(4*i+3 downto 4*i) /= "0000" and i + 1 > n_v then
            n_v := i + 1;
         end if;
      end loop;
      if k = 1 then
         return '.';
      end if;
      i_v := k;
      if k > 1 then
         i_v := k - 1;
      end if;
      if i_v < n_v and i_v < C_DIGITS then
         return character'val(48 + to_integer(d_v(4*i_v+3 downto 4*i_v)));
      end if;
      return ' ';
   end function decimal_char;

begin

   i_bcd : entity work.bcd
      generic map (
         G_BITS   => 48,
         G_DIGITS => C_DIGITS
      )
      port map (
         clk_i   => clk_i,
         start_i => start_r,
         bin_i   => bin_r,
         bcd_o   => bcd,
         done_o  => bcd_done
      ); -- i_bcd

   p_fsm : process (clk_i)
      variable kind_v : natural range 0 to 9;
      variable index_v : natural range 0 to 31;
      variable from_r_v : natural range 0 to 31;
   begin
      if rising_edge(clk_i) then
         start_r <= '0';
         valid_d <= '0';

         case state_r is
            when IDLE_ST =>
               if frame_i = '1' then
                  stats_r <= stats_i;
                  num_r   <= 0;
                  bin_r   <= stats_i.positions;
                  start_r <= '1';
                  state_r <= CONV_ST;
               end if;

            -- The numbers, one after the other
            when CONV_ST =>
               if bcd_done = '1' then
                  digits_r(num_r) <= bcd;
                  start_r         <= '1';
                  case num_r is
                     when 0      => bin_r <= resize(stats_r.solutions, 48);
                     when 1      => bin_r <= resize(stats_r.rate, 48);
                     when 2      => bin_r <= resize(stats_r.progress, 48);
                     when 3      => bin_r <= resize(stats_r.time, 48);
                     when others => start_r <= '0';
                  end case;
                  if num_r = 4 then
                     row_r   <= 0;
                     col_r   <= 0;
                     addr_r  <= 0;
                     state_r <= WRITE_ST;
                  else
                     num_r <= num_r + 1;
                  end if;
               end if;

            -- Each character: find the field at the position
            when WRITE_ST =>
               kind_v   := F_NONE;
               index_v  := 0;
               from_r_v := 0;
               for f in C_FIELDS'range loop
                  if row_r = C_FIELDS(f).row and col_r >= C_FIELDS(f).col and
                     col_r < C_FIELDS(f).col + C_FIELDS(f).width
                  then
                     kind_v   := C_FIELDS(f).kind;
                     index_v  := col_r - C_FIELDS(f).col;
                     from_r_v := C_FIELDS(f).col + C_FIELDS(f).width - 1 - col_r;
                  end if;
               end loop;
               valid_d  <= '1';
               addr_d   <= addr_r;
               tmpl_d   <= C_TEMPLATE(row_r)(col_r + 1);
               kind_d   <= kind_v;
               index_d  <= index_v;
               from_r_d <= from_r_v;

               if addr_r = C_ROWS*C_COLS-1 then
                  state_r <= IDLE_ST;
               else
                  addr_r <= addr_r + 1;
               end if;
               if col_r = C_COLS-1 then
                  col_r <= 0;
                  row_r <= (row_r + 1) mod C_ROWS;
               else
                  col_r <= col_r + 1;
               end if;
         end case;
      end if;
   end process p_fsm;

   -- The character and its colour
   p_write : process (clk_i)
      variable c_v   : character;
      variable col_v : std_logic_vector(1 downto 0);
      variable p_v   : natural range 0 to C_NUM_PUZZLES-1;
      variable s_v   : natural range 0 to 7;
   begin
      if rising_edge(clk_i) then
         p_v   := to_integer(stats_r.puzzle) mod C_NUM_PUZZLES;
         s_v   := to_integer(stats_r.status);
         c_v   := tmpl_d;
         col_v := "01";
         case kind_d is
            when F_NUM    =>
               c_v   := character'val(49 + p_v);
               col_v := "00";
            when F_NAME   =>
               c_v   := C_PUZZLES(p_v).name(index_d + 1);
               col_v := "00";
            when F_TITLE  =>
               c_v   := C_PUZZLES(p_v).title(index_d + 1);
               col_v := "00";
            when F_STATUS =>
               c_v   := C_STATUS(s_v)(index_d + 1);
               col_v := "00";
               if stats_r.status = C_ST_FINISHED then
                  col_v := "10";
               elsif stats_r.status = C_ST_SOLUTION then
                  col_v := "11";
               end if;
            when F_POS    =>
               c_v   := number_char(digits_r(0), from_r_d);
               col_v := "00";
            when F_SOL    =>
               c_v   := number_char(digits_r(1), from_r_d);
               col_v := "00";
            when F_RATE   =>
               c_v   := number_char(digits_r(2), from_r_d);
               col_v := "00";
            when F_PROG   =>
               c_v   := decimal_char(digits_r(3), from_r_d);
               col_v := "00";
            when F_TIME   =>
               c_v   := decimal_char(digits_r(4), from_r_d);
               col_v := "00";
            when others   =>
               null;
         end case;
         wr_en_r   <= valid_d;
         wr_addr_r <= to_slv(addr_d, 12);
         wr_data_r <= col_v & to_slv(character'pos(c_v) mod 128, 7);
      end if;
   end process p_write;

   wr_en_o   <= wr_en_r;
   wr_addr_o <= wr_addr_r;
   wr_data_o <= wr_data_r;

end architecture rtl;
