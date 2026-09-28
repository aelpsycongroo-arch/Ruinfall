-- RoyaleService: the 18-player free-for-all battle royale (its own game mode, reached
-- through the Royale hall gate). Only active when PlayerService.Mode == "Royale";
-- CraterArena team matches never touch it.
--   1. DEPLOY  - every player sees the map and clicks where to land. A picked spot blocks
--                Royale.SPAWN_EXCLUSION studs around it for everybody else. Bots pick too;
--                anyone who has not picked when the timer ends lands on a random free spot.
--   2. LOOT    - no classes and no shop: everyone is a Wanderer. Ruins are scattered over
--                the map; breaking one spills class skills (Q) and items onto the ground.
--   3. ZONE    - the play zone shrinks in phases; outside it heroes lose a share of their
--                max health every second (true damage).
--   4. VICTORY - no respawns. The last hero standing wins.

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
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))
local RuinService = require(script.Parent:WaitForChild("RuinService"))
local LootService = require(script.Parent:WaitForChild("LootService"))

-- Constants
local ROYALE = Constants.Royale
local WALL_SEGMENTS = 72
local WALL_HEIGHT = 70
local ZONE_COLOR = Color3.fromRGB(170, 80, 255)

-- State
local RoyaleService = {}
RoyaleService.Active = false
RoyaleService.Picks = {} -- [participantId] = Vector3
RoyaleService.DeployEndsAt = 0
RoyaleService.Zone = nil -- { Center, Radius, From*, To*, Phase, State, PhaseEndsAt }

local random = Random.new()
local runId = 0
local wallFolder = nil
local wallSegments = {}
local lootTable = nil
local nextRuinAt = 0
local initialized = false

-- Loot ----------------------------------------------------------------------------------
local function buildLootTable()
	local items = {}
	for id, item in pairs(ItemDefinitions.Items) do
		if item.SlotType == "Mythic" or item.SlotType == "Boots" or item.SlotType == "Passive" then
			table.insert(items, id)
		end
	end
	table.sort(items)
	return items
end

local function rollLoot()
	if random:NextNumber() < ROYALE.SKILL_CHANCE then
		local order = ClassDefinitions.Order
		return "Skill", order[random:NextInteger(1, #order)]
	end
	lootTable = lootTable or buildLootTable()
	return "Item", lootTable[random:NextInteger(1, #lootTable)]
end

local function spillRuinLoot(position)
	for index = 1, ROYALE.LOOT_PER_RUIN do
		local kind, key = rollLoot()
		local offset = Util.RotateY(Vector3.new(0, 0, 4.5), (index / ROYALE.LOOT_PER_RUIN) * math.pi * 2 + random:NextNumber(0, 1))
		LootService.Spawn(kind, key, position + offset)
	end
	if random:NextNumber() < 0.5 then
		LootService.Spawn("Potion", "Potion", position)
	end
end

-- Zone ------------------------------------------------------------------------------------
local function zoneAt(now)
	local zone = RoyaleService.Zone
	if zone.State == "Shrinking" then
		local t = math.clamp(1 - (zone.PhaseEndsAt - now) / zone.ShrinkTime, 0, 1)
		zone.Center = zone.FromCenter:Lerp(zone.ToCenter, t)
		zone.Radius = zone.FromRadius + (zone.ToRadius - zone.FromRadius) * t
	end
	return zone.Center, zone.Radius
end

local function buildWall()
	wallFolder = Instance.new("Folder")
	wallFolder.Name = "ZoneWall"
	wallFolder.Parent = MapGenerator.Current and MapGenerator.Current.Folder or workspace
	table.clear(wallSegments)
	for index = 1, WALL_SEGMENTS do
		local part = Instance.new("Part")
		part.Name = "ZoneWall"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = ZONE_COLOR
		part.Transparency = 0.05
		part.Parent = wallFolder
		wallSegments[index] = part
	end
end

local function updateWall(center, radius)
	if not wallFolder then
		return
	end
	local width = 2 * math.pi * math.max(radius, 1) / WALL_SEGMENTS + 0.6
	for index, part in ipairs(wallSegments) do
		local angle = (index - 0.5) * 2 * math.pi / WALL_SEGMENTS
		local position = center + Util.RotateY(Vector3.new(0, 0, radius), angle)
		part.Size = Vector3.new(width, WALL_HEIGHT, 1)
		part.CFrame = CFrame.lookAt(Vector3.new(position.X, WALL_HEIGHT / 2 - 1, position.Z), Vector3.new(center.X, WALL_HEIGHT / 2 - 1, center.Z))
		part.Transparency = radius < 1 and 1 or 0.05
	end
end

-- the next circle lies fully inside the current one
local function pickNextCenter(center, radius, nextRadius)
	local slack = math.max(0, radius - nextRadius)
	local offset = Util.RotateY(Vector3.new(0, 0, math.sqrt(random:NextNumber()) * slack), random:NextNumber(0, math.pi * 2))
	return Vector3.new(center.X + offset.X, 0, center.Z + offset.Z)
end

local function startPhase(index, now)
	local zone = RoyaleService.Zone
	local phase = ROYALE.ZONE_PHASES[index]
	zone.Phase = index
	if not phase then
		zone.State = "Final"
		zone.PhaseEndsAt = 0
		return
	end
	zone.State = "Waiting"
	zone.PhaseEndsAt = now + (index == 1 and ROYALE.ZONE_START_DELAY or phase.Wait)
	zone.DamagePercent = index == 1 and 0.01 or ROYALE.ZONE_PHASES[index - 1].DamagePercent
	zone.NextRadius = MapGenerator.Current.Radius * phase.Radius
	zone.NextCenter = pickNextCenter(zone.Center, zone.Radius, zone.NextRadius)
end

local function tickZone(now)
	local zone = RoyaleService.Zone
	if zone.State == "Waiting" and now >= zone.PhaseEndsAt then
		local phase = ROYALE.ZONE_PHASES[zone.Phase]
		zone.State = "Shrinking"
		zone.ShrinkTime = phase.Shrink
		zone.PhaseEndsAt = now + phase.Shrink
		zone.FromCenter, zone.FromRadius = zone.Center, zone.Radius
		zone.ToCenter, zone.ToRadius = zone.NextCenter, zone.NextRadius
		zone.DamagePercent = phase.DamagePercent
		Net.Notify(nil, "THE ZONE IS CLOSING", "Danger", { Banner = true, Sub = "Move inside the purple ring" })
	elseif zone.State == "Shrinking" and now >= zone.PhaseEndsAt then
		zoneAt(now)
		zone.Center, zone.Radius = zone.ToCenter, zone.ToRadius
		startPhase(zone.Phase + 1, now)
		if zone.State == "Waiting" then
			Net.Notify(nil, string.format("Zone stable - next shrink in %ds", math.floor(zone.PhaseEndsAt - now)), "Warning")
		end
	end
	local center, radius = zoneAt(now)
	updateWall(center, radius)
	-- storm damage (true damage, % of max health per second)
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		local entity = participant.Entity
		if entity and entity.Alive and Util.FlatDistance(CombatService.GetPosition(entity), center) > radius then
			CombatService.ApplyDamage(nil, entity, entity.MaxHealth * zone.DamagePercent * ROYALE.ZONE_TICK, { IgnoreArmor = true, Zone = true })
		end
	end
	-- keep loot flowing: a fresh ruin inside the zone every interval
	if now >= nextRuinAt and radius > 30 then
		nextRuinAt = now + ROYALE.RUIN_RESPAWN_INTERVAL
		RuinService.SpawnRuin({ Center = center, Radius = radius * 0.85, Health = ROYALE.RUIN_HEALTH })
	end
end

-- Deploy (landing spot selection) -----------------------------------------------------------
local function isSpotValid(position, participantId, exclusion)
	local mapData = MapGenerator.Current
	if not mapData then
		return false
	end
	if Util.Flat(position).Magnitude > mapData.Radius - ROYALE.SPAWN_EDGE_MARGIN then
		return false
	end
	if not MapGenerator.IsSpawnClear(position) then
		return false
	end
	for id, other in pairs(RoyaleService.Picks) do
		if id ~= participantId and Util.FlatDistance(other, position) < (exclusion or ROYALE.SPAWN_EXCLUSION) then
			return false
		end
	end
	return true
end

local function randomFreeSpot(participantId)
	local mapData = MapGenerator.Current
	for _, exclusion in ipairs({ ROYALE.SPAWN_EXCLUSION, ROYALE.SPAWN_EXCLUSION * 0.6, ROYALE.SPAWN_EXCLUSION * 0.3, 8 }) do
		for _ = 1, 150 do
			local position = Util.RotateY(Vector3.new(0, 0, math.sqrt(random:NextNumber()) * (mapData.Radius - ROYALE.SPAWN_EDGE_MARGIN)), random:NextNumber(0, math.pi * 2))
			if isSpotValid(position, participantId, exclusion) then
				return position
			end
		end
	end
	return Vector3.new(0, 0, 0)
end

function RoyaleService.Pick(participant, position)
	if not RoyaleService.Active or Util.Now() > RoyaleService.DeployEndsAt then
		return false, "Landing selection is closed"
	end
	local flat = Vector3.new(position.X, 0, position.Z)
	if not isSpotValid(flat, participant.Id) then
		return false, "You can't land there - too close to another player or blocked"
	end
	RoyaleService.Picks[participant.Id] = flat
	return true
end

-- Runs the deploy phase: returns { [participant] = landing position } when the timer ends.
function RoyaleService.RunDeploy(onChanged)
	RoyaleService.DeployEndsAt = Util.Now() + ROYALE.DEPLOY_TIME
	table.clear(RoyaleService.Picks)
	-- bots choose at random moments during the countdown
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.IsBot then
			task.delay(random:NextNumber(2, ROYALE.DEPLOY_TIME - 3), function()
				if RoyaleService.Active and Util.Now() < RoyaleService.DeployEndsAt and not RoyaleService.Picks[participant.Id] then
					RoyaleService.Picks[participant.Id] = randomFreeSpot(participant.Id)
					if onChanged then
						onChanged()
					end
				end
			end)
		end
	end
	while Util.Now() < RoyaleService.DeployEndsAt and RoyaleService.Active do
		task.wait(0.25)
	end
	local landing = {}
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		local spot = RoyaleService.Picks[participant.Id]
		if not spot then
			spot = randomFreeSpot(participant.Id)
			RoyaleService.Picks[participant.Id] = spot
			if participant.Player then
				Net.Notify(participant.Player, "No spot chosen - you land somewhere random", "Warning")
			end
		end
		landing[participant] = spot
	end
	return landing
end

-- Victory -------------------------------------------------------------------------------------
function RoyaleService.CountAlive()
	local alive, last = 0, nil
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.State == "Alive" or participant.Spawning then
			alive += 1
			last = participant
		end
	end
	return alive, last
end

-- Public API ------------------------------------------------------------------------------
function RoyaleService.Init()
	if initialized then
		return
	end
	initialized = true
	CombatService.EntityDied:Connect(function(entity)
		if RoyaleService.Active and entity.Kind == "Ruin" then
			spillRuinLoot(entity.Position or CombatService.GetPosition(entity))
		end
	end)
end

function RoyaleService.Setup(mapData, seed)
	RoyaleService.Cleanup()
	RoyaleService.Active = true
	random = Random.new(seed + 4242)
	lootTable = nil
	RoyaleService.Zone = {
		Center = Vector3.zero, Radius = mapData.Radius, Phase = 0, State = "Idle", PhaseEndsAt = 0, DamagePercent = 0,
	}
	buildWall()
	updateWall(Vector3.zero, mapData.Radius)
end

function RoyaleService.Start()
	runId += 1
	local myRun = runId
	local now = Util.Now()
	for _ = 1, ROYALE.START_RUINS do
		RuinService.SpawnRuin({ Health = ROYALE.RUIN_HEALTH })
	end
	nextRuinAt = now + ROYALE.RUIN_RESPAWN_INTERVAL
	startPhase(1, now)
	task.spawn(function()
		while runId == myRun do
			task.wait(ROYALE.ZONE_TICK)
			if runId ~= myRun then
				break
			end
			local ok, err = pcall(tickZone, Util.Now())
			if not ok then
				warn("[Ruinfall] Royale zone error:", err)
			end
		end
	end)
end

function RoyaleService.Stop()
	runId += 1
end

function RoyaleService.Cleanup()
	RoyaleService.Stop()
	RoyaleService.Active = false
	table.clear(RoyaleService.Picks)
	RoyaleService.Zone = nil
	RoyaleService.DeployEndsAt = 0
	if wallFolder then
		wallFolder:Destroy()
		wallFolder = nil
	end
	table.clear(wallSegments)
end

-- zone info for bots (current circle and where it is heading)
function RoyaleService.GetZone()
	local zone = RoyaleService.Zone
	if not zone then
		return nil
	end
	local center, radius = zoneAt(Util.Now())
	return { Center = center, Radius = radius, NextCenter = zone.NextCenter or center, NextRadius = zone.NextRadius or radius }
end

function RoyaleService.Serialize()
	if not RoyaleService.Active then
		return nil
	end
	local picks = {}
	for id, position in pairs(RoyaleService.Picks) do
		local participant = PlayerService.GetParticipantById(id)
		table.insert(picks, { Id = id, Name = participant and participant.Name or id, Team = participant and participant.Team or 0, X = position.X, Z = position.Z })
	end
	local zone = RoyaleService.Zone
	local zoneInfo = nil
	if zone then
		local center, radius = zoneAt(Util.Now())
		zoneInfo = {
			X = center.X, Z = center.Z, Radius = radius,
			NextX = zone.NextCenter and zone.NextCenter.X or center.X, NextZ = zone.NextCenter and zone.NextCenter.Z or center.Z,
			NextRadius = zone.NextRadius or radius, State = zone.State, Phase = zone.Phase, PhaseEndsAt = zone.PhaseEndsAt,
			PhaseCount = #ROYALE.ZONE_PHASES,
		}
	end
	local alive = RoyaleService.CountAlive()
	return {
		Picks = picks,
		DeployEndsAt = RoyaleService.DeployEndsAt,
		Exclusion = ROYALE.SPAWN_EXCLUSION,
		EdgeMargin = ROYALE.SPAWN_EDGE_MARGIN,
		MapRadius = MapGenerator.Current and MapGenerator.Current.Radius or ROYALE.MAP_RADIUS,
		Zone = zoneInfo,
		Alive = alive,
		Loot = LootService.Serialize(),
	}
end

return RoyaleService
