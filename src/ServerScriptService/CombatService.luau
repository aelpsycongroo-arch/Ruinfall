-- CombatService: server-authoritative entity registry, damage, projectiles,
-- melee, buffs and status effects. Every damageable thing is an "entity":
--   Kind = "Hero" | "Monster" | "Flag" | "Ruin"
--   Team = team index (0 = neutral)

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local ShopDefinitions = require(Shared:WaitForChild("ShopDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local Net = require(script.Parent:WaitForChild("Net"))
-- PlayerService requires CombatService at load time, so we must require it lazily
-- to avoid a circular require error.
local _PlayerService
local function getPlayerService()
	if not _PlayerService then
		_PlayerService = require(script.Parent:WaitForChild("PlayerService"))
	end
	return _PlayerService
end

-- Constants
local TAGS = { Hero = "RF_Hero", Monster = "RF_Monster", Flag = "RF_Flag", Ruin = "RF_Ruin", Creep = "RF_Creep" }
-- Kinds that count as "attacking units" (can receive reflected damage)
local UNIT_KINDS = { Hero = true, Monster = true, Creep = true }
local BUFFS = CombatDefinitions.Buffs
local MELEE_LAG_COMPENSATION = 0.12 -- seconds of movement to lead a running melee swing
local MELEE_MAX_LEAD = 3 -- studs
local COMBAT = Constants.Combat
local MANA = CombatDefinitions.Mana or { Base = 300, RegenPerSecond = 6 }
local CRIT_MULTIPLIER = CombatDefinitions.CritMultiplier or 1.5
local MAX_CDR = CombatDefinitions.MaxCooldownReduction or 0.4

-- State
local CombatService = {}
CombatService.Tags = TAGS
CombatService.Entities = {}
CombatService.EntityDied = Util.Signal.new() -- (entity, killerEntity)
CombatService.EntityDamaged = Util.Signal.new() -- (entity, sourceEntity, amount)
CombatService.AssistGranted = Util.Signal.new() -- (contributorParticipant, deadHeroEntity)
-- Passive-item hooks, installed by PassiveService (all optional; nil = no passive effects):
--   DamageModifier(source, target, raw, info) -> ctx | nil   before mitigation (amp / pierce / reduction)
--   DamageDealt(ctx, total)                                   after the damage landed (on-hit effects)
--   BeforeBasicAttack(entity, now) -> mods | nil              a basic attack is starting (every Nth attack...)
--   BonusHook(participant, bonuses)                           extra stats from stacking passives
--   HealMultiplier(entity) -> number                          healing received (grievous wounds)
--   CCMultiplier(entity) -> number                            stun / slow / taunt duration (tenacity)
--   StunEnded(entity)                                         a stun from an enemy wore off
--   RevealedTo(entity, team) -> bool                          stealthed but revealed (True Sight)
CombatService.Active = false
CombatService.ArenaRadius = Constants.Map.RADIUS

local projectiles = {}
local nextEntityId = 0
local nextProjectileId = 0
local obstacleParams = RaycastParams.new()
obstacleParams.FilterType = Enum.RaycastFilterType.Include
obstacleParams.FilterDescendantsInstances = {}
local projectileConnection = nil
local tickRunId = 0
local wardNotices = setmetatable({}, { __mode = "k" }) -- [player] = last notice time

----------------------------------------------------------------------------
-- Entity registry
----------------------------------------------------------------------------
function CombatService.GetPosition(entity)
	if entity.Root and entity.Root.Parent then
		return entity.Root.Position
	end
	return entity.Position or Vector3.zero
end

function CombatService.AreEnemies(a, b)
	return a ~= nil and b ~= nil and a.Team ~= b.Team
end

function CombatService.GetObstacleParams()
	return obstacleParams
end

function CombatService.SyncHealth(entity)
	local model = entity.Model
	if model then
		model:SetAttribute("Health", math.max(0, math.ceil(entity.Health)))
		model:SetAttribute("MaxHealth", entity.MaxHealth)
		model:SetAttribute("Shield", math.max(0, math.floor(entity.Shield + 0.5)))
		if entity.Class then
			-- replicated for skill tooltips (skills scale with these; server recomputes on cast)
			model:SetAttribute("AttackDamage", entity.Class.AttackDamage + (entity.BonusAttackDamage or 0) + math.floor((entity.PassiveAttackDamage or 0) + 0.5))
			model:SetAttribute("Armor", entity.Armor)
			model:SetAttribute("MagicPower", (entity.Class.MagicPower or 0) + (entity.BonusMagicPower or 0))
		end
	end
	local humanoid = entity.Humanoid
	if humanoid and entity.Alive and humanoid.Parent then
		humanoid.MaxHealth = entity.MaxHealth
		humanoid.Health = math.max(1, entity.Health)
	end
end

-- Mana (heroes): replicated as whole numbers, only when they change
function CombatService.SyncMana(entity)
	local model = entity.Model
	if not model or entity.MaxMana == nil then
		return
	end
	local mana = math.floor(entity.Mana + 0.5)
	if model:GetAttribute("Mana") ~= mana then
		model:SetAttribute("Mana", mana)
	end
	if model:GetAttribute("MaxMana") ~= entity.MaxMana then
		model:SetAttribute("MaxMana", entity.MaxMana)
	end
end

function CombatService.SpendMana(entity, amount)
	if (entity.Mana or 0) < amount then
		return false
	end
	entity.Mana -= amount
	CombatService.SyncMana(entity)
	return true
end

function CombatService.RestoreMana(entity, amount)
	if not entity.Alive or entity.MaxMana == nil or amount <= 0 then
		return 0
	end
	local before = entity.Mana
	entity.Mana = math.min(entity.MaxMana, entity.Mana + amount)
	CombatService.SyncMana(entity)
	return entity.Mana - before
end

-- Skill cooldown after Cooldown Reduction (item stat, capped at MAX_CDR)
function CombatService.GetCooldown(entity, baseCooldown)
	return (baseCooldown or 0) * (1 - math.clamp(entity and entity.CooldownReduction or 0, 0, MAX_CDR))
end

-- Is this stealthed entity revealed to `team` (True Sight)?
function CombatService.IsRevealedTo(entity, team)
	return CombatService.RevealedTo ~= nil and CombatService.RevealedTo(entity, team) == true
end

function CombatService.Register(entity)
	nextEntityId += 1
	entity.Id = entity.Id or (entity.Kind .. "_" .. nextEntityId)
	entity.Alive = true
	entity.Shield = entity.Shield or 0
	entity.ShieldExpiresAt = entity.ShieldExpiresAt or 0
	entity.Armor = entity.Armor or 0
	entity.Radius = entity.Radius or 2
	entity.LastDamagedAt = 0
	entity.StunnedUntil = entity.StunnedUntil or 0
	entity.StealthUntil = entity.StealthUntil or 0
	entity.TauntedUntil = entity.TauntedUntil or 0
	CombatService.Entities[entity.Id] = entity

	local model = entity.Model
	if model then
		model:SetAttribute("EntityId", entity.Id)
		model:SetAttribute("Kind", entity.Kind)
		model:SetAttribute("Team", entity.Team)
		model:SetAttribute("Dead", false)
		if TAGS[entity.Kind] then
			CollectionService:AddTag(model, TAGS[entity.Kind])
		end
	end
	CombatService.SyncHealth(entity)
	return entity
end

function CombatService.Unregister(entity)
	if entity and CombatService.Entities[entity.Id] == entity then
		CombatService.Entities[entity.Id] = nil
	end
end

function CombatService.GetEntity(entityId)
	return CombatService.Entities[entityId]
end

function CombatService.ComputeShopBonuses(participant)
	local bonuses = {
		MaxHealth = 0, Armor = 0, MoveSpeed = 0, AttackDamage = 0, HealthRegen = 0, AttackSpeed = 0,
		MagicPower = 0, Mana = 0, CooldownReduction = 0, CritChance = 0, Lifesteal = 0, MagicDefense = 0, MoveSpeedPercent = 0,
	}
	if not participant or not participant.Purchases then
		return bonuses
	end
	for key, count in pairs(participant.Purchases) do
		local item = ShopDefinitions.Get(key)
		if item and item.Effect then
			for stat, value in pairs(item.Effect) do
				bonuses[stat] = (bonuses[stat] or 0) + value * count
			end
		end
	end
	-- Passive stats from equipped mythic items + the separate boot slot + passive items
	local equipped = {}
	for slot = 1, ItemDefinitions.MAX_MYTHIC_SLOTS do
		table.insert(equipped, participant.Mythics and participant.Mythics[slot])
	end
	table.insert(equipped, participant.Boots)
	for slot = 1, ItemDefinitions.MAX_PASSIVE_SLOTS or 0 do
		table.insert(equipped, participant.Passives and participant.Passives[slot])
	end
	for _, itemId in pairs(equipped) do
		local item = ItemDefinitions.GetItem(itemId)
		if item and item.Stats then
			for stat, value in pairs(item.Stats) do
				bonuses[stat] = (bonuses[stat] or 0) + value
			end
		end
	end
	if CombatService.BonusHook then
		CombatService.BonusHook(participant, bonuses) -- stacking passives (Soul Harvest, Overgrowth)
	end
	return bonuses
end

-- Item stats beyond health / armor / speed / damage (passive items) + the mana pool.
-- fresh = a newly spawned hero (starts with full mana).
local function applyExtraStats(entity, bonuses, fresh)
	entity.BonusMagicPower = bonuses.MagicPower or 0
	entity.BonusCritChance = bonuses.CritChance or 0
	entity.BonusLifesteal = bonuses.Lifesteal or 0
	entity.MagicDefense = bonuses.MagicDefense or 0
	entity.CooldownReduction = math.clamp(bonuses.CooldownReduction or 0, 0, MAX_CDR)
	entity.BonusMoveSpeedPercent = bonuses.MoveSpeedPercent or 0
	local oldMax = entity.MaxMana or 0
	entity.MaxMana = MANA.Base + (bonuses.Mana or 0)
	if fresh or entity.Mana == nil then
		entity.Mana = entity.MaxMana
	elseif entity.MaxMana > oldMax then
		entity.Mana += entity.MaxMana - oldMax
	end
	entity.Mana = math.min(entity.Mana, entity.MaxMana)
	CombatService.SyncMana(entity)
end

-- Equipped passive items of a hero / participant (their item.Passive holds the automatic
-- effect's parameters). Combat code reads this to apply passive effects.
function CombatService.GetEquippedPassives(entityOrParticipant)
	local participant = entityOrParticipant and (entityOrParticipant.Participant or entityOrParticipant)
	local list = {}
	for slot = 1, ItemDefinitions.MAX_PASSIVE_SLOTS or 0 do
		local item = ItemDefinitions.GetItem(participant and participant.Passives and participant.Passives[slot])
		if item then
			table.insert(list, item)
		end
	end
	return list
end

-- Re-apply shop + mythic bonuses to a living hero (after buying/selling/equipping).
function CombatService.RefreshParticipantBonuses(participant)
	local entity = participant and participant.Entity
	if not entity or not entity.Alive or not entity.Class then
		return
	end
	local bonuses = CombatService.ComputeShopBonuses(participant)
	local classDef = entity.Class
	local oldMax = entity.MaxHealth
	entity.MaxHealth = classDef.MaxHealth + bonuses.MaxHealth
	entity.Armor = classDef.Armor + bonuses.Armor
	entity.BaseSpeed = classDef.MoveSpeed + bonuses.MoveSpeed
	entity.BonusAttackDamage = bonuses.AttackDamage
	entity.BonusHealthRegen = bonuses.HealthRegen
	entity.BonusAttackSpeed = bonuses.AttackSpeed
	applyExtraStats(entity, bonuses, false)
	if entity.MaxHealth > oldMax then
		entity.Health += entity.MaxHealth - oldMax
	end
	entity.Health = math.min(entity.Health, entity.MaxHealth)
	CombatService.SyncHealth(entity)
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity) -- e.g. new attack speed -> client attack cooldown
end

function CombatService.CreateHero(participant, model, classKey)
	local classDef = ClassDefinitions.Get(classKey)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local shopBonuses = CombatService.ComputeShopBonuses(participant)
	if participant.Skill and participant.Skill ~= "" then
		classDef = ClassDefinitions.WithSkill(classKey, participant.Skill) -- Royale: looted Q skill
	end
	local entity = {
		Kind = "Hero",
		Team = participant.Team,
		Model = model,
		Root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart,
		Humanoid = humanoid,
		Participant = participant,
		Player = participant.Player,
		ClassKey = classKey,
		Class = classDef,
		MaxHealth = classDef.MaxHealth + shopBonuses.MaxHealth,
		Health = classDef.MaxHealth + shopBonuses.MaxHealth,
		Armor = classDef.Armor + shopBonuses.Armor,
		BaseSpeed = classDef.MoveSpeed + shopBonuses.MoveSpeed,
		BonusAttackDamage = shopBonuses.AttackDamage,
		BonusHealthRegen = shopBonuses.HealthRegen,
		BonusAttackSpeed = shopBonuses.AttackSpeed,
		Radius = 2.2,
		LastAttackAt = 0,
		AbilityReadyAt = 0,
		NextAttackMultiplier = 1,
		NextAttackExpires = 0,
		BloodRushUntil = 0,
		FrenzyUntil = 0,
		FrenzyAttackSpeed = 0,
		Buff = nil,
		CarryingFragment = false,
		MovementGraceUntil = Util.Now() + 1,
	}
	applyExtraStats(entity, shopBonuses, true)
	CombatService.Register(entity)
	-- LookClass: Royale Wanderers borrow the Fighter's gear / animations on the client
	model:SetAttribute("Class", ClassDefinitions.Get(classKey).LookClass or classKey)
	model:SetAttribute("ParticipantId", participant.Id)
	model:SetAttribute("DisplayName", participant.Name)
	model:SetAttribute("IsBot", participant.IsBot == true)
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity)
	return entity
end

----------------------------------------------------------------------------
-- Stats and status
----------------------------------------------------------------------------
function CombatService.GetAttackCooldown(entity)
	local cooldown = entity.Class.AttackCooldown
	-- Passive attack speed from mythic item stats
	local bonusAS = (entity.BonusAttackSpeed or 0) + (entity.PassiveAttackSpeed or 0) -- items + passive effects
	if bonusAS > 0 then
		cooldown = cooldown / (1 + bonusAS)
	end
	-- Temporary attack speed from ability buffs (Frenzy, IronFrenzy, BloodFury)
	if entity.FrenzyUntil and entity.FrenzyUntil > Util.Now() then
		cooldown = cooldown / (1 + (entity.FrenzyAttackSpeed or 0))
	end
	if entity.BloodRushUntil > Util.Now() then
		cooldown /= entity.Class.Ability and entity.Class.Ability.AttackSpeedMultiplier or 1
	end
	return cooldown
end

function CombatService.GetSpeedMultiplier(entity)
	local multiplier = 1 + (entity.BonusMoveSpeedPercent or 0) -- Movement Speed % (item stat)
	if entity.Buff and entity.Buff.Key == "SpeedCore" then
		multiplier *= BUFFS.SpeedCore.SpeedMultiplier
	end
	if entity.Class and (entity.BloodRushUntil or 0) > Util.Now() then
		multiplier *= entity.Class.Ability and entity.Class.Ability.MoveSpeedMultiplier or 1
	end
	-- timed haste / slow from boot skills (CombatService.Haste / CombatService.Slow)
	local now = Util.Now()
	if (entity.HasteUntil or 0) > now then
		multiplier *= 1 + (entity.HasteBonus or 0)
	end
	if (entity.SlowUntil or 0) > now then
		multiplier *= math.max(0.1, 1 - (entity.SlowAmount or 0))
	end
	return multiplier
end

function CombatService.RecomputeSpeed(entity)
	local humanoid = entity.Humanoid
	if not humanoid or not humanoid.Parent then
		return
	end
	if not entity.Alive or entity.StunnedUntil > Util.Now() then
		humanoid.WalkSpeed = 0
	else
		humanoid.WalkSpeed = (entity.BaseSpeed or 16) * CombatService.GetSpeedMultiplier(entity)
	end
end

function CombatService.GetLifesteal(entity)
	local total = entity.BonusLifesteal or 0 -- Lifesteal (item stat)
	if entity.Buff and entity.Buff.Key == "BloodCore" then
		total += BUFFS.BloodCore.Lifesteal
	end
	if entity.Class and (entity.BloodRushUntil or 0) > Util.Now() then
		total += entity.Class.Ability and entity.Class.Ability.Lifesteal or 0
	end
	return total
end

function CombatService.PushHeroAttributes(entity)
	local model = entity.Model
	if not model or not model.Parent then
		return
	end
	model:SetAttribute("AttackCooldown", CombatService.GetAttackCooldown(entity))
	-- Royale Wanderers have no Q until they loot a skill
	model:SetAttribute("AbilityCooldown", entity.Class.Ability and CombatService.GetCooldown(entity, entity.Class.Ability.Cooldown) or 0)
	model:SetAttribute("SkillKey", entity.Class.SkillKey or "")
	model:SetAttribute("CooldownReduction", entity.CooldownReduction or 0)
	model:SetAttribute("AbilityReadyAt", entity.AbilityReadyAt)
	model:SetAttribute("EmpoweredAttack", entity.NextAttackMultiplier > 1)
	model:SetAttribute("BloodRush", entity.BloodRushUntil > Util.Now())
	model:SetAttribute("BuffKey", entity.Buff and entity.Buff.Key or "")
	model:SetAttribute("BuffEndsAt", entity.Buff and entity.Buff.ExpiresAt or 0)
	model:SetAttribute("HasFragment", entity.CarryingFragment == true)
	model:SetAttribute("Stealthed", CombatService.IsStealthed(entity))
	model:SetAttribute("StunnedUntil", entity.StunnedUntil)
end

function CombatService.IsStealthed(entity)
	return (entity.StealthUntil or 0) > Util.Now()
end

-- Crowd-control duration after passive effects (Tenacity). Countdown / end-of-match freezes
-- (CombatService inactive) are never shortened.
local function ccDuration(entity, duration)
	if CombatService.Active and CombatService.CCMultiplier then
		return duration * CombatService.CCMultiplier(entity)
	end
	return duration
end

function CombatService.IsStunned(entity)
	return (entity.StunnedUntil or 0) > Util.Now()
end

-- source (optional): who applied the stun (counts toward assists)
function CombatService.Stun(entity, duration, source)
	if not entity.Alive then
		return
	end
	if (entity.UnstoppableUntil or 0) > Util.Now() then
		return -- Unstoppable March: immune to stuns
	end
	CombatService.MarkAssist(entity, source)
	duration = ccDuration(entity, duration)
	local untilTime = Util.Now() + duration
	if untilTime > entity.StunnedUntil then
		entity.StunnedUntil = untilTime
	end
	if CombatService.Active and source ~= entity then
		entity.StunnedInCombat = true -- lets "after being stunned" passives react when it ends
	end
	if entity.Model then
		entity.Model:SetAttribute("StunnedUntil", entity.StunnedUntil)
	end
	CombatService.RecomputeSpeed(entity)
	if entity.Humanoid and entity.Humanoid.Parent then
		entity.Humanoid:MoveTo(CombatService.GetPosition(entity))
	end
end

function CombatService.ClearStun(entity)
	local wasStunned = entity.StunnedInCombat == true and (entity.StunnedUntil or 0) > 0
	entity.StunnedInCombat = nil
	if wasStunned and entity.Alive and CombatService.Active and CombatService.StunEnded then
		task.defer(CombatService.StunEnded, entity)
	end
	entity.StunnedUntil = 0
	if entity.Model then
		entity.Model:SetAttribute("StunnedUntil", 0)
	end
	CombatService.RecomputeSpeed(entity)
end

-- Assist tracking: remember which players recently hit / crowd-controlled an enemy hero.
-- Summoned golems count for their owner.
function CombatService.MarkAssist(target, source)
	if not target or target.Kind ~= "Hero" or not source or source == target then
		return
	end
	local contributor = source.Participant or (source.IsGolem and source.Owner) or nil
	if not contributor or contributor == target.Participant or source.Team == target.Team then
		return
	end
	target.AssistLog = target.AssistLog or {}
	target.AssistLog[contributor] = Util.Now()
end

function CombatService.Taunt(entity, taunter, duration)
	if not entity.Alive then
		return
	end
	CombatService.MarkAssist(entity, taunter)
	entity.TauntedBy = taunter
	entity.TauntedUntil = Util.Now() + ccDuration(entity, duration)
end

-- Timed move-speed buff (boots). bonus 0.35 = +35%. A stronger / longer haste is kept.
function CombatService.Haste(entity, bonus, duration)
	if not entity.Alive then
		return
	end
	local now = Util.Now()
	if (entity.HasteUntil or 0) > now then
		entity.HasteBonus = math.max(entity.HasteBonus or 0, bonus)
		entity.HasteUntil = math.max(entity.HasteUntil, now + duration)
	else
		entity.HasteBonus = bonus
		entity.HasteUntil = now + duration
	end
	if entity.Model then
		entity.Model:SetAttribute("HasteUntil", entity.HasteUntil)
	end
	CombatService.RecomputeSpeed(entity)
end

-- Timed slow (boots). amount 0.5 = -50% move speed. A stronger / longer slow is kept.
function CombatService.Slow(entity, amount, duration, source)
	if not entity.Alive then
		return
	end
	CombatService.MarkAssist(entity, source)
	duration = ccDuration(entity, duration)
	local now = Util.Now()
	if (entity.SlowUntil or 0) > now then
		entity.SlowAmount = math.max(entity.SlowAmount or 0, amount)
		entity.SlowUntil = math.max(entity.SlowUntil, now + duration)
	else
		entity.SlowAmount = amount
		entity.SlowUntil = now + duration
	end
	if entity.Model then
		entity.Model:SetAttribute("SlowedUntil", entity.SlowUntil)
	end
	CombatService.RecomputeSpeed(entity)
end

-- Removes stuns and makes the entity immune to new ones for duration (Unstoppable March)
function CombatService.SetUnstoppable(entity, duration)
	entity.UnstoppableUntil = Util.Now() + duration
	if entity.Model then
		entity.Model:SetAttribute("UnstoppableUntil", entity.UnstoppableUntil)
	end
	if CombatService.IsStunned(entity) then
		CombatService.ClearStun(entity)
	end
end

function CombatService.SetStealth(entity, duration)
	entity.StealthUntil = Util.Now() + duration
	if entity.Model then
		entity.Model:SetAttribute("Stealthed", true)
	end
end

function CombatService.BreakStealth(entity)
	if (entity.StealthUntil or 0) > 0 then
		entity.StealthUntil = 0
		if entity.Model then
			entity.Model:SetAttribute("Stealthed", false)
		end
	end
end

function CombatService.AddShield(entity, amount, duration)
	entity.Shield = math.max(entity.Shield, amount)
	entity.ShieldExpiresAt = Util.Now() + duration
	CombatService.SyncHealth(entity)
	Net.Effect("Shield", { EntityId = entity.Id, Position = CombatService.GetPosition(entity) })
end

function CombatService.ApplyBuff(entity, buffKey)
	local definition = BUFFS[buffKey]
	if not definition or not entity.Alive then
		return
	end
	entity.Buff = { Key = buffKey, ExpiresAt = Util.Now() + definition.Duration }
	if buffKey == "ShieldCore" then
		CombatService.AddShield(entity, definition.ShieldAmount, definition.Duration)
	end
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity)
end

function CombatService.ClearBuff(entity)
	entity.Buff = nil
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity)
end

----------------------------------------------------------------------------
-- Health
----------------------------------------------------------------------------
function CombatService.Heal(entity, amount, showEffect)
	if not entity.Alive or amount <= 0 then
		return 0
	end
	if CombatService.HealMultiplier then
		amount *= CombatService.HealMultiplier(entity)
	end
	local before = entity.Health
	entity.Health = math.min(entity.MaxHealth, entity.Health + amount)
	local healed = entity.Health - before
	if healed > 0 then
		CombatService.SyncHealth(entity)
		if showEffect and healed >= 4 then
			Net.Effect("Heal", { Position = CombatService.GetPosition(entity), Amount = math.floor(healed + 0.5) })
		end
	end
	return healed
end

function CombatService.Revive(entity, healthFraction)
	entity.Alive = true
	entity.Health = entity.MaxHealth * healthFraction
	entity.LastDamagedAt = 0
	if entity.Model then
		entity.Model:SetAttribute("Dead", false)
	end
	CombatService.SyncHealth(entity)
end

function CombatService.Kill(target, killer)
	if not target.Alive then
		return
	end
	local position = CombatService.GetPosition(target)
	target.Alive = false
	target.Health = 0
	target.Shield = 0
	CombatService.SyncHealth(target)
	if target.Model then
		target.Model:SetAttribute("Dead", true)
	end
	if target.Humanoid and target.Humanoid.Parent then
		target.Humanoid.Health = 0
	end
	if killer and killer.Participant and target.Kind == "Hero" then
		killer.Participant.Stats.Kills += 1
	end
	if target.Participant then
		target.Participant.Stats.Deaths += 1
	end
	-- Gold rewards (only the player who lands the killing blow gets gold)
	if killer and killer.Participant and killer.Kind == "Hero" then
		local reward = 0
		if target.Kind == "Hero" then
			reward = ShopDefinitions.GoldRewards.HeroKill
		elseif target.Kind == "Monster" then
			-- Big monster (Brute) gives more gold than small monster (Minion)
			local monsterKey = target.Definition and target.Definition.Key
			if monsterKey == "Brute" then
				reward = ShopDefinitions.GoldRewards.BruteKill
			else
				reward = ShopDefinitions.GoldRewards.MinionKill
			end
		elseif target.Kind == "Ruin" then
			reward = ShopDefinitions.GoldRewards.RuinKill
		elseif target.Kind == "Flag" then
			reward = ShopDefinitions.GoldRewards.FlagKill
		elseif target.Kind == "Creep" then
			-- purchased war band creep: fixed reward, only to an enemy hero (Kill runs once per death)
			reward = target.KillReward or ItemDefinitions.CreepWave.KillReward
		end
		if reward > 0 then
			killer.Participant.Stats.Gold = (killer.Participant.Stats.Gold or 0) + reward
			getPlayerService().SetPlayerAttributes(killer.Participant)
		end
	end
	-- Assists: every other enemy player who hit / stunned / taunted this hero in the last
	-- AssistWindow seconds gets AssistShare (60%) of the hero kill gold
	if target.Kind == "Hero" and target.AssistLog then
		local rewards = ShopDefinitions.GoldRewards
		local window = rewards.AssistWindow or 5
		local assistGold = math.floor(rewards.HeroKill * (rewards.AssistShare or 0.6) + 0.5)
		local now = Util.Now()
		local killerParticipant = killer and (killer.Participant or (killer.IsGolem and killer.Owner)) or nil
		for contributor, lastAt in pairs(target.AssistLog) do
			if contributor ~= killerParticipant and now - lastAt <= window and contributor.Team ~= target.Team and contributor.Stats then
				contributor.Stats.Assists = (contributor.Stats.Assists or 0) + 1
				contributor.Stats.Gold = (contributor.Stats.Gold or 0) + assistGold
				getPlayerService().SetPlayerAttributes(contributor)
				if contributor.Player then
					Net.Notify(contributor.Player, string.format("+%d gold (assist)", assistGold), "Success")
				end
				CombatService.AssistGranted:Fire(contributor, target)
			end
		end
	end
	target.AssistLog = nil
	local color = target.Class and target.Class.Color or Constants.GetTeamColor(target.Team)
	Net.Effect("Death", { Position = position, Kind = target.Kind, Color = color })
	CombatService.EntityDied:Fire(target, killer)
end

-- The only way damage is dealt in Ruinfall. Clients never send damage values.
function CombatService.ApplyDamage(source, target, rawAmount, info)
	info = info or {}
	if not target or not target.Alive or target.Invulnerable then
		return 0
	end
	if source and not CombatService.AreEnemies(source, target) then
		return 0
	end
	-- Smoke Bomb: basic attacks made from inside an enemy smoke cloud miss completely
	if info.BasicAttack and source and CombatService.IsInEnemySmoke(source) then
		Net.Effect("Damage", { Position = CombatService.GetPosition(target), Amount = 0, Kind = "Miss", TargetId = target.Id, SourceId = source.Id })
		return 0
	end
	-- Flag ward: flags can only be damaged by heroes standing inside siege range
	if target.Kind == "Flag" and source and source.Kind == "Hero" then
		local siegeRange = Constants.Flag.SIEGE_RANGE + target.Radius
		if Util.FlatDistance(CombatService.GetPosition(source), CombatService.GetPosition(target)) > siegeRange then
			if source.Player and Util.Now() - (wardNotices[source.Player] or 0) > 3 then
				wardNotices[source.Player] = Util.Now()
				Net.Notify(source.Player, "Flag is warded - move closer to damage it", "Warning")
			end
			Net.Effect("Damage", { Position = CombatService.GetPosition(target), Amount = 0, Kind = "Shield" })
			return 0
		end
	end
	-- passive items (PassiveService): amplify / pierce / reduce before mitigation
	local ctx = CombatService.DamageModifier and CombatService.DamageModifier(source, target, rawAmount, info) or nil
	local armor = info.IgnoreArmor and 0 or target.Armor * (ctx and ctx.ArmorFactor or 1)
	local amount = math.max(0, rawAmount + (ctx and ctx.RawBonus or 0)) * (ctx and ctx.Multiplier or 1) * CombatDefinitions.ArmorMultiplier(armor)
	if ctx then
		if ctx.MagicDefense > 0 then
			amount *= CombatDefinitions.MagicDefenseMultiplier(ctx.MagicDefense)
		end
		amount = (amount + ctx.TrueBonus) * ctx.Reduction
	end
	local absorbed = 0
	if target.Shield > 0 then
		absorbed = math.min(target.Shield, amount)
		target.Shield -= absorbed
		amount -= absorbed
	end
	target.Health -= amount
	target.LastDamagedAt = Util.Now()
	if source then
		target.LastAttacker = source
		CombatService.MarkAssist(target, source)
		if source.Kind == "Hero" and not info.Reflected then
			source.LastTarget = target -- lets summoned golems join their owner's fight
		end
		source.LastDamagedAt = source.Kind == "Hero" and Util.Now() or source.LastDamagedAt
	end
	local total = amount + absorbed
	local targetPosition = CombatService.GetPosition(target)
	if source and source.Participant then
		source.Participant.Stats.Damage += total
	end
	CombatService.SyncHealth(target)

	local numberKind = info.Crit and "Crit" or (absorbed > 0 and amount <= 0 and "Shield" or "Damage")
	-- audio context (who hit whom, how hard) rides along with the damage number; clients use it
	-- to choose hit / crit / armor / stagger sounds and to drive combat music (AudioHooks.EffectAudio)
	Net.Effect("Damage", {
		Position = targetPosition,
		Amount = math.floor(total + 0.5),
		Kind = numberKind,
		TargetId = target.Id,
		TargetKind = target.Kind,
		TargetArmor = target.Armor,
		SourceId = source and source.Id or nil,
		SourceKind = source and source.Kind or nil,
		SourceClass = source and source.Model and source.Model:GetAttribute("Class") or nil,
		Basic = info.BasicAttack == true,
		Reflected = info.Reflected == true,
		Heavy = (target.MaxHealth or 0) > 0 and total >= target.MaxHealth * 0.15,
	})
	CombatService.EntityDamaged:Fire(target, source, total)

	-- Spiked Scale: reflect a share of the damage actually taken back to the attacking unit.
	-- Reflected damage is flagged so it can never reflect again (no infinite loops).
	-- Tank Boots also reflect passively (item.PassiveReflect) while equipped; the Spiked
	-- Scale active raises it to ReflectPercent for its duration (never stacked).
	local reflectPercent = 0
	if (target.ReflectUntil or 0) > Util.Now() then
		reflectPercent = target.ReflectPercent or 0
	elseif target.Participant and target.Participant.Boots then
		local boots = ItemDefinitions.GetItem(target.Participant.Boots)
		reflectPercent = boots and boots.PassiveReflect or 0
	end
	if not info.Reflected and source and source ~= target and UNIT_KINDS[source.Kind] and source.Alive
		and total > 0 and reflectPercent > 0 then
		local reflected = total * reflectPercent
		if reflected > 0 then
			Net.Effect("Lightning", { From = targetPosition, To = CombatService.GetPosition(source), Color = Color3.fromRGB(230, 90, 60) })
			CombatService.LastReflection = { From = target.Id, To = source.Id, Taken = total, Reflected = reflected }
			task.defer(CombatService.ApplyDamage, target, source, reflected, { Reflected = true, IgnoreArmor = true, NoChain = true })
		end
	end

	-- Warlord's Cleaver passive: basic attacks splash part of their damage around the target
	if info.BasicAttack and source and source.Participant and total > 0 then
		local splash = CombatService.GetPassiveSplash(source)
		if splash then
			local victims = CombatService.GetEntitiesInRadius(targetPosition, splash.Radius, function(candidate)
				return candidate ~= target and candidate.Alive and UNIT_KINDS[candidate.Kind] and CombatService.AreEnemies(source, candidate)
			end)
			Net.Effect("Shockwave", { Position = targetPosition, Radius = splash.Radius, Color = Color3.fromRGB(255, 120, 80) })
			for _, victim in ipairs(victims) do
				task.defer(CombatService.ApplyDamage, source, victim, rawAmount * splash.Percent, { Splash = true, NoChain = true })
			end
		end
	end

	if source and source.Kind == "Hero" and source.Alive and total > 0 and not info.Reflected then
		local lifesteal = CombatService.GetLifesteal(source) + (ctx and ctx.ExtraLifesteal or 0)
		if lifesteal > 0 then
			CombatService.Heal(source, total * lifesteal, true)
		end
		local canChain = not info.NoChain and (target.Kind == "Hero" or target.Kind == "Monster")
		if canChain and source.Buff and source.Buff.Key == "ArcCore" then
			local arc = BUFFS.ArcCore
			local chainTarget = CombatService.FindNearestEnemy(source, targetPosition, arc.ChainRange, function(candidate)
				return candidate ~= target and (candidate.Kind == "Hero" or candidate.Kind == "Monster")
					and not CombatService.IsStealthed(candidate)
			end)
			if chainTarget then
				Net.Effect("Lightning", { From = targetPosition, To = CombatService.GetPosition(chainTarget), Color = arc.Color })
				task.defer(CombatService.ApplyDamage, source, chainTarget, rawAmount * arc.ChainDamagePercent, { NoChain = true })
			end
		end
	end

	if ctx and CombatService.DamageDealt then
		CombatService.DamageDealt(ctx, total) -- on-hit passive effects (DoTs, marks, slows, stacks)
	end
	if target.Health <= 0 then
		CombatService.Kill(target, source)
	end
	return total
end

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------
function CombatService.FindNearestEnemy(source, position, range, filter)
	local best, bestDistance = nil, range
	for _, entity in pairs(CombatService.Entities) do
		if entity.Alive and entity ~= source and CombatService.AreEnemies(source, entity) and (not filter or filter(entity)) then
			local distance = Util.FlatDistance(position, CombatService.GetPosition(entity)) - entity.Radius
			if distance <= bestDistance then
				best, bestDistance = entity, distance
			end
		end
	end
	return best, bestDistance
end

function CombatService.GetEntitiesInRadius(position, radius, predicate)
	local results = {}
	for _, entity in pairs(CombatService.Entities) do
		if entity.Alive and (not predicate or predicate(entity)) then
			if Util.FlatDistance(position, CombatService.GetPosition(entity)) <= radius + entity.Radius then
				table.insert(results, entity)
			end
		end
	end
	return results
end

function CombatService.HasLineOfSight(fromPosition, toPosition)
	local origin = Vector3.new(fromPosition.X, 3, fromPosition.Z)
	local target = Vector3.new(toPosition.X, 3, toPosition.Z)
	return workspace:Raycast(origin, target - origin, obstacleParams) == nil
end

function CombatService.ClampToArena(position)
	local flat = Vector3.new(position.X, 0, position.Z)
	local limit = CombatService.ArenaRadius - 6
	if flat.Magnitude > limit then
		flat = flat.Unit * limit
	end
	return Vector3.new(flat.X, position.Y, flat.Z)
end

----------------------------------------------------------------------------
-- Movement abilities
----------------------------------------------------------------------------
-- Server-driven dash with wall collision. Returns the final position.
function CombatService.Dash(entity, direction, distance, duration)
	local root = entity.Root
	if not root or not root.Parent then
		return nil
	end
	direction = Util.Flat(direction)
	if direction.Magnitude < 1e-3 then
		return root.Position
	end
	direction = direction.Unit
	local start = root.Position
	local travel = distance
	local hit = workspace:Raycast(start, direction * (distance + 2.5), obstacleParams)
	if hit then
		travel = math.max(0, (hit.Position - start).Magnitude - 2.5)
	end
	local finish = CombatService.ClampToArena(start + direction * travel)
	entity.MovementGraceUntil = Util.Now() + duration + 0.8

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if not entity.Alive or not root.Parent then
			connection:Disconnect()
			return
		end
		local alpha = math.min(1, elapsed / duration)
		local position = start:Lerp(finish, alpha)
		root.CFrame = CFrame.new(position) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
	local color = entity.Class and entity.Class.Color or Color3.new(1, 1, 1)
	Net.Effect("Dash", { From = start, To = finish, Color = color })
	return finish
end

----------------------------------------------------------------------------
-- Projectiles (simulated on the server, drawn by clients)
----------------------------------------------------------------------------
function CombatService.FireProjectile(spec)
	nextProjectileId += 1
	local projectile = {
		Id = nextProjectileId,
		Owner = spec.Owner,
		Team = spec.Owner.Team,
		Position = spec.Origin,
		Direction = Util.Flat(spec.Direction).Unit,
		Speed = spec.Speed,
		Damage = spec.Damage,
		Radius = spec.Radius or 1,
		Remaining = spec.Range or 60,
		Pierce = spec.Pierce == true,
		Style = spec.Style or "Default",
		Crit = spec.Crit == true,
		CritHit = spec.CritHit == true, -- a rolled critical hit (Critical Chance)
		AttackMods = spec.AttackMods, -- passive-item modifiers of this basic attack
		IgnoreArmor = spec.IgnoreArmor == true,
		BasicAttack = spec.BasicAttack == true,
		OnEnd = spec.OnEnd, -- optional (endPosition, hitEntity|nil): e.g. an explosion where it lands
		HitIds = {},
	}
	projectiles[projectile.Id] = projectile
	Net.Effect("Projectile", {
		Id = projectile.Id,
		Origin = projectile.Position,
		Direction = projectile.Direction,
		Speed = projectile.Speed,
		Range = projectile.Remaining,
		Style = projectile.Style,
	})
	return projectile
end

local function stepProjectiles(dt)
	for id, projectile in pairs(projectiles) do
		local stepLength = math.min(projectile.Speed * dt, projectile.Remaining)
		local from = projectile.Position
		local to = from + projectile.Direction * stepLength
		local ended = false
		local endPosition = to
		local hitEntity = nil

		local wallHit = workspace:Raycast(from, projectile.Direction * stepLength, obstacleParams)
		local wallDistance = wallHit and (wallHit.Position - from).Magnitude or math.huge

		local candidates = {}
		for _, entity in pairs(CombatService.Entities) do
			if entity.Alive and entity.Team ~= projectile.Team and not projectile.HitIds[entity.Id] then
				local entityPosition = CombatService.GetPosition(entity)
				if Util.PointSegmentDistance2D(entityPosition, from, to) <= entity.Radius + projectile.Radius then
					local along = Util.Flat(entityPosition - from):Dot(projectile.Direction)
					if along <= wallDistance then
						table.insert(candidates, { Entity = entity, Along = along })
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.Along < b.Along
		end)
		for _, candidate in ipairs(candidates) do
			projectile.HitIds[candidate.Entity.Id] = true
			CombatService.ApplyDamage(projectile.Owner, candidate.Entity, projectile.Damage, { Crit = projectile.Crit, CritHit = projectile.CritHit, AttackMods = projectile.AttackMods, IgnoreArmor = projectile.IgnoreArmor, BasicAttack = projectile.BasicAttack })
			if not projectile.Pierce then
				ended = true
				hitEntity = candidate.Entity
				endPosition = from + projectile.Direction * math.max(0, candidate.Along)
				break
			end
		end

		if not ended and wallHit then
			ended = true
			endPosition = wallHit.Position
		end
		projectile.Remaining -= stepLength
		projectile.Position = to
		if not ended and projectile.Remaining <= 0 then
			ended = true
		end
		if ended then
			projectiles[id] = nil
			Net.Effect("ProjectileEnd", { Id = id, Position = endPosition, Style = projectile.Style })
			if projectile.OnEnd then
				task.spawn(projectile.OnEnd, endPosition, hitEntity)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Basic attacks
----------------------------------------------------------------------------
-- basicAttack: true for auto-attacks (these can miss inside enemy smoke)
-- critHit / mods (optional): rolled critical hit and passive-item modifiers of a basic attack
function CombatService.MeleeStrike(attacker, origin, direction, range, arcDegrees, damage, cleave, empowered, basicAttack, critHit, mods)
	local cosHalfArc = math.cos(math.rad(arcDegrees / 2))
	local hits = {}
	for _, target in pairs(CombatService.Entities) do
		if target.Alive and target ~= attacker and CombatService.AreEnemies(attacker, target) then
			local offset = Util.Flat(CombatService.GetPosition(target) - origin)
			local distance = offset.Magnitude
			if distance <= range + target.Radius then
				local inArc = distance <= target.Radius + 1 or offset.Unit:Dot(direction) >= cosHalfArc
				if inArc and CombatService.HasLineOfSight(origin, CombatService.GetPosition(target)) then
					table.insert(hits, { Target = target, Distance = distance })
				end
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.Distance < b.Distance
	end)
	local color = attacker.Class and attacker.Class.Color or Color3.new(1, 1, 1)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = range, Arc = arcDegrees, Color = color, Empowered = empowered, EntityId = attacker.Id })
	local count = cleave and #hits or math.min(1, #hits)
	for index = 1, count do
		CombatService.ApplyDamage(attacker, hits[index].Target, damage, { Crit = empowered or critHit == true, CritHit = critHit == true, AttackMods = mods, BasicAttack = basicAttack == true })
	end
	return count
end

-- Validates and performs a hero basic attack toward aimPosition.
function CombatService.PerformBasicAttack(entity, aimPosition)
	if not CombatService.Active or not entity or not entity.Alive or entity.Kind ~= "Hero" then
		return false
	end
	local now = Util.Now()
	if entity.StunnedUntil > now then
		return false
	end
	local cooldown = CombatService.GetAttackCooldown(entity)
	if now - entity.LastAttackAt < cooldown * COMBAT.COOLDOWN_TOLERANCE then
		return false
	end
	-- passive items look at the time since the previous attack, so ask before updating it
	local mods = CombatService.BeforeBasicAttack and CombatService.BeforeBasicAttack(entity, now) or nil
	entity.LastAttackAt = now

	local origin = CombatService.GetPosition(entity)
	-- Players move their own character, so the server sees them slightly in the past.
	-- While running (e.g. chasing), shift the swing origin forward by a short latency
	-- window so melee hits line up with where the avatar actually is (capped).
	if entity.Player and entity.Root and entity.Class and entity.Class.AttackType == "Melee" then
		local velocity = Util.Flat(entity.Root.AssemblyLinearVelocity)
		local lead = velocity * MELEE_LAG_COMPENSATION
		if lead.Magnitude > MELEE_MAX_LEAD then
			lead = lead.Unit * MELEE_MAX_LEAD
		end
		origin += lead
	end
	if entity.TauntedUntil > now and entity.TauntedBy and entity.TauntedBy.Alive then
		aimPosition = CombatService.GetPosition(entity.TauntedBy)
	end
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)

	local classDef = entity.Class
	local empowered = entity.NextAttackMultiplier > 1 and entity.NextAttackExpires > now
	local damage = (classDef.AttackDamage + (entity.BonusAttackDamage or 0) + (entity.PassiveAttackDamage or 0)) * (empowered and entity.NextAttackMultiplier or 1)
	-- Critical Chance (item stat): empowered strikes are already crits
	local critHit = not empowered and (entity.BonusCritChance or 0) > 0 and math.random() < entity.BonusCritChance
	if critHit then
		damage *= CRIT_MULTIPLIER
	end
	entity.NextAttackMultiplier = 1
	entity.Model:SetAttribute("LastAttackAt", now)
	entity.Model:SetAttribute("EmpoweredAttack", false)
	entity.Model:SetAttribute("AttackCooldown", cooldown)

	if classDef.AttackType == "Melee" then
		CombatService.MeleeStrike(entity, origin, direction, classDef.AttackRange, classDef.MeleeArc, damage, classDef.Cleave, empowered, true, critHit, mods)
	else
		CombatService.FireProjectile({
			Owner = entity,
			Origin = origin + direction * 1.5,
			Direction = direction,
			Speed = classDef.Projectile.Speed,
			Range = classDef.AttackRange,
			Radius = classDef.Projectile.Radius,
			Damage = damage,
			Style = classDef.Projectile.Style,
			Crit = empowered or critHit,
			CritHit = critHit,
			AttackMods = mods,
			Pierce = mods ~= nil and mods.Pierce == true, -- Piercing Shot
			BasicAttack = true,
		})
	end
	return true
end

----------------------------------------------------------------------------
-- Periodic status update + movement sanity checks
----------------------------------------------------------------------------
local function tickStatus(dt)
	local now = Util.Now()
	for _, entity in pairs(CombatService.Entities) do
		if entity.Alive then
			if entity.StunnedUntil > 0 and now >= entity.StunnedUntil then
				CombatService.ClearStun(entity)
			end
			if entity.StealthUntil > 0 and now >= entity.StealthUntil then
				CombatService.BreakStealth(entity)
			end
			if entity.Shield > 0 and entity.ShieldExpiresAt > 0 and now >= entity.ShieldExpiresAt then
				entity.Shield = 0
				entity.ShieldExpiresAt = 0
				CombatService.SyncHealth(entity)
			end
			if entity.TauntedUntil > 0 and now >= entity.TauntedUntil then
				entity.TauntedUntil = 0
				entity.TauntedBy = nil
			end
			if (entity.HasteUntil or 0) > 0 and now >= entity.HasteUntil then
				entity.HasteUntil = 0
				CombatService.RecomputeSpeed(entity)
			end
			if (entity.SlowUntil or 0) > 0 and now >= entity.SlowUntil then
				entity.SlowUntil = 0
				CombatService.RecomputeSpeed(entity)
			end
			if entity.Kind == "Hero" then
				if entity.Buff and now >= entity.Buff.ExpiresAt then
					CombatService.ClearBuff(entity)
				end
				if entity.BloodRushUntil > 0 and now >= entity.BloodRushUntil then
					entity.BloodRushUntil = 0
					CombatService.RecomputeSpeed(entity)
					CombatService.PushHeroAttributes(entity)
				end
				if entity.NextAttackMultiplier > 1 and now >= entity.NextAttackExpires then
					entity.NextAttackMultiplier = 1
					entity.Model:SetAttribute("EmpoweredAttack", false)
				end
				if entity.MaxMana and entity.Mana < entity.MaxMana then
					entity.Mana = math.min(entity.MaxMana, entity.Mana + MANA.RegenPerSecond * dt)
					CombatService.SyncMana(entity)
				end
				if now - entity.LastDamagedAt >= COMBAT.OUT_OF_COMBAT_TIME and entity.Health < entity.MaxHealth then
					CombatService.Heal(entity, entity.MaxHealth * (entity.Class.HealthRegen + (entity.BonusHealthRegen or 0)) * dt)
				end
				-- Passive gold income
				if entity.Participant then
					entity.Participant.Stats.Gold = (entity.Participant.Stats.Gold or 0) + ShopDefinitions.GoldRewards.PassivePerSecond * dt
					getPlayerService().SetPlayerAttributes(entity.Participant)
				end
			end
		end
	end
end

-- Players own their character physics, so the server sanity-checks travel speed
-- and snaps back impossible movement (teleports / speed hacks).
local function checkMovement()
	local now = Util.Now()
	for _, entity in pairs(CombatService.Entities) do
		if entity.Kind == "Hero" and entity.Alive and entity.Player and entity.Root and entity.Root.Parent then
			local position = entity.Root.Position
			local valid = true
			if entity.LastValidPosition and now > (entity.MovementGraceUntil or 0) then
				local elapsed = math.max(0.05, now - entity.LastValidTime)
				local maxSpeed = math.max(entity.Humanoid and entity.Humanoid.WalkSpeed or 0, entity.BaseSpeed * 1.6)
				local allowed = maxSpeed * elapsed * COMBAT.MOVEMENT_TOLERANCE + 4
				if Util.FlatDistance(position, entity.LastValidPosition) > allowed then
					valid = false
				end
			end
			if Util.Flat(position).Magnitude > CombatService.ArenaRadius + 4 then
				valid = false
			end
			if position.Y < -25 then
				CombatService.Kill(entity, nil)
			elseif valid then
				entity.LastValidPosition = position
				entity.LastValidTime = now
			elseif entity.LastValidPosition then
				entity.Root.CFrame = CFrame.new(entity.LastValidPosition) * entity.Root.CFrame.Rotation
				entity.Root.AssemblyLinearVelocity = Vector3.zero
				entity.LastValidTime = now
			end
		end
	end
end

----------------------------------------------------------------------------
-- Match lifecycle
----------------------------------------------------------------------------
function CombatService.Init() end

-- Strongest basic-attack splash granted by the hero's equipped mythics (item.PassiveSplash)
function CombatService.GetPassiveSplash(entity)
	local participant = entity and entity.Participant
	local mythics = participant and participant.Mythics
	if not mythics then
		return nil
	end
	local best = nil
	for slot = 1, ItemDefinitions.MAX_MYTHIC_SLOTS do
		local item = ItemDefinitions.GetItem(mythics[slot])
		if item and item.PassiveSplash and (not best or item.PassiveSplash.Percent > best.Percent) then
			best = item.PassiveSplash
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Smoke clouds (Smoke Bomb). Enemy units standing inside miss basic attacks.
----------------------------------------------------------------------------
CombatService.SmokeZones = {}

function CombatService.AddSmokeZone(team, position, radius, duration)
	local zone = { Team = team, Position = Vector3.new(position.X, 0, position.Z), Radius = radius, ExpiresAt = Util.Now() + duration }
	table.insert(CombatService.SmokeZones, zone)
	return zone
end

function CombatService.IsInEnemySmoke(entity)
	local zones = CombatService.SmokeZones
	if #zones == 0 or not entity then
		return false
	end
	local now = Util.Now()
	local position = CombatService.GetPosition(entity)
	for index = #zones, 1, -1 do
		local zone = zones[index]
		if now >= zone.ExpiresAt then
			table.remove(zones, index)
		elseif zone.Team ~= entity.Team and Util.FlatDistance(position, zone.Position) <= zone.Radius then
			return true
		end
	end
	return false
end

-- Royale: give a hero the Q skill of another class (looted from a ruin). skillKey = class key.
function CombatService.SetSkill(entity, skillKey)
	if not entity or entity.Kind ~= "Hero" then
		return false
	end
	local participant = entity.Participant
	if participant then
		participant.Skill = skillKey
	end
	entity.Class = ClassDefinitions.WithSkill(entity.ClassKey, skillKey)
	entity.AbilityReadyAt = Util.Now() + 1
	entity.BloodRushUntil = 0
	CombatService.RecomputeSpeed(entity)
	CombatService.PushHeroAttributes(entity)
	return true
end

function CombatService.BeginMatch(mapData)
	obstacleParams.FilterDescendantsInstances = { mapData.Blockers }
	CombatService.ArenaRadius = mapData.Radius
	CombatService.Active = false
end

function CombatService.Start()
	CombatService.Active = true
	tickRunId += 1
	local myRun = tickRunId
	if projectileConnection then
		projectileConnection:Disconnect()
	end
	projectileConnection = RunService.Heartbeat:Connect(stepProjectiles)
	task.spawn(function()
		local movementTimer = 0
		while tickRunId == myRun do
			local dt = task.wait(COMBAT.TICK_INTERVAL)
			if tickRunId ~= myRun then
				break
			end
			tickStatus(dt)
			movementTimer += dt
			if movementTimer >= COMBAT.MOVEMENT_CHECK_INTERVAL then
				movementTimer = 0
				checkMovement()
			end
		end
	end)
end

function CombatService.Stop()
	CombatService.Active = false
	table.clear(CombatService.SmokeZones)
	tickRunId += 1
	if projectileConnection then
		projectileConnection:Disconnect()
		projectileConnection = nil
	end
	table.clear(projectiles)
end

function CombatService.EndMatch()
	CombatService.Stop()
	table.clear(CombatService.Entities)
	obstacleParams.FilterDescendantsInstances = {}
end

return CombatService
