-- AbilityService: server-validated signature abilities (Q) for the five classes.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local AbilityScaling = require(Shared:WaitForChild("AbilityScaling"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local COOLDOWN_GRACE = 0.15 -- seconds of latency forgiveness

-- State
local AbilityService = {}
local handlers = {}

-- Ability handlers: (entity, ability, origin, aimPosition, now) -> false to cancel
handlers.ShadowStep = function(entity, ability, origin, aimPosition, now)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local distance = math.clamp(Util.FlatDistance(origin, aimPosition), 8, ability.DashDistance)
	Net.Effect("Stealth", { Position = origin, Color = entity.Class.Color })
	CombatService.Dash(entity, direction, distance, 0.16)
	CombatService.SetStealth(entity, ability.StealthDuration)
	entity.NextAttackMultiplier = ability.NextAttackMultiplier
	entity.NextAttackExpires = now + ability.EmpowerWindow
	entity.Model:SetAttribute("EmpoweredAttack", true)
end

handlers.ArcaneBurst = function(entity, ability, origin, aimPosition)
	local color = entity.Class.Color
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > ability.CastRange then
		offset = offset.Unit * ability.CastRange
	end
	local target = Vector3.new(origin.X + offset.X, 0.2, origin.Z + offset.Z)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = target, Radius = ability.Radius, Duration = ability.Delay, Color = color })
	Net.Effect("Cast", { Position = origin, Color = color })
	task.delay(ability.Delay, function()
		if not CombatService.Active or not entity.Alive then
			return
		end
		Net.Effect("Explosion", { Position = target, Radius = ability.Radius, Color = color })
		local victims = CombatService.GetEntitiesInRadius(target, ability.Radius, function(candidate)
			return CombatService.AreEnemies(entity, candidate)
		end)
		for _, victim in ipairs(victims) do
			CombatService.ApplyDamage(entity, victim, ability.Damage)
		end
	end)
end

handlers.DashShot = function(entity, ability, origin, aimPosition)
	local aimDirection = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.Dash(entity, -aimDirection, ability.DashDistance, 0.18)
	task.delay(0.2, function()
		if not CombatService.Active or not entity.Alive then
			return
		end
		local from = CombatService.GetPosition(entity)
		local direction = Util.FlatDirection(from, aimPosition, aimDirection)
		CombatService.FireProjectile({
			Owner = entity,
			Origin = from + direction * 1.5,
			Direction = direction,
			Speed = ability.ProjectileSpeed,
			Range = ability.Range,
			Radius = ability.ProjectileRadius,
			Damage = ability.Damage, -- 220% of current attack damage (resolved at cast)
			Style = "PowerShot",
			Pierce = true,
			Crit = true,
		})
	end)
end

handlers.TauntingShockwave = function(entity, ability, origin)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = entity.Class.Color })
	local victims = CombatService.GetEntitiesInRadius(origin, ability.Radius, function(candidate)
		return CombatService.AreEnemies(entity, candidate)
	end)
	for _, victim in ipairs(victims) do
		CombatService.ApplyDamage(entity, victim, ability.Damage)
		if victim.Alive and (victim.Kind == "Hero" or victim.Kind == "Monster") then
			CombatService.Stun(victim, ability.StunDuration)
			CombatService.Taunt(victim, entity, ability.TauntDuration)
			Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.StunDuration })
		end
	end
end

handlers.BloodRush = function(entity, ability, origin, _, now)
	entity.BloodRushUntil = now + ability.Duration
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity)
	Net.Effect("BloodRush", { Position = origin, Color = entity.Class.Color })
end

-- Public API ---------------------------------------------------------------------------
function AbilityService.Init() end

function AbilityService.IsReady(entity)
	return Util.Now() >= entity.AbilityReadyAt
end

-- Validates cooldown/state and performs the class signature ability.
function AbilityService.Use(entity, aimPosition)
	if not CombatService.Active or not entity or not entity.Alive or entity.Kind ~= "Hero" then
		return false
	end
	local now = Util.Now()
	if CombatService.IsStunned(entity) or now < entity.AbilityReadyAt - COOLDOWN_GRACE then
		return false
	end
	if not entity.Class.Ability then
		return false, "No ability"
	end
	-- Q costs mana when the class ability sets ManaCost (Mage Arcane Burst: 80); spent only if the cast succeeds
	local manaCost = entity.Class.Ability.ManaCost or 0
	if manaCost > 0 and (entity.Mana or 0) < manaCost then
		return false, "Not enough mana"
	end
	-- scaled values (Damage, Shield) are computed from the caster's current stats
	local ability = AbilityScaling.Resolve(entity.Class.Ability, AbilityScaling.StatsFromEntity(entity))
	local handler = handlers[ability.Key]
	if not handler then
		return false
	end
	local origin = CombatService.GetCastOrigin(entity) -- lag lead while running
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > Constants.Combat.MAX_AIM_DISTANCE then
		aimPosition = origin + offset.Unit * Constants.Combat.MAX_AIM_DISTANCE
	end
	-- Cooldown starts before the handler runs so re-entrant requests are rejected
	entity.AbilityReadyAt = now + CombatService.GetCooldown(entity, ability.Cooldown) -- Cooldown Reduction
	local result = handler(entity, ability, origin, aimPosition, now)
	if result == false then
		entity.AbilityReadyAt = now
		return false
	end
	if manaCost > 0 then
		CombatService.SpendMana(entity, manaCost)
	end
	if entity.Model then
		entity.Model:SetAttribute("AbilityReadyAt", entity.AbilityReadyAt)
		entity.Model:SetAttribute("LastAbilityAt", now)
	end
	return true
end

return AbilityService
