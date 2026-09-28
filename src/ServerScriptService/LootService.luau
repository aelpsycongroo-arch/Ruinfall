-- LootService: things lying on the ground that heroes pick up.
--   * Health potions (BOTH modes): natural camp monsters may drop one when they die.
--     Walking over a potion stores it (up to Loot.MAX_POTIONS); drink one with H (or the
--     mobile potion button) to heal Loot.POTION_HEAL_PERCENT of max health over a few seconds.
--   * Items and class skills (Royale only): dropped by ruins and by players who throw away
--     gear they no longer want. Players pick them up with the F prompt; bots walk over them.
-- Server-authoritative: clients only send "UsePotion" / "Drop <slot>" intents.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local Net = require(script.Parent:WaitForChild("Net"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local ItemService = require(script.Parent:WaitForChild("ItemService"))

-- Constants
local LOOT = Constants.Loot
local TICK = 0.25
local POTION_COLOR = Color3.fromRGB(255, 70, 90)
local SKILL_COLOR = Color3.fromRGB(190, 140, 255)
local ITEM_COLORS = { Mythic = Color3.fromRGB(255, 190, 80), Boots = Color3.fromRGB(120, 200, 255), Passive = Color3.fromRGB(200, 130, 255) }
local BOOT_SLOT = ItemDefinitions.BOOT_SLOT
local PASSIVE_BASE = ItemDefinitions.PASSIVE_SLOT_BASE

-- State
local LootService = {}
LootService.Loot = {} -- [id] = { Id, Kind = "Potion"|"Item"|"Skill", Key, Position, Model, ExpiresAt }
LootService.AllowGear = false -- Royale turns item / skill loot on
local folder = nil
local nextId = 0
local runId = 0
local healing = {} -- [entity] = { PerSecond, Until }
local potionReadyAt = setmetatable({}, { __mode = "k" }) -- [participant] = time
local initialized = false

-- Helpers -------------------------------------------------------------------------------
local function describe(kind, key)
	if kind == "Potion" then
		return "Health Potion", POTION_COLOR, "Heal " .. math.floor(LOOT.POTION_HEAL_PERCENT * 100) .. "% (H)"
	elseif kind == "Skill" then
		local classDef = ClassDefinitions.Get(key)
		local ability = classDef and classDef.Ability
		return (ability and ability.Name or "Skill") .. " (Q)", classDef and classDef.Color or SKILL_COLOR, "Class skill scroll"
	end
	local item = ItemDefinitions.GetItem(key)
	local slot = item and (item.SlotType == "Boots" and "Boots (Right Mouse)" or item.SlotType == "Passive" and "Passive" or "Mythic (E / R)") or ""
	return item and item.Name or "?", item and (ITEM_COLORS[item.SlotType] or ITEM_COLORS.Mythic) or ITEM_COLORS.Mythic, slot
end

local function buildModel(loot)
	local name, color, sub = describe(loot.Kind, loot.Key)
	local ground = Vector3.new(loot.Position.X, 0, loot.Position.Z)
	local model = Instance.new("Model")
	model.Name = "Loot_" .. loot.Id
	local potion = loot.Kind == "Potion"
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.Neon
	core.Color = color
	if potion then
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(1.4, 1.4, 1.4)
		core.CFrame = CFrame.new(ground + Vector3.new(0, 1.5, 0))
		local neck = Instance.new("Part")
		neck.Name = "Neck"
		neck.Anchored, neck.CanCollide, neck.CanQuery, neck.CanTouch = true, false, false, false
		neck.Size = Vector3.new(0.45, 0.6, 0.45)
		neck.Color = Color3.fromRGB(150, 110, 70)
		neck.Material = Enum.Material.Wood
		neck.CFrame = CFrame.new(ground + Vector3.new(0, 2.4, 0))
		neck.Parent = model
	else
		core.Size = Vector3.new(1.3, 1.3, 1.3)
		core.CFrame = CFrame.new(ground + Vector3.new(0, 2.2, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		-- light beam so gear is visible from far away
		local beam = Instance.new("Part")
		beam.Name = "Beam"
		beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(14, 0.5, 0.5)
		beam.CFrame = CFrame.new(ground + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.55
		beam.Parent = model
	end
	core.Parent = model
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 3.2, 3.2)
	ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.4
	ring.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = potion and 8 or 12
	light.Brightness = 1.3
	light.Parent = core
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(170, 44)
	billboard.StudsOffset = Vector3.new(0, potion and 2.2 or 2.4, 0)
	billboard.MaxDistance = potion and 45 or 90
	billboard.LightInfluence = 0
	local icon = nil
	if loot.Kind == "Item" then
		local item = ItemDefinitions.GetItem(loot.Key)
		icon = item and item.Icon ~= "" and item.Icon or nil
	elseif loot.Kind == "Skill" then
		local classDef = ClassDefinitions.Get(loot.Key)
		icon = classDef and classDef.IconImage or nil
	end
	if icon then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = icon
		image.Size = UDim2.fromOffset(40, 40)
		image.Parent = billboard
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(icon and 44 or 0, 0)
	label.Size = UDim2.new(1, icon and -44 or 0, 0, 24)
	label.Font = Enum.Font.Fondamento
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = name
	label.Parent = billboard
	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.fromOffset(icon and 44 or 0, 24)
	subLabel.Size = UDim2.new(1, icon and -44 or 0, 0, 16)
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(230, 220, 200)
	subLabel.TextStrokeTransparency = 0.4
	subLabel.Text = sub
	subLabel.Parent = billboard
	billboard.Parent = core
	if not potion then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PickupPrompt"
		prompt.ActionText = "Take"
		prompt.ObjectText = name
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = LOOT.PICKUP_RADIUS + 2
		prompt.RequiresLineOfSight = false
		prompt.Parent = core
		prompt.Triggered:Connect(function(player)
			local participant = PlayerService.GetParticipantByPlayer(player)
			if participant then
				LootService.TryPickup(participant, loot.Id)
			end
		end)
	end
	model.PrimaryPart = core
	model.Parent = folder
	return model
end

local function removeLoot(id)
	local loot = LootService.Loot[id]
	if not loot then
		return
	end
	LootService.Loot[id] = nil
	if loot.Model then
		loot.Model:Destroy()
	end
end

-- Public API ------------------------------------------------------------------------------
function LootService.Spawn(kind, key, position)
	if not folder then
		return nil
	end
	nextId += 1
	local scatter = Util.RotateY(Vector3.new(0, 0, math.random() * 2.5), math.random() * math.pi * 2)
	local spot = Vector3.new(position.X, 0, position.Z) + scatter
	spot = CombatService.ClampToArena(spot)
	local loot = { Id = "L" .. nextId, Kind = kind, Key = key, Position = spot, ExpiresAt = Util.Now() + LOOT.LOOT_LIFETIME }
	loot.Model = buildModel(loot)
	LootService.Loot[loot.Id] = loot
	return loot
end

-- A hero takes a loot drop. Potions stack; items / skills are equipped, and whatever
-- they replace is dropped where the hero stands (so nothing is ever lost).
function LootService.TryPickup(participant, lootId)
	local loot = LootService.Loot[lootId]
	local entity = participant and participant.Entity
	if not loot or not entity or not entity.Alive or not CombatService.Active then
		return false
	end
	local position = CombatService.GetPosition(entity)
	if Util.FlatDistance(position, loot.Position) > LOOT.PICKUP_RADIUS + 3 then
		return false
	end
	local player = participant.Player
	if loot.Kind == "Potion" then
		local count = participant.Potions or 0
		if count >= LOOT.MAX_POTIONS then
			return false
		end
		participant.Potions = count + 1
		removeLoot(lootId)
		PlayerService.SetPlayerAttributes(participant)
		if player then
			Net.Notify(player, string.format("Health Potion (%d / %d) - press H to drink", participant.Potions, LOOT.MAX_POTIONS), "Success")
		end
		return true
	end
	if not LootService.AllowGear then
		return false
	end
	if loot.Kind == "Skill" then
		local old = participant.Skill
		if old == loot.Key then
			if player then
				Net.Notify(player, "You already know that skill", "Warning")
			end
			return false
		end
		removeLoot(lootId)
		CombatService.SetSkill(entity, loot.Key)
		if old and old ~= "" then
			LootService.Spawn("Skill", old, position)
		end
		local ability = ClassDefinitions.GetAbility("Wanderer", loot.Key)
		if player then
			Net.Notify(player, "SKILL LEARNED", "Buff", { Banner = true, Sub = (ability and ability.Name or loot.Key) .. " is now your Q skill", Color = ClassDefinitions.Get(loot.Key).Color })
		end
		PlayerService.SetPlayerAttributes(participant)
		return true
	end
	local ok, message, replaced = ItemService.Grant(participant, loot.Key)
	if not ok then
		if player then
			Net.Notify(player, message, "Warning")
		end
		return false
	end
	removeLoot(lootId)
	if replaced then
		LootService.Spawn("Item", replaced, position)
	end
	if player then
		local item = ItemDefinitions.GetItem(loot.Key)
		local where = item.SlotType == "Boots" and "Boot Slot (Right Mouse)" or item.SlotType == "Passive" and "a Passive slot" or "a Mythic slot"
		Net.Notify(player, string.format("%s equipped in %s", message, where), "Success", { Sound = "UI.MythicAcquire" })
	end
	return true
end

-- Drink a stored potion: heal over time, short cooldown.
function LootService.UsePotion(participant)
	local entity = participant and participant.Entity
	if not entity or not entity.Alive or not CombatService.Active then
		return false
	end
	if (participant.Potions or 0) <= 0 then
		return false, "No health potions - defeat monsters to find some"
	end
	local now = Util.Now()
	if now < (potionReadyAt[participant] or 0) then
		return false, string.format("Potion ready in %.0fs", potionReadyAt[participant] - now)
	end
	if entity.Health >= entity.MaxHealth then
		return false, "Already at full health"
	end
	participant.Potions -= 1
	potionReadyAt[participant] = now + LOOT.POTION_COOLDOWN
	healing[entity] = { PerSecond = entity.MaxHealth * LOOT.POTION_HEAL_PERCENT / LOOT.POTION_HEAL_TIME, Until = now + LOOT.POTION_HEAL_TIME }
	Net.Effect("Heal", { Position = CombatService.GetPosition(entity), Amount = math.floor(entity.MaxHealth * LOOT.POTION_HEAL_PERCENT) })
	PlayerService.SetPlayerAttributes(participant)
	if entity.Model then
		entity.Model:SetAttribute("PotionReadyAt", potionReadyAt[participant])
	end
	return true
end

-- Royale: throw away an equipped item or the current skill. slot: "Skill", 1, 2, BOOT_SLOT,
-- PASSIVE_BASE + n. The item lands at the hero's feet and anyone can pick it up.
function LootService.Drop(participant, slot)
	local entity = participant and participant.Entity
	if not LootService.AllowGear or not entity or not entity.Alive or not CombatService.Active then
		return false
	end
	local position = CombatService.GetPosition(entity) + entity.Root.CFrame.LookVector * 3
	if slot == "Skill" then
		local skill = participant.Skill
		if not skill or skill == "" then
			return false, "You have no skill to drop"
		end
		participant.Skill = nil
		entity.Class = ClassDefinitions.Get(entity.ClassKey)
		CombatService.PushHeroAttributes(entity)
		PlayerService.SetPlayerAttributes(participant)
		LootService.Spawn("Skill", skill, position)
		return true
	end
	if type(slot) ~= "number" then
		return false
	end
	local removed = ItemService.Unequip(participant, slot)
	if not removed then
		return false, "That slot is empty"
	end
	LootService.Spawn("Item", removed, position)
	return true
end

-- A dead Royale hero spills everything they carried.
function LootService.DropAll(participant, position)
	if not LootService.AllowGear then
		return
	end
	if participant.Skill and participant.Skill ~= "" then
		LootService.Spawn("Skill", participant.Skill, position)
	end
	local items = {}
	for slot = 1, ItemDefinitions.MAX_MYTHIC_SLOTS do
		table.insert(items, participant.Mythics and participant.Mythics[slot])
	end
	table.insert(items, participant.Boots)
	for slot = 1, ItemDefinitions.MAX_PASSIVE_SLOTS do
		table.insert(items, participant.Passives and participant.Passives[slot])
	end
	for _, itemId in pairs(items) do
		if itemId then
			LootService.Spawn("Item", itemId, position)
		end
	end
	for _ = 1, participant.Potions or 0 do
		LootService.Spawn("Potion", "Potion", position)
	end
	participant.Potions = 0
end

function LootService.FindNearest(position, maxDistance, filter)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, loot in pairs(LootService.Loot) do
		if not filter or filter(loot) then
			local distance = Util.FlatDistance(position, loot.Position)
			if distance < bestDistance then
				best, bestDistance = loot, distance
			end
		end
	end
	return best
end

function LootService.Serialize()
	local list = {}
	for _, loot in pairs(LootService.Loot) do
		table.insert(list, { Id = loot.Id, Kind = loot.Kind, Key = loot.Key, Position = loot.Position })
	end
	return list
end

-- Lifecycle -------------------------------------------------------------------------------
local function tick()
	local now = Util.Now()
	-- potion heal over time
	for entity, heal in pairs(healing) do
		if not entity.Alive or now >= heal.Until then
			healing[entity] = nil
		else
			CombatService.Heal(entity, heal.PerSecond * TICK, false)
		end
	end
	-- walk-over pickups: potions for everyone, all gear for bots
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		local entity = participant.Entity
		if entity and entity.Alive then
			local position = CombatService.GetPosition(entity)
			for id, loot in pairs(LootService.Loot) do
				if Util.FlatDistance(position, loot.Position) <= LOOT.PICKUP_RADIUS * 0.6 then
					if loot.Kind == "Potion" or participant.IsBot then
						LootService.TryPickup(participant, id)
					end
				end
			end
		end
	end
	-- expire old loot
	for id, loot in pairs(LootService.Loot) do
		if now >= loot.ExpiresAt then
			removeLoot(id)
		end
	end
end

function LootService.Init()
	if initialized then
		return
	end
	initialized = true
	-- natural camp monsters drop health potions (both modes)
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.Kind == "Monster" and folder and math.random() <= LOOT.POTION_DROP_CHANCE then
			LootService.Spawn("Potion", "Potion", CombatService.GetPosition(entity))
		end
		if entity.Kind == "Hero" then
			healing[entity] = nil
		end
	end)
end

function LootService.Setup(mapData, allowGear)
	LootService.Cleanup()
	LootService.AllowGear = allowGear == true
	folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = mapData.Folder
end

function LootService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			task.wait(TICK)
			if runId ~= myRun then
				break
			end
			local ok, err = pcall(tick)
			if not ok then
				warn("[Ruinfall] Loot tick error:", err)
			end
		end
	end)
end

function LootService.Stop()
	runId += 1
end

function LootService.Cleanup()
	LootService.Stop()
	for id in pairs(LootService.Loot) do
		removeLoot(id)
	end
	table.clear(healing)
	if folder then
		folder:Destroy()
		folder = nil
	end
	LootService.AllowGear = false
end

LootService.BOOT_SLOT = BOOT_SLOT
LootService.PASSIVE_BASE = PASSIVE_BASE

return LootService
