-- ItemService: server-authoritative Mythic item inventory (2 slots) and item-granted
-- E/R abilities. The rule is fixed and dynamic: MYTHIC SLOT 1 -> E, MYTHIC SLOT 2 -> R.
-- Clients only send intents (Buy <id>, Sell <slot>, Swap, use E/R); prices, gold,
-- ownership, class locks, cooldowns, targets and damage are all decided here.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local AbilityScaling = require(Shared:WaitForChild("AbilityScaling"))
local Net = require(script.Parent:WaitForChild("Net"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

-- Constants
local STATE = Constants.MatchState
local MAX_SLOTS = ItemDefinitions.MAX_MYTHIC_SLOTS
local BOOT_SLOT = ItemDefinitions.BOOT_SLOT -- 4: the separate boot slot (right mouse)
local MAX_PASSIVES = ItemDefinitions.MAX_PASSIVE_SLOTS -- 3 passive items (automatic, no hotkey)
local PASSIVE_BASE = ItemDefinitions.PASSIVE_SLOT_BASE -- slot index of passive N = PASSIVE_BASE + N
local COOLDOWN_GRACE = 0.15
local REQUEST_INTERVAL = 0.2
local UNIT_KINDS = { Hero = true, Monster = true, Creep = true }

-- State
local ItemService = {}
local handlers = {}
local lastRequest = setmetatable({}, { __mode = "k" })

-- Helpers -------------------------------------------------------------------------------
local function mythicsOf(participant)
	participant.Mythics = participant.Mythics or {}
	participant.ItemReadyAt = participant.ItemReadyAt or {}
	return participant.Mythics
end

local function passivesOf(participant)
	participant.Passives = participant.Passives or {}
	return participant.Passives
end

local function ownsItem(participant, itemId)
	if participant.Boots == itemId then
		return BOOT_SLOT
	end
	local passives = passivesOf(participant)
	for slot = 1, MAX_PASSIVES do
		if passives[slot] == itemId then
			return PASSIVE_BASE + slot
		end
	end
	local mythics = mythicsOf(participant)
	for slot = 1, MAX_SLOTS do
		if mythics[slot] == itemId then
			return slot
		end
	end
	return nil
end

local function firstEmptySlot(participant)
	local mythics = mythicsOf(participant)
	for slot = 1, MAX_SLOTS do
		if not mythics[slot] then
			return slot
		end
	end
	return nil
end

local function isValidSlot(slot)
	return type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= MAX_SLOTS
end

local function changed(participant)
	CombatService.RefreshParticipantBonuses(participant)
	PlayerService.SetPlayerAttributes(participant)
	MatchManager.Broadcast()
end

-- sound (optional): an AudioConfig cue the buyer's client plays with the notification
local function notify(player, message, style, sound)
	if player then -- a nil target would broadcast to everyone
		Net.Notify(player, message, style, sound and { Sound = sound } or nil)
	end
end

local function reject(player, message)
	notify(player, message, "Warning", "UI.PurchaseFail")
	return false, message
end

local function isUnitEnemy(entity, candidate)
	return candidate and candidate.Alive and UNIT_KINDS[candidate.Kind] and CombatService.AreEnemies(entity, candidate)
end

-- Inventory -----------------------------------------------------------------------------
-- replaceSlot (optional): when both slots are full the player must explicitly choose a
-- slot to replace; the old item is sold for its sell value. Never replaced silently.
-- Boots go to their own slot. Owning boots of another class (after a class change) is
-- replaced explicitly by buying new boots; the old pair is sold back for half.
local function buyBoots(player, participant, item)
	local canShop, reason = ShopService.CanShop(participant)
	if not canShop then
		return reject(player, reason)
	end
	if not ItemDefinitions.CanClassUse(item, participant.ClassKey) then
		return reject(player, "LOCKED - Requires " .. tostring(item.Class))
	end
	if participant.Boots == item.Id then
		return reject(player, "You already own " .. item.Name)
	end
	local old = ItemDefinitions.GetItem(participant.Boots)
	local refund = old and ItemDefinitions.GetSellValue(old) or 0
	local gold = PlayerService.GetGold(participant)
	if gold + refund < item.Price then
		return reject(player, string.format("Not enough gold (%d / %d)", math.floor(gold + refund), item.Price))
	end
	PlayerService.AddGold(participant, refund - item.Price)
	participant.Boots = item.Id
	changed(participant)
	if old then
		notify(player, string.format("Replaced %s with %s (+%d gold)", old.Name, item.Name, refund), "Success", "UI.BootsAcquire")
	else
		notify(player, string.format("%s equipped in the Boot Slot (Right Mouse)", item.Name), "Success", "UI.BootsAcquire")
	end
	return true, BOOT_SLOT
end

-- Passive items: up to MAX_PASSIVES different ones, placed in the first free passive slot.
-- No duplicates, never replaced silently (sell one first when all 3 slots are used).
local function buyPassive(player, participant, item)
	local canShop, reason = ShopService.CanShop(participant)
	if not canShop then
		return reject(player, reason)
	end
	if not ItemDefinitions.CanClassUse(item, participant.ClassKey) then
		return reject(player, "LOCKED - Requires " .. tostring(item.Class))
	end
	local passives = passivesOf(participant)
	local free = nil
	for slot = 1, MAX_PASSIVES do
		if passives[slot] == item.Id then
			return reject(player, "You already own " .. item.Name)
		end
		if not passives[slot] and not free then
			free = slot
		end
	end
	if not free then
		return reject(player, string.format("PASSIVE SLOTS FULL (%d / %d) - sell a passive item first", MAX_PASSIVES, MAX_PASSIVES))
	end
	local gold = PlayerService.GetGold(participant)
	if gold < item.Price then
		return reject(player, string.format("Not enough gold (%d / %d)", math.floor(gold), item.Price))
	end
	PlayerService.AddGold(participant, -item.Price)
	passives[free] = item.Id
	changed(participant)
	notify(player, string.format("%s equipped in Passive Slot %d", item.Name, free), "Success", "UI.MythicAcquire")
	return true, PASSIVE_BASE + free
end

function ItemService.Buy(player, participant, itemId, replaceSlot)
	local item = ItemDefinitions.GetItem(itemId)
	if item and item.SlotType == "Boots" then
		return buyBoots(player, participant, item)
	end
	if item and item.SlotType == "Passive" then
		return buyPassive(player, participant, item)
	end
	if not item or item.SlotType ~= "Mythic" then
		return reject(player, "Unknown item")
	end
	local canShop, reason = ShopService.CanShop(participant)
	if not canShop then
		return reject(player, reason)
	end
	if not ItemDefinitions.CanClassUse(item, participant.ClassKey) then
		return reject(player, "LOCKED - Requires " .. tostring(item.Class))
	end
	if ownsItem(participant, itemId) then
		return reject(player, "You already own " .. item.Name)
	end
	local mythics = mythicsOf(participant)
	local slot = firstEmptySlot(participant)
	local refund = 0
	if not slot then
		if replaceSlot == nil then
			return reject(player, "MYTHIC SLOTS FULL")
		end
		if not isValidSlot(replaceSlot) or not mythics[replaceSlot] then
			return reject(player, "Invalid slot to replace")
		end
		slot = replaceSlot
		refund = ItemDefinitions.GetSellValue(ItemDefinitions.GetItem(mythics[slot]))
	end
	local gold = PlayerService.GetGold(participant)
	if gold + refund < item.Price then
		return reject(player, string.format("Not enough gold (%d / %d)", math.floor(gold + refund), item.Price))
	end
	local replaced = mythics[slot]
	PlayerService.AddGold(participant, refund - item.Price)
	mythics[slot] = itemId
	changed(participant)
	if replaced then
		notify(player, string.format("Replaced %s with %s (+%d gold)", ItemDefinitions.GetItem(replaced).Name, item.Name, refund), "Success", "UI.MythicAcquire")
	else
		notify(player, string.format("%s equipped in Mythic Slot %d (%s)", item.Name, slot, ItemDefinitions.SLOT_KEYS[slot]), "Success", "UI.MythicAcquire")
	end
	return true, slot
end

function ItemService.Sell(player, participant, slot)
	if slot == BOOT_SLOT then
		local canShop, reason = ShopService.CanShop(participant)
		if not canShop then
			return reject(player, reason)
		end
		local boots = ItemDefinitions.GetItem(participant.Boots)
		if not boots then
			return reject(player, "Your boot slot is empty")
		end
		local bootValue = ItemDefinitions.GetSellValue(boots)
		participant.Boots = nil
		PlayerService.AddGold(participant, bootValue)
		changed(participant)
		notify(player, string.format("Sold %s for %d gold", boots.Name, bootValue), "Success", "UI.Sell")
		return true, bootValue
	end
	if type(slot) == "number" and slot > PASSIVE_BASE and slot <= PASSIVE_BASE + MAX_PASSIVES and slot == math.floor(slot) then
		local canShop, reason = ShopService.CanShop(participant)
		if not canShop then
			return reject(player, reason)
		end
		local passives = passivesOf(participant)
		local index = slot - PASSIVE_BASE
		local passive = ItemDefinitions.GetItem(passives[index])
		if not passive then
			return reject(player, "That passive slot is empty")
		end
		local passiveValue = ItemDefinitions.GetSellValue(passive)
		passives[index] = nil
		PlayerService.AddGold(participant, passiveValue)
		changed(participant)
		notify(player, string.format("Sold %s for %d gold", passive.Name, passiveValue), "Success", "UI.Sell")
		return true, passiveValue
	end
	if not isValidSlot(slot) then
		return reject(player, "Invalid slot")
	end
	local canShop, reason = ShopService.CanShop(participant)
	if not canShop then
		return reject(player, reason)
	end
	local mythics = mythicsOf(participant)
	local item = ItemDefinitions.GetItem(mythics[slot])
	if not item then
		return reject(player, "That slot is empty")
	end
	local value = ItemDefinitions.GetSellValue(item)
	mythics[slot] = nil
	PlayerService.AddGold(participant, value)
	changed(participant)
	notify(player, string.format("Sold %s for %d gold", item.Name, value), "Success", "UI.Sell")
	return true, value
end

-- Royale loot ---------------------------------------------------------------------------
-- Equip an item picked up from the ground: no gold, no shop, no class lock (Royale has no
-- classes). Fills the first free slot of the item's kind, otherwise swaps it with the
-- replace slot (E/R mythic: the R slot, boots: the boot slot, passives: the last passive).
-- Returns ok, message, replacedItemId (the caller drops the replaced item on the ground).
function ItemService.Grant(participant, itemId)
	local item = ItemDefinitions.GetItem(itemId)
	if not item or not participant then
		return false, "Unknown item"
	end
	if ownsItem(participant, itemId) then
		return false, "You already carry " .. item.Name
	end
	local replaced = nil
	if item.SlotType == "Boots" then
		replaced = participant.Boots
		participant.Boots = itemId
	elseif item.SlotType == "Passive" then
		local passives = passivesOf(participant)
		local free = nil
		for slot = 1, MAX_PASSIVES do
			if not passives[slot] then
				free = slot
				break
			end
		end
		free = free or MAX_PASSIVES
		replaced = passives[free]
		passives[free] = itemId
	else
		local mythics = mythicsOf(participant)
		local slot = firstEmptySlot(participant) or MAX_SLOTS
		replaced = mythics[slot]
		mythics[slot] = itemId
		participant.ItemReadyAt[itemId] = Util.Now() + 1
	end
	changed(participant)
	return true, item.Name, replaced
end

-- Remove an equipped item (Royale: the player drops it on the ground).
-- slot: 1 / 2 (E / R), BOOT_SLOT, or PASSIVE_BASE + n. Returns the removed item id.
function ItemService.Unequip(participant, slot)
	if not participant or type(slot) ~= "number" then
		return nil
	end
	local removed = nil
	if slot == BOOT_SLOT then
		removed = participant.Boots
		participant.Boots = nil
	elseif slot > PASSIVE_BASE and slot <= PASSIVE_BASE + MAX_PASSIVES then
		local passives = passivesOf(participant)
		removed = passives[slot - PASSIVE_BASE]
		passives[slot - PASSIVE_BASE] = nil
	elseif isValidSlot(slot) then
		local mythics = mythicsOf(participant)
		removed = mythics[slot]
		mythics[slot] = nil
	end
	if removed then
		changed(participant)
	end
	return removed
end

-- Swap two mythic slots (default E <-> R). Hotkeys follow slots (1 = E, 2 = R, 3 = SPACE).
function ItemService.Swap(player, participant, from, to)
	if MatchManager.State ~= STATE.ACTIVE then
		return reject(player, "Items can only be swapped during a match")
	end
	from = isValidSlot(from) and from or 1
	to = isValidSlot(to) and to or 2
	if from == to then
		return false
	end
	local mythics = mythicsOf(participant)
	if not mythics[from] and not mythics[to] then
		return reject(player, "No mythic items to swap")
	end
	mythics[from], mythics[to] = mythics[to], mythics[from]
	changed(participant)
	return true
end

-- Item abilities ------------------------------------------------------------------------
-- handler(entity, ability, origin, aimPosition, targetId, now) -> false, reason to cancel
-- (a cancelled cast refunds the cooldown).

-- Fighter crowd-control boots: an area stun in a wide cone in front of you (every enemy
-- inside is hit, no target selection). Casts even when nobody is in range.
handlers.HeavyKick = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local cosHalfArc = math.cos(math.rad(ability.Arc / 2))
	CombatService.BreakStealth(entity)
	local impact = origin + direction * (ability.Range * 0.6)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true, EntityId = entity.Id })
	Net.Effect("HeavyKick", { Origin = origin, Position = impact, Color = ability.Color })
	Net.Effect("Shockwave", { Position = impact, Radius = ability.Range * 0.5, Color = ability.Color })
	local victims = CombatService.GetEntitiesInRadius(origin, ability.Range, function(candidate)
		return isUnitEnemy(entity, candidate)
	end)
	for _, victim in ipairs(victims) do
		local position = CombatService.GetPosition(victim)
		local offset = Util.Flat(position - origin)
		local inCone = offset.Magnitude <= victim.Radius + 1 or offset.Unit:Dot(direction) >= cosHalfArc
		if inCone and CombatService.HasLineOfSight(origin, position) then
			CombatService.ApplyDamage(entity, victim, ability.Damage)
			if victim.Alive then
				CombatService.Stun(victim, ability.Stun, entity)
				Net.Effect("Stun", { Position = position, Duration = ability.Stun })
			end
		end
	end
	return true
end

handlers.PointStrike = function(entity, ability, origin, _, targetId)
	local target = type(targetId) == "string" and CombatService.GetEntity(targetId) or nil
	if not isUnitEnemy(entity, target) then
		return false, "Select a living enemy"
	end
	if CombatService.IsStealthed(target) then
		return false, "Target is not visible"
	end
	local targetPosition = CombatService.GetPosition(target)
	if Util.FlatDistance(origin, targetPosition) > ability.Range + target.Radius then
		return false, "Target out of range"
	end
	if not CombatService.HasLineOfSight(origin, targetPosition) then
		return false, "No line of sight"
	end
	CombatService.BreakStealth(entity)
	Net.Effect("PointStrike", { From = origin, Position = targetPosition, Color = ability.Color })
	CombatService.ApplyDamage(entity, target, ability.Damage, { Crit = true })
	return true
end

handlers.WindPull = function(entity, ability, origin, aimPosition)
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > ability.Range then
		offset = offset.Unit * ability.Range
	end
	local center = Vector3.new(origin.X + offset.X, 0.2, origin.Z + offset.Z)
	CombatService.BreakStealth(entity)
	Net.Effect("WindPull", { Position = center, Radius = ability.Radius, Duration = ability.Duration, Color = ability.Color })
	local victims = CombatService.GetEntitiesInRadius(center, ability.Radius, function(candidate)
		return isUnitEnemy(entity, candidate)
	end)
	ItemService.LastDebug = { Ability = "WindPull", Center = center, Victims = {} }
	for _, victim in ipairs(victims) do
		table.insert(ItemService.LastDebug.Victims, victim.Id)
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		if victim.Alive then
			local position = CombatService.GetPosition(victim)
			local toCenter = Util.Flat(center - position)
			local distance = math.min(ability.PullDistance, math.max(0, toCenter.Magnitude - 1.5))
			if distance > 0.5 then
				CombatService.Dash(victim, toCenter.Unit, distance, ability.Duration)
			end
		end
	end
	return true
end

handlers.SpikedScale = function(entity, ability, origin, _, _, now)
	entity.ReflectUntil = now + ability.Duration
	entity.ReflectPercent = ability.ReflectPercent
	if entity.Model then
		entity.Model:SetAttribute("SpikedScaleUntil", entity.ReflectUntil)
	end
	Net.Effect("SpikedScale", { EntityId = entity.Id, Position = origin, Duration = ability.Duration, Color = ability.Color })
	return true
end

handlers.CleavingArc = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.MeleeStrike(entity, origin, direction, ability.Range, ability.Arc, ability.Damage, true, true)
	return true
end

handlers.Bulwark = function(entity, ability)
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	return true
end

handlers.Blink = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local distance = math.clamp(Util.FlatDistance(origin, aimPosition), 4, ability.Range)
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	CombatService.Dash(entity, direction, distance, 0.08)
	return true
end

-- Role items ----------------------------------------------------------------------------
local function enemiesInRadius(entity, center, radius, unitsOnly)
	return CombatService.GetEntitiesInRadius(center, radius, function(candidate)
		if unitsOnly then
			return isUnitEnemy(entity, candidate)
		end
		return CombatService.AreEnemies(entity, candidate)
	end)
end

handlers.ShadowDash = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local finish = CombatService.Dash(entity, direction, ability.Range, 0.18) or origin
	local path = Util.Flat(finish - origin)
	local length = path.Magnitude
	for _, candidate in pairs(CombatService.Entities) do
		if isUnitEnemy(entity, candidate) then
			local offset = Util.Flat(CombatService.GetPosition(candidate) - origin)
			local along = length > 0 and math.clamp(offset:Dot(path.Unit), 0, length) or 0
			local closest = length > 0 and path.Unit * along or Vector3.zero
			if (offset - closest).Magnitude <= ability.Width + candidate.Radius then
				CombatService.ApplyDamage(entity, candidate, ability.Damage)
			end
		end
	end
	return true
end

-- Smoke Bomb: a smoke cloud at the caster's feet; enemies inside miss basic attacks
-- (checked in CombatService.ApplyDamage for every basic attack).
handlers.SmokeVeil = function(entity, ability, origin)
	CombatService.AddSmokeZone(entity.Team, origin, ability.Radius, ability.Duration)
	Net.Effect("SmokeCloud", { Position = Vector3.new(origin.X, 0, origin.Z), Radius = ability.Radius, Duration = ability.Duration, Color = ability.Color })
	return true
end

-- Ranged skillshot: full damage to the first enemy hit, then an explosion (SplashPercent of the
-- damage) on every other enemy within ExplosionRadius of where the fireball lands
handlers.Fireball = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.FireProjectile({
		Owner = entity, Origin = origin + direction * 1.5, Direction = direction, Speed = ability.Speed,
		Range = ability.Range, Radius = 1.4, Damage = ability.Damage, Style = "Fireball", IgnoreArmor = ability.TrueDamage,
		OnEnd = function(position, hitEntity)
			if not CombatService.Active or not ability.ExplosionRadius then
				return
			end
			Net.Effect("Explosion", { Position = position, Radius = ability.ExplosionRadius, Color = ability.Color })
			for _, victim in ipairs(enemiesInRadius(entity, position, ability.ExplosionRadius, true)) do
				if victim ~= hitEntity then
					CombatService.ApplyDamage(entity, victim, ability.Damage * (ability.SplashPercent or 0), { IgnoreArmor = ability.TrueDamage })
				end
			end
		end,
	})
	return true
end

handlers.FrostNova = function(entity, ability, origin)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, true)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		if victim.Alive then
			CombatService.Stun(victim, ability.Stun)
			Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Stun })
		end
	end
	return true
end

handlers.PiercingArrow = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.FireProjectile({
		Owner = entity, Origin = origin + direction * 1.5, Direction = direction, Speed = ability.Speed,
		Range = ability.Range, Radius = 1.2, Damage = ability.Damage, Style = "PowerShot", Pierce = true, Crit = true,
	})
	return true
end

handlers.Tumble = function(entity, ability, origin, aimPosition, _, now)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.Dash(entity, direction, ability.Range, 0.2)
	entity.NextAttackMultiplier = ability.Empower
	entity.NextAttackExpires = now + ability.Duration
	if entity.Model then
		entity.Model:SetAttribute("EmpoweredAttack", true)
	end
	return true
end

handlers.ShieldBash = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local cosHalfArc = math.cos(math.rad(ability.Arc / 2))
	CombatService.BreakStealth(entity)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Range, true)) do
		local offset = Util.Flat(CombatService.GetPosition(victim) - origin)
		if offset.Magnitude <= victim.Radius + 1 or offset.Unit:Dot(direction) >= cosHalfArc then
			CombatService.ApplyDamage(entity, victim, ability.Damage)
			if victim.Alive then
				CombatService.Stun(victim, ability.Stun)
				Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Stun })
			end
		end
	end
	return true
end

handlers.RallyingHorn = function(entity, ability, origin)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, ally in ipairs(CombatService.GetEntitiesInRadius(origin, ability.Radius, function(candidate)
		return candidate.Kind == "Hero" and candidate.Team == entity.Team
	end)) do
		CombatService.AddShield(ally, ability.Shield, ability.Duration)
	end
	return true
end

handlers.Whirlwind = function(entity, ability, origin)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Melee", { Origin = origin, Direction = entity.Root.CFrame.LookVector, Range = ability.Radius, Arc = 360, Color = ability.Color, Empowered = true })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, false)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage)
	end
	return true
end

handlers.CrushingLeap = function(entity, ability, origin, aimPosition)
	local offset = Util.Flat(aimPosition - origin)
	local distance = math.min(offset.Magnitude, ability.Range)
	local direction = offset.Magnitude > 0.1 and offset.Unit or Util.Flat(entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local landing = CombatService.Dash(entity, direction, distance, 0.35) or origin
	task.delay(0.35, function()
		if not CombatService.Active or not entity.Alive then
			return
		end
		Net.Effect("Explosion", { Position = landing, Radius = ability.Radius, Color = ability.Color })
		for _, victim in ipairs(enemiesInRadius(entity, landing, ability.Radius, true)) do
			CombatService.ApplyDamage(entity, victim, ability.Damage)
			if victim.Alive then
				CombatService.Stun(victim, ability.Stun)
			end
		end
	end)
	return true
end

-- Golem Heart: hurl the golem to a point (ranged). It lands with an area stun + damage,
-- then fights whatever its summoner attacks (CreepService.thinkGolem).
handlers.SummonGolem = function(entity, ability, origin, aimPosition)
	local module = script.Parent:FindFirstChild("CreepService")
	local creepService = module and require(module)
	if not creepService or not creepService.SpawnGolem then
		return false, "Golems are unavailable"
	end
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > (ability.Range or 28) then
		offset = offset.Unit * (ability.Range or 28)
	end
	local point = CombatService.ClampToArena(Vector3.new(origin.X + offset.X, origin.Y, origin.Z + offset.Z))
	CombatService.BreakStealth(entity)
	Net.Effect("Cast", { Position = origin, Color = ability.Color })
	local ok, reason = creepService.SpawnGolem(entity, ability, point)
	if not ok then
		return false, reason
	end
	-- the landing slam
	Net.Effect("Explosion", { Position = point, Radius = ability.Radius or 9, Color = ability.Color })
	Net.Effect("Shockwave", { Position = point, Radius = ability.Radius or 9, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, point, ability.Radius or 9, true)) do
		if ability.Damage then
			CombatService.ApplyDamage(entity, victim, ability.Damage)
		end
		if victim.Alive and ability.Stun then
			CombatService.Stun(victim, ability.Stun, entity)
			Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Stun })
		end
	end
	return true
end

-- Attack speed item abilities -------------------------------------------------------
handlers.Frenzy = function(entity, ability, origin, _, _, now)
	entity.FrenzyUntil = now + ability.Duration
	entity.FrenzyAttackSpeed = ability.AttackSpeedBoost or 0
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.BladeFlurry = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.MeleeStrike(entity, origin, direction, ability.Range, ability.Arc, ability.Damage, true, true)
	return true
end

handlers.ArcaneSurge = function(entity, ability, origin)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, true)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
	end
	return true
end

handlers.Quickdraw = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	CombatService.FireProjectile({
		Owner = entity, Origin = origin + direction * 1.5, Direction = direction, Speed = ability.Speed,
		Range = ability.Range, Radius = 1.2, Damage = ability.Damage, Style = "PowerShot", Pierce = true,
	})
	return true
end

handlers.IronFrenzy = function(entity, ability, origin, _, _, now)
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	entity.FrenzyUntil = now + ability.Duration
	entity.FrenzyAttackSpeed = ability.AttackSpeedBoost or 0
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.BloodFury = function(entity, ability, origin, _, _, now)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Melee", { Origin = origin, Direction = entity.Root.CFrame.LookVector, Range = ability.Radius, Arc = 360, Color = ability.Color, Empowered = true })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, false)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage)
	end
	entity.FrenzyUntil = now + ability.Duration
	entity.FrenzyAttackSpeed = ability.AttackSpeedBoost or 0
	return true
end

-- Boot skills (right mouse) ------------------------------------------------------------
-- Every class has 5 boots: crowd control, attack speed, movement, damage and mobility.
-- They are built from the shared combat mechanics (damage, stun, slow, haste, stealth,
-- shields, dashes, pushes, frenzy, empowered attacks, reflect).

-- enemies (units) whose centre lies within `width` of the segment origin -> origin + direction * length
local function lineVictims(entity, origin, direction, length, width)
	local results = {}
	for _, candidate in pairs(CombatService.Entities) do
		if isUnitEnemy(entity, candidate) then
			local offset = Util.Flat(CombatService.GetPosition(candidate) - origin)
			local along = offset:Dot(direction)
			if along >= -candidate.Radius and along <= length + candidate.Radius then
				local closest = direction * math.clamp(along, 0, length)
				if (offset - closest).Magnitude <= width + candidate.Radius then
					table.insert(results, { Entity = candidate, Along = along })
				end
			end
		end
	end
	table.sort(results, function(a, b)
		return a.Along < b.Along
	end)
	return results
end

-- how far a straight shot travels from origin before it meets a wall
local function rayLength(origin, direction, range)
	local from = Vector3.new(origin.X, 3, origin.Z)
	local hit = workspace:Raycast(from, direction * range, CombatService.GetObstacleParams())
	return hit and Util.FlatDistance(from, hit.Position) or range
end

-- Unit-targeted boot skills: a visible, living enemy within range and line of sight
local function validUnitTarget(entity, ability, origin, targetId)
	local target = type(targetId) == "string" and CombatService.GetEntity(targetId) or nil
	if not isUnitEnemy(entity, target) then
		return nil, "Select a living enemy"
	end
	if CombatService.IsStealthed(target) and not CombatService.IsRevealedTo(target, entity.Team) then
		return nil, "Target is not visible"
	end
	local targetPosition = CombatService.GetPosition(target)
	if Util.FlatDistance(origin, targetPosition) > ability.Range + target.Radius then
		return nil, "Target out of range"
	end
	if not CombatService.HasLineOfSight(origin, targetPosition) then
		return nil, "No line of sight"
	end
	return target, targetPosition
end

local function frenzy(entity, ability, now)
	entity.FrenzyUntil = now + ability.Duration
	entity.FrenzyAttackSpeed = ability.AttackSpeedBoost or 0
end

local function empower(entity, ability, now)
	entity.NextAttackMultiplier = ability.Empower
	entity.NextAttackExpires = now + ability.Duration
	if entity.Model then
		entity.Model:SetAttribute("EmpoweredAttack", true)
	end
end

local function pointInRange(origin, aimPosition, range)
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	return Vector3.new(origin.X + offset.X, 0.2, origin.Z + offset.Z), offset
end

-- Reworked mythic skills ---------------------------------------------------------------------
-- Mage (all ranged): Glacial Prison (ground-target freeze), Arcane Barrage (point-and-click bolts)
handlers.GlacialPrison = function(entity, ability, origin, aimPosition)
	local center = pointInRange(origin, aimPosition, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.Delay, Color = ability.Color })
	task.delay(ability.Delay, function()
		if not CombatService.Active or not entity.Alive then
			return
		end
		Net.Effect("Explosion", { Position = center, Radius = ability.Radius, Color = ability.Color })
		for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
			CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
			if victim.Alive then
				CombatService.Stun(victim, ability.Stun, entity)
				Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Stun })
			end
		end
	end)
	return true
end

handlers.ArcaneBarrage = function(entity, ability, origin, _, targetId)
	local target, reason = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, reason
	end
	CombatService.BreakStealth(entity)
	for bolt = 1, ability.Bolts do
		task.delay((bolt - 1) * ability.Interval, function()
			if not CombatService.Active or not entity.Alive or not target.Alive then
				return
			end
			local from, to = CombatService.GetPosition(entity), CombatService.GetPosition(target)
			if Util.FlatDistance(from, to) > ability.Range + target.Radius + 6 then
				return -- the target ran out of range: the remaining bolts fizzle
			end
			Net.Effect("Lightning", { From = from, To = to, Color = ability.Color })
			CombatService.ApplyDamage(entity, target, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		end)
	end
	return true
end

-- Assassin: a fan of thrown knives (each knife stops at the first enemy it hits)
handlers.FanOfKnives = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local count = ability.Knives or 5
	for index = 1, count do
		local angle = math.rad(ability.Spread or 40) * ((index - 1) / math.max(1, count - 1) - 0.5)
		local knifeDirection = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(direction)
		CombatService.FireProjectile({
			Owner = entity, Origin = origin + knifeDirection * 1.2, Direction = knifeDirection, Speed = ability.Speed,
			Range = ability.Range, Radius = 1.0, Damage = ability.Damage, Style = "Knife",
		})
	end
	return true
end

-- Marksman: three quick arrows toward the cursor
handlers.RapidVolley = function(entity, ability, origin, aimPosition)
	CombatService.BreakStealth(entity)
	for arrow = 1, ability.Arrows or 3 do
		task.delay((arrow - 1) * (ability.Interval or 0.15), function()
			if not CombatService.Active or not entity.Alive or CombatService.IsStunned(entity) then
				return
			end
			local from = CombatService.GetPosition(entity)
			local direction = Util.FlatDirection(from, aimPosition, entity.Root.CFrame.LookVector)
			CombatService.FireProjectile({
				Owner = entity, Origin = from + direction * 1.5, Direction = direction, Speed = ability.Speed,
				Range = ability.Range, Radius = 1.1, Damage = ability.Damage, Style = "Arrow",
			})
		end)
	end
	return true
end

-- Fighter: war drums - attack speed + move speed for you and nearby allies, slow nearby enemies
handlers.DrumsOfWar = function(entity, ability, origin, _, _, now)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, ally in ipairs(CombatService.GetEntitiesInRadius(origin, ability.Radius, function(candidate)
		return candidate.Kind == "Hero" and candidate.Alive and candidate.Team == entity.Team
	end)) do
		-- keep a stronger frenzy the ally already has
		if (ally.FrenzyUntil or 0) <= now or (ally.FrenzyAttackSpeed or 0) <= ability.AttackSpeedBoost then
			ally.FrenzyUntil = now + ability.Duration
			ally.FrenzyAttackSpeed = ability.AttackSpeedBoost
		end
		CombatService.Haste(ally, ability.HasteBonus, ability.Duration)
		CombatService.PushHeroAttributes(ally)
	end
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.SlowRadius, true)) do
		CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
	end
	return true
end

-- Assassin: CC / attack speed / movement / mobility (damage = Assassin Boots' Point Strike)
handlers.CripplingStrike = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local cosHalfArc = math.cos(math.rad(ability.Arc / 2))
	CombatService.BreakStealth(entity)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Range, true)) do
		local position = CombatService.GetPosition(victim)
		local offset = Util.Flat(position - origin)
		if (offset.Magnitude <= victim.Radius + 1 or offset.Unit:Dot(direction) >= cosHalfArc) and CombatService.HasLineOfSight(origin, position) then
			CombatService.ApplyDamage(entity, victim, ability.Damage)
			if victim.Alive then
				CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
			end
		end
	end
	return true
end

handlers.BladeDance = function(entity, ability, origin, _, _, now)
	frenzy(entity, ability, now)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.Vanish = function(entity, ability, origin)
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	CombatService.SetStealth(entity, ability.Duration)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	return true
end

handlers.ShadeLeap = function(entity, ability, origin, _, targetId)
	local target, targetPosition = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, targetPosition
	end
	local toTarget = Util.Flat(targetPosition - origin)
	local forward = toTarget.Magnitude > 0.1 and toTarget.Unit or Util.Flat(entity.Root.CFrame.LookVector)
	local travel = toTarget + forward * (target.Radius + 2.5) -- land just behind the target
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	CombatService.Dash(entity, travel.Unit, travel.Magnitude, 0.1)
	return true
end

-- Mage: CC (push) / attack speed / movement / damage / mobility
handlers.GaleBurst = function(entity, ability, origin, aimPosition)
	local center, offset = pointInRange(origin, aimPosition, ability.Range)
	local fallback = offset.Magnitude > 0.1 and offset.Unit or Util.Flat(entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	Net.Effect("GalePush", { Position = center, Radius = ability.Radius, Duration = ability.Duration, Color = ability.Color })
	Net.Effect("Shockwave", { Position = center, Radius = ability.Radius, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		if victim.Alive then
			local away = Util.Flat(CombatService.GetPosition(victim) - center)
			CombatService.Dash(victim, away.Magnitude > 0.3 and away.Unit or fallback, ability.PushDistance, ability.Duration)
		end
	end
	return true
end

handlers.ArcaneTempo = function(entity, ability, origin, _, _, now)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, true)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
	end
	frenzy(entity, ability, now)
	return true
end

handlers.Tailwind = function(entity, ability, origin)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	for _, ally in ipairs(CombatService.GetEntitiesInRadius(origin, ability.Radius, function(candidate)
		return candidate.Kind == "Hero" and candidate.Team == entity.Team
	end)) do
		CombatService.Haste(ally, ability.HasteBonus, ability.Duration)
	end
	return true
end

handlers.SearingRay = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local length = rayLength(origin, direction, ability.Range)
	local finish = origin + direction * length
	CombatService.BreakStealth(entity)
	Net.Effect("Dash", { From = origin, To = finish, Color = ability.Color })
	Net.Effect("Lightning", { From = origin, To = finish, Color = ability.Color })
	Net.Effect("Explosion", { Position = finish, Radius = 2.5, Color = ability.Color })
	for _, hit in ipairs(lineVictims(entity, origin, direction, length, ability.Width)) do
		CombatService.ApplyDamage(entity, hit.Entity, ability.Damage, { IgnoreArmor = ability.TrueDamage })
	end
	return true
end

handlers.PhaseShift = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local distance = math.clamp(Util.FlatDistance(origin, aimPosition), 4, ability.Range)
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	CombatService.Dash(entity, direction, distance, 0.08)
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	return true
end

-- Marksman: CC / attack speed / movement / damage (mobility = Ranger Boots' Tumble)
handlers.PinningShot = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local length = rayLength(origin, direction, ability.Range)
	CombatService.BreakStealth(entity)
	local first = lineVictims(entity, origin, direction, length, ability.Width)[1]
	local victim = first and first.Entity
	local finish = victim and CombatService.GetPosition(victim) or (origin + direction * length)
	Net.Effect("PointStrike", { From = origin, Position = finish, Color = ability.Color })
	if victim then
		CombatService.ApplyDamage(entity, victim, ability.Damage)
		if victim.Alive then
			CombatService.Stun(victim, ability.Stun, entity)
			Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Stun })
		end
	end
	return true
end

handlers.DeadeyeRhythm = function(entity, ability, origin, _, _, now)
	frenzy(entity, ability, now)
	empower(entity, ability, now)
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.EvasiveStride = function(entity, ability, origin)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.RainOfArrows = function(entity, ability, origin, aimPosition)
	local center = pointInRange(origin, aimPosition, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.Delay, Color = ability.Color })
	local damage = ability.Damage
	task.delay(ability.Delay, function()
		if not CombatService.Active then
			return
		end
		Net.Effect("Explosion", { Position = center, Radius = ability.Radius, Color = ability.Color })
		for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
			CombatService.ApplyDamage(entity, victim, damage)
		end
	end)
	return true
end

-- Tank: CC (stun scaled with max health) / attack speed / movement / mobility (damage = Tank Boots)
handlers.EarthenShackles = function(entity, ability, origin)
	local duration = ItemDefinitions.GetScaledStun(ability, entity.MaxHealth)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Explosion", { Position = origin, Radius = ability.Radius * 0.6, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, true)) do
		CombatService.Stun(victim, duration, entity)
		Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = duration })
	end
	return true
end

handlers.ThornedRhythm = function(entity, ability, origin, _, _, now)
	frenzy(entity, ability, now)
	entity.ReflectUntil = now + ability.Duration
	entity.ReflectPercent = ability.ReflectPercent
	if entity.Model then
		entity.Model:SetAttribute("ThornsUntil", entity.ReflectUntil)
	end
	Net.Effect("SpikedScale", { EntityId = entity.Id, Position = origin, Duration = ability.Duration, Color = ability.Color })
	return true
end

handlers.UnstoppableMarch = function(entity, ability, origin)
	CombatService.SetUnstoppable(entity, ability.Duration)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	Net.Effect("Shockwave", { Position = origin, Radius = 6, Color = ability.Color })
	return true
end

handlers.ShoulderCharge = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local finish = CombatService.Dash(entity, direction, ability.Range, 0.25) or origin
	local length = Util.FlatDistance(origin, finish)
	local side = Vector3.new(-direction.Z, 0, direction.X)
	for _, hit in ipairs(lineVictims(entity, origin, direction, length, ability.Width)) do
		local victim = hit.Entity
		CombatService.ApplyDamage(entity, victim, ability.Damage)
		if victim.Alive then
			local offset = Util.Flat(CombatService.GetPosition(victim) - origin)
			CombatService.Dash(victim, offset:Dot(side) >= 0 and side or -side, ability.KnockDistance, 0.25)
		end
	end
	Net.Effect("Shockwave", { Position = finish, Radius = 4, Color = ability.Color })
	return true
end

-- Fighter: attack speed / movement / damage / mobility (CC = Fighter Boots' Heavy Kick)
handlers.BattleTrance = function(entity, ability, origin, _, _, now)
	frenzy(entity, ability, now)
	CombatService.Heal(entity, ability.Heal or 0, true)
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	return true
end

handlers.Warpath = function(entity, ability, origin, _, _, now)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	empower(entity, ability, now)
	Net.Effect("Shockwave", { Position = origin, Radius = 6, Color = ability.Color })
	return true
end

handlers.SkullSplitter = function(entity, ability, origin, _, targetId)
	local target, targetPosition = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, targetPosition
	end
	CombatService.BreakStealth(entity)
	local toTarget = Util.Flat(targetPosition - origin)
	local gap = toTarget.Magnitude - (target.Radius + 2)
	if gap > 0.5 then
		CombatService.Dash(entity, toTarget.Unit, gap, 0.2)
	end
	local damage = ability.Damage
	task.delay(0.2, function()
		if not CombatService.Active or not entity.Alive or not target.Alive then
			return
		end
		local execute = target.Health / math.max(1, target.MaxHealth) < ability.ExecuteThreshold
		Net.Effect("HeavyKick", { Origin = CombatService.GetPosition(entity), Position = CombatService.GetPosition(target), Color = ability.Color })
		CombatService.ApplyDamage(entity, target, execute and damage * (1 + ability.ExecuteBonus) or damage, { Crit = execute })
	end)
	return true
end

handlers.LeapingBound = function(entity, ability, origin, aimPosition)
	local offset = Util.Flat(aimPosition - origin)
	local direction = offset.Magnitude > 0.1 and offset.Unit or Util.Flat(entity.Root.CFrame.LookVector)
	CombatService.Dash(entity, direction, ability.Range, 0.3)
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration + 0.3)
	return true
end

-- Class active items, set 2 ------------------------------------------------------------------
-- enemies in a cone in front of the caster (with line of sight)
local function coneVictims(entity, origin, direction, range, arc)
	local cosHalfArc = math.cos(math.rad(arc / 2))
	local results = {}
	for _, victim in ipairs(enemiesInRadius(entity, origin, range, true)) do
		local position = CombatService.GetPosition(victim)
		local offset = Util.Flat(position - origin)
		if (offset.Magnitude <= victim.Radius + 1 or offset.Unit:Dot(direction) >= cosHalfArc) and CombatService.HasLineOfSight(origin, position) then
			table.insert(results, victim)
		end
	end
	return results
end

local function stunWithEffect(entity, victim, duration)
	if victim.Alive and duration and duration > 0 then
		CombatService.Stun(victim, duration, entity)
		Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = duration })
	end
end

local function markVulnerable(victim, amount, duration, now)
	victim.VulnerableUntil = now + duration
	victim.VulnerableAmount = math.max(amount, (victim.VulnerableUntil or 0) > now and victim.VulnerableAmount or 0)
	if victim.Model then
		victim.Model:SetAttribute("VulnerableUntil", victim.VulnerableUntil)
	end
end

-- jump from enemy to enemy (Ricochet Blade, Chain Lightning)
local function bounceChain(entity, ability, first, jumps, jumpRange, falloff, style)
	local hit = { [first] = true }
	local current, damage = first, ability.Damage
	local from = CombatService.GetPosition(entity)
	for jump = 0, jumps do
		local target = current
		task.delay(jump * 0.12, function()
			if not CombatService.Active or not target.Alive then
				return
			end
			local to = CombatService.GetPosition(target)
			Net.Effect("Lightning", { From = from, To = to, Color = ability.Color })
			if style == "Blade" then
				Net.Effect("PointStrike", { From = from, Position = to, Color = ability.Color })
			end
			CombatService.ApplyDamage(entity, target, damage, { IgnoreArmor = ability.TrueDamage })
			from = to
		end)
		damage *= 1 - falloff
		local nextTarget = CombatService.FindNearestEnemy(entity, CombatService.GetPosition(current), jumpRange, function(candidate)
			return not hit[candidate] and isUnitEnemy(entity, candidate) and not CombatService.IsStealthed(candidate)
		end)
		if not nextTarget or jump == jumps then
			break
		end
		hit[nextTarget] = true
		current = nextTarget
	end
end

-- Assassin ----------------------------------------------------------------------------------
handlers.Assassinate = function(entity, ability, origin, _, targetId)
	local target, targetPosition = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, targetPosition
	end
	local toTarget = Util.Flat(targetPosition - origin)
	local forward = toTarget.Magnitude > 0.1 and toTarget.Unit or Util.Flat(entity.Root.CFrame.LookVector)
	local travel = toTarget + forward * (target.Radius + 2.5)
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	CombatService.Dash(entity, travel.Unit, travel.Magnitude, 0.1)
	local damage = ability.Damage
	task.delay(0.12, function()
		if not CombatService.Active or not entity.Alive or not target.Alive then
			return
		end
		local execute = target.Health / math.max(1, target.MaxHealth) < ability.ExecuteThreshold
		Net.Effect("PointStrike", { From = CombatService.GetPosition(entity), Position = CombatService.GetPosition(target), Color = ability.Color })
		CombatService.ApplyDamage(entity, target, execute and damage * (1 + ability.ExecuteBonus) or damage, { Crit = true })
		if entity.Alive then
			CombatService.SetStealth(entity, ability.StealthAfter)
		end
	end)
	return true
end

handlers.VenomToxin = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local poison = ability.Damage * ability.PoisonPercent
	CombatService.FireProjectile({
		Owner = entity, Origin = origin + direction * 1.2, Direction = direction, Speed = ability.Speed,
		Range = ability.Range, Radius = 1.1, Damage = ability.Damage, Style = "Knife",
		OnEnd = function(_, victim)
			if not victim or not victim.Alive then
				return
			end
			CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
			for tick = 1, ability.PoisonTicks do
				task.delay(tick, function()
					if CombatService.Active and victim.Alive then
						Net.Effect("Shockwave", { Position = CombatService.GetPosition(victim), Radius = 1.5, Color = ability.Color })
						CombatService.ApplyDamage(entity, victim, poison, { IgnoreArmor = true, NoChain = true })
					end
				end)
			end
		end,
	})
	return true
end

handlers.DeathMark = function(entity, ability, origin, _, targetId, now)
	local target, targetPosition = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, targetPosition
	end
	CombatService.BreakStealth(entity)
	Net.Effect("PointStrike", { From = origin, Position = targetPosition, Color = ability.Color })
	Net.Effect("Telegraph", { Position = targetPosition, Radius = 2.5, Duration = ability.Duration, Color = ability.Color })
	CombatService.ApplyDamage(entity, target, ability.Damage)
	if target.Alive then
		markVulnerable(target, ability.Vulnerable, ability.Duration, now)
	end
	return true
end

handlers.RicochetBlade = function(entity, ability, origin, _, targetId)
	local target, reason = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, reason
	end
	CombatService.BreakStealth(entity)
	bounceChain(entity, ability, target, ability.Bounces, ability.BounceRange, ability.BounceFalloff, "Blade")
	return true
end

handlers.Evasion = function(entity, ability, origin, _, _, now)
	entity.EvadeUntil = now + ability.Duration
	CombatService.Haste(entity, ability.HasteBonus, ability.Duration)
	if entity.Model then
		entity.Model:SetAttribute("EvadeUntil", entity.EvadeUntil)
	end
	Net.Effect("Stealth", { Position = origin, Color = ability.Color })
	Net.Effect("Shockwave", { Position = origin, Radius = 4, Color = ability.Color })
	return true
end

-- Mage --------------------------------------------------------------------------------------
handlers.ChainLightning = function(entity, ability, origin, _, targetId)
	local target, reason = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, reason
	end
	CombatService.BreakStealth(entity)
	bounceChain(entity, ability, target, ability.Chains, ability.ChainRange, ability.ChainFalloff, "Lightning")
	return true
end

handlers.Meteor = function(entity, ability, origin, aimPosition)
	local center = pointInRange(origin, aimPosition, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.Delay, Color = ability.Color })
	Net.Effect("Meteor", { Position = center, Delay = ability.Delay, Color = ability.Color })
	task.delay(ability.Delay, function()
		if not CombatService.Active then
			return
		end
		Net.Effect("Explosion", { Position = center, Radius = ability.Radius, Color = ability.Color })
		Net.Effect("Shockwave", { Position = center, Radius = ability.Radius + 2, Color = ability.Color })
		for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
			CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
			stunWithEffect(entity, victim, ability.Stun)
		end
	end)
	return true
end

handlers.VoidRift = function(entity, ability, origin, aimPosition)
	local center = pointInRange(origin, aimPosition, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.Duration, Color = ability.Color })
	local ticks = math.floor(ability.Duration / ability.TickInterval + 0.5)
	for tick = 1, ticks do
		task.delay(tick * ability.TickInterval, function()
			if not CombatService.Active then
				return
			end
			Net.Effect("Shockwave", { Position = center, Radius = ability.Radius, Color = ability.Color })
			for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
				CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage, NoChain = true })
				if victim.Alive then
					CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
				end
			end
		end)
	end
	return true
end

handlers.ManaAegis = function(entity, ability, origin)
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	Net.Effect("Shockwave", { Position = origin, Radius = 4, Color = ability.Color })
	task.delay(ability.Duration, function()
		if not CombatService.Active or not entity.Alive then
			return
		end
		local position = CombatService.GetPosition(entity)
		Net.Effect("Explosion", { Position = position, Radius = ability.ExplodeRadius, Color = ability.Color })
		for _, victim in ipairs(enemiesInRadius(entity, position, ability.ExplodeRadius, true)) do
			CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		end
	end)
	return true
end

handlers.TimeWarp = function(entity, ability, origin, aimPosition)
	local center = pointInRange(origin, aimPosition, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.SlowDuration, Color = ability.Color })
	Net.Effect("Shockwave", { Position = center, Radius = ability.Radius, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage, { IgnoreArmor = ability.TrueDamage })
		if victim.Alive then
			CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
		end
	end
	CombatService.Haste(entity, ability.HasteBonus, ability.HasteDuration)
	return true
end

-- Marksman ----------------------------------------------------------------------------------
handlers.Snipe = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	local aimLength = rayLength(origin, direction, ability.Range)
	Net.Effect("Telegraph", { Position = origin + direction * 2, Radius = 1.5, Duration = ability.Delay, Color = ability.Color })
	Net.Effect("Dash", { From = origin, To = origin + direction * aimLength, Color = ability.Color })
	local damage = ability.Damage
	task.delay(ability.Delay, function()
		if not CombatService.Active or not entity.Alive or CombatService.IsStunned(entity) then
			return -- interrupted
		end
		local from = CombatService.GetPosition(entity)
		local length = rayLength(from, direction, ability.Range)
		local first = lineVictims(entity, from, direction, length, ability.Width)[1]
		local victim = first and first.Entity
		local finish = victim and CombatService.GetPosition(victim) or (from + direction * length)
		Net.Effect("Lightning", { From = from, To = finish, Color = ability.Color })
		Net.Effect("PointStrike", { From = from, Position = finish, Color = ability.Color })
		if victim then
			CombatService.ApplyDamage(entity, victim, damage, { Crit = true })
		end
	end)
	return true
end

local trapFolder = nil
handlers.BearTrap = function(entity, ability, origin, aimPosition, _, now)
	local center = pointInRange(origin, aimPosition, ability.Range)
	entity.Traps = entity.Traps or {}
	-- only MaxTraps at once: the oldest one snaps shut uselessly
	while #entity.Traps >= ability.MaxTraps do
		local oldest = table.remove(entity.Traps, 1)
		oldest.Done = true
		if oldest.Part then
			oldest.Part:Destroy()
		end
	end
	if not trapFolder or not trapFolder.Parent then
		trapFolder = Instance.new("Folder")
		trapFolder.Name = "Traps"
		trapFolder.Parent = workspace:FindFirstChild("RuinfallMap") or workspace
	end
	local part = Instance.new("Part")
	part.Name = "BearTrap"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, ability.Radius * 1.3, ability.Radius * 1.3)
	part.CFrame = CFrame.new(center.X, center.Y + 0.1, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(70, 64, 58)
	part.Transparency = 0.45 -- hard to spot
	part.Parent = trapFolder
	local trap = { Part = part, Done = false }
	table.insert(entity.Traps, trap)
	Net.Effect("Shockwave", { Position = center, Radius = 2, Color = ability.Color })
	local damage, expires = ability.Damage, now + ability.TrapDuration
	task.spawn(function()
		while not trap.Done and CombatService.Active and Util.Now() < expires do
			task.wait(0.15)
			if trap.Done then
				break
			end
			local victim = enemiesInRadius(entity, center, ability.Radius, true)[1]
			if victim then
				Net.Effect("Explosion", { Position = center, Radius = ability.Radius, Color = ability.Color })
				CombatService.ApplyDamage(entity, victim, damage)
				stunWithEffect(entity, victim, ability.Stun)
				break
			end
		end
		trap.Done = true
		if part.Parent then
			part:Destroy()
		end
		local index = table.find(entity.Traps, trap)
		if index then
			table.remove(entity.Traps, index)
		end
	end)
	return true
end

handlers.HuntersMark = function(entity, ability, origin, _, targetId, now)
	local target, targetPosition = validUnitTarget(entity, ability, origin, targetId)
	if not target then
		return false, targetPosition
	end
	Net.Effect("PointStrike", { From = origin, Position = targetPosition, Color = ability.Color })
	Net.Effect("Telegraph", { Position = targetPosition, Radius = 2.5, Duration = ability.Duration, Color = ability.Color })
	markVulnerable(target, ability.Vulnerable, ability.Duration, now)
	frenzy(entity, ability, now)
	return true
end

handlers.Buckshot = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true })
	for index = -2, 2 do
		local spread = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(index * ability.Arc / 5)):VectorToWorldSpace(direction)
		Net.Effect("Dash", { From = origin, To = origin + spread * ability.Range, Color = ability.Color })
	end
	for _, victim in ipairs(coneVictims(entity, origin, direction, ability.Range, ability.Arc)) do
		CombatService.ApplyDamage(entity, victim, ability.Damage)
		if victim.Alive then
			local away = Util.Flat(CombatService.GetPosition(victim) - origin)
			CombatService.Dash(victim, away.Magnitude > 0.2 and away.Unit or direction, ability.KnockDistance, 0.2)
		end
	end
	CombatService.Dash(entity, -direction, ability.Recoil, 0.2)
	return true
end

handlers.ArrowStorm = function(entity, ability, origin)
	local shots = math.floor(ability.Duration / ability.Interval)
	Net.Effect("Shockwave", { Position = origin, Radius = 5, Color = ability.Color })
	for shot = 1, shots do
		task.delay((shot - 1) * ability.Interval, function()
			if not CombatService.Active or not entity.Alive or CombatService.IsStunned(entity) then
				return
			end
			local from = CombatService.GetPosition(entity)
			local target = CombatService.FindNearestEnemy(entity, from, ability.Range, function(candidate)
				return isUnitEnemy(entity, candidate) and not CombatService.IsStealthed(candidate)
			end)
			if not target then
				return
			end
			local direction = Util.FlatDirection(from, CombatService.GetPosition(target), entity.Root.CFrame.LookVector)
			CombatService.FireProjectile({
				Owner = entity, Origin = from + direction * 1.5, Direction = direction, Speed = 110,
				Range = ability.Range + 4, Radius = 1.1, Damage = ability.Damage, Style = "Arrow",
			})
		end)
	end
	return true
end

-- Tank --------------------------------------------------------------------------------------
handlers.ChainHook = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local length = rayLength(origin, direction, ability.Range)
	CombatService.BreakStealth(entity)
	local first = lineVictims(entity, origin, direction, length, ability.Width)[1]
	local victim = first and first.Entity
	local finish = victim and CombatService.GetPosition(victim) or (origin + direction * length)
	Net.Effect("Lightning", { From = origin, To = finish, Color = ability.Color })
	Net.Effect("Dash", { From = origin, To = finish, Color = ability.Color })
	if victim then
		CombatService.ApplyDamage(entity, victim, ability.Damage)
		if victim.Alive then
			local toCaster = Util.Flat(origin - CombatService.GetPosition(victim))
			local pull = toCaster.Magnitude - (victim.Radius + 3)
			if pull > 0.5 then
				CombatService.Dash(victim, toCaster.Unit, pull, 0.25)
			end
			stunWithEffect(entity, victim, ability.Stun)
		end
	end
	return true
end

handlers.Challenge = function(entity, ability, origin)
	CombatService.BreakStealth(entity)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Explosion", { Position = origin, Radius = 3, Color = ability.Color })
	for _, victim in ipairs(enemiesInRadius(entity, origin, ability.Radius, true)) do
		CombatService.Taunt(victim, entity, ability.Taunt)
		Net.Effect("Stun", { Position = CombatService.GetPosition(victim), Duration = ability.Taunt })
	end
	CombatService.AddShield(entity, ability.Shield, ability.Duration)
	return true
end

handlers.StoneForm = function(entity, ability, origin, _, _, now)
	entity.DamageReductionUntil = now + ability.Duration
	entity.DamageReductionAmount = ability.DamageReduction
	if entity.Model then
		entity.Model:SetAttribute("StoneFormUntil", entity.DamageReductionUntil)
	end
	entity.SlowUntil, entity.SlowAmount = now + ability.Duration, ability.SelfSlow -- self-inflicted, ignores tenacity
	CombatService.RecomputeSpeed(entity)
	Net.Effect("SpikedScale", { EntityId = entity.Id, Position = origin, Duration = ability.Duration, Color = ability.Color })
	Net.Effect("Shockwave", { Position = origin, Radius = 4, Color = ability.Color })
	return true
end

handlers.Fissure = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local length = rayLength(origin, direction, ability.Range)
	CombatService.BreakStealth(entity)
	Net.Effect("Dash", { From = origin, To = origin + direction * length, Color = ability.Color })
	for step = 1, math.max(1, math.floor(length / 5)) do
		local point = origin + direction * (step * 5)
		task.delay(step * 0.04, function()
			Net.Effect("Explosion", { Position = point, Radius = ability.Width, Color = ability.Color })
		end)
	end
	for _, hit in ipairs(lineVictims(entity, origin, direction, length, ability.Width)) do
		CombatService.ApplyDamage(entity, hit.Entity, ability.Damage)
		stunWithEffect(entity, hit.Entity, ability.Stun)
	end
	return true
end

handlers.Sanctuary = function(entity, ability, origin)
	Net.Effect("Shockwave", { Position = origin, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Telegraph", { Position = origin, Radius = ability.Radius, Duration = 0.8, Color = ability.Color })
	for _, ally in ipairs(CombatService.GetEntitiesInRadius(origin, ability.Radius, function(candidate)
		return candidate.Kind == "Hero" and candidate.Alive and candidate.Team == entity.Team
	end)) do
		CombatService.Heal(ally, ability.Heal or 0, true)
		CombatService.AddShield(ally, ability.Shield, ability.Duration)
	end
	return true
end

-- Fighter -----------------------------------------------------------------------------------
handlers.CrimsonCleave = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	Net.Effect("Melee", { Origin = origin, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true, EntityId = entity.Id })
	local dealt = 0
	for _, victim in ipairs(coneVictims(entity, origin, direction, ability.Range, ability.Arc)) do
		dealt += CombatService.ApplyDamage(entity, victim, ability.Damage) or 0
	end
	if dealt > 0 then
		CombatService.Heal(entity, dealt * ability.LifestealPercent, true)
	end
	return true
end

handlers.RendingCharge = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	local length = rayLength(origin, direction, ability.Range)
	CombatService.BreakStealth(entity)
	local first = lineVictims(entity, origin, direction, length, ability.Width)[1]
	local victim = first and first.Entity
	local travel = victim and math.max(0, first.Along - (victim.Radius + 2)) or length
	CombatService.Dash(entity, direction, travel, 0.22)
	local damage = ability.Damage
	if victim then
		task.delay(0.22, function()
			if not CombatService.Active or not entity.Alive or not victim.Alive then
				return
			end
			Net.Effect("HeavyKick", { Origin = CombatService.GetPosition(entity), Position = CombatService.GetPosition(victim), Color = ability.Color })
			CombatService.ApplyDamage(entity, victim, damage)
			if victim.Alive then
				CombatService.Slow(victim, ability.Slow, ability.SlowDuration, entity)
			end
		end)
	end
	return true
end

handlers.BattleStandard = function(entity, ability, origin)
	local center = Vector3.new(origin.X, origin.Y, origin.Z)
	local banner = Instance.new("Part")
	banner.Name = "BattleStandard"
	banner.Anchored = true
	banner.CanCollide = false
	banner.CanQuery = false
	banner.CanTouch = false
	banner.Size = Vector3.new(0.35, 9, 0.35)
	banner.Material = Enum.Material.Wood
	banner.Color = Color3.fromRGB(90, 60, 35)
	banner.CFrame = CFrame.new(center.X, center.Y + 1.5, center.Z)
	local cloth = Instance.new("Part")
	cloth.Name = "Cloth"
	cloth.Anchored = true
	cloth.CanCollide = false
	cloth.CanQuery = false
	cloth.CanTouch = false
	cloth.Size = Vector3.new(2.6, 3.2, 0.12)
	cloth.Material = Enum.Material.Fabric
	cloth.Color = entity.Team and Constants.GetTeamColor(entity.Team) or ability.Color
	cloth.CFrame = banner.CFrame * CFrame.new(1.4, 2.6, 0)
	cloth.Parent = banner
	banner.Parent = workspace:FindFirstChild("RuinfallMap") or workspace
	Net.Effect("Shockwave", { Position = center, Radius = ability.Radius, Color = ability.Color })
	Net.Effect("Telegraph", { Position = center, Radius = ability.Radius, Duration = ability.Duration, Color = ability.Color })
	local ticks = math.floor(ability.Duration / 0.5)
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(0.5)
			if not CombatService.Active then
				break
			end
			for _, ally in ipairs(CombatService.GetEntitiesInRadius(center, ability.Radius, function(candidate)
				return candidate.Kind == "Hero" and candidate.Alive and candidate.Team == entity.Team
			end)) do
				CombatService.Heal(ally, ally.MaxHealth * ability.HealPerSecond * 0.5, false)
			end
			for _, victim in ipairs(enemiesInRadius(entity, center, ability.Radius, true)) do
				CombatService.Slow(victim, ability.Slow, 0.7, entity)
			end
		end
		banner:Destroy()
	end)
	return true
end

handlers.Guillotine = function(entity, ability, origin, aimPosition)
	local direction = Util.FlatDirection(origin, aimPosition, entity.Root.CFrame.LookVector)
	CombatService.BreakStealth(entity)
	Net.Effect("Telegraph", { Position = origin + direction * (ability.Range * 0.55), Radius = ability.Range * 0.45, Duration = ability.Delay, Color = ability.Color })
	local damage = ability.Damage
	task.delay(ability.Delay, function()
		if not CombatService.Active or not entity.Alive or CombatService.IsStunned(entity) then
			return
		end
		local from = CombatService.GetPosition(entity)
		Net.Effect("Melee", { Origin = from, Direction = direction, Range = ability.Range, Arc = ability.Arc, Color = ability.Color, Empowered = true, EntityId = entity.Id })
		Net.Effect("HeavyKick", { Origin = from, Position = from + direction * (ability.Range * 0.6), Color = ability.Color })
		for _, victim in ipairs(coneVictims(entity, from, direction, ability.Range, ability.Arc)) do
			local missing = 1 - victim.Health / math.max(1, victim.MaxHealth)
			CombatService.ApplyDamage(entity, victim, damage * (1 + missing * ability.MissingHealthBonus), { Crit = missing > 0.5 })
		end
	end)
	return true
end

handlers.LastStand = function(entity, ability, origin, _, _, now)
	entity.UndyingUntil = now + ability.Duration
	CombatService.ClearStun(entity)
	CombatService.RecomputeSpeed(entity)
	if entity.Model then
		entity.Model:SetAttribute("UndyingUntil", entity.UndyingUntil)
	end
	Net.Effect("SpikedScale", { EntityId = entity.Id, Position = origin, Duration = ability.Duration, Color = ability.Color })
	Net.Effect("Shockwave", { Position = origin, Radius = 6, Color = ability.Color })
	local heal = ability.Heal or 0
	task.delay(ability.Duration, function()
		if CombatService.Active and entity.Alive then
			CombatService.Heal(entity, heal, true)
		end
	end)
	return true
end

-- slot: 1 (E), 2 (R) or 3 (SPACE), or BOOT_SLOT. targetId only matters for Unit-targeted abilities.
function ItemService.UseSlot(entity, slot, aimPosition, targetId)
	if not CombatService.Active or not entity or not entity.Alive or entity.Kind ~= "Hero" or not entity.Participant then
		return false, "Unavailable"
	end
	if not isValidSlot(slot) and slot ~= BOOT_SLOT then
		return false, "Invalid slot"
	end
	local participant = entity.Participant
	local mythics = mythicsOf(participant) -- also guarantees participant.ItemReadyAt
	local itemId = slot == BOOT_SLOT and participant.Boots or mythics[slot]
	local ability = ItemDefinitions.GetItemAbility(itemId)
	if not ability then
		return false, slot == BOOT_SLOT and "Boot slot is empty - buy boots in the shop" or ("Mythic slot " .. slot .. " is empty")
	end
	local handler = handlers[ability.Id]
	if not handler then
		return false, "Ability not implemented"
	end
	local now = Util.Now()
	if CombatService.IsStunned(entity) and not ability.UsableWhileStunned then
		return false, "Stunned"
	end
	local readyAt = participant.ItemReadyAt[itemId] or 0
	if now < readyAt - COOLDOWN_GRACE then
		return false, "Cooldown"
	end
	-- E / R item skills cost mana (boots only when their skill sets ManaCost - all Mage boots);
	-- spent only when the skill succeeds
	local manaCost = ItemDefinitions.GetSlotManaCost(ability, slot == BOOT_SLOT)
	if manaCost > 0 and (entity.Mana or 0) < manaCost then
		return false, "Not enough mana"
	end
	local origin = CombatService.GetCastOrigin(entity) -- lag lead while running
	participant.ItemReadyAt[itemId] = now + CombatService.GetCooldown(entity, ability.Cooldown) -- set first: rejects re-entrant spam
	-- handlers get a copy whose Damage / Shield are numbers scaled from the caster's current stats
	local resolved = AbilityScaling.Resolve(ability, AbilityScaling.StatsFromEntity(entity))
	local ok, reason = handler(entity, resolved, origin, aimPosition, targetId, now)
	if ok == false then
		participant.ItemReadyAt[itemId] = readyAt
		return false, reason
	end
	if manaCost > 0 then
		CombatService.SpendMana(entity, manaCost)
	end
	if entity.Model then
		entity.Model:SetAttribute("ItemCastAbility", ability.Id)
		entity.Model:SetAttribute("ItemCastAt", now)
	end
	MatchManager.Broadcast()
	return true
end

-- Creep war band purchase is delegated to CreepService (loaded lazily when present)
local function getCreepService()
	local module = script.Parent:FindFirstChild("CreepService")
	return module and require(module) or nil
end

function ItemService.HandleRequest(player, action, arg1, arg2)
	if type(action) ~= "string" then
		return false
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_INTERVAL then
		return false
	end
	lastRequest[player] = now
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or participant.Spectator then
		return false
	end
	if action == "Buy" then
		if type(arg1) ~= "string" or (arg2 ~= nil and type(arg2) ~= "number") then
			return false
		end
		return ItemService.Buy(player, participant, arg1, arg2)
	elseif action == "Sell" then
		return ItemService.Sell(player, participant, arg1)
	elseif action == "Swap" then
		return ItemService.Swap(player, participant, arg1, arg2)
	elseif action == "UpgradeMinions" or action == "BuyCreeps" then
		-- team-wide minion upgrade (minion waves themselves spawn automatically)
		local creepService = getCreepService()
		if not creepService then
			return reject(player, "Minion upgrades are not available yet")
		end
		return creepService.PurchaseUpgrade(player, participant)
	end
	return false
end

-- Public API ----------------------------------------------------------------------------
function ItemService.Init()
	Net.Get("ItemRequest").OnServerEvent:Connect(function(player, action, arg1, arg2)
		local ok, err = pcall(ItemService.HandleRequest, player, action, arg1, arg2)
		if not ok then
			warn("[Ruinfall] ItemRequest error:", err)
		end
	end)
end

function ItemService.GetSlots(participant)
	local mythics = mythicsOf(participant)
	local passives = passivesOf(participant)
	return mythics[1], mythics[2], mythics[3], participant.Boots, passives[1], passives[2], passives[3]
end

return ItemService
