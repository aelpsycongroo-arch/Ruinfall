"""Item drawings (v2). Everything is in 0..100 space; `o` is the option dict from items.py."""
import math
from iconkit import *


def _T(o, ang=0, s=1.0, off=(0, 0)):
    A, sc, of = o.get("ang", ang), o.get("s", s), o.get("off", off)
    return lambda p: tf(p, ang=A, s=sc, off=of)


def rivets(cv, pts, r=0.7, mat="steel"):
    for x, y in pts:
        cv.part(M_ell(x, y, r), mat, round=r * 0.7, outline=0.6, shadow=0.2, rim=0.3)


# ====================================================================== FOOTWEAR
def boot(cv, o):
    """Side view, toe to the right.
    o.style: leather | plate | slipper | greave     o.leather: colour     o.trim: metal
    o.metal: tint for plates"""
    st = o.get("style", "leather")
    trim = o.get("trim", "gold")
    lc = o.get("leather") or mix(cv.theme, (90, 52, 28), 0.45)
    T = _T(o, ang=-7, s=0.92, off=(0, 3))
    dark_l = darken(lc, 0.45)

    if st == "slipper":
        body = bez((30, 44), (44, 40), (58, 48), n=10) + bez((58, 48), (70, 62), (86, 60), n=12) + \
            bez((86, 60), (95, 58), (97, 48), n=8) + bez((97, 48), (101, 66), (88, 80), n=10) + \
            [(32, 82)] + bez((32, 82), (25, 66), (30, 44), n=10)
        cv.part(M_poly(T(body)), "leather", color=lc, round=3.0, tex=0.1)
        cv.part(M_poly(T([(26, 80), (90, 78), (91, 83), (27, 86)])), "dark", round=0.8)
        # embroidered collar + vamp band
        collar = bez((29, 43), (44, 38), (59, 47), n=14)
        cv.part(M_line(T(collar), 2.6), trim, round=0.9, shadow=0.2)
        vamp = bez((52, 52), (60, 70), (80, 66), n=14)
        cv.part(M_line(T(vamp), 1.8), trim, round=0.7, shadow=0.2)
        for t in (0.2, 0.5, 0.8):
            x, y = T([vamp[int(t * 14)]])[0]
            cv.gem(x, y, 1.1, lighten(cv.theme, 0.3))
        cv.stitches(T(bez((33, 78), (60, 76), (88, 76), n=14)), every=2.0)
        x, y = T([(97, 48)])[0]
        cv.gem(x, y, 2.0, lighten(cv.theme, 0.2))
        # ankle ribbon wrap
        for y0 in (50, 58):
            cv.part(M_line(T(bez((28, y0 + 6), (38, y0 - 2), (50, y0 + 2), n=10)), 1.4), "cloth",
                    color=lighten(lc, 0.2), round=0.6, shadow=0.2)
        return

    # --- tall boot silhouette -------------------------------------------------
    top = 10
    body = bez((31, top), (39, 34), (36, 56), n=14) + bez((36, 56), (28, 67), (30, 80), n=10) + [(84, 81)] + \
        bez((84, 81), (97, 77), (92, 69), n=8) + bez((92, 69), (82, 62), (66, 58), n=12) + \
        bez((66, 58), (58, 50), (58.5, 38), n=10) + bez((58.5, 38), (58, 22), (64, top), n=10)
    cv.part(M_poly(T(body)), "leather" if st in ("leather", "greave") else "darksteel",
            color=lc if st in ("leather", "greave") else o.get("metal"), round=3.2, tex=0.12)
    # sole, welt and stacked heel
    cv.part(M_poly(T([(27, 78), (88, 78)] + bez((88, 78), (95, 79), (92, 84), n=6) + [(28, 85)])), "dark", round=0.9)
    cv.part(M_poly(T([(27, 79), (42, 79), (41, 91), (29, 91)])), "dark", round=1.0)
    cv.engrave(T([(29, 86), (41, 86)]), 0.3, 0.5)
    cv.stitches(T([(31, 79.5), (86, 79.5)]), every=1.8, color=lighten(lc, 0.5))

    if st in ("leather", "greave"):
        # ankle creases
        for i in range(3):
            y = 58 + i * 3
            cv.engrave(T(bez((36, y), (46, y + 2 - i), (58, y - 1), n=10)), 0.3, 0.45)
        # laces up the shin
        if st == "leather":
            for i in range(6):
                y = 22 + i * 6
                a, b = (56.5, y), (61, y + 3)
                cv.part(M_line(T([a, b]), 0.9), "cloth", color=(230, 215, 185), round=0.4, shadow=0.1, outline=0.5)
                cv.part(M_line(T([(56.5, y + 3), (61, y)]), 0.9), "cloth", color=(210, 195, 165), round=0.4, shadow=0.1, outline=0.5)
            rivets(cv, T([(56, 22 + i * 6) for i in range(7)]), r=0.55, mat=trim)
        # side strap + buckle over the ankle
        strap = [(33, 49), (61, 45), (62, 50), (34, 54)]
        cv.part(M_poly(T(strap)), "leather", color=dark_l, round=0.9)
        cv.stitches(T([(34, 50), (60, 46)]), every=1.6)
        bx, by = T([(47, 49.5)])[0]
        cv.part(M_ring(bx, by, 2.4, 1.0, ry=2.0), trim, round=0.5, shadow=0.2)
        # folded cuff
        cuff = [(27, top - 5), (70, top - 7)] + bez((70, top - 7), (66, top + 6), (63, top + 14), n=8) + \
            bez((63, top + 14), (48, top + 10), (33, top + 15), n=8) + [(31, top + 2)]
        cv.part(M_poly(T(cuff)), "leather", color=darken(lc, 0.2), tex=0.15)
        # opening seen from slightly above: dark interior, then the front lip in trim metal
        ox, oy = T([(48.5, top - 6)])[0]
        cv.over((8, 5, 5), M_ell(ox, oy, 20.5, 2.4, ang=-9))
        lip = tf(arc_pts(48.5, top - 6, 21.2, 2.8, 0, 180, 30), ang=-7, s=0.92, off=(0, 3))
        lip = [tf([p], ang=-9 + 7, c=(ox, oy))[0] for p in lip]
        cv.part(M_line(lip, 1.5), trim, round=0.6, shadow=0.15, outline=0.6)
        cv.stitches(T(bez((33, top + 12), (48, top + 7), (62, top + 11), n=10)), every=1.8)
        rivets(cv, T([(36, top + 1), (48, top), (60, top - 1)]), r=0.8, mat=trim)
        # toe cap
        cap = bez((70, 63), (86, 63), (93, 72), n=10) + [(91, 78), (72, 78)] + bez((72, 78), (68, 70), (70, 63), n=6)
        cv.part(M_poly(T(cap)), trim if trim != "darksteel" else "steel", round=1.6, streak=0.08)
        cv.engrave(T(bez((72, 66), (84, 66), (90, 73), n=8)), 0.3, 0.4)
        rivets(cv, T([(75, 76), (80, 76), (85, 76)]), r=0.55, mat="darksteel")

    if st == "greave":
        # shin greave over the leather
        g = bez((38, top + 16), (50, top + 12), (61, top + 15), n=10) + [(62, 54)] + \
            bez((62, 54), (50, 59), (40, 56), n=10)
        cv.part(M_poly(T(g)), "steel", color=o.get("metal"), round=3.0, streak=0.1)
        cv.engrave(T([(50, top + 16), (50, 55)]), 0.35, 0.6)
        for y in (top + 24, top + 34):
            cv.engrave(T(bez((40, y), (50, y - 2), (60, y), n=8)), 0.3, 0.5)
        rivets(cv, T([(41, top + 18), (59, top + 18), (41, 52), (60, 52)]), r=0.7, mat=trim)
        # knee cop with a fan wing
        kx, ky = T([(49, top + 9)])[0]
        cv.part(M_ell(kx, ky, 8, 6.5), "steel", color=o.get("metal"), round=2.2)
        cv.part(M_ring(kx, ky, 3.2, 1.2), trim, round=0.5)
        cv.gem(kx, ky, 1.8, lighten(cv.theme, 0.25))

    if st == "plate":
        # articulated lames down the shin
        for i, y in enumerate((top + 2, top + 13, top + 24, top + 35)):
            lame = bez((31, y + 2), (47, y - 2), (63, y), n=10) + [(62.5, y + 12)] + bez((62.5, y + 12), (47, y + 9), (32, y + 14), n=10)
            cv.part(M_poly(T(lame)), "steel", color=o.get("metal"), round=2.0, streak=0.12)
            cv.part(M_line(T(bez((31.5, y + 2.5), (47, y - 1.5), (62.8, y + 0.5), n=10)), 0.9), trim, round=0.4, shadow=0.15)
            rivets(cv, T([(34, y + 5), (60, y + 3)]), r=0.6, mat=trim)
        # pointed sabaton over the foot
        for i, x in enumerate((60, 68, 76)):
            sab = [(x - 2, 56 + i * 2), (x + 9, 59 + i * 2.5)] + bez((x + 9, 59 + i * 2.5), (x + 13, 68), (x + 12, 78), n=6) + [(x - 2, 78)]
            cv.part(M_poly(T(sab)), "steel", color=o.get("metal"), round=1.8, streak=0.1)
        tip = bez((84, 64), (95, 70), (96, 78), n=8) + [(84, 78)]
        cv.part(M_poly(T(tip)), "steel", color=o.get("metal"), round=1.5)
        cv.part(M_poly(T([(33, 46), (60, 44), (60, 56), (34, 60)])), "leather", color=dark_l, round=1.0)
        cv.stitches(T([(35, 50), (58, 48.5)]), every=1.5)


# ====================================================================== BLADES
def sword(cv, o):
    """Straight blade with a diamond cross-section (lit / shadow halves).
    o: ang, length, wide, blade, tint, guard, gem, edgeglow, serrated, curved, rapier, off, s"""
    Lb = o.get("length", 70)
    w = o.get("wide", 5.4)
    T = _T(o, ang=45, s=1.0)
    tip = 50 - (Lb + 22) / 2 + 2
    base = tip + Lb
    bm = o.get("blade", "steel")
    tint = o.get("tint")
    if o.get("curved"):
        left = bez((50, tip), (50 - w * 0.2, tip + Lb * 0.4), (50 - w, base), n=16)
        right = bez((50, tip), (50 + w * 2.4, tip + Lb * 0.35), (50 + w, base), n=16)
    else:
        left = [(50, tip), (50 - w, tip + w * 2.2), (50 - w * 0.8, base)]
        right = [(50, tip), (50 + w, tip + w * 2.2), (50 + w * 0.8, base)]
        if o.get("serrated"):
            r = [(50, tip), (50 + w, tip + w * 2.2)]
            n = 7
            for i in range(n):
                y = tip + w * 2.2 + i * (base - tip - w * 2.4) / n
                r += [(50 + w * 1.55, y + 1.2), (50 + w * 0.95, y + 3)]
            right = r + [(50 + w * 0.8, base)]
    ridge = [(50, tip), (50, base)]
    lh = left + ridge[::-1]
    rh = ridge + right[::-1]
    cv.part(M_poly(T(lh)), bm, color=tint, round=0.8, streak=0.15, outline=0.7, flat=0.3)
    cv.part(M_poly(T(rh)), bm, color=darken(tint or (160, 170, 185), 0.35) if bm == "steel" else tint,
            round=0.8, streak=0.15, outline=0.7, flat=0.5)
    cv.add((255, 255, 255), M_line(T([(50, tip + 3), (50, base - 2)]), 0.35), 0.55)
    if not o.get("rapier"):
        cv.engrave(T([(50 - w * 0.35, tip + w * 3), (50 - w * 0.35, base - 4)]), 0.3, 0.35)
    if o.get("edgeglow"):
        cv.glow(M_line(T(right), 0.35), o["edgeglow"], k=0.9, r=1.0)
        cv.glow(M_line(T(left), 0.25), o["edgeglow"], k=0.5, r=0.8)
    # crossguard
    gm = o.get("guard", "gold")
    gy = base
    if o.get("rapier"):
        cv.part(M_line(T(bez((50 - 10, gy + 2), (50, gy - 3), (50 + 10, gy + 2), n=12)), 1.4), gm, round=0.6)
        cv.part(M_ring(*T([(50, gy + 6)])[0], 5.5, 0.9), gm, round=0.4)
    else:
        guard = bez((50 - 15, gy - 2.5), (50 - 8, gy + 1), (50, gy + 0.5), n=10) + bez((50, gy + 0.5), (50 + 8, gy + 1), (50 + 15, gy - 2.5), n=10) + \
            [(50 + 15.5, gy + 0.5)] + bez((50 + 14, gy + 1.5), (50 + 6, gy + 4.5), (50, gy + 4), n=10) + bez((50, gy + 4), (50 - 6, gy + 4.5), (50 - 14, gy + 1.5), n=10) + [(50 - 15.5, gy + 0.5)]
        cv.part(M_poly(T(guard)), gm, round=1.2)
        for sx in (-1, 1):
            cv.part(M_ell(*T([(50 + sx * 15.3, gy - 1)])[0], 1.3), gm, round=0.8)
    # grip (wrapped) + pommel
    grip = [(48.4, gy + 4), (51.6, gy + 4), (51.8, gy + 17), (48.2, gy + 17)]
    cv.part(M_poly(T(grip)), "leather", color=o.get("grip", (70, 38, 22)), round=1.0)
    for i in range(6):
        y = gy + 5 + i * 2
        cv.engrave(T([(48.3, y), (51.7, y + 1.3)]), 0.3, 0.6)
    cv.part(M_poly(T([(47.5, gy + 16.5), (52.5, gy + 16.5), (52, gy + 18.5), (48, gy + 18.5)])), gm, round=0.5)
    px, py = T([(50, gy + 20.5)])[0]
    cv.part(M_ell(px, py, 2.6), gm, round=1.2)
    if o.get("gem"):
        cv.gem(*T([(50, gy + 1.8)])[0], 1.7, o["gem"])
        cv.gem(px, py, 1.4, o["gem"])


def dagger(cv, o):
    o = dict(o)
    o.setdefault("length", 50)
    o.setdefault("wide", 5.0)
    o.setdefault("s", 1.15)
    sword(cv, o)


def twin_daggers(cv, o):
    sword(cv, dict(o, ang=-40, length=50, wide=4.6, s=1.08, off=(-5, 3)))
    sword(cv, dict(o, ang=40, length=50, wide=4.6, s=1.08, off=(5, 3)))


def axe(cv, o):
    T = _T(o, ang=28)
    hm = o.get("haft", "wood")
    cv.part(M_poly(T([(48.6, 10), (51.4, 10), (52, 94), (48, 94)])), hm, round=1.0, tex=0.2)
    for y in (70, 76, 82):
        cv.part(M_poly(T([(47.6, y), (52.4, y), (52.5, y + 4), (47.5, y + 4)])), "leather", color=(70, 40, 22), round=0.6)
    cv.part(M_ell(*T([(50, 95)])[0], 2.4), o.get("trim", "gold"), round=1.0)
    head = bez((53, 21), (64, 21), (78, 6), n=14) + bez((78, 6), (96, 28), (80, 58), n=18) + bez((80, 58), (66, 44), (53, 42), n=14)
    heads = [head] + ([mirror_x(head)] if o.get("double", True) else [])
    for h in heads:
        cv.part(M_poly(T(h)), o.get("head", "steel"), color=o.get("tint"), round=2.0, streak=0.12)
        edge = ribbon(h[14:33], lambda t: 1.6 * math.sin(math.pi * t) + 0.3)
        cv.part(M_poly(T(edge)), "silver", round=0.6, outline=0.3, shadow=0)
        if o.get("edgeglow"):
            cv.glow(M_line(T(h[14:33]), 0.4), o["edgeglow"], k=0.9, r=1.1)
    cv.part(M_poly(T([(45.5, 16), (54.5, 16), (55.5, 46), (44.5, 46)])), "darksteel", round=1.4)
    rivets(cv, T([(50, 21), (50, 41)]), r=0.9, mat=o.get("trim", "gold"))
    cv.part(M_poly(T([(50, 3), (53, 16), (47, 16)])), o.get("head", "steel"), color=o.get("tint"), round=0.8)
    if o.get("gem"):
        cv.gem(*T([(50, 31)])[0], 3.0, o["gem"])


def cleaver(cv, o):
    T = _T(o, ang=32)
    cv.part(M_poly(T([(48.5, 50), (51.5, 50), (52, 94), (48, 94)])), "wood", round=1.0, tex=0.25)
    for y in (66, 72, 78, 84):
        cv.part(M_poly(T([(47.6, y), (52.4, y), (52.5, y + 3.5), (47.5, y + 3.5)])), "leather", color=(60, 30, 20), round=0.5)
    blade = [(40, 8), (72, 12)] + bez((72, 12), (84, 26), (76, 52), n=14) + [(52, 56), (44, 50)]
    cv.part(M_poly(T(blade)), "steel", color=o.get("tint"), round=2.0, streak=0.15)
    edge = ribbon(bez((72, 12), (84, 26), (76, 52), n=14), lambda t: 1.4)
    cv.part(M_poly(T(edge)), "silver", round=0.6, outline=0.2, shadow=0)
    if o.get("edgeglow"):
        cv.glow(M_line(T(bez((73, 12), (85, 26), (77, 52), n=14)), 0.45), o["edgeglow"], r=1.2)
    cv.part(M_ell(*T([(50, 20)])[0], 3.5), "dark", round=1.0)
    cv.part(M_ring(*T([(50, 20)])[0], 3.5, 0.9), "gold", round=0.4)
    for p in ([(46, 30), (64, 28)], [(46, 38), (66, 36)]):
        cv.engrave(T(p), 0.35, 0.5)
    cv.part(M_poly(T([(44, 47), (56, 47), (57, 55), (43, 55)])), "gold", round=1.0)
    rivets(cv, T([(47, 51), (53, 51)]), r=0.6, mat="darksteel")


def hammer(cv, o):
    T = _T(o, ang=30)
    cv.part(M_poly(T([(48.6, 32), (51.4, 32), (52, 94), (48, 94)])), "wood", round=1.0, tex=0.2)
    for y in (72, 78, 84):
        cv.part(M_poly(T([(47.6, y), (52.4, y), (52.5, y + 3.5), (47.5, y + 3.5)])), "leather", color=(70, 38, 22), round=0.5)
    head = [(26, 16), (74, 16), (77, 20), (77, 36), (74, 40), (26, 40), (23, 36), (23, 20)]
    cv.part(M_poly(T(head)), o.get("head", "steel"), color=o.get("tint"), round=3.0, streak=0.12)
    for x in (23, 77):
        cv.part(M_poly(T([(x - 3 if x < 50 else x - 1, 19), (x + 1 if x < 50 else x + 3, 19), (x + 1 if x < 50 else x + 3, 37), (x - 3 if x < 50 else x - 1, 37)])), "darksteel", round=1.0)
    cv.part(M_poly(T([(41, 13), (59, 13), (60, 43), (40, 43)])), o.get("trim", "gold"), round=1.8)
    cv.engrave(T([(26, 28), (40, 28)]), 0.35, 0.5)
    cv.engrave(T([(60, 28), (74, 28)]), 0.35, 0.5)
    rivets(cv, T([(44, 17), (56, 17), (44, 39), (56, 39)]), r=0.7, mat="darksteel")
    if o.get("gem"):
        cv.gem(*T([(50, 28)])[0], 3.6, o["gem"])
    cv.part(M_ell(*T([(50, 95)])[0], 2.6), o.get("trim", "gold"), round=1.0)


def claw(cv, o):
    """Clawed gauntlet: three hooked blades over a leather bracer."""
    cv.part(M_poly([(16, 74), (44, 58), (56, 76), (28, 92)]), "leather", color=o.get("leather", (50, 32, 30)), round=2.5, tex=0.2)
    for y in (0, 1):
        cv.part(M_line([(20 + y * 8, 78 - y * 5), (34 + y * 8, 90 - y * 5)], 1.4), "darksteel", round=0.5)
    cv.part(M_poly([(38, 58), (54, 50), (64, 64), (48, 74)]), "darksteel", round=2.0)
    rivets(cv, [(47, 60), (54, 66)], r=0.8, mat="gold")
    for i, dx in enumerate((-9, 0, 9)):
        sp = bez((48 + dx * 0.7, 62 + i * 1.5), (58 + dx, 36 + dx * 0.4), (88 + dx * 0.25, 14 + i * 7), n=24)
        blade = ribbon(sp, lambda t: 2.4 * (1 - t) ** 0.8 + 0.1)
        cv.part(M_poly(blade), o.get("mat", "steel"), color=o.get("tint"), round=0.9, streak=0.1)
        if o.get("edgeglow"):
            cv.glow(M_line(sp[6:], 0.3), o["edgeglow"], k=0.8, r=0.9)


def fang(cv, o):
    sp = bez((46, 18), (40, 52), (60, 90), n=28)
    cv.part(M_poly(ribbon(sp, lambda t: 9 * (1 - t) ** 0.9 + 0.2)), "bone", round=3.5, tex=0.08)
    for t in (0.35, 0.55):
        x, y = sp[int(28 * t)]
        cv.engrave([(x - 5 * (1 - t), y - 1), (x + 4 * (1 - t), y + 1)], 0.3, 0.35)
    cv.part(M_poly([(33, 10), (60, 10), (58, 22), (35, 22)]), "gold", round=1.6)
    cv.part(M_line([(33, 16), (60, 16)], 0.8), "darksteel", round=0.3, shadow=0)
    cv.part(M_ring(46.5, 7, 3, 1.2), "gold", round=0.5)
    if o.get("gem"):
        cv.gem(46.5, 16, 2.6, o["gem"])


def talon(cv, o):
    sp = bez((30, 38), (60, 6), (86, 62), n=30)
    cv.part(M_poly(ribbon(sp, lambda t: 6.5 * (1 - t) ** 0.9 + 0.15)), o.get("mat", "darksteel"), color=o.get("tint"), round=1.6, streak=0.1)
    cv.part(M_poly(ribbon(sp[4:], lambda t: 1.0 * (1 - t) + 0.1)), "silver", round=0.4, outline=0.2, shadow=0)
    if o.get("edgeglow"):
        cv.glow(M_line(sp[8:], 0.35), o["edgeglow"], k=0.9, r=1.0)
    cv.part(M_poly([(14, 34), (34, 26), (40, 50), (20, 58)]), "gold", round=2.0)
    cv.part(M_line([(16, 40), (36, 33)], 0.8), "darksteel", round=0.3, shadow=0)
    cv.part(M_line([(18, 50), (38, 43)], 0.8), "darksteel", round=0.3, shadow=0)
    cv.gem(27, 42, 3.0, o.get("gem", cv.theme))
    cv.part(M_line(bez((16, 56), (8, 72), (18, 84), n=12), 1.2), "leather", color=(60, 40, 30), round=0.5)


# ====================================================================== RANGED
def bow(cv, o):
    A = o.get("ang", 22)
    T = _T(o, ang=22)
    mat = o.get("mat", "wood")
    # grip at x=68, limbs sweep back to recurved tips at x~52, string at x=50
    up = bez((68, 50), (72, 34), (64, 16), (52, 7), n=24)
    tip_u = bez((52, 7), (48, 5), (47, 9), n=6)
    lo = [(x, 100 - y) for x, y in up]
    tip_l = [(x, 100 - y) for x, y in tip_u]
    for limb, tip in ((up, tip_u), (lo, tip_l)):
        cv.part(M_poly(T(ribbon(limb, lambda t: 2.4 * (1 - t) + 0.9))), mat, color=o.get("tint"), round=0.9, tex=0.15 if mat == "wood" else 0, streak=0.1 if mat != "wood" else 0)
        cv.part(M_poly(T(ribbon(tip, lambda t: 0.9))), o.get("trim", "gold"), round=0.4, outline=0.5)
        cv.part(M_poly(T(ribbon(limb[8:14], lambda t: 1.9))), o.get("trim", "gold"), round=0.5, shadow=0.1, outline=0.4)
    cv.add((235, 228, 210), M_line(T([(47.5, 9), (50, 50), (47.5, 91)]), 0.35), 0.95)
    cv.part(M_poly(T([(65, 43), (72, 43), (72, 57), (65, 57)])), "leather", color=(70, 38, 22), round=1.0)
    for y in (45, 48, 51, 54):
        cv.engrave(T([(65, y), (72, y + 1)]), 0.25, 0.6)
    if o.get("gem"):
        cv.gem(*T([(70, 39)])[0], 1.8, o["gem"])
    if o.get("arrow", True):
        L = o.get("arrow_len", 62)
        d = (math.cos(math.radians(A)), math.sin(math.radians(A)))
        arrow(cv, dict(ang=A + 90, length=L, glow=o.get("glow"), head=o.get("head", "steel"),
                       fletch=o.get("fletch", (190, 50, 45)), off=(d[0] * (L / 2 - 1), d[1] * (L / 2 - 1))))


def arrow(cv, o):
    L = o.get("length", 80)
    T = _T(o, ang=45)
    y0, y1 = 50 - L / 2, 50 + L / 2
    cv.part(M_poly(T([(49.45, y0 + 9), (50.55, y0 + 9), (50.55, y1), (49.45, y1)])), "wood", round=0.5, outline=0.6)
    head = [(50, y0), (53.4, y0 + 7), (51.2, y0 + 6.2), (51, y0 + 10), (49, y0 + 10), (48.8, y0 + 6.2), (46.6, y0 + 7)]
    cv.part(M_poly(T(head)), o.get("head", "steel"), round=0.8, streak=0.1)
    for sd in (-1, 1):
        f = [(50, y1 - 14), (50 + sd * 3.8, y1 - 10), (50 + sd * 4, y1 - 2), (50, y1 - 4)]
        cv.part(M_poly(T(f)), "cloth", color=o.get("fletch", (190, 50, 45)), round=0.8, outline=0.5)
        for i in range(3):
            cv.engrave(T([(50, y1 - 11 + i * 3), (50 + sd * 3.6, y1 - 9 + i * 3)]), 0.2, 0.4)
    cv.part(M_poly(T([(49.2, y1 - 1), (50.8, y1 - 1), (50.8, y1 + 1.5), (49.2, y1 + 1.5)])), "gold", round=0.3, shadow=0)
    if o.get("glow"):
        cv.glow(M_poly(T(head)), o["glow"], k=0.7, r=1.2)


def quiver(cv, o):
    T = _T(o, ang=-16, off=(2, 3))
    fl = o.get("fletch", lighten(cv.theme, 0.1))
    for dx, h in ((-7, 16), (0, 22), (7, 12), (3.5, 18)):
        x = 50 + dx
        cv.part(M_poly(T([(x - 0.6, 34), (x + 0.6, 34), (x + 0.6, 32 - h), (x - 0.6, 32 - h)])), "wood", round=0.4, outline=0.5)
        for sd in (-1, 1):
            cv.part(M_poly(T([(x, 29 - h), (x + sd * 3.4, 32 - h), (x + sd * 3.4, 41 - h), (x, 38 - h)])), "cloth", color=fl, round=0.7, outline=0.5)
        if o.get("glow"):
            cv.glow(M_line(T([(x, 29 - h), (x, 40 - h)]), 0.4), o["glow"], k=0.5, r=0.9)
    body = [(35, 30)] + bez((35, 30), (33, 60), (39, 92), n=12) + [(61, 92)] + bez((61, 92), (67, 60), (65, 30), n=12)
    cv.part(M_poly(T(body)), "leather", color=o.get("leather"), round=3.5, tex=0.15)
    cv.stitches(T(bez((37, 34), (35, 60), (41, 90), n=12)), every=2.0)
    cv.stitches(T(bez((63, 34), (65, 60), (59, 90), n=12)), every=2.0)
    cv.part(M_poly(T([(33, 27), (67, 27), (66, 35), (34, 35)])), o.get("trim", "gold"), round=1.4)
    cv.part(M_poly(T([(38, 86), (62, 86), (61, 93), (39, 93)])), o.get("trim", "gold"), round=1.2)
    for y in (50, 72):
        cv.part(M_poly(T([(34.5, y), (65.5, y), (65.5, y + 2.4), (34.5, y + 2.4)])), "leather", color=darken(o.get("leather") or cv.theme, 0.5), round=0.5)
    cx, cy = T([(50, 61)])[0]
    cv.part(M_ell(cx, cy, 5.2), o.get("trim", "gold"), round=1.5)
    cv.gem(cx, cy, 3.2, o.get("gem", lighten(cv.theme, 0.2)))
    cv.part(M_line(T(bez((65, 36), (84, 54), (62, 86), n=16)), 1.6), "leather", color=(60, 38, 25), round=0.5)


# ====================================================================== ARMOUR
def shield(cv, o):
    kind = o.get("kind", "kite")
    trim = o.get("trim", "gold")
    if kind == "round":
        cv.part(M_ell(50, 50, 38), trim, round=2.0)
        face = M_ell(50, 50, 34)
        cv.part(face, o.get("mat", "steel"), color=o.get("tint"), round=6.0, streak=0.08)
        for a in range(0, 360, 30):
            x, y = 50 + 36 * math.cos(math.radians(a)), 50 + 36 * math.sin(math.radians(a))
            cv.part(M_ell(x, y, 1.0), "darksteel", round=0.6, shadow=0.1)
        cx, cy = 50, 50
    else:
        outer = [(50, 8)] + bez((50, 8), (70, 14), (86, 12), n=10) + bez((86, 12), (88, 52), (50, 93), n=18) + \
            bez((50, 93), (12, 52), (14, 12), n=18) + bez((14, 12), (30, 14), (50, 8), n=10)
        cv.part(M_poly(outer), trim, round=2.2)
        inner = tf(outer, s=0.9, c=(50, 48))
        face = M_poly(inner)
        cv.part(face, o.get("mat", "steel"), color=o.get("tint"), round=6.0, streak=0.06 if o.get("mat", "steel") != "cloth" else 0, tex=0.06)
        rivets(cv, [(50, 11), (84, 15), (16, 15), (78, 50), (22, 50), (50, 88)], r=0.9, mat="darksteel")
        cx, cy = 50, 46
    em = o.get("emblem")
    if em == "sun":
        rays = []
        for k in range(16):
            a = math.radians(k * 22.5)
            l = 22 if k % 2 == 0 else 14
            rays.append(M_poly([(cx + 5 * math.cos(a + 0.2), cy + 5 * math.sin(a + 0.2)), (cx + l * math.cos(a), cy + l * math.sin(a)),
                                (cx + 5 * math.cos(a - 0.2), cy + 5 * math.sin(a - 0.2))]))
        cv.part(U(*rays), "gold", round=0.9)
        cv.part(M_ell(cx, cy, 8.5), "gold", round=2.0)
        cv.gem(cx, cy, 5.5, (255, 190, 60))
    elif em == "boss":
        cv.part(M_ell(cx, cy, 12), "steel", round=4.0)
        cv.part(M_ring(cx, cy, 12, 1.5), trim, round=0.6)
        for a in range(0, 360, 45):
            x, y = cx + 23 * math.cos(math.radians(a)), cy + 23 * math.sin(math.radians(a))
            cv.part(M_ell(x, y, 2.6), "darksteel", round=1.6)
        for r in (18, 28):
            cv.engrave(arc_pts(cx, cy, r, r, 0, 360, 60), 0.3, 0.4)
    elif em == "mirror":
        cv.part(M_ell(cx, cy, 16, 20), "silver", round=5.0, spec=1.6)
        cv.part(M_ring(cx, cy, 16, 1.6, ry=20), trim, round=0.6)
        cv.add((255, 255, 255), M_poly([(cx - 10, cy - 12), (cx - 5, cy - 15), (cx + 8, cy + 12), (cx + 3, cy + 15)]), 0.35)
    elif em == "frost":
        for k in range(6):
            a = math.radians(k * 60 - 90)
            p0, p1 = (cx, cy), (cx + 22 * math.cos(a), cy + 22 * math.sin(a))
            cv.part(M_line([p0, p1], 1.4), "silver", color=(190, 230, 255), round=0.5, shadow=0.2)
            for f in (0.45, 0.7):
                bx, by = cx + 22 * f * math.cos(a), cy + 22 * f * math.sin(a)
                for sd in (-1, 1):
                    b = a + sd * math.radians(40)
                    cv.part(M_line([(bx, by), (bx + 6 * math.cos(b), by + 6 * math.sin(b))], 1.0), "silver", color=(190, 230, 255), round=0.4, shadow=0.15)
        cv.gem(cx, cy, 4.5, (140, 210, 255))
    elif em == "blood":
        cv.part(M_poly(bez((cx, cy - 16), (cx - 12, cy + 2), (cx, cy + 12), n=14) + bez((cx, cy + 12), (cx + 12, cy + 2), (cx, cy - 16), n=14)), "gem", color=(200, 20, 30), round=3.0)
    elif em == "wall":
        for r in range(5):
            for c in range(4):
                x = 25 + c * 13 - (6 if r % 2 else 0)
                y = 22 + r * 11
                m = INT(M_rect(x, y, x + 12, y + 10, 1), face)
                cv.part(m, "stone", round=1.4, tex=0.2, shadow=0.2)
        cv.part(M_line([(50, 14), (50, 86)], 3), trim, round=1.0)
        cv.part(M_line([(22, 46), (78, 46)], 3), trim, round=1.0)
        cv.gem(50, 46, 3.5, lighten(cv.theme, 0.2))
    elif em == "chevrons":
        for i in range(3):
            y = 62 - i * 14
            cv.part(M_poly([(30, y + 8), (50, y - 6), (70, y + 8), (70, y + 15), (50, y + 1), (30, y + 15)]), "gold", round=1.3)


def chestplate(cv, o):
    mat, trim, tint = o.get("mat", "steel"), o.get("trim", "gold"), o.get("tint")
    torso = [(34, 20)] + bez((34, 20), (50, 28), (66, 20), n=10) + [(72, 30)] + bez((72, 30), (66, 52), (70, 72), n=12) + \
        bez((70, 72), (60, 88), (50, 90), n=8) + bez((50, 90), (40, 88), (30, 72), n=8) + bez((30, 72), (34, 52), (28, 30), n=12)
    tm = M_poly(torso)
    cv.part(tm, mat, color=tint, round=7.0, streak=0.1)
    if o.get("mail"):
        rings = [M_ring(x + (1.5 if (y // 3) % 2 else 0), y, 1.4, 0.55) for y in range(66, 90, 3) for x in range(30, 71, 3)]
        cv.part(INT(U(*rings), tm), "steel", round=0.5, outline=0.3, shadow=0.1, rim=0.4)
    cv.engrave([(50, 30), (50, 62)], 0.4, 0.6)
    for y in (64, 73):
        cv.engrave(bez((32, y), (50, y + 5), (68, y), n=10), 0.35, 0.55)
    for sd in (-1, 1):
        cv.engrave(bez((50 + sd * 5, 34), (50 + sd * 15, 40), (50 + sd * 16, 55), n=12), 0.3, 0.4)
    cv.part(M_poly([(34, 18)] + bez((34, 18), (50, 26), (66, 18), n=10) + [(64, 25)] + bez((64, 25), (50, 33), (36, 25), n=10)), trim, round=1.4)
    for sd in (-1, 1):
        cx = 50 + sd * 26
        p = bez((cx - sd * 8, 20), (cx + sd * 12, 13), (cx + sd * 15, 42), n=14) + [(cx - sd * 4, 34)]
        cv.part(M_poly(p), mat, color=tint, round=3.0, streak=0.1)
        cv.part(M_line(bez((cx - sd * 7, 22), (cx + sd * 10, 16), (cx + sd * 13, 39), n=14), 1.3), trim, round=0.5)
        rivets(cv, [(cx + sd * 4, 22), (cx + sd * 9, 30)], r=0.7, mat=trim)
    rivets(cv, [(33, 70), (67, 70), (40, 83), (60, 83)], r=0.7, mat=trim)
    if o.get("emblem"):
        cv.part(M_ell(50, 46, 7.5), trim, round=2.0)
        cv.gem(50, 46, 5, o["emblem"])


def gauntlet(cv, o):
    mat, tint, trim = o.get("mat", "steel"), o.get("tint"), o.get("trim", "gold")
    cv.part(M_poly([(30, 64), (64, 60), (70, 93), (32, 95)]), mat, color=tint, round=3.5, streak=0.1, tex=0.15 if mat == "stone" else 0)
    cv.part(M_poly([(28, 64), (65, 60), (66, 66), (29, 70)]), trim, round=1.0)
    for y in (74, 84):
        cv.engrave([(33, y), (67, y - 2)], 0.35, 0.5)
    cv.part(M_poly([(70, 52), (82, 38), (89, 44), (79, 62)]), mat, color=tint, round=2.2)
    for x, h in ((28, 26), (39, 31), (50, 31), (61, 27)):
        top = 36 - h
        for j in range(3):
            y0 = top + j * (h / 3)
            cv.part(M_rect(x + 0.3 * j, y0, x + 10 - 0.3 * j, y0 + h / 3 + 1.5, 3), mat, color=tint, round=1.6, streak=0.1, tex=0.15 if mat == "stone" else 0)
    cv.part(M_poly([(26, 36), (74, 34), (75, 64), (28, 66)]), mat, color=tint, round=5.0, streak=0.1, tex=0.15 if mat == "stone" else 0)
    cv.engrave([(28, 46), (74, 44)], 0.4, 0.5)
    rivets(cv, [(30, 39), (71, 37), (30, 61), (71, 59)], r=0.8, mat=trim)
    if o.get("spikes"):
        for x in (33, 44, 55, 66):
            cv.part(M_poly([(x - 2.8, 38), (x, 26), (x + 2.8, 38)]), "darksteel", round=0.8)
    if o.get("cracks"):
        for q in ([(35, 50), (42, 54), (40, 60)], [(58, 40), (55, 50), (63, 56)], [(46, 78), (52, 86)]):
            cv.glow(M_line(q, 0.5), o["cracks"], k=0.9, r=1.0)
    if o.get("gem"):
        cv.part(M_ell(51, 54, 6.5), trim, round=2.0)
        cv.gem(51, 54, 4.4, o["gem"])


def belt(cv, o):
    lc = o.get("leather") or (110, 75, 40)
    band = bez((6, 44), (50, 56), (94, 44), n=24) + bez((94, 62), (50, 74), (6, 62), n=24)
    cv.part(M_poly(band), "leather", color=lc, round=3.0, tex=0.15)
    cv.stitches(bez((8, 47), (50, 59), (92, 47), n=24), every=2.0)
    cv.stitches(bez((8, 59), (50, 71), (92, 59), n=24), every=2.0)
    for x in (14, 24, 76, 86):
        y = 53 + (3 if x in (24, 76) else 0) - (x in (14, 86)) * 1
        cv.part(M_ell(x, y + 1, 2.4), "steel", round=1.0)
    cv.part(M_rect(33, 36, 67, 76, 5), o.get("trim", "gold"), round=3.0)
    cv.part(M_rect(38, 41, 62, 71, 3), "darksteel", round=2.0)
    for a in range(0, 360, 45):
        rivets(cv, [(50 + 13 * math.cos(math.radians(a)) * 0.95, 56 + 13 * math.sin(math.radians(a)) * 1.15)], r=0.8, mat="gold")
    cv.gem(50, 56, 6.2, o.get("gem", cv.theme))


def cloak(cv, o):
    tint = o.get("tint")
    hood = bez((50, 8), (20, 12), (22, 50), n=16) + bez((22, 50), (16, 76), (10, 94), n=10) + [(90, 94)] + \
        bez((90, 94), (84, 76), (78, 50), n=10) + bez((78, 50), (80, 12), (50, 8), n=16)
    cv.part(M_poly(hood), "cloth", color=tint, round=6.0, tex=0.1)
    for x in (30, 42, 58, 70):
        cv.engrave(bez((x, 56), (x + (x - 50) * 0.1, 76), (x + (x - 50) * 0.25, 94), n=12), 0.5, 0.5)
    face = bez((50, 18), (33, 22), (34, 52), n=14) + bez((34, 52), (50, 64), (66, 52), n=14) + bez((66, 52), (67, 22), (50, 18), n=14)
    cv.over((2, 2, 4), M_poly(face))
    cv.over((2, 2, 4), blur(M_poly(face), 1.5) * 0.7)
    for x in (43.5, 56.5):
        cv.glow(M_ell(x, 40, 1.8, 0.9), o.get("eyes", lighten(cv.theme, 0.5)), r=1.0)
    cv.part(M_line(bez((34, 62), (50, 70), (66, 62), n=14), 1.2), "gold", round=0.5)
    cv.part(M_ell(50, 69, 4.2), "gold", round=1.4)
    cv.gem(50, 69, 2.8, o.get("gem", cv.theme))
    # frayed, fading hem
    cv.over((0, 0, 0), clamp01((YY - 86) / 10) * M_poly(hood) * 0.6)


def horn(cv, o):
    n = 32
    spine = bez((14, 16), (22, 84), (80, 74), n=n)
    shape = ribbon(spine, lambda t: 2.6 + 13 * t ** 1.5)
    cv.part(M_poly(shape), o.get("mat", "bone"), color=o.get("tint", (190, 160, 110)), tex=0.15)
    for t in (0.15, 0.42, 0.68):   # growth ridges
        i = int(n * t)
        cv.engrave([spine[i - 1], spine[i + 1]], 0.3, 0.3)
    for t in (0.3, 0.55, 0.8):
        i = int(n * t)
        w = 2.6 + 13 * t ** 1.5
        x, y = spine[i]
        x2, y2 = spine[i + 1]
        d = math.hypot(x2 - x, y2 - y)
        nx, ny = -(y2 - y) / d, (x2 - x) / d
        cv.part(M_line([(x + nx * (w + 0.8), y + ny * (w + 0.8)), (x - nx * (w + 0.8), y - ny * (w + 0.8))], 2.6, caps=False), "gold", round=0.9)
    ex, ey = spine[-1]
    cv.part(M_ell(ex + 1, ey, 5, 14.5), "gold", round=2.0)
    cv.part(M_ell(ex + 1.6, ey, 3.2, 11), "dark", round=2.0, outline=0, shadow=0)
    cv.part(M_ell(*spine[0], 2.8), "gold", round=1.0)
    cv.part(M_line(bez(spine[4], (46, 22), spine[24], n=16), 1.3), "leather", color=(80, 48, 26), round=0.5)
    if o.get("waves"):
        for r in (9, 15, 21):
            cv.glow(M_line(arc_pts(ex + 5, ey, r * 0.6, r, -65, 65, 20), 0.5), lighten(cv.theme, 0.35), k=0.7, r=1.0)


def drum(cv, o):
    for s_ in (1, -1):
        cv.part(M_line([(50 - s_ * 32, 8), (50 + s_ * 16, 48)], 2.4), "wood", round=0.9)
        cv.part(M_ell(50 - s_ * 32, 8, 3.2), "leather", color=(220, 200, 160), round=1.4)
    cv.part(M_rect(16, 40, 84, 84, 4), "wood", color=o.get("tint"), round=6.0, tex=0.15)
    for i in range(7):
        x = 18 + i * 9.8
        cv.part(M_line([(x, 44), (x + 9.8, 79)], 0.8), "cloth", color=(225, 205, 165), round=0.3, outline=0.4, shadow=0.1)
    cv.part(M_ell(50, 40, 34, 9.5), "leather", color=(225, 195, 155), round=3.0, tex=0.15, flat=0.3)
    cv.part(M_ring(50, 40, 34, 2.4, ry=9.5), "gold", round=0.9)
    cv.part(M_rect(15, 80, 85, 86, 2), "gold", round=1.2)
    rivets(cv, [(18 + i * 9.8, 83) for i in range(8)], r=0.6, mat="darksteel")
    if o.get("emblem"):
        cv.part(M_ell(50, 62, 7.5), "gold", round=2.0)
        cv.gem(50, 62, 5, o["emblem"])


def bell(cv, o):
    p = [(50, 16)] + bez((50, 16), (32, 18), (30, 52), n=14) + bez((30, 52), (27, 66), (18, 72), n=8) + [(82, 72)] + \
        bez((82, 72), (73, 66), (70, 52), n=8) + bez((70, 52), (68, 18), (50, 16), n=14)
    cv.part(M_poly(p), o.get("mat", "gold"), round=6.0, streak=0.08)
    for y in (30, 58):
        cv.engrave(bez((32, y), (50, y + 3), (68, y), n=12), 0.4, 0.5)
    cv.part(M_ring(50, 11, 4.5, 2), "darksteel", round=0.8)
    cv.part(M_rect(17, 70, 83, 76, 2.5), "bronze", round=1.4)
    cv.part(M_ell(50, 81, 4.5), "darksteel", round=2.0)
    cv.gem(50, 44, 4.0, o.get("gem", (120, 200, 255)))


def pouch(cv, o):
    lc = o.get("leather")
    cv.part(M_poly(bez((34, 36), (8, 70), (50, 90), n=18) + bez((50, 90), (92, 70), (66, 36), n=18)), "leather", color=lc, round=6.0, tex=0.2)
    cv.part(M_poly([(36, 28), (64, 28), (70, 38), (30, 38)]), "leather", color=darken(lc or cv.theme, 0.3), round=2.0)
    cv.part(M_rect(31, 36, 69, 40, 1), "gold", round=0.8)
    cv.stitches(bez((30, 60), (50, 70), (70, 60), n=12), every=1.8)


def bomb(cv, o):
    cv.part(M_ell(46, 60, 27), "darksteel", color=o.get("tint"), round=9.0)
    for a in range(0, 360, 40):
        cv.engrave(arc_pts(46, 60, 27 * abs(math.cos(math.radians(a))) + 0.01, 27, -90, 90, 20), 0.3, 0.25)
    cv.part(M_rect(39, 29, 53, 37, 1.5), "bronze", round=1.2)
    rivets(cv, [(41, 33), (51, 33)], r=0.6, mat="gold")
    cv.part(M_line(bez((46, 29), (48, 16), (60, 13), n=10), 1.3), "leather", color=(200, 180, 140), round=0.5)
    cv.glow(M_ell(61, 12.5, 1.6), (255, 190, 90), r=1.6)
    cv.add((255, 220, 150), blur(M_ell(61, 12, 4), 2), 0.8)


# ====================================================================== MAGIC
def gem_shape(cv, o):
    cut = o.get("cut", "long")
    c = o.get("color", cv.theme)
    if cut == "long":
        pts = [(50, 6), (68, 26), (64, 74), (50, 94), (36, 74), (32, 26)]
    elif cut == "round":
        pts = [(50, 18), (72, 30), (80, 52), (66, 78), (34, 78), (20, 52), (28, 30)]
    else:
        pts = [(44, 6), (64, 26), (72, 80), (48, 95), (30, 62), (34, 24)]
    m = M_poly(pts)
    cv.part(m, "gem", color=c, round=2.0, emissive=0.35)
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    inner = tf(pts, s=0.45, c=(cx, cy - 4))
    for i, p in enumerate(pts):   # facet lines to a table
        cv.add(lighten(c, 0.6), M_line([p, inner[i]], 0.35), 0.55)
    cv.add(lighten(c, 0.6), M_line(inner + [inner[0]], 0.35), 0.5)
    cv.add((255, 255, 255), M_poly([pts[0], pts[1], inner[1], inner[0]]), 0.28)
    cv.add((255, 255, 255), M_poly([pts[-1], pts[0], inner[0], inner[-1]]), 0.12)
    cv.over((0, 0, 0), M_poly([pts[2], pts[3], inner[3], inner[2]]) * 0.25)
    cv.add(lighten(c, 0.4), blur(M_ell(cx, cy, 10), 3), 0.7)
    if o.get("setting"):
        b = pts[3]
        cv.part(M_poly([(b[0] - 10, b[1] - 8), (b[0] + 10, b[1] - 8), (b[0], b[1] + 4)]), o["setting"], round=1.2)


def crystal_cluster(cv, o):
    c = o.get("color", cv.theme)
    cv.part(M_poly([(16, 80), (84, 80), (76, 92), (24, 92)]), "stone", round=2.5, tex=0.25)
    for x, y, h, a, w in ((30, 82, 36, -22, 6), (70, 82, 30, 24, 5.5), (40, 84, 22, -8, 5), (62, 84, 24, 10, 5), (50, 84, 64, 0, 8)):
        pts = tf([(x - w, y), (x - w, y - h * 0.8), (x, y - h), (x + w, y - h * 0.8), (x + w, y)], ang=a, c=(x, y))
        cv.part(M_poly(pts), "gem", color=c, round=1.2, emissive=0.3)
        cv.add((255, 255, 255), M_poly([pts[1], pts[2], ((pts[2][0] + pts[4][0]) / 2, (pts[2][1] + pts[4][1]) / 2), ((pts[0][0] + pts[4][0]) / 2, (pts[0][1] + pts[4][1]) / 2)]), 0.2)
        cv.add(lighten(c, 0.6), M_line([pts[2], ((pts[0][0] + pts[4][0]) / 2, y)], 0.3), 0.5)


def orb(cv, o):
    c = o.get("color", cv.theme)
    st = o.get("stand", "gold")
    cv.part(M_poly([(32, 80), (68, 80), (74, 92), (26, 92)]), st, round=2.0)
    for sd in (-1, 1):
        cv.part(M_poly(bez((50 + sd * 12, 82), (50 + sd * 32, 62), (50 + sd * 22, 34), n=12) + bez((50 + sd * 20, 36), (50 + sd * 27, 62), (50 + sd * 10, 82), n=12)), st, round=1.2)
    m = M_ell(50, 46, 25)
    cv.part(m, "gem", color=c, round=9.0, emissive=0.3, spec=0.8)
    cv.add(lighten(c, 0.5), blur(M_ell(50, 48, 13), 4), 1.0)
    inner = o.get("inner")
    if inner == "swirl":
        for k in range(3):
            pts = [(50 + (3 + 16 * t) * math.cos(t * 5 + k * 2.09), 46 + (3 + 16 * t) * math.sin(t * 5 + k * 2.09)) for t in [i / 40 for i in range(41)]]
            cv.glow(INT(M_line(pts, 0.6), m), lighten(c, 0.4), k=0.8, r=0.9)
    elif inner == "flame":
        from fx import flames
        flames(cv, 60, 38, 62, 26, n=4, color=lighten(c, 0.1), clip=m)
    elif inner == "skull":
        sk = U(M_ell(50, 43, 9, 8.5), M_rect(44, 46, 56, 56, 2.5))
        cv.add(lighten(c, 0.6), blur(sk, 0.6) * m, 0.5)
        for x in (46, 54):
            cv.over((10, 0, 20), M_ell(x, 44, 2.3, 2.8) * 0.8)
        cv.over((10, 0, 20), M_poly([(50, 48), (51.3, 51), (48.7, 51)]) * 0.8)
    cv.add((255, 255, 255), blur(M_ell(41, 35, 6, 3.6, ang=-35), 0.8), 0.75)
    cv.part(M_ring(50, 70, 13, 2, ry=3.5), st, round=0.7, shadow=0)


def tome(cv, o):
    cover = o.get("cover") or darken(cv.theme, 0.4)
    cv.part(M_poly([(22, 20), (72, 14), (78, 80), (28, 88)]), "leather", color=cover, round=3.0, tex=0.2)
    cv.part(M_poly([(72, 14), (79, 18), (84, 83), (78, 80)]), "bone", round=1.5, tex=0.2)
    for i in range(6):
        cv.engrave([(74 + i * 0.9, 18 + i * 0.6), (79.5 + i * 0.8, 82 + i * 0.2)], 0.2, 0.3)
    cv.part(M_poly([(28, 88), (78, 80), (84, 83), (32, 91)]), "bone", round=1.2)
    cv.part(M_poly([(22, 20), (29, 19), (35, 88), (28, 88)]), "leather", color=darken(cover, 0.3), round=1.4)
    for p in ([(22, 20), (33, 18.5), (31, 30), (23, 31)], [(28, 88), (39, 86.5), (37, 76), (27, 77)],
              [(72, 14), (61, 15.5), (63, 26), (73, 25)], [(78, 80), (67, 81.5), (66, 71), (77, 70)]):
        cv.part(M_poly(p), o.get("plate", "gold"), round=1.2)
    cv.part(M_poly([(38, 34), (64, 31), (68, 66), (41, 70)]), o.get("plate", "gold"), round=2.0)
    cv.part(M_poly([(41, 37), (61.5, 34.5), (65, 63.5), (43.5, 67)]), "leather", color=darken(cover, 0.5), round=1.0, shadow=0)
    sym = o.get("symbol", "gem")
    cx, cy = 53, 50.5
    if sym == "snow":
        for k in range(6):
            a = math.radians(k * 60 - 90)
            cv.glow(M_line([(cx, cy), (cx + 11 * math.cos(a), cy + 11 * math.sin(a))], 0.6), (170, 220, 255), k=0.8, r=0.8)
            bx, by = cx + 6.5 * math.cos(a), cy + 6.5 * math.sin(a)
            for sd in (-1, 1):
                b = a + sd * 0.7
                cv.glow(M_line([(bx, by), (bx + 3.5 * math.cos(b), by + 3.5 * math.sin(b))], 0.45), (170, 220, 255), k=0.7, r=0.7)
    elif sym == "flame":
        from fx import flames
        flames(cv, 64, 44, 62, 26, n=3)
    else:
        cv.gem(cx, cy, 5, o.get("gem", cv.theme))
    cv.part(M_poly([(78, 42), (88, 44), (88, 52), (78, 50)]), o.get("plate", "gold"), round=1.0)


def staff(cv, o):
    T = _T(o, ang=28)
    cv.part(M_poly(T([(48.7, 30), (51.3, 30), (52.2, 97), (47.8, 97)])), "wood", round=1.0, tex=0.25)
    for y in (46, 62):
        cv.part(M_poly(T([(47.8, y), (52.2, y), (52.4, y + 4), (47.6, y + 4)])), o.get("metal", "gold"), round=0.8)
    for sd in (-1, 1):
        c = bez((50, 34), (50 + sd * 14, 28), (50 + sd * 8, 10), (50 + sd * 1.5, 7), n=16)
        cv.part(M_poly(T(ribbon(c, lambda t: 1.6 * (1 - t) + 0.5))), o.get("metal", "gold"), round=0.7)
    gx, gy = T([(50, 21)])[0]
    cv.gem(gx, gy, 7.5, o.get("gem", cv.theme))
    cv.add(lighten(o.get("gem", cv.theme), 0.3), blur(M_ell(gx, gy, 10), 4), 0.9)


def crown(cv, o):
    mat = o.get("mat", "silver")
    pts = [(14, 72), (14, 40), (28, 54), (36, 24), (50, 46), (64, 24), (72, 54), (86, 40), (86, 72)]
    cv.part(M_poly(pts), mat, color=o.get("tint"), round=2.5, streak=0.1)
    cv.part(M_rect(12, 66, 88, 80, 2.5), mat, color=o.get("tint"), round=2.5)
    for x in (28, 50, 72):
        cv.part(M_ell(x, 73, 4.2), "gold", round=1.4)
        cv.gem(x, 73, 3, o.get("gem", cv.theme))
    for x, y in ((36, 24), (64, 24), (14, 40), (86, 40), (50, 46)):
        cv.gem(x, y, 2.4, o.get("gem", cv.theme))
    if o.get("ice"):
        for x, h, w in ((22, 18, 3), (36, 34, 3.6), (50, 26, 3.2), (64, 34, 3.6), (78, 18, 3)):
            cv.part(M_poly([(x - w, 64), (x, 64 - h - 22), (x + w, 64)]), "gem", color=(190, 230, 255), round=0.9, emissive=0.2)
        for i in range(9):
            x = 16 + i * 8.5
            cv.part(M_poly([(x - 1.5, 80), (x, 86 + (i % 3) * 2), (x + 1.5, 80)]), "gem", color=(190, 230, 255), round=0.4, emissive=0.2, shadow=0)


def lantern(cv, o):
    fl = o.get("flame", cv.theme)
    cv.part(M_ring(50, 11, 5, 1.8), "darksteel", round=0.7)
    cv.part(M_poly([(32, 18), (68, 18), (72, 28), (28, 28)]), "darksteel", round=1.8)
    cv.part(M_poly([(30, 76), (70, 76), (74, 88), (26, 88)]), "darksteel", round=1.8)
    glass = M_poly([(34, 28), (66, 28), (64, 76), (36, 76)])
    cv.part(glass, "energy", color=darken(fl, 0.3), round=4.0, rim=0.2)
    cv.add(lighten(fl, 0.2), blur(M_ell(50, 54, 12, 18), 4), 1.2)
    from fx import flames
    flames(cv, 68, 42, 58, 28, n=3, color=fl)
    for x in (34, 50, 66):
        cv.part(M_line([(x, 28), (x + (50 - x) * 0.06, 76)], 1.8), "darksteel", round=0.6)
    for y in (18, 88):
        rivets(cv, [(34, y - 2 if y < 50 else y - 6), (66, y - 2 if y < 50 else y - 6)], r=0.8, mat="gold")


def lens(cv, o):
    cv.part(M_poly(ribbon([(62, 62), (88, 90)], [2.6, 3.2])), "wood", round=1.2, tex=0.2)
    cv.part(M_rect(59, 57, 67, 65, 1) if False else M_poly(tf([(58, 60), (66, 60), (66, 66), (58, 66)], ang=45, c=(62, 63))), "gold", round=1.0)
    cv.part(M_ring(42, 42, 25, 5), o.get("mat", "gold"), round=1.6)
    for a in range(0, 360, 45):
        rivets(cv, [(42 + 25 * math.cos(math.radians(a)), 42 + 25 * math.sin(math.radians(a)))], r=0.8, mat="darksteel")
    glass = M_ell(42, 42, 22.5)
    cv.part(glass, "gem", color=o.get("glass", cv.theme), round=8.0, emissive=0.2, spec=0.6)
    if o.get("stars"):
        from fx import sparkles
        sparkles(cv, n=6, area=(26, 26, 58, 58), size=(1.2, 3.0), clip=glass)
    cv.add((255, 255, 255), blur(M_ell(34, 32, 7, 3.5, ang=-35), 0.8), 0.55)


def eye(cv, o):
    c = o.get("iris", cv.theme)
    lid = bez((8, 50), (50, 12), (92, 50), n=28) + bez((92, 50), (50, 88), (8, 50), n=28)
    cv.part(M_poly(lid), o.get("mat", "gold"), round=2.5, streak=0.08)
    inner = tf(lid, s=0.84)
    im = M_poly(inner)
    cv.part(im, "bone", round=4.0, rim=0.2)
    cv.over((60, 20, 10), blur(SUB(im, M_ell(50, 50, 30, 20)), 2) * 0.4)
    iris = M_ell(50, 50, 16)
    cv.part(iris, "gem", color=c, round=5.0, emissive=0.35, spec=0.4)
    for a in range(0, 360, 15):
        cv.add(lighten(c, 0.5), M_line([(50 + 7 * math.cos(math.radians(a)), 50 + 7 * math.sin(math.radians(a))),
                                         (50 + 15 * math.cos(math.radians(a)), 50 + 15 * math.sin(math.radians(a)))], 0.25), 0.4)
    cv.over((0, 0, 0), M_ell(50, 50, 4.2, 12.5) if o.get("slit") else M_ell(50, 50, 6.2))
    cv.add((255, 255, 255), M_ell(44, 44, 2.6, 2.0), 0.95)
    for i in range(7):   # lashes / flame-like crest
        a = math.radians(-160 + i * 23)
        x, y = 50 + 44 * math.cos(a) * 0.95, 50 + 38 * math.sin(a) * 0.9
        cv.part(M_poly([(x - 1.5, y + 1), (x + (x - 50) * 0.18, y - 7), (x + 1.5, y + 1)]), o.get("mat", "gold"), round=0.6)


def pendant(cv, o):
    ch = o.get("chain", "gold")
    links = [M_ring(x, y, 1.1, 0.55) for x, y in bez((20, 4), (50, 50), (80, 4), n=26)]
    cv.part(U(*links), ch, round=0.4, outline=0.4, shadow=0.1)
    shape = o.get("shape", "tear")
    if shape == "tear":
        p = bez((50, 34), (24, 60), (50, 90), n=18) + bez((50, 90), (76, 60), (50, 34), n=18)
    elif shape == "moon":
        p = arc_pts(50, 62, 25, 25, 60, 300, 40) + arc_pts(61, 58, 19, 19, 280, 80, 40)
    else:
        p = [(50, 34), (70, 60), (50, 90), (30, 60)]
    frame = o.get("frame", "gold")
    cv.part(M_poly(p), frame, round=2.0)
    inner = tf(p, s=0.74, c=(50, 62) if shape != "moon" else (46, 62))
    cv.part(M_poly(inner), "gem", color=o.get("gem", cv.theme), round=3.5, emissive=0.35)
    cv.add((255, 255, 255), blur(M_ell(44, 54, 3, 5, ang=20), 0.6), 0.7)
    cv.part(M_ring(50, 31, 3.2, 1.6), frame, round=0.6)
    for i in range(0, len(p), max(1, len(p) // 8)):
        rivets(cv, [p[i]], r=0.8, mat=frame)


def ring(cv, o):
    mat = o.get("mat", "gold")
    band = SUB(M_ell(50, 62, 27, 25), M_ell(50, 62, 19, 17))
    cv.part(band, mat, round=2.0, streak=0.1)
    for a in range(200, 340, 20):
        x, y = 50 + 23 * math.cos(math.radians(a + 180)), 62 + 21 * math.sin(math.radians(a + 180))
        cv.engrave([(x, y), (x + 1.4, y + 0.4)], 0.3, 0.4)
    for sd in (-1, 1):
        cv.part(M_poly([(50 + sd * 4, 42), (50 + sd * 16, 38), (50 + sd * 12, 28), (50 + sd * 3, 32)]), mat, round=1.2)
    gm = M_poly([(38, 22), (50, 10), (62, 22), (58, 34), (42, 34)])
    cv.part(gm, "gem", color=o.get("gem", cv.theme), round=2.5, emissive=0.35)
    cv.add((255, 255, 255), M_poly([(38, 22), (50, 10), (50, 20), (44, 23)]), 0.3)
    for x, y in ((39, 22), (61, 22), (43, 34), (57, 34)):
        cv.part(M_ell(x, y, 1.3), mat, round=0.6)


def coin(cv, o):
    mat = o.get("mat", "gold")
    cv.part(M_ell(50, 50, 33), mat, round=3.0)
    cv.part(M_ell(50, 50, 28), mat, round=10.0, flat=0.2)
    for a in range(0, 360, 10):
        x0, y0 = 50 + 30.5 * math.cos(math.radians(a)), 50 + 30.5 * math.sin(math.radians(a))
        cv.engrave([(x0, y0), (50 + 32.5 * math.cos(math.radians(a)), 50 + 32.5 * math.sin(math.radians(a)))], 0.3, 0.5)
    sk = U(M_ell(50, 45, 12.5, 11.5), M_rect(43, 49, 57, 63, 2.5))
    cv.part(sk, "bone", round=3.0)
    for x in (45, 55):
        cv.over((20, 10, 5), M_ell(x, 46, 3.2, 3.8))
    cv.over((20, 10, 5), M_poly([(50, 51), (51.5, 55), (48.5, 55)]))
    for x in (46, 50, 54):
        cv.engrave([(x, 58), (x, 62.5)], 0.4, 0.8)
    if o.get("eyes"):
        for x in (45, 55):
            cv.glow(M_ell(x, 46.5, 1.2), o["eyes"], r=0.8)


def gear(cv, o):
    mat = o.get("mat", "bronze")
    teeth = [M_poly(tf([(45.5, 11), (54.5, 11), (56, 22), (44, 22)], ang=k * 30)) for k in range(12)]
    body = SUB(U(M_ell(50, 50, 30), *teeth), M_ell(50, 50, 20))
    for k in range(6):
        body = SUB(body, M_ell(50 + 25 * math.cos(math.radians(k * 60)), 50 + 25 * math.sin(math.radians(k * 60)), 2.2))
    cv.part(body, mat, round=2.5, streak=0.1)
    face = M_ell(50, 50, 20)
    cv.part(face, "dark", round=4.0)
    for k in range(12):
        a = math.radians(k * 30 - 90)
        cv.add(lighten(o.get("gem", cv.theme), 0.3), M_line([(50 + 16 * math.cos(a), 50 + 16 * math.sin(a)), (50 + 18.5 * math.cos(a), 50 + 18.5 * math.sin(a))], 0.6), 0.9)
    cv.part(M_ring(50, 50, 20, 1.8), "gold", round=0.6)
    for ang, l, w in ((-60, 13, 1.3), (40, 9, 1.6)):
        cv.part(M_poly(tf([(49.2, 51), (50.8, 51), (50.3, 50 - l), (49.7, 50 - l)], ang=ang)), "gold", round=0.5, shadow=0.3)
    cv.gem(50, 50, 2.6, o.get("gem", cv.theme))


def golem_heart(cv, o):
    g = o.get("glow", cv.theme)
    p = bez((50, 88), (10, 60), (22, 22), n=20) + bez((22, 22), (38, 10), (50, 28), n=12) + \
        bez((50, 28), (62, 10), (78, 22), n=12) + bez((78, 22), (90, 60), (50, 88), n=20)
    hm = M_poly(p)
    cv.part(hm, "stone", round=7.0, tex=0.3)
    # carved rune plates
    for q in ([(30, 30), (40, 26), (42, 40), (32, 44)], [(60, 26), (70, 30), (68, 44), (58, 40)], [(40, 56), (60, 56), (56, 74), (44, 74)]):
        cv.part(INT(M_poly(q), hm), "stone", round=2.0, tex=0.3, shadow=0.35)
    for q in ([(50, 30), (45, 44), (52, 56), (47, 72)], [(34, 44), (44, 50)], [(66, 42), (58, 52), (64, 62)]):
        cv.glow(M_line(q, 0.7), g, k=1.0, r=1.2)
    cv.add(lighten(g, 0.3), blur(M_ell(50, 52, 9), 3), 0.9)
    cv.glow(M_ell(50, 52, 3.5), g, k=0.8, r=1.2)


def core(cv, o):
    g = o.get("glow", cv.theme)
    m = M_ell(50, 50, 28)
    cv.part(m, "stone", color=darken(g, 0.6), round=9.0, tex=0.35)
    for q in ([(28, 38), (40, 44), (38, 58), (26, 62)], [(54, 24), (52, 40), (66, 48), (76, 44)], [(62, 62), (50, 60), (46, 76)], [(40, 50), (56, 52), (62, 62)]):
        cv.glow(INT(M_line(q, 1.1), m), g, k=1.1, r=1.4)
    cv.add(lighten(g, 0.4), blur(M_ell(50, 50, 10), 4), 0.9)
    if o.get("cage"):
        for a in (0, 60, 120):
            cv.part(M_ring(50, 50, 30, 1.6, ry=30 * abs(math.cos(math.radians(a))) + 1) if a else M_ring(50, 50, 30, 1.6), "darksteel", round=0.6, shadow=0.2)
        cv.part(M_ring(50, 50, 30, 1.8, ry=8), "gold", round=0.6)


def carapace(cv, o):
    p = bez((18, 72), (12, 18), (50, 12), n=20) + bez((50, 12), (88, 18), (82, 72), n=20) + [(64, 88), (50, 84), (36, 88)]
    m = M_poly(p)
    cv.part(m, o.get("mat", "darksteel"), color=o.get("tint"), round=8.0, tex=0.12)
    cv.engrave([(50, 14), (50, 84)], 0.5, 0.7)
    for y in (32, 48, 62):
        cv.engrave(bez((20, y), (50, y + 9), (80, y), n=14), 0.45, 0.6)
    for x, y in ((32, 22), (68, 22), (26, 42), (74, 42), (30, 58), (70, 58)):
        cv.part(M_poly([(x - 3, y + 3.5), (x + (x - 50) * 0.08, y - 9), (x + 3, y + 3.5)]), "bone", round=0.9)
    for x, y in ((40, 38), (60, 38), (44, 58), (56, 58)):
        cv.glow(M_ell(x, y, 1.6), o.get("pustule", (160, 255, 90)), k=0.8, r=1.0)


def chain(cv, o):
    mat = o.get("mat", "steel")
    for (x, y, a) in ((20, 80, 45), (32, 68, -45), (68, 32, -45), (80, 20, 45)):
        link = SUB(M_ell(x, y, 11, 6.5), M_ell(x, y, 7, 3.2))
        cv.part(rotate_mask(link, a, c=(x, y)), mat, round=1.6, streak=0.1)
    for (x, y), cut in (((44, 56), (40, 50, 48, 62)), ((56, 44), (52, 38, 60, 50))):
        half = SUB(M_ell(x, y, 9, 5.5), M_ell(x, y, 5.5, 2.4))
        half = rotate_mask(half, 45 if x < 50 else 45, c=(x, y))
        half = SUB(half, M_ell(50, 50, 4.5))
        cv.part(half, mat, round=1.4, streak=0.1)
    cv.add((255, 210, 140), blur(M_ell(50, 50, 6), 3), 1.0)
    cv.glow(M_ell(50, 50, 1.3), (255, 230, 170), r=1.2)


def banner(cv, o):
    cloth = o.get("cloth", cv.theme)
    cv.part(M_poly([(33.5, 10), (36.5, 10), (37.5, 96), (32.5, 96)]), "wood", round=1.0, tex=0.25)
    flag = [(36, 14)] + bez((36, 14), (58, 8), (84, 16), n=14) + [(76, 34), (86, 52)] + bez((86, 52), (60, 46), (36, 52), n=14)
    cv.part(M_poly(flag), "cloth", color=cloth, round=4.0, tex=0.12)
    for y in (22, 34, 44):
        cv.engrave(bez((40, y), (58, y - 4), (78, y + 1), n=12), 0.35, 0.3)
    cv.part(M_line([(36, 14)] + bez((36, 14), (58, 8), (84, 16), n=14), 1.2), "gold", round=0.5, shadow=0.1)
    crest = [(58, 20), (66, 30), (58, 42), (50, 30)]
    cv.part(M_poly(crest), "gold", round=1.4)
    cv.part(M_poly(tf(crest, s=0.55, c=(58, 31))), "cloth", color=darken(cloth, 0.5), round=0.8, shadow=0)
    cv.part(M_poly([(35, 1), (38.5, 10), (31.5, 10)]), "steel", round=0.8)
    cv.part(M_ring(35, 12, 2.5, 1.2), "gold", round=0.5)


def warband(cv, o):
    """Banner raised over a line of warriors."""
    banner(cv, o)
    for i, (x, sc) in enumerate(((18, 0.9), (48, 1.0), (66, 0.95), (84, 0.88))):
        y = 76
        cv.part(M_line([(x + 5 * sc, y - 24), (x + 5 * sc, y + 16)], 0.8), "wood", round=0.3, shadow=0)
        cv.part(M_poly([(x + 5 * sc, y - 28), (x + 6.4 * sc, y - 23), (x + 3.6 * sc, y - 23)]), "steel", round=0.4, shadow=0)
        body = M_poly([(x - 6 * sc, y - 5 * sc), (x + 6 * sc, y - 5 * sc), (x + 7 * sc, y + 16), (x - 7 * sc, y + 16)])
        cv.part(body, "leather", color=darken(cv.theme, 0.45), shadow=0.2)
        helm = U(M_ell(x, y - 9 * sc, 3.6 * sc), M_poly([(x - 4 * sc, y - 9 * sc), (x, y - 16 * sc), (x + 4 * sc, y - 9 * sc)]))
        cv.part(helm, "steel", shadow=0.2)
        cv.part(M_ell(x - 2 * sc, y + 3, 5 * sc), "bronze", shadow=0.25)
        cv.part(M_ell(x - 2 * sc, y + 3, 1.5 * sc), "gold", shadow=0)
    cv.over((0, 0, 0), clamp01((YY - 80) / 14) * 0.8)


def upgrade(cv, o):
    shield(cv, dict(kind="kite", mat="cloth", tint=darken(cv.theme, 0.35), emblem="chevrons"))
