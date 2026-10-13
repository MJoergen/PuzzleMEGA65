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
-- of the current node are kept on a stack (in the RAMs ds and fs, one entry
-- for each context and level), and the bit vector nonempty shows which of
-- them have children left, so going back up the tree costs nothing. When no
-- ancestor has children left, the search of the context is done.
--
-- The contexts
-- ------------
-- A pass is pipelined in C_STAGES stages, and every stage holds one of the
-- C_STAGES contexts, which move through the stages as a ring (r0 to r7): the
-- last stage feeds the first one. Each context is an independent search,
-- which starts a new pass every C_STAGES clock cycles (when it may, see
-- below). The tree is split at the depth C_D (see puzzle_pkg.vhd) between
-- all the G_NUM_CTX contexts of the puzzle (of all its engines, G_FIRST is
-- the number of the first context of this engine): every context walks the
-- tree down to the depth C_D, and the subtree below the j-th node at depth
-- C_D (counted from 0) belongs to the context j mod G_NUM_CTX. The other
-- contexts visit the node, but skip it (it gets no children). The nodes above
-- the depth C_D (and their solutions) are only counted by context 0, and the
-- root is counted by the solver. So the counts of all the contexts add up to
-- the counts of the C++ program.
--
-- The stages
-- ----------
--   0  Start a pass of the context (if it may), and read the stack, which is
--      needed if the current node is an ancestor (pop).
--   1  Take the current node from the stack after a pop.
--   2  The lowest bit of f (the next child), and the remaining children.
--   3  The window of the child (win or shape), its pieces, and the slot.
--   4  The number of trailing ones of the window of the child (t).
--   5  Shift the window right by t, and move the anchor by t.
--   6  The children of the child, and whether it is counted, skipped, or a
--      solution.
--   7  Commit the pass: the next current node, the stack, and the path.
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
-- counted (count_o) and a solution (sol_o), and the context's counter of the
-- nodes at depth C_D (jcount_o, for the progress) and whether it is done
-- (cdone_o). These outputs are combinational, so the solver can stop all
-- engines in the next clock cycle. The visited node (its level, and the
-- anchor and the slot of its last piece) and whether it is skipped are also
-- shown, for the testbench (they are not used by the design).
--
-- The path of each context, i.e. the placements (anchor and slot) of the
-- last visited node, is stored for the picture of the board (path_*). The
-- read port is registered. While a context is held, its path does not change
-- once its last pass has left the pipeline (busy_o).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

use work.util_pkg.all;
use work.puzzle_pkg.all;

entity engine is
   generic (
      G_PUZZLE  : natural;                     -- An index into C_PUZZLES
      G_FIRST   : natural;                     -- Number of the first context
      G_NUM_CTX : positive                     -- Contexts on the puzzle, a power of two
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

      -- The context in the last stage, and its pass (combinational)
      ctx_o         : out std_logic_vector(log2(C_STAGES)-1 downto 0);
      commit_o      : out std_logic;           -- The pass is committed
      count_o       : out std_logic;           -- ... and its node is counted
      sol_o         : out std_logic;           -- ... and it is a solution
      jcount_o      : out std_logic_vector(31 downto 0);
      cdone_o       : out std_logic;
      lvl_o         : out std_logic_vector(4 downto 0);   -- The visited node
      anchor_o      : out std_logic_vector(8 downto 0);
      slot_o        : out std_logic_vector(7 downto 0);
      skip_o        : out std_logic;

      busy_o        : out std_logic_vector(C_STAGES-1 downto 0);
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

   constant C_SHAPES    : shape_vector := shapes;
   constant C_VALID     : valid_vector := valid_rom;
   constant C_PIECE     : piece_vector := pieces;
   constant C_SIZE      : size_vector := sizes;
   constant C_OFFSETS   : offsets_vector := offsets;

   -- The state of a context, which moves through the stages, and the values
   -- of its pass, which are filled in by the stages
   type stage_t is record
      -- The state
      id       : natural range 0 to C_STAGES-1;
      valid    : std_logic;                          -- A pass is in this stage
      lvl      : natural range 0 to C_N-1;           -- Level of the current node
      pop      : std_logic;                          -- The current node is on the stack
      nonempty : std_logic_vector(C_N-1 downto 0);   -- Ancestors with children left
      base     : natural range 0 to C_B;             -- The current node
      win      : std_logic_vector(C_W-1 downto 0);
      used     : std_logic_vector(C_N-1 downto 0);
      f        : std_logic_vector(C_K-1 downto 0);
      j        : natural range 0 to C_P.frontier;    -- Nodes at depth C_D so far
      done     : std_logic;
      -- The pass
      onehot   : std_logic_vector(C_K-1 downto 0);   -- The slot of the child
      f_rem    : std_logic_vector(C_K-1 downto 0);   -- The children left
      rem_any  : std_logic;
      slot     : std_logic_vector(7 downto 0);
      c        : std_logic_vector(C_W-1 downto 0);   -- The window of the child
      used_c   : std_logic_vector(C_N-1 downto 0);
      t        : natural range 0 to C_W;
      base_c   : natural range 0 to C_B;
      f_child  : std_logic_vector(C_K-1 downto 0);   -- The children of the child
      frontier : std_logic;                          -- The child is at depth C_D
      skip     : std_logic;
      counted  : std_logic;
      sol      : std_logic;
   end record stage_t;

   type stage_vector is array (natural range <>) of stage_t;

   -- The initial state of each context: the root
   function init (id : natural) return stage_t is
      variable r_v : stage_t;
   begin
      r_v.id       := id;
      r_v.valid    := '0';
      r_v.lvl      := 0;
      r_v.pop      := '0';
      r_v.nonempty := (others => '0');
      r_v.base     := 0;
      r_v.win      := (others => '0');
      r_v.used     := (others => '0');
      r_v.f        := C_VALID(0);
      r_v.j        := 0;
      r_v.done     := '0';
      if C_VALID(0) = (C_VALID(0)'range => '0') then
         r_v.done := '1';
      end if;
      r_v.onehot   := (others => '0');
      r_v.f_rem    := (others => '0');
      r_v.rem_any  := '0';
      r_v.slot     := (others => '0');
      r_v.c        := (others => '0');
      r_v.used_c   := (others => '0');
      r_v.t        := 0;
      r_v.base_c   := 0;
      r_v.f_child  := (others => '0');
      r_v.frontier := '0';
      r_v.skip     := '0';
      r_v.counted  := '0';
      r_v.sol      := '0';
      return r_v;
   end function init;

   -- The logic of the stages 0 to 6: each function gets the input register
   -- of the stage, and returns the output register.

   -- Stage 0: Start a pass, if the context may
   function stage0 (s : stage_t; run : std_logic; halt : std_logic; credit : std_logic;
                    hold : std_logic) return stage_t is
      variable s_v : stage_t;
   begin
      s_v       := s;
      s_v.valid := (run or credit) and not halt and not hold and not s.done;
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
      s_v.slot    := encode(s.onehot, 8);
      s_v.rem_any := or s.f_rem;
      return s_v;
   end function stage3;

   -- Stage 4: The trailing ones of the window of the child. This is the
   -- lowest zero of the window, where a zero beyond the window is appended
   -- (all the squares beyond the window are empty).
   function stage4 (s : stage_t) return stage_t is
      variable s_v : stage_t;
   begin
      s_v   := s;
      s_v.t := to_integer(encode(lowest_one(not ('0' & s.c)), log2(C_W+1)));
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

   -- Stage 6: The children of the child, and whether it is counted, skipped,
   -- or a solution. The slots that fit are those that are inside the board,
   -- whose piece is unused, and which do not overlap the window.
   function stage6 (s : stage_t) return stage_t is
      variable s_v   : stage_t;
      variable lvl_v : natural range 1 to C_N;
      variable fit_v : std_logic_vector(C_K-1 downto 0);
   begin
      s_v   := s;
      lvl_v := s.lvl + 1;

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
      s_v.frontier := '0';
      s_v.skip     := '0';
      if lvl_v = C_D then
         s_v.frontier := '1';
         if s.j mod G_NUM_CTX /= G_FIRST + s.id then
            s_v.skip := '1';
         end if;
      end if;
      if lvl_v < C_D then
         s_v.counted := '0';
         if G_FIRST + s.id = 0 then
            s_v.counted := '1';
         end if;
      else
         s_v.counted := not s_v.skip;
      end if;

      s_v.sol := '0';
      if lvl_v = C_N and s.base_c = C_B then
         s_v.sol := s_v.counted;
      end if;

      s_v.f_child := fit_v;
      if lvl_v = C_N or s_v.skip = '1' then
         s_v.f_child := (others => '0');
      end if;
      return s_v;
   end function stage6;

   -- The input register of the last stage (stage 7), and the next state of
   -- its context. The registers of the stages 0 to 6 are variables of p_ring.
   signal r7          : stage_t;
   signal next_s      : stage_t;
   signal commit_s    : std_logic;

   -- The stack: the current node of each ancestor (ds), and its children left
   -- (fs), at the address context & level. The read port is registered, and
   -- its address is that of the context in stage 0.
   constant C_DS_BITS : natural := 9 + C_W + C_N;
   type ds_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(C_DS_BITS-1 downto 0);
   type fs_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(C_K-1 downto 0);
   signal ds          : ds_vector;
   signal fs          : fs_vector;
   signal rd_addr     : std_logic_vector(C_ADDR_BITS-1 downto 0);
   signal ds_rd       : std_logic_vector(C_DS_BITS-1 downto 0);
   signal fs_rd       : std_logic_vector(C_K-1 downto 0);

   -- The path: the anchor and the slot of the placement at each level of each
   -- context, and the level of the last visited node of each context
   type path_vector is array (0 to 2**C_ADDR_BITS-1) of std_logic_vector(16 downto 0);
   type vis_vector is array (0 to C_STAGES-1) of std_logic_vector(4 downto 0);
   signal path        : path_vector;
   signal vis         : vis_vector;

   -- One step for each context, see credit_i
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

   assert 2**log2(G_NUM_CTX) = G_NUM_CTX and G_NUM_CTX >= C_STAGES
      report "G_NUM_CTX must be a power of two, and at least C_STAGES"
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
   -- The stages 0 to 6
   ----------------------------------------------------------------

   -- The ring of the registers of the stages: ring_v(s) is the input register
   -- of stage s, for s = 0 to 6, and r7 that of stage 7. Each clock cycle,
   -- every context moves on by one stage, so the stages are done from the
   -- last to the first, each before its input register is overwritten. After
   -- a reset, stage s holds context (C_STAGES - s) mod C_STAGES.
   p_ring : process (clk_i)
      variable ring_v : stage_vector(0 to C_STAGES-2);
      variable r7_v   : stage_t;
      variable busy_v : std_logic_vector(C_STAGES-1 downto 0);
      variable hold_v : std_logic;
   begin
      if rising_edge(clk_i) then
         r7_v      := stage6(ring_v(6));
         ring_v(6) := stage5(ring_v(5));
         ring_v(5) := stage4(ring_v(4));
         ring_v(4) := stage3(ring_v(3));
         ring_v(3) := stage2(ring_v(2));
         ring_v(2) := stage1(ring_v(1), ds_rd, fs_rd);
         hold_v    := '0';
         if hold_i = '1' and to_integer(hold_ctx_i) = ring_v(0).id then
            hold_v := '1';
         end if;
         ring_v(1) := stage0(ring_v(0), run_i, halt_i, credit_r(ring_v(0).id), hold_v);
         ring_v(0) := next_s;

         if rst_r = '1' then
            for s in 0 to C_STAGES-2 loop
               ring_v(s) := init((C_STAGES - s) mod C_STAGES);
            end loop;
            r7_v := init(1);
         end if;
         r7 <= r7_v;

         -- The stack is read at the address of the context in stage 0
         rd_addr <= addr(ring_v(0).id, ring_v(0).lvl);

         -- The contexts that have a pass in the stages 1 to 7
         busy_v := (others => '0');
         for s in 1 to C_STAGES-2 loop
            if ring_v(s).valid = '1' then
               busy_v(ring_v(s).id) := '1';
            end if;
         end loop;
         if r7_v.valid = '1' then
            busy_v(r7_v.id) := '1';
         end if;
         busy_r <= busy_v;
      end if;
   end process p_ring;

   p_rd : process (clk_i)
   begin
      if rising_edge(clk_i) then
         ds_rd <= ds(to_integer(rd_addr));
         fs_rd <= fs(to_integer(rd_addr));
      end if;
   end process p_rd;


   ----------------------------------------------------------------
   -- Stage 7: Commit the pass
   ----------------------------------------------------------------

   commit_s <= r7.valid and not halt_i;

   -- The next state of the context. The condition of commit_s is repeated
   -- here, so that this process never sees a new r7 with an old commit_s (in
   -- a delta cycle of the simulation).
   p_next : process (all)
      variable s_v : stage_t;
      variable m_v : std_logic_vector(C_N-1 downto 0);
   begin
      s_v       := r7;
      s_v.valid := '0';
      if r7.valid = '1' and halt_i = '0' then
         if s_v.frontier = '1' then
            s_v.j := s_v.j + 1;
         end if;
         if s_v.f_child /= (s_v.f_child'range => '0') then
            -- Go down to the child
            s_v.nonempty(s_v.lvl) := s_v.rem_any;
            s_v.lvl               := s_v.lvl + 1;
            s_v.base              := s_v.base_c;
            s_v.win               := s_v.c;
            s_v.used              := s_v.used_c;
            s_v.f                 := s_v.f_child;
         elsif s_v.rem_any = '1' then
            -- The next child of the current node
            s_v.f := s_v.f_rem;
         else
            -- Go up to the nearest ancestor with children left
            m_v := s_v.nonempty;
            for l in 0 to C_N-1 loop
               if l >= s_v.lvl then
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
      next_s <= s_v;
   end process p_next;

   p_stage7 : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if commit_s = '1' then
            -- The path of the visited node
            path(to_integer(addr(r7.id, r7.lvl))) <= to_slv(r7.base, 9) & r7.slot;
            vis(r7.id) <= to_slv(r7.lvl + 1, 5);

            -- The current node becomes an ancestor
            if r7.f_child /= (r7.f_child'range => '0') then
               ds(to_integer(addr(r7.id, r7.lvl))) <= to_slv(r7.base, 9) & r7.win & r7.used;
               fs(to_integer(addr(r7.id, r7.lvl))) <= r7.f_rem;
            end if;

            -- The step is used up, unless the node is skipped
            if r7.skip = '0' then
               credit_r(r7.id) <= '0';
            end if;
         end if;
         if credit_i = '1' then
            credit_r(to_integer(credit_ctx_i)) <= '1';
         end if;
         cdone_r(r7.id) <= next_s.done;

         if rst_r = '1' then
            vis      <= (others => (others => '0'));
            credit_r <= (others => '0');
            cdone_r  <= (others => init(0).done);
         end if;
      end if;
   end process p_stage7;


   ----------------------------------------------------------------
   -- Read port of the paths
   ----------------------------------------------------------------

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

   ctx_o    <= to_slv(r7.id, C_CTX_BITS);
   commit_o <= commit_s;
   count_o  <= commit_s and r7.counted;
   sol_o    <= commit_s and r7.sol;
   jcount_o <= to_slv(next_s.j, 32);
   cdone_o  <= next_s.done;
   lvl_o    <= to_slv(r7.lvl + 1, 5);
   anchor_o <= to_slv(r7.base, 9);
   slot_o   <= r7.slot;
   skip_o   <= r7.skip;
   busy_o   <= busy_r;
   done_o   <= and cdone_r;

end architecture rtl;
