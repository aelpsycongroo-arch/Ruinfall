-- ItemDefinitions: the single source of truth for Mythic items, item-granted E/R
-- abilities and the purchasable creep War Band. The server reads these numbers for
-- all gameplay; the shop/HUD read the SAME numbers for tooltips, so displayed values
-- can never drift from server logic.
--
-- Adding a new mythic item = add an entry to Items (+ an ability to Abilities if new)
-- and a server handler in ItemService. Shop/HUD pick it up automatically.

local AbilityScaling = require(script.Parent:WaitForChild("AbilityScaling"))

local ItemDefinitions = {}

-- Damage / Shield are SCALING tables (see AbilityScaling): { AD = 2.4 } = 240% of the
-- caster's attack damage, { HP = 0.13 } = 13% of max health, etc. Ratios were tuned so a
-- hero with base stats + the item's own passive deals what the old fixed numbers did;
-- anything that raises AD / max HP / armor now makes the skill stronger.
-- MAGE item skills scale on Magic Power instead ({ MP = x }: the Mage's base Magic Power +
-- Magic Power from items) and ALL of them cost mana - boot skills included (ability.ManaCost).

ItemDefinitions.MAX_MYTHIC_SLOTS = 2 -- slot 1 -> E, slot 2 -> R
ItemDefinitions.SLOT_KEYS = { "E", "R", "RMB" } -- [3] = the separate boot slot
-- Boots live in their own slot (not a mythic slot), cast with the RIGHT MOUSE button.
ItemDefinitions.BOOT_SLOT = 3
ItemDefinitions.BOOT_KEY = "M2" -- AbilityRequest slot name for the boot skill
ItemDefinitions.SELL_RATIO = 0.5 -- mythics sell back for half price

----------------------------------------------------------------------------
-- Ability registry. Targeting: "Unit" (click an enemy), "Point" (ground target),
-- "Direction" (toward cursor), "Self".
----------------------------------------------------------------------------
ItemDefinitions.Abilities = {
	HeavyKick = {
		-- area crowd control (every enemy in the cone), valued above the 250g baseline
		Id = "HeavyKick", Name = "Heavy Kick", Targeting = "Direction", Value = 300,
		Cooldown = 12, Damage = { AD = 1.8 }, Range = 9, Arc = 120, Stun = 1.2,
		Color = Color3.fromRGB(255, 170, 70),
		Summary = "Stomp-kick the ground in front of you: EVERY enemy in a wide cone takes physical damage and is stunned for 1.2 sec.",
	},
	PointStrike = {
		Id = "PointStrike", Name = "Point Strike", Targeting = "Unit",
		Cooldown = 10, Damage = { AD = 4.3 }, Range = 24,
		Color = Color3.fromRGB(170, 90, 255),
		Summary = "Select an enemy, then strike it for a burst of physical damage.",
	},
	WindPull = {
		Id = "WindPull", Name = "Wind Pull", Targeting = "Point",
		Cooldown = 12, Damage = { AD = 1.5 }, TrueDamage = true, Range = 22, Radius = 11, Duration = 0.6, PullDistance = 9,
		Color = Color3.fromRGB(150, 230, 255),
		Summary = "Create a powerful gust at the target point that pulls nearby enemies toward its center.",
	},
	SpikedScale = {
		Id = "SpikedScale", Name = "Spiked Scale", Targeting = "Self",
		Cooldown = 18, Duration = 5, ReflectPercent = 0.5,
		Color = Color3.fromRGB(230, 90, 60),
		Summary = "Harden your armor: reflect 50% of the damage you take from enemy attacks back to the attacker.",
	},
	CleavingArc = {
		Id = "CleavingArc", Name = "Cleaving Arc", Targeting = "Direction",
		Cooldown = 8, Damage = { AD = 2.9 }, Range = 9, Arc = 140,
		Color = Color3.fromRGB(255, 120, 80),
		Summary = "Sweep your weapon in a wide arc, hitting every enemy in front of you.",
	},
	Bulwark = {
		Id = "Bulwark", Name = "Bulwark", Targeting = "Self",
		Cooldown = 16, Shield = { HP = 0.3 }, Duration = 4,
		Color = Color3.fromRGB(255, 220, 120),
		Summary = "Raise a holy ward that absorbs incoming damage.",
	},
	Blink = {
		Id = "Blink", Name = "Shadow Blink", Targeting = "Direction",
		Cooldown = 12, Range = 14,
		Color = Color3.fromRGB(120, 110, 200),
		Summary = "Vanish and reappear a short distance toward the cursor.",
	},
	-- Assassin --------------------------------------------------------------------
	ShadowDash = {
		Id = "ShadowDash", Name = "Shadow Dash", Targeting = "Direction",
		Cooldown = 9, Damage = { AD = 2.0 }, Range = 24, Width = 3.5, -- same dash length as Shadow Step (Q)
		Color = Color3.fromRGB(150, 70, 220),
		Summary = "Dash through enemies, slashing everything along the path.",
	},
	SmokeVeil = {
		Id = "SmokeVeil", Name = "Smoke Bomb", Targeting = "Self",
		Cooldown = 16, Duration = 4, Radius = 9, BlindsEnemies = true,
		Color = Color3.fromRGB(110, 110, 130),
		Summary = "Throw down a smoke cloud at your feet. Enemies standing inside it miss every basic attack (0 damage).",
	},
	-- Mage ------------------------------------------------------------------------
	Fireball = {
		Id = "Fireball", Name = "Fireball", Targeting = "Direction", Value = 300,
		Cooldown = 7, ManaCost = 50, Damage = { MP = 3.1 }, TrueDamage = true, Range = 42, Speed = 70, ExplosionRadius = 5, SplashPercent = 0.5,
		Color = Color3.fromRGB(255, 120, 40),
		Summary = "Hurl a ball of fire that explodes on the first enemy it hits (or where it lands): full damage to that enemy and 50% to every other enemy within 5 studs.",
	},
	FrostNova = {
		Id = "FrostNova", Name = "Frost Nova", Targeting = "Self",
		Cooldown = 14, Damage = { AD = 2.0 }, TrueDamage = true, Radius = 10, Stun = 1,
		Color = Color3.fromRGB(150, 220, 255),
		Summary = "Freeze every enemy around you, damaging and stunning them.",
	},
	-- Marksman --------------------------------------------------------------------
	PiercingArrow = {
		Id = "PiercingArrow", Name = "Piercing Arrow", Targeting = "Direction",
		Cooldown = 9, Damage = { AD = 4.5 }, Range = 65, Speed = 120,
		Color = Color3.fromRGB(210, 255, 120),
		Summary = "Loose a heavy arrow that pierces through every enemy in a line.",
	},
	Tumble = {
		Id = "Tumble", Name = "Tumble", Targeting = "Direction",
		Cooldown = 8, Range = 10, Empower = 1.6, Duration = 3,
		Color = Color3.fromRGB(120, 230, 150),
		Summary = "Roll toward the cursor; your next attack within 3 sec deals 60% more damage.",
	},
	-- Tank ------------------------------------------------------------------------
	ShieldBash = {
		Id = "ShieldBash", Name = "Shield Bash", Targeting = "Direction",
		Cooldown = 12, Damage = { AD = 1.0, HP = 0.05 }, Range = 8, Arc = 110, Stun = 1,
		Color = Color3.fromRGB(120, 170, 255),
		Summary = "Slam your shield forward, damaging and stunning every enemy in front of you.",
	},
	RallyingHorn = {
		Id = "RallyingHorn", Name = "Rallying Horn", Targeting = "Self",
		Cooldown = 20, Shield = { HP = 0.13 }, Radius = 16, Duration = 4,
		Color = Color3.fromRGB(255, 210, 110),
		Summary = "Sound the war horn: you and nearby allies gain a damage-absorbing shield.",
	},
	-- Fighter ---------------------------------------------------------------------
	Whirlwind = {
		Id = "Whirlwind", Name = "Whirlwind", Targeting = "Self",
		Cooldown = 10, Damage = { AD = 2.7 }, Radius = 7,
		Color = Color3.fromRGB(255, 150, 80),
		Summary = "Spin with your weapon, striking every enemy around you.",
	},
	CrushingLeap = {
		Id = "CrushingLeap", Name = "Crushing Leap", Targeting = "Point",
		Cooldown = 13, Damage = { AD = 1.6, HP = 0.04 }, Range = 16, Radius = 6, Stun = 0.5,
		Color = Color3.fromRGB(230, 130, 60),
		Summary = "Leap to the target point and crash down, damaging and briefly stunning enemies.",
	},
	-- Attack speed items ----------------------------------------------------------
	Frenzy = {
		Id = "Frenzy", Name = "Frenzy", Targeting = "Self",
		Cooldown = 14, Duration = 5, AttackSpeedBoost = 0.5,
		Color = Color3.fromRGB(180, 200, 100),
		Summary = "Enter a frenzy, attacking 50% faster for 5 seconds.",
	},
	BladeFlurry = {
		Id = "BladeFlurry", Name = "Blade Flurry", Targeting = "Direction",
		Cooldown = 8, Damage = { AD = 2.0 }, Range = 8, Arc = 130,
		Color = Color3.fromRGB(100, 50, 130),
		Summary = "Spin your blades in a wide arc, hitting every enemy in front of you.",
	},
	ArcaneSurge = {
		Id = "ArcaneSurge", Name = "Arcane Surge", Targeting = "Self",
		Cooldown = 12, Damage = { AD = 2.75 }, TrueDamage = true, Radius = 9,
		Color = Color3.fromRGB(100, 60, 180),
		Summary = "Unleash a surge of arcane energy, damaging all nearby enemies.",
	},
	Quickdraw = {
		Id = "Quickdraw", Name = "Quickdraw", Targeting = "Direction",
		Cooldown = 9, Damage = { AD = 4.3 }, Range = 50, Speed = 100,
		Color = Color3.fromRGB(90, 160, 70),
		Summary = "Fire a quick piercing shot that travels faster than a normal arrow.",
	},
	IronFrenzy = {
		Id = "IronFrenzy", Name = "Iron Frenzy", Targeting = "Self",
		Cooldown = 14, Shield = { HP = 0.18 }, Duration = 4, AttackSpeedBoost = 0.3,
		Color = Color3.fromRGB(80, 100, 140),
		Summary = "Raise your guard and gain a shield plus 30% attack speed for 4 seconds.",
	},
	BloodFury = {
		Id = "BloodFury", Name = "Blood Fury", Targeting = "Self",
		Cooldown = 10, Damage = { AD = 2.0, HP = 0.04 }, Radius = 7, Duration = 4, AttackSpeedBoost = 0.5,
		Color = Color3.fromRGB(160, 60, 50),
		Summary = "Strike all nearby enemies and enter a blood fury, attacking 50% faster for 4 seconds.",
	},
	-- Reworked mythic skills: every Mage skill is ranged and every skill of a class is different.
	-- (FrostNova, ArcaneSurge, BladeFlurry, Quickdraw and BloodFury above are no longer on any item.)
	GlacialPrison = {
		Id = "GlacialPrison", Name = "Glacial Prison", Targeting = "Point", Value = 350,
		Cooldown = 13, ManaCost = 70, Damage = { MP = 2.2 }, TrueDamage = true, Range = 36, Radius = 7, Delay = 0.5, Stun = 1.2,
		Color = Color3.fromRGB(150, 220, 255),
		Summary = "Target an area up to 36 studs away: after 0.5 sec ice erupts there, damaging every enemy inside and freezing them (stun) for 1.2 sec.",
	},
	ArcaneBarrage = {
		Id = "ArcaneBarrage", Name = "Arcane Barrage", Targeting = "Unit", Value = 350,
		Cooldown = 10, ManaCost = 60, Damage = { MP = 1.1 }, TrueDamage = true, Range = 40, Bolts = 3, Interval = 0.18,
		Color = Color3.fromRGB(170, 110, 255),
		Summary = "Select an enemy up to 40 studs away and blast it with 3 homing arcane bolts (damage per bolt below).",
	},
	FanOfKnives = {
		Id = "FanOfKnives", Name = "Fan of Knives", Targeting = "Direction", Value = 300,
		Cooldown = 9, Damage = { AD = 0.7 }, Range = 20, Speed = 80, Knives = 5, Spread = 40,
		Color = Color3.fromRGB(200, 200, 220),
		Summary = "Throw 5 knives in a fan toward the cursor. Each knife damages the first enemy it hits - up close several knives hit the same enemy.",
	},
	RapidVolley = {
		Id = "RapidVolley", Name = "Rapid Volley", Targeting = "Direction", Value = 300,
		Cooldown = 9, Damage = { AD = 1.4 }, Range = 55, Speed = 110, Arrows = 3, Interval = 0.15,
		Color = Color3.fromRGB(120, 200, 90),
		Summary = "Fire 3 arrows in quick succession toward the cursor; each arrow hits the first enemy in its path.",
	},
	DrumsOfWar = {
		Id = "DrumsOfWar", Name = "Drums of War", Targeting = "Self", Value = 300,
		Cooldown = 16, Duration = 5, Radius = 14, AttackSpeedBoost = 0.35, HasteBonus = 0.15, AffectsAllies = true,
		SlowRadius = 8, Slow = 0.3, SlowDuration = 2,
		Color = Color3.fromRGB(200, 70, 50),
		Summary = "Beat the war drums: you and allies within 14 studs gain +35% attack speed and +15% move speed for 5 sec; enemies within 8 studs are slowed by 30% for 2 sec.",
	},
	-- Any class -------------------------------------------------------------------
	SummonGolem = {
		Id = "SummonGolem", Name = "Summon Golem", Targeting = "Point",
		Cooldown = 40, Duration = 20, Range = 28, Radius = 9, Stun = 1.4, Damage = { AD = 1.2 },
		Color = Color3.fromRGB(150, 200, 120),
		Summary = "Hurl a stone golem to the target point: it crashes down, damaging and stunning every enemy within 9 studs for 1.4 sec, then fights whatever you attack.",
	},

	-- Boot skills (right mouse). Each class has 5 boots: crowd control, attack speed,
	-- movement, damage and mobility. Value = the skill's gold value when it is worth more
	-- than the SKILL_VALUE baseline (combined effects, large / long CC, point-and-click,
	-- reliable escapes - see ReplicatedStorage.GameConfig.SharedGameRules).
	-- HasteBonus = +move speed (0.35 = +35%) for HasteDuration (or Duration) seconds.
	-- Assassin -----------------------------------------------------------------------
	CripplingStrike = {
		Id = "CripplingStrike", Name = "Crippling Strike", Targeting = "Direction",
		Cooldown = 11, Damage = { AD = 1.3 }, Range = 8, Arc = 100, Slow = 0.5, SlowDuration = 2.5,
		Color = Color3.fromRGB(150, 70, 200),
		Summary = "Slash the enemies in front of you, damaging them and slowing them by 50% for 2.5 sec.",
	},
	BladeDance = {
		Id = "BladeDance", Name = "Blade Dance", Targeting = "Self", Value = 300,
		Cooldown = 14, Duration = 4, AttackSpeedBoost = 0.5, HasteBonus = 0.2,
		Color = Color3.fromRGB(190, 90, 230),
		Summary = "Start a blade dance: +50% attack speed and +20% move speed for 4 sec.",
	},
	Vanish = {
		Id = "Vanish", Name = "Vanish", Targeting = "Self", Value = 300,
		Cooldown = 18, Duration = 3, HasteBonus = 0.35, Stealth = true,
		Color = Color3.fromRGB(90, 70, 130),
		Summary = "Melt into the shadows: become invisible and gain +35% move speed for 3 sec. Attacking reveals you.",
	},
	ShadeLeap = {
		Id = "ShadeLeap", Name = "Shade Leap", Targeting = "Unit", Value = 300,
		Cooldown = 12, Range = 20,
		Color = Color3.fromRGB(120, 60, 180),
		Summary = "Select an enemy: step through the shadows and appear right behind it.",
	},
	-- Mage ---------------------------------------------------------------------------
	GaleBurst = {
		Id = "GaleBurst", Name = "Gale Burst", Targeting = "Point",
		Cooldown = 12, ManaCost = 60, Damage = { MP = 1.5 }, TrueDamage = true, Range = 22, Radius = 9, PushDistance = 10, Duration = 0.35,
		Color = Color3.fromRGB(150, 230, 255),
		Summary = "Detonate a gale at the target point: enemies caught in it take damage and are hurled away from its center.",
	},
	ArcaneTempo = {
		Id = "ArcaneTempo", Name = "Arcane Tempo", Targeting = "Self", Value = 300,
		Cooldown = 14, ManaCost = 50, Damage = { MP = 1.2 }, TrueDamage = true, Radius = 7, Duration = 5, AttackSpeedBoost = 0.4,
		Color = Color3.fromRGB(140, 110, 255),
		Summary = "Release an arcane pulse that damages nearby enemies, then gain +40% attack speed for 5 sec.",
	},
	Tailwind = {
		Id = "Tailwind", Name = "Tailwind", Targeting = "Self", Value = 300,
		Cooldown = 18, ManaCost = 40, Duration = 4, HasteBonus = 0.35, Radius = 14, AffectsAllies = true,
		Color = Color3.fromRGB(170, 240, 230),
		Summary = "Call a tailwind: you and nearby allies gain +35% move speed for 4 sec.",
	},
	SearingRay = {
		Id = "SearingRay", Name = "Searing Ray", Targeting = "Direction",
		Cooldown = 9, ManaCost = 50, Damage = { MP = 2.4 }, TrueDamage = true, Range = 24, Width = 2.5,
		Color = Color3.fromRGB(255, 130, 50),
		Summary = "Fire a searing ray that burns every enemy in a line (stops at walls).",
	},
	PhaseShift = {
		Id = "PhaseShift", Name = "Phase Shift", Targeting = "Direction", Value = 300,
		Cooldown = 13, ManaCost = 40, Range = 16, Shield = { HP = 0.12 }, Duration = 2,
		Color = Color3.fromRGB(120, 170, 255),
		Summary = "Blink toward the cursor and wrap yourself in a shield for 2 sec.",
	},
	-- Marksman -----------------------------------------------------------------------
	PinningShot = {
		Id = "PinningShot", Name = "Pinning Shot", Targeting = "Direction", Value = 300,
		Cooldown = 12, Damage = { AD = 1.4 }, Range = 32, Width = 2, Stun = 1.2,
		Color = Color3.fromRGB(200, 240, 120),
		Summary = "Fire a heavy bolt: the first enemy in its path takes damage and is pinned in place (stunned) for 1.2 sec.",
	},
	DeadeyeRhythm = {
		Id = "DeadeyeRhythm", Name = "Deadeye Rhythm", Targeting = "Self", Value = 300,
		Cooldown = 14, Duration = 5, AttackSpeedBoost = 0.45, Empower = 1.8,
		Color = Color3.fromRGB(230, 220, 110),
		Summary = "Find your rhythm: +45% attack speed for 5 sec and your next attack deals 80% more damage.",
	},
	EvasiveStride = {
		Id = "EvasiveStride", Name = "Evasive Stride", Targeting = "Self", Value = 300,
		Cooldown = 15, Duration = 3, HasteBonus = 0.45, Shield = { HP = 0.1 },
		Color = Color3.fromRGB(140, 230, 170),
		Summary = "Break into a stride: +45% move speed and a damage-absorbing shield for 3 sec.",
	},
	RainOfArrows = {
		Id = "RainOfArrows", Name = "Rain of Arrows", Targeting = "Point",
		Cooldown = 11, Damage = { AD = 2.6 }, Range = 34, Radius = 7, Delay = 0.6,
		Color = Color3.fromRGB(170, 210, 90),
		Summary = "Call a volley on the target area: after 0.6 sec arrows strike every enemy inside.",
	},
	-- Tank ---------------------------------------------------------------------------
	EarthenShackles = {
		Id = "EarthenShackles", Name = "Earthen Shackles", Targeting = "Self", Value = 350,
		Cooldown = 16, Radius = 8, Stun = 1.0, StunPerHP = 0.001, StunMax = 3.5,
		Color = Color3.fromRGB(170, 130, 80),
		Summary = "Chain every enemy around you to the ground. The stun lasts longer the more max health you have.",
	},
	ThornedRhythm = {
		Id = "ThornedRhythm", Name = "Thorned Rhythm", Targeting = "Self", Value = 300,
		Cooldown = 16, Duration = 5, AttackSpeedBoost = 0.35, ReflectPercent = 0.25,
		Color = Color3.fromRGB(200, 110, 70),
		Summary = "For 5 sec: +35% attack speed and reflect 25% of the damage you take back to the attacker.",
	},
	UnstoppableMarch = {
		Id = "UnstoppableMarch", Name = "Unstoppable March", Targeting = "Self", Value = 300,
		Cooldown = 18, Duration = 4, HasteBonus = 0.3, Unstoppable = true, UsableWhileStunned = true,
		Color = Color3.fromRGB(230, 190, 90),
		Summary = "Break free of stuns (even while stunned) and march on: immune to stuns and +30% move speed for 4 sec.",
	},
	ShoulderCharge = {
		Id = "ShoulderCharge", Name = "Shoulder Charge", Targeting = "Direction", Value = 300,
		Cooldown = 12, Damage = { AD = 0.8, HP = 0.03 }, Range = 15, Width = 3.5, KnockDistance = 5,
		Color = Color3.fromRGB(120, 150, 210),
		Summary = "Charge toward the cursor, damaging every enemy in your path and knocking it aside.",
	},
	-- Fighter ------------------------------------------------------------------------
	BattleTrance = {
		Id = "BattleTrance", Name = "Battle Trance", Targeting = "Self", Value = 300,
		Cooldown = 15, Duration = 5, AttackSpeedBoost = 0.4, Heal = { HP = 0.08 },
		Color = Color3.fromRGB(255, 110, 70),
		Summary = "Fall into a battle trance: heal instantly and gain +40% attack speed for 5 sec.",
	},
	Warpath = {
		Id = "Warpath", Name = "Warpath", Targeting = "Self", Value = 300,
		Cooldown = 14, Duration = 4, HasteBonus = 0.4, Empower = 1.5,
		Color = Color3.fromRGB(240, 150, 60),
		Summary = "Charge into battle: +40% move speed for 4 sec and your next attack deals 50% more damage.",
	},
	SkullSplitter = {
		Id = "SkullSplitter", Name = "Skull Splitter", Targeting = "Unit", Value = 300,
		Cooldown = 11, Damage = { AD = 2.8 }, Range = 10, ExecuteThreshold = 0.4, ExecuteBonus = 0.5,
		Color = Color3.fromRGB(220, 70, 50),
		Summary = "Leap at an enemy and bring your weapon down for heavy damage - 50% more if it is below 40% health.",
	},
	LeapingBound = {
		Id = "LeapingBound", Name = "Leaping Bound", Targeting = "Direction", Value = 300,
		Cooldown = 11, Range = 15, HasteBonus = 0.3, Duration = 2,
		Color = Color3.fromRGB(230, 160, 80),
		Summary = "Bound toward the cursor, then gain +30% move speed for 2 sec.",
	},
}

-- The summoned golem (used by SummonGolem; numbers shown in the tooltip).
-- Its health and hit damage scale with the SUMMONER's stats at cast time.
ItemDefinitions.Golem = {
	MaxHealth = { HP = 1.0 }, Armor = 30, Damage = { AD = 1.1 }, AttackCooldown = 1.3, AttackRange = 6,
	AggroRange = 24, LeashRange = 45, MoveSpeed = 17, Lifetime = 20,
	KillReward = 25, -- gold for the enemy hero who destroys it
}

----------------------------------------------------------------------------
-- Mythic items. Class = nil means any class may buy it.
-- Stats are passive bonuses while equipped (same keys as the stat shop items).
----------------------------------------------------------------------------
ItemDefinitions.Items = {
	AssassinBoots = {
		Id = "AssassinBoots", Name = "Assassin Boots", Class = "Assassin", Price = 500,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "PointStrike", BootType = "Damage",
		Stats = { MoveSpeed = 2, AttackDamage = 5 },
		Description = "Soft black leather laced with a poisoned stiletto.",
		Icon = "rbxassetid://115551106221059", Glyph = "AB", Color = Color3.fromRGB(120, 60, 150),
	},
	MageBoots = {
		Id = "MageBoots", Name = "Mage Boots", Class = "Mage", Price = 500,
		-- crowd control boots: Gale Burst pushes enemies AWAY (was Wind Pull, which pulled them in)
		Rarity = "Mythic", SlotType = "Mythic", Ability = "GaleBurst", BootType = "Crowd Control",
		Stats = { MoveSpeed = 2, MaxHealth = 70 },
		Description = "Light enchanted slippers that ride the wind.",
		Icon = "rbxassetid://126166282769730", Glyph = "MB", Color = Color3.fromRGB(80, 150, 220),
	},
	TankBoots = {
		Id = "TankBoots", Name = "Tank Boots", Class = "Tank", Price = 500,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "SpikedScale", BootType = "Damage",
		Stats = { Armor = 9 },
		PassiveReflect = 0.15, -- always reflects 15% of damage taken (Spiked Scale active: 50%)
		Description = "Heavy spiked sabatons forged for the front line.",
		Icon = "rbxassetid://112163977783452", Glyph = "TB", Color = Color3.fromRGB(90, 110, 140),
	},
	FighterBoots = {
		Id = "FighterBoots", Name = "Fighter Boots", Class = "Fighter", Price = 540,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "HeavyKick", BootType = "Crowd Control",
		Stats = { AttackDamage = 7, MoveSpeed = 1 },
		Description = "Iron-shod boots that crack stone with every step.",
		Icon = "rbxassetid://126370718489812", Glyph = "FB", Color = Color3.fromRGB(200, 110, 50),
	},
	WarlordsCleaver = {
		Id = "WarlordsCleaver", Name = "Warlord's Cleaver", Class = nil, Price = 800,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "CleavingArc",
		Stats = { AttackDamage = 18 },
		-- passive: every basic attack also hits enemies around the target for 40% of its damage
		PassiveSplash = { Percent = 0.4, Radius = 6 },
		Description = "A notched war-axe taken from a fallen warlord.",
		Icon = "rbxassetid://124277646603125", Glyph = "WC", Color = Color3.fromRGB(170, 50, 45),
	},
	AegisOfDawn = {
		Id = "AegisOfDawn", Name = "Aegis of Dawn", Class = nil, Price = 800,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "Bulwark",
		Stats = { Armor = 18, MaxHealth = 150 },
		Description = "A sun-blessed shield from the old temple guard.",
		Icon = "rbxassetid://75774526013211", Glyph = "AD", Color = Color3.fromRGB(210, 170, 70),
	},
	PhantomCloak = {
		Id = "PhantomCloak", Name = "Phantom Cloak", Class = nil, Price = 800,
		Rarity = "Mythic", SlotType = "Mythic", Ability = "Blink",
		Stats = { MoveSpeed = 3, AttackDamage = 14 },
		Description = "Woven from shadow; it never quite touches the ground.",
		Icon = "rbxassetid://116991219758866", Glyph = "PC", Color = Color3.fromRGB(70, 70, 110),
	},
}

-- Role items added with the shop reorganisation ----------------------------------
-- Icons rendered in Blender (RuinfallIcons scene) and uploaded to Roblox
local ROLE_ITEM_ICONS = {
	VenomFang = "rbxassetid://101707442493892",
	SmokeBomb = "rbxassetid://140162053076434",
	EmberStaff = "rbxassetid://140253340840581",
	FrostTome = "rbxassetid://104478334195552",
	RangerBoots = "rbxassetid://111615938141120",
	HuntersLongbow = "rbxassetid://105484722033842",
	BastionShield = "rbxassetid://77923159753070",
	WarHorn = "rbxassetid://122918435100711",
	BerserkerAxe = "rbxassetid://118501173542368",
	TitanGauntlets = "rbxassetid://129960918484481",
	GolemHeart = "rbxassetid://84803967950834",
	-- attack speed items
	SwiftBlade = "rbxassetid://73980977846544",
	ShadowBlades = "rbxassetid://97294412152694",
	ArcaneOrb = "rbxassetid://136418105502710",
	Quickbow = "rbxassetid://128197149101795",
	GuardianGauntlets = "rbxassetid://132373731366138",
	WarDrums = "rbxassetid://125634579841217",
}
-- every class's boots go to the boot slot (right mouse), never a mythic slot
local BOOT_ITEMS = { AssassinBoots = true, MageBoots = true, TankBoots = true, FighterBoots = true, RangerBoots = true }
local function addItem(item)
	item.Rarity = "Mythic"
	item.SlotType = BOOT_ITEMS[item.Id] and "Boots" or "Mythic"
	item.Icon = item.Icon or ROLE_ITEM_ICONS[item.Id] or ""
	ItemDefinitions.Items[item.Id] = item
end
addItem({ Id = "VenomFang", Name = "Venom Fang", Class = "Assassin", Price = 800, Ability = "ShadowDash", Stats = { AttackDamage = 22 },
	Description = "A serpent-tooth blade that leaves a trail of shadow.", Glyph = "VF", Color = Color3.fromRGB(90, 40, 120) })
addItem({ Id = "SmokeBomb", Name = "Smoke Bomb Pouch", Class = "Assassin", Price = 700, Ability = "SmokeVeil", Stats = { MoveSpeed = 3, AttackDamage = 10 },
	Description = "Alchemist's powders sewn into a leather pouch.", Glyph = "SB", Color = Color3.fromRGB(70, 70, 85) })
addItem({ Id = "EmberStaff", Name = "Staff of Embers", Class = "Mage", Price = 850, Ability = "Fireball", Stats = { MagicPower = 20, AttackDamage = 6 },
	Description = "The coals in its head never go out.", Glyph = "SE", Color = Color3.fromRGB(170, 70, 30) })
addItem({ Id = "FrostTome", Name = "Frost Tome", Class = "Mage", Price = 880, Ability = "GlacialPrison", Stats = { MagicPower = 14, MaxHealth = 150 },
	Description = "Pages rimed with ice from the northern peaks.", Glyph = "FT", Color = Color3.fromRGB(80, 140, 190) })
addItem({ Id = "RangerBoots", Name = "Ranger Boots", Class = "Marksman", Price = 500, Ability = "Tumble", BootType = "Mobility", Stats = { MoveSpeed = 2, AttackSpeed = 0.08 },
	Description = "Supple hide boots for a hunter who never stands still.", Glyph = "RB", Color = Color3.fromRGB(70, 120, 60) })
addItem({ Id = "HuntersLongbow", Name = "Hunter's Longbow", Class = "Marksman", Price = 800, Ability = "PiercingArrow", Stats = { AttackDamage = 22 },
	Description = "Yew bow strung with drake sinew.", Glyph = "HL", Color = Color3.fromRGB(120, 90, 40) })
addItem({ Id = "BastionShield", Name = "Bastion Shield", Class = "Tank", Price = 800, Ability = "ShieldBash", Stats = { Armor = 18, MaxHealth = 150 },
	Description = "A tower shield studded with iron bosses.", Glyph = "BS", Color = Color3.fromRGB(70, 90, 130) })
addItem({ Id = "WarHorn", Name = "War Horn", Class = "Tank", Price = 750, Ability = "RallyingHorn", Stats = { MaxHealth = 300 },
	Description = "Its call steadies every shield-wall in earshot.", Glyph = "WH", Color = Color3.fromRGB(150, 110, 50) })
addItem({ Id = "BerserkerAxe", Name = "Berserker Axe", Class = "Fighter", Price = 800, Ability = "Whirlwind", Stats = { AttackDamage = 22 },
	Description = "Double-bladed and hungry for a crowd.", Glyph = "BA", Color = Color3.fromRGB(150, 50, 40) })
addItem({ Id = "TitanGauntlets", Name = "Titan Gauntlets", Class = "Fighter", Price = 750, Ability = "CrushingLeap", Stats = { Armor = 15, MaxHealth = 150 },
	Description = "Stone-knuckled gauntlets that shake the earth.", Glyph = "TG", Color = Color3.fromRGB(110, 90, 70) })
addItem({ Id = "GolemHeart", Name = "Golem Heart", Class = nil, Price = 920, Ability = "SummonGolem", Stats = { MaxHealth = 250, Armor = 15 },
	Description = "A rune-carved stone heart that still beats.", Glyph = "GH", Color = Color3.fromRGB(80, 110, 70) })

-- Attack speed items (one per role) ----------------------------------------------
addItem({ Id = "SwiftBlade", Name = "Swift Blade", Class = nil, Price = 780, Ability = "Frenzy", Stats = { AttackSpeed = 0.35 },
	Description = "A feather-light blade that hums with haste.", Glyph = "SB", Color = Color3.fromRGB(180, 200, 100) })
addItem({ Id = "ShadowBlades", Name = "Shadow Blades", Class = "Assassin", Price = 825, Ability = "FanOfKnives", Stats = { AttackSpeed = 0.25, AttackDamage = 6 },
	Description = "Twin daggers that blur in the shadows.", Glyph = "SBD", Color = Color3.fromRGB(100, 50, 130) })
addItem({ Id = "ArcaneOrb", Name = "Arcane Orb", Class = "Mage", Price = 850, Ability = "ArcaneBarrage", Stats = { MagicPower = 16, AttackSpeed = 0.12 },
	Description = "A pulsing orb that quickens the caster's rhythm.", Glyph = "AO", Color = Color3.fromRGB(100, 60, 180) })
addItem({ Id = "Quickbow", Name = "Quickbow", Class = "Marksman", Price = 825, Ability = "RapidVolley", Stats = { AttackSpeed = 0.25, AttackDamage = 6 },
	Description = "A compact bow built for rapid fire.", Glyph = "QB", Color = Color3.fromRGB(90, 160, 70) })
addItem({ Id = "GuardianGauntlets", Name = "Guardian Gauntlets", Class = "Tank", Price = 790, Ability = "IronFrenzy", Stats = { AttackSpeed = 0.25, Armor = 10 },
	Description = "Gauntlets that turn defense into a relentless assault.", Glyph = "GG", Color = Color3.fromRGB(80, 100, 140) })
addItem({ Id = "WarDrums", Name = "War Drums", Class = "Fighter", Price = 840, Ability = "DrumsOfWar", Stats = { AttackSpeed = 0.25, MaxHealth = 100 },
	Description = "A war drum whose beat drives the bearer into a fury.", Glyph = "WD", Color = Color3.fromRGB(160, 60, 50) })

-- Class boots: 5 per class, one of each kind (the first pair of each class is defined above).
-- Price = stat gold + skill gold (ability.Value or SKILL_VALUE), each within 10g.
-- Icon = "" -> the shop / HUD show the 2-letter Glyph until real icons are uploaded.
local function addBoots(item)
	item.SlotType = "Boots"
	BOOT_ITEMS[item.Id] = true
	addItem(item)
end
-- Assassin
addBoots({ Id = "HamstringBoots", Name = "Hamstring Boots", Class = "Assassin", Price = 500, Ability = "CripplingStrike", BootType = "Crowd Control",
	Stats = { AttackDamage = 6, MoveSpeed = 1.5 }, Description = "A hidden blade in the heel, meant for tendons.", Glyph = "HB", Color = Color3.fromRGB(110, 50, 140) })
addBoots({ Id = "BladedancerBoots", Name = "Bladedancer Boots", Class = "Assassin", Price = 550, Ability = "BladeDance", BootType = "Attack Speed",
	Stats = { AttackSpeed = 0.12, MoveSpeed = 1 }, Description = "Silk-wrapped soles for a dance that ends in blood.", Glyph = "BD", Color = Color3.fromRGB(160, 80, 190) })
addBoots({ Id = "SilentTreads", Name = "Silent Treads", Class = "Assassin", Price = 500, Ability = "Vanish", BootType = "Movement",
	Stats = { MoveSpeed = 3 }, Description = "Felt-lined and soundless; the shadows walk with you.", Glyph = "ST", Color = Color3.fromRGB(60, 50, 90) })
addBoots({ Id = "ShadowstepBoots", Name = "Shadowstep Boots", Class = "Assassin", Price = 500, Ability = "ShadeLeap", BootType = "Mobility",
	Stats = { MoveSpeed = 1.5, AttackDamage = 4 }, Description = "Every step lands behind someone.", Glyph = "SS", Color = Color3.fromRGB(90, 45, 140) })
-- Mage
addBoots({ Id = "RunicSandals", Name = "Runic Sandals", Class = "Mage", Price = 550, Ability = "ArcaneTempo", BootType = "Attack Speed",
	Stats = { AttackSpeed = 0.12, MaxHealth = 40 }, Description = "Runes on the straps pulse with every spell.", Glyph = "RS", Color = Color3.fromRGB(110, 80, 220) })
addBoots({ Id = "WindwalkerSlippers", Name = "Windwalker Slippers", Class = "Mage", Price = 500, Ability = "Tailwind", BootType = "Movement",
	Stats = { MoveSpeed = 2, MaxHealth = 40 }, Description = "Stitched from a storm's hem.", Glyph = "WW", Color = Color3.fromRGB(120, 200, 200) })
addBoots({ Id = "CinderTreads", Name = "Cinder Treads", Class = "Mage", Price = 500, Ability = "SearingRay", BootType = "Damage",
	Stats = { MagicPower = 10, MaxHealth = 30 }, Description = "They leave scorched footprints on stone.", Glyph = "CT", Color = Color3.fromRGB(200, 90, 40) })
addBoots({ Id = "BlinkweaveSlippers", Name = "Blinkweave Slippers", Class = "Mage", Price = 500, Ability = "PhaseShift", BootType = "Mobility",
	Stats = { MoveSpeed = 2, MaxHealth = 40 }, Description = "Woven with thread that is only half here.", Glyph = "BW", Color = Color3.fromRGB(90, 130, 230) })
-- Marksman
addBoots({ Id = "TrappersBoots", Name = "Trapper's Boots", Class = "Marksman", Price = 500, Ability = "PinningShot", BootType = "Crowd Control",
	Stats = { MoveSpeed = 2, AttackDamage = 3 }, Description = "Hobnailed boots with a crossbow bolt tucked in each cuff.", Glyph = "TR", Color = Color3.fromRGB(150, 170, 80) })
addBoots({ Id = "QuickstepBoots", Name = "Quickstep Boots", Class = "Marksman", Price = 550, Ability = "DeadeyeRhythm", BootType = "Attack Speed",
	Stats = { AttackSpeed = 0.17 }, Description = "Light enough to keep time with the bowstring.", Glyph = "QS", Color = Color3.fromRGB(200, 190, 90) })
addBoots({ Id = "FleetfootBoots", Name = "Fleetfoot Boots", Class = "Marksman", Price = 500, Ability = "EvasiveStride", BootType = "Movement",
	Stats = { MoveSpeed = 3 }, Description = "Deer-hide boots for hunters who are also hunted.", Glyph = "FF", Color = Color3.fromRGB(100, 180, 120) })
addBoots({ Id = "DeadshotBoots", Name = "Deadshot Boots", Class = "Marksman", Price = 500, Ability = "RainOfArrows", BootType = "Damage",
	Stats = { AttackDamage = 6, AttackSpeed = 0.07 }, Description = "Planted feet, steady aim, arrows like rain.", Glyph = "DS", Color = Color3.fromRGB(130, 160, 60) })
-- Tank
addBoots({ Id = "ShackleGreaves", Name = "Shackle Greaves", Class = "Tank", Price = 500, Ability = "EarthenShackles", BootType = "Crowd Control",
	Stats = { MaxHealth = 90 }, Description = "Chains hang from the ankle-plates, hungry for prisoners.", Glyph = "SG", Color = Color3.fromRGB(130, 110, 80) })
addBoots({ Id = "ThornmarchSabatons", Name = "Thornmarch Sabatons", Class = "Tank", Price = 500, Ability = "ThornedRhythm", BootType = "Attack Speed",
	Stats = { AttackSpeed = 0.1, Armor = 3 }, Description = "Every step drives thorns into the ground - and into attackers.", Glyph = "TS", Color = Color3.fromRGB(150, 90, 60) })
addBoots({ Id = "UnyieldingGreaves", Name = "Unyielding Greaves", Class = "Tank", Price = 500, Ability = "UnstoppableMarch", BootType = "Movement",
	Stats = { MoveSpeed = 1.5, Armor = 6 }, Description = "Nothing has ever made them stop.", Glyph = "UG", Color = Color3.fromRGB(170, 150, 90) })
addBoots({ Id = "RampartSabatons", Name = "Rampart Sabatons", Class = "Tank", Price = 500, Ability = "ShoulderCharge", BootType = "Mobility",
	Stats = { Armor = 6, MaxHealth = 60 }, Description = "A moving wall needs moving feet.", Glyph = "RP", Color = Color3.fromRGB(90, 120, 170) })
-- Fighter
addBoots({ Id = "TrancefireBoots", Name = "Trancefire Boots", Class = "Fighter", Price = 550, Ability = "BattleTrance", BootType = "Attack Speed",
	Stats = { AttackSpeed = 0.12, MaxHealth = 40 }, Description = "Warm to the touch, and warmer in battle.", Glyph = "TF", Color = Color3.fromRGB(210, 90, 60) })
addBoots({ Id = "WarpathBoots", Name = "Warpath Boots", Class = "Fighter", Price = 500, Ability = "Warpath", BootType = "Movement",
	Stats = { MoveSpeed = 2, AttackDamage = 3 }, Description = "Worn by those who run toward the fight.", Glyph = "WP", Color = Color3.fromRGB(200, 130, 60) })
addBoots({ Id = "HeadsmansBoots", Name = "Headsman's Boots", Class = "Fighter", Price = 500, Ability = "SkullSplitter", BootType = "Damage",
	Stats = { AttackDamage = 6, Armor = 3 }, Description = "Black leather, iron toes, and a long list of names.", Glyph = "HS", Color = Color3.fromRGB(150, 50, 45) })
addBoots({ Id = "BoundingGreaves", Name = "Bounding Greaves", Class = "Fighter", Price = 500, Ability = "LeapingBound", BootType = "Mobility",
	Stats = { MoveSpeed = 1.5, Armor = 6 }, Description = "Spring-steel plates that throw you across the field.", Glyph = "BG", Color = Color3.fromRGB(180, 120, 70) })

for id in pairs(BOOT_ITEMS) do
	if ItemDefinitions.Items[id] then
		ItemDefinitions.Items[id].SlotType = "Boots"
	end
end

-- Shop organisation: one section per role ("General" = any class)
ItemDefinitions.Roles = { "General", "Assassin", "Mage", "Marksman", "Tank", "Fighter" }
ItemDefinitions.RoleItems = {
	General = { "WarlordsCleaver", "AegisOfDawn", "PhantomCloak", "GolemHeart", "SwiftBlade" },
	Assassin = { "AssassinBoots", "VenomFang", "SmokeBomb", "ShadowBlades" },
	Mage = { "MageBoots", "EmberStaff", "FrostTome", "ArcaneOrb" },
	Marksman = { "RangerBoots", "HuntersLongbow", "Quickbow" },
	Tank = { "TankBoots", "BastionShield", "WarHorn", "GuardianGauntlets" },
	Fighter = { "FighterBoots", "BerserkerAxe", "TitanGauntlets", "WarDrums" },
}
-- Boots per class, one of each kind, in the order of BootTypes (shown in the shop's BOOTS section)
ItemDefinitions.BootTypes = { "Crowd Control", "Attack Speed", "Movement", "Damage", "Mobility" }
ItemDefinitions.RoleBoots = {
	Assassin = { "HamstringBoots", "BladedancerBoots", "SilentTreads", "AssassinBoots", "ShadowstepBoots" },
	Mage = { "MageBoots", "RunicSandals", "WindwalkerSlippers", "CinderTreads", "BlinkweaveSlippers" },
	Marksman = { "TrappersBoots", "QuickstepBoots", "FleetfootBoots", "DeadshotBoots", "RangerBoots" },
	Tank = { "ShackleGreaves", "ThornmarchSabatons", "UnyieldingGreaves", "TankBoots", "RampartSabatons" },
	Fighter = { "FighterBoots", "TrancefireBoots", "WarpathBoots", "HeadsmansBoots", "BoundingGreaves" },
}
----------------------------------------------------------------------------
-- PASSIVE ITEMS: no E / R / RMB ability - they work automatically while equipped.
-- Up to MAX_PASSIVE_SLOTS (3) different passive items; no duplicates. They live in the
-- same Items table (SlotType = "Passive") so every lookup (GetItem, stats, sell value)
-- works unchanged. Add one with ItemDefinitions.AddPassive({ ... }):
--   Id, Name, Class (nil = any class), Price, Stats = { MaxHealth = 60, ... } (same keys as
--   mythics), Passive = { Name = "Bloodthirst", Description = "...", Value = gold value of
--   the effect (default PASSIVE_VALUE), ...effect parameters read by the server },
--   Description (flavour), Icon ("" -> Glyph), Glyph, Color.
-- Stats apply through CombatService.ComputeShopBonuses; special effects are read by the
-- server combat code from item.Passive (see CombatService.GetEquippedPassives).
----------------------------------------------------------------------------
ItemDefinitions.MAX_PASSIVE_SLOTS = 3
-- Sell / slot index of passive slot N is PASSIVE_SLOT_BASE + N (4, 5, 6): after E (1), R (2), boots (3)
ItemDefinitions.PASSIVE_SLOT_BASE = 3
ItemDefinitions.RolePassives = { General = {}, Assassin = {}, Mage = {}, Marksman = {}, Tank = {}, Fighter = {} }

function ItemDefinitions.AddPassive(item)
	item.SlotType = "Passive"
	item.Rarity = "Passive"
	item.Icon = item.Icon or ""
	item.Ability = nil -- passives never have an activated skill
	ItemDefinitions.Items[item.Id] = item
	local role = item.Class or "General"
	ItemDefinitions.RolePassives[role] = ItemDefinitions.RolePassives[role] or {}
	table.insert(ItemDefinitions.RolePassives[role], item.Id)
	return item
end

-- The 50 passive items. Name / price / stats / passive name + text are the design spec.
-- Passive.Effect names the server handler (ServerScriptService.PassiveService); the other
-- Passive fields are that effect's numbers. Passive.Details lists numbers the spec left open.
-- Passive.Value (gold value of the effect) defaults to Price - stat value (SharedGameRules).
local A = ItemDefinitions.AddPassive

-- GENERAL (any class) --------------------------------------------------------------------
A({ Id = "BloodstonePendant", Name = "Bloodstone Pendant", Price = 550, Stats = { MaxHealth = 100, AttackDamage = 4 },
	Passive = { Name = "Blood Pact", Description = "5% of damage dealt to enemy heroes is converted into healing.",
		Effect = "BloodPact", HealPercent = 0.05 },
	Glyph = "BP", Color = Color3.fromRGB(170, 30, 45) })
A({ Id = "Emberglass", Name = "Emberglass", Price = 600, Stats = { MagicPower = 8, MaxHealth = 80 },
	Passive = { Name = "Scorching Touch", Description = "Ability damage applies Burn for 3 seconds.",
		Details = "Burn: 12 damage/sec.", Effect = "ScorchingTouch", DPS = 12, Duration = 3 },
	Glyph = "EG", Color = Color3.fromRGB(230, 110, 40) })
A({ Id = "MoonlitPendant", Name = "Moonlit Pendant", Price = 550, Stats = { CooldownReduction = 0.05, Mana = 100 },
	Passive = { Name = "Moonwell", Description = "Regenerate 2% missing mana every 5 seconds.",
		Effect = "Moonwell", Interval = 5, MissingPercent = 0.02 },
	Glyph = "MP", Color = Color3.fromRGB(120, 150, 230) })
A({ Id = "HuntersEye", Name = "Hunter's Eye", Price = 500, Stats = { AttackDamage = 5, AttackSpeed = 0.05 },
	Passive = { Name = "True Sight", Description = "Reveals nearby enemy units that are invisible.",
		Details = "Reveal range: 16 studs (your whole team sees and can target them).", Effect = "TrueSight", Radius = 16 },
	Glyph = "HE", Color = Color3.fromRGB(200, 170, 70) })
A({ Id = "ObsidianShard", Name = "Obsidian Shard", Price = 650, Stats = { AttackDamage = 8, MagicPower = 8 },
	Passive = { Name = "Rupture", Description = "Your next damaging attack or ability every 6 seconds ignores 15% of the target's defenses.",
		Details = "Defenses = armor and magic defense.", Effect = "Rupture", Interval = 6, Ignore = 0.15 },
	Glyph = "OS", Color = Color3.fromRGB(70, 60, 90) })
A({ Id = "SoulFurnace", Name = "Soul Furnace", Price = 650, Stats = { MaxHealth = 150 },
	Passive = { Name = "Soul Harvest", Description = "When an enemy hero dies near you, permanently gain 3 maximum HP, up to a match-based cap.",
		Details = "Near = within 20 studs. Cap: +60 max HP per match.", Effect = "SoulHarvest", Radius = 20, PerKill = 3, Cap = 60 },
	Glyph = "SF", Color = Color3.fromRGB(150, 60, 160) })
A({ Id = "FrostfirePendant", Name = "Frostfire Pendant", Price = 600, Stats = { MaxHealth = 100, AttackDamage = 5 },
	Passive = { Name = "Chilling Flame", Description = "Your first attack against an enemy slows them by 20% for 1.5 sec.",
		Details = "Counts as a first attack again after 5 sec without hitting that enemy.", Effect = "ChillingFlame", Slow = 0.2, Duration = 1.5, Reset = 5 },
	Glyph = "FP", Color = Color3.fromRGB(110, 190, 230) })
A({ Id = "ManaforgedRing", Name = "Manaforged Ring", Price = 500, Stats = { Mana = 200 },
	Passive = { Name = "Overflow", Description = "When above 80% mana, gain 8% bonus ability damage.",
		Effect = "Overflow", Threshold = 0.8, Bonus = 0.08 },
	Glyph = "MR", Color = Color3.fromRGB(70, 120, 220) })
A({ Id = "WarlocksCoin", Name = "Warlock's Coin", Price = 550, Stats = { AttackDamage = 6, MagicPower = 6 },
	Passive = { Name = "Bounty", Description = "Killing an enemy hero grants bonus gold.",
		Details = "+50 gold per hero kill.", Effect = "Bounty", Gold = 50 },
	Glyph = "WC", Color = Color3.fromRGB(210, 170, 50) })
A({ Id = "ChronoGear", Name = "Chrono Gear", Price = 700, Stats = { CooldownReduction = 0.10 },
	Passive = { Name = "Rewind", Description = "Reduces your remaining basic ability cooldowns by 1 second whenever you get an assist.",
		Details = "Basic abilities = Q, E and R.", Effect = "Rewind", Seconds = 1 },
	Glyph = "CG", Color = Color3.fromRGB(180, 150, 90) })

-- ASSASSIN ----------------------------------------------------------------------------------
A({ Id = "ExecutionersTalon", Name = "Executioner's Talon", Class = "Assassin", Price = 600, Stats = { AttackDamage = 15 },
	Passive = { Name = "Mercyless", Description = "Deal 15% increased damage to enemies below 25% HP.",
		Effect = "Mercyless", Threshold = 0.25, Bonus = 0.15 },
	Glyph = "ET", Color = Color3.fromRGB(140, 30, 50) })
A({ Id = "Nightfang", Name = "Nightfang", Class = "Assassin", Price = 650, Stats = { AttackDamage = 18 },
	Passive = { Name = "Predator's Mark", Description = "Damaging an enemy who has no nearby allies marks them for 4 seconds, increasing your damage against them.",
		Details = "+10% damage. No nearby allies = no allied hero within 12 studs.", Effect = "PredatorsMark", AllyRadius = 12, Duration = 4, Bonus = 0.10 },
	Glyph = "NF", Color = Color3.fromRGB(60, 40, 110) })
A({ Id = "Venomclaw", Name = "Venomclaw", Class = "Assassin", Price = 600, Stats = { AttackDamage = 10, AttackSpeed = 0.05 },
	Passive = { Name = "Toxic Wound", Description = "Attacks apply poison.",
		Details = "Poison: 8 damage/sec for 4 sec.", Effect = "ToxicWound", DPS = 8, Duration = 4 },
	Glyph = "VC", Color = Color3.fromRGB(90, 170, 60) })
A({ Id = "Bloodletter", Name = "Bloodletter", Class = "Assassin", Price = 650, Stats = { AttackDamage = 16 },
	Passive = { Name = "Hemorrhage", Description = "Every third consecutive attack applies a strong bleed.",
		Details = "Bleed: 15 damage/sec for 3 sec. Consecutive = same target, within 3 sec.", Effect = "Hemorrhage", Hits = 3, Window = 3, DPS = 15, Duration = 3 },
	Glyph = "BL", Color = Color3.fromRGB(180, 20, 30) })
A({ Id = "Ghoststeel", Name = "Ghoststeel", Class = "Assassin", Price = 700, Stats = { AttackDamage = 18, MoveSpeedPercent = 0.05 },
	Passive = { Name = "Unseen Blade", Description = "After not attacking for 4 seconds, your next attack deals bonus true damage.",
		Details = "+30 true damage (ignores armor).", Effect = "UnseenBlade", Idle = 4, TrueDamage = 30 },
	Glyph = "GS", Color = Color3.fromRGB(150, 170, 200) })
A({ Id = "Widowmaker", Name = "Widowmaker", Class = "Assassin", Price = 700, Stats = { AttackDamage = 15, CritChance = 0.10 },
	Passive = { Name = "Vulnerable", Description = "Critical hits reduce the target's healing received by 30% for 3 seconds.",
		Effect = "Vulnerable", HealCut = 0.3, Duration = 3 },
	Glyph = "WM", Color = Color3.fromRGB(90, 20, 60) })
A({ Id = "Soulpiercer", Name = "Soulpiercer", Class = "Assassin", Price = 750, Stats = { AttackDamage = 20 },
	Passive = { Name = "Armor Break", Description = "Damaging the same enemy 3 times reduces their armor by 15% for 4 seconds.",
		Details = "Hits count while they land within 4 sec of each other.", Effect = "ArmorBreak", Hits = 3, Window = 4, Shred = 0.15, Duration = 4 },
	Glyph = "SP", Color = Color3.fromRGB(120, 80, 170) })
A({ Id = "CrimsonClaw", Name = "Crimson Claw", Class = "Assassin", Price = 650, Stats = { AttackDamage = 14, Lifesteal = 0.08 },
	Passive = { Name = "Blood Rush", Description = "Killing an enemy grants 25% movement speed for 2 seconds.",
		Details = "Any enemy unit (heroes, minions, monsters).", Effect = "KillRush", Haste = 0.25, Duration = 2 },
	Glyph = "CC", Color = Color3.fromRGB(200, 40, 60) })

-- MAGE --------------------------------------------------------------------------------------
A({ Id = "InfernalCodex", Name = "Infernal Codex", Class = "Mage", Price = 650, Stats = { MagicPower = 18 },
	Passive = { Name = "Combustion", Description = "Hitting an enemy with an ability three times causes an explosion around them.",
		Details = "Explosion: 60 magic damage within 8 studs. Hits count within 5 sec of each other.", Effect = "Combustion", Hits = 3, Window = 5, Damage = 60, Radius = 8 },
	Glyph = "IC", Color = Color3.fromRGB(220, 80, 30) })
A({ Id = "WinterCrown", Name = "Winter Crown", Class = "Mage", Price = 700, Stats = { MagicPower = 12, MaxHealth = 100 },
	Passive = { Name = "Deep Freeze", Description = "Abilities that damage an enemy twice within 3 seconds apply a 30% slow.",
		Details = "Slow lasts 1.5 sec.", Effect = "DeepFreeze", Window = 3, Slow = 0.3, Duration = 1.5 },
	Glyph = "WI", Color = Color3.fromRGB(140, 200, 240) })
A({ Id = "VoidLantern", Name = "Void Lantern", Class = "Mage", Price = 700, Stats = { MagicPower = 20 },
	Passive = { Name = "Magic Fracture", Description = "Ability damage reduces enemy Magic Defense by 10% for 3 seconds.",
		Effect = "MagicFracture", Shred = 0.10, Duration = 3 },
	Glyph = "VL", Color = Color3.fromRGB(80, 40, 140) })
A({ Id = "ManaCrystal", Name = "Mana Crystal", Class = "Mage", Price = 550, Stats = { Mana = 250, MagicPower = 5 },
	Passive = { Name = "Arcane Reserve", Description = "Every 100 missing mana increases your ability damage by 1%, up to 10%.",
		Effect = "ArcaneReserve", Per100 = 0.01, Max = 0.10 },
	Glyph = "MC", Color = Color3.fromRGB(60, 140, 230) })
A({ Id = "StarfallLens", Name = "Starfall Lens", Class = "Mage", Price = 750, Stats = { MagicPower = 22 },
	Passive = { Name = "Astral Strike", Description = "Every fourth ability hit calls down a meteor on the target.",
		Details = "Meteor: 80 magic damage within 6 studs after 0.6 sec.", Effect = "AstralStrike", Hits = 4, Damage = 80, Radius = 6, Delay = 0.6 },
	Glyph = "SL", Color = Color3.fromRGB(240, 200, 90) })
A({ Id = "WitchfireOrb", Name = "Witchfire Orb", Class = "Mage", Price = 700, Stats = { MagicPower = 18, CooldownReduction = 0.05 },
	Passive = { Name = "Curse", Description = "Abilities apply a curse that increases damage the target receives from you by 8% for 3 seconds.",
		Effect = "Curse", Bonus = 0.08, Duration = 3 },
	Glyph = "WO", Color = Color3.fromRGB(120, 200, 80) })
A({ Id = "Soulglass", Name = "Soulglass", Class = "Mage", Price = 650, Stats = { MagicPower = 15, MaxHealth = 100 },
	Passive = { Name = "Spell Drain", Description = "Damaging enemy heroes restores 3% of your maximum mana.",
		Details = "Once per second.", Effect = "SpellDrain", ManaPercent = 0.03, Cooldown = 1 },
	Glyph = "SG", Color = Color3.fromRGB(150, 110, 220) })
A({ Id = "StormcallersEye", Name = "Stormcaller's Eye", Class = "Mage", Price = 800, Stats = { MagicPower = 25 },
	Passive = { Name = "Static", Description = "Ability damage charges the item. At 100 charge, your next damaging spell releases lightning to nearby enemies.",
		Details = "+25 charge per ability hit. Lightning: 70 magic damage to up to 3 enemies within 12 studs.", Effect = "Static", Charge = 25, Damage = 70, Targets = 3, Radius = 12 },
	Glyph = "SE", Color = Color3.fromRGB(90, 170, 255) })

-- MARKSMAN ----------------------------------------------------------------------------------
A({ Id = "SilverwindBow", Name = "Silverwind Bow", Class = "Marksman", Price = 600, Stats = { AttackDamage = 12, AttackSpeed = 0.10 },
	Passive = { Name = "Piercing Shot", Description = "Every fifth basic attack passes through the first target and hits enemies behind them.",
		Effect = "PiercingShot", Every = 5 },
	Glyph = "SB", Color = Color3.fromRGB(190, 200, 210) })
A({ Id = "CrimsonQuiver", Name = "Crimson Quiver", Class = "Marksman", Price = 650, Stats = { AttackDamage = 10, CritChance = 0.10 },
	Passive = { Name = "Deep Cut", Description = "Critical attacks apply a bleed.",
		Details = "Bleed: 10 damage/sec for 3 sec.", Effect = "DeepCut", DPS = 10, Duration = 3 },
	Glyph = "CQ", Color = Color3.fromRGB(170, 40, 40) })
A({ Id = "EagleEye", Name = "Eagle Eye", Class = "Marksman", Price = 700, Stats = { AttackDamage = 15, CritChance = 0.05 },
	Passive = { Name = "Precision", Description = "Basic attacks deal increased damage the farther you are from the target.",
		Details = "+1% damage per stud beyond 8 studs (max +20%).", Effect = "Precision", MinDistance = 8, PerStud = 0.01, Max = 0.20 },
	Glyph = "EE", Color = Color3.fromRGB(210, 180, 100) })
A({ Id = "StormQuiver", Name = "Storm Quiver", Class = "Marksman", Price = 700, Stats = { AttackSpeed = 0.15 },
	Passive = { Name = "Static Arrows", Description = "Every 6th attack releases lightning that bounces between nearby enemies.",
		Details = "Lightning: 40 magic damage, bounces to up to 3 enemies within 12 studs.", Effect = "StaticArrows", Every = 6, Damage = 40, Bounces = 3, Range = 12 },
	Glyph = "SQ", Color = Color3.fromRGB(100, 170, 230) })
A({ Id = "Venomshot", Name = "Venomshot", Class = "Marksman", Price = 600, Stats = { AttackDamage = 10, AttackSpeed = 0.08 },
	Passive = { Name = "Toxic Arrow", Description = "Every attack applies a stacking poison.",
		Details = "Maximum: 3 stacks. Poison: 5 damage/sec per stack for 4 sec.", Effect = "ToxicArrow", DPS = 5, Duration = 4, MaxStacks = 3 },
	Glyph = "VS", Color = Color3.fromRGB(110, 180, 70) })
A({ Id = "ExecutionBow", Name = "Execution Bow", Class = "Marksman", Price = 700, Stats = { AttackDamage = 18 },
	Passive = { Name = "Finishing Shot", Description = "Attacks against enemies below 20% HP deal 25% bonus physical damage.",
		Effect = "FinishingShot", Threshold = 0.2, Bonus = 0.25 },
	Glyph = "EB", Color = Color3.fromRGB(120, 40, 30) })
A({ Id = "Lifebow", Name = "Lifebow", Class = "Marksman", Price = 650, Stats = { AttackDamage = 12, Lifesteal = 0.08 },
	Passive = { Name = "Siphon", Description = "Consecutive attacks against the same hero increase lifesteal temporarily.",
		Details = "+3% lifesteal per consecutive hit (max +15%), resets after 3 sec.", Effect = "Siphon", PerStack = 0.03, MaxStacks = 5, Window = 3 },
	Glyph = "LB", Color = Color3.fromRGB(200, 60, 90) })
A({ Id = "Windpiercer", Name = "Windpiercer", Class = "Marksman", Price = 750, Stats = { AttackDamage = 18, AttackSpeed = 0.10 },
	Passive = { Name = "Armor Pierce", Description = "Basic attacks ignore 12% of enemy armor.",
		Effect = "ArmorPierce", Ignore = 0.12 },
	Glyph = "WP", Color = Color3.fromRGB(160, 210, 190) })

-- TANK --------------------------------------------------------------------------------------
A({ Id = "MoltenCore", Name = "Molten Core", Class = "Tank", Price = 650, Stats = { MaxHealth = 200, Armor = 5 },
	Passive = { Name = "Burning Body", Description = "Enemies near you take continuous magic damage.",
		Details = "8 + 1% of your max HP magic damage/sec to enemies within 8 studs.", Effect = "BurningBody", Radius = 8, DPS = 8, HPPercent = 0.01 },
	Glyph = "MO", Color = Color3.fromRGB(220, 90, 30) })
A({ Id = "MirrorAegis", Name = "Mirror Aegis", Class = "Tank", Price = 700, Stats = { MaxHealth = 150, MagicDefense = 10 },
	Passive = { Name = "Spell Reflection", Description = "Every 8 seconds, reduce the next ability damage received and reflect part of it back.",
		Details = "Blocks 30% of that hit and reflects 30% of the damage taken.", Effect = "SpellReflection", Cooldown = 8, Reduce = 0.3, Reflect = 0.3 },
	Glyph = "MA", Color = Color3.fromRGB(170, 200, 230) })
A({ Id = "Frostwall", Name = "Frostwall", Class = "Tank", Price = 650, Stats = { MaxHealth = 180, Armor = 8 },
	Passive = { Name = "Frozen Ground", Description = "When you are damaged, the attacker is slowed by 15% for 1 second.",
		Effect = "FrozenGround", Slow = 0.15, Duration = 1 },
	Glyph = "FW", Color = Color3.fromRGB(130, 180, 220) })
A({ Id = "BloodguardPlate", Name = "Bloodguard Plate", Class = "Tank", Price = 750, Stats = { MaxHealth = 250 },
	Passive = { Name = "Desperation", Description = "Below 30% HP, gain 20% damage reduction.",
		Effect = "Desperation", Threshold = 0.3, Reduction = 0.2 },
	Glyph = "BG", Color = Color3.fromRGB(150, 40, 40) })
A({ Id = "AdamantBulwark", Name = "Adamant Bulwark", Class = "Tank", Price = 700, Stats = { MaxHealth = 200, Armor = 10 },
	Passive = { Name = "Tenacity", Description = "Reduces stun, slow, and other crowd-control duration by 20%.",
		Effect = "Tenacity", Reduction = 0.2 },
	Glyph = "AB", Color = Color3.fromRGB(150, 150, 160) })
A({ Id = "PlagueCarapace", Name = "Plague Carapace", Class = "Tank", Price = 650, Stats = { MaxHealth = 180, MagicDefense = 5 },
	Passive = { Name = "Grievous Aura", Description = "Nearby enemies receive 25% reduced healing.",
		Details = "Nearby = within 10 studs.", Effect = "GrievousAura", Radius = 10, HealCut = 0.25 },
	Glyph = "PC", Color = Color3.fromRGB(110, 140, 60) })
A({ Id = "ColossusBelt", Name = "Colossus Belt", Class = "Tank", Price = 750, Stats = { MaxHealth = 350 },
	Passive = { Name = "Overgrowth", Description = "Every 10 enemy units that die near you permanently grant +2 maximum HP.",
		Details = "Near = within 20 studs.", Effect = "Overgrowth", Radius = 20, Every = 10, HP = 2 },
	Glyph = "CB", Color = Color3.fromRGB(120, 150, 70) })
A({ Id = "GuardiansBell", Name = "Guardian's Bell", Class = "Tank", Price = 700, Stats = { MaxHealth = 150, Armor = 10, MagicDefense = 10 },
	Passive = { Name = "Rescue", Description = "When an allied hero near you falls below 20% HP, both of you gain a small shield.",
		Details = "Cooldown: 25 sec. Shield: 80 + 5% of your max HP for 3 sec. Near = within 15 studs.", Effect = "Rescue", Radius = 15, Threshold = 0.2, Shield = 80, ShieldHPPercent = 0.05, Duration = 3, Cooldown = 25 },
	Glyph = "GB", Color = Color3.fromRGB(220, 190, 110) })

-- FIGHTER -----------------------------------------------------------------------------------
-- Bloodaxe, Sanguine Hammer and Dragonheart Axe are priced above the first draft (650 / 700 /
-- 800g) so stats + passive fit SharedGameRules (their stats alone were worth ~ the old price).
A({ Id = "Bloodaxe", Name = "Bloodaxe", Class = "Fighter", Price = 720, Stats = { AttackDamage = 18, MaxHealth = 100 },
	Passive = { Name = "Carnage", Description = "Dealing damage to enemy heroes grants stacking attack damage for 4 seconds.",
		Details = "+3 attack damage per stack, max 5 stacks.", Effect = "Carnage", PerStack = 3, MaxStacks = 5, Duration = 4 },
	Glyph = "BA", Color = Color3.fromRGB(170, 30, 30) })
A({ Id = "Ironbreaker", Name = "Ironbreaker", Class = "Fighter", Price = 700, Stats = { AttackDamage = 20 },
	Passive = { Name = "Armor Crush", Description = "Every third basic attack reduces enemy armor by 12% for 3 seconds.",
		Effect = "ArmorCrush", Every = 3, Shred = 0.12, Duration = 3 },
	Glyph = "IB", Color = Color3.fromRGB(130, 130, 140) })
A({ Id = "Lifedrinker", Name = "Lifedrinker", Class = "Fighter", Price = 650, Stats = { AttackDamage = 14, Lifesteal = 0.08 },
	Passive = { Name = "Ravage", Description = "Attacking an enemy below 40% HP gives increased lifesteal.",
		Details = "+10% lifesteal on those attacks.", Effect = "Ravage", Threshold = 0.4, Bonus = 0.10 },
	Glyph = "LD", Color = Color3.fromRGB(190, 40, 70) })
A({ Id = "WarforgedMail", Name = "Warforged Mail", Class = "Fighter", Price = 700, Stats = { MaxHealth = 180, Armor = 12 },
	Passive = { Name = "Retaliation", Description = "Taking physical damage increases your attack damage for 3 seconds.",
		Details = "+10% attack damage.", Effect = "Retaliation", Bonus = 0.10, Duration = 3 },
	Glyph = "WF", Color = Color3.fromRGB(160, 110, 60) })
A({ Id = "Chainbreaker", Name = "Chainbreaker", Class = "Fighter", Price = 650, Stats = { AttackDamage = 15, MaxHealth = 100 },
	Passive = { Name = "Tenacious", Description = "After being stunned or rooted, gain 25% movement speed for 2 seconds.",
		Effect = "Tenacious", Haste = 0.25, Duration = 2 },
	Glyph = "CH", Color = Color3.fromRGB(150, 120, 80) })
A({ Id = "Battlebrand", Name = "Battlebrand", Class = "Fighter", Price = 600, Stats = { AttackDamage = 16 },
	Passive = { Name = "Mark of War", Description = "Damaging an enemy three times marks them. Attacking a marked enemy deals bonus true damage.",
		Details = "Bonus: 40 true damage (uses the mark). Mark lasts 5 sec.", Effect = "MarkOfWar", Hits = 3, Window = 4, Duration = 5, TrueDamage = 40 },
	Glyph = "BB", Color = Color3.fromRGB(200, 90, 40) })
A({ Id = "SanguineHammer", Name = "Sanguine Hammer", Class = "Fighter", Price = 850, Stats = { AttackDamage = 20, MaxHealth = 150 },
	Passive = { Name = "Crushing Blow", Description = "Every 5th basic attack deals bonus damage based on your maximum HP.",
		Details = "Bonus: 4% of your max HP (physical).", Effect = "CrushingBlow", Every = 5, HPPercent = 0.04 },
	Glyph = "SH", Color = Color3.fromRGB(140, 20, 40) })
A({ Id = "DragonheartAxe", Name = "Dragonheart Axe", Class = "Fighter", Price = 900, Stats = { AttackDamage = 22, MaxHealth = 150 },
	Passive = { Name = "Dragon's Fury", Description = "When below 40% HP, gain increased attack damage and attack speed.",
		Details = "+15% attack damage and +20% attack speed.", Effect = "DragonsFury", Threshold = 0.4, ADPercent = 0.15, AttackSpeed = 0.20 },
	Glyph = "DA", Color = Color3.fromRGB(210, 70, 30) })

-- Kept for older callers
ItemDefinitions.OpenMythicOrder = ItemDefinitions.RoleItems.General
ItemDefinitions.ClassItemOrder = { "AssassinBoots", "MageBoots", "TankBoots", "FighterBoots" }

----------------------------------------------------------------------------
-- Purchasable creep War Band (numbers fixed by design for the prototype)
----------------------------------------------------------------------------
ItemDefinitions.CreepWave = {
	Id = "WarBand", Name = "War Band", Price = 150, Count = 6, KillReward = 20,
	MaxHealth = 320, Armor = 5, Damage = 24, AttackCooldown = 1.2, AttackRange = 5,
	AggroRange = 16, MoveSpeed = 13,
	MaxActivePerPlayer = 1, -- one living war band per player at a time (anti-spam)
	Description = "Send six warriors toward the enemy base.",
	Icon = "rbxassetid://132306465831471", Glyph = "WB", Color = Color3.fromRGB(170, 40, 45),
}

----------------------------------------------------------------------------
-- Automatic minion waves + team minion upgrades (shop). Every Interval seconds each
-- living team sends Count minions (CreepWave stats) toward the nearest enemy base.
-- Players buy team-wide upgrade levels; each level multiplies minion health/damage.
----------------------------------------------------------------------------
ItemDefinitions.MinionWaves = {
	Interval = 30, -- seconds between waves
	FirstWaveDelay = 10, -- first wave this long after the match starts
	Count = 4, -- minions per team per wave
	MaxAlivePerTeam = 16, -- performance cap (18 players / up to 6 teams)
}
ItemDefinitions.MinionUpgrade = {
	Id = "MinionUpgrade", Name = "Upgrade Minions", MaxLevel = 5,
	Prices = { 150, 250, 350, 450, 550 }, -- price of level 1..5
	HealthPerLevel = 0.2, DamagePerLevel = 0.2, ArmorPerLevel = 1,
	Description = "Train your team's minions: every level gives ALL your team's minions +20% health, +20% damage and +1 armor.",
	Icon = "rbxassetid://132306465831471", Glyph = "UM", Color = Color3.fromRGB(170, 40, 45),
}

-- Minion stats at a team upgrade level (0 = base)
function ItemDefinitions.GetMinionStats(level)
	level = math.clamp(math.floor(tonumber(level) or 0), 0, ItemDefinitions.MinionUpgrade.MaxLevel)
	local upgrade, base = ItemDefinitions.MinionUpgrade, ItemDefinitions.CreepWave
	return {
		Level = level,
		MaxHealth = math.floor(base.MaxHealth * (1 + upgrade.HealthPerLevel * level) + 0.5),
		Damage = math.floor(base.Damage * (1 + upgrade.DamagePerLevel * level) + 0.5),
		Armor = base.Armor + upgrade.ArmorPerLevel * level,
	}
end

-- Price of the next level, or nil when maxed
function ItemDefinitions.GetMinionUpgradePrice(currentLevel)
	return ItemDefinitions.MinionUpgrade.Prices[(currentLevel or 0) + 1]
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
function ItemDefinitions.GetItem(id)
	return type(id) == "string" and ItemDefinitions.Items[id] or nil
end

function ItemDefinitions.GetAbility(id)
	return type(id) == "string" and ItemDefinitions.Abilities[id] or nil
end

function ItemDefinitions.GetItemAbility(itemId)
	local item = ItemDefinitions.GetItem(itemId)
	return item and ItemDefinitions.GetAbility(item.Ability) or nil
end

-- Earthen Shackles style stuns: Stun sec + StunPerHP sec per max health point, capped at StunMax
function ItemDefinitions.GetScaledStun(ability, maxHealth)
	local duration = (ability.Stun or 0) + (ability.StunPerHP or 0) * (maxHealth or 0)
	return math.min(ability.StunMax or duration, duration)
end

-- Mana cost of an E / R item skill (boots and the class Q are free): ability.ManaCost, or
-- 20 + 4 per second of cooldown rounded to 5 (8 sec -> 50, 12 sec -> 70, 20 sec -> 100)
function ItemDefinitions.GetManaCost(ability)
	if not ability then
		return 0
	end
	if ability.ManaCost then
		return ability.ManaCost
	end
	return math.floor((20 + 4 * (ability.Cooldown or 0)) / 5 + 0.5) * 5
end

-- Mana cost of an item skill cast from a given slot: E / R always cost mana (GetManaCost);
-- boot skills are free unless the skill sets its own ManaCost (every Mage boot skill does).
function ItemDefinitions.GetSlotManaCost(ability, isBoots)
	if not ability then
		return 0
	end
	if isBoots then
		return ability.ManaCost or 0
	end
	return ItemDefinitions.GetManaCost(ability)
end

function ItemDefinitions.IsBoots(item)
	return item ~= nil and item.SlotType == "Boots"
end

function ItemDefinitions.IsPassive(item)
	return item ~= nil and item.SlotType == "Passive"
end

-- "Bloodthirst: heal 8% of damage dealt" (the item's automatic effect), or ""
function ItemDefinitions.GetPassiveEffectText(item)
	local passive = item and item.Passive
	if not passive then
		return ""
	end
	if passive.Name and passive.Description then
		return passive.Name .. ": " .. passive.Description
	end
	return passive.Name or passive.Description or ""
end

function ItemDefinitions.CanClassUse(item, classKey)
	return item ~= nil and (item.Class == nil or item.Class == classKey)
end

function ItemDefinitions.GetSellValue(item)
	return item and math.floor(item.Price * ItemDefinitions.SELL_RATIO + 0.5) or 0
end

local STAT_LABELS = {
	MoveSpeed = "Move Speed", Armor = "Armor", AttackDamage = "Attack Damage", MaxHealth = "Max Health", AttackSpeed = "Attack Speed",
	MagicPower = "Magic Power", Mana = "Mana", CooldownReduction = "Cooldown Reduction", CritChance = "Critical Chance",
	Lifesteal = "Lifesteal", MagicDefense = "Magic Defense", MoveSpeedPercent = "Movement Speed",
}

-- Short one-line summary for loot (chests / drops): the two biggest stats + the effect.
-- e.g. "+22 AD  +150 HP  |  Shadow Dash (E/R)"
local SHORT_STATS = {
	AttackDamage = { "AD", 1 }, MagicPower = { "MP", 1 }, MaxHealth = { "HP", 0.12 }, Armor = { "Armor", 1 },
	AttackSpeed = { "Atk Spd", 60, true }, MoveSpeed = { "Speed", 5 }, CritChance = { "Crit", 60, true },
	Lifesteal = { "Lifesteal", 60, true }, CooldownReduction = { "CDR", 60, true }, Mana = { "Mana", 0.08 },
	MagicDefense = { "M.Def", 1 }, MoveSpeedPercent = { "Speed", 60, true }, HealthRegen = { "Regen", 1000, true },
}

function ItemDefinitions.GetShortStats(item)
	local ranked = {}
	for stat, value in pairs(item and item.Stats or {}) do
		local info = SHORT_STATS[stat]
		if info and value ~= 0 then
			table.insert(ranked, { Weight = math.abs(value) * info[2], Text = info[3] and string.format("+%d%% %s", math.floor(value * 100 + 0.5), info[1]) or string.format("+%d %s", math.floor(value + 0.5), info[1]) })
		end
	end
	table.sort(ranked, function(a, b)
		return a.Weight > b.Weight
	end)
	local parts = {}
	for index = 1, math.min(2, #ranked) do
		table.insert(parts, ranked[index].Text)
	end
	return table.concat(parts, "  ")
end

function ItemDefinitions.GetShortEffect(item)
	if not item then
		return ""
	end
	if item.SlotType == "Passive" then
		return item.Passive and item.Passive.Name or ""
	end
	local ability = item.Ability and ItemDefinitions.Abilities[item.Ability]
	if not ability then
		return ""
	end
	return string.format("%s (%s)", ability.Name, item.SlotType == "Boots" and "Right Mouse" or "E/R")
end

function ItemDefinitions.GetShortSummary(item)
	local stats, effect = ItemDefinitions.GetShortStats(item), ItemDefinitions.GetShortEffect(item)
	if stats ~= "" and effect ~= "" then
		return stats .. "  |  " .. effect
	end
	return stats ~= "" and stats or effect
end

-- Tooltip lines built from the live numbers above: { { Label, Value }, ... }
-- stats (optional): { AD, HP, Armor } of the viewing hero, to show live values
function ItemDefinitions.GetAbilityStatLines(ability, stats)
	local lines = {}
	if not ability then
		return lines
	end
	local function add(label, value)
		table.insert(lines, { label, value })
	end
	if ability.Damage then
		local magic = type(ability.Damage) == "table" and ability.Damage.MP ~= nil
		add("Damage", AbilityScaling.DescribeWithValue(ability.Damage, stats) .. (ability.TrueDamage and (magic and " (magic, ignores armor)" or " (ignores armor)") or " (physical)"))
	end
	if ability.Stun and ability.StunPerHP then
		local text = string.format("%.1f sec + %.1f sec per 100 max HP (max %.1f)", ability.Stun, ability.StunPerHP * 100, ability.StunMax or 99)
		if stats and stats.HP then
			text ..= string.format("  = %.1f sec", ItemDefinitions.GetScaledStun(ability, stats.HP))
		end
		add("Stun", text)
	elseif ability.Stun then
		add("Stun", string.format("%.1f sec", ability.Stun))
	end
	if ability.Slow then add("Slow", string.format("-%d%% move speed for %.1f sec", math.floor(ability.Slow * 100 + 0.5), ability.SlowDuration or ability.Duration or 0)) end
	if ability.HasteBonus then add("Move speed", string.format("+%d%% for %.1f sec%s", ability.HasteBonus * 100, ability.HasteDuration or ability.Duration or 0, ability.AffectsAllies and " (you + allies)" or "")) end
	if ability.Stealth then add("Invisible", string.format("%.1f sec (attacking reveals you)", ability.Duration or 0)) end
	if ability.Unstoppable then add("Unstoppable", "removes stuns, immune to stuns") end
	if ability.Heal then add("Heal", AbilityScaling.DescribeWithValue(ability.Heal, stats)) end
	if ability.PushDistance then add("Push", "up to " .. ability.PushDistance .. " studs away from the center") end
	if ability.KnockDistance then add("Knock aside", ability.KnockDistance .. " studs") end
	if ability.ExecuteThreshold then add("Execute", string.format("+%d%% damage below %d%% health", (ability.ExecuteBonus or 0) * 100, ability.ExecuteThreshold * 100)) end
	if ability.Delay then add("Delay", string.format("%.1f sec", ability.Delay)) end
	if ability.ExplosionRadius then add("Explosion", string.format("%d%% damage to enemies within %d studs", (ability.SplashPercent or 0) * 100, ability.ExplosionRadius)) end
	if ability.Bolts then add("Bolts", string.format("%d (damage above is per bolt)", ability.Bolts)) end
	if ability.Knives then add("Knives", string.format("%d in a %d deg fan (damage above is per knife)", ability.Knives, ability.Spread or 0)) end
	if ability.Arrows then add("Arrows", string.format("%d (damage above is per arrow)", ability.Arrows)) end
	if ability.SlowRadius then add("Slow radius", ability.SlowRadius .. " studs (enemies)") end
	if ability.ReflectPercent then add("Reflect", string.format("%d%% of damage taken", math.floor(ability.ReflectPercent * 100 + 0.5))) end
	if ability.Shield then add("Shield", AbilityScaling.DescribeWithValue(ability.Shield, stats) .. (ability.Radius and " (you + allies)" or "")) end
	if ability.Empower then add("Next attack", string.format("+%d%% damage", (ability.Empower - 1) * 100)) end
	if ability.BlindsEnemies then add("Smoke", "enemies inside miss basic attacks") end
	if ability.AttackSpeedBoost then add("Attack speed", string.format("+%d%% for %.1f sec", ability.AttackSpeedBoost * 100, ability.Duration)) end
	if ability.Id == "SummonGolem" then
		local golem = ItemDefinitions.Golem
		add("Golem HP", AbilityScaling.DescribeWithValue(golem.MaxHealth, stats))
		add("Golem hit", AbilityScaling.DescribeWithValue(golem.Damage, stats) .. string.format(" every %.1fs", golem.AttackCooldown))
		add("Lasts", golem.Lifetime .. " sec")
		add("Enemy reward", "+" .. golem.KillReward .. " gold if destroyed")
	end
	if ability.Duration and ability.Id ~= "SummonGolem" then add("Duration", string.format("%.1f sec", ability.Duration)) end
	if ability.Radius then add("Radius", tostring(ability.Radius) .. " studs") end
	if ability.PullDistance then add("Pull", "up to " .. ability.PullDistance .. " studs toward center") end
	if ability.Range then add("Range", tostring(ability.Range) .. " studs") end
	if ability.Arc then add("Arc", tostring(ability.Arc) .. " deg") end
	add("Cooldown", tostring(ability.Cooldown) .. " sec")
	local targeting = { Unit = "Click an enemy", Point = "Ground target", Direction = "Toward cursor", Self = "Self" }
	add("Target", targeting[ability.Targeting] or ability.Targeting)
	return lines
end

local PERCENT_STATS = { AttackSpeed = true, CooldownReduction = true, CritChance = true, Lifesteal = true, MoveSpeedPercent = true }

----------------------------------------------------------------------------
-- Gold value of a mythic = its passive stats (priced like the stat shop items in
-- ShopDefinitions: +150 HP = 250g, +12 armor = 200g, +3 move speed = 200g,
-- +12 AD = 300g, +0.4% regen = 150g; attack speed 1% = 15g) + its active skill
-- (ability.Value, or SKILL_VALUE for a standard skill) + any special passive (PASSIVE_VALUE). Every item is tuned so this
-- total matches its price (within ~10g).
----------------------------------------------------------------------------
ItemDefinitions.SKILL_VALUE = 250
ItemDefinitions.PASSIVE_VALUE = 100 -- reflect / splash style passives
-- gold per point for stats with no stat-shop item (percent stats: gold per +1.0 = +100%)
--   AttackSpeed 15g per 1%, CooldownReduction 25g per 1%, CritChance 20g per 1%,
--   Lifesteal 25g per 1%, MoveSpeedPercent 20g per 1%, MagicPower 20g per point (skill damage
--   only, so cheaper than AD's 25g), MagicDefense = armor price (200g / 12), Mana 1g per point
local EXTRA_STAT_VALUES = {
	AttackSpeed = 1500, CooldownReduction = 2500, CritChance = 2000, Lifesteal = 2500, MoveSpeedPercent = 2000,
	MagicPower = 20, MagicDefense = 200 / 12, Mana = 1,
}

local statGoldCache = nil
local function statGoldPerPoint()
	if statGoldCache then
		return statGoldCache
	end
	statGoldCache = table.clone(EXTRA_STAT_VALUES)
	local ok, ShopDefinitions = pcall(require, script.Parent:WaitForChild("ShopDefinitions"))
	if ok and ShopDefinitions then
		for _, shopItem in pairs(ShopDefinitions.Items) do
			local stat, amount = next(shopItem.Effect or {})
			if stat and amount and amount ~= 0 then
				statGoldCache[stat] = shopItem.Price / amount
			end
		end
	end
	return statGoldCache
end

function ItemDefinitions.GetStatGoldValue(item)
	local perPoint = statGoldPerPoint()
	local total = 0
	for stat, value in pairs(item and item.Stats or {}) do
		total += (perPoint[stat] or 0) * value
	end
	return math.floor(total + 0.5)
end

-- statGold, skillGold, passiveGold, total
function ItemDefinitions.GetItemGoldValue(item)
	local stats = ItemDefinitions.GetStatGoldValue(item)
	-- a skill is worth SKILL_VALUE unless its definition sets a higher Value (stronger skills)
	local ability = item and ItemDefinitions.GetAbility(item.Ability)
	local skill = item and item.Ability and (ability and ability.Value or ItemDefinitions.SKILL_VALUE) or 0
	local passive = (item and (item.PassiveReflect or item.PassiveSplash)) and ItemDefinitions.PASSIVE_VALUE or 0
	if item and item.Passive then -- passive items: their automatic effect's gold value
		-- (explicit Value, else whatever the price leaves after the stats - see SharedGameRules)
		passive = item.Passive.Value or math.max(0, (item.Price or 0) - stats)
	end
	return stats, skill, passive, stats + skill + passive
end

function ItemDefinitions.GetStatText(item)
	local parts = {}
	for key, value in pairs(item and item.Stats or {}) do
		local label = STAT_LABELS[key] or key
		if PERCENT_STATS[key] then
			table.insert(parts, string.format("+%d%% %s", math.floor(value * 100 + 0.5), label))
		else
			table.insert(parts, string.format("+%s %s", tostring(value), label))
		end
	end
	table.sort(parts)
	if item and item.PassiveSplash then
		table.insert(parts, string.format("basic attacks splash %d%% damage to enemies within %d studs of the target", item.PassiveSplash.Percent * 100, item.PassiveSplash.Radius))
	end
	if item and item.PassiveReflect then
		table.insert(parts, string.format("reflects %d%% of damage taken back to attackers", item.PassiveReflect * 100))
	end
	return table.concat(parts, ", ")
end

-- Uploaded painted icons (Shared.IconIds, filled by tools/icons/apply_icons.py) override the
-- icons above; empty entries keep the current icon.
do
	local module = script.Parent:FindFirstChild("IconIds")
	local ok, ids = pcall(function()
		return module and require(module)
	end)
	if ok and type(ids) == "table" then
		for id, icon in pairs(ids.Items or {}) do
			if ItemDefinitions.Items[id] and icon ~= "" then
				ItemDefinitions.Items[id].Icon = icon
			end
		end
		local special = ids.Special or {}
		if special.WarBand and special.WarBand ~= "" then
			ItemDefinitions.CreepWave.Icon = special.WarBand
		end
		if special.MinionUpgrade and special.MinionUpgrade ~= "" then
			ItemDefinitions.MinionUpgrade.Icon = special.MinionUpgrade
		end
	end
end

return ItemDefinitions
