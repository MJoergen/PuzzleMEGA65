# Assumptions

Where the task left something open, I made an educated guess. They are listed
here, roughly in order of importance.

## The search

1. **A "position considered" is a node of the search tree**, i.e. one call
   of `PlaceBitMaps` in the C++ program, including the root (the empty
   board). So after a reset or a new puzzle the counter shows 1 (the empty
   board is the position being considered), and at the end it shows exactly
   the count of the C++ program (e.g. 853,260,456 for 8x8).
2. **Solutions are counted like the C++ program**: rotations and reflections
   count as different solutions, and so do solutions that only swap two
   identical pieces (5x8 has two of each tetromino, so 99,392 solutions).
3. **The order of the positions.** For speed, the hardware searches with many
   contexts in parallel (up to 128), each a depth first search in the same
   order as the C++ program, on its own part of the tree. So the positions
   are not considered in exactly the order of the C++ program, and the
   solutions are found in a different order. The totals are exactly the
   same. With one context the order would be exactly the C++ order (the
   model checks this).
4. **The position shown is that of one context** (the "shown context"). It
   is the one whose steps are shown in the modes S and O. When it has
   searched all of its part of the tree, another one is shown. After N it is
   the context that found the solution.
5. **S (slow)** makes one step of the shown context every 0.5 s, i.e. 2
   positions per second.
6. **O (one step)** makes one step of the shown context, i.e. it shows the
   next position that this context considers, and the counter goes up by one.
   (Nodes at the depth of the split that belong to other contexts are passed
   over without a step.)
7. **N (next)** searches at full speed with all the contexts, and stops at
   the next solution found by any of them. The search stops in the clock
   cycle after the solution, and the passes of the other contexts after it
   are not committed (they are done again later), so N always finds exactly
   one more solution, and the solution is shown until the next key.
8. **Wrap around**: N after the search is finished starts the search again
   from the beginning (the counters start again) and stops at the first
   solution. I did the same for A, S, and O, which would otherwise do
   nothing after the end.
9. **P (pause)** is the default at start-up, after a reset, and after a
   puzzle is selected.
10. **Speed (positions per second)** is the number of positions in the last
    whole second, updated once a second.
11. **Progress** is an estimate: the share of the subtrees at the depth of
    the split (e.g. 153,936 subtrees for 8x8 at depth 4) that have been
    handed out to the contexts. It is not linear in time (the subtrees have
    very different sizes), but it goes from 0 % to 100 %, and is 100 % when
    the search is finished.
12. **Time** (not asked for): the time spent searching (not counting the time
    when paused) is also shown.

## The puzzles

13. The 7 puzzles of the C++ repository are kept. Two classic pentomino
    puzzles are added: the twelve pentominoes in 6x10 (9,356 solutions) and
    in 3x20 (8 solutions). The keys: 1 = 8x8 (the default), 2 = 6x10,
    3 = 3x20, 4 = 5x8, 5 = 7x7, 6 = 5x5, 7 = 1x16, 8 = 1x27, 9 = 16x16.
14. The puzzles are built into the bit-file (they are not loaded at run
    time). Each puzzle has its own specialised engines, generated from the
    puzzle file, so a new puzzle needs a new build (`make puzzles`).
15. The 16x16 puzzle is far too large to be searched to the end in a
    reasonable time, but its first solutions are found (and shown) quickly.
    So it has only one engine (its engine is the largest and slowest).

## The boards

16. **Video**: 1280x1024 @ 60 Hz on VGA and HDMI (DVI mode, no audio) on the
    MEGA65, as in MandelbrotMEGA65, and 1280x1024 on the VGA output of the
    Nexys 4 DDR too (no frame buffer is needed, so the higher resolution
    costs nothing; the colours have 4 bits per channel there).
17. **MEGA65**: only the keyboard is used (the keys A, S, P, O, N, and 1 to
    9); the joysticks are not used. On the R6 the joystick outputs are
    driven high (released), as in MandelbrotMEGA65.
18. **Nexys 4 DDR**: BTNU = A, BTNR = N, BTNL = S, BTND = O, BTNC = P, and
    the switches SW3 to SW0 select the puzzle as a binary number (1 to 9; 0
    is puzzle 1, 10 to 15 are puzzle 9). The puzzle of the switches is
    selected at power-on, and when the switches change.
19. The reset button of the MEGA65 (and CPU_RESET of the Nexys 4 DDR) resets
    the whole design: puzzle 1, paused.

20. **Speed against build time.** The MAIN clock of the MEGA65 is
    196.4 MHz. 205.7 MHz met timing too, but only just, and only with an
    extra optimization after routing, which made the build take 16 to 17
    minutes. I took the 15-minute limit for a build as the harder
    requirement, and gave up 4.5 % of the speed. (The Nexys 4 DDR, the
    nice-to-have board, runs at 154.3 MHz.)

## The repository

21. The repository is created with `git init` in the folder, with the
    history of the work as commits on `main`. I did not create the GitHub
    repository or push (an outward-facing action, left to you); you have
    since pushed it to GitHub (MJoergen/PuzzleMEGA65), where the CI
    workflow (`.github/workflows/ci.yml`) runs on every push.
22. The structure, the Makefile, the coding style (`CODING_STYLE.md`,
    `vsg.yml`), and the tools follow MandelbrotMEGA65. The files from the
    C64MEGA65 core (`src/hdmi`, `src/keyboard`, `src/max10`) and
    `src/clk_rst.vhd` and `src/cdc_data.vhd` are copied from
    MandelbrotMEGA65 (the last two slightly changed).
23. The license is MIT, as for the C++ program and MandelbrotMEGA65 (the
    copied files keep their own licenses).
