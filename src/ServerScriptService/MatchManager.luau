-- MatchManager: the central match state machine.
-- LOBBY -> PREPARING -> GENERATING -> STARTING -> ACTIVE -> ENDING -> RESULTS -> LOBBY
-- Owns respawns, elimination, victory and full cleanup between matches.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(script.Parent:WaitForChild("Net"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local MapGenerator = require(script.Parent:WaitForChild("MapGenerator"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local FragmentService = require(script.Parent:WaitForChild("FragmentService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local RuinService = require(script.Parent:WaitForChild("RuinService"))
local VisibilityService = require(script.Parent:WaitForChild("VisibilityService"))
local BotService = require(script.Parent:WaitForChild("BotService"))

-- Constants
local STATE = Constants.MatchState
local MATCH = Constants.Match
local SPAWN_PROTECTION = 1.5

-- State
local MatchManager = {}
MatchManager.State = STATE.LOBBY
MatchManager.StateEndsAt = 0
MatchManager.Context = nil

local returnRequested = false
local matchRunId = 0
local random = Random.new()

-- Functions
function MatchManager.BuildState()
	local context = MatchManager.Context
	local host = PlayerService.GetHost()
	return {
		State = MatchManager.State,
		StateEndsAt = MatchManager.StateEndsAt,
		Mode = PlayerService.Mode,
		Difficulty = PlayerService.Difficulty,
		Participants = PlayerService.Serialize(),
		HostUserId = host and host.UserId or nil,
		Seed = context and context.Seed or nil,
		SlotCount = context and context.SlotCount or Constants.TeamModeSlots[PlayerService.Mode],
		ActiveTeams = context and context.ActiveTeams or nil,
		StartedAt = context and context.StartedAt or 0,
		Winner = context and context.Winner or nil,
		EliminationOrder = context and context.EliminationOrder or nil,
		Teams = BaseService.Serialize(),
		Ruins = RuinService.Serialize(),
		Camps = MonsterService.Serialize(),
		Fragments = FragmentService.Serialize(),
		NextRuinAt = RuinService.NextSpawnAt,
		LastStandDuration = Constants.LAST_STAND_DURATION,
		Debug = Constants.DEBUG_MODE,
	}
end

function MatchManager.Broadcast()
	Net.FireAll("GameStateUpdate", MatchManager.BuildState())
end

local function setState(state, duration)
	MatchManager.State = state
	MatchManager.StateEndsAt = duration and (Util.Now() + duration) or 0
	workspace:SetAttribute("MatchState", state)
	PlayerService.AcceptingPlayers = state == STATE.LOBBY
	if Constants.DEBUG_MODE then
		print("[Ruinfall] State ->", state)
	end
	MatchManager.Broadcast()
end

function MatchManager.SpawnParticipant(participant, point, frozen)
	local entity = PlayerService.SpawnHero(participant, point, Vector3.zero)
	if not entity then
		warn("[Ruinfall] Failed to spawn", participant.Name)
		return nil
	end
	if frozen then
		CombatService.Stun(entity, MATCH.START_COUNTDOWN + 5)
	else
		entity.Invulnerable = true
		task.delay(SPAWN_PROTECTION, function()
			entity.Invulnerable = false
		end)
	end
	if participant.IsBot then
		BotService.Attach(participant, entity)
	end
	return entity
end

local function describeKiller(killer)
	if not killer then
		return "the arena"
	elseif killer.Participant then
		return killer.Participant.Name
	elseif killer.Kind == "Monster" then
		return "a monster"
	elseif killer.Kind == "Flag" then
		return Constants.GetTeamName(killer.Team) .. "'s flag turret"
	end
	return "something"
end

local function onHeroDied(entity, killer)
	local participant = entity.Participant
	if not participant or participant.Entity ~= entity then
		return
	end
	FragmentService.OnHeroDied(entity)
	if participant.IsBot then
		BotService.Detach(participant)
	end
	PlayerService.DespawnHero(participant, 2.5)
	if MatchManager.State ~= STATE.ACTIVE then
		return
	end
	local team = participant.Team
	local baseState = BaseService.GetState(team)
	if BaseService.CanRespawn(team) then
		participant.State = "Dead"
		participant.RespawnAt = Util.Now() + MATCH.RESPAWN_TIME
	elseif baseState and baseState.FlagState == "LastStand" then
		participant.State = "Dead"
		participant.RespawnAt = nil
	else
		participant.State = "Eliminated"
		participant.RespawnAt = nil
	end
	PlayerService.SetPlayerAttributes(participant)
	Net.Notify(nil, string.format("%s was slain by %s", participant.Name, describeKiller(killer)), "Info")
	if participant.Player then
		if participant.State == "Eliminated" then
			Net.Notify(participant.Player, "ELIMINATED", "Danger", { Banner = true, Sub = "Your team is Flagless - no respawn. Spectating." })
		elseif participant.RespawnAt == nil then
			Net.Notify(participant.Player, "YOU DIED", "Warning", { Banner = true, Sub = "No respawn until a teammate restores the flag" })
		end
	end
	MatchManager.Broadcast()
end

function MatchManager.ProcessRespawns()
	local now = Util.Now()
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.State == "Dead" and not participant.Spawning then
			local team = participant.Team
			if BaseService.CanRespawn(team) then
				if not participant.RespawnAt then
					participant.RespawnAt = now + MATCH.RESPAWN_TIME
					PlayerService.SetPlayerAttributes(participant)
				elseif now >= participant.RespawnAt then
					participant.Spawning = true
					local point = BaseService.GetSpawnPoint(team, random:NextInteger(1, 6))
					task.spawn(function()
						MatchManager.SpawnParticipant(participant, point, false)
						participant.Spawning = false
					end)
				end
			else
				local state = BaseService.GetState(team)
				if not state or state.Eliminated or state.FlagState == "Lost" then
					participant.State = "Eliminated"
					participant.RespawnAt = nil
					PlayerService.SetPlayerAttributes(participant)
					if participant.Player then
						Net.Notify(participant.Player, "ELIMINATED", "Danger", { Banner = true, Sub = "Your flag could not be restored. Spectating." })
					end
				elseif participant.RespawnAt then
					participant.RespawnAt = nil
					PlayerService.SetPlayerAttributes(participant)
				end
			end
		end
	end
end

function MatchManager.CheckEliminations()
	local context = MatchManager.Context
	for _, team in ipairs(context.ActiveTeams) do
		if not context.EliminatedTeams[team] then
			local members = PlayerService.GetTeamMembers(team)
			local state = BaseService.GetState(team)
			local anyAlive = false
			for _, member in ipairs(members) do
				if member.State == "Alive" or member.Spawning then
					anyAlive = true
				end
			end
			local flagState = state and state.FlagState or "Lost"
			local eliminated = #members == 0 or (flagState == "Lost" and not anyAlive)
			if eliminated then
				context.EliminatedTeams[team] = true
				table.insert(context.EliminationOrder, team)
				BaseService.MarkEliminated(team)
				for _, member in ipairs(members) do
					if member.State ~= "Eliminated" then
						member.State = "Eliminated"
						member.RespawnAt = nil
						PlayerService.SetPlayerAttributes(member)
					end
				end
				Net.Notify(nil, Constants.GetTeamName(team) .. " HAS BEEN ELIMINATED", "Danger")
				MatchManager.Broadcast()
			end
		end
	end
end

function MatchManager.CheckVictory()
	local context = MatchManager.Context
	local remaining = {}
	for _, team in ipairs(context.ActiveTeams) do
		if not context.EliminatedTeams[team] then
			table.insert(remaining, team)
		end
	end
	if #remaining <= 1 then
		MatchManager.EndMatch(remaining[1])
	end
end

local function stopGameplay()
	BotService.Stop()
	MonsterService.Stop()
	RuinService.Stop()
	FragmentService.Stop()
	BaseService.Stop()
	VisibilityService.Cleanup()
	CombatService.Stop()
end

function MatchManager.Cleanup()
	BotService.Cleanup()
	MonsterService.Cleanup()
	RuinService.Cleanup()
	FragmentService.Cleanup()
	BaseService.Cleanup()
	VisibilityService.Cleanup()
	CombatService.EndMatch()
	PlayerService.ResetForLobby()
	MapGenerator.Clear()
	local heroes = workspace:FindFirstChild("Heroes")
	if heroes then
		heroes:ClearAllChildren()
	end
	MatchManager.Context = nil
end

function MatchManager.EndMatch(winner)
	if MatchManager.State ~= STATE.ACTIVE then
		return
	end
	local context = MatchManager.Context
	context.Winner = winner
	stopGameplay()
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.Entity and participant.Entity.Alive then
			participant.Entity.Invulnerable = true
			CombatService.Stun(participant.Entity, 120)
		end
	end
	local winnerName = winner and Constants.GetTeamName(winner) or "Nobody"
	print(string.format("[Ruinfall] Match over | seed=%d winner=%s duration=%ds", context.Seed, winnerName, math.floor(Util.Now() - context.StartedAt)))
	setState(STATE.ENDING, MATCH.ENDING_DURATION)
	task.wait(MATCH.ENDING_DURATION)
	returnRequested = false
	setState(STATE.RESULTS, MATCH.RESULTS_DURATION)
	local deadline = MatchManager.StateEndsAt
	while Util.Now() < deadline and not returnRequested do
		task.wait(0.2)
	end
	MatchManager.Cleanup()
	setState(STATE.LOBBY)
end

function MatchManager.RunMatch()
	matchRunId += 1
	local myRun = matchRunId
	returnRequested = false
	setState(STATE.PREPARING)

	local activeTeams, slotCount = PlayerService.AssignTeams()
	if #activeTeams < 2 then
		Net.Notify(nil, "At least two teams are required", "Danger")
		setState(STATE.LOBBY)
		return
	end
	local seed = Constants.FORCED_SEED or random:NextInteger(1, 2 ^ 30)
	local context = {
		Seed = seed,
		SlotCount = slotCount,
		ActiveTeams = activeTeams,
		Mode = PlayerService.Mode,
		StartedAt = 0,
		Winner = nil,
		EliminatedTeams = {},
		EliminationOrder = {},
	}
	MatchManager.Context = context
	print(string.format("[Ruinfall] Preparing match | seed=%d mode=%s teams=%s participants=%d",
		seed, context.Mode, table.concat(activeTeams, ","), #PlayerService.GetParticipants()))

	setState(STATE.GENERATING)
	local ok, err = pcall(function()
		local mapData = MapGenerator.Generate(seed, slotCount, activeTeams)
		context.Map = mapData
		CombatService.BeginMatch(mapData)
		BaseService.Setup(mapData, activeTeams)
		FragmentService.Setup(mapData)
		MonsterService.Setup(mapData)
		RuinService.Setup(mapData, seed)
		VisibilityService.Setup(mapData, activeTeams)
	end)
	if not ok then
		warn("[Ruinfall] Match setup failed:", err)
		Net.Notify(nil, "Match setup failed - see server output", "Danger")
		MatchManager.Cleanup()
		setState(STATE.LOBBY)
		return
	end

	setState(STATE.STARTING, MATCH.START_COUNTDOWN)
	local pending = 0
	local spawnIndex = {}
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		local team = participant.Team
		spawnIndex[team] = (spawnIndex[team] or 0) + 1
		local point = BaseService.GetSpawnPoint(team, spawnIndex[team])
		pending += 1
		task.spawn(function()
			local spawnOk, spawnErr = pcall(MatchManager.SpawnParticipant, participant, point, true)
			if not spawnOk then
				warn("[Ruinfall] Spawn error:", spawnErr)
			end
			pending -= 1
		end)
	end
	local waitStarted = os.clock()
	while pending > 0 and os.clock() - waitStarted < 10 do
		task.wait(0.1)
	end
	while Util.Now() < MatchManager.StateEndsAt do
		task.wait(0.1)
	end
	if matchRunId ~= myRun then
		return
	end

	context.StartedAt = Util.Now()
	setState(STATE.ACTIVE)
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		if participant.Entity then
			CombatService.ClearStun(participant.Entity)
		elseif participant.State ~= "Alive" then
			participant.State = "Dead"
			participant.RespawnAt = Util.Now() + 1
		end
	end
	CombatService.Start()
	BaseService.Start()
	FragmentService.Start()
	MonsterService.Start()
	RuinService.Start()
	VisibilityService.Start()
	BotService.Start()
	Net.Notify(nil, "FIGHT!", "Info", { Banner = true, Sub = "Destroy enemy flags. Protect your own." })

	while MatchManager.State == STATE.ACTIVE and matchRunId == myRun do
		task.wait(0.25)
		local loopOk, loopErr = pcall(function()
			MatchManager.ProcessRespawns()
			MatchManager.CheckEliminations()
			MatchManager.CheckVictory()
		end)
		if not loopOk then
			warn("[Ruinfall] Match loop error:", loopErr)
		end
	end
end

-- Public API ---------------------------------------------------------------------------
function MatchManager.Init()
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.Kind == "Hero" then
			onHeroDied(entity, killer)
		end
	end)
	PlayerService.Changed:Connect(function()
		if MatchManager.State == STATE.LOBBY then
			MatchManager.Broadcast()
		end
	end)
	setState(STATE.LOBBY)
	task.spawn(function()
		while true do
			task.wait(MATCH.BROADCAST_INTERVAL)
			MatchManager.Broadcast()
		end
	end)
end

function MatchManager.RequestStart(player)
	if MatchManager.State ~= STATE.LOBBY then
		return false, "A match is already running"
	end
	if player and not PlayerService.IsHost(player) then
		return false, "Only the host can start the match"
	end
	if #PlayerService.GetParticipants() < Constants.MIN_PARTICIPANTS then
		return false, "Add at least one bot or player (2 participants minimum)"
	end
	task.spawn(MatchManager.RunMatch)
	return true
end

function MatchManager.RequestReturn(player)
	if MatchManager.State == STATE.RESULTS and (not player or PlayerService.IsHost(player)) then
		returnRequested = true
		return true
	end
	return false
end

return MatchManager
