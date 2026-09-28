-- GameServer: Ruinfall server entry point.
-- Server roles: public servers are the HUB (Ruinfall Hall, HubService) where players pick
-- a lobby; reserved servers (teleported lobbies) are MATCH servers that run the game.
-- Initializes services, lighting and validates every client request.
-- Clients only ever send intents ("I tried to attack toward X"); the server
-- decides everything else.

-- Services
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local Util = require(Shared:WaitForChild("Util"))

local Net = require(ServerScriptService:WaitForChild("Net"))
Net.Init()

local CombatService = require(ServerScriptService:WaitForChild("CombatService"))
local PlayerService = require(ServerScriptService:WaitForChild("PlayerService"))
local AbilityService = require(ServerScriptService:WaitForChild("AbilityService"))
local FragmentService = require(ServerScriptService:WaitForChild("FragmentService"))
local BaseService = require(ServerScriptService:WaitForChild("BaseService"))
local MonsterService = require(ServerScriptService:WaitForChild("MonsterService"))
local RuinService = require(ServerScriptService:WaitForChild("RuinService"))
local VisibilityService = require(ServerScriptService:WaitForChild("VisibilityService"))
local BotService = require(ServerScriptService:WaitForChild("BotService"))
local ShopService = require(ServerScriptService:WaitForChild("ShopService"))
local ItemService = require(ServerScriptService:WaitForChild("ItemService"))
local PassiveService = require(ServerScriptService:WaitForChild("PassiveService"))
local CreepService = require(ServerScriptService:WaitForChild("CreepService"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local HubService = require(ServerScriptService:WaitForChild("HubService"))
local LootService = require(ServerScriptService:WaitForChild("LootService"))
local RoyaleService = require(ServerScriptService:WaitForChild("RoyaleService"))

-- Constants
local STATE = Constants.MatchState
local REQUESTS_PER_SECOND = Constants.Combat.REQUESTS_PER_SECOND

-- State
local buckets = setmetatable({}, { __mode = "k" })

-- Functions
local function applyLighting()
	-- Warm late-afternoon sun, slightly cool ambient shadows (medieval battlefield look)
	Lighting.ClockTime = 15.6
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(78, 84, 98)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 138)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 232, 196)
	Lighting.ColorShift_Bottom = Color3.fromRGB(70, 78, 95)
	Lighting.ShadowSoftness = 0.35
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000
	local function ensure(className, name)
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local instance = Instance.new(className)
		instance.Name = name
		instance.Parent = Lighting
		return instance
	end
	local atmosphere = ensure("Atmosphere", "RuinfallAtmosphere")
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(205, 196, 176)
	atmosphere.Decay = Color3.fromRGB(120, 112, 100)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2
	local bloom = ensure("BloomEffect", "RuinfallBloom")
	bloom.Intensity = 0.2
	bloom.Size = 20
	bloom.Threshold = 2
	local grading = ensure("ColorCorrectionEffect", "RuinfallGrading")
	grading.Brightness = 0.02
	grading.Contrast = 0.1
	grading.Saturation = 0.12
	grading.TintColor = Color3.fromRGB(255, 249, 238)
end

-- Token bucket: ignore floods of requests without kicking anyone
local function allowRequest(player)
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { Tokens = REQUESTS_PER_SECOND, Last = now }
		buckets[player] = bucket
	end
	bucket.Tokens = math.min(REQUESTS_PER_SECOND, bucket.Tokens + (now - bucket.Last) * REQUESTS_PER_SECOND)
	bucket.Last = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

local function getActiveHero(player)
	if MatchManager.State ~= STATE.ACTIVE then
		return nil
	end
	local participant = PlayerService.GetParticipantByPlayer(player)
	local entity = participant and participant.Entity
	if entity and entity.Alive and entity.Player == player then
		return entity
	end
	return nil
end

local function clampAim(entity, aimPosition)
	local origin = CombatService.GetPosition(entity)
	local offset = Util.Flat(aimPosition - origin)
	if offset.Magnitude > Constants.Combat.MAX_AIM_DISTANCE then
		offset = offset.Unit * Constants.Combat.MAX_AIM_DISTANCE
	end
	return Vector3.new(origin.X + offset.X, origin.Y, origin.Z + offset.Z)
end

-- Initialization ------------------------------------------------------------------------
local matchInitialized = false

-- Match servers: apply the lobby's team mode from the hub's TeleportData
local teleportModeApplied = false
local function applyTeleportData(player)
	if teleportModeApplied then
		return
	end
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local data = ok and joinData and joinData.TeleportData
	if type(data) == "table" and type(data.Mode) == "string" and Constants.TeamModeSlots[data.Mode] then
		teleportModeApplied = true
		PlayerService.SetMode(data.Mode)
		PlayerService.LockedMode = data.Mode -- this server keeps its gate's game mode
	end
end

local function initMatchRole()
	if matchInitialized then
		return
	end
	matchInitialized = true
	ReplicatedStorage:SetAttribute("ServerRole", "Match")
	PlayerService.Init()
	CombatService.Init()
	AbilityService.Init()
	FragmentService.Init()
	BaseService.Init()
	MonsterService.Init()
	RuinService.Init()
	VisibilityService.Init()
	BotService.Init()
	ShopService.Init()
	ItemService.Init()
	PassiveService.Init()
	CreepService.Init()
	MatchManager.Init()
	Players.PlayerAdded:Connect(applyTeleportData)
	for _, player in ipairs(Players:GetPlayers()) do
		applyTeleportData(player)
	end
end

applyLighting()
ReplicatedStorage:SetAttribute("DebugMode", Constants.DEBUG_MODE)
ReplicatedStorage:SetAttribute("ReservedServer", game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
local serverRole = HubService.DetermineRole()
if serverRole == "Hub" then
	ReplicatedStorage:SetAttribute("ServerRole", "Hub")
	HubService.Init({
		-- Studio only (no teleporting): turn this server into the lobby's match server
		OnLocalStart = function(lobby)
			HubService.Teardown()
			initMatchRole()
			if lobby and lobby.Mode then
				PlayerService.SetMode(lobby.Mode)
				PlayerService.LockedMode = lobby.Mode
			end
			task.delay(1.5, MatchManager.Broadcast) -- clients finish switching UI first
		end,
	})
else
	initMatchRole()
end

-- Match servers: players can walk back to the Ruinfall Hall (a public hub server)
Net.Get("HubRequest").OnServerEvent:Connect(function(player, action)
	if action ~= "ReturnToHall" or not allowRequest(player) or HubService.IsActive() then
		return
	end
	if RunService:IsStudio() then
		Net.Notify(player, "Returning to the hall only works in the published game", "Warning")
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		Net.Notify(player, "Could not return to the hall: " .. tostring(err), "Warning")
	end
end)

-- Remote handlers ---------------------------------------------------------------------
Net.Get("LobbyRequest").OnServerEvent:Connect(function(player, action, value)
	if not allowRequest(player) or type(action) ~= "string" then
		return
	end
	if MatchManager.State ~= STATE.LOBBY then
		return
	end
	-- SetTeam is available to all players, not just the host
	if action == "SetTeam" and type(value) == "number" then
		PlayerService.SetTeam(player, value)
		return
	end
	if not PlayerService.IsHost(player) then
		Net.Notify(player, "Only the host can change match settings", "Warning")
		return
	end
	if action == "SetMode" and type(value) == "string" then
		PlayerService.SetMode(value)
	elseif action == "AddBot" then
		local bot, err = PlayerService.AddBot()
		if not bot then
			Net.Notify(player, err, "Warning")
		end
	elseif action == "RemoveBot" then
		PlayerService.RemoveBot()
	elseif action == "CycleBotClass" and type(value) == "string" then
		PlayerService.CycleBotClass(value)
	elseif action == "SetDifficulty" and type(value) == "string" then
		PlayerService.SetDifficulty(value)
	end
end)

Net.Get("SelectClass").OnServerEvent:Connect(function(player, classKey)
	if not allowRequest(player) or MatchManager.State ~= STATE.LOBBY then
		return
	end
	if ClassDefinitions.IsValid(classKey) then
		PlayerService.SetClass(player, classKey)
	end
end)

Net.Get("MatchRequest").OnServerEvent:Connect(function(player, action)
	if not allowRequest(player) or type(action) ~= "string" then
		return
	end
	if action == "Start" then
		local ok, err = MatchManager.RequestStart(player)
		if not ok then
			Net.Notify(player, err, "Danger")
		end
	elseif action == "ReturnToLobby" then
		MatchManager.RequestReturn(player)
	end
end)

Net.Get("AttackRequest").OnServerEvent:Connect(function(player, aimPosition)
	if not allowRequest(player) or not Util.IsFiniteVector(aimPosition) then
		return
	end
	local entity = getActiveHero(player)
	if entity then
		CombatService.PerformBasicAttack(entity, clampAim(entity, aimPosition))
	end
end)

Net.Get("AbilityRequest").OnServerEvent:Connect(function(player, slot, aimPosition, targetId)
	if not allowRequest(player) or not Util.IsFiniteVector(aimPosition) then
		return
	end
	local entity = getActiveHero(player)
	if not entity then
		return
	end
	if slot == "Q" then
		local ok, reason = AbilityService.Use(entity, clampAim(entity, aimPosition))
		if not ok and reason then
			Net.Notify(player, reason, "Warning")
		end
	elseif slot == "E" or slot == "R" or slot == "M2" then
		-- item abilities: mythic slot 1 -> E, slot 2 -> R, boot slot -> right mouse ("M2")
		if targetId ~= nil and type(targetId) ~= "string" then
			return
		end
		local index = (slot == "E" and 1) or (slot == "R" and 2) or 3
		local ok, reason = ItemService.UseSlot(entity, index, clampAim(entity, aimPosition), targetId)
		if not ok and reason and reason ~= "Cooldown" then
			Net.Notify(player, reason, "Warning")
		end
	end
end)

-- Health potions (both modes) and dropping unwanted gear (Royale)
Net.Get("LootRequest").OnServerEvent:Connect(function(player, action, value)
	if not allowRequest(player) or type(action) ~= "string" or MatchManager.State ~= STATE.ACTIVE then
		return
	end
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant then
		return
	end
	local ok, reason
	if action == "UsePotion" then
		ok, reason = LootService.UsePotion(participant)
	elseif action == "Drop" and (value == "Skill" or type(value) == "number") then
		ok, reason = LootService.Drop(participant, value)
	end
	if not ok and reason then
		Net.Notify(player, reason, "Warning")
	end
end)

-- Royale deploy: pick a landing spot on the map
Net.Get("RoyaleRequest").OnServerEvent:Connect(function(player, action, value)
	if not allowRequest(player) or action ~= "Pick" or MatchManager.State ~= STATE.DEPLOYING then
		return
	end
	if typeof(value) ~= "Vector3" or not Util.IsFiniteVector(value) then
		return
	end
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or participant.Spectator then
		return
	end
	local ok, reason = RoyaleService.Pick(participant, value)
	if ok then
		MatchManager.Broadcast()
	elseif reason then
		Net.Notify(player, reason, "Warning")
	end
end)

Net.Get("PlayerInput").OnServerEvent:Connect(function(player)
	allowRequest(player) -- reserved for future input types
end)

-- Debug / test harness (server-only BindableFunction) -------------------------------------
local debugFunction = ServerStorage:FindFirstChild("RuinfallDebug") or Instance.new("BindableFunction")
debugFunction.Name = "RuinfallDebug"
debugFunction.Parent = ServerStorage
debugFunction.OnInvoke = function(command, a, b, c, ...)
	-- tests drive the match directly: leave the hub hall first (Studio fallback)
	if command == "hubstate" then
		return { Role = ReplicatedStorage:GetAttribute("ServerRole"), HubActive = HubService.IsActive(), Lobbies = #HubService.Lobbies }
	elseif HubService.IsActive() then
		HubService.ForceLocalStart()
		task.wait(0.5)
	end
	if command == "skiphub" then
		return true
	elseif command == "state" then
		local lines = { "State=" .. MatchManager.State .. " Mode=" .. PlayerService.Mode }
		local context = MatchManager.Context
		if context then
			table.insert(lines, "Seed=" .. tostring(context.Seed) .. " Winner=" .. tostring(context.Winner))
		end
		for _, participant in ipairs(PlayerService.Serialize()) do
			local entity = PlayerService.GetParticipantById(participant.Id).Entity
			local extra = entity and string.format(" hp=%d pos=%s", entity.Health, tostring(CombatService.GetPosition(entity))) or ""
			local brain = BotService.GetBrain(participant.Id)
			table.insert(lines, string.format("%s %s team=%s class=%s state=%s K/D=%d/%d%s%s", participant.Id, participant.Name, tostring(participant.Team), participant.ClassKey, participant.State, participant.Stats.Kills, participant.Stats.Deaths, extra, brain and (" ai=" .. brain.State) or ""))
		end
		for _, team in ipairs(BaseService.Serialize()) do
			table.insert(lines, string.format("Team%d flag=%s hp=%d ls=%.1f secured=%s elim=%s", team.Team, team.FlagState, team.FlagHealth, team.LastStandRemaining, tostring(team.Secured), tostring(team.Eliminated)))
		end
		return table.concat(lines, "\n")
	elseif command == "mode" then
		return PlayerService.SetMode(a)
	elseif command == "addbot" then
		return PlayerService.AddBot() ~= nil
	elseif command == "removebot" then
		return PlayerService.RemoveBot()
	elseif command == "difficulty" then
		return PlayerService.SetDifficulty(a)
	elseif command == "class" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and ClassDefinitions.IsValid(b) then
			participant.ClassKey = b
			PlayerService.Changed:Fire()
			return true
		end
		return false
	elseif command == "swapclass" then
		-- Debug only: change class mid-match and respawn immediately at the team flag
		local participant = PlayerService.GetParticipantById(a)
		if participant and ClassDefinitions.IsValid(b) and participant.Entity then
			participant.ClassKey = b
			PlayerService.DespawnHero(participant, 0)
			participant.State = "Dead"
			participant.RespawnAt = Util.Now()
			return true
		end
		return false
	elseif command == "start" then
		return MatchManager.RequestStart(nil)
	elseif command == "return" then
		return MatchManager.RequestReturn(nil)
	elseif command == "damageflag" then
		local state = BaseService.GetState(a)
		if state and state.FlagEntity.Alive then
			CombatService.ApplyDamage(nil, state.FlagEntity, b or 100000, { IgnoreArmor = true })
			return true
		end
		return false
	elseif command == "killmonster" then
		-- ("killmonster", participantId?) kills the living camp monster nearest to that hero (death animation test)
		local killer = a and PlayerService.GetParticipantById(a)
		local killerEntity = killer and killer.Entity
		local best, bestDistance = nil, math.huge
		for _, entity in pairs(CombatService.Entities) do
			if entity.Kind == "Monster" and entity.Alive then
				local distance = killerEntity and (CombatService.GetPosition(entity) - CombatService.GetPosition(killerEntity)).Magnitude or 0
				if distance < bestDistance then
					best, bestDistance = entity, distance
				end
			end
		end
		if best then
			local name = best.Model and best.Model.Name or "?"
			CombatService.Kill(best, killerEntity)
			return name
		end
		return false
	elseif command == "kill" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			CombatService.Kill(participant.Entity, nil)
			return true
		end
		return false
	elseif command == "fragment" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity and not participant.Entity.CarryingFragment then
			FragmentService.Give(participant.Entity)
			return true
		end
		return false
	elseif command == "buff" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			CombatService.ApplyBuff(participant.Entity, b)
			return true
		end
		return false
	elseif command == "spawnruin" then
		return RuinService.SpawnRuin() ~= nil
	elseif command == "teleport" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			participant.Entity.MovementGraceUntil = Util.Now() + 2
			participant.Entity.Root.CFrame = CFrame.new(Vector3.new(b, 3.5, c))
			return true
		end
		return false
	elseif command == "freeze" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			CombatService.Stun(participant.Entity, b or 5)
			return true
		end
		return false
	elseif command == "god" then
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			participant.Entity.Invulnerable = b == true
			return true
		end
		return false
	elseif command == "entities" then
		local lines = {}
		for id, entity in pairs(CombatService.Entities) do
			table.insert(lines, string.format("%s team=%d hp=%d/%d alive=%s", id, entity.Team, entity.Health, entity.MaxHealth, tostring(entity.Alive)))
		end
		return table.concat(lines, "\n")
	-- Item / creep test commands (a = participant id) ------------------------------------
	elseif command == "gold" then
		local participant = PlayerService.GetParticipantById(a)
		if participant then
			PlayerService.AddGold(participant, b or 0)
			return PlayerService.GetGold(participant)
		end
		return false
	elseif command == "item" then
		-- ("item", participantId, action, arg1, arg2) - goes through the same validation as clients
		local participant = PlayerService.GetParticipantById(a)
		if not participant then
			return false, "no participant"
		end
		local player = participant.Player
		if b == "Buy" then
			return ItemService.Buy(player, participant, c, select(1, ...))
		elseif b == "Sell" then
			return ItemService.Sell(player, participant, c)
		elseif b == "Swap" then
			return ItemService.Swap(player, participant)
		elseif b == "Use" then
			local aim, targetId = ...
			return ItemService.UseSlot(participant.Entity, c, aim, targetId)
		elseif b == "Info" then
			local slot1, slot2, boots = ItemService.GetSlots(participant)
			local entity = participant.Entity
			return string.format("boots(RMB)=" .. tostring(boots) .. " gold=%d slot1(E)=%s slot2(R)=%s armor=%s speed=%s ad=%s hp=%s/%s", PlayerService.GetGold(participant),
				tostring(slot1), tostring(slot2), entity and tostring(entity.Armor) or "-", entity and tostring(entity.BaseSpeed) or "-",
				entity and tostring(entity.BonusAttackDamage) or "-", entity and tostring(math.floor(entity.Health)) or "-", entity and tostring(entity.MaxHealth) or "-")
		end
		return false, "unknown item action"
	elseif command == "hit" then
		-- ("hit", sourceParticipantId, targetParticipantId, amount, ignoreArmor) raw damage between heroes
		local source = PlayerService.GetParticipantById(a)
		local target = PlayerService.GetParticipantById(b)
		if source and target and source.Entity and target.Entity then
			local ignoreArmor = ...
			return CombatService.ApplyDamage(source.Entity, target.Entity, c, { IgnoreArmor = ignoreArmor == true })
		end
		return false
	elseif command == "hero" then
		local participant = PlayerService.GetParticipantById(a)
		local entity = participant and participant.Entity
		if not entity then
			return false
		end
		return { Id = entity.Id, Health = entity.Health, MaxHealth = entity.MaxHealth, StunnedUntil = entity.StunnedUntil, Now = Util.Now(),
			Position = CombatService.GetPosition(entity), Team = entity.Team, Alive = entity.Alive, Gold = PlayerService.GetGold(participant) }
	elseif command == "passives" then
		-- ("passives", participantId) equipped passive effects + their live state
		local participant = PlayerService.GetParticipantById(a)
		local entity = participant and participant.Entity
		return entity and PassiveService.Describe(entity) or false
	elseif command == "sethealth" then
		-- ("sethealth", participantId, fraction of max health)
		local participant = PlayerService.GetParticipantById(a)
		local entity = participant and participant.Entity
		if entity and entity.Alive then
			entity.Health = math.max(1, entity.MaxHealth * (b or 1))
			CombatService.SyncHealth(entity)
			return entity.Health
		end
		return false
	elseif command == "setmana" then
		-- ("setmana", participantId, mana)
		local participant = PlayerService.GetParticipantById(a)
		local entity = participant and participant.Entity
		if entity and entity.MaxMana then
			entity.Mana = math.clamp(b or 0, 0, entity.MaxMana)
			CombatService.SyncMana(entity)
			return entity.Mana
		end
		return false
	elseif command == "hitx" then
		-- ("hitx", sourceParticipantId, targetParticipantId, amount, infoTable) damage with info flags
		local source = PlayerService.GetParticipantById(a)
		local target = PlayerService.GetParticipantById(b)
		if source and target and source.Entity and target.Entity then
			local info = ...
			return CombatService.ApplyDamage(source.Entity, target.Entity, c, type(info) == "table" and info or {})
		end
		return false
	elseif command == "stealth" then
		-- ("stealth", participantId, seconds) make a hero invisible (True Sight tests)
		local participant = PlayerService.GetParticipantById(a)
		if participant and participant.Entity then
			CombatService.SetStealth(participant.Entity, b or 5)
			return true
		end
		return false
	elseif command == "assist" then
		-- ("assist", contributorParticipantId, deadHeroParticipantId) fire the assist event (Rewind tests)
		local contributor = PlayerService.GetParticipantById(a)
		local target = PlayerService.GetParticipantById(b)
		if contributor then
			CombatService.AssistGranted:Fire(contributor, target and target.Entity)
			return true
		end
		return false
	elseif command == "cooldowns" then
		-- ("cooldowns", participantId) seconds until Q / E / R are ready
		local participant = PlayerService.GetParticipantById(a)
		local entity = participant and participant.Entity
		if not entity then
			return false
		end
		local now = Util.Now()
		local readyAt = participant.ItemReadyAt or {}
		local mythics = participant.Mythics or {}
		local e, r = mythics[1], mythics[2]
		return { Q = entity.AbilityReadyAt - now, E = e and (readyAt[e] or 0) - now or 0, R = r and (readyAt[r] or 0) - now or 0 }
	elseif command == "attack" then
		-- ("attack", participantId, targetParticipantId) one basic attack aimed at the target (ignores cooldown)
		local participant = PlayerService.GetParticipantById(a)
		local target = PlayerService.GetParticipantById(b)
		if participant and participant.Entity and target and target.Entity then
			participant.Entity.LastAttackAt = participant.Entity.LastAttackAt - 10
			return CombatService.PerformBasicAttack(participant.Entity, CombatService.GetPosition(target.Entity))
		end
		return false
	elseif command == "lastreflect" then
		return CombatService.LastReflection
	elseif command == "itemdebug" then
		return ItemService.LastDebug
	elseif command == "creeps" then
		-- ("creeps", participantId) buy a TEAM minion upgrade through the normal validation
		local participant = PlayerService.GetParticipantById(a)
		if not participant then
			return false, "no participant"
		end
		return CreepService.Purchase(participant.Player, participant)
	elseif command == "wave" then
		-- ("wave") spawn the next automatic minion wave now
		return CreepService.ForceWave()
	elseif command == "creepinfo" then
		local levelText = {}
		for team, level in pairs(CreepService.TeamLevels) do
			table.insert(levelText, "T" .. team .. "=" .. level)
		end
		local lines = { string.format("nextWaveIn=%.1f levels=%s", (CreepService.NextWaveAt or 0) - Util.Now(), table.concat(levelText, ",")) }
		for id, creep in pairs(CreepService.Creeps) do
			local p = CombatService.GetPosition(creep)
			table.insert(lines, string.format("%s team=%d lvl=%s hp=%d/%d dmg=%s armor=%s pos=(%.0f,%.0f) route=%d/%d target=%s", id, creep.Team, tostring(creep.Level or "-"),
				creep.Health, creep.MaxHealth, tostring(creep.HitDamage), tostring(creep.Armor), p.X, p.Z, creep.RouteIndex or 0, creep.Route and #creep.Route or 0, creep.Target and creep.Target.Id or "-"))
		end
		table.sort(lines)
		return table.concat(lines, "\n")
	elseif command == "killcreeps" then
		-- ("killcreeps", killerParticipantId, count) the killer's hero lands a lethal hit on enemy creeps
		local participant = PlayerService.GetParticipantById(a)
		local killer = participant and participant.Entity
		if not killer then
			return false, "killer not alive"
		end
		local killed = 0
		for _, creep in pairs(table.clone(CreepService.Creeps)) do
			if killed >= (b or 1) then
				break
			end
			if creep.Alive and creep.Team ~= killer.Team then
				CombatService.ApplyDamage(killer, creep, 100000, { IgnoreArmor = true })
				killed += 1
			end
		end
		return killed
	elseif command == "hitcreep" then
		-- ("hitcreep", killerParticipantId) hit an already-dead creep again to prove no double reward
		local participant = PlayerService.GetParticipantById(a)
		local killer = participant and participant.Entity
		local creep = b and CombatService.GetEntity(b)
		return killer and creep and CombatService.ApplyDamage(killer, creep, 100000) or 0
	end
	return "unknown command"
end

print("[Ruinfall] Server ready. Debug mode:", Constants.DEBUG_MODE)
