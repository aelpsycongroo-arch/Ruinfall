-- RuinService: every 60s spawn 1 Ruin per 2 active participants (rounded up).
-- Ruins are destructible neutral objectives; the destroyer gets a random buff.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))
local MapDefinitions = require(Shared:WaitForChild("MapDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))
local Net = require(script.Parent:WaitForChild("Net"))
local PropBuilder = require(script.Parent:WaitForChild("PropBuilder"))

-- Constants
local RUIN = Constants.Ruin
local PALETTE = MapDefinitions.Palette
local TICK_INTERVAL = 0.5

-- State
local RuinService = {}
RuinService.Ruins = {} -- [entityId] = { Id, Position, Entity, Model }
RuinService.NextSpawnAt = 0

local random = Random.new()
local folder = nil
local runId = 0

-- Functions
local function newPart(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(properties) do
		part[key] = value
	end
	return part
end

-- Mesh-library version of the ruin. Colliders/root keep the exact sizes of the original
-- primitive model (so gameplay is unchanged); visuals come from ServerStorage.RuinfallAssets.
local function buildRuinModelAssets(position)
	local model = Instance.new("Model")
	model.Name = "Ruin"
	local ground = Vector3.new(position.X, position.Y, position.Z)
	-- platform
	local platform = PropBuilder.Asset("Shrine_Platform", model, CFrame.new(ground + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), Vector3.new(0.45, 1, 0.45))
	if platform then
		platform.Name = "Platform"
		local appearance = platform:FindFirstChildOfClass("SurfaceAppearance")
		if appearance then
			appearance.Color = Color3.fromRGB(215, 205, 190)
		end
	end
	-- rune stones set into the platform rim
	for index = 1, 6 do
		local angle = (index - 1) * math.pi / 3
		local spot = ground + Util.RotateY(Vector3.new(0, 0, 5.9), angle)
		newPart({
			Name = "RuneStone",
			Size = Vector3.new(0.9, 0.12, 0.45),
			CFrame = CFrame.new(spot + Vector3.new(0, 0.68, 0)) * CFrame.Angles(0, angle, 0),
			Color = PALETTE.RuinRune,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}).Parent = model
	end
	-- broken pillars: invisible colliders (original sizes) + mesh visuals
	local pillarKinds = { "Pillar_Broken", "Pillar_Ruined", "Pillar_Small" }
	for index = 1, 3 do
		local angle = (index - 1) * (2 * math.pi / 3) + random:NextNumber(-0.3, 0.3)
		local height = random:NextNumber(3, 6)
		local pillarPosition = position + Util.RotateY(Vector3.new(0, 0, 4.8), angle)
		newPart({
			Name = "BrokenPillar",
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(pillarPosition + Vector3.new(0, height / 2 + 0.4, 0)) * CFrame.Angles(0, angle, 0),
			Transparency = 1,
			CastShadow = false,
		}).Parent = model
		local kind = pillarKinds[index]
		local source = game:GetService("ServerStorage").RuinfallAssets:FindFirstChild(kind)
		local scale = source and math.clamp((height + 0.6) / source.Size.Y, 0.55, 1.15) or 1
		local pillar = PropBuilder.Asset(kind, model, CFrame.new(pillarPosition + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, angle + random:NextNumber(-0.4, 0.4), 0), scale)
		if pillar then
			pillar.Name = "PillarVisual"
			pillar.CastShadow = true
		end
		if index == 1 then
			local vines = PropBuilder.Asset("Vines_Hanging", model, CFrame.new(pillarPosition + Util.RotateY(Vector3.new(0, 0, 1.05), angle) + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, angle, 0), Vector3.new(0.3, math.max(0.6, height / 4), 1))
			if vines then
				vines.Name = "Vines"
			end
		end
	end
	-- central obelisk: invisible root/collider with the original size, tall pillar mesh visual
	local obelisk = newPart({
		Name = "Obelisk",
		Size = Vector3.new(2.2, 7, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 4.1, 0)),
		Transparency = 1,
		CastShadow = false,
	})
	obelisk.Parent = model
	local column = PropBuilder.Asset("Pillar_Tall", model, CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(22.5), 0), Vector3.new(0.72, 0.74, 0.72))
	if column then
		column.Name = "ObeliskVisual"
		column.CastShadow = true
	end
	local half = column and column.Size.X / 2 or 1.1
	for face = 0, 3 do
		local faceCFrame = CFrame.new(position + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, face * math.pi / 2 + math.rad(22.5), 0) * CFrame.new(0, 0, -(half * 0.93))
		newPart({
			Name = "Rune",
			Size = Vector3.new(0.28, 3.8, 0.06),
			CFrame = faceCFrame,
			Color = PALETTE.RuinRune,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}).Parent = model
	end
	local crystal = newPart({
		Name = "Crystal",
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = CFrame.new(position + Vector3.new(0, 9.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = PALETTE.RuinRune,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	crystal.Parent = model
	local light = Instance.new("PointLight")
	light.Color = PALETTE.RuinRune
	light.Range = 16
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = crystal
	-- rubble and plants around the base
	for _ = 1, 5 do
		local angle = random:NextNumber(0, math.pi * 2)
		local spot = ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(6.4, 8)
		PropBuilder.Asset(random:NextNumber() < 0.6 and "Rock_Small" or "Rock_Flat", model, CFrame.new(spot) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), random:NextNumber(0.6, 1.1))
	end
	PropBuilder.ScatterSmall(model, ground, 7.2, random, 6, true)
	model.PrimaryPart = obelisk
	model.Parent = folder
	return model, obelisk
end

local function buildRuinModel(position)
	if PropBuilder.HasAssets() then
		local ok, model, obelisk = pcall(buildRuinModelAssets, position)
		if ok and model and obelisk then
			return model, obelisk
		elseif not ok then
			warn("[Ruinfall] Ruin asset model failed, using primitive fallback:", model)
		end
	end
	local model = Instance.new("Model")
	model.Name = "Ruin"
	newPart({
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 13, 13),
		CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.RuinStone:Lerp(Color3.new(0, 0, 0), 0.35),
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
	}).Parent = model
	for index = 1, 3 do
		local angle = (index - 1) * (2 * math.pi / 3) + random:NextNumber(-0.3, 0.3)
		local height = random:NextNumber(3, 6)
		local pillarPosition = position + Util.RotateY(Vector3.new(0, 0, 4.8), angle)
		newPart({
			Name = "BrokenPillar",
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(pillarPosition + Vector3.new(0, height / 2 + 0.4, 0)) * CFrame.Angles(random:NextNumber(-0.15, 0.15), angle, random:NextNumber(-0.15, 0.15)),
			Color = PALETTE.RuinStone,
			Material = Enum.Material.Sandstone,
		}).Parent = model
	end
	local obelisk = newPart({
		Name = "Obelisk",
		Size = Vector3.new(2.2, 7, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 4.1, 0)),
		Color = PALETTE.RuinStone,
		Material = Enum.Material.Sandstone,
	})
	obelisk.Parent = model
	for face = 0, 3 do
		local faceCFrame = obelisk.CFrame * CFrame.Angles(0, face * math.pi / 2, 0) * CFrame.new(0, 0, -1.12)
		newPart({
			Name = "Rune",
			Size = Vector3.new(0.5, 5, 0.08),
			CFrame = faceCFrame,
			Color = PALETTE.RuinRune,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}).Parent = model
	end
	local crystal = newPart({
		Name = "Crystal",
		Size = Vector3.new(1.3, 1.3, 1.3),
		CFrame = CFrame.new(position + Vector3.new(0, 8.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = PALETTE.RuinRune,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	crystal.Parent = model
	local light = Instance.new("PointLight")
	light.Color = PALETTE.RuinRune
	light.Range = 16
	light.Brightness = 1.6
	light.Parent = crystal
	model.PrimaryPart = obelisk
	model.Parent = folder
	return model, obelisk
end

local function countActiveParticipants()
	local count = 0
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.State == "Alive" or participant.State == "Dead" then
			count += 1
		end
	end
	return count
end

local function countRuins()
	local count = 0
	for _ in pairs(RuinService.Ruins) do
		count += 1
	end
	return count
end

function RuinService.SpawnRuin()
	if not folder then
		return nil
	end
	local existing = {}
	for _, ruin in pairs(RuinService.Ruins) do
		table.insert(existing, ruin.Position)
	end
	local position = MapGenerator.FindRuinLocation(random, existing)
	if not position then
		return nil
	end
	local model, obelisk = buildRuinModel(position)
	local entity = CombatService.Register({
		Kind = "Ruin",
		Team = Constants.NEUTRAL_TEAM,
		Model = model,
		Root = obelisk,
		Position = position,
		Health = RUIN.HEALTH,
		MaxHealth = RUIN.HEALTH,
		Armor = 0,
		Radius = 3.2,
	})
	local ruin = { Id = entity.Id, Position = position, Entity = entity, Model = model }
	RuinService.Ruins[entity.Id] = ruin
	Net.Effect("RuinSpawn", { Position = position, Color = PALETTE.RuinRune })
	return ruin
end

local function spawnWave()
	local wanted = math.max(1, math.ceil(countActiveParticipants() / RUIN.PLAYERS_PER_RUIN))
	local room = RUIN.MAX_ACTIVE - countRuins()
	local spawned = 0
	for _ = 1, math.min(wanted, room) do
		if RuinService.SpawnRuin() then
			spawned += 1
		end
	end
	if spawned > 0 then
		local text = spawned == 1 and "A RUIN HAS APPEARED" or (spawned .. " RUINS HAVE APPEARED")
		Net.Notify(nil, text, "Ruin", { Sub = "Destroy it to claim a powerful buff" })
	end
end

local function onRuinDestroyed(entity, killer)
	local ruin = RuinService.Ruins[entity.Id]
	if not ruin then
		return
	end
	RuinService.Ruins[entity.Id] = nil
	CombatService.Unregister(entity)
	Net.Effect("RuinDestroyed", { Position = ruin.Position, Color = PALETTE.RuinRune })
	task.delay(0.3, function()
		if ruin.Model then
			ruin.Model:Destroy()
		end
	end)
	if not killer or killer.Kind ~= "Hero" or not killer.Alive then
		return
	end
	local buffKey = CombatDefinitions.BuffOrder[random:NextInteger(1, #CombatDefinitions.BuffOrder)]
	local buff = CombatDefinitions.Buffs[buffKey]
	CombatService.ApplyBuff(killer, buffKey)
	if killer.Participant then
		killer.Participant.Stats.Ruins += 1
	end
	if killer.Player then
		Net.Notify(killer.Player, "RUIN DESTROYED", "Buff", {
			Banner = true,
			Sub = string.format("BUFF ACQUIRED: %s - %s (%ds)", buff.Name, buff.Description, buff.Duration),
			Color = buff.Color,
		})
	end
	local name = killer.Participant and killer.Participant.Name or "Someone"
	Net.Notify(nil, string.format("%s destroyed a Ruin and gained %s", name, buff.Name), "Info")
end

local function tick()
	if Util.Now() >= RuinService.NextSpawnAt then
		RuinService.NextSpawnAt = Util.Now() + RUIN.INTERVAL
		spawnWave()
	end
end

-- Public API ---------------------------------------------------------------------------
function RuinService.Init()
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.Kind == "Ruin" then
			onRuinDestroyed(entity, killer)
		end
	end)
end

function RuinService.Setup(mapData, seed)
	RuinService.Cleanup()
	random = Random.new(seed + 7919)
	folder = Instance.new("Folder")
	folder.Name = "Ruins"
	folder.Parent = mapData.Folder
end

function RuinService.Start()
	runId += 1
	local myRun = runId
	local firstDelay = Constants.DEBUG_MODE and RUIN.DEBUG_FIRST_SPAWN_DELAY or RUIN.FIRST_SPAWN_DELAY
	RuinService.NextSpawnAt = Util.Now() + firstDelay
	task.spawn(function()
		while runId == myRun do
			tick()
			task.wait(TICK_INTERVAL)
		end
	end)
end

function RuinService.Stop()
	runId += 1
end

function RuinService.Cleanup()
	RuinService.Stop()
	for _, ruin in pairs(RuinService.Ruins) do
		CombatService.Unregister(ruin.Entity)
		if ruin.Model then
			ruin.Model:Destroy()
		end
	end
	table.clear(RuinService.Ruins)
	if folder then
		folder:Destroy()
		folder = nil
	end
	RuinService.NextSpawnAt = 0
end

function RuinService.Serialize()
	local list = {}
	for _, ruin in pairs(RuinService.Ruins) do
		table.insert(list, {
			Id = ruin.Id,
			Position = ruin.Position,
			Health = math.ceil(ruin.Entity.Health),
			MaxHealth = ruin.Entity.MaxHealth,
		})
	end
	return list
end

return RuinService
