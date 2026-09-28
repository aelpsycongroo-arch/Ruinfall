-- FragmentService: Core Fragment pickups (dropped by monster camps) and the
-- heroes carrying them. Ownership is tracked only on the server.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local FRAGMENT_COLOR = Constants.Colors.Fragment
local TICK_INTERVAL = 0.15

-- State
local FragmentService = {}
FragmentService.Ground = {} -- [id] = { Id, Position, Model }
FragmentService.Picked = Util.Signal.new() -- (heroEntity)

local folder = nil
local nextId = 0
local runId = 0

-- Functions
local function newPart(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for key, value in pairs(properties) do
		part[key] = value
	end
	return part
end

local function buildPickup(position)
	local model = Instance.new("Model")
	model.Name = "CoreFragment"
	local crystal = newPart({
		Name = "Crystal",
		Size = Vector3.new(1.3, 2.2, 1.3),
		CFrame = CFrame.new(position + Vector3.new(0, 2.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = FRAGMENT_COLOR,
		Material = Enum.Material.Neon,
	})
	crystal.Parent = model
	local light = Instance.new("PointLight")
	light.Color = FRAGMENT_COLOR
	light.Range = 14
	light.Brightness = 2
	light.Parent = crystal
	local glow = newPart({
		Name = "Glow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 4.5, 4.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = FRAGMENT_COLOR,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	glow.Parent = model
	model.PrimaryPart = crystal
	CollectionService:AddTag(model, "RF_Fragment")
	model.Parent = folder
	return model
end

local function attachOrb(hero)
	local anchor = hero.Model and (hero.Model:FindFirstChild("Head") or hero.Root)
	if not anchor then
		return
	end
	local orb = Instance.new("Part")
	orb.Name = "FragmentOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.2, 1.2, 1.2)
	orb.Material = Enum.Material.Neon
	orb.Color = FRAGMENT_COLOR
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.Massless = true
	orb.CastShadow = false
	orb.CFrame = anchor.CFrame * CFrame.new(0, 2.3, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = orb
	weld.Parent = orb
	local light = Instance.new("PointLight")
	light.Color = FRAGMENT_COLOR
	light.Range = 9
	light.Brightness = 1.5
	light.Parent = orb
	orb.Parent = hero.Model
	hero.FragmentOrb = orb
end

-- Public API
function FragmentService.Init() end

function FragmentService.Setup(mapData)
	FragmentService.Cleanup()
	folder = Instance.new("Folder")
	folder.Name = "Fragments"
	folder.Parent = mapData.Folder
end

function FragmentService.CountOnGround()
	local count = 0
	for _ in pairs(FragmentService.Ground) do
		count += 1
	end
	return count
end

function FragmentService.Spawn(position, force)
	if not folder then
		return nil
	end
	if not force and FragmentService.CountOnGround() >= Constants.Fragment.MAX_ON_GROUND then
		return nil
	end
	nextId += 1
	local groundPosition = Vector3.new(position.X, 0, position.Z)
	local fragment = { Id = "Fragment_" .. nextId, Position = groundPosition, Model = buildPickup(groundPosition) }
	FragmentService.Ground[fragment.Id] = fragment
	Net.Effect("FragmentSpawn", { Position = groundPosition, Color = FRAGMENT_COLOR })
	return fragment
end

function FragmentService.Give(hero)
	hero.CarryingFragment = true
	attachOrb(hero)
	CombatService.PushHeroAttributes(hero)
	if hero.Player then
		Net.Notify(hero.Player, "CORE FRAGMENT ACQUIRED", "Fragment", { Banner = true, Sub = "Bring it to your flag to restore or repair it" })
	end
	FragmentService.Picked:Fire(hero)
end

function FragmentService.Consume(hero)
	hero.CarryingFragment = false
	if hero.FragmentOrb then
		hero.FragmentOrb:Destroy()
		hero.FragmentOrb = nil
	end
	CombatService.PushHeroAttributes(hero)
end

function FragmentService.OnHeroDied(hero)
	if not hero.CarryingFragment then
		return
	end
	hero.CarryingFragment = false
	FragmentService.Spawn(CombatService.GetPosition(hero), true)
	Net.Notify(PlayerService.GetTeamPlayers(hero.Team), "Your fragment carrier fell - the Core Fragment dropped!", "Warning")
end

function FragmentService.FindNearest(position, maxDistance)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, fragment in pairs(FragmentService.Ground) do
		local distance = Util.FlatDistance(position, fragment.Position)
		if distance < bestDistance then
			best, bestDistance = fragment, distance
		end
	end
	return best, bestDistance
end

local function tick()
	for id, fragment in pairs(FragmentService.Ground) do
		for _, entity in pairs(CombatService.Entities) do
			if entity.Kind == "Hero" and entity.Alive and not entity.CarryingFragment and entity.Root then
				if Util.FlatDistance(entity.Root.Position, fragment.Position) <= Constants.Fragment.PICKUP_RADIUS then
					FragmentService.Ground[id] = nil
					fragment.Model:Destroy()
					Net.Effect("Pickup", { Position = fragment.Position, Color = FRAGMENT_COLOR })
					FragmentService.Give(entity)
					break
				end
			end
		end
	end
end

function FragmentService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			tick()
			task.wait(TICK_INTERVAL)
		end
	end)
end

function FragmentService.Stop()
	runId += 1
end

function FragmentService.Cleanup()
	FragmentService.Stop()
	for _, fragment in pairs(FragmentService.Ground) do
		if fragment.Model then
			fragment.Model:Destroy()
		end
	end
	table.clear(FragmentService.Ground)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function FragmentService.Serialize()
	local list = {}
	for _, fragment in pairs(FragmentService.Ground) do
		table.insert(list, { Id = fragment.Id, Position = fragment.Position })
	end
	return list
end

return FragmentService
