#!/usr/bin/env python3
"""Runs the reference model of the search (tools/model.cpp) on the puzzles.

The model is compiled to build/model/model, and the slots of each puzzle (from
tools/puzzles.py) are written to build/model/<name>.slots.

Usage: tools/model.py <command>
  check            Runs the whole search of every puzzle (but 16x16) with one
                   context, and checks the counts against those of the C++
                   program (KNOWN below). About 3 minutes.
  depth <name> <engines> <depth>...
                   For the puzzle <name> and the number of engines, the
                   passes of the slowest context for each depth at which the
                   tree is split, i.e. the time of the search, and the
                   efficiency (the nodes per context of a perfect split,
                   divided by that). One whole search for each depth.
  run <name> [<engines>]
                   The counts of every context of the puzzle (default: the
                   engines of the puzzle in puzzles.py), split at its depth.
  frontier         The number of nodes at the depth of the split of every
                   puzzle, as used by src/main/puzzle_pkg.vhd.
"""

import os
import subprocess
import sys

import puzzles

BUILD = os.path.join(puzzles.TOP, 'build', 'model')
MODEL = os.path.join(BUILD, 'model')

# The counts of the C++ program (github.com/MJoergen/puzzle), i.e. the
# positions (nodes, including the root) and the solutions of each puzzle.
# 16x16 is too large to search.
KNOWN = {
    '8x8':  (853260456, 129168),
    '6x10': (349226636, 9356),
    '3x20': (1528716954, 8),
    '5x8':  (15783209, 99392),
    '7x7':  (1094028, 160),
    '5x5':  (372, 8),
    '1x16': (8787, 300),
    '1x27': (3106, 6),
}


def build():
    """Compiles the model and writes the slot files."""
    os.makedirs(BUILD, exist_ok=True)
    src = os.path.join(puzzles.TOP, 'tools', 'model.cpp')
    if not os.path.exists(MODEL) or os.path.getmtime(MODEL) < os.path.getmtime(src):
        subprocess.run(['g++', '-O3', '-march=native', '-std=c++17', '-o', MODEL, src],
                       check=True)
    result = []
    for p in puzzles.load():
        with open(slots_file(p), 'w') as f:
            f.write(f'{p.rows} {p.cols} {len(p.pieces)} {len(p.slots)} {p.width}\n')
            for s in p.slots:
                f.write(f"{s['piece']} {s['down']} {s['left']} {s['right']} "
                        f"{len(s['offsets'])} {' '.join(map(str, s['offsets']))}\n")
        result.append(p)
    return result


def slots_file(p):
    return os.path.join(BUILD, p.name + '.slots')


def model(p, *args):
    """Runs the model on the puzzle, and returns the output lines."""
    out = subprocess.run([MODEL, slots_file(p)] + [str(a) for a in args],
                         check=True, capture_output=True, text=True).stdout
    return out.splitlines()


def run(p, engines, depth):
    """The counts of each context and the totals."""
    ctx = []
    total = None
    for line in model(p, 'run', engines, depth):
        w = line.split()
        if w[0] == 'ctx':
            ctx.append(dict(passes=int(w[3]), nodes=int(w[5]), solutions=int(w[7])))
        else:
            total = dict(nodes=int(w[2]), solutions=int(w[4]), max_passes=int(w[6]))
    return ctx, total


def frontier(p, depth):
    return int(model(p, 'frontier', depth)[0].split()[1])


def seq(p):
    """The totals of the search with one context, i.e. of the C++ program."""
    w = model(p, 'seq')[0].split()
    return dict(nodes=int(w[2]), solutions=int(w[4]), max_passes=int(w[6]))


def main(args):
    by_name = {p.name: p for p in build()}
    if args == ['check']:
        ok = True
        for name, (nodes, solutions) in KNOWN.items():
            p = by_name[name]
            total = seq(p)
            good = (total['nodes'], total['solutions']) == (nodes, solutions)
            ok &= good
            print(f"{name:6} nodes {total['nodes']:>14,} solutions {total['solutions']:>8,}"
                  f"  {'OK' if good else 'WRONG, expected ' + str((nodes, solutions))}")
        sys.exit(0 if ok else 1)
    elif len(args) >= 4 and args[0] == 'depth':
        p = by_name[args[1]]
        engines = int(args[2])
        n = puzzles.STAGES * engines
        for d in [int(a) for a in args[3:]]:
            _, total = run(p, engines, d)
            print(f"{p.name}: {engines} engines, depth {d}: frontier {frontier(p, d):>10,},"
                  f" slowest context {total['max_passes']:>13,} passes,"
                  f" efficiency {total['nodes'] / n / total['max_passes']:6.1%}", flush=True)
    elif len(args) in (2, 3) and args[0] == 'run':
        p = by_name[args[1]]
        engines = int(args[2]) if len(args) == 3 else p.engines
        ctx, total = run(p, engines, p.depth)
        for x, c in enumerate(ctx):
            print(f"ctx {x:3}: passes {c['passes']:>14,} nodes {c['nodes']:>14,}"
                  f" solutions {c['solutions']:>8,}")
        n = puzzles.STAGES * engines
        print(f"total: nodes {total['nodes']:,} solutions {total['solutions']:,}"
              f" slowest {total['max_passes']:,} passes,"
              f" efficiency {total['nodes'] / n / total['max_passes']:.1%}")
    elif args == ['frontier']:
        for p in by_name.values():
            print(f'{p.name:6} depth {p.depth} frontier {frontier(p, p.depth):,}')
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main(sys.argv[1:])
