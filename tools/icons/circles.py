"""Magic circles drawn behind boots. One design per BootType, shared by every class.
    Damage         - Circle of Ruin: outward blade spikes, octagram, crossed blades
    Crowd Control  - Binding Seal: chain ring, hexagram with shackle rings, inward arrows
    Attack Speed   - Tempo Sigil: clock ticks, zig-zag lightning ring, triple swirl blades
    Movement       - Wind Path: feather petals, spiral arms, pentagram, flowing chevrons
    Mobility       - Blink Gate: outward arrows at the cardinal points, portal rings, crescent
"""
import math, random
from iconkit import *

CIRCLE_COLORS = {
    "Damage": (255, 85, 45),
    "Crowd Control": (175, 95, 255),
    "Attack Speed": (255, 205, 60),
    "Movement": (70, 235, 170),
    "Mobility": (70, 170, 255),
}

CX, CY = 50, 50


def P(r, a):
    a = math.radians(a - 90)
    return (CX + r * math.cos(a), CY + r * math.sin(a))


def ring(r, w=0.45):
    return M_ring(CX, CY, r, w)


def dashed(r, n, frac=0.6, w=0.45):
    ms = []
    step = 360 / n
    for i in range(n):
        ms.append(M_line(arc_pts(CX, CY, r, r, i * step - 90, i * step - 90 + step * frac, 6), w, caps=False))
    return U(*ms)


def poly_star(r, n, skip, rot=0, w=0.45):
    pts = [P(r, rot + i * 360 / n) for i in range(n)]
    ms = []
    for i in range(n):
        ms.append(M_line([pts[i], pts[(i + skip) % n]], w))
    return U(*ms)


def rune_band(r, n, seed, size=1.6, w=0.35):
    """ring of procedural rune glyphs; same seed -> same runes"""
    rng = random.Random(seed)
    strokes = [[(-1, -1), (1, 1)], [(-1, 1), (1, -1)], [(0, -1), (0, 1)], [(-1, 0), (1, 0)],
               [(-1, -1), (0, 0), (1, -1)], [(-1, 1), (0, 0), (1, 1)], [(-1, -1), (-1, 1), (1, 1)],
               [(1, -1), (-1, 0), (1, 1)], [(-1, -1), (1, -1), (1, 1)]]
    ms = []
    for i in range(n):
        a = i * 360 / n
        cx, cy = P(r, a)
        rot = a
        for s in rng.sample(strokes, rng.randint(2, 3)):
            pts = [(cx + size * (x * math.cos(math.radians(rot)) - y * math.sin(math.radians(rot))),
                    cy + size * (x * math.sin(math.radians(rot)) + y * math.cos(math.radians(rot)))) for x, y in s]
            ms.append(M_line(pts, w))
    return U(*ms)


def ticks(r0, r1, n, w=0.35, every=None, r2=None):
    ms = []
    for i in range(n):
        a = i * 360 / n
        rr = r2 if (every and i % every == 0) else r1
        ms.append(M_line([P(r0, a), P(rr, a)], w, caps=False))
    return U(*ms)


# ---------------------------------------------------------------- designs
def circle_damage():
    ms = [ring(46.5, 0.6), ring(44), ring(38), rune_band(41, 24, "Damage"), ring(30, 0.4), ring(20)]
    for i in range(8):  # outward blade spikes
        a = i * 45
        big = i % 2 == 0
        tip = P(49 if big else 46, a)
        l, r = P(38, a - (7 if big else 4)), P(38, a + (7 if big else 4))
        ms.append(M_line([l, tip, r], 0.45))
        if big:
            ms.append(M_line([P(38, a), P(44.5, a)], 0.35))
    ms.append(poly_star(30, 8, 3, rot=22.5))            # octagram
    for a in (45, 135):                                  # crossed blades in the core
        p0, p1 = P(18, a), P(18, a + 180)
        ms.append(M_line([p0, p1], 0.6))
        g0, g1 = P(9, a + 180 - 20), P(9, a + 180 + 20)
        ms.append(M_line([g0, g1], 0.5))
    for i in range(8):
        ms.append(M_line([P(3, i * 45), P(7 if i % 2 else 11, i * 45)], 0.4))
    return U(*ms)


def circle_cc():
    ms = [ring(46.5, 0.6), ring(38), ring(33, 0.35), ring(18)]
    n = 26                                               # chain links around the rim
    for i in range(n):
        a = i * 360 / n
        cx, cy = P(42, a)
        if i % 2 == 0:
            ms.append(M_ring(cx, cy, 2.6, 0.45, ry=1.4) if False else
                      rotate_mask(M_ring(cx, cy, 2.8, 0.45, ry=1.5), a + 90, c=(cx, cy)))
        else:
            ms.append(rotate_mask(M_ring(cx, cy, 2.0, 0.45, ry=0.9), a, c=(cx, cy)))
    ms.append(poly_star(33, 6, 2))                      # hexagram
    for i in range(6):                                   # shackle rings at the points
        cx, cy = P(33, i * 60)
        ms.append(M_ring(cx, cy, 3.0, 0.45))
        ms.append(M_ring(cx, cy, 1.4, 0.35))
    for i in range(6):                                   # arrows pressing inward
        a = i * 60 + 30
        ms.append(M_line([P(29, a), P(20.5, a)], 0.45))
        ms.append(M_line([P(23.5, a - 7), P(20.5, a), P(23.5, a + 7)], 0.45))
    ms.append(M_ring(CX, CY - 2, 4, 0.5))               # keyhole lock in the centre
    ms.append(M_line([(CX, CY + 1), (CX, CY + 7)], 1.2))
    ms.append(rune_band(15, 12, "CC", size=1.2))
    return U(*ms)


def circle_as():
    ms = [ring(46.5, 0.6), ring(44), ticks(44, 42.3, 60, every=5, r2=40.5), ring(38.5)]
    zz = []                                              # zig-zag lightning ring
    for i in range(49):
        a = i * 360 / 48
        zz.append(P(34 if i % 2 else 31, a))
    ms.append(M_line(zz, 0.45))
    for k in range(3):                                   # three swirling blades with arrowheads
        base = k * 120
        pts = [P(12 + 20 * t, base + 110 * t) for t in [i / 20 for i in range(21)]]
        ms.append(M_line(pts, 0.6))
        end = pts[-1]
        ms.append(M_line([P(29, base + 100), end, P(33.5, base + 104)], 0.5))
    ms.append(poly_star(17, 3, 1))                      # triangle
    ms.append(poly_star(17, 3, 1, rot=60))
    ms.append(ring(9))
    ms.append(rune_band(26.5, 18, "AS", size=1.1, w=0.3))
    return U(*ms)


def circle_move():
    ms = [dashed(46.5, 48, 0.55, 0.55), ring(44), ring(35), ring(26)]
    for i in range(12):                                  # feather petals
        a = i * 30
        base, tip = P(35.5, a), P(44, a)
        l, r = P(40, a - 5.5), P(40, a + 5.5)
        ms.append(M_line(bez(base, l, tip, n=10) + bez(tip, r, base, n=10), 0.45))
        ms.append(M_line([base, tip], 0.3))
    for i in range(24):                                  # chevrons flowing clockwise
        a = i * 15 + 7.5
        ms.append(M_line([P(33, a - 2.5), P(30.5, a + 1.5), P(28, a - 2.5)], 0.35))
    for k in range(4):                                   # spiral arms
        pts = [P(4 + 20 * t, k * 90 + 140 * t) for t in [i / 24 for i in range(25)]]
        ms.append(M_line(pts, 0.45))
    ms.append(poly_star(26, 5, 2))
    return U(*ms)


def circle_mobility():
    ms = [ring(46.5, 0.6), dashed(44, 36, 0.5), ring(36), ring(22), ring(20, 0.3)]
    for i in range(4):                                   # outward arrows at cardinal points
        a = i * 90
        ms.append(M_line([P(24, a), P(45, a)], 0.5))
        for o in (0, 3.2):
            ms.append(M_line([P(40.5 - o, a - 7), P(45 - o, a), P(40.5 - o, a + 7)], 0.5))
    ms.append(poly_star(32, 8, 3, rot=22.5))            # 8-point star
    for i in range(8):                                   # portal rings
        cx, cy = P(29, i * 45 + 22.5)
        ms.append(M_ring(cx, cy, 2.2, 0.4))
        ms.append(M_ell(cx, cy, 0.6))
    ms.append(M_line(arc_pts(CX, CY, 12, 12, 40, 320, 40), 0.55))          # crescent
    ms.append(M_line(arc_pts(CX + 4, CY, 9.5, 9.5, 60, 300, 40), 0.45))
    ms.append(M_line([(CX, CY - 4), (CX + 3, CY), (CX, CY + 4), (CX - 3, CY), (CX, CY - 4)], 0.45))
    ms.append(rune_band(40, 20, "MOB", size=1.2))
    return U(*ms)


DESIGNS = {
    "Damage": circle_damage,
    "Crowd Control": circle_cc,
    "Attack Speed": circle_as,
    "Movement": circle_move,
    "Mobility": circle_mobility,
}
_cache = {}


def draw_circle(cv, boot_type, k=1.0):
    if boot_type not in _cache:
        _cache[boot_type] = DESIGNS[boot_type]()
    m = _cache[boot_type]
    c = CIRCLE_COLORS[boot_type]
    cv.add(c, blur(M_ell(CX, CY, 46), 6) * 0.35, 0.5 * k)      # inner light pool
    cv.add(c, blur(m, 1.8), 0.9 * k)
    cv.add(c, blur(m, 0.45), 0.9 * k)
    cv.add(lighten(c, 0.6), m, 0.6 * k)
