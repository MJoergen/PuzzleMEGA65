-- This module makes the picture of the board for the VGA output, in the MAIN
-- clock domain, once for each frame: the position of the context that is
-- shown (disp_ctx_i, see control.vhd), as the piece on each square, and for
-- each square whether its 8 neighbours have the same piece. The picture is
-- written to the board memory (board_mem.vhd, a dual clock RAM), and drawn
-- by board.vhd in the VGA clock domain.
--
-- The board memory has two buffers. Each frame, the VGA clock domain takes
-- the newest statistics (see ctrl_pkg.vhd), which say which buffer to show,
-- and then sends frame_i. This module then writes the other buffer, which
-- takes a few thousand clock cycles, much less than a frame, and sends the
-- new statistics with the number of that buffer (stats_valid_o, see
-- core.vhd), so the VGA clock domain shows it from the next frame on. So a
-- buffer is never written while it is shown.
--
-- The steps, after frame_i:
-- 1. Hold the shown context (hold_o, see engine.vhd), and wait until it has
--    no pass in the pipeline (busy_i). Its path, i.e. the placements of the
--    position it has visited last, does not change while it is held.
-- 2. Take the statistics (latch_o), so they belong to the position. The
--    puzzle is taken at the start (puzzle_i), and main.vhd takes it with
--    the statistics, so the picture and the statistics have the same puzzle,
--    also when the puzzle changes.
-- 3. Read the number of placements (path_vis_i) and each placement (the
--    anchor and the slot) from the solver, and stop holding the context.
-- 4. Clear the map of the pieces (idmap, one entry per square).
-- 5. For each placement, write the piece (plus one, 0 is empty) to the
--    squares of its slot (C_SLOTS, the offsets from the anchor).
-- 6. For each square, read the square and its 8 neighbours from the map,
--    and write the piece and the neighbour mask to the board memory. A
--    neighbour outside the board, or any neighbour of an empty square,
--    counts as different.
-- 7. Send the statistics (stats_valid_o) with the number of the buffer.
--
-- The entry of the board memory is the piece (4 downto 0 of 12 downto 8) and
-- the neighbour mask (7 downto 0: NW, W, SW, S, SE, E, NE, N, bit 0 = N).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;

entity snapshot is
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;

      frame_i       : in  std_logic;              -- A frame has started (pulse)
      puzzle_i      : in  natural range 0 to C_NUM_PUZZLES-1;
      disp_ctx_i    : in  natural range 0 to 255;

      -- The paths of the solver
      hold_o        : out std_logic;
      hold_ctx_o    : out natural range 0 to 255;
      busy_i        : in  std_logic_vector(0 to 255);
      path_ctx_o    : out natural range 0 to 255;
      path_lvl_o    : out std_logic_vector(4 downto 0);
      path_anchor_i : in  std_logic_vector(8 downto 0);
      path_slot_i   : in  std_logic_vector(7 downto 0);
      path_vis_i    : in  std_logic_vector(4 downto 0);

      -- Write port of the board memory
      wr_en_o       : out std_logic;
      wr_addr_o     : out std_logic_vector(8 downto 0);  -- Buffer & square
      wr_data_o     : out std_logic_vector(12 downto 0);

      latch_o       : out std_logic;              -- Take the statistics now
      stats_valid_o : out std_logic;              -- The buffer buf_o is written
      buf_o         : out std_logic
   );
end entity snapshot;

architecture rtl of snapshot is

   -- The slots of all the puzzles, as tables indexed by the global number of
   -- the slot (first_slot of the puzzle + the slot)
   constant C_NUM_SLOTS : natural := C_SLOTS'length;

   type piece_vector is array (0 to C_NUM_SLOTS-1) of std_logic_vector(4 downto 0);
   type size_vector is array (0 to C_NUM_SLOTS-1) of std_logic_vector(4 downto 0);
   type offset_vector is array (0 to C_NUM_SLOTS*C_MAX_SIZE-1) of std_logic_vector(7 downto 0);

   function pieces return piece_vector is
      variable r_v : piece_vector;
   begin
      for g in 0 to C_NUM_SLOTS-1 loop
         r_v(g) := to_slv(C_SLOTS(g).piece, 5);
      end loop;
      return r_v;
   end function pieces;

   function sizes return size_vector is
      variable r_v : size_vector;
   begin
      for g in 0 to C_NUM_SLOTS-1 loop
         r_v(g) := to_slv(C_SLOTS(g).size, 5);
      end loop;
      return r_v;
   end function sizes;

   function offsets return offset_vector is
      variable r_v : offset_vector;
   begin
      for g in 0 to C_NUM_SLOTS-1 loop
         for i in 0 to C_MAX_SIZE-1 loop
            r_v(g*C_MAX_SIZE + i) := to_slv(C_SLOTS(g).offsets(i), 8);
         end loop;
      end loop;
      return r_v;
   end function offsets;

   constant C_PIECE   : piece_vector  := pieces;
   constant C_SIZE    : size_vector   := sizes;
   constant C_OFFSET  : offset_vector := offsets;

   type state_t is (IDLE_ST, HOLD_ST, VIS_ST, PATH_ST, CLEAR_ST, PLACE_ST, NBR_ST, SEND_ST);

   signal state_r     : state_t := IDLE_ST;
   signal puzzle_r    : natural range 0 to C_NUM_PUZZLES-1;
   signal cnt_r       : natural range 0 to 15;
   signal buf_r       : std_logic := '0';

   -- The placements of the position
   type anchor_vector is array (0 to 31) of std_logic_vector(8 downto 0);
   type slot_vector is array (0 to 31) of natural range 0 to C_NUM_SLOTS-1;
   signal vis_r       : natural range 0 to 31;
   signal lvl_r       : natural range 0 to 32;
   signal anchors_r   : anchor_vector;
   signal slots_r     : slot_vector;

   -- The map of the pieces
   type idmap_vector is array (0 to C_MAX_SQUARES-1) of std_logic_vector(4 downto 0);
   signal idmap       : idmap_vector;
   signal map_wr_r    : std_logic;
   signal map_addr_r  : natural range 0 to C_MAX_SQUARES-1;
   signal map_data_r  : std_logic_vector(4 downto 0);

   -- Placing a piece: the square of the slot, and the offset (read from the
   -- table, one clock cycle later)
   signal sq_r        : natural range 0 to C_MAX_SIZE;
   signal offset_r    : std_logic_vector(7 downto 0);
   signal place_r     : std_logic;
   signal piece_r     : std_logic_vector(4 downto 0);
   signal anchor_r    : std_logic_vector(8 downto 0);

   -- The neighbour masks: the square (row, column) and the neighbour
   -- (0 = the square itself, 1 to 8 = N, NE, E, SE, S, SW, W, NW), and the
   -- neighbour that is read (one clock cycle later)
   signal row_r       : natural range 0 to C_MAX_ROWS-1;
   signal col_r       : natural range 0 to C_MAX_COLS-1;
   signal square_r    : natural range 0 to C_MAX_SQUARES-1;
   signal nbr_r       : natural range 0 to 10;
   signal rd_on_r     : std_logic;
   signal rd_addr_r   : natural range 0 to C_MAX_SQUARES-1;
   signal rd_nbr_r    : natural range 0 to 10;
   signal center_r    : std_logic_vector(4 downto 0);
   signal mask_r      : std_logic_vector(7 downto 0);

   signal wr_en_r     : std_logic;
   signal wr_addr_r   : std_logic_vector(8 downto 0);
   signal wr_data_r   : std_logic_vector(12 downto 0);
   signal latch_r     : std_logic;
   signal valid_r     : std_logic;

begin

   p_fsm : process (clk_i)
      variable p_v   : puzzle_t;
      variable dr_v  : integer;
      variable dc_v  : integer;
      variable r_v   : integer;
      variable c_v   : integer;
      variable id_v  : std_logic_vector(4 downto 0);
   begin
      if rising_edge(clk_i) then
         p_v       := C_PUZZLES(puzzle_r);
         map_wr_r  <= '0';
         wr_en_r   <= '0';
         latch_r   <= '0';
         valid_r   <= '0';
         place_r   <= '0';

         case state_r is
            when IDLE_ST =>
               if frame_i = '1' then
                  puzzle_r   <= puzzle_i;
                  hold_o     <= '1';
                  hold_ctx_o <= disp_ctx_i;
                  path_ctx_o <= disp_ctx_i;
                  cnt_r      <= 0;
                  state_r    <= HOLD_ST;
               end if;

            -- Wait until the context has no pass in the pipeline, and some
            -- more clock cycles for the hold to reach the engine
            when HOLD_ST =>
               if busy_i(hold_ctx_o) = '1' then
                  cnt_r <= 0;
               elsif cnt_r = 15 then
                  latch_r <= '1';
                  cnt_r   <= 0;
                  state_r <= VIS_ST;
               else
                  cnt_r <= cnt_r + 1;
               end if;

            -- The number of placements, after the read latency (two clock
            -- cycles, see solver.vhd)
            when VIS_ST =>
               cnt_r <= cnt_r + 1;
               if cnt_r = 5 then
                  vis_r      <= to_integer(path_vis_i);
                  lvl_r      <= 0;
                  path_lvl_o <= (others => '0');
                  cnt_r      <= 0;
                  state_r    <= PATH_ST;
               end if;

            -- Each placement: the address is set, and the data is taken five
            -- clock cycles later
            when PATH_ST =>
               cnt_r <= cnt_r + 1;
               if cnt_r = 5 then
                  if lvl_r < vis_r then
                     anchors_r(lvl_r) <= path_anchor_i;
                     slots_r(lvl_r)   <= p_v.first_slot + to_integer(path_slot_i);
                  end if;
                  lvl_r      <= lvl_r + 1;
                  path_lvl_o <= to_slv(lvl_r + 1, 5);
                  cnt_r      <= 0;
                  if lvl_r + 1 >= vis_r then
                     hold_o     <= '0';
                     map_addr_r <= 0;
                     state_r    <= CLEAR_ST;
                  end if;
               end if;

            when CLEAR_ST =>
               map_wr_r   <= '1';
               map_data_r <= (others => '0');
               if map_wr_r = '1' then
                  if map_addr_r = C_MAX_SQUARES-1 then
                     map_wr_r <= '0';
                     lvl_r    <= 0;
                     sq_r     <= 0;
                     state_r  <= PLACE_ST;
                  else
                     map_addr_r <= map_addr_r + 1;
                  end if;
               end if;

            -- Each square of each placement: the offset is read from the
            -- table in one clock cycle (place_r), and written in the next
            when PLACE_ST =>
               if place_r = '1' then
                  map_wr_r   <= '1';
                  map_addr_r <= to_integer(anchor_r + offset_r);
                  map_data_r <= piece_r;
               end if;
               if lvl_r >= vis_r then
                  if place_r = '0' then
                     row_r    <= 0;
                     col_r    <= 0;
                     square_r <= 0;
                     nbr_r    <= 0;
                     rd_nbr_r <= 0;
                     rd_on_r  <= '0';
                     rd_addr_r <= 0;
                     state_r  <= NBR_ST;
                  end if;
               else
                  place_r  <= '1';
                  offset_r <= C_OFFSET(slots_r(lvl_r) * C_MAX_SIZE + sq_r);
                  piece_r  <= C_PIECE(slots_r(lvl_r)) + 1;
                  anchor_r <= anchors_r(lvl_r);
                  if sq_r + 1 = to_integer(C_SIZE(slots_r(lvl_r))) then
                     sq_r  <= 0;
                     lvl_r <= lvl_r + 1;
                  else
                     sq_r <= sq_r + 1;
                  end if;
               end if;

            -- Each square: the square itself and its 8 neighbours. In the
            -- clock cycles 0 to 8 the address of neighbour nbr_r is set (with
            -- whether it is on the board), and one clock cycle later it is read
            -- and compared with the square. In clock cycle 10 the entry is
            -- written to the board memory, and the next square is taken.
            when NBR_ST =>
               dr_v := 0;
               dc_v := 0;
               case nbr_r is
                  when 1      => dr_v := -1;             -- N
                  when 2      => dr_v := -1; dc_v :=  1; -- NE
                  when 3      =>             dc_v :=  1; -- E
                  when 4      => dr_v :=  1; dc_v :=  1; -- SE
                  when 5      => dr_v :=  1;             -- S
                  when 6      => dr_v :=  1; dc_v := -1; -- SW
                  when 7      =>             dc_v := -1; -- W
                  when 8      => dr_v := -1; dc_v := -1; -- NW
                  when others => null;
               end case;
               r_v      := row_r + dr_v;
               c_v      := col_r + dc_v;
               rd_on_r  <= to_sl(r_v >= 0 and r_v < p_v.rows and c_v >= 0 and c_v < p_v.cols);
               rd_addr_r <= (square_r + dr_v * p_v.cols + dc_v) mod C_MAX_SQUARES;
               rd_nbr_r <= nbr_r;

               -- The neighbour of the last clock cycle
               id_v := idmap(rd_addr_r);
               if rd_on_r = '0' then
                  id_v := (others => '0');
               end if;
               if rd_nbr_r = 0 then
                  center_r <= id_v;
               elsif rd_nbr_r <= 8 then
                  mask_r(rd_nbr_r - 1) <= '0';
                  if id_v = center_r and center_r /= "00000" then
                     mask_r(rd_nbr_r - 1) <= '1';
                  end if;
               end if;

               if nbr_r = 10 then
                  nbr_r <= 0;
               else
                  nbr_r <= nbr_r + 1;
               end if;

               -- All 8 neighbours have been compared
               if nbr_r = 10 then
                  wr_en_r   <= '1';
                  wr_addr_r <= buf_r & to_slv(square_r, 8);
                  wr_data_r <= center_r & mask_r;
                  if col_r = p_v.cols-1 then
                     col_r <= 0;
                     if row_r = p_v.rows-1 then
                        state_r <= SEND_ST;
                     else
                        row_r <= row_r + 1;
                     end if;
                  else
                     col_r <= col_r + 1;
                  end if;
                  square_r <= (square_r + 1) mod C_MAX_SQUARES;
               end if;

            when SEND_ST =>
               valid_r <= '1';
               buf_o   <= buf_r;
               buf_r   <= not buf_r;
               state_r <= IDLE_ST;
         end case;

         if rst_i = '1' then
            state_r <= IDLE_ST;
            hold_o  <= '0';
            buf_r   <= '0';
            buf_o   <= '1';
         end if;
      end if;
   end process p_fsm;

   p_map : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if map_wr_r = '1' then
            idmap(map_addr_r) <= map_data_r;
         end if;
      end if;
   end process p_map;

   wr_en_o       <= wr_en_r;
   wr_addr_o     <= wr_addr_r;
   wr_data_o     <= wr_data_r;
   latch_o       <= latch_r;
   stats_valid_o <= valid_r;

end architecture rtl;
