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
