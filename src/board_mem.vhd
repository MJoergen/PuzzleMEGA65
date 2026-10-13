-- This is the board memory: the picture of the board, with two buffers of
-- 256 squares, see snapshot.vhd (which writes it in the MAIN clock domain)
-- and board.vhd (which reads it in the VGA clock domain). It is a simple dual
-- port RAM with a separate clock for each port, i.e. one block RAM, which is
-- how the picture crosses the clock domains. The read is registered (a read
-- latency of one clock cycle).
--
-- A buffer is never read while it is written (see snapshot.vhd), so the
-- relation between the two clocks does not matter.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

entity board_mem is
   port (
      wr_clk_i  : in  std_logic;
      wr_en_i   : in  std_logic;
      wr_addr_i : in  std_logic_vector(8 downto 0);
      wr_data_i : in  std_logic_vector(12 downto 0);

      rd_clk_i  : in  std_logic;
      rd_addr_i : in  std_logic_vector(8 downto 0);
      rd_data_o : out std_logic_vector(12 downto 0)
   );
end entity board_mem;

architecture rtl of board_mem is

   -- Initially every square is empty
   type mem_vector is array (0 to 511) of std_logic_vector(12 downto 0);
   signal mem    : mem_vector := (others => (others => '0'));
   signal data_r : std_logic_vector(12 downto 0) := (others => '0');

   attribute ram_style : string;
   attribute ram_style of mem : signal is "block";

begin

   p_write : process (wr_clk_i)
   begin
      if rising_edge(wr_clk_i) then
         if wr_en_i = '1' then
            mem(to_integer(wr_addr_i)) <= wr_data_i;
         end if;
      end if;
   end process p_write;

   p_read : process (rd_clk_i)
   begin
      if rising_edge(rd_clk_i) then
         data_r <= mem(to_integer(rd_addr_i));
      end if;
   end process p_read;

   rd_data_o <= data_r;

end architecture rtl;
