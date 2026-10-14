-- This is the VGA clock domain: it draws the screen, 1280x1024 @ 60 Hz with
-- the pixel clock of 108 MHz (G_MODE, see video_pkg.vhd):
-- * the board (board.vhd), from the board memory, which the MAIN clock
--   domain writes (see snapshot.vhd), and
-- * the text (text.vhd): the puzzle, the status, the statistics, and the keys,
--   which status.vhd writes once for each frame.
-- The text is drawn over the board, and the rest of the screen is the
-- background.
--
-- At the start of the vertical blanking (the first pixel after the visible
-- area), the newest statistics (stats_i, from the MAIN clock domain) are
-- taken, and used for the whole next frame: the puzzle and the buffer of the
-- board memory for the board, and the text. Then frame_o is sent to the MAIN
-- clock domain, which then writes the next picture of the board, see
-- snapshot.vhd.
--
-- The output is registered, C_LATENCY clock cycles after the pixel counters,
-- and the sync signals are delayed to match.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.video_pkg.all;
use work.puzzle_pkg.all;
use work.ctrl_pkg.all;

entity vga is
   generic (
      G_MODE : video_mode_t;
      G_HELP : string                             -- The keys, see status.vhd
   );
   port (
      clk_i     : in  std_logic;                     -- The pixel clock

      stats_i   : in  stats_t;
      frame_o   : out std_logic;

      -- Read port of the board memory
      rd_addr_o : out std_logic_vector(8 downto 0);
      rd_data_i : in  std_logic_vector(12 downto 0);

      vga_hs_o  : out std_logic;
      vga_vs_o  : out std_logic;
      vga_de_o  : out std_logic;                     -- Visible area
      vga_col_o : out std_logic_vector(23 downto 0)  -- RRGGBB
   );
end entity vga;

architecture structural of vga is

   -- From the pixel counters to the output: the board and the text, and the
   -- stage that puts them together
   constant C_LATENCY : natural := C_BOARD_LATENCY + 1;

   signal pix_x       : std_logic_vector(10 downto 0);
   signal pix_y       : std_logic_vector(10 downto 0);

   signal stats_r     : stats_t := C_STATS_INIT;
   signal frame_r     : std_logic := '0';
   signal puzzle      : natural range 0 to C_NUM_PUZZLES-1;

   signal board_col   : std_logic_vector(23 downto 0);
   signal board_on    : std_logic;
   signal text_col    : std_logic_vector(23 downto 0);
   signal text_on     : std_logic;

   signal wr_en       : std_logic;
   signal wr_addr     : std_logic_vector(11 downto 0);
   signal wr_data     : std_logic_vector( 8 downto 0);

   -- The sync signals and the visible area, delayed
   signal hs_d        : std_logic_vector(1 to C_LATENCY);
   signal vs_d        : std_logic_vector(1 to C_LATENCY);
   signal de_d        : std_logic_vector(1 to C_LATENCY);

   signal col_r       : std_logic_vector(23 downto 0) := (others => '0');

begin

   assert C_BOARD_LATENCY = C_TEXT_LATENCY
      report "The board and the text must have the same latency"
      severity failure;

   i_pix : entity work.pix
      generic map (
         G_MODE => G_MODE
      )
      port map (
         clk_i   => clk_i,
         pix_x_o => pix_x,
         pix_y_o => pix_y
      ); -- i_pix


   --------------------------------------------------
   -- The statistics of each frame
   --------------------------------------------------

   p_frame : process (clk_i)
   begin
      if rising_edge(clk_i) then
         frame_r <= '0';
         if pix_x = 0 and pix_y = G_MODE.v_visible then
            stats_r <= stats_i;
            frame_r <= '1';
         end if;
      end if;
   end process p_frame;

   puzzle <= to_integer(stats_r.puzzle) mod C_NUM_PUZZLES;


   --------------------------------------------------
   -- The board and the text
   --------------------------------------------------

   i_board : entity work.board
      port map (
         clk_i     => clk_i,
         pix_x_i   => pix_x,
         pix_y_i   => pix_y,
         puzzle_i  => puzzle,
         buf_i     => stats_r.buf,
         rd_addr_o => rd_addr_o,
         rd_data_i => rd_data_i,
         col_o     => board_col,
         on_o      => board_on
      ); -- i_board

   i_status : entity work.status
      generic map (
         G_HELP => G_HELP
      )
      port map (
         clk_i     => clk_i,
         frame_i   => frame_r,
         stats_i   => stats_r,
         wr_en_o   => wr_en,
         wr_addr_o => wr_addr,
         wr_data_o => wr_data
      ); -- i_status

   i_text : entity work.text
      port map (
         clk_i     => clk_i,
         wr_en_i   => wr_en,
         wr_addr_i => wr_addr,
         wr_data_i => wr_data,
         pix_x_i   => pix_x,
         pix_y_i   => pix_y,
         col_o     => text_col,
         on_o      => text_on
      ); -- i_text


   --------------------------------------------------
   -- The output
   --------------------------------------------------

   p_sync : process (clk_i)
      variable hs_v : std_logic;
      variable vs_v : std_logic;
      variable de_v : std_logic;
   begin
      if rising_edge(clk_i) then
         hs_v := not G_MODE.sync_active;
         vs_v := not G_MODE.sync_active;
         de_v := '0';
         if pix_x >= G_MODE.h_visible + G_MODE.h_front and
            pix_x < G_MODE.h_visible + G_MODE.h_front + G_MODE.h_sync
         then
            hs_v := G_MODE.sync_active;
         end if;
         if pix_y >= G_MODE.v_visible + G_MODE.v_front and
            pix_y < G_MODE.v_visible + G_MODE.v_front + G_MODE.v_sync
         then
            vs_v := G_MODE.sync_active;
         end if;
         if pix_x < G_MODE.h_visible and pix_y < G_MODE.v_visible then
            de_v := '1';
         end if;
         hs_d <= hs_v & hs_d(1 to C_LATENCY-1);
         vs_d <= vs_v & vs_d(1 to C_LATENCY-1);
         de_d <= de_v & de_d(1 to C_LATENCY-1);
      end if;
   end process p_sync;

   -- The text is drawn over the board. board.vhd gives the background where
   -- there is no board.
   p_col : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if text_on = '1' then
            col_r <= text_col;
         else
            col_r <= board_col;
         end if;
         if de_d(C_LATENCY-1) = '0' then
            col_r <= (others => '0');
         end if;
      end if;
   end process p_col;

   vga_hs_o  <= hs_d(C_LATENCY);
   vga_vs_o  <= vs_d(C_LATENCY);
   vga_de_o  <= de_d(C_LATENCY);
   vga_col_o <= col_r;
   frame_o   <= frame_r;

end architecture structural;
