# CLAUDE.md

A port of the C++ polyomino puzzle solver (`../puzzle`) to VHDL, for the
MEGA65 (R3 and R6, XC7A200T, 1280x1024 on VGA and HDMI) and the Nexys 4 DDR
(XC7A100T, 1280x1024 VGA). [README.md](README.md) is the overview,
[LOG.md](LOG.md) the history of the decisions and the results,
[ASSUMPTIONS.md](ASSUMPTIONS.md) the guesses where the task was open, and
[TODO.md](TODO.md) the ideas.

## Commands
* `make sim`: all testbenches in parallel (logs in `build/<tb>.log`), about
  10 minutes, mostly `core`. `make run TB=engine GENERICS=G_COUNTED=true`
  also runs the whole 5x8 search (18 minutes). `make run TB=<name>` runs
  one. They must all pass after a VHDL change. Needs `make tbdata` (done
  automatically): the model data in `build/model/` (not committed).
* `make formal`: the proofs in `formal/` (control, cdc_data, bcd,
  snapshot), under a minute.
* `make model`: checks the model against the counts of the C++ program
  (about 3 minutes).
* `make puzzles` regenerates `src/main/puzzle_pkg.vhd` (from `puzzles/*.txt`
  and `tools/puzzles.py`), `make palette` regenerates
  `src/vga/palette_pkg.vhd`. Commit the generated files.
* `make mega65-r6`, `make mega65-r3`, `make nexys4ddr`: Vivado builds
  (MEGA65 about 14 minutes with the default 8 threads, Nexys 4 DDR about 7),
  results in `build/<board>/` (`vivado.log`, `timing.rpt`,
  `utilization.rpt`). A build that fails timing writes no bit-file. Run
  them in the background; at most 10 cores in total, so two at a time with
  `VIVADO_THREADS=5` (`make -j2 mega65-r3 mega65-r6 VIVADO_THREADS=5`).
  The timing margin is small (about 0.05 ns at 196.4 MHz): after a change
  in the MAIN clock domain, build and check `timing.rpt`. Check for runaway
  Vivado processes with `ps -eo pid,etime,args | grep [v]ivado` and kill by
  PID (never `pkill -f` with a pattern that matches your own shell). Vivado
  2025.1 crashed once (segmentation fault during routing): just run it
  again.
* `make pictures`: core_tb with G_PICTURES writes the screen to
  `build/core/*.ppm`, converted to `doc/*.png` (slow, run in background).
* VSG: `vsg -c vsg.yml -ap -f $(git ls-files '*.vhd' ':!src/vga/font_pkg.vhd' ':!src/main/puzzle_pkg.vhd' ':!src/hdmi' ':!src/keyboard' ':!src/max10')`
  must report no errors (lines over 100 columns are only warnings).
* `make fpga BOARD=<board>` programs a real board. Only when asked.

## Architecture in brief
* MAIN clock domain (`src/main/`): `solver` (the engines of all 9 puzzles,
  only the selected puzzle runs), `engine` (8-stage pipeline, 8 interleaved
  contexts, one node per clock cycle; a dynamic split of the tree by a
  global counter of the subtrees at depth `depth`), `control` (the modes),
  `stats`, `snapshot` (the picture of the shown context for each frame).
* VGA clock domain (`src/vga/`): `board` (the rounded pieces), `status` and
  `text` (the text), `vga`. `core.vhd` holds both domains and the crossings
  (`cdc_data`, `board_mem`).
* The model (`tools/model.cpp`, `tools/model.py`) simulates the contexts in
  the order of the hardware, so its traces match the engine pass by pass.
  Any change of the search order (e.g. the split) must be made in both. The
  latency of a grant (3 clock cycles) does not change the order, as long as
  the target arrives before stage 4 of the next pass (engine.vhd).

## Conventions
* VHDL follows [CODING_STYLE.md](CODING_STYLE.md) (as MandelbrotMEGA65).
* Vectors indexed by a context or an engine are `to` vectors (e.g. busy
  and done flags): assigning a `downto` vector to a `to` slice reverses it
  silently (this froze the picture during a search once).
* Test the display while a search runs (mode A), not only when paused.
* Formal (GHDL synthesis): an array of records indexed by a signal (e.g.
  `C_PUZZLES(puzzle_i).rows`) is read wrongly; use a loop with constant
  indices (see `puzzle_field` in snapshot.vhd). A natural is not limited to
  its range in the formal model: assert the range. The CI uses newer tools
  (`scripts/install-tools.sh`, in `~/.cache/puzzle-tools`): run
  `make formal` with them before pushing a change of the properties.
* GHDL uses the mcode backend; external names in testbenches must be
  declared in a process after the instance. GHDL can not analyze
  `clk_rst.vhd` and the top levels (unisim).
* Keep LOG.md updated (a curated transcript), and ASSUMPTIONS.md for guesses.
* Commit messages: subject, why, bullets, what was tested, and the
  Co-Authored-By line.
