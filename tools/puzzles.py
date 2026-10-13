"""The puzzles, and their translation to the tables of the hardware.

This module is used by gen_puzzle_pkg.py (which writes src/main/puzzle_pkg.vhd),
by model.py (the reference model of the search), and by the testbench data
generator. It reads the puzzle files exactly like the C++ program
(github.com/MJoergen/puzzle, initInfo.cpp), builds the placements exactly
like it (solver.cpp, BuildBitMaps and CreateBitMaps), and then groups them
into slots, see below.

A *placement* is a set of squares on the board covered by one piece. The C++
program builds all of them for each piece: for every offset (row, column) and
every one of the 8 orientations (block.cpp), in that order, it keeps the ones
that are inside the board and are not a duplicate of an earlier placement of
the same piece. The search fills the lowest empty square (the *anchor*, in
row-major order), and at each anchor it tries the unused pieces in order, and
for each piece its placements whose lowest square is the anchor, in the order
they were built.

A *slot* is one distinct shape of one piece (an orientation, with duplicates
removed), relative to its lowest square. A placement is a slot at an anchor,
so the hardware only needs the slots, and a test of whether a slot is inside
the board at a given anchor (the extent of the slot: rows below the anchor,
and columns to the left and to the right of it). The slots are numbered by
piece, and within a piece in the order of the C++ program, so that the
hardware visits the children of a node in exactly the same order as the C++
program. This is checked for every anchor of every puzzle (check()).

The squares of a slot are given as linear offsets from the anchor, i.e.
row * cols + column, where the column may be negative (to the left of the
anchor) for the rows below the anchor. The largest offset plus one is the
*width* W of the window of the hardware, see src/main/engine.vhd.
"""

import os

# The puzzles, in the order of the keys 1 to 9 (puzzle 0 is key 1).
#   name     : the file puzzles/<name>.txt
#   depth    : the depth D at which the tree is split between the search
#              contexts, see src/main/engine.vhd. Chosen with model.py.
#   engines  : the number of engines working on the puzzle on the MEGA65, and
#   nexys      on the Nexys 4 DDR, see solver.vhd.
#   title    : shown on the screen.
PUZZLES = [
    dict(name='8x8',   depth=4, engines=16, nexys=4, title='12 pentominoes and a square'),
    dict(name='6x10',  depth=4, engines=8, nexys=2, title='12 pentominoes'),
    dict(name='3x20',  depth=4, engines=8, nexys=2, title='12 pentominoes'),
    dict(name='5x8',   depth=4, engines=4, nexys=1, title='10 tetrominoes'),
    dict(name='7x7',   depth=3, engines=2, nexys=1, title='9 pentominoes and a square'),
    dict(name='5x5',   depth=1, engines=1, nexys=1, title='5 pentominoes'),
    dict(name='1x16',  depth=2, engines=1, nexys=1, title='8 pairs of squares'),
    dict(name='1x27',  depth=2, engines=1, nexys=1, title='9 triples of squares'),
    dict(name='16x16', depth=4, engines=2, nexys=1, title='19 large pieces'),
]

# The number of pipeline stages of an engine, i.e. the number of search
# contexts in each engine. Must match C_STAGES in src/main/engine_pkg.vhd.
STAGES = 8

# The screen layout of the board, see src/vga/board.vhd: the board is
# centred in the area of AREA_W x AREA_H pixels with its top left corner at
# (AREA_X, AREA_Y), and the size of a square is at most MAX_CELL pixels. The
# size of a square is even.
AREA_X = 32
AREA_Y = 96
AREA_W = 1216
AREA_H = 704
MAX_CELL = 96

TOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


class Puzzle:
    """A puzzle, read from puzzles/<name>.txt."""

    def __init__(self, index, name, depth, engines, nexys, title):
        self.index = index
        self.name = name
        self.depth = depth
        self.engines = engines
        self.nexys = nexys
        self.title = title
        self.rows, self.cols, self.pieces = read_file(
            os.path.join(TOP, 'puzzles', name + '.txt'))
        self.squares = self.rows * self.cols
        self.placements = build_placements(self.rows, self.cols, self.pieces)
        self.slots = build_slots(self.cols, self.placements)
        self.width = max(max(s['offsets']) for s in self.slots) + 1
        self.cell = min(AREA_W // self.cols, AREA_H // self.rows, MAX_CELL) // 2 * 2
        self.x0 = AREA_X + (AREA_W - self.cell * self.cols) // 2
        self.y0 = AREA_Y + (AREA_H - self.cell * self.rows) // 2

    def valid(self, anchor, slot):
        """Whether the slot is inside the board at the anchor."""
        r, c = divmod(anchor, self.cols)
        s = self.slots[slot]
        return (r + s['down'] < self.rows and c - s['left'] >= 0
                and c + s['right'] < self.cols)

    def mask(self, slot):
        """The squares of the slot as a bit mask of the window."""
        m = 0
        for o in self.slots[slot]['offsets']:
            m |= 1 << o
        return m


def read_file(filename):
    """Reads a puzzle file like initInfo.cpp: the lines that are empty or
    start with '#' are skipped, and the rest are the number of rows, the
    number of columns, the number of pieces, and for each piece the number of
    squares followed by the row and the column of each square."""
    words = []
    for line in open(filename):
        line = line.rstrip('\n')
        if line == '' or line[0] == '#':
            continue
        words.append(line.split())
    pos = 0

    def take():
        nonlocal pos
        pos += 1
        return words[pos - 1]
    rows = int(take()[0])
    cols = int(take()[0])
    num = int(take()[0])
    pieces = []
    for _ in range(num):
        n = int(take()[0])
        squares = []
        for _ in range(n):
            w = take()
            squares.append((int(w[0]), int(w[1])))
        pieces.append(squares)
    return rows, cols, pieces


def orientations(squares):
    """The 8 orientations of a piece, in the order of block.cpp."""
    return [[(r, c) for r, c in squares],
            [(r, -c) for r, c in squares],
            [(c, r) for r, c in squares],
            [(c, -r) for r, c in squares],
            [(-c, r) for r, c in squares],
            [(-c, -r) for r, c in squares],
            [(-r, c) for r, c in squares],
            [(-r, -c) for r, c in squares]]


def build_placements(rows, cols, pieces):
    """For each piece the list of its placements, each a frozenset of bit
    numbers (row * cols + col), in the order of solver.cpp."""
    result = []
    for squares in pieces:
        configs = orientations(squares)
        bitmaps = []
        seen = set()
        for row in range(rows):
            for col in range(cols):
                for config in configs:
                    sqs = [(r + row, c + col) for r, c in config]
                    if not all(0 <= r < rows and 0 <= c < cols for r, c in sqs):
                        continue
                    bm = frozenset(r * cols + c for r, c in sqs)
                    if bm in seen:
                        continue
                    seen.add(bm)
                    bitmaps.append(bm)
        result.append(bitmaps)
    return result


def shape_of(cols, bm):
    """The shape of a placement relative to its lowest square: a tuple of
    (row, column) offsets, sorted in row-major order."""
    low = min(bm)
    r0, c0 = divmod(low, cols)
    return tuple(sorted((b // cols - r0, b % cols - c0) for b in bm))


def build_slots(cols, placements):
    """The slots of all pieces, numbered by piece, and within a piece in an
    order that is consistent with the order of the C++ program at every
    anchor (a topological sort of the orders seen at the anchors)."""
    slots = []
    for piece, bitmaps in enumerate(placements):
        # The sequence of shapes at each anchor, in the order of the C++
        # program, i.e. of the index of the placement
        by_anchor = {}
        for bm in bitmaps:
            by_anchor.setdefault(min(bm), []).append(shape_of(cols, bm))
        shapes = []
        for bm in bitmaps:
            s = shape_of(cols, bm)
            if s not in shapes:
                shapes.append(s)
        # Constraints "a before b", and a topological sort that prefers the
        # order of the first appearance
        before = {s: set() for s in shapes}
        for seq in by_anchor.values():
            assert len(seq) == len(set(seq)), 'A shape twice at one anchor'
            for i in range(len(seq) - 1):
                before[seq[i + 1]].add(seq[i])
        order = []
        while len(order) < len(shapes):
            ready = [s for s in shapes if s not in order and before[s] <= set(order)]
            assert ready, f'Piece {piece}: the order of the slots is not consistent'
            order.append(ready[0])
        for s in order:
            slots.append(dict(
                piece=piece,
                shape=s,
                offsets=[dr * cols + dc for dr, dc in s],
                down=max(dr for dr, dc in s),
                left=-min(dc for dr, dc in s),
                right=max(dc for dr, dc in s)))
    return slots


def check(p):
    """Checks that the slots give exactly the placements of the C++ program,
    and in the same order at every anchor."""
    for anchor in range(p.squares):
        # The C++ order: by piece, then by the index of the placement
        expected = []
        for piece, bitmaps in enumerate(p.placements):
            for bm in bitmaps:
                if min(bm) == anchor:
                    expected.append((piece, bm))
        got = []
        for k, s in enumerate(p.slots):
            if p.valid(anchor, k):
                got.append((s['piece'], frozenset(anchor + o for o in s['offsets'])))
        assert got == expected, f'{p.name}: the slots differ from the C++ program at {anchor}'
    for s in p.slots:
        assert s['offsets'][0] == 0 and s['offsets'] == sorted(s['offsets'])


def load():
    """All the puzzles, checked."""
    result = []
    for i, d in enumerate(PUZZLES):
        p = Puzzle(i, **d)
        check(p)
        result.append(p)
    return result
