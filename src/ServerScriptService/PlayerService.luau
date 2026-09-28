-- PlayerService: participants (humans + bots), lobby configuration, team
-- assignment and hero spawning/despawning.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local CharacterFactory = require(script.Parent:WaitForChild("CharacterFactory"))

-- Constants
local BOT_NAMES = { "Vex", "Mora", "Kade", "Sable", "Rook", "Lyra", "Thorn", "Iris", "Grim", "Nyx", "Ash", "Juno", "Brand", "Wren", "Osric", "Talia", "Fenn", "Dusk" }

-- State
local PlayerService = {}
PlayerService.Participants = {}
PlayerService.Mode = Constants.TeamModes.TWO
PlayerService.Difficulty = Constants.DEFAULT_BOT_DIFFICULTY
PlayerService.AcceptingPlayers = true
PlayerService.Changed = Util.Signal.new()
PlayerService.ParticipantLeft = Util.Signal.new() -- (participant)

local botCounter = 0
local joinCounter = 0
local heroesFolder = nil

-- Functions
local function freshStats()
	return { Kills = 0, Deaths = 0, Assists = 0, Damage = 0, Flags = 0, Ruins = 0, Gold = 0 }
end

local function orderParticipants(list)
	table.sort(list, function(a, b)
		if a.IsBot ~= b.IsBot then
			return not a.IsBot
		end
		return a.Order < b.Order
	end)
	return list
end

function PlayerService.GetParticipants()
	local list = {}
	for _, participant in ipairs(PlayerService.Participants) do
		if not participant.Spectator then
			table.insert(list, participant)
		end
	end
	return orderParticipants(list)
end

function PlayerService.GetParticipantByPlayer(player)
	for _, participant in ipairs(PlayerService.Participants) do
		if participant.Player == player then
			return participant
		end
	end
	return nil
end

function PlayerService.GetParticipantById(participantId)
	for _, participant in ipairs(PlayerService.Participants) do
		if participant.Id == participantId then
			return participant
		end
	end
	return nil
end

function PlayerService.GetHost()
	local host = nil
	for _, participant in ipairs(PlayerService.Participants) do
		if not participant.IsBot and (not host or participant.Order < host.Order) then
			host = participant
		end
	end
	return host
end

function PlayerService.IsHost(player)
	local host = PlayerService.GetHost()
	return host ~= nil and host.Player == player
end

function PlayerService.GetBots()
	local bots = {}
	for _, participant in ipairs(PlayerService.Participants) do
		if participant.IsBot then
			table.insert(bots, participant)
		end
	end
	return orderParticipants(bots)
end

function PlayerService.GetTeamMembers(team)
	local members = {}
	for _, participant in ipairs(PlayerService.Participants) do
		if participant.Team == team and not participant.Spectator then
			table.insert(members, participant)
		end
	end
	return members
end

function PlayerService.GetTeamPlayers(team)
	local players = {}
	for _, participant in ipairs(PlayerService.GetTeamMembers(team)) do
		if participant.Player then
			table.insert(players, participant.Player)
		end
	end
	return players
end

function PlayerService.SetPlayerAttributes(participant)
	local player = participant.Player
	if not player or player.Parent ~= Players then
		return
	end
	player:SetAttribute("ParticipantId", participant.Id)
	player:SetAttribute("Team", participant.Team or 0)
	player:SetAttribute("Class", participant.ClassKey)
	player:SetAttribute("State", participant.State)
	player:SetAttribute("RespawnAt", participant.RespawnAt or 0)
	player:SetAttribute("Gold", participant.Stats.Gold or 0)
	player:SetAttribute("Potions", participant.Potions or 0)
	player:SetAttribute("CrossState", participant.CrossState or "")
end

-- Lobby -------------------------------------------------------------------
-- Which base slots to use for N teams, spread around the arena
local SLOT_SPREAD = {
	[2] = { { 1 }, { 1, 2 } },
	[4] = { { 1 }, { 1, 3 }, { 1, 2, 3 }, { 1, 2, 3, 4 } },
	[6] = { { 1 }, { 1, 4 }, { 1, 3, 5 }, { 1, 2, 4, 5 }, { 1, 2, 3, 4, 5 }, { 1, 2, 3, 4, 5, 6 } },
}

-- Royale: free for all - every participant is its own team (1..18), everyone starts as a
-- Fighter (other classes come from weapons found on the map)
local function assignRoyaleTeams()
	local activeTeams = {}
	for index, participant in ipairs(PlayerService.GetParticipants()) do
		participant.Team = index
		participant.ManualTeam = false
		participant.ClassKey = "Fighter"
		table.insert(activeTeams, index)
		PlayerService.SetPlayerAttributes(participant)
	end
	return activeTeams, Constants.TeamModeSlots.Royale
end

function PlayerService.IsRoyale()
	return Constants.IsRoyale(PlayerService.Mode)
end

function PlayerService.AssignTeams()
	if Constants.IsRoyale(PlayerService.Mode) then
		return assignRoyaleTeams()
	end
	local slots = Constants.TeamModeSlots[PlayerService.Mode] or 2
	local ordered = PlayerService.GetParticipants()
	local teamCount = math.clamp(#ordered, 1, slots)
	local teamList = SLOT_SPREAD[slots][teamCount]
	local used = {}
	-- First pass: respect manually chosen teams
	for _, participant in ipairs(ordered) do
		if participant.ManualTeam and participant.Team and participant.Team >= 1 and participant.Team <= slots then
			used[participant.Team] = true
			PlayerService.SetPlayerAttributes(participant)
		end
	end
	-- Second pass: auto-assign the rest via round-robin
	local autoIndex = 0
	for _, participant in ipairs(ordered) do
		if not participant.ManualTeam or not participant.Team or participant.Team < 1 or participant.Team > slots then
			participant.ManualTeam = false
		autoIndex += 1
			participant.Team = teamList[((autoIndex - 1) % teamCount) + 1]
			used[participant.Team] = true
			PlayerService.SetPlayerAttributes(participant)
		end
	end
	local activeTeams = {}
	for team = 1, slots do
		if used[team] then
			table.insert(activeTeams, team)
		end
	end
	return activeTeams, slots
end

function PlayerService.SetTeam(player, team)
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or Constants.IsRoyale(PlayerService.Mode) then
		return false
	end
	local maxTeams = Constants.TeamModeSlots[PlayerService.Mode] or 2
	if type(team) ~= "number" or team < 1 or team > maxTeams then
		return false
	end
	participant.Team = team
	participant.ManualTeam = true
	PlayerService.SetPlayerAttributes(participant)
	PlayerService.Changed:Fire()
	return true
end

function PlayerService.AddBot()
	if #PlayerService.GetParticipants() >= Constants.MAX_PARTICIPANTS then
		return nil, string.format("Match is full (%d participants max)", Constants.MAX_PARTICIPANTS)
	end
	botCounter += 1
	local classKeys = ClassDefinitions.Order
	local participant = {
		Id = "B" .. botCounter,
		IsBot = true,
		Name = "Bot " .. BOT_NAMES[((botCounter - 1) % #BOT_NAMES) + 1],
		ClassKey = classKeys[math.random(1, #classKeys)],
		Difficulty = PlayerService.Difficulty,
		Order = botCounter,
		State = "Lobby",
		Stats = freshStats(),
		Purchases = {},
		PurchaseTimestamps = {},
	}
	table.insert(PlayerService.Participants, participant)
	PlayerService.AssignTeams()
	PlayerService.Changed:Fire()
	return participant
end

function PlayerService.RemoveBot()
	local bots = PlayerService.GetBots()
	local last = bots[#bots]
	if not last then
		return false, "No bots to remove"
	end
	local index = table.find(PlayerService.Participants, last)
	if index then
		table.remove(PlayerService.Participants, index)
	end
	PlayerService.AssignTeams()
	PlayerService.Changed:Fire()
	return true
end

function PlayerService.CycleBotClass(participantId)
	local participant = PlayerService.GetParticipantById(participantId)
	if not participant or not participant.IsBot or Constants.IsRoyale(PlayerService.Mode) then
		return false
	end
	local order = ClassDefinitions.Order
	local index = table.find(order, participant.ClassKey) or 0
	participant.ClassKey = order[(index % #order) + 1]
	PlayerService.Changed:Fire()
	return true
end

-- LockedMode: a server reached through a hall gate keeps that gate's game mode
-- (a Royale server never turns into a team match and vice versa).
PlayerService.LockedMode = nil

function PlayerService.SetMode(mode)
	if not Constants.TeamModeSlots[mode] then
		return false
	end
	local locked = PlayerService.LockedMode
	if locked and Constants.IsRoyale(locked) ~= Constants.IsRoyale(mode) then
		return false
	end

	PlayerService.Mode = mode
	-- Clear manual team choices since the available teams changed
	for _, participant in ipairs(PlayerService.Participants) do
		participant.ManualTeam = false
	end
	PlayerService.AssignTeams()
	PlayerService.Changed:Fire()
	return true
end

function PlayerService.SetDifficulty(difficulty)
	if not Constants.BotDifficulty[difficulty] then
		return false
	end
	PlayerService.Difficulty = difficulty
	for _, bot in ipairs(PlayerService.GetBots()) do
		bot.Difficulty = difficulty
	end
	PlayerService.Changed:Fire()
	return true
end

function PlayerService.SetClass(player, classKey)
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or not ClassDefinitions.IsValid(classKey) or Constants.IsRoyale(PlayerService.Mode) then
		return false
	end
	participant.ClassKey = classKey
	PlayerService.SetPlayerAttributes(participant)
	PlayerService.Changed:Fire()
	return true
end

-- Heroes ------------------------------------------------------------------
-- Real players spawn with their own Roblox avatar; the class-coloured generic rig is
-- only a fallback when the avatar can't be fetched (e.g. offline test accounts).
local USE_PLAYER_AVATARS = true
local avatarCache = {} -- [userId] = HumanoidDescription | false

local function getAvatarDescription(player)
	if not USE_PLAYER_AVATARS or player.UserId <= 0 then
		return nil
	end
	local cached = avatarCache[player.UserId]
	if cached == nil then
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		cached = (ok and result) or false
		avatarCache[player.UserId] = cached
		if not ok then
			warn("[Ruinfall] Could not fetch avatar for", player.Name, result)
		end
	end
	return cached and cached:Clone() or nil
end

function PlayerService.SpawnHero(participant, position, lookAt)
	local teamColor = Constants.GetTeamColor(participant.Team)
	local model
	local isAvatar = false
	if participant.IsBot then
		local ok, result = pcall(CharacterFactory.CreateBotCharacter, participant)
		if not ok or not result then
			warn("[Ruinfall] Bot rig failed:", result)
			return nil
		end
		model = result
	else
		local player = participant.Player
		if not player or player.Parent ~= Players then
			return nil
		end
		local description = getAvatarDescription(player)
		isAvatar = description ~= nil
		if not description then
			description = CharacterFactory.BuildDescription(participant.ClassKey)
		end
		local ok, err = pcall(function()
			player:LoadCharacterWithHumanoidDescription(description)
		end)
		if not ok and isAvatar then
			warn("[Ruinfall] Avatar load failed, using class rig:", err)
			isAvatar = false
			ok, err = pcall(function()
				player:LoadCharacterWithHumanoidDescription(CharacterFactory.BuildDescription(participant.ClassKey))
			end)
		end
		if not ok then
			warn("[Ruinfall] LoadCharacterWithHumanoidDescription failed, using default:", err)
			pcall(function()
				player:LoadCharacter()
			end)
		end
		model = player.Character
		if not model or player.Parent ~= Players then
			return nil
		end
		model:WaitForChild("HumanoidRootPart", 5)
		CharacterFactory.PrepareHumanoid(model, isAvatar)
	end

	CharacterFactory.ApplyClassLook(model, participant.ClassKey, teamColor, isAvatar)
	participant.AvatarLook = isAvatar -- Royale weapon swaps re-dress the hero
	local spawnPosition = position + Vector3.new(0, 3.4, 0)
	local spawnCFrame = CFrame.lookAt(spawnPosition, Vector3.new(lookAt.X, spawnPosition.Y, lookAt.Z))
	model:PivotTo(spawnCFrame)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if participant.IsBot then
		model.Parent = heroesFolder
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	elseif humanoid then
		humanoid.AutoRotate = false -- the client faces the mouse
	end

	local entity = CombatService.CreateHero(participant, model, participant.ClassKey)
	participant.Entity = entity
	participant.State = "Alive"
	participant.RespawnAt = nil
	if humanoid then
		humanoid.Died:Connect(function()
			if entity.Alive then
				CombatService.Kill(entity, nil)
			end
		end)
	end
	PlayerService.SetPlayerAttributes(participant)
	return entity
end

function PlayerService.DespawnHero(participant, delaySeconds)
	local entity = participant.Entity
	participant.Entity = nil
	if not entity then
		return
	end
	CombatService.Unregister(entity)
	local model = entity.Model
	task.delay(delaySeconds or 0, function()
		if not model then
			return
		end
		local player = participant.Player
		if player and player.Character == model then
			player.Character = nil
		end
		model:Destroy()
	end)
end

-- Match lifecycle -----------------------------------------------------------
function PlayerService.ResetForLobby()
	for _, participant in ipairs(PlayerService.Participants) do
		if participant.Entity then
			PlayerService.DespawnHero(participant, 0)
		end
		local player = participant.Player
		if player and player.Character then
			local character = player.Character
			player.Character = nil
			character:Destroy()
		end
		participant.Team = nil
		participant.ManualTeam = false
		participant.State = "Lobby"
		participant.RespawnAt = nil
		participant.Placement = nil
		participant.Stats = freshStats()
		participant.Purchases = {}
		participant.PurchaseTimestamps = {}
		participant.Mythics = {} -- [1] = item id (-> E), [2] = (-> R), [3] = (-> SPACE)
		participant.Boots = nil -- separate boot slot (-> right mouse)
		participant.Passives = {} -- [1..3] = passive item ids (automatic effects, no hotkey)
		participant.PassiveStacks = {} -- per-match stacking passives, e.g. SoulHarvest = +HP (PassiveService)
		participant.ItemReadyAt = {} -- [itemId] = server time the item ability is ready
		participant.Potions = 0 -- health potions carried (monster drops)
		participant.CrossState = nil -- Royale revive cross: "Held" / "Planted" / "Used" / "Lost"
		participant.Cross = nil
	end
	-- Admit spectators (late joiners); humans take priority over bots
	for _, participant in ipairs(table.clone(PlayerService.Participants)) do
		if participant.Spectator then
			if #PlayerService.GetParticipants() >= Constants.MAX_PARTICIPANTS then
				PlayerService.RemoveBot()
			end
			if #PlayerService.GetParticipants() < Constants.MAX_PARTICIPANTS then
				participant.Spectator = false
			end
		end
	end
	PlayerService.AcceptingPlayers = true
	PlayerService.AssignTeams()
	for _, participant in ipairs(PlayerService.Participants) do
		PlayerService.SetPlayerAttributes(participant)
	end
	PlayerService.Changed:Fire()
end

function PlayerService.AddGold(participant, amount)
	if not participant or not participant.Stats then
		return
	end
	participant.Stats.Gold = (participant.Stats.Gold or 0) + amount
	if participant.Stats.Gold < 0 then
		participant.Stats.Gold = 0
	end
	PlayerService.SetPlayerAttributes(participant)
end

function PlayerService.GetGold(participant)
	return participant and participant.Stats and participant.Stats.Gold or 0
end

function PlayerService.AddPurchase(participant, itemKey)
	if not participant or not participant.Purchases then
		return
	end
	participant.Purchases[itemKey] = (participant.Purchases[itemKey] or 0) + 1
	-- Track purchase timestamps for resale pricing (FIFO: oldest first)
	if not participant.PurchaseTimestamps then
		participant.PurchaseTimestamps = {}
	end
	if not participant.PurchaseTimestamps[itemKey] then
		participant.PurchaseTimestamps[itemKey] = {}
	end
	table.insert(participant.PurchaseTimestamps[itemKey], os.time())
end

-- Remove one purchase of itemKey (sells the oldest one first)
-- Returns the timestamp of the removed purchase, or nil if nothing to remove
function PlayerService.RemovePurchase(participant, itemKey)
	if not participant or not participant.Purchases then
		return nil
	end
	local count = participant.Purchases[itemKey] or 0
	if count <= 0 then
		return nil
	end
	participant.Purchases[itemKey] = count - 1
	if participant.Purchases[itemKey] == 0 then
		participant.Purchases[itemKey] = nil
	end
	-- Remove the oldest timestamp (FIFO)
	local timestamp = nil
	if participant.PurchaseTimestamps and participant.PurchaseTimestamps[itemKey] then
		local timestamps = participant.PurchaseTimestamps[itemKey]
		timestamp = table.remove(timestamps, 1)
		if #timestamps == 0 then
			participant.PurchaseTimestamps[itemKey] = nil
		end
	end
	return timestamp
end

-- Get the oldest purchase timestamp for an item (for sell price display)
function PlayerService.GetOldestTimestamp(participant, itemKey)
	if not participant or not participant.PurchaseTimestamps then
		return nil
	end
	local timestamps = participant.PurchaseTimestamps[itemKey]
	if timestamps and #timestamps > 0 then
		return timestamps[1]
	end
	return nil
end

function PlayerService.GetPurchases(participant)
	return participant and participant.Purchases or {}
end

function PlayerService.Serialize()
	local host = PlayerService.GetHost()
	local list = {}
	local all = orderParticipants(table.clone(PlayerService.Participants))
	for _, participant in ipairs(all) do
		table.insert(list, {
			Id = participant.Id,
			Name = participant.Name,
			IsBot = participant.IsBot == true,
			UserId = participant.UserId,
			ClassKey = participant.ClassKey,
			Team = participant.Team,
			State = participant.State,
			Spectator = participant.Spectator == true,
			Difficulty = participant.Difficulty,
			RespawnAt = participant.RespawnAt,
			Placement = participant.Placement, -- Royale: final place (1 = winner)
			IsHost = participant == host,
			EntityId = participant.Entity and participant.Entity.Id or nil,
			Stats = participant.Stats,
			Purchases = participant.Purchases or {},
		PurchaseTimestamps = participant.PurchaseTimestamps or {},
			-- "" marks an empty mythic slot (arrays can't hold nil holes over the network)
			Mythics = {
				(participant.Mythics and participant.Mythics[1]) or "",
				(participant.Mythics and participant.Mythics[2]) or "",
				(participant.Mythics and participant.Mythics[3]) or "",
			},
			Boots = participant.Boots or "",
			Passives = {
				(participant.Passives and participant.Passives[1]) or "",
				(participant.Passives and participant.Passives[2]) or "",
				(participant.Passives and participant.Passives[3]) or "",
			},
			ItemReadyAt = participant.ItemReadyAt or {},
			PassiveStacks = participant.PassiveStacks or {},
			WarBandActive = participant.WarBandActive or 0,
			Potions = participant.Potions or 0,
			CrossState = participant.CrossState or "",
		})
	end
	return list
end

-- Players joining / leaving -----------------------------------------------------
local function onPlayerAdded(player)
	joinCounter += 1
	local full = #PlayerService.GetParticipants() >= Constants.MAX_PARTICIPANTS
	if full and PlayerService.AcceptingPlayers then
		PlayerService.RemoveBot()
		full = #PlayerService.GetParticipants() >= Constants.MAX_PARTICIPANTS
	end
	local spectator = full or not PlayerService.AcceptingPlayers
	local participant = {
		Id = "P" .. player.UserId,
		Player = player,
		UserId = player.UserId,
		Name = player.DisplayName,
		IsBot = false,
		ClassKey = "Fighter",
		Order = joinCounter,
		Spectator = spectator,
		State = spectator and "Spectator" or "Lobby",
		Stats = freshStats(),
		Purchases = {},
		PurchaseTimestamps = {},
	}
	table.insert(PlayerService.Participants, participant)
	if PlayerService.AcceptingPlayers then
		PlayerService.AssignTeams()
	end
	PlayerService.SetPlayerAttributes(participant)
	PlayerService.Changed:Fire()
end

local function onPlayerRemoving(player)
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant then
		return
	end
	if participant.Entity then
		CombatService.Unregister(participant.Entity)
		participant.Entity = nil
	end
	local index = table.find(PlayerService.Participants, participant)
	if index then
		table.remove(PlayerService.Participants, index)
	end
	if PlayerService.AcceptingPlayers then
		PlayerService.AssignTeams()
	end
	PlayerService.ParticipantLeft:Fire(participant)
	PlayerService.Changed:Fire()
end

-- Public API ----------------------------------------------------------------
function PlayerService.Init()
	Players.CharacterAutoLoads = false
	heroesFolder = workspace:FindFirstChild("Heroes")
	if not heroesFolder then
		heroesFolder = Instance.new("Folder")
		heroesFolder.Name = "Heroes"
		heroesFolder.Parent = workspace
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerService
