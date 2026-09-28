-- LootService: things heroes pick up.
--   * Health potions (BOTH modes): natural camp monsters may drop one. Walking over a potion
--     stores it (up to Loot.MAX_POTIONS); H drinks one (heal over a few seconds).
--   * Supply chests (Royale): every piece of gear on the ground lives in a chest. Gear that
--     lands within Loot.CHEST_MERGE_RADIUS of a chest goes INTO that chest, so a death or a
--     broken ruin leaves one chest you can browse instead of a pile you can't choose from.
--     Opening a chest (F) shows every entry with its name + short stats / effect; the player
--     drags the one they want onto their gear panel. Whatever it replaces goes back into the
--     same chest. Entries: { Kind = "Item" | "Weapon" | "Potion", Key }.
--       Weapon = a class kit (Key = class): taking it turns the hero into that class.
--   * Revive cross (Royale): every hero starts holding one. Plant it anywhere; if you die
--     while it stands you rise there REVIVE_DELAY seconds later (the cross is used up).
--     Enemies can smash a planted cross. The owner can pick it back up.
-- Server-authoritative: clients only send intents (UsePotion, Drop, OpenChest, Take, ...).

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
local ROYALE = Constants.Royale
local TICK = 0.25
local POTION_COLOR = Color3.fromRGB(255, 70, 90)
local CHEST_GLOW = Color3.fromRGB(255, 200, 90)
local BOOT_SLOT = ItemDefinitions.BOOT_SLOT
local PASSIVE_BASE = ItemDefinitions.PASSIVE_SLOT_BASE

-- State
local LootService = {}
LootService.Loot = {} -- loose potions: [id] = { Id, Kind = "Potion", Position, Model, ExpiresAt }
LootService.Chests = {} -- [id] = { Id, Position, Entries = { {Kind, Key} }, Model, ExpiresAt, Viewers = {[player]=true} }
LootService.AllowGear = false -- Royale turns chests / weapons / crosses on
local folder = nil
local nextId = 0
local runId = 0
local healing = {} -- [entity] = { PerSecond, Until }
local potionReadyAt = setmetatable({}, { __mode = "k" })
local initialized = false

local function remote()
	return Net.Get("LootRequest")
end

local function newPart(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(properties) do
		part[key] = value
	end
	return part
end

-- Entry descriptions (name, colour, one-line summary, icon) -------------------------------
function LootService.Describe(entry)
	if entry.Kind == "Potion" then
		return { Name = "Health Potion", Summary = string.format("+%d%% HP  +%d%% Mana over %ds  |  drink with H", LOOT.POTION_HEAL_PERCENT * 100, LOOT.POTION_MANA_PERCENT * 100, LOOT.POTION_HEAL_TIME), Color = POTION_COLOR, Icon = "", Slot = "Potion" }
	elseif entry.Kind == "Weapon" then
		local classDef = ClassDefinitions.Get(entry.Key)
		local ability = classDef and classDef.Ability
		local stats = classDef and string.format("%d HP  %d %s  %s", classDef.MaxHealth, classDef.MagicPower and classDef.MagicPower or classDef.AttackDamage,
			classDef.MagicPower and "MP" or "AD", classDef.AttackType == "Melee" and "melee" or "ranged") or ""
		return {
			Name = ClassDefinitions.GetWeaponName(entry.Key) .. " (" .. (classDef and classDef.DisplayName or entry.Key) .. ")",
			Summary = stats .. "  |  Q " .. (ability and ability.Name or "?"),
			Color = classDef and classDef.Color or CHEST_GLOW, Icon = classDef and classDef.IconImage or "", Slot = "Weapon",
		}
	end
	local item = ItemDefinitions.GetItem(entry.Key)
	return {
		Name = item and item.Name or tostring(entry.Key),
		Summary = item and ItemDefinitions.GetShortSummary(item) or "",
		Color = item and item.Color or CHEST_GLOW, Icon = item and item.Icon or "",
		Slot = item and item.SlotType or "Mythic",
	}
end

-- Loose potions -----------------------------------------------------------------------------
local function buildPotion(loot)
	local ground = Vector3.new(loot.Position.X, 0, loot.Position.Z)
	local model = Instance.new("Model")
	model.Name = "Potion_" .. loot.Id
	local flask = newPart({ Name = "Flask", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(ground + Vector3.new(0, 1.5, 0)), Material = Enum.Material.Neon, Color = POTION_COLOR, CastShadow = false })
	flask.Parent = model
	newPart({ Name = "Neck", Size = Vector3.new(0.45, 0.6, 0.45), CFrame = CFrame.new(ground + Vector3.new(0, 2.4, 0)), Material = Enum.Material.Wood, Color = Color3.fromRGB(150, 110, 70) }).Parent = model
	newPart({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 3, 3), CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = POTION_COLOR, Transparency = 0.4, CastShadow = false }).Parent = model
	local light = Instance.new("PointLight")
	light.Color = POTION_COLOR
	light.Range = 8
	light.Parent = flask
	model.PrimaryPart = flask
	model.Parent = folder
	return model
end

local function spawnPotion(position)
	nextId += 1
	local spot = CombatService.ClampToArena(Vector3.new(position.X, 0, position.Z) + Util.RotateY(Vector3.new(0, 0, math.random() * 2.5), math.random() * math.pi * 2))
	local loot = { Id = "L" .. nextId, Kind = "Potion", Position = spot, ExpiresAt = Util.Now() + LOOT.LOOT_LIFETIME }
	loot.Model = buildPotion(loot)
	LootService.Loot[loot.Id] = loot
	return loot
end

local function removeLoot(id)
	local loot = LootService.Loot[id]
	if loot then
		LootService.Loot[id] = nil
		if loot.Model then
			loot.Model:Destroy()
		end
	end
end

-- Chests ----------------------------------------------------------------------------------------
local function chestPayload(chest)
	local entries = {}
	for index, entry in ipairs(chest.Entries) do
		local info = LootService.Describe(entry)
		info.Index = index
		info.Kind = entry.Kind
		info.Key = entry.Key
		table.insert(entries, info)
	end
	return { Id = chest.Id, Entries = entries, Position = chest.Position }
end

local function refreshChestLabel(chest)
	local label = chest.Model and chest.Model:FindFirstChild("Label", true)
	if not label then
		return
	end
	local names = {}
	for index = 1, math.min(3, #chest.Entries) do
		table.insert(names, LootService.Describe(chest.Entries[index]).Name)
	end
	if #chest.Entries > 3 then
		table.insert(names, string.format("+%d more", #chest.Entries - 3))
	end
	label.Title.Text = string.format("SUPPLY CHEST (%d)", #chest.Entries)
	label.Items.Text = table.concat(names, "\n")
end

local function buildChest(chest)
	local ground = Vector3.new(chest.Position.X, 0, chest.Position.Z)
	local yaw = math.random() * math.pi * 2
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local model = Instance.new("Model")
	model.Name = "Chest_" .. chest.Id
	local wood = Color3.fromRGB(120, 78, 42)
	local body = newPart({ Name = "Body", Size = Vector3.new(4, 2.2, 2.6), CFrame = base * CFrame.new(0, 1.1, 0), Material = Enum.Material.WoodPlanks, Color = wood, CanQuery = true })
	body.Parent = model
	newPart({ Name = "Lid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.6, 2.6), CFrame = base * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, 0), Material = Enum.Material.WoodPlanks, Color = wood:Lerp(Color3.new(0, 0, 0), 0.1) }).Parent = model
	for _, x in ipairs({ -1.6, 0, 1.6 }) do
		newPart({ Name = "Band", Size = Vector3.new(0.3, 2.3, 2.7), CFrame = base * CFrame.new(x, 1.12, 0), Material = Enum.Material.Metal, Color = Color3.fromRGB(200, 160, 70) }).Parent = model
		newPart({ Name = "LidBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.72, 2.72), CFrame = base * CFrame.new(x, 2.2, 0), Material = Enum.Material.Metal, Color = Color3.fromRGB(200, 160, 70) }).Parent = model
	end
	newPart({ Name = "Lock", Size = Vector3.new(0.6, 0.7, 0.3), CFrame = base * CFrame.new(0, 1.9, -1.36), Material = Enum.Material.Metal, Color = Color3.fromRGB(230, 190, 90) }).Parent = model
	local glow = newPart({ Name = "Glow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 6, 6), CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = CHEST_GLOW, Transparency = 0.5, CastShadow = false })
	glow.Parent = model
	local beam = newPart({ Name = "Beam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 0.5, 0.5), CFrame = CFrame.new(ground + Vector3.new(0, 10, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = CHEST_GLOW, Transparency = 0.6, CastShadow = false })
	beam.Parent = model
	local light = Instance.new("PointLight")
	light.Color = CHEST_GLOW
	light.Range = 14
	light.Brightness = 1.4
	light.Parent = body
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(200, 74)
	billboard.StudsOffset = Vector3.new(0, 4.6, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.Fondamento
	title.TextScaled = true
	title.TextColor3 = CHEST_GLOW
	title.TextStrokeTransparency = 0.3
	title.Parent = billboard
	local items = Instance.new("TextLabel")
	items.Name = "Items"
	items.BackgroundTransparency = 1
	items.Position = UDim2.fromOffset(0, 22)
	items.Size = UDim2.new(1, 0, 0, 52)
	items.Font = Enum.Font.GothamMedium
	items.TextSize = 13
	items.TextYAlignment = Enum.TextYAlignment.Top
	items.TextColor3 = Color3.fromRGB(235, 225, 205)
	items.TextStrokeTransparency = 0.4
	items.Parent = billboard
	billboard.Parent = body
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Supply Chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		LootService.OpenChest(player, chest.Id)
	end)
	model.PrimaryPart = body
	model.Parent = folder
	return model
end

local function pushChest(chest)
	local payload = chestPayload(chest)
	for player in pairs(chest.Viewers) do
		if player.Parent then
			remote():FireClient(player, "Chest", payload)
		end
	end
end

local function removeChest(id)
	local chest = LootService.Chests[id]
	if not chest then
		return
	end
	LootService.Chests[id] = nil
	for player in pairs(chest.Viewers) do
		if player.Parent then
			remote():FireClient(player, "ChestClosed", { Id = id })
		end
	end
	if chest.Model then
		chest.Model:Destroy()
	end
end

local function chestChanged(chest)
	if #chest.Entries == 0 then
		removeChest(chest.Id)
		return
	end
	chest.ExpiresAt = math.max(chest.ExpiresAt, Util.Now() + 60)
	refreshChestLabel(chest)
	pushChest(chest)
end

local function findChestNear(position, radius)
	local best, bestDistance = nil, radius
	for _, chest in pairs(LootService.Chests) do
		local distance = Util.FlatDistance(chest.Position, position)
		if distance <= bestDistance then
			best, bestDistance = chest, distance
		end
	end
	return best
end

-- Put gear into the chest near position (a new chest if none is close enough).
function LootService.AddToChest(kind, key, position, noMerge)
	if not folder then
		return nil
	end
	local chest = not noMerge and findChestNear(position, LOOT.CHEST_MERGE_RADIUS) or nil
	if not chest then
		nextId += 1
		local spot = CombatService.ClampToArena(Vector3.new(position.X, 0, position.Z))
		chest = { Id = "C" .. nextId, Position = spot, Entries = {}, ExpiresAt = Util.Now() + LOOT.CHEST_LIFETIME, Viewers = {} }
		chest.Model = buildChest(chest)
		LootService.Chests[chest.Id] = chest
	end
	table.insert(chest.Entries, { Kind = kind, Key = key })
	chestChanged(chest)
	return chest
end

-- Anything on the ground: potions lie loose, gear goes into a chest.
function LootService.Spawn(kind, key, position)
	if kind == "Potion" then
		return folder and spawnPotion(position) or nil
	end
	if not LootService.AllowGear then
		return nil
	end
	return LootService.AddToChest(kind, key, position)
end

function LootService.OpenChest(player, chestId)
	local chest = LootService.Chests[chestId]
	local participant = PlayerService.GetParticipantByPlayer(player)
	local entity = participant and participant.Entity
	if not chest or not entity or not entity.Alive then
		return false
	end
	if Util.FlatDistance(CombatService.GetPosition(entity), chest.Position) > LOOT.CHEST_REACH then
		return false
	end
	for _, other in pairs(LootService.Chests) do
		other.Viewers[player] = nil
	end
	chest.Viewers[player] = true
	remote():FireClient(player, "Chest", chestPayload(chest))
	return true
end

function LootService.CloseChest(player)
	for _, chest in pairs(LootService.Chests) do
		chest.Viewers[player] = nil
	end
end

-- Weapons ------------------------------------------------------------------------------------
-- Swap the hero to another class; the old weapon goes into `chest` (or a new chest).
local function equipWeapon(participant, classKey, chest)
	local entity = participant.Entity
	local old = participant.ClassKey
	if not CombatService.SetClass(entity, classKey) then
		return false
	end
	-- re-dress the hero with the new class's gear / weapon mesh
	local CharacterFactory = require(script.Parent:WaitForChild("CharacterFactory"))
	pcall(CharacterFactory.ApplyClassLook, entity.Model, classKey, Constants.GetTeamColor(participant.Team), participant.AvatarLook == true)
	if participant.IsBot then
		local BotService = require(script.Parent:WaitForChild("BotService"))
		BotService.Detach(participant)
		BotService.Attach(participant, entity)
	end
	PlayerService.SetPlayerAttributes(participant)
	if old and old ~= classKey then
		if chest then
			table.insert(chest.Entries, { Kind = "Weapon", Key = old })
		else
			LootService.AddToChest("Weapon", old, CombatService.GetPosition(entity))
		end
	end
	return true
end

-- Take entry `index` out of a chest (drag onto the gear panel). Replaced gear goes back in.
function LootService.Take(participant, chestId, index)
	local chest = LootService.Chests[chestId]
	local entity = participant and participant.Entity
	local player = participant and participant.Player
	if not chest or not entity or not entity.Alive or not CombatService.Active or type(index) ~= "number" then
		return false
	end
	if Util.FlatDistance(CombatService.GetPosition(entity), chest.Position) > LOOT.CHEST_REACH then
		return false, "Too far from the chest"
	end
	local entry = chest.Entries[index]
	if not entry then
		return false
	end
	if entry.Kind == "Potion" then
		if (participant.Potions or 0) >= LOOT.MAX_POTIONS then
			return false, "You can't carry more potions"
		end
		table.remove(chest.Entries, index)
		participant.Potions = (participant.Potions or 0) + 1
		PlayerService.SetPlayerAttributes(participant)
	elseif entry.Kind == "Weapon" then
		if entry.Key == participant.ClassKey then
			return false, "You already wield that weapon"
		end
		table.remove(chest.Entries, index)
		equipWeapon(participant, entry.Key, chest)
		local classDef = ClassDefinitions.Get(entry.Key)
		if player then
			Net.Notify(player, "NEW WEAPON", "Buff", { Banner = true, Sub = string.format("%s - you are now a %s (Q: %s)", ClassDefinitions.GetWeaponName(entry.Key), classDef.DisplayName, classDef.Ability.Name), Color = classDef.Color })
		end
	else
		local ok, message, replaced = ItemService.Grant(participant, entry.Key)
		if not ok then
			return false, message
		end
		table.remove(chest.Entries, index)
		if replaced then
			table.insert(chest.Entries, { Kind = "Item", Key = replaced })
		end
		if player then
			Net.Notify(player, message .. " equipped", "Success", { Sound = "UI.MythicAcquire" })
		end
	end
	chestChanged(chest)
	return true
end

-- Potions ---------------------------------------------------------------------------------------
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
	if entity.Health >= entity.MaxHealth and (entity.Mana or 0) >= (entity.MaxMana or 0) then
		return false, "Already at full health and mana"
	end
	participant.Potions -= 1
	potionReadyAt[participant] = now + LOOT.POTION_COOLDOWN
	healing[entity] = {
		PerSecond = entity.MaxHealth * LOOT.POTION_HEAL_PERCENT / LOOT.POTION_HEAL_TIME,
		ManaPerSecond = (entity.MaxMana or 0) * LOOT.POTION_MANA_PERCENT / LOOT.POTION_HEAL_TIME, -- restores mana too
		Until = now + LOOT.POTION_HEAL_TIME,
	}
	Net.Effect("Heal", { Position = CombatService.GetPosition(entity), Amount = math.floor(entity.MaxHealth * LOOT.POTION_HEAL_PERCENT) })
	PlayerService.SetPlayerAttributes(participant)
	return true
end

-- Dropping gear (Royale) ----------------------------------------------------------------------
-- slot: 1 / 2 (E / R), BOOT_SLOT, PASSIVE_BASE + n. The item goes into a chest at your feet.
function LootService.Drop(participant, slot)
	local entity = participant and participant.Entity
	if not LootService.AllowGear or not entity or not entity.Alive or not CombatService.Active then
		return false
	end
	if type(slot) ~= "number" then
		return false
	end
	local removed = ItemService.Unequip(participant, slot)
	if not removed then
		return false, "That slot is empty"
	end
	LootService.AddToChest("Item", removed, CombatService.GetPosition(entity) + entity.Root.CFrame.LookVector * 3)
	return true
end

-- A dead hero's whole inventory goes into ONE chest where they fell.
function LootService.DropAll(participant, position)
	if not LootService.AllowGear then
		return
	end
	local entries = {}
	if participant.ClassKey and participant.ClassKey ~= "Fighter" then
		table.insert(entries, { "Weapon", participant.ClassKey })
	end
	for slot = 1, ItemDefinitions.MAX_MYTHIC_SLOTS do
		local id = participant.Mythics and participant.Mythics[slot]
		if id then
			table.insert(entries, { "Item", id })
		end
	end
	if participant.Boots then
		table.insert(entries, { "Item", participant.Boots })
	end
	for slot = 1, ItemDefinitions.MAX_PASSIVE_SLOTS do
		local id = participant.Passives and participant.Passives[slot]
		if id then
			table.insert(entries, { "Item", id })
		end
	end
	for _ = 1, participant.Potions or 0 do
		table.insert(entries, { "Potion", "Potion" })
	end
	participant.Potions = 0
	if #entries == 0 then
		return
	end
	local chest = LootService.AddToChest(entries[1][1], entries[1][2], position)
	for index = 2, #entries do
		table.insert(chest.Entries, { Kind = entries[index][1], Key = entries[index][2] })
	end
	chestChanged(chest)
end

-- Revive cross (Royale) ----------------------------------------------------------------------
local function buildCross(position, color, ownerName)
	local ground = Vector3.new(position.X, 0, position.Z)
	local model = Instance.new("Model")
	model.Name = "ReviveCross"
	local stone = Color3.fromRGB(215, 205, 185)
	local post = newPart({ Name = "Post", Size = Vector3.new(0.9, 6, 0.9), CFrame = CFrame.new(ground + Vector3.new(0, 3.4, 0)), Material = Enum.Material.Marble, Color = stone, CanQuery = true, CanCollide = true })
	post.Parent = model
	newPart({ Name = "Arm", Size = Vector3.new(3.6, 0.9, 0.9), CFrame = CFrame.new(ground + Vector3.new(0, 4.8, 0)), Material = Enum.Material.Marble, Color = stone }).Parent = model
	newPart({ Name = "Base", Size = Vector3.new(2.6, 0.6, 2.6), CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0)), Material = Enum.Material.Marble, Color = stone:Lerp(Color3.new(0, 0, 0), 0.2) }).Parent = model
	local gem = newPart({ Name = "Gem", Size = Vector3.new(0.7, 0.7, 0.7), CFrame = CFrame.new(ground + Vector3.new(0, 4.8, -0.5)) * CFrame.Angles(0, 0, math.rad(45)), Material = Enum.Material.Neon, Color = color, CastShadow = false })
	gem.Parent = model
	newPart({ Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 5, 5), CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon, Color = color, Transparency = 0.45, CastShadow = false }).Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 1.6
	light.Parent = gem
	model:SetAttribute("OwnerName", ownerName)
	model.PrimaryPart = post
	model.Parent = folder
	return model, post
end

function LootService.PlantCross(participant)
	local entity = participant and participant.Entity
	if not LootService.AllowGear or not entity or not entity.Alive or not CombatService.Active then
		return false
	end
	if participant.CrossState ~= "Held" then
		return false, participant.CrossState == "Planted" and "Your cross is already planted" or "You no longer have a revive cross"
	end
	local position = CombatService.ClampToArena(CombatService.GetPosition(entity) + entity.Root.CFrame.LookVector * 3)
	local color = Color3.fromRGB(255, 230, 160) -- neutral glow: no team colours in free for all
	local model, root = buildCross(position, color, participant.Name)
	local cross = CombatService.Register({
		Kind = "Cross",
		Team = participant.Team,
		Model = model,
		Root = root,
		Position = Vector3.new(position.X, 0, position.Z),
		Health = ROYALE.CROSS_HEALTH,
		MaxHealth = ROYALE.CROSS_HEALTH,
		Armor = 10,
		Radius = 1.6,
		Owner = participant,
	})
	participant.Cross = cross
	participant.CrossState = "Planted"
	-- the owner can pull it out again and plant it somewhere else
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Your Revive Cross"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		if player == participant.Player then
			LootService.PickUpCross(participant)
		end
	end)
	Net.Effect("Cast", { Position = position, Color = color })
	PlayerService.SetPlayerAttributes(participant)
	if participant.Player then
		Net.Notify(participant.Player, "Revive Cross planted - if you fall, you rise here", "Success")
	end
	return true
end

local function destroyCross(participant)
	local cross = participant.Cross
	participant.Cross = nil
	if cross then
		CombatService.Unregister(cross)
		if cross.Model then
			cross.Model:Destroy()
		end
	end
end

function LootService.PickUpCross(participant)
	if participant.CrossState ~= "Planted" or not participant.Entity or not participant.Entity.Alive then
		return false
	end
	if Util.FlatDistance(CombatService.GetPosition(participant.Entity), participant.Cross.Position) > 10 then
		return false
	end
	destroyCross(participant)
	participant.CrossState = "Held"
	PlayerService.SetPlayerAttributes(participant)
	return true
end

-- used by the revive: returns the cross position (and consumes the cross) if it still stands
function LootService.ConsumeCross(participant)
	local cross = participant.Cross
	if participant.CrossState ~= "Planted" or not cross or not cross.Alive then
		return nil
	end
	local position = cross.Position
	destroyCross(participant)
	participant.CrossState = "Used"
	PlayerService.SetPlayerAttributes(participant)
	return position
end

function LootService.HasStandingCross(participant)
	return participant.CrossState == "Planted" and participant.Cross ~= nil and participant.Cross.Alive
end

function LootService.GiveCrosses()
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		participant.CrossState = "Held"
		participant.Cross = nil
		PlayerService.SetPlayerAttributes(participant)
	end
end

-- Queries -------------------------------------------------------------------------------------
function LootService.FindNearestPotion(position, maxDistance)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, loot in pairs(LootService.Loot) do
		local distance = Util.FlatDistance(position, loot.Position)
		if distance < bestDistance then
			best, bestDistance = loot, distance
		end
	end
	return best
end

function LootService.FindNearestChest(position, maxDistance, filter)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, chest in pairs(LootService.Chests) do
		if not filter or filter(chest) then
			local distance = Util.FlatDistance(position, chest.Position)
			if distance < bestDistance then
				best, bestDistance = chest, distance
			end
		end
	end
	return best
end

-- Bots: take what helps from a chest they stand next to (a weapon while still a Fighter,
-- then gear for empty slots).
local function botLoot(participant, chest)
	for index, entry in ipairs(chest.Entries) do
		if entry.Kind == "Weapon" and participant.ClassKey == "Fighter" then
			return LootService.Take(participant, chest.Id, index)
		end
	end
	for index, entry in ipairs(chest.Entries) do
		if entry.Kind == "Potion" and (participant.Potions or 0) < LOOT.MAX_POTIONS then
			return LootService.Take(participant, chest.Id, index)
		elseif entry.Kind == "Item" then
			local item = ItemDefinitions.GetItem(entry.Key)
			local free = false
			if item and item.SlotType == "Boots" then
				free = participant.Boots == nil
			elseif item and item.SlotType == "Passive" then
				free = not (participant.Passives and participant.Passives[ItemDefinitions.MAX_PASSIVE_SLOTS])
			elseif item then
				free = not (participant.Mythics and participant.Mythics[ItemDefinitions.MAX_MYTHIC_SLOTS])
			end
			if free and LootService.Take(participant, chest.Id, index) then
				return true
			end
		end
	end
	participant.BotSkipChest = chest.Id -- nothing useful: don't come back
	return false
end

function LootService.Serialize()
	local list = {}
	for _, chest in pairs(LootService.Chests) do
		table.insert(list, { Id = chest.Id, Kind = "Chest", Position = chest.Position, Count = #chest.Entries })
	end
	return list
end

-- Lifecycle -------------------------------------------------------------------------------------
local function tick()
	local now = Util.Now()
	for entity, heal in pairs(healing) do
		if not entity.Alive or now >= heal.Until then
			healing[entity] = nil
		else
			CombatService.Heal(entity, heal.PerSecond * TICK, false)
			if heal.ManaPerSecond > 0 and entity.MaxMana then
				entity.Mana = math.min(entity.MaxMana, (entity.Mana or 0) + heal.ManaPerSecond * TICK)
				CombatService.SyncMana(entity)
			end
		end
	end
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		local entity = participant.Entity
		if entity and entity.Alive then
			local position = CombatService.GetPosition(entity)
			-- walk-over potions
			for id, loot in pairs(LootService.Loot) do
				if Util.FlatDistance(position, loot.Position) <= LOOT.PICKUP_RADIUS * 0.6 and (participant.Potions or 0) < LOOT.MAX_POTIONS then
					participant.Potions = (participant.Potions or 0) + 1
					removeLoot(id)
					PlayerService.SetPlayerAttributes(participant)
					if participant.Player then
						Net.Notify(participant.Player, string.format("Health Potion (%d / %d) - press H to drink", participant.Potions, LOOT.MAX_POTIONS), "Success")
					end
				end
			end
			if participant.IsBot and LootService.AllowGear then
				local chest = LootService.FindNearestChest(position, 5)
				if chest and chest.Id ~= participant.BotSkipChest then
					botLoot(participant, chest)
				end
			end
		end
	end
	-- close chest windows of players who walked away / died
	for _, chest in pairs(LootService.Chests) do
		for player in pairs(chest.Viewers) do
			local participant = PlayerService.GetParticipantByPlayer(player)
			local entity = participant and participant.Entity
			if not player.Parent or not entity or not entity.Alive or Util.FlatDistance(CombatService.GetPosition(entity), chest.Position) > LOOT.CHEST_REACH + 2 then
				chest.Viewers[player] = nil
				if player.Parent then
					remote():FireClient(player, "ChestClosed", { Id = chest.Id })
				end
			end
		end
	end
	for id, loot in pairs(LootService.Loot) do
		if now >= loot.ExpiresAt then
			removeLoot(id)
		end
	end
	for id, chest in pairs(LootService.Chests) do
		if now >= chest.ExpiresAt then
			removeChest(id)
		end
	end
end

function LootService.Init()
	if initialized then
		return
	end
	initialized = true
	CombatService.EntityDied:Connect(function(entity, killer)
		-- natural camp monsters drop health potions (both modes)
		if entity.Kind == "Monster" and folder and math.random() <= LOOT.POTION_DROP_CHANCE then
			spawnPotion(CombatService.GetPosition(entity))
		elseif entity.Kind == "Hero" then
			healing[entity] = nil
		elseif entity.Kind == "Cross" and entity.Owner then
			local owner = entity.Owner
			if owner.Cross == entity then
				owner.Cross = nil
				owner.CrossState = "Lost"
				CombatService.Unregister(entity)
				task.delay(0.3, function()
					if entity.Model then
						entity.Model:Destroy()
					end
				end)
				PlayerService.SetPlayerAttributes(owner)
				if owner.Player then
					Net.Notify(owner.Player, "YOUR REVIVE CROSS WAS DESTROYED", "Danger", { Sub = killer and killer.Participant and ("by " .. killer.Participant.Name) or nil })
				end
			end
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
	for id in pairs(LootService.Chests) do
		removeChest(id)
	end
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.Cross then
			destroyCross(participant)
		end
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
