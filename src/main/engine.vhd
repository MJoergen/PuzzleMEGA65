-- This is the search engine of one puzzle (G_PUZZLE, see puzzle_pkg.vhd). It
-- searches the tree of the positions depth first, in the same order as the
-- C++ program, with C_STAGES (8) search contexts interleaved in a pipeline,
-- so it visits one position (node) in every clock cycle.
--
-- The search
-- ----------
-- A node is a partly filled board. Its *anchor* is the lowest empty square
-- (in row-major order), and its children are the placements of an unused
-- piece that cover the anchor, i.e. the *slots* (the orientations of the
-- pieces, see tools/puzzles.py) whose lowest square is placed on the anchor.
-- All the squares below the anchor are full, and no piece reaches further
-- than C_W-1 squares beyond its own anchor, so the board of a node is the
-- anchor (base) and a window of C_W bits (win) of the squares from the anchor
-- on: all the squares beyond the window are empty. The node also has the set
-- of pieces used so far (used), and the set of its children that have not
-- been visited yet (f, one bit for each slot).
--
-- A child is made by placing slot k: the window becomes win or shape(k), and
-- is then shifted right by the number of its trailing ones t, which moves the
-- anchor to the next empty square (base + t). The children of the child are
-- the slots that are inside the board at the new anchor (C_VALID), whose
-- piece is unused, and which do not overlap the window. All of them are
-- tested in parallel; the shapes are constants, so each test is a NOR of the
-- 2 to 20 bits of the window under the shape. When all the pieces are placed
-- and the board is full (the anchor is beyond the last square), the child is
-- a solution.
--
-- A *pass* visits one node: it takes the lowest bit k of f of the current
-- node, makes child k, and finds its children. If the child has children, it
-- becomes the current node. Otherwise the current node stays, and the next
-- pass visits its next child, or, when it has no more children, the nearest
-- ancestor that has children left becomes the current node: the ancestors
-- of the current node are kept on a stack (ds and fs, one entry for each
-- context and level), and the bit vector nonempty shows which of them have
-- children left, so going back up the tree costs nothing. When no ancestor
-- has children left, the search of the context is done.
--
-- The contexts
-- ------------
-- A pass is pipelined in C_STAGES stages, and every stage holds one of the
-- C_STAGES contexts, which move through the stages as a ring: the last stage
-- feeds the first one. Each context is an independent search, which starts a
-- new pass every C_STAGES clock cycles (when it may, see below).
--
-- The tree is split at the depth C_D (see puzzle_pkg.vhd) between all the
-- contexts of the puzzle, i.e. of all its engines (solver.vhd), numbered
-- G_FIRST + id for the contexts of this engine. Every context walks the tree
-- down to the depth C_D. The nodes at depth C_D are numbered j = 0, 1, ...
-- in the order of the search, and each context has a target (tgt_r): it owns
-- the node whose number is its target, i.e. searches its subtree, and it
-- skips the other nodes at depth C_D (they get no children, and are not
-- counted). When a context owns a node, it claims a new target (claim_o),
-- which the solver hands out from a global counter (grant_*). The grant
-- comes a few clock cycles later, long before the context's next pass. At
-- the start the target of each context is its number. The nodes above the
-- depth C_D (and their solutions) are only counted by context 0, and the
-- root is counted by the solver. So the counts of all the contexts add up to
-- the counts of the C++ program.
--
-- The stages
-- ----------
--   0  The next current node of the context (after the commit of its last
--      pass: the child, the same node, or an ancestor (pop)), and start a
--      pass (if the context may). The stack is read at the address of the
--      next current node, which is needed after a pop.
--   1  Take the current node from the stack after a pop.
--   2  The lowest bit of f (the next child), and the remaining children.
--   3  The window of the child (win or shape), its pieces, and the slot.
--   4  The number of trailing ones of the window of the child (t), and
--      whether the child is the target (if it is at depth C_D).
--   5  Shift the window right by t, and move the anchor by t.
--   6  The children of the child, and whether it is owned, counted, skipped,
--      or a solution.
--   7  Commit the pass: write the current node to the stack (it becomes an
--      ancestor if the search goes down to the child; otherwise the write
--      does no harm), the path, and whether the child has children.
--
-- Control
-- -------
-- A context starts a pass when run_i is high (the modes "all" and "next"),
-- or when it has a credit (credit_i, the modes "slow" and "one step"), and
-- it is not done, not held (hold_i, while its path is read), and halt_i is
-- low. The credit is used up by a pass that visits a node that is not
-- skipped, so a step always shows a new position. When halt_i is high, no
-- pass is started, and no pass is committed: the solver sets it at once
-- after a solution in the mode "next", so the passes after the solution are
-- not committed, and are done again when the search goes on.
--
-- The last stage shows every clock cycle which context is in it (ctx_o), and
-- whether its pass is committed (commit_o), and if so whether its node is
-- counted (count_o), a solution (sol_o), or owned (claim_o). These outputs
-- are combinational (registers and halt_i), so that the solver can stop all
-- engines in the next clock cycle. The visited node (its level, and the
-- anchor and the slot of its last piece) and whether it is skipped are also
-- shown, for the testbench (they are not used by the design).
--
-- The path of each context, i.e. the placements (anchor and slot) of the
-- last visited node, is stored for the picture of the board (path_*). The
-- read port is registered. While a context is held, its path does not change
-- once its last pass has left the pipeline and its path is written (busy_o
-- low).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;

entity engine is
   generic (
      G_PUZZLE  : natural;                     -- An index into C_PUZZLES
      G_FIRST   : natural                      -- Number of the first context
   );
   port (
      clk_i         : in  std_logic;
      rst_i         : in  std_logic;           -- Start the search again

      -- Control of the passes
      run_i         : in  std_logic;           -- All contexts may start passes
      halt_i        : in  std_logic;           -- No pass is started or committed
      credit_i      : in  std_logic;           -- One step for the context credit_ctx_i
      credit_ctx_i  : in  std_logic_vector(log2(C_STAGES)-1 downto 0);
      hold_i        : in  std_logic;           -- The context hold_ctx_i starts no pass
      hold_ctx_i    : in  std_logic_vector(log2(C_STAGES)-1 downto 0);

      -- New targets
      grant_i       : in  std_logic;
      grant_ctx_i   : in  std_logic_vector(log2(C_STAGES)-1 downto 0);
      grant_tgt_i   : in  std_logic_vector(31 downto 0);

      -- The context in the last stage, and its pass (combinational)
      ctx_o         : out std_logic_vector(log2(C_STAGES)-1 downto 0);
      commit_o      : out std_logic;           -- The pass is committed
      count_o       : out std_logic;           -- ... and its node is counted
      sol_o         : out std_logic;           -- ... and it is a solution
      claim_o       : out std_logic;           -- ... and it is owned
      lvl_o         : out std_logic_vector(4 downto 0);   -- The visited node
      anchor_o      : out std_logic_vector(8 downto 0);
      slot_o        : out std_logic_vector(7 downto 0);
      skip_o        : out std_logic;

      busy_o        : out std_logic_vector(C_STAGES-1 downto 0);
      ctx_done_o    : out std_logic_vector(C_STAGES-1 downto 0);
      done_o        : out std_logic;           -- All the contexts are done

      -- Read port of the paths (registered)
      path_ctx_i    : in  std_logic_vector(log2(C_STAGES)-1 downto 0);
      path_lvl_i    : in  std_logic_vector(4 downto 0);
      path_anchor_o : out std_logic_vector(8 downto 0);
      path_slot_o   : out std_logic_vector(7 downto 0);
      path_vis_o    : out std_logic_vector(4 downto 0)    -- Level of the last visited node
   );
end entity engine;

architecture rtl of engine is

   constant C_P         : puzzle_t := C_PUZZLES(G_PUZZLE);
   constant C_N         : positive := C_P.pieces;
   constant C_K         : positive := C_P.slots;
   constant C_W         : positive := C_P.width;
   constant C_B         : positive := C_P.squares;
   constant C_D         : positive := C_P.depth;

   constant C_CTX_BITS  : natural  := log2(C_STAGES);
   constant C_LVL_BITS  : natural  := maximum(log2(C_N), 1);
   constant C_ADDR_BITS : natural  := C_CTX_BITS + C_LVL_BITS;

   -- The shapes of the slots, as masks of the window
   type shape_vector is array (0 to C_K-1) of std_logic_vector(C_W-1 downto 0);

   function shapes return shape_vector is
      variable r_v : shape_vector;
      variable s_v : slot_t;
   begin
      for k in 0 to C_K-1 loop
         s_v    := C_SLOTS(C_P.first_slot + k);
         r_v(k) := (others => '0');
         for i in 0 to s_v.size-1 loop
            r_v(k)(s_v.offsets(i)) := '1';
         end loop;
      end loop;
      return r_v;
   end function shapes;

   -- The slots that are inside the board at each anchor. The anchor C_B
   -- (beyond the last square, the board is full) has none.
   type valid_vector is array (0 to C_B) of std_logic_vector(C_K-1 downto 0);

   function valid_rom return valid_vector is
      variable r_v   : valid_vector;
      variable s_v   : slot_t;
      variable row_v : natural;
      variable col_v : natural;
   begin
      for a in 0 to C_B-1 loop
         row_v := a / C_P.cols;
         col_v := a mod C_P.cols;
         for k in 0 to C_K-1 loop
            s_v       := C_SLOTS(C_P.first_slot + k);
            r_v(a)(k) := '0';
            if row_v + s_v.down < C_P.rows and col_v >= s_v.left and
               col_v + s_v.right < C_P.cols
            then
               r_v(a)(k) := '1';
            end if;
         end loop;
      end loop;
      r_v(C_B) := (others => '0');
      return r_v;
   end function valid_rom;

   -- The piece and the squares (the number and the offsets) of each slot
   type piece_vector is array (0 to C_K-1) of natural range 0 to C_N-1;
   type size_vector is array (0 to C_K-1) of natural range 1 to C_MAX_SIZE;
   type offsets_vector is array (0 to C_K-1) of offsets_t;

   function pieces return piece_vector is
      variable r_v : piece_vector;
   begin
      for k in 0 to C_K-1 loop
         r_v(k) := C_SLOTS(C_P.first_slot + k).piece;
      end loop;
      return r_v;
   end function pieces;

   function sizes return size_vector is
      variable r_v : size_vector;
   begin
      for k in 0 to C_K-1 loop
         r_v(k) := C_SLOTS(C_P.first_slot + k).size;
      end loop;
      return r_v;
   end function sizes;

   function offsets return offsets_vector is
      variable r_v : offsets_vector;
   begin
      for k in 0 to C_K-1 loop
         r_v(k) := C_SLOTS(C_P.first_slot + k).offsets;
      end loop;
      return r_v;
   end function offsets;

   constant C_SHAPES    : shape_vector   := shapes;
   constant C_VALID     : valid_vector   := valid_rom;
   constant C_PIECE     : piece_vector   := pieces;
   constant C_SIZE      : size_vector    := sizes;
   constant C_OFFSETS   : offsets_vector := offsets;

   -- The state of a context, which moves through the stages, and the values
   -- of its pass, which are filled in by the stages
   type stage_t is record
      -- The state
      id        : natural range 0 to C_STAGES-1;
      valid     : std_logic;                          -- A pass is in this stage
      commit    : std_logic;                          -- The pass has been committed
      lvl       : natural range 0 to C_N-1;           -- Level of the current node
      pop       : std_logic;                          -- The current node is on the stack
      nonempty  : std_logic_vector(C_N-1 downto 0);   -- Ancestors with children left
      base      : natural range 0 to C_B;             -- The current node
      win       : std_logic_vector(C_W-1 downto 0);
      used      : std_logic_vector(C_N-1 downto 0);
      f         : std_logic_vector(C_K-1 downto 0);
      j         : natural range 0 to C_P.frontier;    -- Nodes at depth C_D so far
      done      : std_logic;
      -- The pass
      onehot    : std_logic_vector(C_K-1 downto 0);   -- The slot of the child
      f_rem     : std_logic_vector(C_K-1 downto 0);   -- The children left
      rem_any   : std_logic;
      slot      : std_logic_vector(7 downto 0);
      c         : std_logic_vector(C_W-1 downto 0);   -- The window of the child
      used_c    : std_logic_vector(C_N-1 downto 0);
      t         : natural range 0 to C_W;
      base_c    : natural range 0 to C_B;
      f_child   : std_logic_vector(C_K-1 downto 0);   -- The children of the child
      child_any : std_logic;
      top       : std_logic;                          -- The child is above depth C_D
      frontier  : std_logic;                          -- The child is at depth C_D
      last      : std_logic;                          -- The child has all the pieces
      hit       : std_logic;                          -- The target is the next node at C_D
      owned     : std_logic;
      skip      : std_logic;
      counted   : std_logic;
      sol       : std_logic;
   end record stage_t;

   type stage_vector is array (natural range <>) of stage_t;

   -- The initial state of each context: the root
   function init (id : natural) return stage_t is
      variable r_v : stage_t;
   begin
      r_v.id        := id;
      r_v.valid     := '0';
      r_v.commit    := '0';
      r_v.lvl       := 0;
      r_v.pop       := '0';
      r_v.nonempty  := (others => '0');
      r_v.base      := 0;
      r_v.win       := (others => '0');
      r_v.used      := (others => '0');
      r_v.f         := C_VALID(0);
      r_v.j         := 0;
      r_v.done      := '0';
      if C_VALID(0) = (C_VALID(0)'range => '0') then
         r_v.done := '1';
      end if;
      r_v.onehot    := (others => '0');
      r_v.f_rem     := (others => '0');
      r_v.rem_any   := '0';
      r_v.slot      := (others => '0');
      r_v.c         := (others => '0');
      r_v.used_c    := (others => '0');
      r_v.t         := 0;
      r_v.base_c    := 0;
      r_v.f_child   := (others => '0');
      r_v.child_any := '0';
      r_v.top       := '0';
      r_v.frontier  := '0';
      r_v.last      := '0';
      r_v.hit       := '0';
      r_v.owned     := '0';
      r_v.skip      := '0';
      r_v.counted   := '0';
      r_v.sol       := '0';
      return r_v;
   end function init;

   -- The logic of the stages: each function gets the input register of the
   -- stage, and returns the output register.

   -- Stage 0: The next current node, and start a pass if the context may
   function stage0 (s : stage_t; may : std_logic) return stage_t is
      variable s_v : stage_t;
      variable m_v : std_logic_vector(C_N-1 downto 0);
   begin
      s_v := s;
      if s.commit = '1' then
         if s.child_any = '1' then
            -- Go down to the child
            s_v.nonempty(s.lvl) := s.rem_any;
            s_v.lvl             := s.lvl + 1;
            s_v.base            := s.base_c;
            s_v.win             := s.c;
            s_v.used            := s.used_c;
            s_v.f               := s.f_child;
         elsif s.rem_any = '1' then
            -- The next child of the current node
            s_v.f := s.f_rem;
         else
            -- Go up to the nearest ancestor with children left
            m_v := s.nonempty;
            for l in 0 to C_N-1 loop
               if l >= s.lvl then
                  m_v(l) := '0';
               end if;
            end loop;
            if m_v = (m_v'range => '0') then
               s_v.done := '1';
            else
               for l in 0 to C_N-1 loop
                  if m_v(l) = '1' then
                     s_v.lvl := l;
                  end if;
               end loop;
               s_v.pop := '1';
            end if;
         end if;
      end if;
      s_v.commit := '0';
      s_v.valid  := may and not s_v.done;
      return s_v;
   end function stage0;

   -- Stage 1: The current node from the stack after a pop
   function stage1 (s : stage_t; ds_rd : std_logic_vector; fs_rd : std_logic_vector)
   return stage_t is
      variable s_v : stage_t;
   begin
      s_v := s;
      if s.pop = '1' then
         s_v.base := to_integer(ds_rd(ds_rd'high downto C_W + C_N));
         s_v.win  := ds_rd(C_W + C_N-1 downto C_N);
         s_v.used := ds_rd(C_N-1 downto 0);
         s_v.f    := fs_rd;
         s_v.pop  := '0';
      end if;
      return s_v;
   end function stage1;

   -- Stage 2: The next child
   function stage2 (s : stage_t) return stage_t is
      variable s_v : stage_t;
   begin
      s_v        := s;
      s_v.onehot := lowest_one(s.f);
      s_v.f_rem  := s.f and not s_v.onehot;
      return s_v;
   end function stage2;

   -- Stage 3: The window of the child, and its pieces
   function stage3 (s : stage_t) return stage_t is
      variable s_v : stage_t;
   begin
      s_v        := s;
      s_v.c      := s.win;
      s_v.used_c := s.used;
      for k in 0 to C_K-1 loop
         if s.onehot(k) = '1' then
            s_v.c                  := s_v.c or C_SHAPES(k);
            s_v.used_c(C_PIECE(k)) := '1';
         end if;
      end loop;
      s_v.slot     := encode(s.onehot, 8);
      s_v.rem_any  := or s.f_rem;
      s_v.top      := to_sl(s.lvl + 1 < C_D);
      s_v.frontier := to_sl(s.lvl + 1 = C_D);
      s_v.last     := to_sl(s.lvl + 1 = C_N);
      return s_v;
   end function stage3;

   -- Stage 4: The trailing ones of the window of the child, i.e. its lowest
   -- zero, where a zero is appended beyond the window (all the squares
   -- beyond the window are empty). And whether the child is the target of the
   -- context, if it is at depth C_D (the target does not change during a
   -- pass: a new target is granted while the context is in stage 1 or 2).
   function stage4 (s : stage_t; tgt : natural) return stage_t is
      variable s_v : stage_t;
   begin
      s_v     := s;
      s_v.t   := trailing_ones(s.c);
      s_v.hit := to_sl(s.j = tgt);
      return s_v;
   end function stage4;

   -- Stage 5: Move the anchor of the child to the next empty square
   function stage5 (s : stage_t) return stage_t is
      variable s_v : stage_t;
   begin
      s_v        := s;
      s_v.c      := s.c srl s.t;
      s_v.base_c := s.base + s.t;
      return s_v;
   end function stage5;

   -- Stage 6: The children of the child, and whether it is owned, counted,
   -- skipped, or a solution. The slots that fit are those that are inside the
   -- board, whose piece is unused, and which do not overlap the window.
   function stage6 (s : stage_t) return stage_t is
      variable s_v   : stage_t;
      variable fit_v : std_logic_vector(C_K-1 downto 0);
   begin
      s_v   := s;

      fit_v := C_VALID(s.base_c);
      for k in 0 to C_K-1 loop
         if s.used_c(C_PIECE(k)) = '1' then
            fit_v(k) := '0';
         end if;
         for i in 0 to C_SIZE(k)-1 loop
            if s.c(C_OFFSETS(k)(i)) = '1' then
               fit_v(k) := '0';
            end if;
         end loop;
      end loop;

      -- The split of the tree between the contexts
      s_v.owned := s.frontier and s.hit;
      s_v.skip  := s.frontier and not s.hit;
      if s.top = '1' then
         s_v.counted := to_sl(G_FIRST + s.id = 0);
      else
         s_v.counted := not s_v.skip;
      end if;

      s_v.sol := '0';
      if s.last = '1' and s.base_c = C_B then
         s_v.sol := s_v.counted;
      end if;

      s_v.f_child := fit_v;
      if s.last = '1' or s_v.skip = '1' then
         s_v.f_child := (others => '0');
      end if;
      return s_v;
   end function stage6;

   -- Stage 7: Commit the pass
   function stage7 (s : stage_t; halt : std_logic) return stage_t is
      variable s_v : stage_t;
   begin
      s_v           := s;
      s_v.commit    := s.valid and not halt;
      s_v.valid     := '0';
      s_v.child_any := or s.f_child;
      if s_v.commit = '1' and s.frontier = '1' then
         s_v.j := s.j + 1;
      end if;
      return s_v;
   end function stage7;

   -- The input register of stage 7, copied to signals for the outputs (the
   -- registers of the stages are variables of p_ring)
   signal r7_id       : natural range 0 to C_STAGES-1;
   signal r7_valid    : std_logic;
   signal r7_counted  : std_logic;
   signal r7_sol      : std_logic;
   signal r7_owned    : std_logic;
   signal r7_skip     : std_logic;
   signal r7_lvl      : natural range 0 to C_N-1;
   signal r7_base     : natural range 0 to C_B;
   signal r7_slot     : std_logic_vector(7 downto 0);
   signal commit_s    : std_logic;

   -- The stack: the current node of each ancestor (ds), and its children left
   -- (fs), at the address context & level. It is distributed RAM: the read
   -- address is registered (the address of the context in stage 0), and the
   -- read is asynchronous (stage 1). The write is one clock cycle after the
   -- commit, which is still before the context reads the stack again.
   constant C_DS_BITS : natural := 9 + C_W + C_N;
   type ds_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(C_DS_BITS-1 downto 0);
   type fs_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(C_K-1 downto 0);
   signal ds          : ds_vector;
   signal fs          : fs_vector;
   signal rd_addr     : std_logic_vector(C_ADDR_BITS-1 downto 0);
   signal ds_rd       : std_logic_vector(C_DS_BITS-1 downto 0);
   signal fs_rd       : std_logic_vector(C_K-1 downto 0);
   signal wr_en       : std_logic;
   signal wr_addr     : std_logic_vector(C_ADDR_BITS-1 downto 0);
   signal wr_ds       : std_logic_vector(C_DS_BITS-1 downto 0);
   signal wr_fs       : std_logic_vector(C_K-1 downto 0);
   signal wr_path     : std_logic_vector(16 downto 0);

   attribute ram_style : string;
   attribute ram_style of ds : signal is "distributed";
   attribute ram_style of fs : signal is "distributed";

   -- The path: the anchor and the slot of the placement at each level of each
   -- context, and the level of the last visited node of each context
   type path_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(16 downto 0);
   type vis_vector is array (0 to C_STAGES-1) of std_logic_vector(4 downto 0);
   signal path        : path_vector;
   signal vis         : vis_vector;

   -- The target of each context, one step for each context (see credit_i),
   -- the contexts that are done, and those that have a pass in the pipeline
   type tgt_vector is array (0 to C_STAGES-1) of natural;
   signal tgt_r       : tgt_vector;
   signal credit_r    : std_logic_vector(C_STAGES-1 downto 0);
   signal cdone_r     : std_logic_vector(C_STAGES-1 downto 0);
   signal busy_r      : std_logic_vector(C_STAGES-1 downto 0);

   signal rst_r       : std_logic;

   function addr (id : natural; lvl : natural) return std_logic_vector is
   begin
      return to_slv(id, C_CTX_BITS) & to_slv(lvl, C_LVL_BITS);
   end function addr;

begin

   assert C_STAGES = 8
      report "The engine has 8 stages"
      severity failure;

   assert C_K <= 256 and C_B <= 256 and C_N <= 31
      report "At most 256 slots, 256 squares, and 31 pieces"
      severity failure;

   -- The reset goes to many registers, so it is registered here first
   p_rst : process (clk_i)
   begin
      if rising_edge(clk_i) then
         rst_r <= rst_i;
      end if;
   end process p_rst;


   ----------------------------------------------------------------
   -- The stages
   ----------------------------------------------------------------

   -- The ring of the registers of the stages: ring_v(s) is the input register
   -- of stage s. Each clock cycle, every context moves on by one stage, so
   -- the stages are done from the last to the first, each before its input
   -- register is overwritten. After a reset, stage s holds context
   -- (C_STAGES - s) mod C_STAGES.
   p_ring : process (clk_i)
      variable ring_v : stage_vector(0 to C_STAGES-1);
      variable s7_v   : stage_t;
      variable may_v  : std_logic;
      variable busy_v : std_logic_vector(C_STAGES-1 downto 0);
   begin
      if rising_edge(clk_i) then
         -- Stage 7: the stack and the path are written one clock cycle later
         s7_v    := stage7(ring_v(7), halt_i);
         wr_en   <= s7_v.commit;
         wr_addr <= addr(s7_v.id, s7_v.lvl);
         wr_ds   <= to_slv(s7_v.base, 9) & s7_v.win & s7_v.used;
         wr_fs   <= s7_v.f_rem;
         wr_path <= to_slv(s7_v.base, 9) & s7_v.slot;
         if s7_v.commit = '1' then
            vis(s7_v.id) <= to_slv(s7_v.lvl + 1, 5);
            if s7_v.skip = '0' then
               credit_r(s7_v.id) <= '0';
            end if;
         end if;

         ring_v(7) := stage6(ring_v(6));
         ring_v(6) := stage5(ring_v(5));
         ring_v(5) := stage4(ring_v(4), tgt_r(ring_v(4).id));
         ring_v(4) := stage3(ring_v(3));
         ring_v(3) := stage2(ring_v(2));
         ring_v(2) := stage1(ring_v(1), ds_rd, fs_rd);

         -- Stage 0
         may_v := (run_i or credit_r(ring_v(0).id)) and not halt_i;
         if hold_i = '1' and to_integer(hold_ctx_i) = ring_v(0).id then
            may_v := '0';
         end if;
         ring_v(1) := stage0(ring_v(0), may_v);
         rd_addr   <= addr(ring_v(1).id, ring_v(1).lvl);
         cdone_r(ring_v(1).id) <= ring_v(1).done;

         ring_v(0) := s7_v;

         -- New targets and credits
         if grant_i = '1' then
            tgt_r(to_integer(grant_ctx_i)) <= to_integer(grant_tgt_i);
         end if;
         if credit_i = '1' then
            credit_r(to_integer(credit_ctx_i)) <= '1';
         end if;

         if rst_r = '1' then
            for s in 0 to C_STAGES-1 loop
               ring_v(s) := init((C_STAGES - s) mod C_STAGES);
            end loop;
            wr_en    <= '0';
            vis      <= (others => (others => '0'));
            credit_r <= (others => '0');
            cdone_r  <= (others => init(0).done);
            for i in 0 to C_STAGES-1 loop
               tgt_r(i) <= G_FIRST + i;
            end loop;
         end if;

         -- The input register of stage 7
         r7_id      <= ring_v(7).id;
         r7_valid   <= ring_v(7).valid;
         r7_counted <= ring_v(7).counted;
         r7_sol     <= ring_v(7).sol;
         r7_owned   <= ring_v(7).owned;
         r7_skip    <= ring_v(7).skip;
         r7_lvl     <= ring_v(7).lvl;
         r7_base    <= ring_v(7).base;
         r7_slot    <= ring_v(7).slot;

         -- The contexts that have a pass in the stages 1 to 7, or whose path is
         -- still to be written
         busy_v := (others => '0');
         for s in 1 to C_STAGES-1 loop
            if ring_v(s).valid = '1' then
               busy_v(ring_v(s).id) := '1';
            end if;
         end loop;
         if s7_v.commit = '1' then
            busy_v(s7_v.id) := '1';
         end if;
         busy_r <= busy_v;
      end if;
   end process p_ring;


   ----------------------------------------------------------------
   -- The stack and the path
   ----------------------------------------------------------------

   p_ram : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wr_en = '1' then
            ds(to_integer(wr_addr))   <= wr_ds;
            fs(to_integer(wr_addr))   <= wr_fs;
            path(to_integer(wr_addr)) <= wr_path;
         end if;
      end if;
   end process p_ram;

   ds_rd <= ds(to_integer(rd_addr));
   fs_rd <= fs(to_integer(rd_addr));

   p_path : process (clk_i)
   begin
      if rising_edge(clk_i) then
         path_anchor_o <= path(to_integer(path_ctx_i & path_lvl_i(C_LVL_BITS-1 downto 0)))(16 downto 8);
         path_slot_o   <= path(to_integer(path_ctx_i & path_lvl_i(C_LVL_BITS-1 downto 0)))( 7 downto 0);
         path_vis_o    <= vis(to_integer(path_ctx_i));
      end if;
   end process p_path;


   ----------------------------------------------------------------
   -- Outputs
   ----------------------------------------------------------------

   commit_s   <= r7_valid and not halt_i;

   ctx_o      <= to_slv(r7_id, C_CTX_BITS);
   commit_o   <= commit_s;
   count_o    <= commit_s and r7_counted;
   sol_o      <= commit_s and r7_sol;
   claim_o    <= commit_s and r7_owned;
   lvl_o      <= to_slv(r7_lvl + 1, 5);
   anchor_o   <= to_slv(r7_base, 9);
   slot_o     <= r7_slot;
   skip_o     <= r7_skip;
   busy_o     <= busy_r;
   ctx_done_o <= cdone_r;
   done_o     <= and cdone_r;

end architecture rtl;
