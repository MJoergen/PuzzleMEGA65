-- This module draws the text, in the VGA clock domain: 32 rows of 80
-- characters of 16x32 pixels (font_pkg.vhd), over the whole 1280x1024 screen.
-- For each pixel (pix_x_i, pix_y_i) it gives whether the pixel is part of a
-- character (on_o) and its colour (col_o), C_TEXT_LATENCY (7) clock cycles
-- later. The background of the text is transparent, so the board is seen
-- where there is no character (a space has no pixels).
--
-- The text memory holds the character at each position (row * 80 + column),
-- with its colour in the upper two bits (see status.vhd, which writes it with
-- wr_*): 0 white, 1 grey, 2 green, 3 yellow.
--
-- The stages:
--   1  The address of the character, and the position in it.
--   2  The read of the text memory.
--   3  The address of the row of the character in the font.
--   4  The read of the font.
--   5  The pixel and its colour.
--   6, 7  Delays, to match the latency of board.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.video_pkg.all;
use work.font_pkg.all;

entity text is
   port (
      clk_i     : in  std_logic;

      -- Write port of the text memory
      wr_en_i   : in  std_logic;
      wr_addr_i : in  std_logic_vector(11 downto 0);
      wr_data_i : in  std_logic_vector( 8 downto 0);

      pix_x_i   : in  std_logic_vector(10 downto 0);
      pix_y_i   : in  std_logic_vector(10 downto 0);
      col_o     : out std_logic_vector(23 downto 0);   -- RRGGBB
      on_o      : out std_logic
   );
end entity text;

architecture rtl of text is

   type colour_vector is array (0 to 3) of std_logic_vector(23 downto 0);
   constant C_COLOURS : colour_vector := (
      X"F0F0F8",    -- White
      X"8890B0",    -- Grey
      X"40F070",    -- Green
      X"F8D838");   -- Yellow

   -- The text memory, initially all spaces
   signal mem         : text_mem_t := (others => "0" & X"20");

   -- The font, a ROM
   signal font        : font_t := C_FONT;

   signal addr_r      : std_logic_vector(11 downto 0);
   signal vis_d1      : std_logic := '0';
   signal gx_d1       : std_logic_vector( 3 downto 0);
   signal gy_d1       : std_logic_vector( 4 downto 0);

   signal char_r      : std_logic_vector( 8 downto 0);
   signal vis_d2      : std_logic := '0';
   signal gx_d2       : std_logic_vector( 3 downto 0);
   signal gy_d2       : std_logic_vector( 4 downto 0);

   signal faddr_r     : std_logic_vector(11 downto 0);
   signal vis_d3      : std_logic := '0';
   signal gx_d3       : std_logic_vector( 3 downto 0);
   signal colour_d3   : std_logic_vector( 1 downto 0);

   signal frow_r      : std_logic_vector(15 downto 0);
   signal vis_d4      : std_logic := '0';
   signal gx_d4       : std_logic_vector( 3 downto 0);
   signal colour_d4   : std_logic_vector( 1 downto 0);

   signal on_d5       : std_logic := '0';
   signal col_d5      : std_logic_vector(23 downto 0);
   signal on_d6       : std_logic := '0';
   signal col_d6      : std_logic_vector(23 downto 0);
   signal on_d7       : std_logic := '0';
   signal col_d7      : std_logic_vector(23 downto 0);

begin

   p_write : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wr_en_i = '1' then
            mem(to_integer(wr_addr_i)) <= wr_data_i;
         end if;
      end if;
   end process p_write;

   p_stages : process (clk_i)
      variable row_v : std_logic_vector(11 downto 0);
   begin
      if rising_edge(clk_i) then
         -- Stage 1: row * 80 + column = row * 64 + row * 16 + column
         row_v  := "0000000" & pix_y_i(9 downto 5);
         addr_r <= (row_v(5 downto 0) & "000000") + (row_v(7 downto 0) & "0000") +
                   ("00000" & pix_x_i(10 downto 4));
         vis_d1 <= '0';
         if pix_x_i < 1280 and pix_y_i < 1024 then
            vis_d1 <= '1';
         end if;
         gx_d1  <= pix_x_i(3 downto 0);
         gy_d1  <= pix_y_i(4 downto 0);

         -- Stage 2
         char_r <= mem(to_integer(addr_r));
         vis_d2 <= vis_d1;
         gx_d2  <= gx_d1;
         gy_d2  <= gy_d1;

         -- Stage 3
         faddr_r   <= char_r(6 downto 0) & gy_d2;
         vis_d3    <= vis_d2;
         gx_d3     <= gx_d2;
         colour_d3 <= char_r(8 downto 7);

         -- Stage 4
         frow_r    <= font(to_integer(faddr_r));
         vis_d4    <= vis_d3;
         gx_d4     <= gx_d3;
         colour_d4 <= colour_d3;

         -- Stage 5: the leftmost pixel is bit 15
         on_d5  <= vis_d4 and frow_r(15 - to_integer(gx_d4));
         col_d5 <= C_COLOURS(to_integer(colour_d4));

         -- Stages 6 and 7
         on_d6  <= on_d5;
         col_d6 <= col_d5;
         on_d7  <= on_d6;
         col_d7 <= col_d6;
      end if;
   end process p_stages;

   col_o <= col_d7;
   on_o  <= on_d7;

end architecture rtl;
