-- VisibilityService: server-authoritative fog of war for heroes.
-- An enemy hero is visible to a team when any living teammate (or the team's
-- intact flag) is within vision range with clear line of sight, the enemy is
-- not stealthed, and - if the enemy stands in brush - the viewer is in the same
-- brush patch or within reveal range. Clients only receive visible ids.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local VISION = Constants.Vision

-- State
local VisibilityService = {}
local visibleByTeam = {} -- [team] = { [entityId] = true }
local activeTeams = {}
local lastSent = setmetatable({}, { __mode = "k" }) -- [player] = key
local runId = 0

-- Functions
local function canSee(viewer, target)
	local distance = Util.FlatDistance(viewer.Position, target.Position)
	if distance > viewer.Radius then
		return false
	end
	if target.Brush and target.Brush ~= viewer.Brush and distance > VISION.BRUSH_REVEAL_RANGE then
		return false
	end
	return CombatService.HasLineOfSight(viewer.Position, target.Position)
end

local function collectHeroes()
	local heroes = {}
	for _, entity in pairs(CombatService.Entities) do
		if entity.Kind == "Hero" and entity.Alive and entity.Root and entity.Root.Parent then
			local position = entity.Root.Position
			local brush = MapGenerator.GetBrushZoneIndex(position)
			local inBrush = brush ~= nil
			if entity.Model:GetAttribute("InBrush") ~= inBrush then
				entity.Model:SetAttribute("InBrush", inBrush)
			end
			entity.BrushIndex = brush
			table.insert(heroes, { Entity = entity, Position = position, Brush = brush })
		end
	end
	return heroes
end

local function update()
	local heroes = collectHeroes()
	for _, team in ipairs(activeTeams) do
		local viewers = {}
		for _, hero in ipairs(heroes) do
			if hero.Entity.Team == team then
				table.insert(viewers, { Position = hero.Position, Radius = VISION.RADIUS, Brush = hero.Brush })
			end
		end
		local baseState = BaseService.GetState(team)
		if baseState and baseState.FlagState == "Intact" and not baseState.Eliminated then
			table.insert(viewers, { Position = baseState.Base.Position, Radius = Constants.Flag.VISION_RADIUS })
		end
		local visible = {}
		for _, hero in ipairs(heroes) do
			local entity = hero.Entity
			-- stealthed heroes stay hidden unless revealed to this team (True Sight passive)
			if entity.Team ~= team and (not CombatService.IsStealthed(entity) or CombatService.IsRevealedTo(entity, team)) then
				for _, viewer in ipairs(viewers) do
					if canSee(viewer, hero) then
						visible[entity.Id] = true
						break
					end
				end
			end
		end
		visibleByTeam[team] = visible
	end

	-- Send each client only what its team can see
	for _, player in ipairs(Players:GetPlayers()) do
		local participant = PlayerService.GetParticipantByPlayer(player)
		local revealAll = not participant or participant.Spectator or participant.State == "Eliminated"
		local ids = {}
		if revealAll then
			for _, hero in ipairs(heroes) do
				if not CombatService.IsStealthed(hero.Entity) then
					table.insert(ids, hero.Entity.Id)
				end
			end
		else
			for id in pairs(visibleByTeam[participant.Team] or {}) do
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		-- stealthed enemies this player's team can see anyway (True Sight): drawn and targetable
		local revealed = {}
		if not revealAll then
			for _, id in ipairs(ids) do
				local entity = CombatService.GetEntity(id)
				if entity and CombatService.IsStealthed(entity) then
					table.insert(revealed, id)
				end
			end
		end
		local key = (revealAll and "*" or "") .. table.concat(ids, ",") .. "|" .. table.concat(revealed, ",")
		if lastSent[player] ~= key then
			lastSent[player] = key
			Net.FireClient("VisibilityUpdate", player, { Ids = ids, RevealAll = revealAll, Revealed = revealed })
		end
	end
end

-- Public API ---------------------------------------------------------------------------
function VisibilityService.Init() end

function VisibilityService.Setup(_mapData, teams)
	activeTeams = table.clone(teams)
	visibleByTeam = {}
	for _, team in ipairs(teams) do
		visibleByTeam[team] = {}
	end
	table.clear(lastSent)
end

-- Can `team` currently see `entity`? Non-hero entities are always known.
function VisibilityService.CanTeamSee(team, entity)
	if not entity or entity.Team == team then
		return true
	end
	if entity.Kind ~= "Hero" then
		return true
	end
	local visible = visibleByTeam[team]
	return visible ~= nil and visible[entity.Id] == true
end

function VisibilityService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			update()
			task.wait(VISION.UPDATE_INTERVAL)
		end
	end)
end

function VisibilityService.Stop()
	runId += 1
end

function VisibilityService.Cleanup()
	VisibilityService.Stop()
	visibleByTeam = {}
	activeTeams = {}
	table.clear(lastSent)
	Net.FireAll("VisibilityUpdate", { Ids = {}, RevealAll = true })
end

return VisibilityService
