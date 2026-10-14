-- This is a self-checking testbench of the search engine (engine.vhd). It
-- runs the whole search of several puzzles, each by its own engine with its 8
-- contexts, with run_i high (until it is done), and checks it against the model
-- (tools/model.cpp) with one engine. The testbench hands out the targets like
-- the solver: a claim is granted three clock cycles later, with the next
-- value of a counter that starts at 8. It checks:
-- * For the puzzles in C_TRACED, every committed pass of every context: the
--   level of the visited node, the anchor and the slot of its last piece, and
--   whether it is counted, skipped, and a solution, against the trace of the
--   model (build/model/<name>_<ctx>.trace, see tools/gen_tb_data.py). After
--   the search, every trace must be used up.
-- * For the puzzles in C_PARTIAL (16x16, which can not be searched to the
--   end), the same for the first passes of every context (the trace of the
--   model has only those).
-- * For all the puzzles in C_TRACED and C_COUNTED: the number of nodes
--   (the counted passes plus the root) and of solutions (model_pkg.vhd), and
--   that the search takes 8 clock cycles for each pass of the slowest
--   context, plus at most the latency of the pipeline.
-- The puzzles are given by their index (key - 1): 4 = 7x7, 5 = 5x5, 6 =
-- 1x16, 7 = 1x27, 8 = 16x16, and 3 = 5x8 (15.8 million nodes, about 18
-- minutes, so it is only simulated with G_COUNTED=true: "make run TB=engine
-- GENERICS=G_COUNTED=true"; "make sim" leaves it out).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

library std;
use std.textio.all;

use work.puzzle_pkg.all;
use work.model_pkg.all;

entity engine_tb is
   generic (
      G_COUNTED : boolean := false                       -- Also simulate C_COUNTED
   );
end entity engine_tb;

architecture simulation of engine_tb is

   type int_vector is array (natural range <>) of natural;

   constant C_TRACED  : int_vector := (5, 6, 7, 4);
   constant C_PARTIAL : int_vector := (0 => 8);
   constant C_COUNTED : int_vector := (0 => 3);

   function puzzles return int_vector is
   begin
      if G_COUNTED then
         return C_TRACED & C_PARTIAL & C_COUNTED;
      end if;
      return C_TRACED & C_PARTIAL;
   end function puzzles;

   constant C_PUZZLES_TB : int_vector := puzzles;

   signal clk      : std_logic := '0';
   signal rst      : std_logic := '1';
   signal finished : std_logic_vector(C_PUZZLES_TB'range) := (others => '0');

begin

   clk <= not clk after 2 ns;
   rst <= '1', '0' after 40 ns;

   p_finish : process
   begin
      wait until finished = (finished'range => '1');
      report "engine_tb: finished";
      std.env.finish;
   end process p_finish;


   gen_dut : for n in C_PUZZLES_TB'range generate
      constant C_PUZ    : natural  := C_PUZZLES_TB(n);
      constant C_NAME   : string   := C_PUZZLES(C_PUZ).name;
      constant C_TRACE  : boolean  := n < C_TRACED'length + C_PARTIAL'length;
      constant C_PART   : boolean  := n >= C_TRACED'length and C_TRACE;

      signal ctx        : std_logic_vector(2 downto 0);
      type ctx_vector is array (1 to 2) of std_logic_vector(2 downto 0);
      signal claim_d    : std_logic_vector(1 to 2) := (others => '0');
      signal ctx_d      : ctx_vector;
      signal commit     : std_logic;
      signal count      : std_logic;
      signal sol        : std_logic;
      signal lvl        : std_logic_vector(4 downto 0);
      signal anchor     : std_logic_vector(8 downto 0);
      signal slot       : std_logic_vector(7 downto 0);
      signal skip       : std_logic;
      signal claim      : std_logic;
      signal done       : std_logic;
      signal grant      : std_logic := '0';
      signal grant_ctx  : std_logic_vector(2 downto 0);
      signal grant_tgt  : std_logic_vector(31 downto 0);

      -- Each context sets its bit when its trace is used up
      signal trace_done : std_logic_vector(0 to C_STAGES-1) := (others => '0');

      function trim (s : string) return string is
      begin
         for i in s'range loop
            if s(i) = ' ' then
               return s(s'low to i - 1);
            end if;
         end loop;
         return s;
      end function trim;

   begin

      -- The counter of the targets, with the latency of the solver: three
      -- clock cycles from the claim to the grant
      p_grant : process (clk)
         variable tgt_v : natural := C_STAGES;
      begin
         if rising_edge(clk) then
            claim_d <= claim_d(2) & claim;
            ctx_d   <= (ctx_d(2), ctx);
            grant   <= claim_d(1);
            if claim_d(1) = '1' then
               grant_ctx <= ctx_d(1);
               grant_tgt <= to_slv(tgt_v, 32);
               tgt_v     := tgt_v + 1;
            end if;
         end if;
      end process p_grant;

      i_engine : entity work.engine
         generic map (
            G_PUZZLE => C_PUZ,
            G_FIRST  => 0
         )
         port map (
            clk_i         => clk,
            rst_i         => rst,
            run_i         => not finished(n),  -- Idle when done (16x16)
            halt_i        => '0',
            credit_i      => '0',
            credit_ctx_i  => "000",
            hold_i        => '0',
            hold_ctx_i    => "000",
            grant_i       => grant,
            grant_ctx_i   => grant_ctx,
            grant_tgt_i   => grant_tgt,
            ctx_o         => ctx,
            commit_o      => commit,
            count_o       => count,
            sol_o         => sol,
            claim_o       => claim,
            lvl_o         => lvl,
            anchor_o      => anchor,
            slot_o        => slot,
            skip_o        => skip,
            busy_o        => open,
            ctx_done_o    => open,
            done_o        => done,
            path_ctx_i    => "000",
            path_lvl_i    => "00000",
            path_anchor_o => open,
            path_slot_o   => open,
            path_vis_o    => open
         ); -- i_engine

      gen_trace : if C_TRACE generate

         gen_ctx : for x in 0 to C_STAGES-1 generate

            p_trace : process
               file     f_v      : text;
               variable l_v      : line;
               variable lvl_v    : integer;
               variable anchor_v : integer;
               variable slot_v   : integer;
               variable count_v  : integer;
               variable skip_v   : integer;
               variable sol_v    : integer;
               variable pass_v   : natural := 0;
            begin
               file_open(f_v, "build/model/" & trim(C_NAME) & "_" & integer'image(x) & ".trace",
                         read_mode);
               wait until rst = '0';
               loop
                  wait until rising_edge(clk);
                  if commit = '1' and to_integer(ctx) = x and not (C_PART and endfile(f_v)) then
                     assert not endfile(f_v)
                        report C_NAME & " ctx " & integer'image(x) & ": more passes than the model"
                        severity failure;
                     readline(f_v, l_v);
                     read(l_v, lvl_v);
                     read(l_v, anchor_v);
                     read(l_v, slot_v);
                     read(l_v, count_v);
                     read(l_v, skip_v);
                     read(l_v, sol_v);
                     assert to_integer(lvl) = lvl_v and to_integer(anchor) = anchor_v and
                            to_integer(slot) = slot_v and to_integer("" & count) = count_v and
                            to_integer("" & skip) = skip_v and to_integer("" & sol) = sol_v
                        report C_NAME & " ctx " & integer'image(x) & " pass " &
                               integer'image(pass_v) & ": got " &
                               to_string(to_integer(lvl)) & " " & to_string(to_integer(anchor)) &
                               " " & to_string(to_integer(slot)) & " " & to_string(count) & " " &
                               to_string(skip) & " " & to_string(sol) & ", expected " &
                               integer'image(lvl_v) & " " & integer'image(anchor_v) & " " &
                               integer'image(slot_v) & " " & integer'image(count_v) & " " &
                               integer'image(skip_v) & " " & integer'image(sol_v)
                        severity failure;
                     pass_v := pass_v + 1;
                  end if;
                  if endfile(f_v) then
                     trace_done(x) <= '1';
                  end if;
               end loop;
            end process p_trace;

         end generate gen_ctx;

      else generate

         trace_done <= (others => '1');

      end generate gen_trace;

      p_count : process
         variable nodes_v  : natural := 1;  -- The root
         variable sols_v   : natural := 0;
         variable cycles_v : natural := 0;
         variable min_v    : natural;
      begin
         wait until rst = '0';
         wait until rising_edge(clk);
         -- A partial trace: only the passes of the trace are checked
         if C_PART then
            wait until trace_done = (trace_done'range => '1');
            report C_NAME & ": the first passes of every context, OK";
            finished(n) <= '1';
            wait;
         end if;
         while done = '0' loop
            if count = '1' then
               nodes_v := nodes_v + 1;
            end if;
            if sol = '1' then
               sols_v := sols_v + 1;
            end if;
            cycles_v := cycles_v + 1;
            wait until rising_edge(clk);
         end loop;
         -- Nothing is committed after the end
         for i in 1 to 20 loop
            assert commit = '0'
               report C_NAME & ": a pass after the end"
               severity failure;
            wait until rising_edge(clk);
         end loop;

         assert nodes_v = C_MODEL(C_PUZ).nodes and sols_v = C_MODEL(C_PUZ).solutions
            report C_NAME & ": " & integer'image(nodes_v) & " nodes and " &
                   integer'image(sols_v) & " solutions, expected " &
                   integer'image(C_MODEL(C_PUZ).nodes) & " and " &
                   integer'image(C_MODEL(C_PUZ).solutions)
            severity failure;
         assert trace_done = (trace_done'range => '1')
            report C_NAME & ": not all the passes of the model were done"
            severity failure;
         min_v := 8 * C_MODEL(C_PUZ).max_passes;
         assert cycles_v >= min_v and cycles_v <= min_v + 16
            report C_NAME & ": " & integer'image(cycles_v) & " clock cycles, expected " &
                   integer'image(min_v) & " to " & integer'image(min_v + 16)
            severity failure;
         report C_NAME & ": " & integer'image(nodes_v) & " nodes, " & integer'image(sols_v) &
                " solutions, " & integer'image(cycles_v) & " clock cycles, OK";
         finished(n) <= '1';
         wait;
      end process p_count;

   end generate gen_dut;

end architecture simulation;
