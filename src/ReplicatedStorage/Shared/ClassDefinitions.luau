-- ClassDefinitions: the five playable classes.
-- Ratings (1-5) are for UI only; gameplay uses the raw stats.
-- Ability Damage values are scaling tables (see Shared.AbilityScaling):
-- { AD = 3.75 } = 375% of the hero's current attack damage (base + items).

local ClassDefinitions = {}

ClassDefinitions.Order = { "Assassin", "Mage", "Marksman", "Tank", "Fighter" }

ClassDefinitions.Classes = {
	Assassin = {
		Key = "Assassin",
		DisplayName = "Assassin",
		Role = "Burst / Mobility",
		Icon = "A",
		IconImage = "rbxassetid://122959683753829", -- Blender emblem: crossed daggers
		Color = Color3.fromRGB(200, 40, 60),
		SecondaryColor = Color3.fromRGB(28, 22, 30),
		Ratings = { Health = 1, Damage = 5, Range = 1, Speed = 5, Armor = 1 },
		MaxHealth = 520,
		Armor = 10,
		MoveSpeed = 22,
		HealthRegen = 0.012, -- fraction of max health per second out of combat
		AttackType = "Melee",
		AttackDamage = 46,
		AttackRange = 7.5,
		AttackCooldown = 0.55,
		MeleeArc = 80,
		Cleave = false,
		Ability = {
			Key = "ShadowStep",
			Name = "Shadow Step",
			Description = "Dash toward the cursor, vanish from enemy sight and empower your next strike (x2 damage).",
			Cooldown = 7,
			DashDistance = 24,
			StealthDuration = 3,
			NextAttackMultiplier = 2,
			EmpowerWindow = 5,
		},
	},
	Mage = {
		Key = "Mage",
		DisplayName = "Mage",
		Role = "Ranged AoE",
		Icon = "M",
		IconImage = "rbxassetid://113196464165818", -- Blender emblem: arcane staff
		Color = Color3.fromRGB(150, 80, 255),
		SecondaryColor = Color3.fromRGB(40, 28, 70),
		Ratings = { Health = 1, Damage = 4, Range = 4, Speed = 2, Armor = 1 },
		MaxHealth = 480,
		Armor = 8,
		MoveSpeed = 16,
		HealthRegen = 0.012,
		AttackType = "Projectile",
		AttackDamage = 40,
		MagicPower = 40, -- base Magic Power: Arcane Burst and every Mage item skill scale on it
		AttackRange = 30,
		AttackCooldown = 0.9,
		Projectile = { Speed = 70, Radius = 1.3, Style = "Arcane" },
		Ability = {
			Key = "ArcaneBurst",
			Name = "Arcane Burst",
			Description = "After a short channel, detonate arcane energy at the cursor, dealing 375% Magic Power to every enemy in the area.",
			Cooldown = 4,
			ManaCost = 80,
			CastRange = 45,
			Radius = 7,
			Damage = { MP = 3.75 },
			Delay = 0.55,
		},
	},
	Marksman = {
		Key = "Marksman",
		DisplayName = "Marksman",
		Role = "Long-range DPS",
		Icon = "K",
		IconImage = "rbxassetid://77589325068041", -- Blender emblem: bow and arrow
		Color = Color3.fromRGB(70, 200, 90),
		SecondaryColor = Color3.fromRGB(60, 45, 30),
		Ratings = { Health = 3, Damage = 4, Range = 5, Speed = 3, Armor = 1 },
		MaxHealth = 600,
		Armor = 12,
		MoveSpeed = 18,
		HealthRegen = 0.012,
		AttackType = "Projectile",
		AttackDamage = 30,
		AttackRange = 45,
		AttackCooldown = 0.6,
		Projectile = { Speed = 115, Radius = 0.9, Style = "Arrow" },
		Ability = {
			Key = "DashShot",
			Name = "Dash Shot",
			Description = "Leap backward and loose a piercing power shot toward the cursor (220% attack damage).",
			Cooldown = 7,
			DashDistance = 16,
			Damage = { AD = 2.2 },
			ProjectileSpeed = 160,
			ProjectileRadius = 1.4,
			Range = 85,
		},
	},
	Tank = {
		Key = "Tank",
		DisplayName = "Tank",
		Role = "Frontline / Crowd Control",
		Icon = "T",
		IconImage = "rbxassetid://89176805824795", -- Blender emblem: tower shield
		Color = Color3.fromRGB(60, 110, 220),
		SecondaryColor = Color3.fromRGB(120, 130, 150),
		Ratings = { Health = 5, Damage = 2, Range = 1, Speed = 1, Armor = 5 },
		MaxHealth = 1100,
		Armor = 45,
		MoveSpeed = 15,
		HealthRegen = 0.015,
		AttackType = "Melee",
		AttackDamage = 34,
		AttackRange = 8.5,
		AttackCooldown = 1.0,
		MeleeArc = 120,
		Cleave = true,
		Ability = {
			Key = "TauntingShockwave",
			Name = "Taunting Shockwave",
			Description = "Slam the ground: deal 80% attack damage + 3% max health to nearby enemies, stun them and force them to attack you.",
			Cooldown = 10,
			Radius = 16,
			Damage = { AD = 0.8, HP = 0.03 },
			StunDuration = 1.2,
			TauntDuration = 2.5,
		},
	},
	Fighter = {
		Key = "Fighter",
		DisplayName = "Fighter",
		Role = "Balanced Bruiser",
		Icon = "F",
		IconImage = "rbxassetid://98048107932628", -- Blender emblem: sword and axe
		Color = Color3.fromRGB(255, 150, 40),
		SecondaryColor = Color3.fromRGB(90, 60, 30),
		Ratings = { Health = 4, Damage = 3, Range = 1, Speed = 3, Armor = 3 },
		MaxHealth = 900,
		Armor = 30,
		MoveSpeed = 18,
		HealthRegen = 0.012,
		AttackType = "Melee",
		AttackDamage = 42,
		AttackRange = 8,
		AttackCooldown = 0.75,
		MeleeArc = 100,
		Cleave = false,
		Ability = {
			Key = "BloodRush",
			Name = "Blood Rush",
			Description = "For 5s gain +60% attack speed, +25% move speed and 30% lifesteal.",
			Cooldown = 11,
			Duration = 5,
			AttackSpeedMultiplier = 1.6,
			MoveSpeedMultiplier = 1.25,
			Lifesteal = 0.3,
		},
	},
}

-- Royale weapons: every hero starts with the Fighter's sword; picking up another class's
-- weapon turns the hero into that class (its stats, basic attack and Q ability).
ClassDefinitions.Weapons = {
	Assassin = "Twin Shadow Daggers",
	Mage = "Arcane Staff",
	Marksman = "Hunter's Longbow",
	Tank = "Tower Shield & Mace",
	Fighter = "Soldier's Sword",
}

function ClassDefinitions.GetWeaponName(classKey)
	return ClassDefinitions.Weapons[classKey] or (classKey .. " weapon")
end

-- The Q skill of a class (kept as a helper for UI code)
function ClassDefinitions.GetAbility(classKey)
	local classDef = ClassDefinitions.Classes[classKey]
	return classDef and classDef.Ability or nil
end

function ClassDefinitions.Get(classKey)
	return ClassDefinitions.Classes[classKey]
end

function ClassDefinitions.IsValid(classKey)
	return type(classKey) == "string" and ClassDefinitions.Classes[classKey] ~= nil
end

return ClassDefinitions
