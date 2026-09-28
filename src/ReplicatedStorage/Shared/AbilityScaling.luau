-- AbilityScaling
-- Resolves ability damage, shields, and heals from the caster's CURRENT stats.
--
-- Scaling examples:
--   { AD = 2.4 }                  -> 240% Attack Damage
--   { MP = 2.4 }                  -> 240% Magic Power
--   { AD = 1.0, MP = 1.5 }        -> 100% AD + 150% Magic Power
--   { AD = 1.0, HP = 0.05 }       -> 100% AD + 5% Max HP
--   { HP = 0.13 }                 -> 13% Max HP
--   { Armor = 1.5 }               -> 150% Armor
--
-- Stats:
--   AD    = total Attack Damage
--   HP    = Max Health
--   Armor = total Armor
--   MP    = Magic Power (class base MagicPower + Magic Power from items)
--
-- IMPORTANT:
-- Magic Power is NO LONGER automatically added to Attack Damage.
-- Abilities must explicitly use { MP = X } if they scale from Magic Power.
--
-- Server resolves values at cast time.
-- Client can use the same functions for live tooltip numbers.

local AbilityScaling = {}

----------------------------------------------------------------
-- AVAILABLE STATS
----------------------------------------------------------------

AbilityScaling.STATS = {
	"AD",
	"HP",
	"Armor",
	"MP",
}

AbilityScaling.LABELS = {
	AD = "Attack Damage",
	HP = "Max Health",
	Armor = "Armor",
	MP = "Magic Power",
}

AbilityScaling.SHORT = {
	AD = "AD",
	HP = "max HP",
	Armor = "armor",
	MP = "Magic Power",
}

----------------------------------------------------------------
-- ABILITY FIELDS THAT SUPPORT SCALING
----------------------------------------------------------------

AbilityScaling.SCALED_FIELDS = {
	"Damage",
	"Shield",
	"Heal",
}

----------------------------------------------------------------
-- CHECK IF VALUE IS A SCALING TABLE
----------------------------------------------------------------

function AbilityScaling.IsScaling(value)
	return type(value) == "table"
end

----------------------------------------------------------------
-- GET CURRENT STATS FROM SERVER ENTITY
----------------------------------------------------------------

function AbilityScaling.StatsFromEntity(entity)
	if not entity then
		return {
			AD = 0,
			HP = 0,
			Armor = 0,
			MP = 0,
		}
	end

	local baseAD =
		entity.Class and entity.Class.AttackDamage
		or entity.AttackDamage
		or 0

	return {
		AD =
			baseAD
			+ (entity.BonusAttackDamage or 0)
			+ (entity.PassiveAttackDamage or 0),

		HP = entity.MaxHealth or 0,

		Armor = entity.Armor or 0,

		MP = (entity.Class and entity.Class.MagicPower or 0)
			+ (entity.BonusMagicPower or 0),
	}
end

----------------------------------------------------------------
-- GET CURRENT STATS FROM REPLICATED HERO MODEL
-- Used by client-side HUD / tooltips.
----------------------------------------------------------------

function AbilityScaling.StatsFromModel(model)
	if not model then
		return nil
	end

	local ad = model:GetAttribute("AttackDamage")

	if not ad then
		return nil
	end

	return {
		AD = ad,

		HP = model:GetAttribute("MaxHealth") or 0,

		Armor = model:GetAttribute("Armor") or 0,

		MP = model:GetAttribute("MagicPower") or 0,
	}
end

----------------------------------------------------------------
-- COMPUTE A SCALING TABLE
--
-- Example:
-- scaling = { AD = 2.0, MP = 1.5 }
--
-- AD = 100
-- MP = 50
--
-- Result:
-- 100 * 2.0 + 50 * 1.5
-- = 275
----------------------------------------------------------------

function AbilityScaling.Compute(scaling, stats)
	if type(scaling) == "number" then
		return scaling
	end

	if type(scaling) ~= "table" then
		return 0
	end

	stats = stats or {}

	local total = 0

	for _, stat in ipairs(AbilityScaling.STATS) do
		local ratio = scaling[stat]

		if ratio then
			total += ratio * (stats[stat] or 0)
		end
	end

	return total
end

----------------------------------------------------------------
-- RESOLVE ABILITY VALUES
--
-- IMPORTANT:
-- No automatic MP -> AD conversion.
--
-- This means:
--
-- { AD = 2.4 }
--     = 240% AD
--
-- { MP = 2.4 }
--     = 240% Magic Power
--
-- { AD = 1.0, MP = 1.5 }
--     = 100% AD + 150% Magic Power
----------------------------------------------------------------

function AbilityScaling.Resolve(ability, stats)
	local resolved = table.clone(ability)

	for _, field in ipairs(AbilityScaling.SCALED_FIELDS) do
		if type(ability[field]) == "table" then
			resolved[field] = math.floor(
				AbilityScaling.Compute(ability[field], stats) + 0.5
			)
		end
	end

	-- Keep original scaling data for tooltips / debugging.
	resolved.Scaling = ability

	return resolved
end

----------------------------------------------------------------
-- DESCRIBE SCALING
--
-- Example:
-- { AD = 2.4 }
-- -> "240% AD"
--
-- { MP = 2.0 }
-- -> "200% Magic Power"
--
-- { AD = 1.0, MP = 1.5 }
-- -> "100% AD + 150% Magic Power"
----------------------------------------------------------------

function AbilityScaling.Describe(scaling)
	if type(scaling) == "number" then
		return tostring(scaling)
	end

	if type(scaling) ~= "table" then
		return ""
	end

	local parts = {}

	for _, stat in ipairs(AbilityScaling.STATS) do
		local ratio = scaling[stat]

		if ratio then
			local percent = ratio * 100

			local text

			if math.abs(
				percent - math.floor(percent + 0.5)
				) < 0.05 then
				text = string.format(
					"%d%%",
					math.floor(percent + 0.5)
				)
			else
				text = string.format(
					"%.1f%%",
					percent
				)
			end

			table.insert(
				parts,
				text .. " " .. AbilityScaling.SHORT[stat]
			)
		end
	end

	return table.concat(parts, " + ")
end

----------------------------------------------------------------
-- DESCRIBE SCALING WITH CURRENT VALUE
--
-- Example:
-- "240% AD  = 240"
----------------------------------------------------------------

function AbilityScaling.DescribeWithValue(scaling, stats)
	local text = AbilityScaling.Describe(scaling)

	if stats and type(scaling) == "table" then
		text ..= string.format(
			"  = %d",
			math.floor(
				AbilityScaling.Compute(scaling, stats) + 0.5
			)
		)
	end

	return text
end

----------------------------------------------------------------
-- OPTIONAL DEBUG FUNCTION
--
-- Useful for testing an ability's scaling in Studio.
----------------------------------------------------------------

function AbilityScaling.Debug(scaling, stats)
	local value = AbilityScaling.Compute(scaling, stats)

	print(
		"[AbilityScaling]",
		AbilityScaling.Describe(scaling),
		"=",
		value
	)

	return value
end

return AbilityScaling