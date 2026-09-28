"""Context effects. Each one illustrates a game mechanic (lifesteal, bleed, burn...)."""
import math
from iconkit import *


def _rng(cv):
    return cv.rng


# ---------------------------------------------------------------- primitives
def flames(cv, base_y, x0, x1, height, n=6, color=(255, 120, 30), clip=None, k=1.0):
    rng = cv.rng
    for layer, (col, hs, ws) in enumerate(((darken(color, 0.1), 1.0, 1.0), (lighten(color, 0.25), 0.75, 0.7), ((255, 235, 170), 0.45, 0.4))):
        for i in range(n):
            x = x0 + (x1 - x0) * (i + 0.5 + rng.uniform(-0.3, 0.3)) / n
            h = height * hs * rng.uniform(0.7, 1.15)
            w = (x1 - x0) / n * 0.75 * ws * rng.uniform(0.8, 1.3)
            lean = rng.uniform(-3, 3)
            pts = bez((x - w, base_y), (x - w * 0.9, base_y - h * 0.5), (x + lean - w * 0.2, base_y - h * 0.8), (x + lean, base_y - h), n=12) + \
                bez((x + lean, base_y - h), (x + lean + w * 0.4, base_y - h * 0.6), (x + w * 0.9, base_y - h * 0.4), (x + w, base_y), n=12)
            m = M_poly(pts)
            if clip is not None:
                m = INT(m, clip)
            if layer == 0:
                cv.add(col, blur(m, 2.2), 0.55 * k)
            cv.add(col, blur(m, 0.5), (0.75 if layer else 0.6) * k)


def sparkles(cv, n=6, area=(15, 15, 85, 85), size=(1.2, 3.2), color=None, clip=None, k=1.0):
    rng = cv.rng
    c = color or lighten(cv.theme, 0.6)
    for _ in range(n):
        x, y = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3])
        s = rng.uniform(*size)
        star = M_poly([(x, y - s), (x + s * 0.14, y - s * 0.14), (x + s, y), (x + s * 0.14, y + s * 0.14),
                       (x, y + s), (x - s * 0.14, y + s * 0.14), (x - s, y), (x - s * 0.14, y - s * 0.14)])
        if clip is not None:
            star = INT(star, clip)
        cv.add(c, blur(star, s * 0.4), 0.7 * k)
        cv.add((255, 255, 255), star, 0.85 * k)


def drop(cx, cy, r):
    return M_poly(bez((cx, cy - r * 2.2), (cx - r * 1.3, cy - r * 0.2), (cx - r, cy + r * 0.4), n=10) +
                  arc_pts(cx, cy + r * 0.3, r, r, 180, 360, 16)[::-1][::-1] +
                  bez((cx + r, cy + r * 0.4), (cx + r * 1.3, cy - r * 0.2), (cx, cy - r * 2.2), n=10)) if False else \
        U(M_ell(cx, cy, r), M_poly([(cx - r * 0.93, cy - r * 0.35), (cx, cy - r * 2.4), (cx + r * 0.93, cy - r * 0.35)]))


def liquid_drops(cv, pts, color):
    for x, y, r in pts:
        m = drop(x, y, r)
        cv.part(m, "gem", color=color, round=r * 0.7, outline=0.6, shadow=0.2, rim=0.3)
        cv.add(color, blur(m, r), 0.35)


def stream(cv, p0, p3, bend, color, w=0.9, k=1.0, arrow=False):
    """curved glowing energy stream from p0 to p3"""
    p1 = (p0[0] + bend[0], p0[1] + bend[1])
    p2 = (p3[0] + bend[0] * 0.3, p3[1] + bend[1] * 0.3)
    pts = bez(p0, p1, p2, p3, n=30)
    ms = [M_line(pts[i:i + 2], w * (0.35 + 0.65 * i / 30)) for i in range(0, 30, 1)]
    m = U(*ms)
    cv.glow(m, color, k=k, r=1.2)
    if arrow:
        x, y = pts[-1]
        x0, y0 = pts[-4]
        a = math.atan2(y - y0, x - x0)
        tip = [(x + 2.5 * math.cos(a), y + 2.5 * math.sin(a)), (x + 2.2 * math.cos(a + 2.4), y + 2.2 * math.sin(a + 2.4)),
               (x + 2.2 * math.cos(a - 2.4), y + 2.2 * math.sin(a - 2.4))]
        cv.glow(M_poly(tip), color, k=k, r=1.0)
    return pts


def motes(cv, n, color, area=(15, 15, 85, 85), r=(0.5, 1.4), k=1.0):
    rng = cv.rng
    for _ in range(n):
        x, y = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3])
        rr = rng.uniform(*r)
        m = M_ell(x, y, rr)
        cv.add(color, blur(m, rr * 1.5), 0.8 * k)
        cv.add(lighten(color, 0.6), m, 0.8 * k)


def mist(cv, color, n=8, area=(10, 50, 90, 95), r=(6, 14), k=0.18):
    rng = cv.rng
    for _ in range(n):
        x, y, rr = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3]), rng.uniform(*r)
        cv.add(color, blur(M_ell(x, y, rr, rr * 0.7), rr * 0.4), k)


def bolt(cv, p0, p1, color, segs=7, jitter=4, w=0.6, branches=1, k=1.0):
    rng = cv.rng
    pts = [p0]
    for i in range(1, segs):
        t = i / segs
        pts.append((p0[0] + (p1[0] - p0[0]) * t + rng.uniform(-jitter, jitter),
                    p0[1] + (p1[1] - p0[1]) * t + rng.uniform(-jitter, jitter)))
    pts.append(p1)
    cv.glow(M_line(pts, w), color, k=k, r=1.2)
    for _ in range(branches):
        j = rng.randint(1, segs - 2)
        q = pts[j]
        e = (q[0] + rng.uniform(-10, 10), q[1] + rng.uniform(-10, 10))
        cv.glow(M_line([q, ((q[0] + e[0]) / 2 + rng.uniform(-2, 2), (q[1] + e[1]) / 2 + rng.uniform(-2, 2)), e], w * 0.6), color, k=k * 0.8, r=0.9)


def snowflake(cv, cx, cy, r, color=(200, 235, 255), w=0.5, k=0.9):
    ms = []
    for i in range(6):
        a = math.radians(i * 60 - 90)
        ms.append(M_line([(cx, cy), (cx + r * math.cos(a), cy + r * math.sin(a))], w))
        bx, by = cx + r * 0.55 * math.cos(a), cy + r * 0.55 * math.sin(a)
        for sd in (-1, 1):
            b = a + sd * 0.75
            ms.append(M_line([(bx, by), (bx + r * 0.32 * math.cos(b), by + r * 0.32 * math.sin(b))], w * 0.8))
    cv.glow(U(*ms), color, k=k, r=0.8)


def shards(cv, n, color, area=(10, 10, 90, 90), size=(2, 5), mat="steel"):
    rng = cv.rng
    for _ in range(n):
        x, y, s, a = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3]), rng.uniform(*size), rng.uniform(0, 360)
        pts = tf([(x, y - s), (x + s * 0.5, y + s * 0.2), (x - s * 0.3, y + s * 0.6)], ang=a, c=(x, y))
        cv.part(M_poly(pts), mat, color=color, round=0.5, outline=0.6, shadow=0.2)


def ring_wave(cv, cx, cy, r, color, ry=None, w=0.6, k=0.8, a0=0, a1=360):
    cv.glow(M_line(arc_pts(cx, cy, r, ry or r, a0, a1, 60), w), color, k=k, r=1.0)


def sigil(cv, cx, cy, r, color, k=0.8, sides=3):
    """small hunter's-mark style target sigil"""
    ms = [M_ring(cx, cy, r, 0.45), M_ring(cx, cy, r * 0.55, 0.35)]
    for i in range(4):
        a = math.radians(i * 90 + 45)
        ms.append(M_line([(cx + r * 0.7 * math.cos(a), cy + r * 0.7 * math.sin(a)), (cx + r * 1.35 * math.cos(a), cy + r * 1.35 * math.sin(a))], 0.45))
    pts = [(cx + r * 0.4 * math.cos(math.radians(i * 360 / sides - 90)), cy + r * 0.4 * math.sin(math.radians(i * 360 / sides - 90))) for i in range(sides + 1)]
    ms.append(M_line(pts, 0.35))
    cv.glow(U(*ms), color, k=k, r=0.9)


def counter(cv, cx, cy, n, color, r=2.2, gap=5.5, lit=None, k=0.9):
    """row of pips - shows 'every Nth hit' mechanics"""
    lit = n if lit is None else lit
    x0 = cx - gap * (n - 1) / 2
    for i in range(n):
        m = M_poly([(x0 + i * gap, cy - r), (x0 + i * gap + r, cy), (x0 + i * gap, cy + r), (x0 + i * gap - r, cy)])
        if i < lit:
            cv.glow(m, color, k=k, r=0.8)
        else:
            cv.glow(SUB(m, M_poly([(x0 + i * gap, cy - r * 0.5), (x0 + i * gap + r * 0.5, cy), (x0 + i * gap, cy + r * 0.5), (x0 + i * gap - r * 0.5, cy)])), color, k=k * 0.45, r=0.6)


def cracked_cross(cv, cx, cy, s, color=(120, 255, 120), crack=(20, 10, 10)):
    """healing cross split by a crack - grievous wounds / anti-heal"""
    m = U(M_rect(cx - s * 0.3, cy - s, cx + s * 0.3, cy + s, 0.6), M_rect(cx - s, cy - s * 0.3, cx + s, cy + s * 0.3, 0.6))
    cv.glow(m, color, k=0.7, r=1.0)
    crk = M_line([(cx - s * 0.6, cy - s * 1.1), (cx + s * 0.1, cy - s * 0.2), (cx - s * 0.3, cy + s * 0.2), (cx + s * 0.6, cy + s * 1.1)], 0.9)
    cv.over(crack, dilate(crk, 0.2))


# ---------------------------------------------------------------- mechanics
def fx_lifesteal(cv, color=(255, 40, 60), target=(50, 50), n=4):
    """blood drawn from the edges into the item"""
    rng = cv.rng
    for i in range(n):
        a = math.radians(-150 + i * (300 / max(1, n - 1)) + rng.uniform(-10, 10))
        p0 = (target[0] + 46 * math.cos(a), target[1] + 46 * math.sin(a))
        p3 = (target[0] + 10 * math.cos(a), target[1] + 10 * math.sin(a))
        bend = (18 * math.cos(a + 1.3), 18 * math.sin(a + 1.3))
        pts = stream(cv, p0, p3, bend, color, w=1.2, k=0.75, arrow=True)
        for j in (6, 14, 22):   # blood beads travelling inward
            x, y = pts[j]
            cv.part(M_ell(x, y, 0.7 + j * 0.03), "gem", color=color, round=0.4, outline=0.4, shadow=0, rim=0.2)
        x, y = pts[0]
        cv.add(color, blur(M_ell(x, y, 3), 1.5), 0.6)
    cv.add(color, blur(M_ell(target[0], target[1], 12), 4), 0.45)
    motes(cv, 8, color, r=(0.4, 1.0), k=0.8)


def fx_bleed(cv, color=(190, 10, 25), pts=None):
    rng = cv.rng
    pts = pts or [(rng.uniform(55, 75), rng.uniform(62, 78), rng.uniform(1.4, 2.0)) for _ in range(3)]
    liquid_drops(cv, pts, color)
    for _ in range(8):
        x, y, r = rng.uniform(15, 85), rng.uniform(15, 85), rng.uniform(0.3, 0.8)
        cv.part(M_ell(x, y, r), "gem", color=color, round=0.3, outline=0.3, shadow=0, rim=0)


def fx_poison(cv, color=(120, 235, 70)):
    rng = cv.rng
    mist(cv, color, n=9, area=(10, 45, 90, 95), k=0.2)
    for _ in range(9):
        x, y, r = rng.uniform(20, 80), rng.uniform(25, 85), rng.uniform(0.8, 2.0)
        cv.glow(M_ring(x, y, r, 0.35), color, k=0.6, r=0.6)
    liquid_drops(cv, [(rng.uniform(60, 74), rng.uniform(66, 78), 1.6), (rng.uniform(30, 45), rng.uniform(70, 82), 1.2)], color)


def fx_burn(cv, color=(255, 120, 30)):
    """licking flames behind the item + rising embers"""
    cv.add(color, blur(M_ell(50, 96, 46, 16), 6), 0.55)
    flames(cv, 99, 4, 96, 20, n=9, color=color, k=0.45)
    motes(cv, 16, lighten(color, 0.25), area=(8, 8, 92, 90), r=(0.3, 0.9))


def fx_frost(cv, color=(170, 225, 255)):
    rng = cv.rng
    mist(cv, color, n=7, area=(10, 60, 90, 95), k=0.14)
    for x, y, r in ((78, 20, 7), (20, 76, 5), (84, 70, 3.5)):
        snowflake(cv, x, y, r, color)
    shards(cv, 5, (180, 220, 255), area=(10, 70, 90, 92), size=(2, 4), mat="silver")


def fx_slow(cv, color=(150, 210, 255)):
    """frozen ground under the item"""
    cv.add(color, blur(M_ell(50, 90, 40, 7), 2), 0.6)
    for i in range(7):
        x = 16 + i * 11
        cv.part(M_poly([(x - 3, 94), (x, 94 - 8 - (i % 3) * 4), (x + 3, 94)]), "gem", color=color, round=0.8, emissive=0.2, shadow=0)
    snowflake(cv, 80, 20, 6, color)


def fx_lightning(cv, color=(140, 200, 255)):
    bolt(cv, (12, 14), (34, 54), color, segs=6, jitter=4)
    bolt(cv, (88, 36), (68, 84), color, segs=6, jitter=4)
    motes(cv, 8, color, r=(0.3, 0.8))


def fx_chain_lightning(cv, color=(140, 200, 255)):
    """bolt bouncing between three targets"""
    pts = [(14, 30), (40, 18), (70, 26), (86, 56)]
    for a, b in zip(pts, pts[1:]):
        bolt(cv, a, b, color, segs=5, jitter=3, branches=0)
    for p in pts:
        cv.glow(M_ell(p[0], p[1], 1.6), color, k=1.0, r=1.4)


def fx_shatter(cv, color=(200, 205, 215)):
    """armor fragments breaking away - armor penetration / armor break"""
    rng = cv.rng
    for _ in range(7):
        x, y = rng.uniform(58, 90), rng.uniform(55, 90)
        s, a = rng.uniform(2.5, 5), rng.uniform(0, 360)
        pts = tf([(x - s, y - s * 0.6), (x + s * 0.8, y - s), (x + s, y + s * 0.4), (x - s * 0.2, y + s)], ang=a, c=(x, y))
        cv.part(M_poly(pts), "steel", round=0.8, streak=0.1, outline=0.7, shadow=0.3)
    for a in (-30, 10, 50):
        r = rng.uniform(10, 16)
        cv.glow(M_line([(66, 68), (66 + r * math.cos(math.radians(a)), 68 + r * math.sin(math.radians(a)))], 0.4), (255, 220, 160), k=0.6, r=0.8)


def fx_pierce(cv, color=None):
    """arrow trail punching through a broken plate"""
    c = color or lighten(cv.theme, 0.4)
    for i in range(4):
        y = 70 + i * 2.2
        cv.glow(M_line([(8, y + 10 - i * 3), (38, y - 14 - i * 3)], 0.35), c, k=0.5, r=0.7)


def fx_speed(cv, color=None):
    rng = cv.rng
    c = color or lighten(cv.theme, 0.5)
    for i in range(6):
        y = 22 + i * 10 + rng.uniform(-2, 2)
        x0 = rng.uniform(4, 10)
        cv.glow(M_line([(x0, y), (x0 + rng.uniform(14, 26), y - 2)], 0.45), c, k=0.6, r=0.8)


def fx_wind(cv, color=None):
    rng = cv.rng
    c = color or lighten(cv.theme, 0.5)
    for i in range(4):
        y = 24 + i * 15 + rng.uniform(-3, 3)
        x0 = rng.uniform(4, 12)
        pts = bez((x0, y), (x0 + 16, y - 7), (x0 + 30, y + 2), (x0 + 36, y - 4), n=20)
        cv.glow(M_line(pts, 0.5), c, k=0.6, r=0.9)
        cv.glow(M_line(arc_pts(pts[-1][0] + 2, pts[-1][1] + 2, 2.5, 2.5, 180, 450, 12), 0.4), c, k=0.5, r=0.7)


def fx_shadow(cv, color=None):
    rng = cv.rng
    c = color or cv.theme
    for _ in range(10):
        x, y, r = rng.uniform(10, 90), rng.uniform(50, 96), rng.uniform(6, 14)
        cv.over(darken(c, 0.85), blur(M_ell(x, y, r, r * 0.7), 3) * 0.55)
    for _ in range(4):
        x = rng.uniform(15, 85)
        pts = bez((x, 96), (x + rng.uniform(-14, 14), 76), (x + rng.uniform(-10, 10), 62), (x + rng.uniform(-6, 6), 48), n=20)
        cv.glow(M_line(pts, 0.5), lighten(c, 0.2), k=0.5, r=1.1)


def fx_smoke(cv, color=(150, 150, 170)):
    rng = cv.rng
    for _ in range(12):
        x, y, r = rng.uniform(8, 92), rng.uniform(8, 70), rng.uniform(6, 13)
        cv.add(color, blur(M_ell(x, y, r, r * 0.8), 4), 0.13)
    for _ in range(3):
        x, y = rng.uniform(15, 85), rng.uniform(15, 50)
        cv.glow(M_line(arc_pts(x, y, 5, 3, 0, 260, 20), 0.35), color, k=0.35, r=0.9)


def fx_mana(cv, color=(90, 160, 255)):
    motes(cv, 14, color, area=(12, 12, 88, 88), r=(0.4, 1.2))
    for x in (20, 80):
        pts = bez((x, 90), (x + 6, 70), (x - 6, 50), (x + 2, 28), n=20)
        cv.glow(M_line(pts, 0.4), color, k=0.5, r=1.0)


def fx_runes(cv, color=None, r=42):
    from circles import rune_band
    c = color or lighten(cv.theme, 0.45)
    cv.glow(U(M_ring(50, 50, r + 2.5, 0.35), M_ring(50, 50, r - 2.5, 0.35), rune_band(r, 16, "runes" + str(r), size=1.2)), c, k=0.5, r=0.8)


def fx_curse(cv, color=(140, 255, 90)):
    rng = cv.rng
    mist(cv, color, n=6, area=(10, 40, 90, 95), k=0.15)
    for x, y, s in ((20, 24, 3), (82, 30, 2.4), (78, 80, 2.8)):
        sk = U(M_ell(x, y, s, s * 0.9), M_rect(x - s * 0.55, y + s * 0.3, x + s * 0.55, y + s * 1.2, 0.3))
        sk = SUB(sk, M_ell(x - s * 0.38, y, s * 0.26, s * 0.3), M_ell(x + s * 0.38, y, s * 0.26, s * 0.3))
        cv.glow(sk, color, k=0.7, r=0.8)


def fx_meteor(cv, color=(255, 170, 60)):
    x1, y1 = 74, 26
    for i, w in enumerate((3.2, 2.2, 1.2)):
        cv.glow(M_poly(ribbon([(96, 2), (x1, y1)], lambda t: w * t)), lighten(color, 0.2 * i), k=0.6, r=1.4)
    cv.part(M_ell(x1, y1, 3.6), "stone", color=(120, 60, 30), round=1.5, rim=1.5)
    cv.glow(M_ring(x1, y1, 3.8, 0.6), color, k=0.8, r=1.2)
    motes(cv, 6, color, area=(68, 4, 96, 34), r=(0.3, 0.8))


def fx_explosion(cv, color=(255, 130, 40), cx=50, cy=50):
    for r, k in ((30, 0.35), (20, 0.5)):
        cv.add(color, blur(M_ell(cx, cy, r), r * 0.3), k)
    rng = cv.rng
    for i in range(14):
        a = math.radians(i * 360 / 14 + rng.uniform(-8, 8))
        r0, r1 = 20, rng.uniform(36, 46)
        cv.glow(M_line([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)), (cx + r1 * math.cos(a), cy + r1 * math.sin(a))], 0.5), lighten(color, 0.3), k=0.6, r=0.9)
    motes(cv, 10, color, r=(0.4, 1.0))


def fx_mark(cv, color=(255, 60, 60), cx=76, cy=24, r=8):
    sigil(cv, cx, cy, r, color)


def fx_souls(cv, color=(210, 150, 255), target=(50, 50)):
    rng = cv.rng
    for i, a in enumerate((-150, -30, 200, 330)):
        a = math.radians(a + rng.uniform(-10, 10))
        p0 = (target[0] + 44 * math.cos(a), target[1] + 44 * math.sin(a))
        p3 = (target[0] + 16 * math.cos(a), target[1] + 16 * math.sin(a))
        pts = stream(cv, p0, p3, (14 * math.cos(a + 1.5), 14 * math.sin(a + 1.5)), color, w=0.7, k=0.55)
        x, y = pts[0]
        wisp = U(M_ell(x, y, 2.2, 2.6), M_poly([(x - 2.2, y), (x + 2.2, y), (x + (target[0] - x) * 0.08, y + (target[1] - y) * 0.08 + 5)]))
        cv.glow(wisp, color, k=0.6, r=1.0)
        for ex in (-0.8, 0.8):
            cv.over((10, 0, 20), M_ell(x + ex, y - 0.4, 0.45, 0.6))


def fx_coins(cv):
    rng = cv.rng
    for x, y, r in ((18, 76, 5), (82, 80, 4.2), (76, 20, 3.4), (24, 22, 2.8), (86, 54, 3)):
        a = rng.uniform(-30, 30)
        m = M_ell(x, y, r, r * 0.55, ang=a)
        cv.part(m, "gold", round=1.2, outline=0.8, shadow=0.3)
        cv.engrave(tf(arc_pts(x, y, r * 0.65, r * 0.35, 0, 360, 24), ang=a, c=(x, y)), 0.25, 0.4)
    sparkles(cv, n=4, color=(255, 220, 120))


def fx_rewind(cv, color=(120, 220, 255)):
    pts = arc_pts(50, 50, 44, 44, 300, 20, 60)[::-1]
    cv.glow(M_line(pts, 0.7), color, k=0.7, r=1.0)
    x, y = pts[-1]
    cv.glow(M_poly([(x, y - 3), (x - 4, y + 1), (x + 2, y + 3)]), color, k=0.8, r=0.9)
    pts = arc_pts(50, 50, 44, 44, 120, 200, 40)[::-1]
    cv.glow(M_line(pts, 0.7), color, k=0.7, r=1.0)
    x, y = pts[-1]
    cv.glow(M_poly([(x, y + 3), (x + 4, y - 1), (x - 2, y - 3)]), color, k=0.8, r=0.9)


def fx_shield_dome(cv, color=(150, 210, 255)):
    ring_wave(cv, 50, 56, 44, color, ry=40, w=0.6, k=0.6, a0=180, a1=360)
    cv.add(color, clamp01(blur(M_ell(50, 56, 44, 40), 3) - blur(M_ell(50, 56, 38, 34), 3)) * (YY < 56), 0.35)
    for a in range(200, 350, 25):
        x, y = 50 + 44 * math.cos(math.radians(a)), 56 + 40 * math.sin(math.radians(a))
        cv.glow(M_poly([(x, y - 1.5), (x + 1.5, y), (x, y + 1.5), (x - 1.5, y)]), color, k=0.6, r=0.7)


def fx_reflect(cv, color=(190, 225, 255)):
    """incoming bolt bouncing off"""
    cv.glow(M_line([(8, 16), (40, 40)], 0.9), (255, 120, 90), k=0.8, r=1.2)
    cv.glow(M_line([(40, 40), (12, 70)], 0.9), color, k=0.9, r=1.2)
    cv.glow(M_poly([(12, 70), (13.5, 64.5), (17.5, 68.5)]), color, k=1.0, r=1.0)
    cv.add((255, 255, 255), blur(M_ell(40, 40, 4), 2), 0.9)


def fx_heat(cv, color=(255, 110, 30)):
    for r in (34, 40, 46):
        ring_wave(cv, 50, 50, r, color, w=0.45, k=0.45)
    flames(cv, 96, 6, 94, 22, n=9, color=color, k=0.7)


def fx_blight(cv, color=(140, 220, 60)):
    mist(cv, color, n=10, area=(8, 20, 92, 96), k=0.16)
    cracked_cross(cv, 80, 22, 5.5, color=(140, 255, 140))


def fx_growth(cv, color=(120, 220, 90)):
    rng = cv.rng
    for sd in (-1, 1):
        x = 50 + sd * 40
        pts = bez((x, 96), (x - sd * 6, 72), (x + sd * 4, 50), (x - sd * 4, 30), n=24)
        cv.part(M_line(pts, 1.2), "wood", color=(60, 90, 40), round=0.4, shadow=0.2)
        for i in range(4, 24, 5):
            px, py = pts[i]
            leaf = tf(bez((0, 0), (3, -2.5), (0, -7), n=8) + bez((0, -7), (-3, -2.5), (0, 0), n=8), ang=sd * 60 + rng.uniform(-20, 20), c=(0, 0), off=(px, py))
            cv.part(M_poly(leaf), "cloth", color=color, round=0.8, outline=0.5, shadow=0.1)
    motes(cv, 6, color, r=(0.4, 0.9))


def fx_rage(cv, color=(255, 50, 30)):
    """low-HP fury: red veins, embers and a cracked health pip"""
    rng = cv.rng
    for _ in range(3):
        x0 = rng.uniform(15, 85)
        bolt(cv, (x0, 96), (x0 + rng.uniform(-10, 10), 62), color, segs=5, jitter=3, branches=1, k=0.6)
    motes(cv, 12, color, r=(0.4, 1.1))


def fx_stacks(cv, color=(255, 70, 60)):
    """rising chevrons = stacking buff"""
    for i in range(3):
        y = 80 - i * 7
        cv.glow(M_line([(78, y + 3), (84, y - 2), (90, y + 3)], 0.8), color, k=0.8 - i * 0.15, r=0.9)


def fx_anti_heal(cv, color=(150, 255, 150)):
    cracked_cross(cv, 80, 22, 6, color=color)


def fx_gold_glint(cv):
    sparkles(cv, n=5, color=(255, 220, 120))


def fx_ghost(cv, color=None):
    c = color or lighten(cv.theme, 0.4)
    cv.add(c, blur(cv.sil, 3) * (1 - cv.sil), 0.7)
    mist(cv, c, n=6, area=(10, 10, 90, 90), k=0.1)


def fx_target_range(cv, color=(255, 220, 120)):
    """long dashed trajectory ending at a distant target - Precision"""
    for i in range(9):
        t0, t1 = i / 9, i / 9 + 0.06
        p = lambda t: (8 + 80 * t, 88 - 70 * t + 22 * math.sin(math.pi * t) * -0.4)
        cv.glow(M_line([p(t0), p(t1)], 0.45), color, k=0.5, r=0.7)
    sigil(cv, 86, 16, 5.5, (255, 90, 60), k=0.9)


def fx_tenacity(cv, color=(200, 220, 255)):
    """broken shackle bits flying off"""
    for x, y, a in ((18, 22, 30), (82, 78, -20)):
        link = SUB(M_ell(x, y, 5, 3), M_ell(x, y, 3, 1.4), M_rect(x + 1, y - 4, x + 6, y + 4))
        cv.part(rotate_mask(link, a, c=(x, y)), "darksteel", round=0.8)
    sparkles(cv, n=4, color=color)


def fx_rescue(cv, color=(255, 230, 150)):
    fx_shield_dome(cv, color)
    for x, y in ((18, 30), (82, 34)):
        cv.glow(U(M_rect(x - 0.9, y - 3, x + 0.9, y + 3, 0.4), M_rect(x - 3, y - 0.9, x + 3, y + 0.9, 0.4)), color, k=0.8, r=0.9)


def fx_retaliate(cv, color=(255, 150, 60)):
    for a in (200, 230, 260):
        r = math.radians(a)
        cv.glow(M_line([(50 + 44 * math.cos(r), 50 + 44 * math.sin(r)), (50 + 30 * math.cos(r), 50 + 30 * math.sin(r))], 0.7), (255, 90, 60), k=0.6, r=0.9)
    for a in (20, 50, 80):
        r = math.radians(a)
        cv.glow(M_line([(50 + 30 * math.cos(r), 50 + 30 * math.sin(r)), (50 + 46 * math.cos(r), 50 + 46 * math.sin(r))], 0.9), color, k=0.8, r=1.1)


def fx_ground_crack(cv, color=None):
    c = color or lighten(cv.theme, 0.35)
    cv.add(c, blur(M_ell(52, 92, 38, 5), 2.5), 0.6)
    rng = cv.rng
    for a in (-170, -140, -40, -10):
        r1 = rng.uniform(22, 34)
        pts = [(52, 92), (52 + r1 * 0.5 * math.cos(math.radians(a)) + rng.uniform(-2, 2), 92 + r1 * 0.12 * math.sin(math.radians(a))),
               (52 + r1 * math.cos(math.radians(a)), 92 + r1 * 0.25 * math.sin(math.radians(a)))]
        cv.glow(M_line(pts, 0.5), c, k=0.8, r=0.9)
    shards(cv, 6, None, area=(18, 76, 86, 92), size=(1.5, 3), mat="stone")


def fx_blade_shadow(cv, color=None):
    """afterimages behind the object (dash / blink)"""
    c = color or lighten(cv.theme, 0.3)
    for i, dx in enumerate((-10, -20)):
        g = np.roll(cv.sil, int(dx * K), axis=1)
        cv.add(c, blur(g, 0.8) * (1 - cv.sil), 0.35 - i * 0.12)
