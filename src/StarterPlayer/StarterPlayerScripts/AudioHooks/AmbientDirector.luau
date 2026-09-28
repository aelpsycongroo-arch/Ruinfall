--[[
	AmbientDirector - makes the world breathe without being noisy.

	Once per second it picks a zone for the local character (AudioConfig.AmbientZones):
	  Hall    hub hall / lobby between matches
	  Base    near a team flag (camp fire, calm)
	  Cursed  near a monster camp or the ruined arena centre (drones, whispers, crows)
	  Forest  everywhere else (wind, birds, leaves, distant howls)
	Each zone has up to two looping beds (cross-faded on zone change) and a list of short
	one-shots played at random intervals, random positions around the listener and with the
	randomised pitch / volume defined in AudioConfig.
	Add a zone: add an entry in AudioConfig.AmbientZones and a rule in pickZone().
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- State
local AmbientDirector = {}
local ctx, Manager, Zones = nil, nil, nil
local currentZone = nil
local nextOneShotAt = 0
local rng = Random.new()

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function pickZone(position)
	if ReplicatedStorage:GetAttribute("ServerRole") == "Hub" or not ctx.InMatch() then
		return "Hall"
	end
	if not position then
		return "Forest"
	end
	for _, model in ipairs(CollectionService:GetTagged("RF_Flag")) do
		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if part and (flat(part.Position) - flat(position)).Magnitude <= Zones.BaseRadius then
			return "Base"
		end
	end
	local gameState = ctx.ClientState.Game
	for _, camp in ipairs(gameState and gameState.Camps or {}) do
		if camp.Position and (flat(camp.Position) - flat(position)).Magnitude <= Zones.CampRadius then
			return "Cursed"
		end
	end
	if flat(position).Magnitude <= Zones.CenterRadius then
		return "Cursed"
	end
	return "Forest"
end

local function setZone(zoneName)
	if zoneName == currentZone then
		return
	end
	currentZone = zoneName
	local zone = Zones[zoneName]
	for index = 1, 2 do
		local bed = zone and zone.Beds[index]
		if bed then
			Manager:StartLoop("AmbientBed" .. index, bed, { Fade = 3 })
		else
			Manager:StopLoop("AmbientBed" .. index, 3)
		end
	end
	nextOneShotAt = os.clock() + rng:NextNumber(2, 5)
end

local function oneShot(position)
	local zone = Zones[currentZone]
	if not zone or #zone.OneShots == 0 or os.clock() < nextOneShotAt then
		return
	end
	nextOneShotAt = os.clock() + rng:NextNumber(zone.Interval[1], zone.Interval[2])
	local cue = zone.OneShots[rng:NextInteger(1, #zone.OneShots)]
	local around = position or Manager:GetListenerPosition()
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(14, 40)
	local at = around + Vector3.new(math.cos(angle) * distance, rng:NextNumber(2, 10), math.sin(angle) * distance)
	Manager:Play(cue, { Position = at, Source = "Ambient " .. currentZone })
end

function AmbientDirector.Init(context)
	ctx = context
	Manager = ctx.Manager
	Zones = ctx.Config.AmbientZones
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local position = root and root.Position
				setZone(pickZone(position))
				oneShot(position)
			end)
			if not ok then
				warn("[Audio] ambient", err)
			end
			task.wait(1)
		end
	end)
	return AmbientDirector
end

return AmbientDirector
