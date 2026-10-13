# Handoff

The state of the work, for the next session. The task is in LOG.md (section
1, verbatim). Read LOG.md (the decisions and the results) and ASSUMPTIONS.md
first. This file can be deleted when the work is done.

## Done (committed, except as noted)

* The model and the generators: `tools/puzzles.py` (puzzles, slots),
  `tools/model.cpp` + `tools/model.py` (the reference model, identical counts
  to the C++ program; `make model`), `tools/gen_puzzle_pkg.py`
  (`make puzzles` -> src/main/puzzle_pkg.vhd), `tools/gen_tb_data.py` and
  `tools/render.py` (`make tbdata`, `make palette`).
* The whole RTL: src/main/ (engine, solver, control, stats, snapshot, main),
  src/vga/ (pix, board, bcd, status, text, vga, packages, font), src/ (core,
  cdc_data, board_mem, ctrl_pkg, util_pkg, keys, buttons, clk_rst, tops),
  constraints for 3 boards, `puzzle.tcl`, `Makefile`.
* Testbenches (all pass): core board engine status bcd cdc_data keys buttons.
* Formal (pass): formal/control, formal/cdc_data (+ cdc_data_top.vhd),
  formal/bcd (bcd.psl/sby and the bcd.vhd fix are NOT yet committed at the
  time of writing; commit them).

## In progress / not verified

* A Vivado build of mega65-r6 was running in the background (started at
  20:53, log in build/logs/build_r6.log, results in build/mega65-r6/). At
  the last look: WNS -1.3 ns after phys_opt, so it will probably fail timing.
  Look at build/mega65-r6/timing.rpt (if routed) for the failing paths. Ideas:
  the 16x16 engine's trailing ones (129 bits) and stack read address fanout
  (OOC: 232 MHz); the snapshot/solver paths; or lower the MAIN clock to
  1080/5.0 = 216 MHz (C_MAIN_DIVIDE in src/mega65.vhd), or fewer engines.
  Build times so far: synthesis ~5 min, placement ~6 min: watch the 15 min
  limit (maybe simpler directives in puzzle.tcl). Check for runaway Vivado
  processes (`ps -eo pid,etime,args | grep [v]ivado`); kill by PID (never
  `pkill -f` with a pattern that matches your own shell).
* formal/snapshot.psl and formal/snapshot.sby were written but never run
  (the run was interrupted). Run `cd formal && sby --yosys "yosys -m ghdl"
  -f snapshot.sby`; the big constant tables may make it slow. Fix or drop.

## To do

1. Get timing closure for mega65-r6, then build mega65-r3 and nexys4ddr
   (`make -j2 mega65-r3 mega65-r6`, VIVADO_THREADS=5, at most 10 cores).
   Record the utilization, WNS, build time in README.md and LOG.md.
2. formal/Makefile (like MandelbrotMEGA65's: DUTS = control cdc_data bcd
   [snapshot] [engine]), so `make formal` works. Maybe a formal job for the
   engine on 1x16 (bounded: halt prevents commits, credits, hold/busy).
3. `make pictures` (core_tb with G_PICTURES=true writes build/core/*.ppm,
   then converted to doc/*.png). It takes a long time (several frames, about
   a minute or more each); run it in the background. Check the pictures.
4. README.md (overview, keys, pictures, puzzles and their counts, speed:
   e.g. 8x8 in about 0.25 s at 227 MHz with 16 engines vs 42.6 s for C++,
   architecture, build/sim/formal commands, tools, implementation results,
   license), CLAUDE.md (concise), TODO.md (ideas: work queue instead of the
   shadow walk above the split, more engines, a generic engine, faster
   16x16 engine, better progress estimate, ...), CODING_STYLE.md and
   vsg.yml (copy from MandelbrotMEGA65 and adapt; run VSG and fix), LICENSE
   (MIT, Michael Jørgensen), .github/workflows/ci.yml and
   scripts/install-tools.sh (from MandelbrotMEGA65; CI also needs g++ for
   the model, `make tbdata` before `make sim`).
5. Run `make sim` (all testbenches in parallel) and check the total time
   (< 15 min). Update LOG.md and ASSUMPTIONS.md at the end.

## Notes

* GHDL: mcode backend; external names must be declared in a process (after
  the instance). The tb data (build/model/) is generated, not committed.
* Commit messages follow MandelbrotMEGA65 (subject, why, bullets, what was
  tested), with the Co-Authored-By line. Nothing is pushed (no remote).
