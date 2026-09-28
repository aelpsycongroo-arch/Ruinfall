-- CombatDefinitions: damage formula, ruin buffs, monsters, projectile visuals

local CombatDefinitions = {}

-- Damage formula: FinalDamage = RawDamage * 100 / (100 + Armor)
-- 0 armor = full damage, 25 armor = 80%, 45 armor = 69%.
function CombatDefinitions.ArmorMultiplier(armor)
	return 100 / (100 + math.max(0, armor or 0))
end

-- Mana: every hero has a mana pool (Base + Mana from items) that regenerates over time.
-- E / R item skills cost mana (ItemDefinitions.GetManaCost). A class Q costs mana only when its
-- ability sets ManaCost (Mage Arcane Burst: 80 - checked / spent in AbilityService.Use). LM and boots
-- are free, except boot skills that set ManaCost (all Mage boots - see ItemDefinitions.GetSlotManaCost).
CombatDefinitions.Mana = { Base = 300, RegenPerSecond = 6 }

-- Critical Chance (item stat): basic attacks that crit deal CritMultiplier x damage
CombatDefinitions.CritMultiplier = 1.5

-- Cooldown Reduction (item stat) is capped so skills never become spammable
CombatDefinitions.MaxCooldownReduction = 0.4

-- Magic Defense (item stat): reduces damage taken from skills (Q / E / R / RMB) and magic
-- effects (burn, poison, lightning, auras) with the same curve as armor, on top of armor.
function CombatDefinitions.MagicDefenseMultiplier(magicDefense)
	return 100 / (100 + math.max(0, magicDefense or 0))
end

-- Ruin buffs (temporary, lost on death) -------------------------------------
CombatDefinitions.BuffOrder = { "SpeedCore", "ArcCore", "ShieldCore", "BloodCore" }
CombatDefinitions.Buffs = {
	SpeedCore = {
		Key = "SpeedCore",
		Name = "Speed Core",
		Description = "+25% movement speed",
		Color = Color3.fromRGB(90, 230, 255),
		Duration = 60,
		SpeedMultiplier = 1.25,
	},
	ArcCore = {
		Key = "ArcCore",
		Name = "Arc Core",
		Description = "Attacks chain lightning to a nearby enemy",
		Color = Color3.fromRGB(255, 240, 90),
		Duration = 60,
		ChainDamagePercent = 0.45,
		ChainRange = 16,
	},
	ShieldCore = {
		Key = "ShieldCore",
		Name = "Shield Core",
		Description = "Absorbs the next 300 damage",
		Color = Color3.fromRGB(150, 210, 255),
		Duration = 60,
		ShieldAmount = 300,
	},
	BloodCore = {
		Key = "BloodCore",
		Name = "Blood Core",
		Description = "+20% lifesteal",
		Color = Color3.fromRGB(255, 60, 90),
		Duration = 60,
		Lifesteal = 0.2,
	},
}

-- Neutral monsters ---------------------------------------------------------------
CombatDefinitions.Monsters = {
	Minion = {
		Key = "Minion",
		Name = "Ruin Crawler",
		MaxHealth = 280,
		Armor = 10,
		Damage = 16,
		AttackRange = 5.5,
		AttackCooldown = 1.2,
		MoveSpeed = 14,
		Scale = 1,
		Color = Color3.fromRGB(70, 60, 80),
		EyeColor = Color3.fromRGB(220, 70, 20),
		StoneColor = Color3.fromRGB(70, 68, 72),
		KillHealPercent = 0.06,
	},
	Brute = {
		Key = "Brute",
		Name = "Ruin Brute",
		MaxHealth = 720,
		Armor = 20,
		Damage = 32,
		AttackRange = 7,
		AttackCooldown = 1.6,
		MoveSpeed = 12,
		Scale = 1.6,
		Color = Color3.fromRGB(90, 55, 45),
		EyeColor = Color3.fromRGB(230, 105, 15),
		StoneColor = Color3.fromRGB(80, 78, 76),
		KillHealPercent = 0.12,
	},
}
CombatDefinitions.CampComposition = { "Brute", "Minion", "Minion" }

-- Projectile visual styles (client) ------------------------------------------------
CombatDefinitions.ProjectileStyles = {
	Arcane = { Color = Color3.fromRGB(180, 110, 255), Size = Vector3.new(1.3, 1.3, 1.3), Shape = "Ball", Light = true },
	Fireball = { Color = Color3.fromRGB(255, 120, 40), Size = Vector3.new(1.6, 1.6, 1.6), Shape = "Ball", Light = true },
	Arrow = { Color = Color3.fromRGB(120, 255, 140), Size = Vector3.new(0.35, 0.35, 2.4), Shape = "Block", Light = false },
	PowerShot = { Color = Color3.fromRGB(210, 255, 120), Size = Vector3.new(0.8, 0.8, 4), Shape = "Block", Light = true },
	Knife = { Color = Color3.fromRGB(215, 220, 235), Size = Vector3.new(0.3, 0.2, 1.8), Shape = "Block", Light = false },
	Default = { Color = Color3.fromRGB(230, 230, 230), Size = Vector3.new(0.6, 0.6, 0.6), Shape = "Ball", Light = false },
}

return CombatDefinitions
