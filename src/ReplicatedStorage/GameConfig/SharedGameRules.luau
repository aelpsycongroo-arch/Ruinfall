-- SharedGameRules
-- ============================================================================
-- Authoritative design specification for the item economy and AI collaboration.
-- This file is NOT gameplay code. It is a machine-readable rules document that AI
-- agents (and human developers) should consult BEFORE creating or modifying game
-- systems. The live gameplay implementation lives in ReplicatedStorage.Shared
-- (ItemDefinitions, ShopDefinitions, AbilityScaling, etc.).
--
-- AI COLLABORATION RULE — read this before making any gameplay-related change:
--   1. Read this file.
--   2. Follow all existing rules.
--   3. Do not silently change or remove rules.
--   4. If a requested change conflicts with an existing rule, preserve the rule
--      and adapt the implementation.
--   5. Only modify this file when explicitly instructed by the developer/user.
--   6. Do not create duplicate rule files containing conflicting versions.
--   7. Keep the rules concise and machine-readable where practical.
-- ============================================================================

local SharedGameRules = {}

SharedGameRules.Version = 1
SharedGameRules.LastUpdated = "2025-01-01"

----------------------------------------------------------------------------
-- 1. AI COLLABORATION RULES
----------------------------------------------------------------------------
SharedGameRules.AICollaboration = {
	ReadBeforeChanges = true,
	FollowExistingRules = true,
	DoNotSilentlyChangeOrRemoveRules = true,
	ConflictResolution = "Preserve the rule and adapt the implementation",
	ModifyOnlyWhenInstructed = true,
	NoDuplicateRuleFiles = true,
	KeepConciseAndMachineReadable = true,
}

----------------------------------------------------------------------------
-- 2. ITEM ECONOMY — TOTAL VALUE MUST MATCH PRICE
----------------------------------------------------------------------------
SharedGameRules.ItemEconomy = {
	Formula = "TotalItemValue = StatValue + SkillValue + OtherGameplayValue",
	Constraint = "TotalItemValue should approximately equal the item's gold cost",
	Tolerance = 10, -- gold; items should be within ~10g of their price
	ValueSources = {
		"Raw statistics",
		"Passive effects",
		"Active abilities",
		"Mobility",
		"Range",
		"Crowd control",
		"Defensive effects",
		"Offensive effects",
		"Utility",
		"Other meaningful gameplay advantages",
	},
}

----------------------------------------------------------------------------
-- 3. SKILLS MUST HAVE AN ECONOMIC VALUE
----------------------------------------------------------------------------
SharedGameRules.SkillEconomy = {
	Principle = "Active and passive skills are NOT free. Every meaningful skill must have an estimated gold value.",
	Formula = "ItemCost = SkillValue + StatValue + OtherValue",
	Example = {
		ItemPrice = 550,
		DashSkillValue = 300,
		RemainingValue = 250,
		Note = "Only ~250g remains for stats and other effects. Do NOT give the item another large amount of statistics as though the dash had no economic value.",
	},
}

----------------------------------------------------------------------------
-- 4. STRONGER SKILLS REQUIRE GREATER STAT TRADEOFFS
----------------------------------------------------------------------------
SharedGameRules.StrongSkillTradeoffs = {
	Principle = "When an item has an unusually powerful ability, its statistics should generally be reduced to compensate.",
	HighValueEffects = {
		"Long-distance dash",
		"Very short cooldown mobility",
		"Large-area crowd control",
		"Powerful burst damage",
		"Point-and-click damage",
		"Strong defensive reflection",
		"High damage reduction",
		"Reliable escape abilities",
		"Long-range displacement",
		"Strong enemy displacement",
		"Multiple useful effects combined together",
	},
	Rule = "The stronger or more reliable the ability is, the more of the item's budget it should consume.",
}

----------------------------------------------------------------------------
-- 5. DO NOT DOUBLE-COUNT VALUE
----------------------------------------------------------------------------
SharedGameRules.NoDoubleCounting = {
	Principle = "Do not treat a skill as having zero value simply because it is attached to an item.",
	Acceptable = {
		ItemPrice = 1000,
		StatValue = 500,
		SkillValue = 500,
		Total = 1000,
		Note = "Total equals price — this is acceptable.",
	},
	OverBudget = {
		ItemPrice = 1000,
		StatValue = 1000,
		SkillValue = 500,
		Total = 1500,
		Note = "Total exceeds price by 500 — this is significantly over-budget.",
	},
}

----------------------------------------------------------------------------
-- 6. VALUE ESTIMATES MUST BE CONSISTENT
----------------------------------------------------------------------------
SharedGameRules.ConsistentValuation = {
	Principle = "Use the same general valuation philosophy across the entire game. If a particular effect is established at a given gold value, use that same value consistently.",
}

----------------------------------------------------------------------------
-- LIVE IMPLEMENTATION REFERENCES
-- These point to the existing modules that implement these rules in code.
-- AI agents should use these functions to verify budget compliance.
----------------------------------------------------------------------------
SharedGameRules.LiveImplementation = {
	ItemDefinitions = "ReplicatedStorage.Shared.ItemDefinitions",
	ShopDefinitions = "ReplicatedStorage.Shared.ShopDefinitions",
	AbilityScaling = "ReplicatedStorage.Shared.AbilityScaling",
	Functions = {
		GetItemGoldValue = "ItemDefinitions.GetItemGoldValue(item) -> statGold, skillGold, passiveGold, total",
		GetStatGoldValue = "ItemDefinitions.GetStatGoldValue(item) -> statGold",
		SKILL_VALUE = "ItemDefinitions.SKILL_VALUE (currently 250g) — baseline gold value for an active skill",
		PASSIVE_VALUE = "ItemDefinitions.PASSIVE_VALUE (currently 100g) — baseline gold value for a passive effect",
	},
	StatGoldPerPoint = {
		MaxHealth = "250g per 150 HP = ~1.67g per HP (from ShopDefinitions.Vitality)",
		Armor = "200g per 12 armor = ~16.67g per armor (from ShopDefinitions.Iron)",
		MoveSpeed = "200g per 3 move speed = ~66.67g per move speed (from ShopDefinitions.Swift)",
		AttackDamage = "300g per 12 AD = 25g per AD (from ShopDefinitions.Power)",
		HealthRegen = "150g per 0.004 regen = 37500g per 1.0 regen (from ShopDefinitions.Regen)",
		AttackSpeed = "1500g per +1.0 (100%) attack speed (from ItemDefinitions.EXTRA_STAT_VALUES)",
	},
}

return SharedGameRules
