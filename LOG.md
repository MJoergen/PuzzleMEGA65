# Log

This is the log of the work on this repository: a curated version of the
transcript of the session with Claude Code, with the progress, the decisions,
and the attempts along the way. The newest entry is at the bottom.

## 1. The prompt

The task, verbatim:

```
I want you to port the C++ application in my 'puzzle' repo to the MEGA65 FPGA
platform (both board revisions, i.e. R3 and R6). Support for the Nexys4DDR board
is nice-to-have.

So, please create a new repo called "PuzzleMEGA65" using the current folder. Use
a folder structure and coding style similar to that of "MandelbrotMEGA65".

Features I want:
* It displays on VGA and HDMI the current position being considered in real
  time. It also displays a count of total positions considered so far, and a
  count of number of solutions found so far.
* Nice-to-have is a speed, i.e. showing the rate: "total positions per second".
* Press A and it searches at full speed and stops when all positions have been
  searched. The screen must clearly state that all solutions have been found.
* Nice-to-have is an estimate of progress, e.g. "20% searched so far".
* Press S and it searches at slow speed (about 2 positions per second).
* Press P and it pauses. This is the default at start-up.
* Press O and it progresses one single step.
* Press N and it searches at full speed and pauses when the next solution is
  found. This should also work after all positions have been searched. I.e. it
  must "wrap around" and counters must reset.
* Numbers 1-9 select one of many different puzzles. The default is number 1,
  which is the 8x8.txt. I believe the puzzle repo has 7 predefined puzzles to
  select from. You are free to add two more (and even replace some of the
  existing ones, but do keep the 16x16 one), so we can make use of all 9 keys
  (1-9) on the keyboard. Pressing a number resets the puzzle (and the two
  counters mentioned above) to the new size, and pauses.

Minimum output resolution is 640x480 @ 60 Hz, but you may choose higher output
resolutions if that makes the images prettier.

You need to come up with a nice visual rendering of the current position. I
suggest - as a minimum - using different colors for each piece. I hope you can
make a nice curved outline around each piece; for that you may perhaps need a
higher resolution than suggested above. And a clear visual distinction between
pieces and (so far) empty areas.

I expect you to do this completely on your own. If you are in doubt about
anything at all, then make an educated guess and write it in a file called
ASSUMPTIONS.md. I will review this file when you're done.

Do also create a LOG.md where you document your progress and decisions and
attempts along the way. I will review this file when you're done. The first
entry in this file should be this prompt verbatim. Remember to always keep this
LOG.md file updated along the way so I can monitor your progress in real time.
I'm expecting something like a curated version of your transcript.

I expect you to include:
* a nice Makefile
* self-checking test benches where relevant
* formal verification where relevant
* a nice README, including pictures from the video output
* CI workflow for GitHub

I expect a nice clean hierarchical architecture, where clock domains are kept
separate as much as possible.

I expect the searching to run in a different (faster) clock domain from the
video rendering.

I expect you to write a concise CLAUDE.md, for your own use.

I expect you to build bitstreams using Vivado and test timing reports.

I expect you to optimize performance so it finds solutions as fast as
(reasonably) possible.

Do also write a TODO.md with ideas for future work. This may include ideas for
performance optimizations not yet tried.

I expect a final bitstream build to complete in under 15 minutes. And I expect
similar times for the simulation and formal verification.

Do remember to check for run-away builds and/or crashes of Vivado.

You may use up to half of the cores on the host machine while building/testing.
```

## 2. Exploring the starting point

* The folder `PuzzleMEGA65` was empty. The host has 20 cores (so at most 10
  are used), 62 GB of RAM, Vivado 2025.1 (and 2025.2), GHDL 6.0.0-dev, Yosys
  0.56 with SymbiYosys, VSG 3.35.0, Python 3 with numpy and PIL, gtkwave,
  pdflatex, and the MEGA65 tools `m65` and `coretool`.
* `../puzzle` (the C++ program): it reads a puzzle file (board size and the
  pieces), builds all the placements of every piece (8 orientations, every
  offset, duplicates removed), and searches depth first: each step fills the
  lowest empty square (row-major order), trying the unused pieces in order,
  and for each piece the placements whose lowest square is that square. A
  "node" (= a position considered) is counted at every call of the recursive
  function, including the root. It has 7 puzzles: 16x16, 1x16, 1x27, 5x5,
  5x8, 7x7, and 8x8.
* `../MandelbrotMEGA65` (the reference for structure and style): VHDL-2008,
  `src/` with `main/` (fast clock domain) and `vga/` (pixel clock domain),
  `core.vhd` (everything that is the same on all boards, simulatable by GHDL),
  `mega65.vhd` plus thin `mega65_r3.vhd` / `mega65_r6.vhd` top levels,
  `nexys4ddr.vhd`, `clk_rst.vhd` (one MMCM), `cdc_data.vhd` (toggle based
  CDC), the HDMI, keyboard, and MAX10 files copied unchanged from the
  C64MEGA65 core, one `.tcl` Vivado script driven by the Makefile, `sim/`
  testbenches that print `<name>_tb: finished`, `formal/` with SymbiYosys +
  PSL, VSG with a `vsg.yml`, a `CODING_STYLE.md`, and a GitHub CI that runs
  formal, VSG, and the simulations. 1280x1024 @ 60 Hz on the MEGA65.

Baseline of the C++ program on this host (`-O3 -march=native`, output to a
file):

| Puzzle | Positions (nodes) | Solutions | Time      |
| ------ | ----------------: | --------: | --------: |
| 5x5    |               372 |         8 |     0.0 s |
| 1x27   |             3,106 |         6 |     0.0 s |
| 1x16   |             8,787 |       300 |     0.0 s |
| 7x7    |         1,094,028 |       160 |     0.05 s |
| 5x8    |        15,783,209 |    99,392 |     3.9 s (mostly output) |
| 8x8    |       853,260,456 |   129,168 |    42.6 s |

So the C++ program does about 20 million positions per second on the 8x8.

## 3. The puzzles

The 7 puzzles of the C++ repository are kept, and two classic pentomino
puzzles are added, the twelve pentominoes in a 6x10 box and in a 3x20 box
(`puzzles/6x10.txt` and `puzzles/3x20.txt`, the pentominoes of `8x8.txt`
without the square). Measured with the C++ program:

| Puzzle | Positions (nodes) | Solutions | Time   |
| ------ | ----------------: | --------: | -----: |
| 6x10   |       349,226,636 |     9,356 | 14.7 s |
| 3x20   |     1,528,716,954 |         8 | 57.4 s |

Keys: 1 = 8x8 (the default), 2 = 6x10, 3 = 3x20, 4 = 5x8, 5 = 7x7, 6 = 5x5,
7 = 1x16, 8 = 1x27, 9 = 16x16.

## 4. Architecture decisions

The main design question is how to make the depth first search fast in
hardware while keeping the semantics of the C++ program (the same positions,
the same counts, a step is one position).

* **Window instead of a full bitmap.** The search always fills the lowest
  empty square ("anchor"). All the squares below the anchor are full, and a
  piece placed at an earlier anchor reaches at most W-1 squares beyond its
  anchor (W = the largest span of a placement in row-major order). So the
  whole state of the board is the anchor plus a window of W bits starting at
  the anchor; all squares beyond the window are empty. Placing a piece is then
  an OR of a constant shape into the window, followed by a shift right by the
  number of trailing ones (which moves the anchor to the next empty square).
  No 256-bit board is needed, even for 16x16.
* **Slots.** The placements of the C++ program are grouped into "slots": one
  slot for each distinct shape (orientation) of each piece. A placement is a
  slot at an anchor. A slot fits at an anchor if it stays on the board (a
  table of the extent of each slot) and does not overlap the window. All the
  slots are tested in parallel, which gives the bit vector F of the children
  of a node. The slots are ordered by piece and then in the order of the C++
  program, so the children are visited in exactly the same order as in the
  C++ program (checked by the generator for every square of every puzzle).
* **One node per pass.** A "pass" takes the lowest bit of F of the current
  node, builds the child, normalizes the window, and computes the child's F.
  If the child has no children, the next pass continues with the siblings;
  backtracking to the nearest ancestor with remaining children is free (a
  priority encoder over a bit mask of the levels). So every pass visits
  exactly one position.
* **Interleaved contexts.** A pass is a long chain of logic (priority encoder,
  shape OR, trailing ones, shifter, fit test), so it is pipelined into C
  stages, and C independent search contexts are interleaved in the pipeline
  (a barrel processor), so a new pass starts every clock cycle.
* **Static partitioning of the tree.** The contexts split the tree at a depth
  D: every context walks the levels above D (only context 0 counts those
  positions), and the subtree below the j-th position at depth D belongs to
  context j mod (number of contexts). No work queue is needed, and the
  partitioning is exact, so the counts are the same as in the C++ program.
* **Specialised engines.** There is one engine per puzzle, generated from the
  puzzle file (`tools/gen_puzzles.py` writes a VHDL package with the slots of
  all 9 puzzles). The shapes are constants, so each fit test is just a NOR of
  the 4 to 20 window bits of the shape, and the small puzzles get small
  engines. Only the engine of the selected puzzle runs.
* **Clock domains.** The search (the engines, the counters, the control of
  the modes, and the writer of the board picture) runs in the fast MAIN clock
  domain. The keyboard, the text, and the rendering run in the VGA (pixel)
  clock domain. Between them: the commands (VGA to MAIN) and the statistics
  (MAIN to VGA) through `cdc_data`, and the board (piece number and
  neighbour mask of each square) through a dual clock RAM.
* **Video.** 1280x1024 @ 60 Hz (108 MHz), as in MandelbrotMEGA65, on VGA and
  HDMI, and also on the Nexys 4 DDR (no frame buffer is needed, so the
  resolution costs nothing).

## 5. The model and the first engine

* `tools/puzzles.py` reads the puzzles like the C++ program, builds the
  placements like it, and groups them into slots. For every anchor of every
  puzzle it checks that the slots give exactly the placements of the C++
  program, in the same order. All 9 puzzles pass.
* `tools/model.cpp` searches exactly like the hardware (window, slots, one
  node per pass, contexts). With one context it gives exactly the counts of
  the C++ program for all 8 puzzles that can be searched (`model.py check`,
  2.3 minutes), and the solutions come in the same order.
* Choosing the depth of the split (`model.py depth`): with 8 contexts and the
  static split (subtree j to context j mod 8), depth 4 gives 97 to 99 % of the
  ideal speed for 8x8, 6x10, and 3x20. With 16 to 64 contexts the static
  split gets worse (8x8: 95 % at 16, 89 % at 64 contexts), because every
  context walks the whole tree above the split and the subtrees differ a lot
  in size.
* `src/main/engine.vhd`, first version: 8 stages, 8 contexts, and
  `sim/engine_tb.vhd` checks every single pass of every context of 5x5, 1x16,
  1x27, and 7x7 against traces of the model. All pass, with the exact counts,
  and with 8 clock cycles per pass of the slowest context.
* Simulation speed: the first version (one process per stage, a record signal
  between the stages) simulated at only 2,600 clock cycles per second in
  GHDL, as every bit of every stage register is a signal. Rewritten so that
  each stage is a pure function and one process moves the ring of registers
  (variables), and with the fit test and the encoder written to loop only
  over the bits that matter: 15,000 cycles per second, the same logic for
  synthesis. engine_tb now takes 2 minutes instead of 7.6.
* First out-of-context Vivado runs at 250 MHz (4.0 ns): 8x8 fails by
  0.39 ns, in the commit stage (the OR of the 64 children, a carry chain, and
  then the next level); 16x16 fails by 2.5 ns, in the count of the trailing
  ones (`lowest_one` as v and -v is a 130-bit carry chain, 32 CARRY4). But
  the engines are small: 8x8 is 1,100 LUTs and 1,400 registers, 16x16 is
  3,000 LUTs and 3,300 registers.

### Decision: many engines, and dynamic splitting

Because the engines are so small, the speed comes from having many engines
per puzzle, not from the last MHz. But with many contexts the static split
loses a lot. So the split is changed to a dynamic one, which is still exact:
a global counter in the solver hands out the subtrees at depth D. Every
context walks the tree above D (only context 0 counts it), and owns the
subtree of a node at depth D when the node's index is its target; it then
claims a new target from the counter at once (the grant arrives a few clock
cycles later, long before the context's next node at depth D). The model
simulates the contexts in the same order as the hardware (pass by pass,
context 0 to 7, engine 0 to E-1), so its traces stay exact.

At the same time the engine is made faster: the next-state decision moves
from stage 7 to stage 0 (stage 7 only ORs the children and writes the stack,
which can be written unconditionally), the stack becomes distributed RAM
with an asynchronous read (stage 1), and the wide priority logic uses groups
of 8 bits instead of one long carry chain.

## 6. Dynamic split: results

* The model now steps all the contexts in the hardware's order (pass by
  pass; ids 0 to 7, engines 0 to E-1), so the claims are the same.
  Efficiency (nodes per context of a perfect split / passes of the slowest
  context), depth 4 unless noted:

  | Puzzle | Engines | Contexts | Static split | Dynamic split |
  | ------ | ------: | -------: | -----------: | ------------: |
  | 8x8    |       1 |        8 |       97.8 % |              |
  | 8x8    |       4 |       32 |       91.5 % |       99.1 % |
  | 8x8    |       8 |       64 |  89.3 % (d5) |       98.1 % |
  | 8x8    |      16 |      128 |              |       95.5 % |
  | 6x10   |       8 |       64 |              |       93.8 % |
  | 3x20   |       8 |       64 |              |       98.8 % |
  | 7x7    |       1 |        8 |  90.1 % (d3) |  96.2 % (d3) |
  | 5x8    |       4 |       32 |              |  96.8 % (d3) |

  8x8 with 16 engines: 6.98 million passes for the slowest context, i.e.
  56 million clock cycles, 0.25 s at 227 MHz (the C++ program: 42.6 s).
* The engine with the dynamic split matches the model pass by pass
  (engine_tb). Out of context: the commit stage was too slow (the OR of all
  the children, then the next level), so the decision moved to stage 0, and
  then the compare of the target in stage 6 (moved to stage 4, the target
  cannot change during a pass). Now 8x8 meets 250 MHz (+0.21 ns), 16x16 is
  at 232 MHz (the 129-bit count of trailing ones). Size: 8x8 1,550 LUTs (520
  of them distributed RAM for the stack) and 1,950 registers; 16x16 5,000
  LUTs and 4,400 registers.

## 7. The picture of the board

* Prototyped in Python first (`tools/render.py`), with exactly the integer
  arithmetic of the hardware: each square is split into four quadrants, and
  each quadrant is drawn from the distances to its two edges and from which
  of its three neighbours have the same piece: the inside, a straight edge,
  an outer corner (rounded, radius cell/4, compared as squared distances, so
  no square root), or an inner corner. The boundary gets a dark outline and
  a light rim, the gap between pieces is about cell/12, and an empty square
  is a dark rounded square of its own. The colours of the pieces are spaced
  by the golden angle on the colour wheel (`src/vga/palette_pkg.vhd` is
  generated from render.py).
* `src/vga/board.vhd` is a 7-stage pipeline of the same algorithm, and
  `sim/board_tb.vhd` compares all 1280x1024 pixels of three frames (8x8, a
  partial 16x16 with many empty squares, a partial 1x27) with render.py. All
  pixels are equal (after fixing a missing stage for the read latency of the
  board memory).

## 8. The whole design, the first builds, tests, and formal proofs

* VGA clock domain: `status.vhd` writes the text (80x32 characters,
  Spleen 16x32 font, full ASCII) into the text memory once per frame during
  the vertical blanking; `text.vhd` draws it over the board; `vga.vhd` takes
  the statistics at the start of the vertical blanking and sends the frame
  pulse to the MAIN domain. `core.vhd` holds both domains and the crossings
  (cdc_data for the commands, the frames, and the statistics; a dual clock
  block RAM with two buffers for the board picture).
* Top levels for MEGA65 R3/R6 (keyboard in the VGA domain, `keys.vhd`) and
  the Nexys 4 DDR (`buttons.vhd`, 1280x1024 too, 4 bits per colour).
  Engines per puzzle: MEGA65 (16, 8, 8, 4, 2, 1, 1, 1, 2), Nexys
  (4, 2, 2, 1, 1, 1, 1, 1, 1). MAIN clock: MEGA65 227.37 MHz (1080/4.75),
  Nexys 180 MHz.
* First MEGA65 R6 build: 71.5k LUTs (53 %), 86.5k registers, placement 6
  minutes, WNS -9.5 ns. The cause was `(disp_r + 1) mod num_ctx(puzzle_r)`
  in control.vhd (a divider by a value that depends on the puzzle). Fixed
  with a compare. Also: the engine results are registered in the solver
  before they are summed, and the halt uses an OR of the solutions of all the
  engines of all the puzzles (no multiplexer). Second build in progress: WNS
  -1.8 ns after placement, -1.3 ns after phys_opt.
* Simulation speed of the whole design: an idle engine still cost a lot in
  GHDL. Engines in reset now do nothing in simulation, and a stage without a
  pass is not computed in simulation (a `translate_off` constant C_SIM; the
  synthesized logic is unchanged). core_tb runs the MAIN clock at 54 MHz.
* Testbenches, all passing: engine_tb (2 min), board_tb (every pixel of 3
  frames), core_tb (modes, counts, statistics, and the text on the screen,
  about 6 min), status_tb (the formatting), bcd_tb, cdc_data_tb (both
  directions, both boards), keys_tb, buttons_tb.
* Formal (SymbiYosys), proven by k-induction: control.vhd (the modes, the
  halt after a solution, credits, the shown context), cdc_data.vhd (two free
  clocks; a wrapper registers the inputs in the source domain), bcd.vhd
  (correct digits for every 10-bit number). The proof of bcd found a small
  bug: a start in the last cycle of a conversion gave done_o; fixed.

## 9. Timing closure

* The second R6 build (227.37 MHz) failed by 1.15 ns, with 23,047 failing
  endpoints. The 400 worst paths fell into a few groups:
  * The estimate of the progress (`stats.vhd`): the constants of the puzzle
    (selected by `puzzle_r`), a subtraction and a clamp, all in front of the
    DSP multiplier, in one clock cycle. Now a pipeline of registers, one
    step per clock cycle (the latency does not matter).
  * The placement of the pieces in `snapshot.vhd`: `slot * 20 + square` as
    the address of the table of the offsets, in one clock cycle. Now four
    registered steps per square (a few thousand clock cycles per frame).
  * Paths of one level of logic, from a register with 600 loads to the
    stage registers of many engines: the engines of a puzzle have the same
    reset, so synthesis merged their local reset registers into one, with a
    fanout across the whole FPGA. The local reset is now two registers in
    each engine, with `keep` (and no shift register extraction).
  * The grant of the targets (`solver.vhd`): the count of the claims of 16
    engines and a 32-bit addition in one clock cycle. Now two clock cycles,
    so a claim is granted 3 clock cycles after it (instead of 2). This is
    still before the target is needed (stage 4 of the next pass of the
    context); engine_tb now uses the same latency, and all its traces still
    match the model pass by pass.
  * The done flags (`solver.vhd`, the AND of 128 flags into the control of
    the shown context): registered once more.
* Third R6 build: WNS -0.248 ns (234 failing endpoints, TNS -24 ns), in the
  engines (e.g. the busy flags). But it took 30 minutes (synthesis 6,
  placement with ExtraTimingOpt 11, phys_opt AggressiveExplore 4 + 3,
  routing 5), twice the limit.
* So: the MAIN clock goes down to 1080/5.0 = 216 MHz (5 % slower), and the
  Vivado script uses the default directives, with the phys_opt after
  routing only if the timing fails. R3 and R6 built at the same time (20
  minutes each): R6 met timing (+0.021 ns, only after the phys_opt after
  routing), R3 failed by 0.20 ns, in the control of the shown context
  (`ctx_done_i(disp_r)`, a 256 to 1 multiplexer, back into `disp_r`). Now
  registered, with a flag that skips the clock cycle after `disp_r`
  changes (the formal proof of control still passes).
* The 16x16 puzzle can not be searched to the end anyway, so it now has one
  engine instead of two (about 5,000 LUTs and 4,400 registers less, and a
  shorter build).
* R6 alone at 216 MHz: WNS -0.09 ns, 16 minutes. The paths: the 16x16
  engine (stage 0, the level to the read address of the stack), the busy
  flag of the held context in `snapshot.vhd` (a 256 to 1 multiplexer,
  now registered; the 16 clock cycles of the wait cover the one clock cycle
  of delay, and the property in snapshot.psl now says two clock cycles),
  and the loop from the halt through the engines back to the mode (see
  TODO.md). So the clock went down once more, to 1080/5.25 = 205.7 MHz.
* R6 at 205.7 MHz: WNS -0.16 ns, in yet another place: the address of the
  neighbour in `snapshot.vhd` (NBR_ST), which synthesis had moved in front
  of the address register of the block RAM of the map of the pieces. The
  map (256 x 5 bits) is now distributed RAM.
* R3 and R6 at the same time: R3 met timing (+0.013 ns, 15.5 minutes), and
  Vivado crashed on R6 during routing ("Abnormal program termination (11)",
  a segmentation fault; the log is kept as build/logs/vivado_r6_crash.log).
  Run again (with the Nexys 4 DDR at the same time): R6 -0.09 ns, in the
  16x16 engine (stage 4, the count of the trailing ones of the 129-bit
  window), and the Nexys 4 DDR -0.11 ns, in the VGA clock domain (stage 6
  of `board.vhd`, which squared the radius and the widths of the outline of
  the registered geometry of the puzzle for every pixel).
* `synth_design -retiming` did not help: R6 -0.20 ns, and synthesis took
  6.7 instead of 5.1 minutes (the Nexys 4 DDR met timing, +0.014 ns). Not
  used.
* `board.vhd`: the squares are now constants in the table of the geometry
  (board_tb: still every pixel equal).
* The engine: the shift of the window by its trailing ones is now split
  differently between the stages 4 and 5. Stage 4 shifts by whole groups of
  8 bits (the lowest group that is not full: a carry chain over 17 groups
  for 16x16, and a one-hot multiplexer), stage 5 by the trailing ones of
  the lowest group (0 to 7). Before, stage 4 counted all the trailing ones
  (carry chain, then a 17-way multiplexer of the count of each group, then
  the encoder), and stage 5 shifted by up to 129.
* engine_tb never simulated the 16x16 engine (it can not be searched to the
  end). The model can now write the first passes of every context
  (`trace ... <passes>`, it stops the search when all the contexts have
  them), and engine_tb checks the first 5,000 passes of every context of
  16x16 against them (C_PARTIAL). It passes, with the new stages 4 and 5,
  and the engine is then idle (run_i low), so engine_tb takes 98 s.

## 10. Formal verification of the snapshot, VSG, and the repository files

* `formal/snapshot.psl` (written last time, never run) failed at once: some
  registers had no initial value (so a pulse at step 0), `latch_o` is
  registered (so it is checked against `busy_i` of the clock cycle before),
  and a reset in the clock cycle of `latch_r` left the pulse. Fixed in the
  RTL (initial values, the pulses cleared by the reset, one register for
  the held context instead of two outputs) and in the properties, plus the
  invariants k-induction needs. The properties with an implication are also
  cover statements, and writing the board takes thousands of clock cycles,
  so the ones about writing the board memory are plain assertions. A
  mutation (`< squares - 1`) checks that `f_square` is not vacuous.
* `formal/Makefile` (as MandelbrotMEGA65): `make formal` runs control,
  cdc_data, bcd, and snapshot (prove and cover), in about 30 seconds.
* `vsg.yml` and `CODING_STYLE.md` copied from MandelbrotMEGA65 and adapted.
  VSG fixed the formatting by itself; by hand: a few names (`C_F_*`,
  `char_file_t`, `to_bcd` instead of the reserved word `reference`), and
  the `translate_off` trick of `C_SIM` is excluded from one rule. The
  generated `puzzle_pkg.vhd` is left out, like `font_pkg.vhd`.
* engine_tb with 5x8 takes 18 minutes (15,000 clock cycles per second), so
  5x8 is now only simulated with `G_COUNTED=true`; it passes (with the new
  grant latency). The other testbenches all pass: core 3.4 min, board 3.1
  min, the rest a few seconds.
* The CI (`.github/workflows/ci.yml`, `scripts/install-tools.sh`), README,
  CLAUDE.md, TODO.md, and LICENSE.
* Expected time of the whole search on the MEGA65 (the passes of the
  slowest context from the model, times 8 clock cycles, at 196.4 MHz, see
  section 9):

  | Puzzle | Engines | Slowest context (passes) | Efficiency | Time      | C++     |
  | ------ | ------: | -----------------------: | ---------: | --------: | ------: |
  | 8x8    |      16 |                6,982,269 |     95.5 % |   0.285 s |  42.6 s |
  | 6x10   |       8 |                5,820,099 |     93.8 % |   0.237 s |  14.7 s |
  | 3x20   |       8 |               24,168,913 |     98.8 % |   0.985 s |  57.4 s |
  | 5x8    |       4 |                  565,098 |     87.3 % |   23.0 ms |   3.9 s |
  | 7x7    |       2 |                   74,447 |     91.8 % |    3.0 ms |  0.05 s |
* R3 and R6 with that: R3 -0.007 ns (from `finished_r` of control.vhd,
  through `run_o`, to the busy flags of an engine), R6 -0.37 ns, in the new
  stage 4 (the anchor plus 8 times the encoded group, an adder after the
  carry chain). So stage 4 now only registers the group, and stage 5 adds
  both shifts to the anchor; and `run_i` is registered in each engine (with
  `keep`, like the reset), so a pass starts one clock cycle after the mode
  allows it (halt_i still acts at once, so N still stops at the solution).
  engine_tb and core_tb pass.
* R6 and R3 at 205.7 MHz met timing (+0.002 and +0.027 ns), but only with
  the phys_opt after routing, so the clock went down one more step, to
  1080/5.5 = 196.4 MHz (the Nexys 4 DDR: 180 MHz failed by 0.11 ns in the
  16x16 engine, so 1080/6.5 = 166 MHz). Then all three met timing right
  after routing (R6 +0.072 ns, R3 +0.057 ns, Nexys +0.021 ns).
* The halt loop (control.vhd, halt_r, through the commits of all the
  engines, back to halt_r) was the worst path of R3: the engines now give
  the solution flag before the halt (`sol_any_o`) for it. The control only
  acts on it in the mode N, where the halt is never set already.
* Build time: R3 alone with 5 threads took 15.7 minutes. With 8 threads
  (the most Vivado uses; one build alone stays within half of the cores)
  and without the power report: 13.6 minutes. VIVADO_THREADS is now 8, and
  5 for two builds at the same time.

## 11. The pictures, and a bug they found

* `make pictures` (core_tb with G_PICTURES, 40 minutes) wrote all the
  pictures, but the 16x16 one still showed the 6x10 solution, and the 5x5
  one 373 positions instead of 372 (after a switch from the running 16x16
  search).
* The first: the snapshot never finished while a search ran in the mode A.
  The engine's busy and done flags were `downto` vectors, and the solver
  put them into `to` slices, so the flags of the contexts were reversed
  within each engine: the snapshot waited for 16 idle clock cycles of
  context 7 instead of the held context 0, which never came while the
  search ran. The picture (and the statistics, which are sent with it)
  froze in the modes A and N until the end of the search. This was in the
  design from the start: all the tests of the picture and of the
  statistics so far were made while paused or halted. Also the shown
  context moved on when the wrong context was done. Now both are `to`
  vectors, indexed by the context.
* The second: the engines of the old puzzle still commit passes for a few
  clock cycles after a puzzle is selected (until their reset arrives,
  which now takes 3 clock cycles), and the counts take 2 more through the
  solver, but the restart (which also clears the statistics) was only 2
  clock cycles long. It is now 8 (C_RESTART in control.vhd, the formal
  proof updated).
* core_tb now also checks both: 16x16 in the mode A, and after two frames
  the statistics in the VGA clock domain must be those of the running
  search; then 5x5 selected while 16x16 runs, and all: exactly the counts
  of the model. core_tb has a 16x16 engine for this, and takes 10 minutes.
* R6 at 196.4 MHz then needed the phys_opt after routing again (-0.11 ns
  after routing), now almost only in the 16x16 engine (stage 4: the test
  of the full groups, the carry chain over 17 groups, and the 17-way
  multiplexer). With groups of 16 bits for a window of more than 64 bits
  (only 16x16: 9 groups; stage 5 shifts by 0 to 15), R6 met timing right
  after routing, +0.119 ns. The Nexys 4 DDR then failed at 166 MHz
  (-0.20 ns, 82 % routing: the select of the group fans out to all 129
  bits), so it runs at 1080/7 = 154.3 MHz (see TODO.md for a better split
  of the stages 4 and 5).
* Vivado crashed once more on R6 at the start of routing (segmentation
  fault, a core dump); the same run again passed.

## 12. Final results

| Board       | MAIN clock | WNS       | LUTs            | Registers       | Build time |
| ----------- | ---------: | --------: | --------------: | --------------: | ---------: |
| MEGA65 R6   | 196.4 MHz  | +0.119 ns | 64,473 (48.2 %) | 84,499 (31.6 %) | 13.3 min   |
| MEGA65 R3   | 196.4 MHz  | +0.073 ns | 64,600 (48.3 %) | 84,641 (31.6 %) | 14.8 min   |
| Nexys 4 DDR | 154.3 MHz  | +0.129 ns | 22,989 (36.3 %) | 28,730 (22.7 %) | 6.3 min    |

One build at a time, 8 threads, Vivado 2025.1. The MEGA65 builds are just
under 15 minutes (synthesis 5, placement 4, routing 3 minutes, the rest
reports and the bit-file); with the phys_opt after routing they would be
16 minutes. `make formal`: 20 seconds, all proven. `make sim`: all 8
testbenches pass in 9.9 minutes (core_tb 9.9, board_tb 3, engine_tb 1.7).
The full engine_tb with 5x8: passes (18 minutes). `make pictures`: 45
minutes; the pictures in doc/ are from this version.
