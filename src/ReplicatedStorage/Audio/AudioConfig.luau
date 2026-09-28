--[[
	AudioConfig - THE single place to configure every sound in RUINFALL.

	HOW TO ADD / CHANGE A SOUND
	  1. Find (or add) the entry below, e.g. Sounds.Combat.SwordSwing.
	  2. Put one or more Roblox audio asset ids in `Ids` (several ids = random variations).
	  3. Play it from any client script with   AudioManager:Play("Combat.SwordSwing", { Position = pos })
	     (or the helpers PlaySFX / PlayUI / PlaySkill / PlayMusic - see AudioManager).
	  No code changes are needed in AudioManager to add a sound.

	MISSING ASSETS
	  If you do not have an asset yet, set   Ids = { AudioConfig.PLACEHOLDER }   and mark it with
	  -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET
	  Placeholders never error: the manager silently skips them (and logs them in debug mode).

	ENTRY FIELDS (all optional except Ids / Alias / Layers)
	  Ids          = { assetId, ... }       random variation, never the same one twice in a row
	  Alias        = "Section.Name"          reuse another entry (with optional overrides below)
	  Layers       = { "Section.Name" | { Cue = "Section.Name", Delay = s, Volume = x } , ... }
	                 composite sound: plays several cues together / in sequence
	  Group        = "Music" | "Ambient" | "UI" | "SFX" | "Combat"      (volume category)
	  Priority     = "Critical" | "High" | "Medium" | "Low"            (voice stealing / dropping)
	  Volume       = 0..1 base volume          VolumeJitter = 0..1 (+/- fraction, randomised)
	  Pitch        = number or { min, max }    subtle randomised pitch (keep within ~0.9..1.1)
	  Delay        = { min, max } seconds      small random timing variation
	  Spatial      = true -> 3D at the given Position, false -> 2D (UI / music / own-player feedback)
	  MinDistance / MaxDistance   rolloff (studs) for 3D sounds. Sounds beyond MaxDistance are skipped.
	  Looped       = true for loops (music / ambience beds / heartbeat)
	  Cooldown     = seconds between two plays of this entry (anti-spam)
	  MaxInstances = how many copies of this entry may overlap
]]

local AudioConfig = {}

AudioConfig.PLACEHOLDER = "PLACEHOLDER" -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET

-- Developer debug -------------------------------------------------------------------------
AudioConfig.Debug = {
	Enabled = false, -- true: print "[Audio] Playing: ..." for every sound (Studio only)
	TestPanelKey = Enum.KeyCode.F7, -- Studio only: opens the sound test panel (plays any entry)
	LogMissing = true, -- warn once for placeholder / failed ids when Enabled
}

-- Volume categories -> SoundGroups (created under SoundService on each client) ----------
-- Combat is nested inside SFX, so the SFX slider / toggle also affects combat sounds.
AudioConfig.Groups = {
	{ Name = "Master", Parent = nil },
	{ Name = "Music", Parent = "Master" },
	{ Name = "Ambient", Parent = "Master" },
	{ Name = "UI", Parent = "Master" },
	{ Name = "SFX", Parent = "Master" },
	{ Name = "Combat", Parent = "SFX" },
}

-- Player settings defaults (saved per player on the server, see AudioService) ---------------
AudioConfig.DefaultSettings = {
	Master = 0.8,
	Music = 0.45,
	SFX = 0.9,
	Combat = 0.9,
	Ambient = 0.7,
	UI = 0.7,
	MusicEnabled = true,
	SFXEnabled = true,
}

-- Priority / voice management -------------------------------------------------------------
AudioConfig.Priority = { Critical = 4, High = 3, Medium = 2, Low = 1 }
AudioConfig.Voices = {
	Emitters3D = 30, -- pooled 3D emitters (one Sound each)
	Channels2D = 16, -- pooled 2D sounds
	DropLowAbove = 16, -- when this many voices are busy, Low priority sounds are skipped
	DropMediumAbove = 24, -- ... and Medium priority sounds too
}
AudioConfig.Spatial = {
	MinDistance = 10,
	MaxDistance = 110,
	RollOffMode = Enum.RollOffMode.InverseTapered,
}

-- Dynamic music ------------------------------------------------------------------------------
AudioConfig.MusicRules = {
	Crossfade = 2.5, -- seconds between tracks
	CombatTimeout = 9, -- seconds without dealing/taking damage -> back to exploration
	CombatHostileRange = 38, -- an enemy hero / chasing monster this close keeps combat music on
	BossRange = 55, -- a Ruin / Brute this close while in combat -> Boss music
	StingerDuck = 0.3, -- music volume multiplier while a stinger / big cue plays
	DeadDuck = 0.55, -- music multiplier while the local hero is dead
	LowHealthDuck = 0.75,
}

-- Skill sounds: every skill / spell sound is kept short and FADES out (never cut abruptly).
-- Applies to all entries in the listed sections, and to every layer a skill cast or skill
-- effect plays (see CharacterAudio / EffectAudio). An entry can opt out with MaxDuration = 0
-- or set its own MaxDuration / FadeOut.
AudioConfig.SkillAudio = {
	MaxDuration = 0.9, -- seconds from the cast / effect trigger to silence
	FadeOut = 0.35, -- length of the fade at the end
	Sections = { Effects = true, Skills = true },
}

-- Ambient zones (chosen from the local character position every second) -------------------
AudioConfig.AmbientZones = {
	Forest = {
		Beds = { "Ambient.ForestBed", "Ambient.NightInsects" },
		OneShots = { "Ambient.BirdChirp", "Ambient.WindGust", "Ambient.LeavesRustle", "Ambient.BranchCreak", "Ambient.DistantHowl", "Ambient.Owl" },
		Interval = { 5, 12 },
	},
	Cursed = { -- monster camps and the ruined arena centre
		Beds = { "Ambient.CursedBed", "Ambient.ForestBed" },
		OneShots = { "Ambient.Whisper", "Ambient.CrowCaw", "Ambient.WindGust", "Ambient.BranchCreak", "Ambient.DistantHowl" },
		Interval = { 6, 14 },
	},
	Base = { -- your base / flag: camp fire, calm
		Beds = { "Ambient.BaseBed", "Ambient.ForestBed" },
		OneShots = { "Ambient.BirdChirp", "Ambient.LeavesRustle", "Ambient.WindGust" },
		Interval = { 7, 15 },
	},
	Hall = { -- hub hall between matches
		Beds = { "Ambient.HallBed" },
		OneShots = {},
		Interval = { 30, 60 },
	},
	CampRadius = 26,
	BaseRadius = 38,
	CenterRadius = 30,
}

-- Footstep surfaces: part-name keywords first, then Material, then Default ------------------
AudioConfig.Footsteps = {
	Default = "Grass",
	NameKeywords = {
		{ "water", "Water" }, { "puddle", "Water" },
		{ "wood", "Wood" }, { "plank", "Wood" }, { "bridge", "Wood" }, { "crate", "Wood" },
		{ "metal", "Metal" }, { "iron", "Metal" }, { "grate", "Metal" },
		{ "road", "Stone" }, { "rock", "Stone" }, { "stone", "Stone" }, { "shrine", "Stone" }, { "platform", "Stone" },
		{ "brick", "Stone" }, { "cobble", "Stone" }, { "ruin", "Stone" }, { "flag", "Stone" }, { "base", "Stone" },
		{ "dirt", "Dirt" }, { "mud", "Dirt" }, { "sand", "Dirt" }, { "path", "Dirt" },
		{ "grass", "Grass" }, { "leaf", "Grass" }, { "bush", "Grass" }, { "ground", "Grass" },
	},
	Materials = {
		Grass = "Grass", LeafyGrass = "Grass", Ground = "Dirt", Mud = "Dirt", Sand = "Dirt", Sandstone = "Stone",
		Slate = "Stone", Rock = "Stone", Basalt = "Stone", Cobblestone = "Stone", Brick = "Stone", Granite = "Stone",
		Concrete = "Stone", Pavement = "Stone", Marble = "Stone", Limestone = "Stone",
		Wood = "Wood", WoodPlanks = "Wood",
		Metal = "Metal", DiamondPlate = "Metal", CorrodedMetal = "Metal", Foil = "Metal",
		Water = "Water",
	},
	WalkInterval = 0.42, -- seconds between steps at walk speed 16 (scaled by actual speed)
	ReferenceSpeed = 16,
	MaxHeroDistance = 70, -- footsteps of other heroes further than this are not simulated
}

-- Class identity: basic attack swing / hit, Q ability id, footstep weight -------------------
AudioConfig.Classes = {
	Assassin = { Swing = "Combat.BladeSwing", Hit = "Combat.FleshHit", StepVolume = 0.55, Ability = "ShadowStep" },
	Mage = { Swing = nil, Hit = "Combat.MagicImpact", StepVolume = 0.7, Ability = "ArcaneBurst" }, -- ranged: projectile style
	Marksman = { Swing = nil, Hit = "Combat.ArrowImpact", StepVolume = 0.7, Ability = "DashShot" },
	Tank = { Swing = "Combat.HeavySwing", Hit = "Combat.BluntHit", StepVolume = 1.0, ArmorRattle = true, Ability = "TauntingShockwave" },
	Fighter = { Swing = "Combat.PunchSwing", Hit = "Combat.Punch", StepVolume = 0.85, Ability = "BloodRush" },
}

-- Projectile styles (CombatDefinitions.ProjectileStyles) ----------------------------------
AudioConfig.Projectiles = {
	Arcane = { Launch = "Combat.MagicProjectile", Travel = "Skills.ArcaneTravel", Impact = "Combat.MagicImpact" },
	Fireball = { Launch = "Skills.FireLaunch", Travel = "Skills.FireTravel", Impact = "Skills.FireImpact" },
	Arrow = { Launch = "Combat.BowRelease", Impact = "Combat.ArrowImpact" },
	PowerShot = { Launch = "Skills.PowerShot", Travel = "Skills.PowerShotTravel", Impact = "Combat.CriticalHit" },
	Default = { Launch = "Combat.Whiff", Impact = "Combat.BluntHit" },
}

--[[ Skills: key = class ability Key (Q) or item ability Id (E / R / M2 slots).
	Cast    plays at the caster when the server confirms the cast (attributes LastAbilityAt / ItemCastAt)
	Charge  optional, right after Cast
	Release optional, ReleaseDelay seconds after Cast
	Impact  replaces the generic sound of the next area effect (Explosion / Shockwave / Stun...) this
	        caster produces within ImpactWindow seconds - gives every skill its own impact identity
	Extra   optional secondary layer (buff, debuff, heal...)
	Mythic  true -> adds the subtle mythic shimmer layer so mythic items feel special
	ADD NEW SKILLS HERE: copy an entry and rename it to the ability Id used in ItemDefinitions. ]]
AudioConfig.Skills = {
	-- Class signature abilities (Q)
	ShadowStep = { Cast = "Effects.Teleport", Extra = "Effects.Stealth" },
	ArcaneBurst = { Cast = "Effects.ArcaneCast", Charge = "Effects.MagicCharge", Impact = "Skills.ArcaneExplosion", ImpactWindow = 2.5 },
	DashShot = { Cast = "Movement.Dash", Release = "Skills.PowerShot", ReleaseDelay = 0.2 },
	TauntingShockwave = { Cast = "Effects.Roar", Impact = "Effects.GroundSlam", ImpactWindow = 0.6, Extra = "Combat.ArmorHit" },
	BloodRush = { Cast = "Effects.Roar", Extra = "Skills.BloodPulse", Volume = 0.8 }, -- toned down (was too loud / long)
	-- Mythic / boot item abilities
	Bulwark = { Cast = "Effects.Shield", Mythic = true },
	ArcaneSurge = { Cast = "Effects.ArcaneCast", Extra = "Effects.Buff", Mythic = true },
	PointStrike = { Cast = "Effects.DaggerThrow", Impact = "Combat.CriticalHit", ImpactWindow = 0.6 },
	ShieldBash = { Cast = "Combat.ShieldBlock", Impact = "Effects.Knockback", ImpactWindow = 0.6, Mythic = true },
	Whirlwind = { Cast = "Effects.Whirlwind", Impact = "Combat.HeavySwing", ImpactWindow = 0.5, Mythic = true },
	Fireball = { Cast = "Effects.MagicCharge", Release = "Skills.FireLaunch", ReleaseDelay = 0.05, Impact = "Skills.FireImpact", ImpactWindow = 3, Mythic = true },
	HeavyKick = { Cast = "Combat.HeavySwing", Impact = "Combat.Kick", ImpactWindow = 0.6 },
	FrostNova = { Cast = "Effects.Ice", Impact = "Effects.Ice", ImpactWindow = 0.6, Extra = "Effects.Slow", Mythic = true },
	SummonGolem = { Cast = "Effects.Summon", Impact = "Monsters.GolemAttack", ImpactWindow = 0.8, Mythic = true },
	IronFrenzy = { Cast = "Effects.Shield", Extra = "Combat.ArmorHit", Mythic = true },
	PiercingArrow = { Cast = "Effects.Charge", Release = "Skills.PowerShot", ReleaseDelay = 0.05, Mythic = true },
	WindPull = { Cast = "Effects.Wind", Impact = "Effects.Wind", ImpactWindow = 0.6 },
	Blink = { Cast = "Effects.Teleport", Extra = "Effects.DarkMagic", Mythic = true },
	Quickdraw = { Cast = "Combat.BowRelease", Release = "Combat.BowRelease", ReleaseDelay = 0.18, Mythic = true },
	Tumble = { Cast = "Movement.Dash" },
	BladeFlurry = { Cast = "Effects.Whirlwind", Extra = "Combat.BladeSwing", Mythic = true },
	SmokeVeil = { Cast = "Effects.Smoke", Extra = "Effects.Stealth", Mythic = true },
	Frenzy = { Cast = "Effects.Buff", Extra = "Combat.BladeSwing", Mythic = true },
	SpikedScale = { Cast = "Combat.ArmorHit", Extra = "Effects.Shield" },
	CrushingLeap = { Cast = "Movement.Jump", Impact = "Effects.GroundSlam", ImpactWindow = 1.4, Mythic = true },
	ShadowDash = { Cast = "Movement.Dash", Extra = "Effects.Poison", Mythic = true },
	BloodFury = { Cast = "Effects.Roar", Extra = "Skills.BloodPulse", Mythic = true },
	RallyingHorn = { Cast = "Effects.WarHorn", Extra = "Effects.Buff", Mythic = true },
	CleavingArc = { Cast = "Combat.HeavySwing", Impact = "Combat.FleshHit", ImpactWindow = 0.5, Mythic = true },
	GlacialPrison = { Cast = "Effects.Ice", Impact = "Effects.Ice", ImpactWindow = 1.2, Extra = "Effects.Slow", Mythic = true },
	ArcaneBarrage = { Cast = "Effects.ArcaneCast", Charge = "Effects.MagicCharge", Mythic = true },
	FanOfKnives = { Cast = "Effects.DaggerThrow", Extra = "Combat.BladeSwing", Mythic = true },
	RapidVolley = { Cast = "Combat.BowRelease", Release = "Combat.BowRelease", ReleaseDelay = 0.15, Mythic = true },
	DrumsOfWar = { Cast = "Effects.WarHorn", Extra = "Effects.Buff", Mythic = true },
	-- Boot skills (right mouse)
	CripplingStrike = { Cast = "Combat.BladeSwing", Extra = "Effects.Slow" },
	BladeDance = { Cast = "Effects.Whirlwind", Extra = "Effects.Buff" },
	Vanish = { Cast = "Effects.Smoke", Extra = "Effects.Stealth" },
	ShadeLeap = { Cast = "Effects.Teleport", Extra = "Effects.DarkMagic" },
	GaleBurst = { Cast = "Effects.Wind", Impact = "Effects.Knockback", ImpactWindow = 0.6 },
	ArcaneTempo = { Cast = "Effects.ArcaneCast", Extra = "Effects.Buff" },
	Tailwind = { Cast = "Effects.Wind", Extra = "Effects.Buff" },
	SearingRay = { Cast = "Effects.MagicCharge", Extra = "Effects.Fire" },
	PhaseShift = { Cast = "Effects.Teleport", Extra = "Effects.Shield" },
	PinningShot = { Cast = "Combat.BowRelease", Impact = "Effects.Stun", ImpactWindow = 0.6 },
	DeadeyeRhythm = { Cast = "Effects.Charge", Extra = "Effects.Buff" },
	EvasiveStride = { Cast = "Movement.Dash", Extra = "Effects.Shield" },
	RainOfArrows = { Cast = "Combat.BowRelease", Impact = "Combat.ArrowImpact", ImpactWindow = 1.2 },
	EarthenShackles = { Cast = "Effects.GroundSlam", Impact = "Effects.Stun", ImpactWindow = 0.6 },
	ThornedRhythm = { Cast = "Combat.ArmorHit", Extra = "Effects.Buff" },
	UnstoppableMarch = { Cast = "Effects.Roar", Extra = "Effects.Buff" },
	ShoulderCharge = { Cast = "Movement.Dash", Impact = "Effects.Knockback", ImpactWindow = 0.6 },
	BattleTrance = { Cast = "Effects.Roar", Extra = "Effects.Heal" },
	Warpath = { Cast = "Effects.WarHorn", Extra = "Effects.Buff" },
	SkullSplitter = { Cast = "Movement.Jump", Impact = "Combat.CriticalHit", ImpactWindow = 0.8 },
	LeapingBound = { Cast = "Movement.Jump", Extra = "Movement.Land" },
}

-- Monster identities (by MonsterType attribute / rig) ----------------------------------------
AudioConfig.Monsters = {
	Brute = { -- Stone Warden, big
		Pitch = 0.82, Volume = 1.0,
		Idle = "Monsters.StoneIdle", Alert = "Monsters.StoneAlert", AttackWindup = "Monsters.StoneAttack",
		AttackImpact = "Monsters.StoneImpact", Death = "Monsters.StoneDeath", DeathCry = "Monsters.Roar", Step = "Monsters.StoneStep",
		IdleInterval = { 7, 15 },
	},
	Minion = { -- Stone Warden, small "Ruin Crawler"
		Pitch = 1.12, Volume = 0.75,
		Idle = "Monsters.StoneIdle", Alert = "Monsters.CreatureGrowl", AttackWindup = "Monsters.CreatureGrowl",
		AttackImpact = "Monsters.StoneImpact", Death = "Monsters.StoneDeath", Step = "Monsters.StoneStep",
		IdleInterval = { 9, 18 },
	},
	Goblin = { -- lane minions
		Pitch = 1.0, Volume = 0.8,
		Idle = "Monsters.GoblinChatter", Alert = "Monsters.GoblinAlert", AttackWindup = "Monsters.GoblinAttack",
		AttackImpact = "Combat.Whiff", Death = "Monsters.GoblinDeath", Step = "Footsteps.Dirt",
		IdleInterval = { 10, 22 },
	},
	Golem = { -- Golem Heart summon
		Pitch = 0.9, Volume = 0.9,
		AttackWindup = "Monsters.GolemAttack", Death = "Monsters.StoneDeath", Step = "Monsters.GolemStep",
	},
}

--[[ SOUND LIBRARY ------------------------------------------------------------------------------
	Asset notes: 91xxxxxxxx ids are ProSoundEffects (Roblox licensed library), 18xxxxxxxx /
	9042970982 etc. are APM Music (Roblox licensed), 10066xxxxxx / 15675xxxxxx are Roblox UI sounds.
	Others are free Creator Store uploads chosen for generic, non-ripped names.
	Every id below was verified to load in Play mode (2026-09-27). ]]
local P = AudioConfig.PLACEHOLDER
AudioConfig.Sounds = {
	Music = {
		Exploration = { Ids = { 135328350514814, 131334832939011 }, Group = "Music", Volume = 0.55, Looped = true, Priority = "Critical" },
		Combat = { Ids = { 134889061669719, 1835248722 }, Group = "Music", Volume = 0.5, Looped = true, Priority = "Critical" },
		Boss = { Ids = { 1841702618, 9044584195 }, Group = "Music", Volume = 0.5, Looped = true, Priority = "Critical" },
		Lobby = { Ids = { 108104191337046 }, Group = "Music", Volume = 0.4, Looped = true, Priority = "Critical" },
		Victory = { Ids = { 1836473422, 1837930800 }, Group = "Music", Volume = 0.7, Priority = "Critical" },
		Defeat = { Ids = { 9042970982, 1842024312 }, Group = "Music", Volume = 0.7, Priority = "Critical" },
	},
	Stingers = {
		MythicReveal = { Ids = { 9125635650, 9114369623 }, Group = "UI", Volume = 0.55, Priority = "Critical" },
		BossSpawn = { Ids = { 1841353932, 1837950656 }, Group = "Music", Volume = 0.65, Priority = "Critical" },
		MatchStart = { Ids = { 6875748361, 4624851445 }, Group = "SFX", Volume = 0.55, Priority = "Critical" },
		Legendary = { Ids = { 79894991988109, 1835347947 }, Group = "UI", Volume = 0.35, Priority = "Critical" },
	},
	Ambient = {
		ForestBed = { Ids = { 9113444476, 9112802475 }, Group = "Ambient", Volume = 0.22, Looped = true, Priority = "Low" },
		CursedBed = { Ids = { 9112795463, 9114353374 }, Group = "Ambient", Volume = 0.3, Looped = true, Priority = "Low" },
		BaseBed = { Ids = { 84505057446001 }, Group = "Ambient", Volume = 0.25, Looped = true, Priority = "Low" },
		NightInsects = { Ids = { 9112764040, 9117114084 }, Group = "Ambient", Volume = 0.1, Looped = true, Priority = "Low" },
		HallBed = { Ids = { 80388954716054 }, Group = "Ambient", Volume = 0.18, Looped = true, Priority = "Low" },
		BirdChirp = { Ids = { 105990653889537, 9080200077 }, Group = "Ambient", Volume = 0.2, VolumeJitter = 0.3, Pitch = { 0.92, 1.1 }, Spatial = true, MinDistance = 20, MaxDistance = 140, Priority = "Low", Cooldown = 3 },
		WindGust = { Ids = { 224339308, 94321371111141 }, Group = "Ambient", Volume = 0.22, VolumeJitter = 0.3, Pitch = { 0.9, 1.05 }, Priority = "Low", Cooldown = 5 },
		LeavesRustle = { Ids = { 9114519078, 9114518577 }, Group = "Ambient", Volume = 0.25, VolumeJitter = 0.3, Pitch = { 0.9, 1.1 }, Spatial = true, MinDistance = 12, MaxDistance = 90, Priority = "Low", Cooldown = 3 },
		Owl = { Ids = { 9117181540, 9117181886 }, Group = "Ambient", Volume = 0.16, VolumeJitter = 0.2, Spatial = true, MinDistance = 30, MaxDistance = 160, Priority = "Low", Cooldown = 25 },
		CrowCaw = { Ids = { 9118067220, 9118066001 }, Group = "Ambient", Volume = 0.2, VolumeJitter = 0.3, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 25, MaxDistance = 150, Priority = "Low", Cooldown = 8 },
		Whisper = { Ids = { 9126213995, 9114228524 }, Group = "Ambient", Volume = 0.14, VolumeJitter = 0.3, Pitch = { 0.9, 1.0 }, Spatial = true, MinDistance = 10, MaxDistance = 70, Priority = "Low", Cooldown = 12 },
		BranchCreak = { Ids = { 9120831000, 9126263691 }, Group = "Ambient", Volume = 0.2, VolumeJitter = 0.3, Pitch = { 0.85, 1.05 }, Spatial = true, MinDistance = 15, MaxDistance = 100, Priority = "Low", Cooldown = 6 },
		DistantHowl = { Ids = { 9120790529, 9120789309 }, Group = "Ambient", Volume = 0.12, VolumeJitter = 0.2, Pitch = { 0.9, 1.0 }, Spatial = true, MinDistance = 60, MaxDistance = 250, Priority = "Low", Cooldown = 40 },
	},
	Footsteps = {
		Grass = { Ids = { 129956418693357, 78534941650081, 133687456650659 }, Group = "SFX", Volume = 0.32, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		Stone = { Ids = { 133325104274958, 93803555891980, 85328773673103 }, Group = "SFX", Volume = 0.32, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		Wood = { Ids = { 92705710431057, 121617932377026, 118963081526014 }, Group = "SFX", Volume = 0.35, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		Dirt = { Ids = { 83951881420997, 83249973538428 }, Group = "SFX", Volume = 0.35, VolumeJitter = 0.2, Pitch = { 0.92, 1.1 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		Metal = { Ids = { 129120211828684, 105780223584021, 9116669163 }, Group = "SFX", Volume = 0.3, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		Water = { Ids = { 9117940837, 9117940312, 9117942767 }, Group = "SFX", Volume = 0.3, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Medium", MaxInstances = 6 },
		ArmorRattle = { Ids = { 9116669121, 9125740352 }, Group = "SFX", Volume = 0.1, VolumeJitter = 0.3, Pitch = { 1.1, 1.3 }, Spatial = true, MinDistance = 6, MaxDistance = 45, Priority = "Low", Cooldown = 0.25, MaxInstances = 3 },
	},
	Movement = {
		Jump = { Ids = { 130071482231047, 136224586361044, 85427157842688 }, Group = "SFX", Volume = 0.35, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.2 },
		Land = { Ids = { 9113472109, 9113473249, 122835002033356 }, Group = "SFX", Volume = 0.35, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.2 },
		HeavyLand = { Ids = { 9113470178, 9113525391, 9113475819 }, Group = "SFX", Volume = 0.55, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.3 },
		Dash = { Ids = { 127385391673824, 124044443087502, 139342858021841 }, Group = "Combat", Volume = 0.5, Pitch = { 0.95, 1.1 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Fall = { Ids = { P }, Group = "SFX", Volume = 0.3, Spatial = true, Priority = "Low" }, -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET (falling wind)
	},
	Combat = {
		BladeSwing = { Ids = { 134671877618939, 138283030240531, 130891204126428 }, Group = "Combat", Volume = 0.42, VolumeJitter = 0.15, Pitch = { 1.02, 1.15 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 5 },
		SwordSwing = { Ids = { 134671877618939, 138283030240531, 130891204126428 }, Group = "Combat", Volume = 0.42, VolumeJitter = 0.15, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 5 },
		HeavySwing = { Ids = { 6241709963, 125914564702009, 114339845055217 }, Group = "Combat", Volume = 0.5, VolumeJitter = 0.15, Pitch = { 0.88, 1.0 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 4 },
		PunchSwing = { Ids = { 111254855668531, 93311226362113, 122522591098602 }, Group = "Combat", Volume = 0.4, VolumeJitter = 0.15, Pitch = { 0.95, 1.1 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 4 },
		Punch = { Ids = { 132504023010884, 126895218143022, 121339611256342 }, Group = "Combat", Volume = 0.5, VolumeJitter = 0.15, Pitch = { 0.92, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.04, MaxInstances = 4 },
		Kick = { Ids = { 138488212707530, 87184281388169, 124633350149628 }, Group = "Combat", Volume = 0.6, Pitch = { 0.92, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.05 },
		BluntHit = { Ids = { 9116488438, 127495971181378, 9113500863 }, Group = "Combat", Volume = 0.45, VolumeJitter = 0.15, Pitch = { 0.9, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.04, MaxInstances = 4 },
		FleshHit = { Ids = { 9113484620, 101309544882556, 135119591308242 }, Group = "Combat", Volume = 0.42, VolumeJitter = 0.15, Pitch = { 0.92, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.04, MaxInstances = 5 },
		CriticalHit = { Ids = { 101232234433592, 9117971636, 82235785832022 }, Group = "Combat", Volume = 0.65, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "Critical", Cooldown = 0.06, MaxInstances = 3 },
		ArmorHit = { Ids = { 9116669121, 9125740352, 93864237211566 }, Group = "Combat", Volume = 0.35, VolumeJitter = 0.2, Pitch = { 0.92, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.08, MaxInstances = 3 },
		StoneHit = { Ids = { 9125869797, 9125869505, 9118587494 }, Group = "Combat", Volume = 0.4, VolumeJitter = 0.15, Pitch = { 0.95, 1.1 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 4 },
		ShieldBlock = { Ids = { 137927717315258, 71029422716008, 73531248392900 }, Group = "Combat", Volume = 0.5, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.08 },
		Parry = { Ids = { 9119747138, 9119746751, 9113224751 }, Group = "Combat", Volume = 0.5, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.08 },
		Whiff = { Ids = { 111254855668531, 93311226362113, 122522591098602 }, Group = "Combat", Volume = 0.32, VolumeJitter = 0.2, Pitch = { 0.95, 1.12 }, Spatial = true, Priority = "Medium", Cooldown = 0.05, MaxInstances = 4 },
		BowRelease = { Ids = { 108298859110126, 136967567038278, 173979241 }, Group = "Combat", Volume = 0.45, VolumeJitter = 0.1, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 4 },
		ArrowImpact = { Ids = { 609369680, 609352672, 114751690910911 }, Group = "Combat", Volume = 0.45, VolumeJitter = 0.15, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.04, MaxInstances = 4 },
		MagicProjectile = { Ids = { 93989620006639, 130293516985070 }, Group = "Combat", Volume = 0.35, VolumeJitter = 0.1, Pitch = { 1.0, 1.15 }, Spatial = true, Priority = "High", Cooldown = 0.05, MaxInstances = 4 },
		MagicImpact = { Ids = { 130781614838570, 97512133857868, 117365336140725 }, Group = "Combat", Volume = 0.35, VolumeJitter = 0.15, Pitch = { 0.95, 1.1 }, Spatial = true, Priority = "High", Cooldown = 0.04, MaxInstances = 4 },
		Explosion = { Ids = { 138533090376585, 139900006476219, 138680390593747 }, Group = "Combat", Volume = 0.6, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 16, MaxDistance = 160, Priority = "Critical", Cooldown = 0.1, MaxInstances = 3 },
		Stagger = { Ids = { 9120416464, 9120415788, 75074552502663 }, Group = "Combat", Volume = 0.35, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.3 },
		Miss = { Alias = "Combat.Whiff", Volume = 0.25 },
	},
	Player = {
		Hurt = { Ids = { 9120417632, 9120415873, 86765830289261 }, Group = "SFX", Volume = 0.35, Pitch = { 0.95, 1.05 }, Priority = "High", Cooldown = 0.55 },
		HeavyHurt = { Ids = { 9125652443, 9125652675, 9120416707 }, Group = "SFX", Volume = 0.45, Pitch = { 0.95, 1.05 }, Priority = "Critical", Cooldown = 0.9 },
		CritHurt = { Layers = { "Combat.CriticalHit", { Cue = "Player.HeavyHurt", Delay = 0.05 } } },
		Death = { Ids = { 9125652432, 9125652466, 9114029889 }, Group = "SFX", Volume = 0.55, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "Critical", Cooldown = 0.3 },
		Heartbeat = { Ids = { 6202853067, 176554627 }, Group = "SFX", Volume = 0.45, Looped = true, Priority = "Critical" },
		Respawn = { Ids = { 115042659593009, 80326038611039 }, Group = "SFX", Volume = 0.4, Priority = "High" },
		LevelUp = { Ids = { 89481514209130, 112485797063762 }, Group = "UI", Volume = 0.45, Priority = "High" },
		Stunned = { Alias = "Effects.Stun", Spatial = false, Volume = 0.35 },
	},
	Effects = {
		MagicCharge = { Ids = { 5696557721, 7346570832 }, Group = "Combat", Volume = 0.4, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		ArcaneCast = { Ids = { 93989620006639, 74295042381271 }, Group = "Combat", Volume = 0.42, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Fire = { Ids = { 7106659874, 113831670560719 }, Group = "Combat", Volume = 0.45, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.08 },
		Ice = { Ids = { 9125611419, 103076518786222 }, Group = "Combat", Volume = 0.45, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Lightning = { Ids = { 9116281189, 9116280747 }, Group = "Combat", Volume = 0.3, VolumeJitter = 0.2, Pitch = { 1.0, 1.15 }, Spatial = true, Priority = "Medium", Cooldown = 0.12, MaxInstances = 3 },
		Wind = { Ids = { 110536638811166, 224339308 }, Group = "Combat", Volume = 0.45, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Blood = { Ids = { 8164951181, 330595293 }, Group = "Combat", Volume = 0.22, Pitch = { 0.9, 1.05 }, Spatial = true, Priority = "Medium", Cooldown = 0.1 },
		DarkMagic = { Ids = { 5696565116, 106638753466021 }, Group = "Combat", Volume = 0.3, Pitch = { 0.9, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Holy = { Ids = { 9116395089, 9116394545 }, Group = "Combat", Volume = 0.4, Pitch = { 0.98, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.1 },
		Poison = { Ids = { 9119991958, 9119991930 }, Group = "Combat", Volume = 0.3, Pitch = { 0.95, 1.1 }, Spatial = true, Priority = "Medium", Cooldown = 0.15 },
		Teleport = { Ids = { 135640489101126, 138819213201245 }, Group = "Combat", Volume = 0.45, Pitch = { 0.95, 1.08 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Shield = { Ids = { 126809328894734, 135542215299934 }, Group = "Combat", Volume = 0.45, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.15 },
		Heal = { Ids = { 93563873520722, 87617283678788 }, Group = "SFX", Volume = 0.3, Pitch = { 0.98, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.4, MaxInstances = 2 },
		Buff = { Ids = { 118447166204331, 3406813517 }, Group = "SFX", Volume = 0.35, Pitch = { 0.98, 1.05 }, Spatial = true, Priority = "Medium", Cooldown = 0.3 },
		Debuff = { Ids = { 138477691722591, 126339453064756 }, Group = "SFX", Volume = 0.35, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "Medium", Cooldown = 0.3 },
		Stun = { Ids = { 80922711052665, 139239108826837 }, Group = "Combat", Volume = 0.35, Pitch = { 0.98, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.2, MaxInstances = 2 },
		Silence = { Ids = { P }, Group = "Combat", Volume = 0.35, Spatial = true, Priority = "Medium" }, -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET (no silence mechanic yet)
		Slow = { Ids = { 112446252251908, 71299856160100 }, Group = "Combat", Volume = 0.25, Spatial = true, Priority = "Medium", Cooldown = 0.5 },
		Knockback = { Ids = { 9113077334, 9113077484 }, Group = "Combat", Volume = 0.5, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.1 },
		Summon = { Ids = { 99963459517796, 18338296739 }, Group = "Combat", Volume = 0.5, Spatial = true, Priority = "High", Cooldown = 0.3 },
		Smoke = { Ids = { 134731804861896, 110329372880748 }, Group = "Combat", Volume = 0.5, Spatial = true, Priority = "High", Cooldown = 0.2 },
		Stealth = { Ids = { 9120736182, 9120056092 }, Group = "Combat", Volume = 0.35, Spatial = true, Priority = "High", Cooldown = 0.2 },
		Reveal = { Ids = { 9116394756, 8389878748 }, Group = "Combat", Volume = 0.3, Spatial = true, Priority = "Medium", Cooldown = 0.5 },
		GroundSlam = { Ids = { 74149238738530, 124317275836539 }, Group = "Combat", Volume = 0.6, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 14, MaxDistance = 140, Priority = "Critical", Cooldown = 0.1 },
		WarHorn = { Ids = { 6875748361, 4624851445 }, Group = "Combat", Volume = 0.5, Spatial = true, MinDistance = 20, MaxDistance = 200, Priority = "High", Cooldown = 1 },
		Roar = { Ids = { 76542353361181, 90430304231403 }, Group = "Combat", Volume = 0.28, Pitch = { 0.95, 1.05 }, Spatial = true, MinDistance = 14, MaxDistance = 140, Priority = "High", Cooldown = 0.5 },
		Whirlwind = { Ids = { 111041932147500, 9120733724 }, Group = "Combat", Volume = 0.5, Spatial = true, Priority = "High", Cooldown = 0.15 },
		DaggerThrow = { Ids = { 9125620110, 9125619884 }, Group = "Combat", Volume = 0.45, Pitch = { 1.0, 1.1 }, Spatial = true, Priority = "High", Cooldown = 0.08 },
		Charge = { Ids = { 100719595855360, 139493189032178 }, Group = "Combat", Volume = 0.4, Spatial = true, Priority = "High", Cooldown = 0.15 },
		MythicShimmer = { Ids = { 9116393976, 9116393765 }, Group = "SFX", Volume = 0.18, Pitch = { 1.0, 1.08 }, Spatial = true, Priority = "Medium", Cooldown = 0.2 },
		Reflect = { Alias = "Effects.Lightning", Volume = 0.25 },
	},
	Skills = {
		ArcaneTravel = { Ids = { 9116394525, 9116395085 }, Group = "Combat", Volume = 0.18, Pitch = { 1.05, 1.2 }, Spatial = true, MinDistance = 6, MaxDistance = 60, Priority = "Low", MaxInstances = 4 },
		ArcaneExplosion = { Layers = { "Combat.Explosion", { Cue = "Effects.DarkMagic", Volume = 0.7 } } },
		FireLaunch = { Ids = { 7106659874, 113831670560719 }, Group = "Combat", Volume = 0.5, Pitch = { 0.95, 1.05 }, Spatial = true, Priority = "High", Cooldown = 0.08 },
		FireTravel = { Ids = { 113831670560719 }, Group = "Combat", Volume = 0.25, Pitch = { 0.8, 0.9 }, Spatial = true, MinDistance = 6, MaxDistance = 70, Priority = "Low", MaxInstances = 3 },
		FireImpact = { Layers = { "Combat.Explosion", { Cue = "Effects.Fire", Volume = 0.8 } } },
		PowerShot = { Layers = { "Combat.BowRelease", { Cue = "Effects.Charge", Volume = 0.35 } } },
		PowerShotTravel = { Ids = { 9113077334 }, Group = "Combat", Volume = 0.25, Pitch = { 1.1, 1.2 }, Spatial = true, MinDistance = 8, MaxDistance = 80, Priority = "Low", MaxInstances = 3 },
		BloodPulse = { Layers = { "Effects.Blood", { Cue = "Effects.DarkMagic", Volume = 0.45, Delay = 0.05 } } },
	},
	Monsters = {
		StoneIdle = { Ids = { 9114628818, 9125470786, 9114630281 }, Group = "SFX", Volume = 0.2, VolumeJitter = 0.25, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 10, MaxDistance = 70, Priority = "Low", MaxInstances = 3 },
		StoneAlert = { Ids = { 119184309554795, 114600180172960, 133651202885353 }, Group = "SFX", Volume = 0.25, Pitch = { 0.95, 1.05 }, Spatial = true, MinDistance = 14, MaxDistance = 120, Priority = "High", Cooldown = 1 },
		StoneAttack = { Ids = { 9125842137, 9125842589, 84183219139808 }, Group = "Combat", Volume = 0.25, VolumeJitter = 0.15, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 10, MaxDistance = 90, Priority = "High", Cooldown = 0.2, MaxInstances = 3 },
		StoneImpact = { Ids = { 9125869797, 9125869505, 9118587494 }, Group = "Combat", Volume = 0.5, Pitch = { 0.9, 1.05 }, Spatial = true, MinDistance = 10, MaxDistance = 90, Priority = "High", Cooldown = 0.1, MaxInstances = 3 },
		StoneDeath = { Ids = { 9118586430, 139037180974154, 9118692390 }, Group = "SFX", Volume = 0.35, Pitch = { 0.9, 1.05 }, Spatial = true, MinDistance = 14, MaxDistance = 120, Priority = "High", Cooldown = 0.1 },
		StoneStep = { Ids = { 106345699720712, 9114165461, 134690409222127 }, Group = "SFX", Volume = 0.25, VolumeJitter = 0.2, Pitch = { 0.9, 1.1 }, Spatial = true, MinDistance = 8, MaxDistance = 60, Priority = "Low", MaxInstances = 4 },
		GoblinChatter = { Ids = { 9114625205, 9114625192, 9114625189 }, Group = "SFX", Volume = 0.22, VolumeJitter = 0.25, Pitch = { 1.05, 1.3 }, Spatial = true, MinDistance = 8, MaxDistance = 55, Priority = "Low", Cooldown = 1.5, MaxInstances = 2 },
		GoblinAlert = { Ids = { 9114624345, 9125474511 }, Group = "SFX", Volume = 0.2, Pitch = { 1.1, 1.3 }, Spatial = true, MinDistance = 8, MaxDistance = 70, Priority = "Medium", Cooldown = 1.2, MaxInstances = 2 },
		GoblinAttack = { Ids = { 9114624343, 9125475724 }, Group = "Combat", Volume = 0.18, VolumeJitter = 0.2, Pitch = { 1.1, 1.35 }, Spatial = true, MinDistance = 8, MaxDistance = 60, Priority = "Medium", Cooldown = 0.25, MaxInstances = 3 },
		GoblinDeath = { Ids = { 9125474560, 9113793916 }, Group = "SFX", Volume = 0.22, Pitch = { 1.05, 1.25 }, Spatial = true, MinDistance = 8, MaxDistance = 70, Priority = "Medium", Cooldown = 0.1, MaxInstances = 3 },
		GolemStep = { Ids = { 137770631794060, 116277856231702, 9114036511 }, Group = "SFX", Volume = 0.3, Pitch = { 0.9, 1.05 }, Spatial = true, MinDistance = 8, MaxDistance = 60, Priority = "Low", MaxInstances = 3 },
		GolemAttack = { Ids = { 74149238738530, 124317275836539, 127391319566407 }, Group = "Combat", Volume = 0.5, Pitch = { 0.92, 1.05 }, Spatial = true, MinDistance = 12, MaxDistance = 100, Priority = "High", Cooldown = 0.2 },
		CreatureGrowl = { Ids = { 9113973520, 9113971531, 9125889406 }, Group = "SFX", Volume = 0.18, Pitch = { 0.95, 1.1 }, Spatial = true, MinDistance = 10, MaxDistance = 80, Priority = "Medium", Cooldown = 0.4, MaxInstances = 3 },
		Roar = { Ids = { 114600180172960, 109312518223078, 73347268205810 }, Group = "SFX", Volume = 0.22, Pitch = { 0.9, 1.0 }, Spatial = true, MinDistance = 20, MaxDistance = 180, Priority = "Critical", Cooldown = 1 },
		-- Future creature families: add ids and reference them from AudioConfig.Monsters
		WolfHowl = { Alias = "Ambient.DistantHowl", Group = "SFX", Volume = 0.4 },
		BatScreech = { Ids = { P }, Group = "SFX", Spatial = true, Priority = "Medium" }, -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET
		UndeadGroan = { Ids = { P }, Group = "SFX", Spatial = true, Priority = "Medium" }, -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET
		DemonGrowl = { Alias = "Monsters.StoneAttack", Pitch = { 0.7, 0.8 } },
		WingFlap = { Ids = { P }, Group = "SFX", Spatial = true, Priority = "Low" }, -- REPLACE WITH APPROPRIATE ROBLOX AUDIO ASSET
	},
	Objectives = {
		RuinSpawn = { Layers = { "Stingers.BossSpawn", { Cue = "Objectives.RuinPortal", Delay = 0.1 } } },
		RuinPortal = { Ids = { 110613808041774, 109286612583064 }, Group = "SFX", Volume = 0.55, Spatial = true, MinDistance = 30, MaxDistance = 400, Priority = "Critical", Cooldown = 1 },
		RuinDestroyed = { Ids = { 9116384473, 9116384485 }, Group = "SFX", Volume = 0.65, Spatial = true, MinDistance = 30, MaxDistance = 400, Priority = "Critical", Cooldown = 1 },
		RuinTelegraph = { Alias = "Effects.MagicCharge", Volume = 0.5 },
		FlagDestroyed = { Ids = { 9114604477, 9113966327 }, Group = "SFX", Volume = 0.6, Priority = "Critical", Cooldown = 1 },
		FlagRestored = { Ids = { 9116394525, 9116395085 }, Group = "SFX", Volume = 0.5, Priority = "Critical", Cooldown = 1 },
		FlagHit = { Alias = "Combat.StoneHit", Volume = 0.35 },
		FragmentSpawn = { Ids = { 9116394876, 118091077749326 }, Group = "SFX", Volume = 0.4, Spatial = true, MinDistance = 20, MaxDistance = 250, Priority = "High", Cooldown = 1 },
		FragmentPickup = { Ids = { 106586585181583, 723157335 }, Group = "SFX", Volume = 0.45, Spatial = true, Priority = "High", Cooldown = 0.5 },
		MinionWave = { Ids = { 9114820503, 9114821239 }, Group = "SFX", Volume = 0.3, Priority = "Medium", Cooldown = 5 },
		Countdown = { Ids = { 119133534035860, 90302428165264 }, Group = "UI", Volume = 0.35, Priority = "High", Cooldown = 0.5 },
	},
	UI = {
		Hover = { Ids = { 10066931761, 10066936758 }, Group = "UI", Volume = 0.18, Pitch = { 0.98, 1.05 }, Priority = "Low", Cooldown = 0.06 },
		Click = { Ids = { 15675032796, 10128760939 }, Group = "UI", Volume = 0.4, Priority = "Medium", Cooldown = 0.05 },
		Disabled = { Ids = { 15675075163 }, Group = "UI", Volume = 0.3, Priority = "Medium", Cooldown = 0.15 },
		MenuOpen = { Ids = { 15675037413, 15675024286 }, Group = "UI", Volume = 0.35, Priority = "Medium", Cooldown = 0.15 },
		MenuClose = { Ids = { 10066914500, 15675028888 }, Group = "UI", Volume = 0.3, Priority = "Medium", Cooldown = 0.15 },
		Purchase = { Ids = { 10066947742, 133570405319995 }, Group = "UI", Volume = 0.5, Priority = "High", Cooldown = 0.1 },
		PurchaseFail = { Ids = { 96076237507837, 83600603085349 }, Group = "UI", Volume = 0.3, Priority = "High", Cooldown = 0.3 },
		Equip = { Ids = { 82479764694278, 130560557198529 }, Group = "UI", Volume = 0.45, Priority = "High", Cooldown = 0.1 },
		Unequip = { Ids = { 81904985537003, 97568182472477 }, Group = "UI", Volume = 0.4, Priority = "High", Cooldown = 0.1 },
		Sell = { Ids = { 134911555436784, 1210852193 }, Group = "UI", Volume = 0.4, Priority = "High", Cooldown = 0.1 },
		Notification = { Ids = { 107978604605265, 15675085146 }, Group = "UI", Volume = 0.25, Priority = "Medium", Cooldown = 0.4 },
		Confirm = { Ids = { 10066968815, 15675059323 }, Group = "UI", Volume = 0.35, Priority = "Medium", Cooldown = 0.1 },
		Error = { Ids = { 124387798635805, 10066926605 }, Group = "UI", Volume = 0.3, Priority = "Medium", Cooldown = 0.35 },
		Upgrade = { Ids = { 112485797063762, 89481514209130 }, Group = "UI", Volume = 0.45, Priority = "High", Cooldown = 0.2 },
		SkillUnlock = { Ids = { 9116393976, 9116393765 }, Group = "UI", Volume = 0.4, Priority = "High", Cooldown = 0.2 },
		MythicEquip = { Ids = { 9116384762, 9116385087 }, Group = "UI", Volume = 0.4, Priority = "High", Cooldown = 0.2 },
		InventoryOpen = { Alias = "UI.MenuOpen" },
		InventoryClose = { Alias = "UI.MenuClose" },
		QuestAccepted = { Alias = "UI.Confirm" }, -- no quest system yet: hook here when one exists
		QuestCompleted = { Alias = "UI.Upgrade" },
		-- Composite shop cues (sent by the server in Notify Options.Sound)
		MythicAcquire = { Layers = { { Cue = "Effects.MagicCharge", Volume = 0.6, Spatial = false }, { Cue = "Stingers.MythicReveal", Delay = 0.35 }, { Cue = "UI.MythicEquip", Delay = 0.45 }, { Cue = "Stingers.Legendary", Delay = 0.5 } } },
		BootsAcquire = { Layers = { "UI.Purchase", { Cue = "UI.Equip", Delay = 0.15 } } },
		SupplyPurchase = { Layers = { "UI.Purchase", { Cue = "Effects.Buff", Delay = 0.1, Volume = 0.6, Spatial = false } } },
		MinionUpgrade = { Layers = { "UI.Upgrade", { Cue = "Objectives.MinionWave", Delay = 0.2, Volume = 0.7 } } },
	},
}

-- Notify style -> default UI sound (used when the server does not name a sound) -------------
AudioConfig.NotifyStyles = {
	Info = "UI.Notification",
	Success = "UI.Confirm",
	Warning = "UI.Error",
	Danger = "UI.Error",
	Ruin = nil, -- the Ruin effect already has its own cue
	Buff = "Effects.Buff",
	Fragment = "Objectives.FragmentPickup",
}

return AudioConfig
