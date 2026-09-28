--[[
	MusicDirector - dynamic music state machine (2 Hz, crossfades handled by AudioManager).

	  Hub hall / lobby / results      -> Lobby
	  Match starting / exploring      -> Exploration
	  Local hero in combat            -> Combat   (dealt / took damage, cast a skill, a hostile
	                                                monster or enemy hero close by)
	  Combat near a Ruin or a Brute    -> Boss     (the elite fights)
	  Match end                       -> Victory / Defeat stinger once, then back to Lobby
	Leaving combat waits MusicRules.CombatTimeout seconds, then fades back to Exploration.
	The same track is never restarted; tracks never overlap (two crossfading channels).
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- Constants
local STATE = Constants.MatchState

-- State
local MusicDirector = {}
local ctx, Manager, Rules = nil, nil, nil
local resultPlayedFor = nil -- match id the victory/defeat cue was played for
local resultUntil = 0

local function myRoot()
	local character = ctx.MyCharacter()
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function hostileNear(root)
	local range = Rules.CombatHostileRange
	local myTeam = ctx.MyTeam()
	for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
		local other = model:FindFirstChild("HumanoidRootPart")
		if other and model:GetAttribute("Team") ~= myTeam and model:GetAttribute("Dead") ~= true
			and (other.Position - root.Position).Magnitude <= range and ctx.ClientState.IsHeroVisible(model) then
			return true
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("RF_Monster")) do
		local other = model.PrimaryPart
		if other and model:GetAttribute("AIState") == "Chase" and (other.Position - root.Position).Magnitude <= range then
			return true
		end
	end
	return false
end

local function eliteNear(root)
	local range = Rules.BossRange
	for _, model in ipairs(CollectionService:GetTagged("RF_Ruin")) do
		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if part and model:GetAttribute("Dead") ~= true and (part.Position - root.Position).Magnitude <= range then
			return true
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("RF_Monster")) do
		local part = model.PrimaryPart
		if part and model:GetAttribute("MonsterType") == "Brute" and model:GetAttribute("AIState") == "Chase"
			and (part.Position - root.Position).Magnitude <= range then
			return true
		end
	end
	return false
end

local function update()
	local role = ReplicatedStorage:GetAttribute("ServerRole")
	local gameState = ctx.ClientState.Game
	local matchState = gameState and gameState.State or STATE.LOBBY
	local now = os.clock()

	if role == "Hub" then
		Manager:PlayMusic("Lobby")
		return
	end
	-- match end: one victory / defeat cue per match, then calm lobby music
	if matchState == STATE.ENDING or matchState == STATE.RESULTS then
		local matchId = tostring(gameState and (gameState.Seed or gameState.StartedAt))
		if resultPlayedFor ~= matchId then
			resultPlayedFor = matchId
			local winner = gameState and gameState.Winner
			local won = winner ~= nil and winner == ctx.MyTeam()
			Manager:PlayMusic(won and "Victory" or "Defeat", { Once = true, Then = "Lobby", Fade = 1.2 })
			resultUntil = now + 12
		end
		return
	end
	if now < resultUntil then
		return -- let the result cue finish
	end
	if matchState ~= STATE.ACTIVE and matchState ~= STATE.STARTING then
		Manager:PlayMusic("Lobby")
		return
	end
	local root = myRoot()
	local inCombat = now - ctx.LastCombatAt < Rules.CombatTimeout
	if root and not inCombat and hostileNear(root) then
		ctx.NoteCombat()
		inCombat = true
	end
	if inCombat and root and eliteNear(root) then
		Manager:PlayMusic("Boss")
	elseif inCombat then
		Manager:PlayMusic("Combat")
	else
		Manager:PlayMusic("Exploration")
	end
end

function MusicDirector.Init(context)
	ctx = context
	Manager = ctx.Manager
	Rules = ctx.Config.MusicRules
	ctx.ClientState.StateChanged:Connect(function(newState)
		if newState == STATE.ACTIVE then
			Manager:PlayStinger("Stingers.MatchStart")
			ctx.LastCombatAt = 0
		end
		task.defer(update)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(update)
			if not ok then
				warn("[Audio] music director", err)
			end
			task.wait(0.5)
		end
	end)
	return MusicDirector
end

return MusicDirector
