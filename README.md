# Polyomino puzzles on the MEGA65

This solves polyomino packing puzzles (e.g. the twelve pentominoes and a
2x2 square in an 8x8 box) in VHDL on the [MEGA65](https://mega65.org/)
(board revisions R3 and R6, with a Xilinx Artix-7 XC7A200T FPGA). It is a
port of a C++ program, which finds all the solutions by a depth first
search, and it finds exactly the same positions and solutions, only much
faster: the 8x8 puzzle (853,260,456 positions, 129,168 solutions) takes
about 0.27 seconds (estimated from the model) instead of 42.6 seconds for the C++ program on a fast PC.

The position being considered is shown in real time on the VGA and HDMI
outputs (1280x1024 @ 60 Hz), with the number of positions considered, the
solutions found, the speed, the progress, and the time. The same design also
runs on the
[Nexys 4 DDR](https://digilent.com/reference/programmable-logic/nexys-4-ddr/start)
board (XC7A100T, with fewer search engines), see [Nexys 4 DDR](#nexys-4-ddr).

@@PICTURES@@

## The puzzles

The keys `1` to `9` select a puzzle. The first seven are those of the C++
program, and 6x10 and 3x20 are the classic pentomino boxes. The counts are
those of the C++ program (every node of the search tree is a position,
including the empty board, and rotations and reflections of a solution are
different solutions), and the hardware gives exactly the same numbers.

| Key | Puzzle | Pieces | Positions | Solutions | C++ program | MEGA65 (engines, time) |
| --- | ------ | ------ | --------: | --------: | ----------: | ---------------------: |
| 1 | 8x8   | 12 pentominoes and a 2x2 square | 853,260,456   | 129,168 | 42.6 s  | 16, 0.27 s |
| 2 | 6x10  | 12 pentominoes                  | 349,226,636   |   9,356 | 14.7 s  |  8, 0.23 s |
| 3 | 3x20  | 12 pentominoes                  | 1,528,716,954 |       8 | 57.4 s  |  8, 0.94 s |
| 4 | 5x8   | 10 tetrominoes                  | 15,783,209    |  99,392 | 3.9 s   |  4, 22 ms  |
| 5 | 7x7   | 9 pentominoes and a square      | 1,094,028     |     160 | 0.05 s  |  2, 2.9 ms |
| 6 | 5x5   | 5 pentominoes                   | 372           |       8 | 0.0 s   |  1         |
| 7 | 1x16  | 8 pairs of squares              | 8,787         |     300 | 0.0 s   |  1         |
| 8 | 1x27  | 9 triples of squares            | 3,106         |       6 | 0.0 s   |  1         |
| 9 | 16x16 | 19 large pieces                 | (too many)    |         |         |  1         |

The C++ times were measured on the build machine (`-O3 -march=native`,
output to a file). The MEGA65 times are the passes of the slowest context in
the model (`tools/model.py run <name>`), times 8 clock cycles, at
205.7 MHz.

The 16x16 puzzle is far too large to be searched to the end, but its first
solutions are found quickly. The puzzles are in [`puzzles/`](puzzles), in
the format of the C++ program, and built into the bit-file (`make puzzles`
generates [`src/main/puzzle_pkg.vhd`](src/main/puzzle_pkg.vhd) from them).

## Controls

| Key (MEGA65) | Button (Nexys 4 DDR) | Action
| ------------ | -------------------- | ------
| `A`          | BTNU                 | Search all positions at full speed, and stop when the search is finished. The screen then says "ALL SOLUTIONS FOUND".
| `N`          | BTNR                 | Search at full speed, and stop at the next solution, which is shown.
| `S`          | BTNL                 | Search slowly, 2 positions per second.
| `O`          | BTND                 | One step: the next position.
| `P`          | BTNC                 | Pause (the default at start-up).
| `1` to `9`   | SW3 to SW0 (binary)  | Select a puzzle: the counters start again, and the search is paused.

After the search is finished, `A`, `N`, `S`, and `O` start it again from the
beginning (the counters start again). The reset button resets the whole
design (puzzle 1, paused). See [ASSUMPTIONS.md](ASSUMPTIONS.md) for the
details of the interpretation of each key.

## How it works

The C++ program fills the lowest empty square (in row-major order) at each
step, trying the unused pieces in order, and for each piece its placements
that cover that square. The hardware does exactly the same, in the same
order, but:

* **A window instead of a board.** All the squares before the lowest empty
  square (the "anchor") are full, and no piece reaches more than W squares
  beyond it (W is the largest span of a piece in row-major order, e.g. 33 for
  8x8). So the state of the board is the anchor and a window of W bits.
  Placing a piece is an OR of a constant shape into the window, and a shift
  by the number of trailing ones, which moves the anchor to the next empty
  square.
* **All the placements at once.** A "slot" is one orientation of one piece.
  All the slots of the puzzle are tested in parallel against the window,
  which gives the children of a position as a bit vector. The shapes are
  constants (each puzzle has its own engines, generated from the puzzle
  file), so each test is just a NOR of a few bits.
* **One position per clock cycle.** Each step (a "pass") visits exactly one
  position: it takes the next child, builds it, and computes its children.
  Backtracking is free. A pass is pipelined in 8 stages, and 8 independent
  searches ("contexts") are interleaved in the pipeline, so an engine starts
  a pass every clock cycle.
* **Many engines.** The tree is split at a depth D (e.g. 4 for 8x8): every
  context walks the tree above D, and the subtrees below D are handed out
  one by one by a global counter, to the context that asks first. The 8x8
  puzzle has 16 engines (128 contexts), and the split keeps 95 % of them busy.

So the 8x8 puzzle runs at up to 16 positions per clock cycle, i.e. 3.3
billion positions per second at 205.7 MHz. The model of the search
([`tools/model.cpp`](tools/model.cpp), driven by
[`tools/model.py`](tools/model.py)) simulates the contexts in exactly the
order of the hardware, and the testbenches compare the hardware with it pass
by pass. [LOG.md](LOG.md) tells how the design came about, with the
decisions and the results along the way.

The picture of the board is made in the MAIN clock domain once per frame
(the position of one context, the "shown context"), and drawn in the VGA
clock domain: each square is split into four quadrants, and each quadrant is
drawn from the distances to its edges and from which neighbours belong to
the same piece, which gives rounded outlines around each piece. The colours
of the pieces are spaced by the golden angle on the colour wheel.

### Architecture

```
            MAIN clock domain (206 MHz)                 VGA clock domain (108 MHz)
 +---------------------------------------------+    +-------------------------------+
 | main                                        |    | vga                           |
 |  control  - modes, credits, shown context   |<---|  keys (MEGA65) / buttons      |
 |  solver   - engines of each puzzle          |    |                               |
 |    engine x N (8 stages, 8 contexts)        |    |  pix    - pixel counters      |
 |  stats    - counters, rate, time, progress  |--->|  status - text of the screen  |
 |  snapshot - picture of the shown context    |--->|  board  - rounded pieces      |
 +---------------------------------------------+    |  text   - text over the board |
          cdc_data (commands, statistics), board_mem (dual clock RAM)
```

* [`src/core.vhd`](src/core.vhd) holds the two clock domains and the
  crossings, and is the same on all the boards (simulated by `core_tb`).
* [`src/mega65.vhd`](src/mega65.vhd) (with the thin top levels
  `mega65_r3.vhd` and `mega65_r6.vhd`) and
  [`src/nexys4ddr.vhd`](src/nexys4ddr.vhd) add the clocks
  ([`src/clk_rst.vhd`](src/clk_rst.vhd)), the keyboard or the buttons, and
  the video outputs.

## Implementation results

Vivado 2025.1, 5 threads per build, the R3 and R6 built at the same time:

| Board        | MAIN clock | WNS       | LUTs            | Registers       | BRAM | Build time |
| ------------ | ---------: | --------: | --------------: | --------------: | ---: | ---------: |
| MEGA65 R6    | 205.7 MHz  | +0.002 ns | 65,077 (48.6 %) | 84,515 (31.6 %) | 29   | 17 min     |
| MEGA65 R3    | 205.7 MHz  | +0.027 ns | 65,132 (48.7 %) | 84,620 (31.6 %) | 29   | 17 min     |
| Nexys 4 DDR  | 180 MHz    | @@NEXYS@@ |

The VGA clock is 108 MHz (1280x1024 @ 60 Hz). The engines are small (8x8:
about 1,550 LUTs and 1,950 registers; 16x16: about 5,000 LUTs and 4,400
registers), and the MAIN clock is limited by the longest paths in them and
around them, see [LOG.md](LOG.md) (Timing closure) and [TODO.md](TODO.md).

## Building and running

* `make mega65-r6`, `make mega65-r3`, `make nexys4ddr` build the bit-file
  `build/<board>/<board>.bit` with Vivado (the reports are in the same
  folder). A build that does not meet timing writes no bit-file. The builds
  can run at the same time, e.g. `make -j2 mega65-r3 mega65-r6` (each Vivado
  uses `VIVADO_THREADS` = 5 threads).
* `make cor` makes the core files for MEGAFLASH (`build/<board>/<board>.cor`)
  with coretool, and `make fpga BOARD=<board>` programs the FPGA with m65.
* `make sim` runs all the testbenches in parallel (the logs are in
  `build/<name>.log`), `make run TB=<name>` one of them, and
  `make check TB=<name>` one of them with the waveform in GTKWave. The data
  of the testbenches is generated from the model first (`make tbdata`).
* `make formal` runs the formal verification.
* `make model` checks the model against the counts of the C++ program.
* `make pictures` simulates the whole design and saves the pictures of the
  screen (`doc/*.png`).

### Testbenches

All are self-checking, and print `<name>_tb: finished` at the end.

| Testbench | Checks
| --------- | ------
| `engine_tb` | Every pass of every context of 5x5, 1x16, 1x27, and 7x7 against the traces of the model, the counts, and the time (8 clock cycles per pass of the slowest context). With `GENERICS=G_COUNTED=true` also the counts of 5x8 (about 18 minutes).
| `core_tb` | The whole design without the board files: the modes (A, N, S, O, P, and the puzzles), the counts against the model, the statistics in the VGA clock domain, and the text on the screen.
| `board_tb` | Every pixel of three pictures of the board against `tools/render.py`.
| `status_tb` | The formatting of the numbers and the text of the screen.
| `bcd_tb` | The binary to decimal conversion, for many numbers.
| `cdc_data_tb` | The clock domain crossing, in both directions, with the clocks of both boards.
| `keys_tb`, `buttons_tb` | The keys of the MEGA65 and the buttons of the Nexys 4 DDR.

### Formal verification

[SymbiYosys](https://github.com/YosysHQ/sby) with the properties in PSL
(`formal/<name>.psl`), each proven by k-induction and covered:

| Module | Properties
| ------ | ----------
| `control` | The modes, the halt after a solution in the mode N, the credits (steps), the restart, and the shown context.
| `cdc_data` | The value arrives unchanged, with two free clocks.
| `bcd` | The digits are right for every 10-bit number, and a restart is safe.
| `snapshot` | The buffer that is shown is never written (no tearing), the statistics are taken while the shown context is held and idle, and the squares written are on the board.

## Tools

| Tool | Version | Used by
| ---- | ------- | -------
| [Vivado](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html) | 2025.1 | `make mega65-r3`, `make mega65-r6`, `make nexys4ddr`
| [GHDL](https://github.com/ghdl/ghdl) | 6.0.0-dev and 6.0.0 (mcode backend) | `make sim`, `make run`, `make check`
| [Yosys](https://github.com/YosysHQ/yosys), [SymbiYosys](https://github.com/YosysHQ/sby), [ghdl-yosys-plugin](https://github.com/ghdl/ghdl-yosys-plugin), Yices | Yosys 0.56 | `make formal`
| [VSG](https://vhdl-style-guide.readthedocs.io/) | 3.35.0 | the coding style, see [`CODING_STYLE.md`](CODING_STYLE.md)
| Python 3, g++ | 3.12, 13 | the model and the generators (`tools/`); Pillow only for `tools/render.py png`
| ImageMagick (`convert`) | 6.9 | `make pictures`
| [m65, coretool](https://github.com/MEGA65/mega65-tools) | | `make fpga`, `make cor`

The testbenches use external names of VHDL-2008, which need the mcode
backend of GHDL. [`scripts/install-tools.sh`](scripts/install-tools.sh)
installs the free tools (as the CI does,
[`.github/workflows/ci.yml`](.github/workflows/ci.yml), which runs
`make formal`, VSG, and `make sim` on every push).

## Nexys 4 DDR

The Nexys 4 DDR has a smaller FPGA (XC7A100T, speed grade -1), so it has
fewer engines (4 for 8x8, 2 for 6x10 and 3x20, 1 for the others), and the
MAIN clock is 180 MHz. The picture is also 1280x1024 @ 60 Hz on its VGA
output (4 bits per colour). The buttons are listed under
[Controls](#controls); the switches SW3 to SW0 select the puzzle as a binary
number (0 is puzzle 1, 10 to 15 are puzzle 9).

## License

The design is licensed under the [MIT License](LICENSE), except for the files
copied from other projects, which keep their own licenses:
* [`src/keyboard/`](src/keyboard): the MEGA65 keyboard driver, from the
  [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework (via
  [C64MEGA65](https://github.com/MJoergen/C64MEGA65)), GPL v3.
* [`src/hdmi/`](src/hdmi): the HDMI output, from The Tyto Project by Adam
  Barnes (via C64MEGA65), LGPL v3.
* [`src/max10/`](src/max10): the serial link to the MAX10 of the MEGA65 R3,
  from the [MEGA65 core](https://github.com/MEGA65/mega65-core) (via
  C64MEGA65), GPL v3.
* [`src/vga/font_pkg.vhd`](src/vga/font_pkg.vhd): the
  [Spleen](https://github.com/fcambus/spleen) 16x32 font by Frederic Cambus,
  BSD 2-Clause (see [`font/LICENSE.spleen`](font/LICENSE.spleen)).
