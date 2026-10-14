-- This module draws the board, in the VGA clock domain: for each pixel
-- (pix_x_i, pix_y_i) it gives the colour (col_o) and whether the pixel is on
-- the board or its frame (on_o), seven clock cycles later (C_BOARD_LATENCY
-- in video_pkg.vhd).
-- The picture is exactly that of tools/render.py, which also describes how the
-- pieces are drawn: square by square, each square in four quadrants, with the
-- outline, the rim, and the fill of the piece decided from the distances to
-- the edges of the square and the neighbours that have the same piece. The
-- sizes (in pixels) depend on the size of a square of the puzzle, see
-- geometry() in render.py.
--
-- The board picture (the piece and the neighbour mask of each square, see
-- snapshot.vhd) is read from the board memory (rd_addr_o and rd_data_i, the
-- buffer buf_i), with a read latency of one clock cycle. The puzzle (puzzle_i)
-- and the buffer only change during the vertical blanking.
--
-- The pixel counters are those of pix.vhd: pix_x_i counts up by one in each
-- clock cycle, and pix_y_i by one at the start of each line (pix_x_i = 0).
-- The square and the position in the square are counted along with them, so
-- no division is needed.
--
-- The stages:
--   1  The square (row and column) and the position in it (u and v), and
--      whether the pixel is in the frame.
--   2  The address of the square in the board memory.
--   3  The read of the board memory (one clock cycle).
--   4  The quadrant, the distances a and b, and the three neighbours.
--   5  The distances p and q to the boundary of the piece, and the squares
--      of the distances to the centres of the round corners.
--   6  The part of the piece: outside, outline, rim, or fill.
--   7  The colour.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;
use work.palette_pkg.all;

entity board is
   port (
      clk_i     : in  std_logic;
      pix_x_i   : in  std_logic_vector(10 downto 0);
      pix_y_i   : in  std_logic_vector(10 downto 0);
      puzzle_i  : in  natural range 0 to C_NUM_PUZZLES-1;
      buf_i     : in  std_logic;

      rd_addr_o : out std_logic_vector(8 downto 0);
      rd_data_i : in  std_logic_vector(12 downto 0);

      col_o     : out std_logic_vector(23 downto 0);   -- RRGGBB
      on_o      : out std_logic
   );
end entity board;

architecture rtl of board is

   -- The sizes of each puzzle, in pixels, see geometry() in tools/render.py
   type geom_t is record
      rows : natural range 0 to C_MAX_ROWS;
      cols : natural range 0 to C_MAX_COLS;
      cell : natural range 0 to C_MAX_CELL;
      half : natural range 0 to C_MAX_CELL;
      x0   : natural range 0 to 2047;
      y0   : natural range 0 to 2047;
      x1   : natural range 0 to 2047;           -- Right of the last square
      y1   : natural range 0 to 2047;
      g    : natural range 0 to 15;             -- Gap
      r    : natural range 0 to 31;             -- Radius
      bw   : natural range 0 to 15;             -- Outline
      rim  : natural range 0 to 15;
      br   : natural range 0 to 31;             -- Outline and rim
      -- The squares of the distances that stage 6 compares with, so that
      -- they are constants (not products of the registered geometry)
      bw2  : natural range 0 to 255;            -- bw * bw
      br2  : natural range 0 to 1023;           -- br * br
      r2   : natural range 0 to 1023;           -- r * r
      rbw2 : natural range 0 to 1023;           -- (r - bw) * (r - bw)
      rbr2 : natural range 0 to 1023;           -- (r - br) * (r - br)
   end record geom_t;

   type geom_vector is array (0 to C_NUM_PUZZLES-1) of geom_t;

   function geometries return geom_vector is
      variable r_v : geom_vector;
      variable p_v : puzzle_t;
   begin
      for i in 0 to C_NUM_PUZZLES-1 loop
         p_v         := C_PUZZLES(i);
         r_v(i).rows := p_v.rows;
         r_v(i).cols := p_v.cols;
         r_v(i).cell := p_v.cell;
         r_v(i).half := p_v.cell / 2;
         r_v(i).x0   := p_v.x0;
         r_v(i).y0   := p_v.y0;
         r_v(i).x1   := p_v.x0 + p_v.cols * p_v.cell;
         r_v(i).y1   := p_v.y0 + p_v.rows * p_v.cell;
         r_v(i).g    := maximum(2, p_v.cell / 24);
         r_v(i).r    := p_v.cell / 4;
         r_v(i).bw   := maximum(2, p_v.cell / 22);
         r_v(i).rim  := maximum(1, p_v.cell / 30);
         r_v(i).br   := r_v(i).bw + r_v(i).rim;
         r_v(i).bw2  := r_v(i).bw * r_v(i).bw;
         r_v(i).br2  := r_v(i).br * r_v(i).br;
         r_v(i).r2   := r_v(i).r * r_v(i).r;
         r_v(i).rbw2 := (r_v(i).r - r_v(i).bw) * (r_v(i).r - r_v(i).bw);
         r_v(i).rbr2 := (r_v(i).r - r_v(i).br) * (r_v(i).r - r_v(i).br);
      end loop;
      return r_v;
   end function geometries;

   constant C_GEOM   : geom_vector := geometries;

   signal geom_r     : geom_t := C_GEOM(0);

   -- Stage 1
   signal in_x_r     : std_logic := '0';
   signal u_r        : natural range 0 to C_MAX_CELL-1 := 0;
   signal col_r      : natural range 0 to C_MAX_COLS-1 := 0;
   signal in_y_r     : std_logic := '0';
   signal v_r        : natural range 0 to C_MAX_CELL-1 := 0;
   signal row_r      : natural range 0 to C_MAX_ROWS-1 := 0;
   signal base_r     : natural range 0 to C_MAX_SQUARES-1 := 0;   -- row * cols
   signal frame_r    : std_logic := '0';

   -- Stage 2
   signal in_d2      : std_logic := '0';
   signal u_d2       : natural range 0 to C_MAX_CELL-1 := 0;
   signal v_d2       : natural range 0 to C_MAX_CELL-1 := 0;
   signal frame_d2   : std_logic := '0';
   signal addr_r     : std_logic_vector(8 downto 0);

   -- Stage 3, while the board memory is read
   signal in_d2b     : std_logic := '0';
   signal u_d2b      : natural range 0 to C_MAX_CELL-1 := 0;
   signal v_d2b      : natural range 0 to C_MAX_CELL-1 := 0;
   signal frame_d2b  : std_logic := '0';

   -- Stage 3
   signal in_d3      : std_logic := '0';
   signal frame_d3   : std_logic := '0';
   signal id_d3      : natural range 0 to 31 := 0;
   signal a_d3       : natural range 0 to C_MAX_CELL-1 := 0;
   signal b_d3       : natural range 0 to C_MAX_CELL-1 := 0;
   signal s_h_d3     : std_logic := '0';
   signal s_v_d3     : std_logic := '0';
   signal s_d_d3     : std_logic := '0';

   -- Stage 4
   signal in_d4      : std_logic := '0';
   signal frame_d4   : std_logic := '0';
   signal id_d4      : natural range 0 to 31 := 0;
   signal p_d4       : integer range -16 to C_MAX_CELL := 0;
   signal q_d4       : integer range -16 to C_MAX_CELL := 0;
   signal s_h_d4     : std_logic := '0';
   signal s_v_d4     : std_logic := '0';
   signal s_d_d4     : std_logic := '0';
   signal e_d4       : natural range 0 to 2**16-1 := 0;   -- (r-p)^2 + (r-q)^2
   signal d2_d4      : natural range 0 to 2**16-1 := 0;   -- p^2 + q^2

   -- Stage 5
   signal in_d5      : std_logic := '0';
   signal frame_d5   : std_logic := '0';
   signal id_d5      : natural range 0 to 31 := 0;
   signal part_d5    : natural range 0 to 3 := 0;          -- Outside, outline, rim, fill

   -- Stage 6
   signal col_r6     : std_logic_vector(23 downto 0) := C_BACKGROUND;
   signal on_r6      : std_logic := '0';

begin

   p_geom : process (clk_i)
   begin
      if rising_edge(clk_i) then
         geom_r <= C_GEOM(puzzle_i);
      end if;
   end process p_geom;


   ----------------------------------------------------------------
   -- Stage 1: The square, and the position in it
   ----------------------------------------------------------------

   p_stage1 : process (clk_i)
      variable x_v : natural range 0 to 2047;
      variable y_v : natural range 0 to 2047;
   begin
      if rising_edge(clk_i) then
         x_v := to_integer(pix_x_i);
         y_v := to_integer(pix_y_i);

         -- The columns, counted along the line
         if x_v = geom_r.x0 then
            in_x_r <= '1';
            u_r    <= 0;
            col_r  <= 0;
         elsif in_x_r = '1' then
            if u_r = geom_r.cell-1 then
               u_r <= 0;
               if col_r = geom_r.cols-1 then
                  in_x_r <= '0';
               else
                  col_r <= col_r + 1;
               end if;
            else
               u_r <= u_r + 1;
            end if;
         end if;

         -- The rows, counted at the start of each line
         if x_v = 0 then
            if y_v = geom_r.y0 then
               in_y_r <= '1';
               v_r    <= 0;
               row_r  <= 0;
               base_r <= 0;
            elsif in_y_r = '1' then
               if v_r = geom_r.cell-1 then
                  v_r <= 0;
                  if row_r = geom_r.rows-1 then
                     in_y_r <= '0';
                  else
                     row_r  <= row_r + 1;
                     base_r <= base_r + geom_r.cols;
                  end if;
               else
                  v_r <= v_r + 1;
               end if;
            end if;
            if y_v = 0 then
               in_y_r <= '0';
            end if;
         end if;

         -- The frame: 4 to 7 pixels outside the board
         frame_r <= '0';
         if x_v + 8 >= geom_r.x0 and x_v < geom_r.x1 + 8 and
            y_v + 8 >= geom_r.y0 and y_v < geom_r.y1 + 8
         then
            frame_r <= '1';
            if x_v + 4 >= geom_r.x0 and x_v < geom_r.x1 + 4 and
               y_v + 4 >= geom_r.y0 and y_v < geom_r.y1 + 4
            then
               frame_r <= '0';
            end if;
         end if;
      end if;
   end process p_stage1;


   ----------------------------------------------------------------
   -- Stage 2: The address of the square
   ----------------------------------------------------------------

   p_stage2 : process (clk_i)
   begin
      if rising_edge(clk_i) then
         in_d2    <= in_x_r and in_y_r;
         u_d2     <= u_r;
         v_d2     <= v_r;
         frame_d2 <= frame_r;
         addr_r   <= buf_i & to_slv((base_r + col_r) mod C_MAX_SQUARES, 8);
      end if;
   end process p_stage2;

   rd_addr_o <= addr_r;

   p_stage3 : process (clk_i)
   begin
      if rising_edge(clk_i) then
         in_d2b    <= in_d2;
         u_d2b     <= u_d2;
         v_d2b     <= v_d2;
         frame_d2b <= frame_d2;
      end if;
   end process p_stage3;


   ----------------------------------------------------------------
   -- Stage 4: The quadrant and its neighbours
   ----------------------------------------------------------------

   -- The neighbour mask, see snapshot.vhd: bit 0 = N, 1 = NE, 2 = E,
   -- 3 = SE, 4 = S, 5 = SW, 6 = W, 7 = NW
   p_stage4 : process (clk_i)
      variable qx_v : boolean;
      variable qy_v : boolean;
      variable m_v  : std_logic_vector(7 downto 0);
   begin
      if rising_edge(clk_i) then
         m_v      := rd_data_i(7 downto 0);
         qx_v     := u_d2b >= geom_r.half;
         qy_v     := v_d2b >= geom_r.half;
         in_d3    <= in_d2b;
         frame_d3 <= frame_d2b;
         id_d3    <= to_integer(rd_data_i(12 downto 8));
         if qx_v then
            a_d3   <= geom_r.cell - 1 - u_d2b;
            s_h_d3 <= m_v(2);                            -- E
         else
            a_d3   <= u_d2b;
            s_h_d3 <= m_v(6);                            -- W
         end if;
         if qy_v then
            b_d3   <= geom_r.cell - 1 - v_d2b;
            s_v_d3 <= m_v(4);                            -- S
         else
            b_d3   <= v_d2b;
            s_v_d3 <= m_v(0);                            -- N
         end if;
         if qx_v and qy_v then
            s_d_d3 <= m_v(3);                            -- SE
         elsif qx_v then
            s_d_d3 <= m_v(1);                            -- NE
         elsif qy_v then
            s_d_d3 <= m_v(5);                            -- SW
         else
            s_d_d3 <= m_v(7);                            -- NW
         end if;
      end if;
   end process p_stage4;


   ----------------------------------------------------------------
   -- Stage 5: The distances
   ----------------------------------------------------------------

   p_stage5 : process (clk_i)
      variable p_v : integer range -16 to C_MAX_CELL;
      variable q_v : integer range -16 to C_MAX_CELL;
   begin
      if rising_edge(clk_i) then
         p_v      := a_d3 - geom_r.g;
         q_v      := b_d3 - geom_r.g;
         in_d4    <= in_d3;
         frame_d4 <= frame_d3;
         id_d4    <= id_d3;
         p_d4     <= p_v;
         q_d4     <= q_v;
         s_h_d4   <= s_h_d3;
         s_v_d4   <= s_v_d3;
         s_d_d4   <= s_d_d3;
         -- Only used where p and q are in 0 to r-1
         e_d4     <= ((geom_r.r - p_v) mod 64) * ((geom_r.r - p_v) mod 64) +
                     ((geom_r.r - q_v) mod 64) * ((geom_r.r - q_v) mod 64);
         -- Only used where p and q are not negative
         d2_d4    <= (p_v mod 128) * (p_v mod 128) + (q_v mod 128) * (q_v mod 128);
      end if;
   end process p_stage5;


   ----------------------------------------------------------------
   -- Stage 6: The part of the piece, see shade() in tools/render.py
   ----------------------------------------------------------------

   p_stage6 : process (clk_i)
      variable lin_v  : integer range -16 to C_MAX_CELL;
      variable part_v : natural range 0 to 3;
      variable bw_v   : natural range 0 to 15;
      variable br_v   : natural range 0 to 31;
      variable r_v    : natural range 0 to 31;
   begin
      if rising_edge(clk_i) then
         bw_v := geom_r.bw;
         br_v := geom_r.br;
         r_v  := geom_r.r;

         -- Either the part is known at once, or it follows from a distance to
         -- a straight edge (lin_v)
         part_v := 3;
         lin_v  := C_MAX_CELL;
         if id_d4 = 0 or s_h_d4 = '0' or s_v_d4 = '0' or s_d_d4 = '0' then
            if id_d4 /= 0 and s_h_d4 = '1' and s_v_d4 = '1' then
               -- An inner corner
               if p_d4 < 0 and q_d4 < 0 then
                  part_v := 0;
               elsif p_d4 < 0 then
                  lin_v := q_d4;
               elsif q_d4 < 0 then
                  lin_v := p_d4;
               elsif d2_d4 < geom_r.bw2 then
                  part_v := 1;
               elsif d2_d4 < geom_r.br2 then
                  part_v := 2;
               end if;
            elsif id_d4 /= 0 and s_h_d4 = '1' then
               -- An edge along the horizontal edge of the square
               if q_d4 < 0 then
                  part_v := 0;
               else
                  lin_v := q_d4;
               end if;
            elsif id_d4 /= 0 and s_v_d4 = '1' then
               -- An edge along the vertical edge of the square
               if p_d4 < 0 then
                  part_v := 0;
               else
                  lin_v := p_d4;
               end if;
            else
               -- An outer corner (or an empty square)
               if p_d4 < 0 or q_d4 < 0 then
                  part_v := 0;
               elsif p_d4 < r_v and q_d4 < r_v then
                  if e_d4 > geom_r.r2 then
                     part_v := 0;
                  elsif e_d4 > geom_r.rbw2 then
                     part_v := 1;
                  elsif e_d4 > geom_r.rbr2 then
                     part_v := 2;
                  end if;
               else
                  lin_v := minimum(p_d4, q_d4);
               end if;
            end if;
         end if;
         if part_v = 3 then
            if lin_v < bw_v then
               part_v := 1;
            elsif lin_v < br_v then
               part_v := 2;
            end if;
         end if;

         in_d5    <= in_d4;
         frame_d5 <= frame_d4;
         id_d5    <= id_d4;
         part_d5  <= part_v;
      end if;
   end process p_stage6;


   ----------------------------------------------------------------
   -- Stage 7: The colour
   ----------------------------------------------------------------

   p_stage7 : process (clk_i)
   begin
      if rising_edge(clk_i) then
         col_r6 <= C_BACKGROUND;
         on_r6  <= frame_d5 or in_d5;
         if frame_d5 = '1' then
            col_r6 <= C_FRAME;
         elsif in_d5 = '1' then
            case part_d5 is
               when 1      => col_r6 <= C_OUTLINE(id_d5 mod 20);
               when 2      => col_r6 <= C_RIM(id_d5 mod 20);
               when 3      => col_r6 <= C_FILL(id_d5 mod 20);
               when others => null;
            end case;
         end if;
      end if;
   end process p_stage7;

   col_o <= col_r6;
   on_o  <= on_r6;

end architecture rtl;
