-- The top level of the formal verification of cdc_data.vhd (see
-- cdc_data.psl). In the design, the inputs of the source clock domain are
-- registers of that domain, so they only change at its clock edges. With
-- free clocks (multiclock), the free inputs could change at any time, so
-- they are registered here in the source clock domain.

library ieee;
use ieee.std_logic_1164.all;

entity cdc_data_top is
   generic (
      G_DATA_SIZE : positive;
      G_INIT      : std_logic_vector
   );
   port (
      s_clk_i   : in  std_logic;
      s_data_i  : in  std_logic_vector(G_DATA_SIZE-1 downto 0);
      s_valid_i : in  std_logic;
      m_clk_i   : in  std_logic;
      m_data_o  : out std_logic_vector(G_DATA_SIZE-1 downto 0);
      m_valid_o : out std_logic
   );
end entity cdc_data_top;

architecture structural of cdc_data_top is

   signal s_data_r  : std_logic_vector(G_DATA_SIZE-1 downto 0) := G_INIT;
   signal s_valid_r : std_logic := '0';

begin

   p_s : process (s_clk_i)
   begin
      if rising_edge(s_clk_i) then
         s_data_r  <= s_data_i;
         s_valid_r <= s_valid_i;
      end if;
   end process p_s;

   i_cdc_data : entity work.cdc_data
      generic map (
         G_DATA_SIZE => G_DATA_SIZE,
         G_INIT      => G_INIT
      )
      port map (
         s_clk_i   => s_clk_i,
         s_data_i  => s_data_r,
         s_valid_i => s_valid_r,
         m_clk_i   => m_clk_i,
         m_data_o  => m_data_o,
         m_valid_o => m_valid_o
      ); -- i_cdc_data

end architecture structural;
