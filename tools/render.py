#!/usr/bin/env python3
"""The picture of the board, exactly as src/vga/board.vhd draws it.

This is the reference for the testbench of board.vhd (sim/board_tb.vhd), and
it generates the palette of the pieces (src/vga/palette_pkg.vhd), so the
colours and the shapes are defined here once.

The board is drawn square by square. Each square of size cell x cell pixels
(see puzzles.py) is split into four quadrants. In a quadrant, a and b are the
distances (in pixels) from the vertical and the horizontal edge of the square
that the quadrant touches, and three neighbours matter: the one beside it (H,
west or east), the one above or below it (V, north or south), and the
diagonal one (D). Each is "same" when it has the same piece. A piece is drawn
inset by G pixels from the edges to a different neighbour, so there is a gap
of 2 G between pieces, with corners rounded with the radius R. The boundary
of the piece is drawn as an outline of BW pixels in a dark colour, followed
by a rim of RIM pixels in a light colour, and the rest of the piece is filled
with its colour. With p = a - G and q = b - G:
* H and V same, D same: the inside of the piece.
* H and V same, D different: an inner corner. The G x G square at the corner
  (p < 0 and q < 0) is outside, and the distance to it is the distance to the
  boundary.
* Only H same: an edge along the horizontal edge of the square (q).
* Only V same: an edge along the vertical edge of the square (p).
* Neither: an outer corner, rounded with the radius R: within the R x R
  square at the corner, the distance is R minus the distance to the centre of
  the circle (compared as squares, so there is no square root), and outside
  it the smaller of p and q.
An empty square is drawn as a piece of its own (all neighbours different) in
the colours of C_EMPTY. Outside the squares the background is drawn.

Usage:
   tools/render.py palette > src/vga/palette_pkg.vhd
   tools/render.py png <puzzle 1-9> <pieces> <file.png>
   tools/render.py ref <puzzle 1-9> <pieces> <prefix>
The position is the first solution of the puzzle with only its first <pieces>
pieces (in the order they were placed), or all of them for 0. "ref" writes
<prefix>.mem, the board memory as snapshot.vhd writes it (one entry per line,
in hex, 256 lines), and <prefix>.ppm, the picture (P3), for board_tb.vhd.
"""

import colorsys
import sys

import model
import puzzles

WIDTH = 1280
HEIGHT = 1024

BACKGROUND = (0x14, 0x16, 0x24)
FRAME = (0x50, 0x56, 0x78)            # The frame around the board

# The colours of an empty square: outline, rim, and fill
EMPTY = ((0x2a, 0x2e, 0x40), (0x30, 0x34, 0x48), (0x22, 0x25, 0x34))


def piece_colour(n):
    """The colour of piece n: hues spaced by the golden angle, so that the
    colours of pieces with neighbouring numbers differ a lot."""
    h = (n * 0.618034 + 0.05) % 1.0
    s = 0.62 if n % 2 == 0 else 0.78
    v = 0.95 if n % 3 != 1 else 0.82
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (round(r * 255), round(g * 255), round(b * 255))


def shades(c):
    """The outline (dark), the rim (light), and the fill of a colour."""
    outline = tuple(x * 2 // 5 for x in c)
    rim = tuple((x + 255 * 2) // 3 for x in c)
    return outline, rim, c


NUM_COLOURS = 20  # Piece numbers 1 to 19, 0 = empty


def palette():
    """The (outline, rim, fill) colours of each entry, 0 = empty."""
    return [EMPTY] + [shades(piece_colour(n)) for n in range(NUM_COLOURS - 1)]


def geometry(cell):
    """The gap G, the radius R, the outline BW, and the rim RIM, in pixels,
    for a square of size cell. Must match src/vga/board.vhd."""
    g = max(2, cell // 24)
    r = cell // 4
    bw = max(2, cell // 22)
    rim = max(1, cell // 30)
    return g, r, bw, rim


def shade(a, b, s_h, s_v, s_d, cell):
    """The part of a pixel: 0 = outside, 1 = outline, 2 = rim, 3 = fill."""
    g, r, bw, rim = geometry(cell)
    p = a - g
    q = b - g
    big = 1 << 20
    if s_h and s_v:
        if s_d:
            d2, lin = big, None
        else:
            if p < 0 and q < 0:
                return 0
            if p < 0:
                d2, lin = None, q
            elif q < 0:
                d2, lin = None, p
            else:
                # The distance to the corner of the G x G square
                d2, lin = p * p + q * q, None
                if d2 < bw * bw:
                    return 1
                if d2 < (bw + rim) * (bw + rim):
                    return 2
                return 3
    elif s_h:
        if q < 0:
            return 0
        d2, lin = None, q
    elif s_v:
        if p < 0:
            return 0
        d2, lin = None, p
    else:
        if p < 0 or q < 0:
            return 0
        if p < r and q < r:
            e = (r - p) * (r - p) + (r - q) * (r - q)
            if e > r * r:
                return 0
            if e > (r - bw) * (r - bw):
                return 1
            if e > (r - bw - rim) * (r - bw - rim):
                return 2
            return 3
        d2, lin = None, min(p, q)
    if lin is None:
        return 3
    if lin < bw:
        return 1
    if lin < bw + rim:
        return 2
    return 3


def render(p, board):
    """The picture (HEIGHT rows of WIDTH (r, g, b)) of the board of puzzle p,
    a list with the piece (0 = empty, else 1 + the piece number) of each
    square."""
    pal = palette()
    img = [[BACKGROUND] * WIDTH for _ in range(HEIGHT)]
    cell = p.cell
    half = cell // 2

    def piece(r, c):
        if 0 <= r < p.rows and 0 <= c < p.cols:
            return board[r * p.cols + c]
        return -1

    # The frame: a band of 4 pixels, 4 to 7 pixels outside the board
    x1 = p.x0 + p.cols * cell
    y1 = p.y0 + p.rows * cell
    for y in range(p.y0 - 8, y1 + 8):
        for x in range(p.x0 - 8, x1 + 8):
            inside = p.x0 - 4 <= x < x1 + 4 and p.y0 - 4 <= y < y1 + 4
            if not inside and 0 <= x < WIDTH and 0 <= y < HEIGHT:
                img[y][x] = FRAME

    for row in range(p.rows):
        for col in range(p.cols):
            n = piece(row, col)
            for v in range(cell):
                for u in range(cell):
                    qx = u >= half
                    qy = v >= half
                    a = cell - 1 - u if qx else u
                    b = cell - 1 - v if qy else v
                    dc = 1 if qx else -1
                    dr = 1 if qy else -1
                    if n == 0:
                        s_h = s_v = s_d = False
                    else:
                        s_h = piece(row, col + dc) == n
                        s_v = piece(row + dr, col) == n
                        s_d = piece(row + dr, col + dc) == n
                    part = shade(a, b, s_h, s_v, s_d, cell)
                    x = p.x0 + col * cell + u
                    y = p.y0 + row * cell + v
                    img[y][x] = BACKGROUND if part == 0 else pal[n][part - 1]
    return img


def first_solution(p, pieces=0):
    """The board of the first solution of the puzzle (from the model), with
    only the first pieces (in the order they were placed: by their lowest
    square), or all of them for 0."""
    out = model.model(p, 'solutions', 1)
    board = []
    for line in out:
        board += [int(w) + 1 for w in line.split()]
    if pieces:
        order = []
        for n in board:
            if n not in order:
                order.append(n)
        keep = set(order[:pieces])
        board = [n if n in keep else 0 for n in board]
    return board


def board_mem(p, board):
    """The entries of the board memory, see snapshot.vhd: the piece (bits 12
    to 8) and the neighbour mask (bit 0 = N, then NE, E, SE, S, SW, W, NW)."""
    dirs = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]
    mem = [0] * 256
    for r in range(p.rows):
        for c in range(p.cols):
            n = board[r * p.cols + c]
            mask = 0
            for i, (dr, dc) in enumerate(dirs):
                rr, cc = r + dr, c + dc
                if n and 0 <= rr < p.rows and 0 <= cc < p.cols and board[rr * p.cols + cc] == n:
                    mask |= 1 << i
            mem[r * p.cols + c] = (n << 8) | mask
    return mem


def write_vhdl():
    pal = palette()
    w = print
    w('-- This file is generated by tools/render.py ("make palette"). Do not edit.')
    w('--')
    w('-- The colours of the board, see board.vhd: for each piece (1 to 19, and 0')
    w('-- for an empty square) the colours of the outline, the rim, and the fill, as')
    w('-- RRGGBB. The colour of a piece is its number times the golden angle on the')
    w('-- colour wheel, so pieces with neighbouring numbers have very different')
    w('-- colours.')
    w('')
    w('library ieee;')
    w('use ieee.std_logic_1164.all;')
    w('')
    w('package palette_pkg is')
    w('')
    w('   type colour_vector is array (natural range <>) of std_logic_vector(23 downto 0);')
    w('')
    for name, i in [('OUTLINE', 0), ('RIM', 1), ('FILL', 2)]:
        w(f'   constant C_{name} : colour_vector(0 to {NUM_COLOURS - 1}) := (')
        items = [f'X"{c[i][0]:02X}{c[i][1]:02X}{c[i][2]:02X}"' for c in pal]
        for k in range(0, len(items), 8):
            end = ',' if k + 8 < len(items) else ');'
            w('      ' + ', '.join(items[k:k + 8]) + end)
        w('')
    w(f'   constant C_BACKGROUND : std_logic_vector(23 downto 0) := '
      f'X"{BACKGROUND[0]:02X}{BACKGROUND[1]:02X}{BACKGROUND[2]:02X}";')
    w(f'   constant C_FRAME      : std_logic_vector(23 downto 0) := '
      f'X"{FRAME[0]:02X}{FRAME[1]:02X}{FRAME[2]:02X}";')
    w('')
    w('end package palette_pkg;')


def save_png(img, filename):
    from PIL import Image
    im = Image.new('RGB', (WIDTH, HEIGHT))
    im.putdata([px for row in img for px in row])
    im.save(filename)


def save_ppm(img, filename):
    with open(filename, 'w') as f:
        f.write(f'P3\n{WIDTH} {HEIGHT}\n255\n')
        for row in img:
            f.write(' '.join(f'{r} {g} {b}' for r, g, b in row) + '\n')


def main(args):
    if args == ['palette']:
        write_vhdl()
        return
    if len(args) == 4 and args[0] in ('png', 'ref'):
        ps = model.build()
        p = ps[int(args[1]) - 1]
        board = first_solution(p, int(args[2]))
        img = render(p, board)
        if args[0] == 'png':
            save_png(img, args[3])
        else:
            save_ppm(img, args[3] + '.ppm')
            with open(args[3] + '.mem', 'w') as f:
                f.write(''.join(f'{m:04X}\n' for m in board_mem(p, board)))
        return
    print(__doc__)
    sys.exit(1)


if __name__ == '__main__':
    main(sys.argv[1:])
