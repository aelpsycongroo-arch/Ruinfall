"""Icon catalog: item id -> (theme colour, shape, options, effects).
Theme colours match each item's `Color` in ItemDefinitions / ShopDefinitions so the
icons sit with the rest of the UI. Run render.py to produce PNGs in ./out."""
import math
from iconkit import *

# ---------------------------------------------------------------- effects
# "pre" effects are painted behind the item, "post" effects in front.


def fx_wind(cv, rng, color=None, side="left"):
    c = color or lighten(cv.theme, 0.5)
    for i in range(4):
        y = 30 + i * 12 + rng.uniform(-3, 3)
        x0 = rng.uniform(6, 14)
        pts = bezier((x0, y), (x0 + 14, y - 5), (x0 + 30, y + rng.uniform(-3, 3)), 16)
        cv.glowline(M_line(pts, 0.7), c, r=1.0, k=0.7)


def fx_shadow(cv, rng, color=None):
    c = color or darken(cv.theme, 0.2)
    for _ in range(9):
        x, y, r = rng.uniform(15, 85), rng.uniform(55, 92), rng.uniform(6, 14)
        cv.over(np.zeros((S, S, 3), np.float32) + rgb(darken(c, 0.6)), blur(M_ell(x, y, r), 3) * 0.55)
    for _ in range(3):
        x = rng.uniform(20, 80)
        cv.glowline(M_line(bezier((x, 92), (x + rng.uniform(-14, 14), 70), (x + rng.uniform(-8, 8), 52), 16), 0.6),
                    lighten(cv.theme, 0.3), r=1.2, k=0.6)


def fx_poison(cv, rng, color=(120, 230, 70)):
    for _ in range(5):
        x, y, r = rng.uniform(20, 80), rng.uniform(55, 90), rng.uniform(5, 10)
        cv.add(color, blur(M_ell(x, y, r), 3.5), 0.22)
    fx_drips(cv, rng, [(rng.uniform(40, 70), rng.uniform(60, 72)) for _ in range(2)], color=color)


def fx_blood(cv, rng):
    fx_drips(cv, rng, [(rng.uniform(38, 70), rng.uniform(58, 72)) for _ in range(2)], color=(200, 20, 30))


def fx_runes(cv, rng, color=None, cx=50, cy=50, r=40):
    c = color or lighten(cv.theme, 0.45)
    cv.glowline(M_ring(cx, cy, r, 0.5), c, r=0.8, k=0.35)
    for k in range(8):
        a = math.radians(k * 45 + 22)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        glyph = rng.choice([[(-2, -3), (0, 3), (2, -3)], [(-2, 0), (2, 0), (0, -3), (0, 3)], [(-2, -3), (2, -3), (-2, 3), (2, 3)]])
        cv.glowline(M_line([(x + dx, y + dy) for dx, dy in glyph], 0.5), c, r=0.8, k=0.7)


def fx_speed(cv, rng, color=None):
    c = color or lighten(cv.theme, 0.5)
    for i in range(5):
        y = 26 + i * 11 + rng.uniform(-2, 2)
        cv.glowline(M_line([(rng.uniform(4, 10), y), (rng.uniform(22, 32), y)], 0.6), c, r=0.9, k=0.6)


def fx_impact(cv, rng, color=None):
    c = color or lighten(cv.theme, 0.4)
    cv.add(c, blur(M_ell(55, 90, 34, 5), 2.5), 0.7)
    for a in (-160, -130, -50, -20):
        r0, r1 = 14, rng.uniform(24, 34)
        pts = [(55 + r0 * math.cos(math.radians(a)), 90 + r0 * 0.3 * math.sin(math.radians(a))),
               (55 + r1 * math.cos(math.radians(a)), 90 + r1 * 0.3 * math.sin(math.radians(a)))]
        cv.glowline(M_line(pts, 0.7), c, r=1.0, k=0.7)
    for _ in range(6):
        x, y = rng.uniform(22, 88), rng.uniform(74, 90)
        cv.part(M_poly([(x, y), (x + 2.5, y - 1), (x + 2, y + 2)]), "stone", outline=0.4, shadow=False)


def fx_chains(cv, rng):
    for i in range(6):
        x, y = 20 + i * 5.5, 70 + i * 3
        cv.part(M_ring(x, y, 2.4, 1.1) if i % 2 else SUB(M_ell(x, y, 3.2, 1.8), M_ell(x, y, 1.6, 0.6)), "darksteel", outline=0.6)


def fx_thorns(cv, rng):
    pts = bezier((22, 88), (40, 60), (30, 30), 20)
    cv.part(M_line(pts, 2.0), "wood", color=(70, 90, 40))
    for i in range(3, 20, 4):
        x, y = pts[i]
        s = 1 if i % 8 else -1
        cv.part(M_poly([(x, y - 1.5), (x + s * 6, y - 3), (x, y + 1.5)]), "bone", outline=0.6)


def fx_reticle(cv, rng, color=(255, 70, 50)):
    cx, cy = 70, 30
    cv.glowline(U(M_ring(cx, cy, 10, 0.8), M_line([(cx - 15, cy), (cx - 5, cy)], 0.7), M_line([(cx + 5, cy), (cx + 15, cy)], 0.7),
                  M_line([(cx, cy - 15), (cx, cy - 5)], 0.7), M_line([(cx, cy + 5), (cx, cy + 15)], 0.7)), color, r=1.0)


def fx_frost(cv, rng):
    fx_snow(cv, 76, 24, 8)
    fx_snow(cv, 22, 72, 5)
    fx_sparkles(cv, rng, n=5, color=(200, 235, 255))


def fx_fire(cv, rng):
    fx_flames(cv, 90, 18, 82, 34, rng, n=7)


def fx_bolts(cv, rng, color=None):
    c = color or lighten(cv.theme, 0.4)
    fx_bolt(cv, (14, 18), (34, 56), rng, color=c, segs=5, jitter=4)
    fx_bolt(cv, (88, 40), (70, 82), rng, color=c, segs=5, jitter=4)


def fx_leaves(cv, rng, color=(120, 200, 90)):
    for _ in range(4):
        x, y, a = rng.uniform(15, 85), rng.uniform(15, 85), rng.uniform(0, 180)
        leaf = tf(bezier((0, 0), (3, -3), (0, -8), 8) + bezier((0, -8), (-3, -3), (0, 0), 8), ang=a, c=(0, 0), off=(x, y))
        cv.part(M_poly(leaf), "cloth", color=color, outline=0.5, shadow=False)


def fx_sparkle(cv, rng, color=None):
    fx_sparkles(cv, rng, n=7, color=color or lighten(cv.theme, 0.6))


def fx_hearts(cv, rng, color=(255, 90, 120)):
    for x, y, s in ((22, 24, 3.5), (80, 70, 2.6), (78, 20, 2.2)):
        p = bezier((x, y + s), (x - s * 2, y - s * 0.2), (x - s * 0.9, y - s * 1.3), 8) + bezier((x - s * 0.9, y - s * 1.3), (x, y - s * 1.4), (x, y - s * 0.5), 6) + \
            bezier((x, y - s * 0.5), (x, y - s * 1.4), (x + s * 0.9, y - s * 1.3), 6) + bezier((x + s * 0.9, y - s * 1.3), (x + s * 2, y - s * 0.2), (x, y + s), 8)
        cv.glowline(M_poly(p), color, core=lighten(color, 0.5), r=1.0, k=0.8)


def fx_smoke(cv, rng, color=(150, 150, 170)):
    for _ in range(10):
        x, y, r = rng.uniform(12, 88), rng.uniform(10, 60), rng.uniform(6, 13)
        cv.add(color, blur(M_ell(x, y, r), 4), 0.16)


def fx_ghost(cv, rng):
    cv.add(lighten(cv.theme, 0.4), blur(cv.sil, 4), 0.5)


def fx_blade(cv, rng):
    """small dagger tucked in the boot"""
    import shapes as SH
    SH.sword(cv, dict(ang=18, length=40, wide=3.2, off=(-20, -10), s=0.8, guard="darksteel"))


FX = {k[3:]: v for k, v in globals().items() if k.startswith("fx_") and callable(v)}

# ---------------------------------------------------------------- catalog
# id: (theme, shape, options, pre-fx, post-fx)
B = "boot"
ITEMS = {
    # --- basic shop items ---------------------------------------------------------
    "Vitality": ((60, 200, 90), "gem", dict(cut="long"), [], ["hearts", "sparkle"]),
    "Iron": ((140, 150, 170), "chestplate", dict(), [], []),
    "Swift": ((70, 190, 200), B, dict(style="leather", leather=(120, 80, 45), trim="steel", wing=(200, 230, 240)), ["wind"], []),
    "Power": ((230, 90, 50), "sword", dict(edgeglow=(255, 150, 90), gem=(255, 80, 40)), [], ["sparkle"]),
    "Regen": ((90, 220, 140), "pendant", dict(shape="tear"), ["leaves"], ["sparkle"]),
    # --- general mythics ------------------------------------------------------------
    "WarlordsCleaver": ((170, 50, 45), "cleaver", dict(edgeglow=(255, 90, 60)), [], ["blood"]),
    "AegisOfDawn": ((210, 170, 70), "shield", dict(kind="kite", emblem="sun", tint=(90, 110, 170), mat="cloth"), [], ["sparkle"]),
    "PhantomCloak": ((70, 70, 110), "cloak", dict(tint=(60, 55, 95), eyes=(150, 200, 255), gem=(120, 160, 255)), ["smoke"], []),
    "GolemHeart": ((80, 110, 70), "heart", dict(glow=(120, 255, 110)), [], ["sparkle"]),
    "SwiftBlade": ((180, 200, 100), "sword", dict(wide=4.5, edgeglow=(230, 255, 160), guard_wings=True), ["speed"], []),
    # --- assassin ---------------------------------------------------------------------
    "AssassinBoots": ((120, 60, 150), B, dict(leather=(60, 40, 70), trim="steel"), ["shadow"], ["blade"]),
    "VenomFang": ((90, 40, 120), "dagger", dict(serrated=True, curved=False, edgeglow=(130, 240, 80), gem=(120, 230, 70)), [], ["poison"]),
    "SmokeBomb": ((70, 70, 85), "bomb", dict(), ["smoke"], ["smoke"]),
    "ShadowBlades": ((100, 50, 130), "twin_daggers", dict(edgeglow=(190, 120, 255), guard="darksteel"), ["shadow"], []),
    "HamstringBoots": ((110, 50, 140), B, dict(leather=(80, 40, 60), trim="steel"), [], ["blade", "blood"]),
    "BladedancerBoots": ((160, 80, 190), B, dict(style="slipper", leather=(150, 70, 170), trim="gold"), [], ["sparkle", "speed"]),
    "SilentTreads": ((60, 50, 90), B, dict(leather=(45, 40, 60), trim="darksteel"), ["shadow"], []),
    "ShadowstepBoots": ((90, 45, 140), B, dict(leather=(70, 40, 100), trim="steel"), ["shadow", "speed"], []),
    # --- mage -------------------------------------------------------------------------
    "MageBoots": ((80, 150, 220), B, dict(leather=(50, 80, 150), trim="gold"), ["runes"], []),
    "EmberStaff": ((170, 70, 30), "staff", dict(gem=(255, 120, 40), fire=True), [], ["sparkle"]),
    "FrostTome": ((80, 140, 190), "tome", dict(cover=(50, 80, 140), symbol="snow", plate="silver"), [], ["frost"]),
    "ArcaneOrb": ((100, 60, 180), "orb", dict(inner="swirl"), ["runes"], []),
    "RunicSandals": ((110, 80, 220), B, dict(style="slipper", leather=(80, 60, 150), trim="gold"), ["runes"], []),
    "WindwalkerSlippers": ((120, 200, 200), B, dict(style="slipper", leather=(200, 210, 215), trim="silver", wing=(220, 250, 250)), ["wind"], []),
    "CinderTreads": ((200, 90, 40), B, dict(leather=(110, 40, 25), trim="bronze"), ["fire"], []),
    "BlinkweaveSlippers": ((90, 130, 230), B, dict(style="slipper", leather=(70, 90, 190), trim="silver"), ["runes"], ["sparkle"]),
    # --- marksman ------------------------------------------------------------------
    "RangerBoots": ((70, 120, 60), B, dict(leather=(90, 70, 40), trim="bronze"), ["leaves"], []),
    "HuntersLongbow": ((120, 90, 40), "bow", dict(), [], []),
    "Quickbow": ((90, 160, 70), "bow", dict(ang=-10, glow=(200, 255, 150)), ["speed"], []),
    "TrappersBoots": ((150, 170, 80), B, dict(leather=(100, 80, 45), trim="steel"), ["chains"], []),
    "QuickstepBoots": ((200, 190, 90), B, dict(leather=(150, 110, 50), trim="gold"), ["speed"], []),
    "FleetfootBoots": ((100, 180, 120), B, dict(leather=(140, 110, 70), trim="bronze", wing=(210, 240, 220)), ["wind"], []),
    "DeadshotBoots": ((130, 160, 60), B, dict(leather=(80, 60, 40), trim="steel"), [], ["reticle"]),
    # --- tank ---------------------------------------------------------------------------
    "TankBoots": ((90, 110, 140), B, dict(style="plate", trim="steel"), [], []),
    "BastionShield": ((70, 90, 130), "shield", dict(kind="round", emblem="boss", mat="steel"), [], []),
    "WarHorn": ((150, 110, 50), "horn", dict(waves=True), [], []),
    "GuardianGauntlets": ((80, 100, 140), "gauntlet", dict(spikes=True, gem=(110, 170, 255)), [], []),
    "ShackleGreaves": ((130, 110, 80), B, dict(style="plate", trim="bronze"), [], ["chains"]),
    "ThornmarchSabatons": ((150, 90, 60), B, dict(style="plate", trim="bronze", metal=(140, 100, 70)), ["thorns"], []),
    "UnyieldingGreaves": ((170, 150, 90), B, dict(style="greave", trim="gold"), ["impact"], []),
    "RampartSabatons": ((90, 120, 170), B, dict(style="greave", trim="steel", metal=(110, 140, 190)), [], []),
    # --- fighter ------------------------------------------------------------------------
    "FighterBoots": ((200, 110, 50), B, dict(style="greave", trim="gold", metal=(200, 130, 80)), [], []),
    "BerserkerAxe": ((150, 50, 40), "axe", dict(edgeglow=(255, 90, 60)), [], ["blood"]),
    "TitanGauntlets": ((110, 90, 70), "gauntlet", dict(mat="stone", gem=(255, 160, 60)), ["impact"], []),
    "WarDrums": ((160, 60, 50), "drum", dict(tint=(150, 60, 40), emblem=(255, 90, 50)), [], ["sparkle"]),
    "TrancefireBoots": ((210, 90, 60), B, dict(leather=(140, 50, 30), trim="gold"), ["fire"], []),
    "WarpathBoots": ((200, 130, 60), B, dict(style="greave", trim="bronze", metal=(170, 120, 80)), ["speed"], []),
    "HeadsmansBoots": ((150, 50, 45), B, dict(leather=(35, 30, 30), trim="darksteel"), [], ["blood"]),
    "BoundingGreaves": ((180, 120, 70), B, dict(style="greave", trim="bronze", metal=(190, 150, 110)), ["impact"], []),
    # --- passives: general -------------------------------------------------------------------
    "BloodstonePendant": ((170, 30, 45), "pendant", dict(shape="tear", gem=(200, 20, 40)), [], ["sparkle"]),
    "Emberglass": ((230, 110, 40), "gem", dict(cut="shard", color=(255, 130, 40)), ["fire"], []),
    "MoonlitPendant": ((120, 150, 230), "pendant", dict(shape="moon", frame="silver", chain="silver", gem=(170, 200, 255)), [], ["sparkle"]),
    "HuntersEye": ((200, 170, 70), "eye", dict(iris=(230, 170, 40), slit=True), [], []),
    "ObsidianShard": ((70, 60, 90), "gem", dict(cut="shard", color=(60, 50, 85)), [], ["sparkle"]),
    "SoulFurnace": ((150, 60, 160), "core", dict(glow=(220, 120, 255)), ["fire"], []),
    "FrostfirePendant": ((110, 190, 230), "pendant", dict(shape="diamond", gem=(120, 200, 255)), ["fire"], ["frost"]),
    "ManaforgedRing": ((70, 120, 220), "ring", dict(gem=(90, 150, 255)), [], ["sparkle"]),
    "WarlocksCoin": ((210, 170, 50), "coin", dict(symbol="skull"), [], ["sparkle"]),
    "ChronoGear": ((180, 150, 90), "gear", dict(gem=(120, 220, 255)), ["runes"], []),
    # --- passives: assassin ---------------------------------------------------------------------
    "ExecutionersTalon": ((140, 30, 50), "talon", dict(edgeglow=(255, 70, 80), gem=(220, 30, 50)), [], ["blood"]),
    "Nightfang": ((60, 40, 110), "fang", dict(gem=(140, 90, 255)), ["shadow"], []),
    "Venomclaw": ((90, 170, 60), "claw", dict(edgeglow=(150, 255, 90)), [], ["poison"]),
    "Bloodletter": ((180, 20, 30), "dagger", dict(curved=True, edgeglow=(255, 60, 60), guard="darksteel"), [], ["blood"]),
    "Ghoststeel": ((150, 170, 200), "dagger", dict(blade="glow", tint=(170, 210, 255), guard="silver"), ["smoke"], ["ghost"]),
    "Widowmaker": ((90, 20, 60), "dagger", dict(serrated=True, blade="darksteel", edgeglow=(255, 40, 110), gem=(200, 20, 80)), ["shadow"], []),
    "Soulpiercer": ((120, 80, 170), "sword", dict(wide=3.2, edgeglow=(200, 150, 255), gem=(160, 100, 255), guard="silver"), [], ["sparkle"]),
    "CrimsonClaw": ((200, 40, 60), "claw", dict(tint=(170, 40, 50), edgeglow=(255, 90, 90)), [], ["blood"]),
    # --- passives: mage -------------------------------------------------------------------------
    "InfernalCodex": ((220, 80, 30), "tome", dict(cover=(120, 30, 20), symbol="flame"), [], ["sparkle"]),
    "WinterCrown": ((140, 200, 240), "crown", dict(ice=True, gem=(120, 200, 255)), [], ["frost"]),
    "VoidLantern": ((80, 40, 140), "lantern", dict(flame=(170, 90, 255)), ["smoke"], []),
    "ManaCrystal": ((60, 140, 230), "crystal_cluster", dict(color=(80, 160, 255)), [], ["sparkle"]),
    "StarfallLens": ((240, 200, 90), "lens", dict(glass=(120, 140, 230), stars=True), [], ["sparkle"]),
    "WitchfireOrb": ((120, 200, 80), "orb", dict(inner="flame", stand="darksteel"), [], []),
    "Soulglass": ((150, 110, 220), "orb", dict(inner="skull", stand="silver"), ["smoke"], []),
    "StormcallersEye": ((90, 170, 255), "eye", dict(iris=(90, 180, 255), storm=True, mat="silver"), ["bolts"], []),
    # --- passives: marksman ---------------------------------------------------------------------
    "SilverwindBow": ((190, 200, 210), "bow", dict(mat="silver", tip="silver"), ["wind"], []),
    "CrimsonQuiver": ((170, 40, 40), "quiver", dict(leather=(130, 35, 35), fletch=(230, 60, 50)), [], []),
    "EagleEye": ((210, 180, 100), "eye", dict(iris=(240, 180, 40), slit=False), [], ["sparkle"]),
    "StormQuiver": ((100, 170, 230), "quiver", dict(leather=(50, 70, 110), fletch=(150, 210, 255), glow=(150, 210, 255)), ["bolts"], []),
    "Venomshot": ((110, 180, 70), "arrow", dict(ang=45, len=86, glow=(150, 255, 90), fletch=(90, 170, 60)), [], ["poison"]),
    "ExecutionBow": ((120, 40, 30), "bow", dict(mat="darksteel", glow=(255, 80, 60), gem=(220, 40, 30)), [], []),
    "Lifebow": ((200, 60, 90), "bow", dict(gem=(255, 80, 120), glow=(255, 150, 170)), [], ["hearts"]),
    "Windpiercer": ((160, 210, 190), "arrow", dict(ang=60, len=90, glow=(220, 255, 240), fletch=(200, 240, 230)), ["wind"], []),
    # --- passives: tank ------------------------------------------------------------------------
    "MoltenCore": ((220, 90, 30), "core", dict(glow=(255, 140, 40)), [], ["sparkle"]),
    "MirrorAegis": ((170, 200, 230), "shield", dict(kind="kite", emblem="mirror", trim="silver"), [], ["sparkle"]),
    "Frostwall": ((130, 180, 220), "shield", dict(kind="kite", emblem="frost", mat="cloth", tint=(60, 100, 150), trim="silver"), [], ["frost"]),
    "BloodguardPlate": ((150, 40, 40), "chestplate", dict(tint=(150, 50, 50), emblem=(220, 20, 40)), [], ["blood"]),
    "AdamantBulwark": ((150, 150, 160), "shield", dict(kind="kite", emblem="wall", mat="cloth", tint=(90, 90, 100), trim="steel"), [], []),
    "PlagueCarapace": ((110, 140, 60), "carapace", dict(tint=(90, 120, 50)), [], ["poison"]),
    "ColossusBelt": ((120, 150, 70), "belt", dict(leather=(110, 75, 40), gem=(140, 220, 90)), [], []),
    "GuardiansBell": ((220, 190, 110), "bell", dict(), [], ["sparkle"]),
    # --- passives: fighter ------------------------------------------------------------------------
    "Bloodaxe": ((170, 30, 30), "axe", dict(double=False, edgeglow=(255, 60, 60), tint=(150, 60, 60)), [], ["blood"]),
    "Ironbreaker": ((130, 130, 140), "hammer", dict(), ["impact"], []),
    "Lifedrinker": ((190, 40, 70), "sword", dict(serrated=True, edgeglow=(255, 80, 120), gem=(230, 40, 80)), [], ["hearts"]),
    "WarforgedMail": ((160, 110, 60), "chestplate", dict(mat="bronze", mail=True), [], ["sparkle"]),
    "Chainbreaker": ((150, 120, 80), "chain_broken", dict(), [], []),
    "Battlebrand": ((200, 90, 40), "brand", dict(edgeglow=(255, 160, 80)), [], []),
    "SanguineHammer": ((140, 20, 40), "hammer", dict(tint=(120, 40, 50), gem=(230, 30, 60)), [], ["blood"]),
    "DragonheartAxe": ((210, 70, 30), "axe", dict(gem=(255, 120, 30), edgeglow=(255, 170, 60)), ["fire"], []),
    # --- special purchasables --------------------------------------------------------------------
    "WarBand": ((170, 40, 45), "war_banner", dict(cloth=(170, 35, 40)), ["fire"], []),
    "MinionUpgrade": ((200, 150, 60), "upgrade_emblem", dict(), [], ["sparkle"]),
}
