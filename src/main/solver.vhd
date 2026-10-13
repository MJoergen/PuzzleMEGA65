-- This module holds the search engines of all the puzzles (engine.vhd), and
-- connects the engines of the selected puzzle (puzzle_i) to one interface.
-- Puzzle p has G_ENGINES(p) engines, with C_STAGES contexts each, numbered
-- globally from 0: context g is context g mod C_STAGES of engine
-- g / C_STAGES. The engines of the other puzzles are held in reset, so they
-- do nothing. A puzzle with no engines (only in testbenches, which leave out
-- puzzles to save time) is done at once.
--
-- The control inputs (run_i, halt_i, credit_i, hold_i, see engine.vhd) go to
-- all the engines of the selected puzzle; a credit or a hold is for one
-- context (credit_ctx_i, hold_ctx_i). The results of each clock cycle are the
-- number of counted nodes (count_o, at most one for each engine), the number
-- of solutions (sol_o), and the context of the solution of the lowest engine
-- that has one (sol_ctx_o), two clock cycles later (registered twice: the
-- bits of the engines, and the sums). Only sol_any_o, whether any engine
-- commits a solution, is combinational (from the last stage of the engines,
-- an OR of all the engines of all the puzzles, without a multiplexer), so
-- that the halt can be registered in the same clock cycle (control.vhd). The
-- engines of the puzzles that are not selected are in reset, so their
-- outputs are low.
--
-- The targets: when a context owns a node at the depth of the split, it
-- claims a new target (engine.vhd). The claims of a clock cycle are
-- registered, and granted in the next clock cycle, in the order of the
-- engines, from a counter (claimed_o) that starts at the number of contexts.
-- So the grant reaches the engine two clock cycles after the commit, long
-- before the context's next pass (eight clock cycles). All the engines are
-- reset together, so they always have the same context in the last stage.
-- claimed_o is the number of subtrees handed out, used for the progress.
--
-- The solver also shows which contexts are done (ctx_done_o) and whether all
-- of them are done (done_o), and which have a pass in the pipeline (busy_o).
-- These are registered, and only valid a few clock cycles after a reset, see
-- control.vhd. The path of a context (path_*) is read through the read port
-- of its engine, which is registered, and then registered again here, so
-- the data is valid two clock cycles after the address.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;

entity solver is
   generic (
      G_ENGINES     : natural_vector(0 to C_NUM_PUZZLES-1)
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;         -- Start the search again
      puzzle_i      : in  natural range 0 to C_NUM_PUZZLES-1;

      run_i         : in  std_logic;
      halt_i        : in  std_logic;
      credit_i      : in  std_logic;
      credit_ctx_i  : in  natural range 0 to 255;
      hold_i        : in  std_logic;
      hold_ctx_i    : in  natural range 0 to 255;

      count_o       : out natural range 0 to 32;
      sol_o         : out natural range 0 to 32;
      sol_ctx_o     : out natural range 0 to 255;
      sol_any_o     : out std_logic;
      claimed_o     : out std_logic_vector(31 downto 0);

      busy_o        : out std_logic_vector(0 to 255);
      ctx_done_o    : out std_logic_vector(0 to 255);
      done_o        : out std_logic;

      path_ctx_i    : in  natural range 0 to 255;
      path_lvl_i    : in  std_logic_vector(4 downto 0);
      path_anchor_o : out std_logic_vector(8 downto 0);
      path_slot_o   : out std_logic_vector(7 downto 0);
      path_vis_o    : out std_logic_vector(4 downto 0)
   );
end entity solver;

architecture structural of solver is

   constant C_CTX_BITS : natural := log2(C_STAGES);
   constant C_E        : positive := maximum(max_of(G_ENGINES), 1);
   constant C_NUM_CTX  : natural := C_STAGES * C_E;

   type ctx_vector is array (0 to C_E-1) of std_logic_vector(C_CTX_BITS-1 downto 0);
   type slv32_vector is array (natural range <>) of std_logic_vector(31 downto 0);
   type slv9_vector is array (natural range <>) of std_logic_vector(8 downto 0);
   type slv8_vector is array (natural range <>) of std_logic_vector(7 downto 0);
   type slv5_vector is array (natural range <>) of std_logic_vector(4 downto 0);

   -- The outputs of the engines of each puzzle
   type eng_t is record
      ctx      : ctx_vector;
      count    : std_logic_vector(0 to C_E-1);
      sol      : std_logic_vector(0 to C_E-1);
      claim    : std_logic_vector(0 to C_E-1);
      busy     : std_logic_vector(0 to C_NUM_CTX-1);
      cdone    : std_logic_vector(0 to C_NUM_CTX-1);
      anchor   : slv9_vector(0 to C_E-1);
      slot     : slv8_vector(0 to C_E-1);
      vis      : slv5_vector(0 to C_E-1);
   end record eng_t;

   type eng_vector is array (0 to C_NUM_PUZZLES-1) of eng_t;

   -- The outputs of an engine that the puzzle does not have
   constant C_NO_ENG : eng_t := (ctx    => (others => (others => '0')),
                                 count  => (others => '0'),
                                 sol    => (others => '0'),
                                 claim  => (others => '0'),
                                 busy   => (others => '0'),
                                 cdone  => (others => '1'),
                                 anchor => (others => (others => '0')),
                                 slot   => (others => (others => '0')),
                                 vis    => (others => (others => '0')));

   signal eng          : eng_vector;
   signal sel_r        : eng_t;

   -- Registered locally, and per puzzle
   signal rst_r        : std_logic_vector(0 to C_NUM_PUZZLES-1);

   -- The results of the engines of the last clock cycle: the counted nodes,
   -- the solutions, the claims, and the context in the last stage
   signal count_r      : std_logic_vector(0 to C_E-1);
   signal sol_r        : std_logic_vector(0 to C_E-1);
   signal claim_r      : std_logic_vector(0 to C_E-1);
   signal ctx_r        : natural range 0 to C_STAGES-1;

   -- The grants and the counter
   signal grant_r      : std_logic_vector(0 to C_E-1);
   signal grant_ctx_r  : std_logic_vector(C_CTX_BITS-1 downto 0);
   signal grant_tgt_r  : slv32_vector(0 to C_E-1);
   signal claimed_r    : std_logic_vector(31 downto 0);

   signal path_e_r     : natural range 0 to C_E-1;

begin

   p_rst : process (clk_i)
   begin
      if rising_edge(clk_i) then
         for p in 0 to C_NUM_PUZZLES-1 loop
            rst_r(p) <= '1';
            if p = puzzle_i and rst_i = '0' then
               rst_r(p) <= '0';
            end if;
         end loop;
      end if;
   end process p_rst;


   --------------------------------------------------
   -- The engines of each puzzle
   --------------------------------------------------

   gen_puzzle : for p in 0 to C_NUM_PUZZLES-1 generate

      gen_engine : for e in 0 to G_ENGINES(p)-1 generate

         i_engine : entity work.engine
            generic map (
               G_PUZZLE  => p,
               G_FIRST   => e * C_STAGES
            )
            port map (
               clk_i         => clk_i,
               rst_i         => rst_r(p),
               run_i         => run_i,
               halt_i        => halt_i,
               credit_i      => credit_i and to_sl(credit_ctx_i / C_STAGES = e),
               credit_ctx_i  => to_slv(credit_ctx_i mod C_STAGES, C_CTX_BITS),
               hold_i        => hold_i and to_sl(hold_ctx_i / C_STAGES = e),
               hold_ctx_i    => to_slv(hold_ctx_i mod C_STAGES, C_CTX_BITS),
               grant_i       => grant_r(e),
               grant_ctx_i   => grant_ctx_r,
               grant_tgt_i   => grant_tgt_r(e),
               ctx_o         => eng(p).ctx(e),
               commit_o      => open,
               count_o       => eng(p).count(e),
               sol_o         => eng(p).sol(e),
               claim_o       => eng(p).claim(e),
               lvl_o         => open,
               anchor_o      => open,
               slot_o        => open,
               skip_o        => open,
               busy_o        => eng(p).busy(e*C_STAGES to e*C_STAGES + C_STAGES-1),
               ctx_done_o    => eng(p).cdone(e*C_STAGES to e*C_STAGES + C_STAGES-1),
               done_o        => open,
               path_ctx_i    => to_slv(path_ctx_i mod C_STAGES, C_CTX_BITS),
               path_lvl_i    => path_lvl_i,
               path_anchor_o => eng(p).anchor(e),
               path_slot_o   => eng(p).slot(e),
               path_vis_o    => eng(p).vis(e)
            ); -- i_engine

      end generate gen_engine;

      -- The engines that the puzzle does not have
      gen_unused : if G_ENGINES(p) < C_E generate
         eng(p).ctx(G_ENGINES(p) to C_E-1)    <= C_NO_ENG.ctx(G_ENGINES(p) to C_E-1);
         eng(p).count(G_ENGINES(p) to C_E-1)  <= C_NO_ENG.count(G_ENGINES(p) to C_E-1);
         eng(p).sol(G_ENGINES(p) to C_E-1)    <= C_NO_ENG.sol(G_ENGINES(p) to C_E-1);
         eng(p).claim(G_ENGINES(p) to C_E-1)  <= C_NO_ENG.claim(G_ENGINES(p) to C_E-1);
         eng(p).busy(G_ENGINES(p)*C_STAGES to C_NUM_CTX-1)  <=
            C_NO_ENG.busy(G_ENGINES(p)*C_STAGES to C_NUM_CTX-1);
         eng(p).cdone(G_ENGINES(p)*C_STAGES to C_NUM_CTX-1) <=
            C_NO_ENG.cdone(G_ENGINES(p)*C_STAGES to C_NUM_CTX-1);
         eng(p).anchor(G_ENGINES(p) to C_E-1) <= C_NO_ENG.anchor(G_ENGINES(p) to C_E-1);
         eng(p).slot(G_ENGINES(p) to C_E-1)   <= C_NO_ENG.slot(G_ENGINES(p) to C_E-1);
         eng(p).vis(G_ENGINES(p) to C_E-1)    <= C_NO_ENG.vis(G_ENGINES(p) to C_E-1);
      end generate gen_unused;

   end generate gen_puzzle;

   -- The registered outputs of the selected puzzle
   p_sel : process (clk_i)
   begin
      if rising_edge(clk_i) then
         sel_r <= eng(puzzle_i);
      end if;
   end process p_sel;


   --------------------------------------------------
   -- The results of the selected puzzle
   --------------------------------------------------

   -- Any solution of any engine, for the halt
   p_sol_any : process (all)
      variable any_v : std_logic;
   begin
      any_v := '0';
      for p in 0 to C_NUM_PUZZLES-1 loop
         any_v := any_v or (or eng(p).sol);
      end loop;
      sol_any_o <= any_v;
   end process p_sol_any;

   -- The bits of the engines (an OR of the puzzles, as only the selected one
   -- has results), and then the sums
   p_results : process (clk_i)
      variable count_v : natural range 0 to 32;
      variable sol_v   : natural range 0 to 32;
      variable ctx_v   : natural range 0 to 255;
   begin
      if rising_edge(clk_i) then
         for e in 0 to C_E-1 loop
            count_r(e) <= '0';
            sol_r(e)   <= '0';
            claim_r(e) <= '0';
            for p in 0 to C_NUM_PUZZLES-1 loop
               if eng(p).count(e) = '1' then
                  count_r(e) <= '1';
               end if;
               if eng(p).sol(e) = '1' then
                  sol_r(e) <= '1';
               end if;
               if eng(p).claim(e) = '1' then
                  claim_r(e) <= '1';
               end if;
            end loop;
         end loop;
         ctx_r <= to_integer(eng(puzzle_i).ctx(0));

         count_v := 0;
         sol_v   := 0;
         ctx_v   := 0;
         for e in C_E-1 downto 0 loop
            if count_r(e) = '1' then
               count_v := count_v + 1;
            end if;
            if sol_r(e) = '1' then
               sol_v := sol_v + 1;
               ctx_v := e * C_STAGES + ctx_r;
            end if;
         end loop;
         count_o   <= count_v;
         sol_o     <= sol_v;
         sol_ctx_o <= ctx_v;

         if rst_i = '1' then
            count_r <= (others => '0');
            sol_r   <= (others => '0');
            claim_r <= (others => '0');
            count_o <= 0;
            sol_o   <= 0;
         end if;
      end if;
   end process p_results;


   --------------------------------------------------
   -- The targets
   --------------------------------------------------

   p_claim : process (clk_i)
      variable n_v : natural range 0 to C_E;
   begin
      if rising_edge(clk_i) then
         -- The number of claims of the lower engines is added to the counter
         n_v := 0;
         for e in 0 to C_E-1 loop
            grant_tgt_r(e) <= claimed_r + n_v;
            if claim_r(e) = '1' then
               n_v := n_v + 1;
            end if;
         end loop;
         grant_r     <= claim_r;
         grant_ctx_r <= to_slv(ctx_r, C_CTX_BITS);
         claimed_r   <= claimed_r + n_v;

         if rst_i = '1' then
            grant_r   <= (others => '0');
            claimed_r <= to_slv(C_STAGES * G_ENGINES(puzzle_i), 32);
         end if;
      end if;
   end process p_claim;


   --------------------------------------------------
   -- The state of the contexts and the paths
   --------------------------------------------------

   p_path : process (clk_i)
   begin
      if rising_edge(clk_i) then
         path_e_r      <= path_ctx_i / C_STAGES;
         path_anchor_o <= sel_r.anchor(path_e_r);
         path_slot_o   <= sel_r.slot(path_e_r);
         path_vis_o    <= sel_r.vis(path_e_r);
      end if;
   end process p_path;

   p_outputs : process (all)
   begin
      busy_o     <= (others => '0');
      ctx_done_o <= (others => '1');
      busy_o(0 to C_NUM_CTX-1)     <= sel_r.busy;
      ctx_done_o(0 to C_NUM_CTX-1) <= sel_r.cdone;
   end process p_outputs;

   claimed_o <= claimed_r;
   done_o    <= and sel_r.cdone;

end architecture structural;
