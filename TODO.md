# TODO

Ideas for future work, roughly in order of expected benefit.

## Speed

* **A work queue instead of the shadow walk.** Every context walks the
  whole tree above the depth of the split (only context 0 counts it) to find
  its next target. A queue of the nodes at the split depth, filled by one
  context, would save these passes, which matters most for the puzzles with
  few nodes per subtree (5x5, 1x16, 1x27, 7x7).
* **More engines.** The MEGA65 R6 build uses about half of the LUTs. The
  8x8 puzzle (16 engines) could get more, at the cost of a longer build and
  harder timing. The efficiency of the dynamic split drops with more
  contexts (95.5 % with 128), so a deeper split would also be needed.
* **Engines shared between puzzles.** Each puzzle has its own engines,
  specialised for its pieces, and only those of the selected puzzle run. A
  generic engine (the slots in a RAM instead of constants) could run any
  puzzle, so all the engines of the FPGA would work on the selected puzzle.
  It would be larger and slower per engine, so this is only a win if the
  number of engines grows more than their speed drops.
* **A faster 16x16 engine.** The 129-bit window of 16x16 makes its engine
  the slowest: stage 4 (the lowest group of 8 bits that is not full, and
  the shift by whole groups) and stage 0 (the level to the read address of
  the stack). It limits the Nexys 4 DDR to 154 MHz, where the path is
  mostly routing (the one-hot select of the group fans out to all 129
  bits). Stage 4 could only find the group and the trailing ones of every
  group (registered, so the select can be replicated), and stage 5 do both
  shifts. A ninth stage, or a slower clock for this one engine, would also
  help.
* **A faster MAIN clock.** The MEGA65 runs at 196.4 MHz. 205.7 MHz met
  timing only just (and only with phys_opt_design after routing, which
  makes the build longer than 15 minutes), with the near-critical paths
  spread over all the engines (the done and busy flags, the write addresses
  of the distributed RAMs of the stacks). Fewer, larger LUTRAMs per stack,
  or more registers between the solver and the engines, might help. The
  loop from `halt_o` of `control.vhd` through the commits of all the
  engines (`sol_any_i`) back to its mode is also long: the solution flag
  for the halt could be taken before the halt (it is only used when not
  halted).
* **A faster clock for the 8x8 engines.** Out of context the 8x8 engine
  meets 250 MHz; the MAIN clock is set by the slowest engine and the
  surrounding logic. A separate clock domain per puzzle is possible, but
  costs MMCM outputs and crossings.
* **Pruning.** The C++ program does not prune (e.g. regions of empty squares
  whose size is not a multiple of 5 for the pentominoes). Pruning would
  change the counts of positions, so it would have to be an option.

## Display

* **A better estimate of the progress.** The progress is the share of the
  subtrees at the split depth that have been handed out, which is not linear
  in time (the subtrees have very different sizes). Weighting the subtrees by
  an estimate of their size (e.g. from a sample search) would be better.
* **An estimate of the remaining time**, from the progress and the time.
* **Show several contexts at once**, e.g. small pictures of all the contexts
  of one engine.
* **Show the list of solutions found**, e.g. the last few solutions as small
  pictures.

## Other

* **Puzzles loaded at run time**, e.g. from the SD card of the MEGA65,
  which needs the generic engine above.
* **Formal verification of the engine**, e.g. on the 1x16 puzzle (bounded:
  the halt prevents commits, the credits, and the hold/busy protocol).
