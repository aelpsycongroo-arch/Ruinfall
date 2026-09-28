"""Icon catalog. Each entry illustrates what the item actually does in Ruinfall:
the object is the item itself, the effects show its ability / passive mechanic, and
every boot stands on the magic circle of its BootType (read from ItemDefinitions)."""
import math, os, re
from iconkit import *
import fx as F

HERE = os.path.dirname(os.path.abspath(__file__))
ITEMDEFS = os.path.join(HERE, "..", "..", "src", "ReplicatedStorage", "Shared", "ItemDefinitions.luau")


def boot_types():
    """BootType per boot, from ItemDefinitions.RoleBoots (ordered like ItemDefinitions.BootTypes)."""
    src = open(ITEMDEFS, encoding="utf-8").read()
    kinds = re.findall(r'"([^"]+)"', re.search(r'ItemDefinitions\.BootTypes = \{([^}]*)\}', src).group(1))
    block = re.search(r'ItemDefinitions\.RoleBoots = \{(.*?)\n\}', src, re.S).group(1)
    out = {}
    for row in re.findall(r'\{([^}]*)\}', block):
        for kind, item in zip(kinds, re.findall(r'"(\w+)"', row)):
            out[item] = kind
    return out


BOOT_TYPE = boot_types()

CLASS = {
    "Assassin": (200, 40, 60), "Mage": (150, 80, 255), "Marksman": (70, 200, 90),
    "Tank": (60, 110, 220), "Fighter": (255, 150, 40),
}


# ---------------------------------------------------------------- item-specific effects
def slash_arc(cv, color=(255, 90, 60)):
    pts = arc_pts(50, 54, 42, 38, 150, 370, 60)
    cv.glow(M_poly(ribbon(pts, lambda t: 2.8 * math.sin(math.pi * t) + 0.1)), color, k=0.7, r=1.4)


def whirl(cv, color=(255, 90, 60)):
    for r, a0 in ((44, 200), (38, 20)):
        pts = arc_pts(50, 50, r, r * 0.9, a0, a0 + 130, 40)
        cv.glow(M_poly(ribbon(pts, lambda t: 1.8 * math.sin(math.pi * t) + 0.1)), color, k=0.6, r=1.2)


def fireball(cv, color=(255, 120, 30)):
    x, y = 76, 22
    cv.glow(M_poly(ribbon([(96, 4), (x, y)], lambda t: 4.5 * t)), color, k=0.6, r=1.8)
    cv.add(color, blur(M_ell(x, y, 7), 2.5), 0.9)
    cv.add((255, 230, 150), blur(M_ell(x, y, 3.5), 1), 1.0)


def knife_fan(cv, color=(200, 130, 255)):
    for a in (-60, -30, 0, 30, 60):
        r = math.radians(a - 90)
        x, y = 50 + 40 * math.cos(r), 54 + 40 * math.sin(r)
        pts = tf([(x, y - 3.5), (x + 1, y + 1.5), (x - 1, y + 1.5)], ang=a, c=(x, y))
        cv.part(M_poly(pts), "steel", round=0.5, outline=0.6, shadow=0.1)
        cv.glow(M_line([(x - 5 * math.cos(r), y - 5 * math.sin(r)), (x - 1.5 * math.cos(r), y - 1.5 * math.sin(r))], 0.35), color, k=0.5, r=0.7)


def sound_waves(cv, color=None):
    c = color or lighten(cv.theme, 0.4)
    for r in (40, 45):
        F.ring_wave(cv, 50, 62, r, c, ry=r * 0.8, w=0.5, k=0.5, a0=190, a1=350)


def reveal(cv, color=(255, 220, 120)):
    for a in range(0, 360, 20):
        r = math.radians(a)
        cv.glow(M_line([(50 + 40 * math.cos(r), 50 + 40 * math.sin(r)), (50 + 46 * math.cos(r), 50 + 46 * math.sin(r))], 0.35), color, k=0.45, r=0.7)
    for x, y in ((18, 78), (84, 24)):   # hidden silhouettes being revealed
        m = U(M_ell(x, y - 4, 2.2), M_poly([(x - 3.5, y - 1.5), (x + 3.5, y - 1.5), (x + 4, y + 7), (x - 4, y + 7)]))
        cv.glow(SUB(dilate(m, 0.3), m), (255, 90, 60), k=0.7, r=0.7)


def heal_motes(cv, color=(110, 255, 140)):
    rng = cv.rng
    for _ in range(6):
        x, y, s = rng.uniform(14, 86), rng.uniform(14, 86), rng.uniform(1.2, 2.4)
        cv.glow(U(M_rect(x - s * 0.3, y - s, x + s * 0.3, y + s, 0.3), M_rect(x - s, y - s * 0.3, x + s, y + s * 0.3, 0.3)), color, k=0.7, r=0.8)


LOCAL = dict(slash_arc=slash_arc, whirl=whirl, fireball=fireball, knife_fan=knife_fan, sound_waves=sound_waves,
             reveal=reveal, heal_motes=heal_motes)


def fx(name, **kw):
    fn = LOCAL.get(name) or getattr(F, "fx_" + name)
    return (fn, kw)


def E(theme, shape, o=None, pre=(), post=(), glow=1.0):
    return dict(theme=theme, shape=shape, o=o or {}, pre=list(pre), post=list(post), glow=glow)


def BOOT(item_id, theme, o, pre=(), post=()):
    return dict(theme=theme, shape="boot", o=o, pre=list(pre), post=list(post), glow=0.55, boot=BOOT_TYPE[item_id])


ITEMS = {
    # ------------------------------------------------------------------ basic shop
    "Vitality": E((60, 210, 100), "gem_shape", dict(cut="long", color=(50, 220, 110)), post=[fx("heal_motes")]),
    "Iron": E((150, 160, 180), "chestplate", dict(), post=[fx("gold_glint")]),
    "Swift": E((80, 200, 210), "boot", dict(leather=(120, 80, 45), trim="bronze"), pre=[fx("wind")], post=[fx("speed")]),
    "Power": E((230, 80, 40), "sword", dict(edgeglow=(255, 140, 80), gem=(255, 70, 40)), pre=[fx("burn", color=(255, 90, 40))]),
    "Regen": E((90, 220, 140), "pendant", dict(shape="tear", gem=(70, 230, 130)), pre=[fx("growth")], post=[fx("heal_motes")]),

    # ------------------------------------------------------------------ general mythics
    "WarlordsCleaver": E((170, 50, 45), "cleaver", dict(edgeglow=(255, 90, 60)), pre=[fx("slash_arc")], post=[fx("bleed")]),
    "AegisOfDawn": E((230, 180, 70), "shield", dict(kind="kite", emblem="sun", mat="cloth", tint=(60, 80, 150)), pre=[fx("shield_dome", color=(255, 220, 130))]),
    "PhantomCloak": E((90, 90, 150), "cloak", dict(tint=(55, 50, 90), eyes=(150, 200, 255), gem=(120, 160, 255)), pre=[fx("smoke")], post=[fx("blade_shadow")]),
    "GolemHeart": E((80, 130, 70), "golem_heart", dict(glow=(130, 255, 110)), post=[fx("ground_crack", color=(130, 255, 110))]),
    "SwiftBlade": E((190, 210, 100), "sword", dict(wide=4.4, edgeglow=(230, 255, 160)), pre=[fx("speed")]),

    # ------------------------------------------------------------------ assassin
    "VenomFang": E((90, 40, 120), "dagger", dict(edgeglow=(140, 240, 80), gem=(120, 230, 70), grip=(40, 30, 50)), pre=[fx("shadow")], post=[fx("blade_shadow", color=(150, 90, 220))]),
    "SmokeBomb": E((90, 90, 110), "bomb", dict(), pre=[fx("smoke")], post=[fx("smoke")]),
    "ShadowBlades": E((110, 50, 150), "twin_daggers", dict(edgeglow=(190, 120, 255), guard="darksteel"), pre=[fx("shadow"), fx("knife_fan")]),
    "AssassinBoots": BOOT("AssassinBoots", (120, 60, 150), dict(leather=(55, 38, 66), trim="steel")),
    "HamstringBoots": BOOT("HamstringBoots", (110, 50, 140), dict(leather=(78, 36, 58), trim="steel")),
    "BladedancerBoots": BOOT("BladedancerBoots", (160, 80, 190), dict(style="slipper", leather=(130, 60, 150), trim="gold")),
    "SilentTreads": BOOT("SilentTreads", (70, 60, 110), dict(leather=(42, 38, 58), trim="darksteel")),
    "ShadowstepBoots": BOOT("ShadowstepBoots", (100, 50, 160), dict(leather=(66, 38, 96), trim="steel")),

    # ------------------------------------------------------------------ mage
    "EmberStaff": E((190, 80, 30), "staff", dict(gem=(255, 120, 40)), post=[fx("fireball")]),
    "FrostTome": E((80, 150, 210), "tome", dict(cover=(40, 70, 130), symbol="snow", plate="silver"), post=[fx("frost")]),
    "ArcaneOrb": E((120, 70, 210), "orb", dict(inner="swirl", color=(150, 90, 255)), pre=[fx("runes")], post=[fx("mana", color=(190, 130, 255))]),
    "MageBoots": BOOT("MageBoots", (80, 150, 220), dict(leather=(45, 70, 140), trim="gold")),
    "RunicSandals": BOOT("RunicSandals", (110, 80, 220), dict(style="slipper", leather=(80, 60, 150), trim="gold")),
    "WindwalkerSlippers": BOOT("WindwalkerSlippers", (120, 200, 200), dict(style="slipper", leather=(180, 200, 205), trim="silver")),
    "CinderTreads": BOOT("CinderTreads", (210, 90, 40), dict(leather=(100, 36, 22), trim="bronze"), pre=[fx("burn")]),
    "BlinkweaveSlippers": BOOT("BlinkweaveSlippers", (90, 130, 230), dict(style="slipper", leather=(60, 80, 180), trim="silver")),

    # ------------------------------------------------------------------ marksman
    "HuntersLongbow": E((140, 100, 45), "bow", dict(fletch=(200, 60, 40)), pre=[fx("pierce")]),
    "Quickbow": E((90, 170, 70), "bow", dict(ang=-10, glow=(200, 255, 150), fletch=(90, 170, 60)), pre=[fx("speed")]),
    "RangerBoots": BOOT("RangerBoots", (70, 130, 60), dict(leather=(92, 70, 40), trim="bronze")),
    "TrappersBoots": BOOT("TrappersBoots", (150, 170, 80), dict(leather=(98, 78, 44), trim="steel")),
    "QuickstepBoots": BOOT("QuickstepBoots", (200, 190, 90), dict(leather=(140, 102, 48), trim="gold")),
    "FleetfootBoots": BOOT("FleetfootBoots", (100, 180, 120), dict(leather=(130, 104, 66), trim="bronze")),
    "DeadshotBoots": BOOT("DeadshotBoots", (130, 160, 60), dict(leather=(76, 58, 38), trim="steel")),

    # ------------------------------------------------------------------ tank
    "BastionShield": E((70, 100, 160), "shield", dict(kind="round", emblem="boss", mat="steel"), pre=[fx("retaliate", color=(170, 210, 255))]),
    "WarHorn": E((170, 120, 50), "horn", dict(waves=True), pre=[fx("sound_waves")]),
    "GuardianGauntlets": E((80, 110, 160), "gauntlet", dict(spikes=True, gem=(110, 170, 255)), pre=[fx("speed")]),
    "TankBoots": BOOT("TankBoots", (90, 110, 140), dict(style="plate", trim="steel")),
    "ShackleGreaves": BOOT("ShackleGreaves", (130, 110, 80), dict(style="plate", trim="bronze")),
    "ThornmarchSabatons": BOOT("ThornmarchSabatons", (150, 90, 60), dict(style="plate", trim="bronze", metal=(150, 110, 80))),
    "UnyieldingGreaves": BOOT("UnyieldingGreaves", (170, 150, 90), dict(style="greave", leather=(90, 70, 45), trim="gold")),
    "RampartSabatons": BOOT("RampartSabatons", (90, 120, 170), dict(style="plate", trim="steel", metal=(120, 150, 200))),

    # ------------------------------------------------------------------ fighter
    "BerserkerAxe": E((160, 50, 40), "axe", dict(edgeglow=(255, 90, 60)), pre=[fx("whirl")], post=[fx("bleed")]),
    "TitanGauntlets": E((120, 95, 70), "gauntlet", dict(mat="stone", cracks=(255, 160, 60), gem=(255, 150, 50)), post=[fx("ground_crack", color=(255, 160, 60))]),
    "WarDrums": E((170, 60, 50), "drum", dict(tint=(150, 60, 40), emblem=(255, 90, 50)), pre=[fx("sound_waves", color=(255, 150, 90))]),
    "FighterBoots": BOOT("FighterBoots", (200, 110, 50), dict(style="greave", leather=(110, 60, 30), trim="gold", metal=(200, 140, 90))),
    "TrancefireBoots": BOOT("TrancefireBoots", (210, 90, 60), dict(leather=(130, 46, 28), trim="gold"), pre=[fx("burn")]),
    "WarpathBoots": BOOT("WarpathBoots", (200, 130, 60), dict(style="greave", leather=(100, 64, 34), trim="bronze", metal=(170, 125, 85))),
    "HeadsmansBoots": BOOT("HeadsmansBoots", (150, 50, 45), dict(leather=(34, 30, 30), trim="darksteel")),
    "BoundingGreaves": BOOT("BoundingGreaves", (180, 120, 70), dict(style="greave", leather=(90, 62, 38), trim="bronze", metal=(190, 150, 110))),

    # ------------------------------------------------------------------ passives: general
    "BloodstonePendant": E((170, 30, 45), "pendant", dict(shape="tear", gem=(210, 20, 40)), pre=[fx("lifesteal")]),
    "Emberglass": E((230, 110, 40), "gem_shape", dict(cut="shard", color=(255, 130, 40)), pre=[fx("burn")]),
    "MoonlitPendant": E((110, 140, 230), "pendant", dict(shape="moon", frame="silver", chain="silver", gem=(150, 190, 255)), post=[fx("mana")]),
    "HuntersEye": E((200, 170, 70), "eye", dict(iris=(230, 170, 40), slit=True), pre=[fx("reveal")]),
    "ObsidianShard": E((110, 80, 160), "gem_shape", dict(cut="shard", color=(70, 50, 100)), post=[fx("shatter")]),
    "SoulFurnace": E((150, 60, 170), "core", dict(glow=(220, 120, 255), cage=True), pre=[fx("souls")]),
    "FrostfirePendant": E((110, 190, 230), "pendant", dict(shape="diamond", gem=(130, 210, 255)), pre=[fx("burn", color=(255, 130, 60))], post=[fx("frost")]),
    "ManaforgedRing": E((70, 120, 230), "ring", dict(gem=(90, 150, 255)), post=[fx("mana")]),
    "WarlocksCoin": E((210, 170, 50), "coin", dict(eyes=(255, 80, 40)), post=[fx("coins")]),
    "ChronoGear": E((180, 150, 90), "gear", dict(gem=(120, 220, 255)), pre=[fx("rewind")]),

    # ------------------------------------------------------------------ passives: assassin
    "ExecutionersTalon": E((150, 30, 50), "talon", dict(edgeglow=(255, 70, 80), gem=(220, 30, 50)), post=[fx("bleed"), fx("mark")]),
    "Nightfang": E((80, 50, 140), "fang", dict(gem=(150, 100, 255)), pre=[fx("shadow")], post=[fx("mark", color=(190, 120, 255))]),
    "Venomclaw": E((90, 170, 60), "claw", dict(edgeglow=(150, 255, 90)), post=[fx("poison")]),
    "Bloodletter": E((180, 20, 30), "dagger", dict(curved=True, edgeglow=(255, 60, 60), guard="darksteel"), post=[fx("bleed")]),
    "Ghoststeel": E((150, 180, 220), "dagger", dict(blade="silver", tint=(170, 210, 255), guard="silver", edgeglow=(200, 230, 255)), pre=[fx("smoke", color=(170, 200, 240))], post=[fx("ghost")]),
    "Widowmaker": E((110, 20, 60), "dagger", dict(serrated=True, blade="darksteel", edgeglow=(255, 40, 110), gem=(200, 20, 80)), pre=[fx("shadow")], post=[fx("anti_heal")]),
    "Soulpiercer": E((120, 80, 170), "sword", dict(wide=3.2, rapier=True, edgeglow=(200, 150, 255), gem=(160, 100, 255), guard="silver"), post=[fx("shatter")]),
    "CrimsonClaw": E((200, 40, 60), "claw", dict(tint=(170, 40, 50), edgeglow=(255, 90, 90)), pre=[fx("speed", color=(255, 90, 90))], post=[fx("bleed")]),

    # ------------------------------------------------------------------ passives: mage
    "InfernalCodex": E((220, 80, 30), "tome", dict(cover=(110, 28, 18), symbol="flame"), pre=[fx("explosion")]),
    "WinterCrown": E((140, 200, 240), "crown", dict(ice=True, gem=(120, 200, 255)), post=[fx("frost")]),
    "VoidLantern": E((110, 50, 180), "lantern", dict(flame=(170, 90, 255)), pre=[fx("smoke", color=(140, 90, 200))], post=[fx("shatter")]),
    "ManaCrystal": E((60, 140, 230), "crystal_cluster", dict(color=(80, 160, 255)), post=[fx("mana")]),
    "StarfallLens": E((240, 200, 90), "lens", dict(glass=(110, 120, 220), stars=True), post=[fx("meteor")]),
    "WitchfireOrb": E((120, 200, 80), "orb", dict(inner="flame", stand="darksteel", color=(110, 210, 80)), post=[fx("curse")]),
    "Soulglass": E((150, 110, 220), "orb", dict(inner="skull", stand="silver", color=(160, 120, 240)), pre=[fx("lifesteal", color=(120, 170, 255))]),
    "StormcallersEye": E((90, 170, 255), "eye", dict(iris=(90, 180, 255), mat="silver"), pre=[fx("lightning")]),

    # ------------------------------------------------------------------ passives: marksman
    "SilverwindBow": E((190, 205, 215), "bow", dict(mat="silver", trim="silver", fletch=(200, 230, 240), glow=(220, 240, 255)), pre=[fx("wind"), fx("pierce")]),
    "CrimsonQuiver": E((170, 40, 40), "quiver", dict(leather=(120, 30, 30), fletch=(230, 60, 50)), post=[fx("bleed")]),
    "EagleEye": E((210, 180, 100), "eye", dict(iris=(240, 180, 40)), pre=[fx("target_range")]),
    "StormQuiver": E((100, 170, 230), "quiver", dict(leather=(45, 62, 100), fletch=(150, 210, 255), glow=(150, 210, 255)), pre=[fx("chain_lightning")]),
    "Venomshot": E((110, 180, 70), "arrow", dict(ang=45, length=86, glow=(150, 255, 90), fletch=(90, 170, 60)), post=[fx("poison")]),
    "ExecutionBow": E((130, 40, 30), "bow", dict(mat="darksteel", glow=(255, 80, 60), gem=(220, 40, 30), fletch=(40, 30, 30)), post=[fx("mark")]),
    "Lifebow": E((200, 60, 90), "bow", dict(gem=(255, 80, 120), glow=(255, 150, 170)), pre=[fx("lifesteal")]),
    "Windpiercer": E((160, 210, 190), "arrow", dict(ang=60, length=90, glow=(220, 255, 240), fletch=(200, 240, 230)), pre=[fx("wind")], post=[fx("shatter")]),

    # ------------------------------------------------------------------ passives: tank
    "MoltenCore": E((220, 90, 30), "core", dict(glow=(255, 140, 40)), pre=[fx("heat")]),
    "MirrorAegis": E((170, 200, 230), "shield", dict(kind="kite", emblem="mirror", trim="silver"), post=[fx("reflect")]),
    "Frostwall": E((130, 180, 220), "shield", dict(kind="kite", emblem="frost", mat="cloth", tint=(50, 90, 140), trim="silver"), post=[fx("slow")]),
    "BloodguardPlate": E((160, 40, 40), "chestplate", dict(tint=(150, 50, 50), emblem=(220, 20, 40)), pre=[fx("shield_dome", color=(255, 90, 90))]),
    "AdamantBulwark": E((150, 150, 165), "shield", dict(kind="kite", emblem="wall", mat="cloth", tint=(80, 80, 95), trim="steel"), post=[fx("tenacity")]),
    "PlagueCarapace": E((110, 140, 60), "carapace", dict(tint=(80, 110, 45)), pre=[fx("blight")]),
    "ColossusBelt": E((120, 150, 70), "belt", dict(leather=(105, 70, 38), gem=(140, 220, 90)), pre=[fx("growth")]),
    "GuardiansBell": E((220, 190, 110), "bell", dict(), pre=[fx("rescue")]),

    # ------------------------------------------------------------------ passives: fighter
    "Bloodaxe": E((170, 30, 30), "axe", dict(double=False, edgeglow=(255, 60, 60), tint=(150, 60, 60)), post=[fx("bleed"), fx("stacks")]),
    "Ironbreaker": E((130, 135, 150), "hammer", dict(), post=[fx("shatter")]),
    "Lifedrinker": E((190, 40, 70), "sword", dict(serrated=True, edgeglow=(255, 80, 120), gem=(230, 40, 80)), pre=[fx("lifesteal")]),
    "WarforgedMail": E((170, 110, 60), "chestplate", dict(mat="bronze", mail=True), pre=[fx("retaliate")]),
    "Chainbreaker": E((150, 120, 80), "chain", dict(), pre=[fx("speed", color=(255, 210, 150))]),
    "Battlebrand": E((210, 90, 40), "sword", dict(wide=6.4, length=68, guard="bronze", edgeglow=(255, 160, 80)), pre=[fx("burn")], post=[fx("mark", color=(255, 120, 40))]),
    "SanguineHammer": E((150, 25, 45), "hammer", dict(tint=(120, 40, 50), gem=(230, 30, 60)), post=[fx("ground_crack", color=(255, 60, 80))]),
    "DragonheartAxe": E((210, 70, 30), "axe", dict(gem=(255, 120, 30), edgeglow=(255, 170, 60)), pre=[fx("rage", color=(255, 90, 30)), fx("burn")]),

    # ------------------------------------------------------------------ special purchasables
    "WarBand": E((170, 40, 45), "warband", dict(cloth=(165, 30, 38))),
    "MinionUpgrade": E((200, 150, 60), "upgrade", dict(), post=[fx("stacks", color=(255, 210, 120))]),
}


# ---------------------------------------------------------------- class Q skills
def skill_shadow_step(cv, o):
    """Dash, vanish, empowered strike: a dagger lunging out of a trail of shadow clones."""
    import shapes as SH
    F.fx_shadow(cv, color=(120, 40, 90))
    for i, (dx, a) in enumerate(((-26, 0.18), (-16, 0.32))):
        c2 = Canvas(cv.theme, seed=i)
        SH.sword(c2, dict(ang=60, length=54, wide=5, s=1.1, off=(dx + 6, 6 - dx * 0.3)))
        cv.add(lighten(cv.theme, 0.25), blur(c2.sil, 0.6), a)
    SH.sword(cv, dict(ang=60, length=54, wide=5, s=1.1, off=(8, 2), edgeglow=(255, 90, 110), guard="darksteel", gem=(255, 50, 80)))
    F.fx_speed(cv, color=(255, 120, 140))


def skill_arcane_burst(cv, o):
    from circles import circle_damage
    c = (170, 100, 255)
    cv.add(c, blur(M_ell(50, 50, 42), 6), 0.4)
    m = circle_damage()
    cv.add(c, blur(m, 1.2), 0.5)
    cv.add(lighten(c, 0.5), m, 0.35)
    for i in range(16):
        a = math.radians(i * 22.5)
        l = 40 if i % 2 == 0 else 26
        cv.glow(M_poly([(50 + 3 * math.cos(a + 0.3), 50 + 3 * math.sin(a + 0.3)), (50 + l * math.cos(a), 50 + l * math.sin(a)),
                        (50 + 3 * math.cos(a - 0.3), 50 + 3 * math.sin(a - 0.3))]), c, k=0.6, r=1.2)
    cv.add((255, 240, 255), blur(M_ell(50, 50, 9), 3), 1.2)
    cv.glow(M_ell(50, 50, 5), (230, 200, 255), k=1.0, r=2)
    F.motes(cv, 14, lighten(c, 0.3))


def skill_dash_shot(cv, o):
    """roll back and loose an arrow"""
    import shapes as SH
    F.fx_wind(cv, color=(150, 255, 160))
    SH.arrow(cv, dict(ang=62, length=88, glow=(170, 255, 160), fletch=(80, 190, 90), off=(4, -2)))
    for i in range(3):
        y = 60 + i * 7
        cv.glow(M_line([(10, y + 6), (46, y - 12)], 0.5), (150, 255, 160), k=0.5 - i * 0.12, r=0.9)
    F.motes(cv, 8, (170, 255, 160))


def skill_taunting_shockwave(cv, o):
    import shapes as SH
    c = (110, 170, 255)
    for r in (46, 40, 34):
        F.ring_wave(cv, 50, 70, r, c, ry=r * 0.45, w=0.8, k=0.7)
    SH.shield(cv, dict(kind="kite", emblem="boss", mat="steel", trim="gold"))
    for a in (-135, -45, 135, 45):
        r = math.radians(a)
        cx, cy = 50 + 43 * math.cos(r), 50 + 43 * math.sin(r)
        for j in (0, 4):
            q = [(cx - j * math.cos(r) + 4 * math.cos(r + 2.3), cy - j * math.sin(r) + 4 * math.sin(r + 2.3)),
                 (cx - j * math.cos(r), cy - j * math.sin(r)),
                 (cx - j * math.cos(r) + 4 * math.cos(r - 2.3), cy - j * math.sin(r) + 4 * math.sin(r - 2.3))]
            cv.glow(M_line(q, 0.8), (255, 80, 60), k=0.9, r=1.0)
    F.fx_ground_crack(cv, color=c)


def skill_blood_rush(cv, o):
    c = (255, 50, 50)
    F.fx_lifesteal(cv, color=c, n=3)
    for i, dx in enumerate((-10, 0, 10)):   # three claw slashes
        sp = bez((22 + dx, 86), (40 + dx, 56), (76 + dx, 14), n=24)
        cv.glow(M_poly(ribbon(sp, lambda t: 2.4 * math.sin(math.pi * t) + 0.1)), c, k=0.9, r=1.3, core=(255, 220, 220))
    F.fx_bleed(cv, pts=[(70, 74, 1.8), (62, 84, 1.3), (80, 62, 1.1)])
    F.fx_speed(cv, color=(255, 120, 120))


SKILLS = {
    "Skill_ShadowStep": dict(theme=CLASS["Assassin"], draw=skill_shadow_step, name="Shadow Step"),
    "Skill_ArcaneBurst": dict(theme=CLASS["Mage"], draw=skill_arcane_burst, name="Arcane Burst"),
    "Skill_DashShot": dict(theme=CLASS["Marksman"], draw=skill_dash_shot, name="Dash Shot"),
    "Skill_TauntingShockwave": dict(theme=CLASS["Tank"], draw=skill_taunting_shockwave, name="Taunting Shockwave"),
    "Skill_BloodRush": dict(theme=CLASS["Fighter"], draw=skill_blood_rush, name="Blood Rush"),
}
