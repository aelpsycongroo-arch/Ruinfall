-- PassiveService: the automatic effects of passive items (ItemDefinitions.AddPassive - up to 3
-- per hero, no hotkey). Every item's Passive.Effect names a handler below and its numbers come
-- from the item definition. The effects run through hooks in CombatService (damage, healing,
-- crowd control, basic attacks, stat bonuses, stealth reveal) plus a small tick (damage over
-- time, auras, mana, HP thresholds). Server-authoritative: clients never send any of this.
--
-- Damage words used here:
--   basic   = a hero's basic attack (LM)
--   ability = a hero skill (Q / E / R / RMB): not basic, not reflected, not splash / chain, not a proc
--   proc    = damage made by a passive (burn, poison, bleed, explosion, meteor, lightning, aura);
--             procs never trigger on-hit passives again (no loops)
--   magic   = ability or magic proc: reduced by Magic Defense on top of armor

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local TICK = 0.25
local UNIT_KINDS = { Hero = true, Monster = true, Creep = true }
local EMPTY = table.freeze({})
local STATIC_MAX = 100
local CARNAGE_STACK_GAP = 0.4 -- a multi-hit skill adds one Carnage stack, not five

-- State
local PassiveService = {}
local dotTargets = setmetatable({}, { __mode = "k" }) -- [entity] = true while it has DoTs
local revealed = {} -- [team] = { [entity] = true } stealthed enemies seen through True Sight
local started = false
local _PlayerService

local function getPlayerService()
	_PlayerService = _PlayerService or require(script.Parent:WaitForChild("PlayerService"))
	return _PlayerService
end

-- push the participant snapshot (cooldowns, stacks) to clients now (MatchManager loads lazily)
local function broadcast()
	local ok, MatchManager = pcall(require, script.Parent:WaitForChild("MatchManager"))
	if ok and MatchManager and MatchManager.Broadcast then
		MatchManager.Broadcast()
	end
end

-- Lookups ---------------------------------------------------------------------------------
-- { [EffectName] = Passive definition } of a participant's equipped passive items (cached)
local function effectsOfParticipant(participant)
	local slots = participant and participant.Passives
	if not slots then
		return EMPTY
	end
	local key = (slots[1] or "") .. "|" .. (slots[2] or "") .. "|" .. (slots[3] or "")
	local cache = participant.PassiveEffectCache
	if cache and cache.Key == key then
		return cache.Effects
	end
	local effects = {}
	for slot = 1, ItemDefinitions.MAX_PASSIVE_SLOTS or 3 do
		local item = ItemDefinitions.GetItem(slots[slot])
		local passive = item and item.Passive
		if passive and passive.Effect then
			effects[passive.Effect] = passive
		end
	end
	participant.PassiveEffectCache = { Key = key, Effects = effects }
	return effects
end

local function effectsOf(entity)
	if not entity or entity.Kind ~= "Hero" then
		return EMPTY
	end
	return effectsOfParticipant(entity.Participant)
end

local function stateOf(entity)
	local state = entity.PassiveState
	if not state then
		state = { PerTarget = setmetatable({}, { __mode = "k" }) }
		entity.PassiveState = state
	end
	return state
end

-- this hero's record about one target (hit counters, marks, curses...)
local function recordOf(entity, target)
	local perTarget = stateOf(entity).PerTarget
	local record = perTarget[target]
	if not record then
		record = {}
		perTarget[target] = record
	end
	return record
end

local function healthFraction(entity)
	return (entity.MaxHealth or 0) > 0 and entity.Health / entity.MaxHealth or 1
end

-- Timed debuffs on an entity: entity.PassiveDebuffs[key] = { Amount, Until }
local function applyDebuff(target, key, amount, duration)
	target.PassiveDebuffs = target.PassiveDebuffs or {}
	local now = Util.Now()
	local debuff = target.PassiveDebuffs[key]
	if debuff and debuff.Until > now then
		debuff.Amount = math.max(debuff.Amount, amount)
		debuff.Until = math.max(debuff.Until, now + duration)
	else
		target.PassiveDebuffs[key] = { Amount = amount, Until = now + duration }
	end
end

local function debuffAmount(target, ...)
	local debuffs = target.PassiveDebuffs
	if not debuffs then
		return 0
	end
	local now, best = Util.Now(), 0
	for _, key in ipairs({ ... }) do
		local debuff = debuffs[key]
		if debuff and debuff.Until > now and debuff.Amount > best then
			best = debuff.Amount
		end
	end
	return best
end

local function enemyUnitsNear(source, position, radius, except)
	return CombatService.GetEntitiesInRadius(position, radius, function(candidate)
		return candidate ~= except and candidate.Alive and UNIT_KINDS[candidate.Kind] and CombatService.AreEnemies(source, candidate)
	end)
end

-- Damage made by a passive (never re-triggers on-hit passives). Deferred: callers are
-- usually inside CombatService.ApplyDamage.
local function procDamage(source, target, amount, magic)
	if amount <= 0 or not target.Alive then
		return
	end
	task.defer(CombatService.ApplyDamage, source, target, amount, { Proc = true, Magic = magic ~= false, NoChain = true })
end

-- Damage over time: target.Dots[kind:sourceId] = { Source, DPS, Until, Magic, Stacks }
local function addDot(source, target, kind, dps, duration, magic, maxStacks)
	if not target.Alive then
		return
	end
	target.Dots = target.Dots or {}
	local key = kind .. ":" .. tostring(source.Id)
	local dot = target.Dots[key]
	local now = Util.Now()
	if dot and dot.Until > now then
		dot.Until = now + duration
		dot.DPS = dps
		if maxStacks then
			dot.Stacks = math.min(maxStacks, dot.Stacks + 1)
		end
	else
		target.Dots[key] = { Source = source, DPS = dps, Until = now + duration, Magic = magic, Stacks = 1, Kind = kind }
	end
	dotTargets[target] = true
end

-- Temporary attack damage / attack speed from Carnage, Retaliation and Dragon's Fury
local function refreshDynamic(entity)
	if entity.Kind ~= "Hero" or not entity.Class then
		return
	end
	local effects = effectsOf(entity)
	local state = stateOf(entity)
	local now = Util.Now()
	local flat, percent, attackSpeed = 0, 0, 0
	if entity.Alive then
		if effects.Carnage and (state.CarnageUntil or 0) > now then
			flat += (state.CarnageStacks or 0) * effects.Carnage.PerStack
		end
		if effects.Retaliation and (state.RetaliationUntil or 0) > now then
			percent += effects.Retaliation.Bonus
		end
		if effects.DragonsFury and healthFraction(entity) < effects.DragonsFury.Threshold then
			percent += effects.DragonsFury.ADPercent
			attackSpeed += effects.DragonsFury.AttackSpeed
		end
	end
	local baseAD = entity.Class.AttackDamage + (entity.BonusAttackDamage or 0)
	local attackDamage = flat + baseAD * percent
	if math.abs(attackDamage - (entity.PassiveAttackDamage or 0)) > 0.01 or math.abs(attackSpeed - (entity.PassiveAttackSpeed or 0)) > 0.001 then
		entity.PassiveAttackDamage = attackDamage
		entity.PassiveAttackSpeed = attackSpeed
		if entity.Alive then
			CombatService.SyncHealth(entity)
			CombatService.PushHeroAttributes(entity)
		end
	end
end

local function notify(entity, text)
	if entity and entity.Player then
		Net.Notify(entity.Player, text, "Success")
	end
end

-- Hooks -------------------------------------------------------------------------------------
local function classify(source, info)
	local basic = info.BasicAttack == true
	local ability = source ~= nil and source.Kind == "Hero" and not basic and not info.Reflected
		and not info.Splash and not info.NoChain and not info.Proc
	return basic, ability
end

-- Before mitigation: returns the context CombatService.ApplyDamage uses
local function damageModifier(source, target, raw, info)
	local basic, ability = classify(source, info)
	local ctx = {
		Source = source, Target = target, Info = info, Basic = basic, Ability = ability,
		Magic = ability or info.Magic == true,
		Multiplier = 1, ArmorFactor = 1, MagicDefense = 0, TrueBonus = 0, RawBonus = 0, Reduction = 1, ExtraLifesteal = 0,
	}
	local now = Util.Now()
	local direct = basic or ability
	local armorFactor = 1 - debuffAmount(target, "ArmorBreak", "ArmorCrush")
	local magicDefenseFactor = 1 - debuffAmount(target, "MagicFracture")
	local fraction = healthFraction(target)
	local sourceEffects = effectsOf(source)
	if next(sourceEffects) and not info.Reflected then
		local state = stateOf(source)
		local record = recordOf(source, target)
		local mods = info.AttackMods
		local e = sourceEffects
		if e.Rupture and direct and now >= (state.RuptureReadyAt or 0) then
			state.RuptureReadyAt = now + e.Rupture.Interval
			armorFactor *= 1 - e.Rupture.Ignore
			magicDefenseFactor *= 1 - e.Rupture.Ignore
		end
		if e.ArmorPierce and basic then
			armorFactor *= 1 - e.ArmorPierce.Ignore
		end
		if e.Overflow and ability and source.MaxMana and source.Mana >= source.MaxMana * e.Overflow.Threshold then
			ctx.Multiplier *= 1 + e.Overflow.Bonus
		end
		if e.ArcaneReserve and ability and source.MaxMana then
			local missing = math.max(0, source.MaxMana - source.Mana)
			ctx.Multiplier *= 1 + math.min(e.ArcaneReserve.Max, math.floor(missing / 100) * e.ArcaneReserve.Per100)
		end
		if e.Mercyless and direct and fraction < e.Mercyless.Threshold then
			ctx.Multiplier *= 1 + e.Mercyless.Bonus
		end
		if e.FinishingShot and basic and fraction < e.FinishingShot.Threshold then
			ctx.Multiplier *= 1 + e.FinishingShot.Bonus
		end
		if e.PredatorsMark and direct and (record.PredatorUntil or 0) > now then
			ctx.Multiplier *= 1 + e.PredatorsMark.Bonus
		end
		if e.Curse and (record.CurseUntil or 0) > now then
			ctx.Multiplier *= 1 + e.Curse.Bonus
		end
		if e.Precision and basic then
			local distance = Util.FlatDistance(CombatService.GetPosition(source), CombatService.GetPosition(target)) - (target.Radius or 0)
			ctx.Multiplier *= 1 + math.clamp((distance - e.Precision.MinDistance) * e.Precision.PerStud, 0, e.Precision.Max)
		end
		if e.UnseenBlade and basic and mods and mods.UnseenBlade and not mods.UnseenBladeUsed then
			mods.UnseenBladeUsed = true
			ctx.TrueBonus += e.UnseenBlade.TrueDamage
		end
		if e.MarkOfWar and basic and (record.WarMarkUntil or 0) > now then
			record.WarMarkUntil = 0
			ctx.TrueBonus += e.MarkOfWar.TrueDamage
			ctx.WarMarkUsed = true
		end
		if e.CrushingBlow and basic and mods and mods.CrushingBlow then
			ctx.RawBonus += (source.MaxHealth or 0) * e.CrushingBlow.HPPercent
			ctx.CrushingBlow = true
		end
		if e.Ravage and basic and fraction < e.Ravage.Threshold then
			ctx.ExtraLifesteal += e.Ravage.Bonus
		end
		if e.Siphon and basic and target.Kind == "Hero" and (record.SiphonUntil or 0) > now then
			ctx.ExtraLifesteal += (record.SiphonStacks or 0) * e.Siphon.PerStack
		end
	end
	local targetEffects = effectsOf(target)
	if next(targetEffects) then
		local e = targetEffects
		if e.Desperation and fraction < e.Desperation.Threshold then
			ctx.Reduction *= 1 - e.Desperation.Reduction
		end
		if e.SpellReflection and ability then
			local state = stateOf(target)
			if now >= (state.ReflectReadyAt or 0) then
				state.ReflectReadyAt = now + e.SpellReflection.Cooldown
				ctx.Reduction *= 1 - e.SpellReflection.Reduce
				ctx.SpellReflect = e.SpellReflection
			end
		end
	end
	ctx.ArmorFactor = math.max(0, armorFactor)
	if ctx.Magic then
		ctx.MagicDefense = (target.MagicDefense or 0) * math.max(0, magicDefenseFactor)
	end
	return ctx
end

-- counts hits on the same target that land within `window` seconds of each other
local function countHits(record, key, window, now)
	if now - (record[key .. "At"] or -math.huge) > window then
		record[key] = 0
	end
	record[key] = (record[key] or 0) + 1
	record[key .. "At"] = now
	return record[key]
end

local function chainLightning(source, first, damage, count, range, color)
	local hit = { [first] = true }
	local from = first
	for _ = 1, count do
		local fromPosition = CombatService.GetPosition(from)
		local best, bestDistance = nil, range
		for _, candidate in ipairs(enemyUnitsNear(source, fromPosition, range)) do
			if not hit[candidate] then
				local distance = Util.FlatDistance(fromPosition, CombatService.GetPosition(candidate))
				if distance <= bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
		if not best then
			break
		end
		hit[best] = true
		Net.Effect("Lightning", { From = fromPosition, To = CombatService.GetPosition(best), Color = color })
		procDamage(source, best, damage, true)
		from = best
	end
end

-- After the damage landed: on-hit effects of the attacker, reactions of the target
local function damageDealt(ctx, total)
	local source, target, info = ctx.Source, ctx.Target, ctx.Info
	if total <= 0 or not UNIT_KINDS[target.Kind] then
		return
	end
	local now = Util.Now()
	local basic, ability = ctx.Basic, ctx.Ability
	local direct = basic or ability
	local sourceEffects = effectsOf(source)
	if next(sourceEffects) and not info.Reflected then
		local e = sourceEffects
		local state = stateOf(source)
		local record = recordOf(source, target)
		local targetPosition = CombatService.GetPosition(target)
		local mods = info.AttackMods
		if e.BloodPact and target.Kind == "Hero" and source.Alive then
			CombatService.Heal(source, total * e.BloodPact.HealPercent, false)
		end
		if e.ScorchingTouch and ability then
			addDot(source, target, "Burn", e.ScorchingTouch.DPS, e.ScorchingTouch.Duration, true)
		end
		if e.ChillingFlame and basic then
			if now - (record.LastBasicHitAt or -math.huge) >= e.ChillingFlame.Reset then
				CombatService.Slow(target, e.ChillingFlame.Slow, e.ChillingFlame.Duration, source)
			end
		end
		if e.PredatorsMark and direct then
			local allies = CombatService.GetEntitiesInRadius(targetPosition, e.PredatorsMark.AllyRadius, function(candidate)
				return candidate ~= target and candidate.Kind == "Hero" and candidate.Alive and candidate.Team == target.Team
			end)
			if #allies == 0 then
				record.PredatorUntil = now + e.PredatorsMark.Duration
			end
		end
		if e.ToxicWound and basic then
			addDot(source, target, "Poison", e.ToxicWound.DPS, e.ToxicWound.Duration, true)
		end
		if e.ToxicArrow and basic then
			addDot(source, target, "Venom", e.ToxicArrow.DPS, e.ToxicArrow.Duration, true, e.ToxicArrow.MaxStacks)
		end
		if e.Hemorrhage and basic then
			if countHits(record, "Hemorrhage", e.Hemorrhage.Window, now) >= e.Hemorrhage.Hits then
				record.Hemorrhage = 0
				addDot(source, target, "Bleed", e.Hemorrhage.DPS, e.Hemorrhage.Duration, false)
			end
		end
		if e.DeepCut and info.CritHit then
			addDot(source, target, "DeepCut", e.DeepCut.DPS, e.DeepCut.Duration, false)
		end
		if e.Vulnerable and info.CritHit then
			applyDebuff(target, "Vulnerable", e.Vulnerable.HealCut, e.Vulnerable.Duration)
		end
		if e.ArmorBreak and direct then
			if countHits(record, "ArmorBreak", e.ArmorBreak.Window, now) >= e.ArmorBreak.Hits then
				record.ArmorBreak = 0
				applyDebuff(target, "ArmorBreak", e.ArmorBreak.Shred, e.ArmorBreak.Duration)
			end
		end
		if e.ArmorCrush and basic and mods and mods.ArmorCrush then
			applyDebuff(target, "ArmorCrush", e.ArmorCrush.Shred, e.ArmorCrush.Duration)
		end
		if e.MarkOfWar and direct and not ctx.WarMarkUsed then
			if countHits(record, "MarkOfWar", e.MarkOfWar.Window, now) >= e.MarkOfWar.Hits then
				record.MarkOfWar = 0
				record.WarMarkUntil = now + e.MarkOfWar.Duration
			end
		end
		if e.Siphon and basic and target.Kind == "Hero" then
			if (record.SiphonUntil or 0) > now then
				record.SiphonStacks = math.min(e.Siphon.MaxStacks, (record.SiphonStacks or 0) + 1)
			else
				record.SiphonStacks = 1
			end
			record.SiphonUntil = now + e.Siphon.Window
		end
		if e.Combustion and ability then
			if countHits(record, "Combustion", e.Combustion.Window, now) >= e.Combustion.Hits then
				record.Combustion = 0
				local combustion = e.Combustion
				Net.Effect("Explosion", { Position = targetPosition, Radius = combustion.Radius, Color = Color3.fromRGB(255, 110, 40) })
				for _, victim in ipairs(enemyUnitsNear(source, targetPosition, combustion.Radius)) do
					procDamage(source, victim, combustion.Damage, true)
				end
			end
		end
		if e.DeepFreeze and ability then
			if now - (record.LastAbilityHitAt or -math.huge) <= e.DeepFreeze.Window then
				CombatService.Slow(target, e.DeepFreeze.Slow, e.DeepFreeze.Duration, source)
			end
		end
		if e.MagicFracture and ability then
			applyDebuff(target, "MagicFracture", e.MagicFracture.Shred, e.MagicFracture.Duration)
		end
		if e.Curse and ability then
			record.CurseUntil = now + e.Curse.Duration
		end
		if e.SpellDrain and ability and target.Kind == "Hero" and now >= (state.SpellDrainReadyAt or 0) then
			state.SpellDrainReadyAt = now + e.SpellDrain.Cooldown
			CombatService.RestoreMana(source, (source.MaxMana or 0) * e.SpellDrain.ManaPercent)
		end
		if e.AstralStrike and ability then
			state.AstralHits = (state.AstralHits or 0) + 1
			if state.AstralHits >= e.AstralStrike.Hits then
				state.AstralHits = 0
				local strike = e.AstralStrike
				local position = targetPosition
				Net.Effect("Telegraph", { Position = position, Radius = strike.Radius, Duration = strike.Delay, Color = Color3.fromRGB(255, 220, 120) })
				task.delay(strike.Delay, function()
					if not CombatService.Active then
						return
					end
					Net.Effect("Explosion", { Position = position, Radius = strike.Radius, Color = Color3.fromRGB(255, 210, 110) })
					for _, victim in ipairs(enemyUnitsNear(source, position, strike.Radius)) do
						procDamage(source, victim, strike.Damage, true)
					end
				end)
			end
		end
		if e.Static and ability then
			local charge = state.StaticCharge or 0
			if charge >= STATIC_MAX then
				state.StaticCharge = 0
				local static = e.Static
				local victims = enemyUnitsNear(source, targetPosition, static.Radius)
				table.sort(victims, function(a, b)
					if a == target or b == target then
						return a == target
					end
					return Util.FlatDistance(targetPosition, CombatService.GetPosition(a)) < Util.FlatDistance(targetPosition, CombatService.GetPosition(b))
				end)
				for index = 1, math.min(static.Targets, #victims) do
					Net.Effect("Lightning", { From = CombatService.GetPosition(source), To = CombatService.GetPosition(victims[index]), Color = Color3.fromRGB(140, 200, 255) })
					procDamage(source, victims[index], static.Damage, true)
				end
			else
				state.StaticCharge = math.min(STATIC_MAX, charge + e.Static.Charge)
			end
			if source.Model then
				source.Model:SetAttribute("StaticCharge", state.StaticCharge)
			end
		end
		if e.StaticArrows and basic and mods and mods.StaticArrows and not mods.StaticArrowsUsed then
			mods.StaticArrowsUsed = true
			local arrows = e.StaticArrows
			procDamage(source, target, arrows.Damage, true)
			chainLightning(source, target, arrows.Damage, arrows.Bounces, arrows.Range, Color3.fromRGB(120, 190, 255))
		end
		if e.Carnage and direct and target.Kind == "Hero" and now - (state.CarnageAt or -math.huge) >= CARNAGE_STACK_GAP then
			state.CarnageAt = now
			local active = (state.CarnageUntil or 0) > now
			state.CarnageStacks = active and math.min(e.Carnage.MaxStacks, (state.CarnageStacks or 0) + 1) or 1
			state.CarnageUntil = now + e.Carnage.Duration
			refreshDynamic(source)
		end
		if ctx.CrushingBlow then
			Net.Effect("Shockwave", { Position = targetPosition, Radius = 4, Color = Color3.fromRGB(200, 40, 60) })
		end
		if basic then
			record.LastBasicHitAt = now
		end
		if ability then
			record.LastAbilityHitAt = now
		end
	end

	-- the target's own passives react to being hit
	local targetEffects = target.Alive and effectsOf(target) or EMPTY
	if next(targetEffects) then
		local e = targetEffects
		local attackerIsUnit = source ~= nil and source ~= target and UNIT_KINDS[source.Kind] and source.Alive
		if e.FrozenGround and attackerIsUnit and not info.Proc and not info.Reflected then
			CombatService.Slow(source, e.FrozenGround.Slow, e.FrozenGround.Duration, target)
		end
		if e.Retaliation and not ctx.Magic and source ~= nil and source ~= target then
			stateOf(target).RetaliationUntil = now + e.Retaliation.Duration
		end
		if ctx.SpellReflect and attackerIsUnit then
			local reflected = total * ctx.SpellReflect.Reflect
			Net.Effect("Lightning", { From = CombatService.GetPosition(target), To = CombatService.GetPosition(source), Color = Color3.fromRGB(170, 210, 255) })
			task.defer(CombatService.ApplyDamage, target, source, reflected, { Reflected = true, IgnoreArmor = true, NoChain = true })
		end
		if e.Retaliation or e.DragonsFury then
			refreshDynamic(target)
		end
	end
end

-- A basic attack is starting (before LastAttackAt moves): every-Nth-attack and idle effects
local function beforeBasicAttack(entity, now)
	local e = effectsOf(entity)
	if next(e) == nil then
		return nil
	end
	local state = stateOf(entity)
	state.AttackCount = (state.AttackCount or 0) + 1
	local count = state.AttackCount
	local mods, any = {}, false
	if e.PiercingShot and count % e.PiercingShot.Every == 0 then
		mods.Pierce, any = true, true
	end
	if e.StaticArrows and count % e.StaticArrows.Every == 0 then
		mods.StaticArrows, any = true, true
	end
	if e.CrushingBlow and count % e.CrushingBlow.Every == 0 then
		mods.CrushingBlow, any = true, true
	end
	if e.ArmorCrush and count % e.ArmorCrush.Every == 0 then
		mods.ArmorCrush, any = true, true
	end
	if e.UnseenBlade and now - (entity.LastAttackAt or 0) >= e.UnseenBlade.Idle then
		mods.UnseenBlade, any = true, true
	end
	return any and mods or nil
end

local function healMultiplier(entity)
	return 1 - debuffAmount(entity, "Vulnerable", "GrievousAura")
end

local function ccMultiplier(entity)
	local tenacity = effectsOf(entity).Tenacity
	return tenacity and (1 - tenacity.Reduction) or 1
end

local function stunEnded(entity)
	local tenacious = effectsOf(entity).Tenacious
	if tenacious and entity.Alive then
		CombatService.Haste(entity, tenacious.Haste, tenacious.Duration)
	end
end

-- Stacking passives (Soul Harvest, Overgrowth) add max HP while the item is equipped
local function bonusHook(participant, bonuses)
	local stacks = participant.PassiveStacks
	if not stacks then
		return
	end
	local e = effectsOfParticipant(participant)
	if e.SoulHarvest then
		bonuses.MaxHealth += stacks.SoulHarvest or 0
	end
	if e.Overgrowth then
		bonuses.MaxHealth += stacks.OvergrowthHP or 0
	end
end

local function revealedTo(entity, team)
	local set = revealed[team]
	return set ~= nil and set[entity] == true
end

-- Events ------------------------------------------------------------------------------------
local function onEntityDied(target, killer)
	target.Dots = nil
	if not CombatService.Active or not UNIT_KINDS[target.Kind] then
		return
	end
	local position = CombatService.GetPosition(target)
	if killer and killer.Kind == "Hero" and killer.Participant then
		local e = effectsOf(killer)
		if e.Bounty and target.Kind == "Hero" then
			local participant = killer.Participant
			participant.Stats.Gold = (participant.Stats.Gold or 0) + e.Bounty.Gold
			getPlayerService().SetPlayerAttributes(participant)
			notify(killer, string.format("+%d gold (Bounty)", e.Bounty.Gold))
		end
		if e.KillRush and killer.Alive then
			CombatService.Haste(killer, e.KillRush.Haste, e.KillRush.Duration)
		end
	end
	-- stacking passives of enemy heroes standing nearby
	for _, hero in pairs(CombatService.Entities) do
		if hero.Kind == "Hero" and hero.Alive and hero.Participant and CombatService.AreEnemies(hero, target) then
			local e = effectsOf(hero)
			if e.SoulHarvest or e.Overgrowth then
				local distance = Util.FlatDistance(CombatService.GetPosition(hero), position)
				local participant = hero.Participant
				participant.PassiveStacks = participant.PassiveStacks or {}
				local stacks = participant.PassiveStacks
				local changed = false
				if e.SoulHarvest and target.Kind == "Hero" and distance <= e.SoulHarvest.Radius then
					local before = stacks.SoulHarvest or 0
					stacks.SoulHarvest = math.min(e.SoulHarvest.Cap, before + e.SoulHarvest.PerKill)
					if stacks.SoulHarvest > before then
						changed = true
						notify(hero, string.format("Soul Harvest: +%d max HP (%d / %d)", stacks.SoulHarvest - before, stacks.SoulHarvest, e.SoulHarvest.Cap))
					end
				end
				if e.Overgrowth and distance <= e.Overgrowth.Radius then
					stacks.OvergrowthKills = (stacks.OvergrowthKills or 0) + 1
					if stacks.OvergrowthKills % e.Overgrowth.Every == 0 then
						stacks.OvergrowthHP = (stacks.OvergrowthHP or 0) + e.Overgrowth.HP
						changed = true
						notify(hero, string.format("Overgrowth: +%d max HP (total +%d)", e.Overgrowth.HP, stacks.OvergrowthHP))
					end
				end
				if changed then
					CombatService.RefreshParticipantBonuses(participant)
					broadcast()
				end
			end
		end
	end
end

local function onAssist(contributor)
	local entity = contributor and contributor.Entity
	if not entity or not entity.Alive then
		return
	end
	local rewind = effectsOf(entity).Rewind
	if not rewind then
		return
	end
	local now = Util.Now()
	if entity.AbilityReadyAt > now then
		entity.AbilityReadyAt = math.max(now, entity.AbilityReadyAt - rewind.Seconds)
		if entity.Model then
			entity.Model:SetAttribute("AbilityReadyAt", entity.AbilityReadyAt)
		end
	end
	local readyAt = contributor.ItemReadyAt or {}
	for slot = 1, ItemDefinitions.MAX_MYTHIC_SLOTS do
		local itemId = contributor.Mythics and contributor.Mythics[slot]
		if itemId and (readyAt[itemId] or 0) > now then
			readyAt[itemId] = math.max(now, readyAt[itemId] - rewind.Seconds)
		end
	end
	notify(entity, string.format("Rewind: cooldowns -%d sec", rewind.Seconds))
	broadcast()
end

-- Tick --------------------------------------------------------------------------------------
local function tickDots(now)
	for target in pairs(dotTargets) do
		local dots = target.Dots
		if not dots or not target.Alive then
			target.Dots = nil
			dotTargets[target] = nil
		else
			local any = false
			for key, dot in pairs(dots) do
				if dot.Until <= now then
					dots[key] = nil
				else
					any = true
					CombatService.ApplyDamage(dot.Source, target, dot.DPS * dot.Stacks * TICK, { Proc = true, Magic = dot.Magic, IgnoreArmor = true, NoChain = true, Dot = dot.Kind })
					if not target.Alive then
						break
					end
				end
			end
			if not any or not target.Alive then
				target.Dots = nil
				dotTargets[target] = nil
			end
		end
	end
end

local function tickHero(hero, now, newRevealed)
	local e = effectsOf(hero)
	if next(e) == nil then
		if (hero.PassiveAttackDamage or 0) ~= 0 or (hero.PassiveAttackSpeed or 0) ~= 0 then
			refreshDynamic(hero)
		end
		return
	end
	local state = stateOf(hero)
	local position = CombatService.GetPosition(hero)
	if e.Moonwell then
		state.MoonwellAt = state.MoonwellAt or (now + e.Moonwell.Interval)
		if now >= state.MoonwellAt then
			state.MoonwellAt = now + e.Moonwell.Interval
			CombatService.RestoreMana(hero, math.max(0, (hero.MaxMana or 0) - (hero.Mana or 0)) * e.Moonwell.MissingPercent)
		end
	end
	if e.BurningBody then
		state.BurningBodyAt = state.BurningBodyAt or now
		if now >= state.BurningBodyAt then
			state.BurningBodyAt = now + 0.5
			local body = e.BurningBody
			local damage = (body.DPS + (hero.MaxHealth or 0) * body.HPPercent) * 0.5
			for _, victim in ipairs(enemyUnitsNear(hero, position, body.Radius)) do
				procDamage(hero, victim, damage, true)
			end
		end
	end
	if e.GrievousAura then
		for _, victim in ipairs(enemyUnitsNear(hero, position, e.GrievousAura.Radius)) do
			applyDebuff(victim, "GrievousAura", e.GrievousAura.HealCut, TICK * 2 + 0.1)
		end
	end
	if e.Rescue and now >= (state.RescueReadyAt or 0) then
		local rescue = e.Rescue
		local lowest, lowestFraction = nil, rescue.Threshold
		for _, ally in ipairs(CombatService.GetEntitiesInRadius(position, rescue.Radius, function(candidate)
			return candidate ~= hero and candidate.Kind == "Hero" and candidate.Alive and candidate.Team == hero.Team
		end)) do
			local fraction = healthFraction(ally)
			if fraction < lowestFraction then
				lowest, lowestFraction = ally, fraction
			end
		end
		if lowest then
			state.RescueReadyAt = now + rescue.Cooldown
			local amount = rescue.Shield + (hero.MaxHealth or 0) * rescue.ShieldHPPercent
			CombatService.AddShield(lowest, amount, rescue.Duration)
			CombatService.AddShield(hero, amount, rescue.Duration)
			notify(hero, "Rescue: shielded an ally")
			notify(lowest, "Rescue: shielded by " .. (hero.Participant and hero.Participant.Name or "an ally"))
		end
	end
	if e.TrueSight then
		for _, enemy in ipairs(CombatService.GetEntitiesInRadius(position, e.TrueSight.Radius, function(candidate)
			return candidate.Kind == "Hero" and candidate.Alive and candidate.Team ~= hero.Team and CombatService.IsStealthed(candidate)
		end)) do
			newRevealed[hero.Team] = newRevealed[hero.Team] or {}
			newRevealed[hero.Team][enemy] = true
		end
	end
	refreshDynamic(hero)
end

local function tick()
	local now = Util.Now()
	tickDots(now)
	local newRevealed = {}
	for _, entity in pairs(CombatService.Entities) do
		if entity.Kind == "Hero" and entity.Alive then
			tickHero(entity, now, newRevealed)
		end
	end
	revealed = newRevealed
end

-- Public API --------------------------------------------------------------------------------
function PassiveService.Init()
	CombatService.DamageModifier = damageModifier
	CombatService.DamageDealt = damageDealt
	CombatService.BeforeBasicAttack = beforeBasicAttack
	CombatService.HealMultiplier = healMultiplier
	CombatService.CCMultiplier = ccMultiplier
	CombatService.StunEnded = stunEnded
	CombatService.BonusHook = bonusHook
	CombatService.RevealedTo = revealedTo
	CombatService.EntityDied:Connect(onEntityDied)
	CombatService.AssistGranted:Connect(onAssist)
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(TICK)
			if CombatService.Active then
				local ok, err = pcall(tick)
				if not ok then
					warn("[Ruinfall] PassiveService tick error:", err)
				end
			elseif next(revealed) then
				revealed = {}
			end
		end
	end)
end

-- Debug: effects + state of a hero (GameServer debug command "passives")
function PassiveService.Describe(entity)
	local names = {}
	for name in pairs(effectsOf(entity)) do
		table.insert(names, name)
	end
	table.sort(names)
	local state = entity.PassiveState or {}
	return {
		Effects = names,
		PassiveAttackDamage = entity.PassiveAttackDamage or 0,
		PassiveAttackSpeed = entity.PassiveAttackSpeed or 0,
		CarnageStacks = state.CarnageStacks or 0,
		StaticCharge = state.StaticCharge or 0,
		AttackCount = state.AttackCount or 0,
		Mana = entity.Mana, MaxMana = entity.MaxMana,
		MagicDefense = entity.MagicDefense, CooldownReduction = entity.CooldownReduction,
		CritChance = entity.BonusCritChance, Lifesteal = entity.BonusLifesteal, MagicPower = entity.BonusMagicPower,
		Debuffs = entity.PassiveDebuffs and (function()
			local out = {}
			for key, debuff in pairs(entity.PassiveDebuffs) do
				if debuff.Until > Util.Now() then
					out[key] = debuff.Amount
				end
			end
			return out
		end)() or {},
		Dots = entity.Dots and (function()
			local out = {}
			for key, dot in pairs(entity.Dots) do
				out[key] = dot.DPS * dot.Stacks
			end
			return out
		end)() or {},
	}
end

return PassiveService
