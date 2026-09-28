"""Item silhouettes. Each draws onto a Canvas in 0..100 space. `o` = option dict."""
import math
from iconkit import *


# ================================================================ FOOTWEAR
def boot(cv, o):
    """Side-view boot, toe to the right. o: style = leather|plate|slipper|greave, trim, lean."""
    style = o.get("style", "leather")
    trim = o.get("trim", "gold")
    ang = o.get("lean", -8)
    T = lambda p: tf(p, ang=ang, s=o.get("s", 0.86), off=o.get("off", (1, 5)))
    low = style == "slipper"
    top = 42 if low else 12
    if low:
        body = [(30, top)] + bezier((30, top), (44, top - 2), (58, top + 6), 8) + \
            bezier((58, top + 6), (70, 60), (86, 60), 12) + bezier((86, 60), (96, 56), (94, 50), 8) + \
            bezier((94, 50), (100, 64), (86, 82), 10) + [(31, 82)] + bezier((31, 82), (26, 64), (30, top), 10)
    else:
        body = bezier((33, top), (37, 38), (34, 58), 14) + bezier((34, 58), (28, 68), (30, 81), 10) + [(84, 82)] + \
            bezier((84, 82), (96, 74), (80, 64), 12) + bezier((80, 64), (64, 60), (61, 46), 12) + \
            bezier((61, 46), (59, 28), (65, top), 12)
    shaft_mat = "leather" if style in ("leather", "slipper") else "darksteel"
    cv.part(M_poly(T(body)), shaft_mat, color=o.get("leather"), tex=0.12)
    # sole + heel
    cv.part(M_poly(T([(27, 79), (89, 79), (91, 83), (87, 86), (28, 86)])), "dark", outline=0.8)
    cv.part(M_poly(T([(27, 80), (43, 80), (42, 91), (29, 91)])), "dark", outline=0.8)
    if style in ("plate", "greave"):
        # overlapping shin plates
        for i, y in enumerate((14, 27, 40)):
            cv.part(M_poly(T(bezier((33, y + 2), (50, y - 3), (66, y), 10) + [(66, y + 12)] +
                             bezier((66, y + 12), (50, y + 9), (32, y + 14), 10))), "steel",
                    color=o.get("metal"), outline=0.9)
        cv.part(M_poly(T(bezier((62, 55), (80, 58), (90, 72), 12) + [(88, 79), (64, 79), (60, 66)])), "steel",
                color=o.get("metal"))
        if style == "greave":
            cv.part(M_ell(*T([(51, 16)])[0], 9, 7), trim, outline=0.9)
            cv.part(M_ell(*T([(51, 16)])[0], 3, 3), "gem", spec=1.2)
    else:
        # cuff + straps + toe cap
        if not low:
            cuff = [(27, top - 5), (71, top - 7)] + bezier((71, top - 7), (66, top + 6), (64, top + 13), 8) + \
                bezier((64, top + 13), (48, top + 10), (34, top + 14), 8)
            cv.part(M_poly(T(cuff)), "leather", color=darken(o.get("leather") or cv.theme, 0.35), tex=0.15)
            cv.part(M_line(T([(27, top - 5), (71, top - 7)]), 2.2), trim)
            for y, x0, x1 in ((36, 35.5, 60), (50, 34.5, 61.5)):
                cv.part(M_poly(T([(x0, y), (x1, y - 1.5), (x1 + 0.5, y + 4), (x0 - 0.3, y + 5)])), "leather",
                        color=darken(o.get("leather") or cv.theme, 0.55))
                cv.part(M_rect(*T([(45, y - 1.5)])[0], *T([(52, y + 5.5)])[0], r=0.8), trim)
        cv.part(M_poly(T(bezier((72, 63), (88, 64), (92, 75), 10) + [(89, 80), (74, 80), (70, 71)])),
                "steel" if trim != "gold" else "gold", color=o.get("metal"))
        if low:
            cv.part(M_ell(*T([(94, 60)])[0], 2.4), "gem", spec=1.2)
    if o.get("wing"):
        wing(cv, T([(30, 30)])[0], o.get("wing"), flip=True)


def wing(cv, at, color, flip=False, s=1.0):
    x, y = at
    d = -1 if flip else 1
    feathers = []
    for i in range(5):
        l = (20 - i * 3) * s
        a = math.radians(-150 + i * 18) if flip else math.radians(-30 - i * 18)
        ex, ey = x + l * math.cos(a), y + l * math.sin(a)
        feathers.append(M_poly([(x, y + 2 * s), (ex, ey), (x + d * 3 * s, y + 4 * s)]))
    cv.part(U(*feathers), "silver", color=color, outline=0.7, spec=0.6)


# ================================================================ BLADES
def sword(cv, o):
    """Long sword, rotated. o: ang, blade(material), guard, gem, length, wide, curved."""
    L = o.get("length", 84)
    w = o.get("wide", 6.0)
    tip = 50 - L / 2
    base = tip + L * 0.72
    blade = [(50, tip), (50 + w, tip + 9), (50 + w * 0.9, base), (50 - w * 0.9, base), (50 - w, tip + 9)]
    if o.get("curved"):
        blade = [(50, tip), (50 + w * 1.6, tip + 12), (50 + w * 1.2, base), (50 - w * 0.8, base),
                 (50 - w * 0.2, tip + 16)]
    if o.get("serrated"):
        edge = []
        for i in range(7):
            y = tip + 10 + i * (base - tip - 12) / 7
            edge += [(50 + w * 0.95, y), (50 + w * 1.5, y + 2.5)]
        blade = [(50, tip)] + edge + [(50 + w * 0.9, base), (50 - w * 0.9, base), (50 - w, tip + 9)]
    A = o.get("ang", 45)
    T = lambda p: tf(p, ang=A, off=o.get("off", (0, 0)), s=o.get("s", 1.1))
    cv.part(M_poly(T(blade)), o.get("blade", "steel"), color=o.get("tint"))
    # fuller
    cv.add((255, 255, 255), M_line(T([(50, tip + 10), (50, base - 3)]), 0.7), 0.35)
    if o.get("edgeglow"):
        cv.glowline(M_line(T([(50, tip), (50 + w, tip + 9), (50 + w * 0.9, base)]), 0.6), o["edgeglow"], r=1.2)
    gy = base
    guard = [(50 - 13, gy), (50 + 13, gy), (50 + 15, gy + 2.5), (50 + 11, gy + 4.5), (50 - 11, gy + 4.5), (50 - 15, gy + 2.5)]
    if o.get("guard_wings"):
        guard = [(50 - 18, gy - 5), (50 - 8, gy), (50 + 8, gy), (50 + 18, gy - 5), (50 + 14, gy + 4.5), (50 - 14, gy + 4.5)]
    cv.part(M_poly(T(guard)), o.get("guard", "gold"))
    cv.part(M_poly(T([(48, gy + 4.5), (52, gy + 4.5), (52.2, gy + 17), (47.8, gy + 17)])), "leather", color=(90, 50, 30), tex=0.3)
    for i in range(4):
        cv.part(M_line(T([(47.8, gy + 7 + i * 3), (52.2, gy + 8.5 + i * 3)]), 0.6), "dark", outline=0)
    cv.part(M_ell(*T([(50, gy + 19.5)])[0], 3.2), o.get("guard", "gold"))
    if o.get("gem"):
        cv.part(M_ell(*T([(50, gy + 2.2)])[0], 2.3), "gem", color=o["gem"])
        cv.part(M_ell(*T([(50, gy + 19.5)])[0], 1.6), "gem", color=o["gem"])


def dagger(cv, o):
    o = dict(o)
    o.setdefault("length", 74)
    o.setdefault("wide", 5.0)
    sword(cv, o)


def twin_daggers(cv, o):
    a = dict(o, ang=-38, off=(-4, 2), length=68, s=0.95)
    b = dict(o, ang=38, off=(4, 2), length=68, s=0.95)
    sword(cv, a)
    sword(cv, b)


def axe(cv, o):
    """Battle axe; o: double, ang, head(material), haft."""
    A = o.get("ang", 30)
    T = lambda p: tf(p, ang=A, off=o.get("off", (0, 0)))
    cv.part(M_poly(T([(48.5, 14), (51.5, 14), (52, 90), (48, 90)])), o.get("haft", "wood"), tex=0.25)
    for y in (70, 78):
        cv.part(M_rect(*T([(47.5, y)])[0], *T([(52.5, y + 3)])[0]), "leather", color=(80, 45, 25))
    head = bezier((53, 18), (70, 16), (84, 6), 14) + bezier((84, 6), (74, 28), (86, 54), 14) + \
        bezier((86, 54), (70, 42), (53, 42), 14)
    heads = [head]
    if o.get("double", True):
        heads.append(mirror_x(head))
    for h in heads:
        cv.part(M_poly(T(h)), o.get("head", "steel"), color=o.get("tint"))
    cv.part(M_poly(T([(46, 18), (54, 18), (55, 40), (45, 40)])), "darksteel")
    cv.part(M_poly(T([(50, 6), (53, 16), (47, 16)])), o.get("head", "steel"), color=o.get("tint"))
    if o.get("gem"):
        cv.part(M_ell(*T([(50, 29)])[0], 3), "gem", color=o["gem"])
    if o.get("edgeglow"):
        for h in heads:
            e = h[14:29]
            cv.glowline(M_line(T(e), 0.7), o["edgeglow"], r=1.3)


def cleaver(cv, o):
    A = o.get("ang", 35)
    T = lambda p: tf(p, ang=A)
    cv.part(M_poly(T([(48.5, 48), (51.5, 48), (52, 92), (48, 92)])), "wood", tex=0.3)
    blade = [(44, 8), (74, 14), (78, 30), (70, 52), (52, 54), (46, 50)]
    cv.part(M_poly(T(blade)), "steel", color=o.get("tint"))
    cv.part(M_ell(*T([(54, 20)])[0], 3.5), "dark")
    cv.part(M_poly(T([(45, 46), (55, 46), (56, 56), (44, 56)])), "gold")
    if o.get("edgeglow"):
        cv.glowline(M_line(T([(74, 14), (78, 30), (70, 52)]), 0.8), o["edgeglow"])


def hammer(cv, o):
    A = o.get("ang", 30)
    T = lambda p: tf(p, ang=A)
    cv.part(M_poly(T([(48.5, 30), (51.5, 30), (52, 92), (48, 92)])), "wood", tex=0.25)
    cv.part(M_poly(T([(30, 14), (70, 14), (72, 18), (72, 36), (70, 40), (30, 40), (28, 36), (28, 18)])),
            o.get("head", "steel"), color=o.get("tint"))
    cv.part(M_poly(T([(40, 12), (60, 12), (60, 42), (40, 42)])), "gold")
    cv.part(M_poly(T([(26, 20), (30, 20), (30, 34), (26, 34)])), "darksteel")
    cv.part(M_poly(T([(70, 20), (74, 20), (74, 34), (70, 34)])), "darksteel")
    if o.get("gem"):
        cv.part(M_ell(*T([(50, 27)])[0], 4), "gem", color=o["gem"])
    cv.part(M_ell(*T([(50, 93)])[0], 3), "gold")


def claw(cv, o):
    """Three curved talon blades over a wrist guard."""
    base = o.get("mat", "steel")
    cv.part(M_poly([(24, 70), (52, 58), (60, 72), (34, 88)]), "leather", color=darken(cv.theme, 0.3), tex=0.2)
    cv.part(M_poly([(40, 60), (56, 54), (64, 66), (48, 74)]), "darksteel")
    for i, dx in enumerate((-10, 0, 10)):
        p = bezier((46 + dx, 62 + i * 2), (58 + dx, 34), (86 + dx * 0.4, 16 + i * 6), 16) + \
            bezier((86 + dx * 0.4, 16 + i * 6), (62 + dx, 42), (52 + dx, 66 + i * 2), 16)
        cv.part(M_poly(p), base, color=o.get("tint"))
        if o.get("edgeglow"):
            cv.glowline(M_line(p[4:16], 0.5), o["edgeglow"], r=1.0, k=0.8)


def fang(cv, o):
    p = bezier((40, 14), (30, 50), (54, 88), 20) + bezier((54, 88), (54, 50), (62, 14), 20)
    cv.part(M_poly(p), "bone")
    cv.part(M_poly([(36, 10), (66, 10), (64, 20), (38, 20)]), "gold")
    if o.get("gem"):
        cv.part(M_ell(51, 15, 3), "gem", color=o["gem"])


def talon(cv, o):
    p = bezier((30, 30), (70, 8), (84, 60), 22) + bezier((84, 60), (66, 30), (38, 44), 22)
    cv.part(M_poly(p), o.get("mat", "darksteel"), color=o.get("tint"))
    cv.part(M_poly([(22, 28), (40, 24), (44, 48), (26, 52)]), "gold")
    cv.part(M_ell(33, 38, 3), "gem", color=o.get("gem", cv.theme))
    if o.get("edgeglow"):
        cv.glowline(M_line(p[6:22], 0.6), o["edgeglow"])


# ================================================================ BOWS
def bow(cv, o):
    A = o.get("ang", 20)
    T = lambda p: tf(p, ang=A)
    limb = bezier((50, 10), (84, 30), (58, 50), 20) + bezier((58, 50), (84, 70), (50, 90), 20)
    inner = bezier((50, 90), (78, 70), (55, 50), 20) + bezier((55, 50), (78, 30), (50, 10), 20)
    cv.part(M_poly(T(limb + inner)), o.get("mat", "wood"), color=o.get("tint"), tex=0.15)
    cv.part(M_poly(T([(54, 44), (62, 44), (62, 56), (54, 56)])), "leather", color=(80, 45, 25))
    for y in (10, 90):
        cv.part(M_ell(*T([(50, y)])[0], 2.2), o.get("tip", "gold"))
    cv.add((230, 225, 210), M_line(T([(50, 11), (50, 89)]), 0.5), 0.9)
    if o.get("arrow", True):
        arrow(cv, dict(ang=A + 90, len=64, glow=o.get("glow"), head=o.get("head", "steel")))
    if o.get("gem"):
        cv.part(M_ell(*T([(58, 50)])[0], 2.6), "gem", color=o["gem"])


def arrow(cv, o):
    A = o.get("ang", 45)
    L = o.get("len", 70)
    off = o.get("off", (0, 0))
    T = lambda p: tf(p, ang=A, off=off)
    y0, y1 = 50 - L / 2, 50 + L / 2
    cv.part(M_poly(T([(49.4, y0 + 8), (50.6, y0 + 8), (50.6, y1), (49.4, y1)])), "wood")
    cv.part(M_poly(T([(50, y0), (53.5, y0 + 9), (50, y0 + 7.5), (46.5, y0 + 9)])), o.get("head", "steel"))
    for s in (-1, 1):
        cv.part(M_poly(T([(50, y1 - 12), (50 + s * 4, y1 - 9), (50 + s * 4, y1 - 1), (50, y1 - 4)])),
                "cloth", color=o.get("fletch", (200, 60, 50)), outline=0.6)
    if o.get("glow"):
        cv.glowline(M_line(T([(50, y0), (50, y0 + 8)]), 0.8), o["glow"])


def quiver(cv, o):
    A = o.get("ang", -18)
    T = lambda p: tf(p, ang=A, off=(0, 4))
    fl = o.get("fletch", lighten(cv.theme, 0.1))
    # arrows stick out of the top, fletching up
    for dx, h in ((-8, 16), (0, 22), (8, 12)):
        x = 50 + dx
        cv.part(M_poly(T([(x - 0.7, 32), (x + 0.7, 32), (x + 0.7, 30 - h), (x - 0.7, 30 - h)])), "wood", outline=0.6)
        for sd in (-1, 1):
            cv.part(M_poly(T([(x, 28 - h), (x + sd * 3.6, 31 - h), (x + sd * 3.6, 40 - h), (x, 37 - h)])),
                    "cloth", color=fl, outline=0.6)
        if o.get("glow"):
            cv.glowline(M_line(T([(x, 29 - h), (x, 40 - h)]), 0.5), o["glow"], r=1.0, k=0.6)
    body = [(35, 30)] + bezier((35, 30), (33, 60), (39, 90), 10) + [(61, 90)] + bezier((61, 90), (67, 60), (65, 30), 10)
    cv.part(M_poly(T(body)), "leather", color=o.get("leather"), tex=0.2)
    cv.part(M_poly(T([(33, 27), (67, 27), (66, 35), (34, 35)])), o.get("trim", "gold"))
    cv.part(M_poly(T([(38, 84), (62, 84), (61, 91), (39, 91)])), o.get("trim", "gold"))
    for y in (48, 70):
        cv.part(M_line(T([(35, y), (65, y)]), 1.4, round_caps=False), "leather", color=darken(o.get("leather") or cv.theme, 0.5))
    cv.part(M_ell(*T([(50, 58)])[0], 5.5), o.get("trim", "gold"))
    cv.part(M_ell(*T([(50, 58)])[0], 3.4), "gem", color=o.get("gem", lighten(cv.theme, 0.2)))
    cv.part(M_line(T(bezier((64, 34), (84, 50), (62, 84), 16)), 1.6), "leather", color=(70, 45, 30))


# ================================================================ ARMOUR
def shield(cv, o):
    kind = o.get("kind", "kite")
    if kind == "round":
        cv.part(M_ell(50, 50, 34), o.get("mat", "steel"), color=o.get("tint"))
        cv.part(M_ring(50, 50, 32, 3.5), o.get("trim", "gold"))
        face = M_ell(50, 50, 26)
    else:
        outer = [(50, 10), (82, 18), (80, 52), (50, 90), (20, 52), (18, 18)]
        cv.part(M_poly(outer), o.get("trim", "gold"))
        inner = [(50, 15), (77, 21), (75, 51), (50, 84), (25, 51), (23, 21)]
        face = M_poly(inner)
        cv.part(face, o.get("mat", "cloth") if o.get("mat") else "steel", color=o.get("tint"))
    em = o.get("emblem", "cross")
    if em == "sun":
        rays = []
        for k in range(12):
            a = math.radians(k * 30)
            rays.append(M_poly([(50 + 5 * math.cos(a + 0.25), 48 + 5 * math.sin(a + 0.25)),
                                (50 + 20 * math.cos(a), 48 + 20 * math.sin(a)),
                                (50 + 5 * math.cos(a - 0.25), 48 + 5 * math.sin(a - 0.25))]))
        cv.part(U(*rays), "gold")
        cv.part(M_ell(50, 48, 8), "gem", color=(255, 200, 80))
    elif em == "cross":
        cv.part(U(M_rect(46, 20, 54, 78), M_rect(28, 36, 72, 44)), o.get("trim", "gold"))
        cv.part(M_ell(50, 40, 4.5), "gem", color=o.get("gem", cv.theme))
    elif em == "boss":
        cv.part(M_ell(50, 50, 10), o.get("trim", "gold"))
        for a in range(0, 360, 45):
            x, y = 50 + 22 * math.cos(math.radians(a)), 50 + 22 * math.sin(math.radians(a))
            cv.part(M_ell(x, y, 2.2), "darksteel")
    elif em == "mirror":
        cv.part(M_ell(50, 46, 15, 18), "silver", spec=1.4)
        cv.add((255, 255, 255), M_line([(42, 36), (54, 58)], 1.2), 0.5)
    elif em == "frost":
        fx_snow(cv, 50, 46, 16)
    elif em == "blood":
        cv.part(M_poly(bezier((50, 28), (36, 50), (50, 62), 14) + bezier((50, 62), (64, 50), (50, 28), 14)),
                "gem", color=(200, 20, 30))
    elif em == "wall":
        for r in range(4):
            for c in range(3):
                x = 32 + c * 12 + (6 if r % 2 else 0)
                cv.part(M_rect(x, 24 + r * 12, x + 11, 34 + r * 12, 1), "stone", tex=0.2)


def chestplate(cv, o):
    mat, trim, tint = o.get("mat", "steel"), o.get("trim", "gold"), o.get("tint")
    torso = [(34, 20)] + bezier((34, 20), (50, 28), (66, 20), 10) + [(72, 30)] + \
        bezier((72, 30), (66, 52), (70, 72), 12) + bezier((70, 72), (60, 88), (50, 90), 8) + \
        bezier((50, 90), (40, 88), (30, 72), 8) + bezier((30, 72), (34, 52), (28, 30), 12)
    cv.part(M_poly(torso), mat, color=tint)
    if o.get("mail"):
        rings = [M_ring(x + (1.5 if (y // 3) % 2 else 0), y, 1.5, 0.6) for y in range(66, 88, 3) for x in range(32, 69, 3)]
        cv.part(INT(U(*rings), M_poly(torso)), "steel", outline=0.3, shadow=False)
    cv.add((0, 0, 0), M_line([(50, 30), (50, 62)], 0.8), 0.5)
    for y in (64, 73):
        cv.add((0, 0, 0), M_line(bezier((32, y), (50, y + 5), (68, y), 10), 0.7), 0.5)
    cv.part(M_poly([(34, 18)] + bezier((34, 18), (50, 26), (66, 18), 10) + [(64, 25)] + bezier((64, 25), (50, 33), (36, 25), 10)), trim)
    for sd in (-1, 1):   # pauldrons
        cx = 50 + sd * 26
        p = bezier((cx - sd * 8, 20), (cx + sd * 12, 14), (cx + sd * 14, 40), 14) + [(cx - sd * 4, 34)]
        cv.part(M_poly(p), mat, color=tint)
        cv.part(M_line(bezier((cx - sd * 7, 22), (cx + sd * 10, 17), (cx + sd * 12, 38), 14), 1.4), trim)
    if o.get("emblem"):
        cv.part(M_ell(50, 46, 7), trim)
        cv.part(M_ell(50, 46, 5), "gem", color=o["emblem"])


def gauntlet(cv, o):
    mat = o.get("mat", "steel")
    tint = o.get("tint")
    cv.part(M_poly([(30, 64), (64, 60), (70, 92), (32, 94)]), mat, color=tint)          # cuff
    cv.part(M_poly([(28, 64), (65, 60), (66, 66), (29, 70)]), o.get("trim", "gold"))
    cv.part(M_poly([(70, 50), (82, 38), (88, 44), (78, 60)]), mat, color=tint)          # thumb
    for i, (x, h) in enumerate(((29, 26), (40, 31), (51, 31), (62, 27))):
        top = 34 - h
        cv.part(M_rect(x, top, x + 10, 40, 4.5), mat, color=tint)
        for j in (0.33, 0.66):
            y = top + (40 - top) * j
            cv.add((0, 0, 0), M_line([(x + 1.5, y), (x + 8.5, y)], 0.7), 0.55)
        cv.part(M_rect(x + 1, top, x + 9, top + 4, 2), o.get("trim", "gold"), outline=0.4, shadow=False)
    cv.part(M_poly([(27, 36), (73, 34), (74, 64), (29, 66)]), mat, color=tint)          # back plate
    cv.add((0, 0, 0), M_line([(29, 45), (73, 44)], 0.8), 0.5)
    if o.get("spikes"):
        for x in (34, 45, 56, 67):
            cv.part(M_poly([(x - 3, 38), (x, 27), (x + 3, 38)]), "darksteel")
    if o.get("gem"):
        cv.part(M_ell(51, 53, 6), o.get("trim", "gold"))
        cv.part(M_ell(51, 53, 4), "gem", color=o["gem"])


def belt(cv, o):
    cv.part(M_poly(bezier((10, 44), (50, 56), (90, 44), 20) + bezier((90, 60), (50, 72), (10, 60), 20)),
            "leather", color=o.get("leather"), tex=0.2)
    cv.part(M_rect(36, 38, 64, 72, 4), o.get("trim", "gold"))
    cv.part(M_rect(41, 43, 59, 67, 3), "dark")
    cv.part(M_ell(50, 55, 6), "gem", color=o.get("gem", cv.theme))
    for x in (18, 26, 74, 82):
        cv.part(M_ell(x, 52 + (2 if x in (26, 74) else 0), 1.8), "steel")


def cloak(cv, o):
    hood = bezier((50, 12), (22, 16), (24, 50), 16) + [(18, 90), (82, 90)] + bezier((76, 50), (78, 16), (50, 12), 16)
    cv.part(M_poly(hood), "cloth", color=o.get("tint"), tex=0.12)
    face = bezier((50, 22), (34, 26), (36, 52), 14) + bezier((36, 52), (50, 62), (64, 52), 14) + bezier((64, 52), (66, 26), (50, 22), 14)
    cv.over(np.zeros((S, S, 3), np.float32), M_poly(face))
    for x in (44, 56):
        cv.glowline(M_ell(x, 42, 1.6, 1.0), o.get("eyes", lighten(cv.theme, 0.4)), r=1.0)
    cv.part(M_ell(50, 66, 4), "gem", color=o.get("gem", cv.theme))
    for x in (30, 50, 70):
        cv.add((0, 0, 0), M_line([(x, 70), (x + (x - 50) * 0.2, 90)], 0.8), 0.4)


def horn(cv, o):
    # curved horn: thin mouthpiece at upper-left sweeping to a wide bell at lower-right
    n = 30
    spine = bezier((18, 22), (30, 78), (78, 70), n)
    top, bot = [], []
    for i, (x, y) in enumerate(spine):
        t = i / n
        r = 2.2 + 12 * t ** 1.8
        x2, y2 = spine[min(i + 1, n)] if i < n else spine[i]
        x1, y1 = spine[max(i - 1, 0)]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        top.append((x + nx * r, y + ny * r))
        bot.append((x - nx * r, y - ny * r))
    cv.part(M_poly(top + bot[::-1]), o.get("mat", "bone"), color=o.get("tint"), tex=0.15)
    for t in (0.3, 0.55, 0.8):
        i = int(n * t)
        cv.part(M_line([top[i], bot[i]], 2.6, round_caps=False), "gold")
    ex, ey = spine[-1]
    cv.part(M_ell(ex + 1, ey, 5, 14), "gold")
    cv.part(M_ell(ex + 1.5, ey, 3, 10.5), "dark", outline=0, shadow=False)
    cv.part(M_ell(*spine[0], 3), "gold")
    cv.part(M_line(bezier(spine[3], (50, 20), spine[24], 16), 1.2), "leather", color=(90, 55, 30))
    if o.get("waves"):
        for r in (8, 14, 20):
            cv.glowline(M_line(arc_pts(ex + 4, ey, r * 0.7, r, -60, 60, 16), 0.6), lighten(cv.theme, 0.35), r=1.0, k=0.7)


def drum(cv, o):
    for s_ in (1, -1):   # crossed sticks behind the drum
        cv.part(M_line([(50 - s_ * 30, 8), (50 + s_ * 18, 50)], 2.4), "wood")
        cv.part(M_ell(50 - s_ * 30, 8, 3.2), "leather", color=(220, 200, 160))
    cv.part(M_rect(18, 40, 82, 82, 3), "wood", color=o.get("tint"), tex=0.2)
    for i in range(6):
        x = 20 + i * 10.5
        cv.part(M_line([(x, 44), (x + 10.5, 78)], 0.8), "leather", color=(220, 200, 160), outline=0.4)
    cv.part(M_ell(50, 40, 32, 9), "leather", color=(225, 195, 155), tex=0.2)
    cv.part(M_ring(50, 40, 31.5, 2.4), "gold")
    cv.part(M_rect(18, 78, 82, 84, 2), "gold")
    if o.get("emblem"):
        cv.part(M_ell(50, 61, 7), "gold")
        cv.part(M_ell(50, 61, 5), "gem", color=o["emblem"])


def bell(cv, o):
    p = [(50, 16)] + bezier((50, 16), (32, 18), (30, 50), 14) + [(22, 72), (78, 72)] + bezier((70, 50), (68, 18), (50, 16), 14)
    cv.part(M_poly(p), o.get("mat", "gold"))
    cv.part(M_ring(50, 12, 4, 2), "darksteel")
    cv.part(M_rect(20, 70, 80, 76, 2), "bronze")
    cv.part(M_ell(50, 80, 4.5), "darksteel")
    for r in (10, 16):
        cv.glowline(M_line(arc_pts(50, 82, r * 2.2, r, 20, 160, 20), 0.6), lighten(cv.theme, 0.4), r=1.0, k=0.7)


def pouch(cv, o):
    cv.part(M_poly(bezier((34, 36), (10, 70), (50, 88), 18) + bezier((50, 88), (90, 70), (66, 36), 18)), "leather",
            color=o.get("leather"), tex=0.25)
    cv.part(M_poly([(36, 30), (64, 30), (68, 38), (32, 38)]), "leather", color=darken(o.get("leather") or cv.theme, 0.3))
    cv.part(M_rect(33, 36, 67, 40, 1), "gold")
    cv.part(M_line([(62, 30), (72, 14), (78, 16)], 1.2), "leather", color=(200, 180, 140))
    cv.glowline(M_ell(78, 16, 1.4), (255, 190, 90), r=1.2)
    for i in range(5):
        x, y, r = cv.rng.uniform(22, 80), cv.rng.uniform(20, 50), cv.rng.uniform(5, 10)
        cv.add((150, 150, 170), blur(M_ell(x, y, r), 3), 0.25)


def bomb(cv, o):
    cv.part(M_ell(48, 58, 26), "darksteel", color=o.get("tint"))
    cv.part(M_rect(42, 26, 56, 34, 1), "bronze")
    cv.part(M_line(bezier((49, 26), (52, 14), (64, 12), 10), 1.2), "leather", color=(200, 180, 140))
    cv.glowline(M_ell(64, 12, 1.6), (255, 190, 90), r=1.4)


# ================================================================ MAGIC
def gem(cv, o):
    cut = o.get("cut", "long")
    c = o.get("color", cv.theme)
    if cut == "long":
        pts = [(50, 10), (70, 30), (66, 70), (50, 90), (34, 70), (30, 30)]
    elif cut == "round":
        pts = [(50, 18), (72, 30), (80, 52), (66, 78), (34, 78), (20, 52), (28, 30)]
    else:  # shard
        pts = [(46, 8), (64, 28), (70, 78), (48, 92), (32, 60), (36, 26)]
    cv.part(M_poly(pts), "gem", color=c, spec=1.4)
    cx, cy = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    for i, p in enumerate(pts):
        if i % 2 == 0:
            cv.add((255, 255, 255), M_line([p, (cx, cy)], 0.35), 0.35)
    facet = [pts[0], pts[1], (cx, cy)]
    cv.add((255, 255, 255), M_poly(facet), 0.25)
    cv.add(lighten(c, 0.5), blur(M_ell(cx, cy, 8), 3), 0.8)
    if o.get("setting"):
        cv.part(M_poly([(pts[3][0] - 10, pts[3][1] - 6), (pts[3][0] + 10, pts[3][1] - 6), (pts[3][0], pts[3][1] + 4)]), o["setting"])


def crystal_cluster(cv, o):
    c = o.get("color", cv.theme)
    for x, y, h, a in ((34, 78, 34, -18), (66, 78, 30, 20), (50, 80, 56, 0)):
        pts = tf([(x - 6, y), (x - 6, y - h * 0.8), (x, y - h), (x + 6, y - h * 0.8), (x + 6, y)], ang=a, c=(x, y))
        cv.part(M_poly(pts), "gem", color=c, spec=1.3)
    cv.part(M_poly([(22, 78), (78, 78), (72, 88), (28, 88)]), "stone", tex=0.2)


def orb(cv, o):
    c = o.get("color", cv.theme)
    cv.part(M_poly([(34, 78), (66, 78), (72, 90), (28, 90)]), o.get("stand", "gold"))
    for s in (-1, 1):
        cv.part(M_poly(bezier((50 + s * 14, 80), (50 + s * 30, 60), (50 + s * 20, 36), 12) +
                       bezier((50 + s * 18, 38), (50 + s * 26, 60), (50 + s * 12, 80), 12)), o.get("stand", "gold"))
    cv.part(M_ell(50, 46, 24), "gem", color=c, spec=1.0, bevel=0.6)
    cv.add(lighten(c, 0.6), blur(M_ell(50, 48, 12), 4), 1.0)
    cv.add((255, 255, 255), blur(M_ell(42, 36, 5, 3.5), 1.2), 0.8)
    if o.get("inner") == "swirl":
        fx_swirl(cv, 50, 46, 16, lighten(c, 0.5))
    elif o.get("inner") == "skull":
        cv.add((0, 0, 0), M_ell(50, 44, 7, 8), 0.4)
    elif o.get("inner") == "flame":
        fx_flames(cv, 60, 38, 62, 22, cv.rng, n=4, color=lighten(c, 0.2))


def tome(cv, o):
    cv.part(M_poly([(22, 22), (74, 16), (80, 80), (28, 86)]), "leather", color=o.get("cover"), tex=0.2)
    cv.part(M_poly([(74, 16), (80, 20), (84, 82), (80, 80)]), "bone")
    cv.part(M_poly([(28, 86), (80, 80), (84, 82), (32, 90)]), "bone")
    for p in ([(22, 22), (32, 21), (30, 32)], [(28, 86), (38, 85), (29, 76)], [(74, 16), (64, 17), (74, 26)], [(80, 80), (70, 81), (79, 71)]):
        cv.part(M_poly(p), "gold")
    cv.part(M_poly([(40, 36), (62, 33), (66, 64), (43, 68)]), o.get("plate", "gold"))
    sym = o.get("symbol", "rune")
    if sym == "snow":
        fx_snow(cv, 53, 50, 11)
    elif sym == "flame":
        fx_flames(cv, 62, 44, 62, 24, cv.rng, n=3)
    else:
        cv.part(M_ell(53, 50, 6), "gem", color=o.get("gem", cv.theme))


def staff(cv, o):
    A = o.get("ang", 30)
    T = lambda p: tf(p, ang=A)
    cv.part(M_poly(T([(48.8, 30), (51.2, 30), (52, 96), (48, 96)])), "wood", tex=0.3)
    claws = [bezier((50, 34), (36, 26), (40, 10), 10), bezier((50, 34), (64, 26), (60, 10), 10)]
    for c in claws:
        cv.part(M_line(T(c), 2.4), o.get("metal", "gold"))
    cv.part(M_ell(*T([(50, 20)])[0], 8), "gem", color=o.get("gem", cv.theme))
    cv.add(lighten(o.get("gem", cv.theme), 0.4), blur(M_ell(*T([(50, 20)])[0], 10), 4), 0.9)
    if o.get("fire"):
        x, y = T([(50, 20)])[0]
        fx_flames(cv, y + 4, x - 10, x + 10, 22, cv.rng, n=4)


def crown(cv, o):
    pts = [(18, 70), (18, 38), (32, 52), (40, 26), (50, 46), (60, 26), (68, 52), (82, 38), (82, 70)]
    cv.part(M_poly(pts), o.get("mat", "silver"), color=o.get("tint"))
    cv.part(M_rect(16, 66, 84, 78, 2), o.get("mat", "silver"), color=o.get("tint"))
    for x in (30, 50, 70):
        cv.part(M_ell(x, 72, 3.2), "gem", color=o.get("gem", cv.theme))
    for x, y in ((40, 26), (60, 26), (18, 38), (82, 38)):
        cv.part(M_ell(x, y, 2.4), "gem", color=o.get("gem", cv.theme))
    if o.get("ice"):
        for x, h in ((26, 14), (50, 22), (74, 14)):
            cv.part(M_poly([(x - 4, 64), (x, 64 - h - 30), (x + 4, 64)]), "gem", color=(190, 230, 255), outline=0.6)


def lantern(cv, o):
    cv.part(M_ring(50, 14, 5, 2), "darksteel")
    cv.part(M_poly([(34, 20), (66, 20), (70, 28), (30, 28)]), "darksteel")
    cv.part(M_poly([(32, 76), (68, 76), (72, 86), (28, 86)]), "darksteel")
    glass = M_poly([(34, 28), (66, 28), (64, 76), (36, 76)])
    cv.part(glass, "glow", color=o.get("flame", cv.theme))
    cv.add(lighten(o.get("flame", cv.theme), 0.3), blur(M_ell(50, 52, 12, 16), 4), 1.2)
    fx_flames(cv, 66, 42, 58, 26, cv.rng, n=3, color=o.get("flame", cv.theme))
    for x in (34, 50, 66):
        cv.part(M_line([(x, 28), (x + (50 - x) * 0.05, 76)], 1.6), "darksteel")


def lens(cv, o):
    cv.part(M_line([(64, 64), (86, 88)], 5), "wood")
    cv.part(M_ring(44, 44, 24, 5), o.get("mat", "gold"))
    cv.part(M_ell(44, 44, 21.5), "glow", color=o.get("glass", cv.theme), bevel=0.3)
    cv.add((255, 255, 255), blur(M_ell(36, 36, 6, 4), 1.2), 0.6)
    if o.get("stars"):
        fx_sparkles(cv, cv.rng, n=5, area=(28, 28, 60, 60), size=(1.5, 3))


def eye(cv, o):
    c = o.get("iris", cv.theme)
    lid = bezier((12, 50), (50, 16), (88, 50), 24) + bezier((88, 50), (50, 84), (12, 50), 24)
    cv.part(M_poly(lid), o.get("mat", "gold"))
    cv.part(M_poly(tf(lid, s=0.86)), "bone", bevel=0.4)
    cv.part(M_ell(50, 50, 16), "gem", color=c, spec=0.8)
    cv.part(M_ell(50, 50, 5, 12) if o.get("slit") else M_ell(50, 50, 6), "dark", outline=0)
    cv.add((255, 255, 255), M_ell(44, 44, 3), 0.9)
    if o.get("storm"):
        fx_bolt(cv, (50, 10), (50, 28), cv.rng, color=lighten(c, 0.2), segs=4, jitter=3, branches=0)


def pendant(cv, o):
    cv.part(M_line(bezier((24, 8), (50, 44), (76, 8), 20), 1.1), o.get("chain", "gold"))
    shape = o.get("shape", "tear")
    if shape == "tear":
        p = bezier((50, 36), (26, 60), (50, 88), 18) + bezier((50, 88), (74, 60), (50, 36), 18)
    elif shape == "moon":
        p = arc_pts(50, 62, 24, 24, 60, 300, 40) + arc_pts(60, 58, 18, 18, 280, 80, 40)
    else:
        p = [(50, 36), (70, 60), (50, 88), (30, 60)]
    cv.part(M_poly(p), o.get("frame", "gold"))
    cv.part(M_poly(tf(p, s=0.72, c=(50, 62))), "gem", color=o.get("gem", cv.theme), spec=1.3)
    cv.part(M_ring(50, 34, 3, 1.6), o.get("frame", "gold"))


def ring(cv, o):
    cv.part(M_ring(50, 60, 24, 8), o.get("mat", "gold"))
    cv.part(M_poly([(38, 30), (62, 30), (66, 40), (34, 40)]), o.get("mat", "gold"))
    cv.part(M_poly([(40, 14), (60, 14), (66, 26), (50, 36), (34, 26)]), "gem", color=o.get("gem", cv.theme), spec=1.3)


def coin(cv, o):
    cv.part(M_ell(50, 50, 32), o.get("mat", "gold"))
    cv.part(M_ring(50, 50, 27, 2), o.get("mat", "gold"), bevel=1.6)
    sym = o.get("symbol", "skull")
    if sym == "skull":
        cv.part(U(M_ell(50, 46, 12, 11), M_rect(43, 50, 57, 62, 2)), "bone")
        for x in (45, 55):
            cv.part(M_ell(x, 47, 3, 3.5), "dark", outline=0, shadow=False)
    else:
        cv.part(M_poly([(50, 30), (56, 46), (72, 46), (59, 56), (64, 72), (50, 62), (36, 72), (41, 56), (28, 46), (44, 46)]), "bronze")


def gear(cv, o):
    teeth = []
    for k in range(10):
        a = math.radians(k * 36)
        teeth.append(M_poly(tf([(46, 12), (54, 12), (55, 22), (45, 22)], ang=k * 36)))
    cv.part(U(M_ell(50, 50, 30), *teeth), o.get("mat", "bronze"))
    cv.part(M_ell(50, 50, 18), "dark", outline=0.5)
    cv.part(M_ring(50, 50, 16, 2.4), "gold")
    for ang, l in ((-60, 12), (30, 8)):
        cv.part(M_poly(tf([(49, 50), (51, 50), (50.5, 50 - l), (49.5, 50 - l)], ang=ang)), "gold")
    cv.part(M_ell(50, 50, 2.4), "gem", color=o.get("gem", cv.theme))


def heart(cv, o):
    p = bezier((50, 86), (12, 58), (24, 24), 20) + bezier((24, 24), (40, 12), (50, 30), 12) + \
        bezier((50, 30), (60, 12), (76, 24), 12) + bezier((76, 24), (88, 58), (50, 86), 20)
    cv.part(M_poly(p), o.get("mat", "stone"), color=o.get("tint"), tex=0.25)
    if o.get("cracks", True):
        for q in ([(50, 32), (44, 46), (52, 56), (46, 72)], [(34, 40), (42, 50)], [(64, 38), (58, 52), (66, 62)]):
            cv.glowline(M_line(q, 0.8), o.get("glow", cv.theme), r=1.3)
    cv.add(lighten(o.get("glow", cv.theme), 0.3), blur(M_ell(50, 52, 8), 3), 0.8)


def core(cv, o):
    cv.part(M_ell(50, 50, 28), "stone", tex=0.3)
    for q in ([(30, 38), (44, 46), (40, 60)], [(56, 26), (54, 44), (68, 50)], [(62, 62), (50, 58), (46, 76)], [(40, 50), (58, 52)]):
        cv.glowline(M_line(q, 1.0), o.get("glow", cv.theme), r=1.6)
    cv.add(lighten(o.get("glow", cv.theme), 0.4), blur(M_ell(50, 50, 10), 4), 0.9)


def carapace(cv, o):
    p = bezier((20, 70), (16, 18), (50, 14), 20) + bezier((50, 14), (84, 18), (80, 70), 20) + [(50, 84)]
    cv.part(M_poly(p), o.get("mat", "darksteel"), color=o.get("tint"), tex=0.1)
    cv.add((0, 0, 0), M_line([(50, 16), (50, 82)], 1.0), 0.6)
    for y in (34, 50, 64):
        cv.add((0, 0, 0), M_line(bezier((22, y), (50, y + 8), (78, y), 12), 0.8), 0.5)
    for x, y in ((34, 26), (66, 26), (30, 44), (70, 44)):
        cv.part(M_poly([(x - 3, y + 3), (x, y - 8), (x + 3, y + 3)]), "bone")


def chain_broken(cv, o):
    for (x, y, a) in ((24, 76, 45), (36, 64, -45), (64, 36, -45), (76, 24, 45)):
        link = SUB(M_ell(x, y, 11, 6.5), M_ell(x, y, 7, 3))
        im = Image.fromarray((link * 255).astype(np.uint8)).rotate(a, center=(x * K, y * K), resample=Image.BICUBIC)
        cv.part(np.asarray(im, np.float32) / 255, o.get("mat", "steel"))
    # the snapped halves
    for (x, y, a) in ((47, 53, 45), (53, 47, 45)):
        half = SUB(M_ell(x, y, 8, 5), M_ell(x, y, 5, 2.2), M_rect(x - 2, y - 8, x + 2, y + 8) if x < 50 else M_rect(0, 0, 0, 0))
        im = Image.fromarray((half * 255).astype(np.uint8)).rotate(a, center=(x * K, y * K), resample=Image.BICUBIC)
        cv.part(np.asarray(im, np.float32) / 255, o.get("mat", "steel"))
    cv.add((255, 200, 120), blur(M_ell(50, 50, 6), 3), 1.0)
    fx_sparkles(cv, cv.rng, n=6, area=(38, 38, 62, 62), size=(1.5, 3.2), color=(255, 200, 120))


def brand(cv, o):
    """Flaming brand / greatsword with fire along the blade."""
    sword(cv, dict(o, wide=7, length=86, guard="bronze"))
    fx_flames(cv, 56, 34, 66, 30, cv.rng, n=5)


# ================================================================ SPECIAL
def war_banner(cv, o):
    cv.part(M_poly([(35, 8), (38, 8), (39, 92), (34, 92)]), "wood", tex=0.3)
    cv.part(M_poly([(38, 12)] + bezier((38, 12), (60, 8), (82, 16), 12) + [(76, 34), (82, 52)] + bezier((82, 52), (60, 46), (38, 50), 12)),
            "cloth", color=o.get("cloth", cv.theme), tex=0.1)
    cv.part(M_poly([(56, 22), (64, 30), (56, 42), (48, 30)]), "gold")
    cv.part(M_poly([(36.5, 2), (39, 8), (34, 8)]), "steel")
    for i, x in enumerate((50, 64, 78, 22)):
        y = 70 + (i % 2) * 4
        cv.part(U(M_ell(x, y - 8, 3.4), M_poly([(x - 5, y - 4), (x + 5, y - 4), (x + 6, y + 14), (x - 6, y + 14)])), "dark", outline=0.4)
        cv.part(M_line([(x + 5, y - 20), (x + 5, y + 12)], 0.9), "darksteel", outline=0.3)


def upgrade_emblem(cv, o):
    shield(cv, dict(kind="kite", emblem=None, mat="cloth", tint=cv.theme))
    for i in range(3):
        y = 64 - i * 13
        cv.part(M_poly([(34, y + 8), (50, y - 4), (66, y + 8), (66, y + 14), (50, y + 2), (34, y + 14)]), "gold")
