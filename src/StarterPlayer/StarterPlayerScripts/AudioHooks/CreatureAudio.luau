--[[
	CreatureAudio - voices for camp monsters (Stone Wardens), goblin lane minions and golems.

	Driven only by replicated attributes the AI already sets, plus client animation markers:
	  AIState  Idle -> Chase         alert roar / growl (the monster noticed someone)
	  AttackSeq (+1 per attack)      wind-up vocal now, impact at the animation's strike frame
	  DiedAt                         death cry + collapse / crumble
	  LastAttackAt (golem)           slam
	  AnimationEvents "Footstep"     heavy steps exactly when a foot plants (animation controllers)
	  AnimationEvents "AttackHit"    strike frame of the attack animation
	Idle noises are rare, random and only for creatures near the listener.
	Profiles (which sound, pitch, volume) live in AudioConfig.Monsters - add new monster types there.
]]

-- Services
local CollectionService = game:GetService("CollectionService")

-- Constants
local IDLE_RANGE = 55
local ALERT_COOLDOWN = 5

-- State
local CreatureAudio = {}
local ctx, Manager, Config = nil, nil, nil
local creatures = {} -- model -> state
local rng = Random.new()

local function profileOf(model)
	if model:GetAttribute("Rig") == "Goblin" then
		return Config.Monsters.Goblin, "Goblin"
	elseif model:GetAttribute("IsGolem") then
		return Config.Monsters.Golem, "Golem"
	end
	local monsterType = model:GetAttribute("MonsterType")
	if monsterType and Config.Monsters[monsterType] then
		return Config.Monsters[monsterType], monsterType
	end
	return nil
end

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function voice(state, cueField, options)
	local profile = state.Profile
	local cue = profile[cueField]
	local root = rootOf(state.Model)
	if not cue or not root then
		return nil
	end
	if not ctx.Visible(root.Position) then
		return nil
	end
	options = options or {}
	if options.Follow == nil then
		options.Follow = root
	elseif options.Follow == false then
		options.Follow = nil
		options.Position = options.Position or root.Position
	end
	options.Pitch = (options.Pitch or 1) * (profile.Pitch or 1)
	options.Volume = (options.Volume or 1) * (profile.Volume or 1)
	options.Source = state.Name
	return Manager:Play(cue, options)
end

local function nearListener(model, range)
	local root = rootOf(model)
	return root and (root.Position - Manager:GetListenerPosition()).Magnitude <= range
end

local function track(model)
	if creatures[model] then
		return
	end
	-- attributes arrive with the model, but give the server a moment on slow joins
	local profile, name = profileOf(model)
	if not profile then
		task.wait(0.5)
		profile, name = profileOf(model)
		if not profile or creatures[model] then
			return
		end
	end
	local state = {
		Model = model,
		Profile = profile,
		Name = name,
		NextIdle = os.clock() + rng:NextNumber(2, 8),
		LastAlert = 0,
		AttackSeq = model:GetAttribute("AttackSeq") or 0,
		PendingHit = false,
		Alerted = false,
	}
	creatures[model] = state

	model:GetAttributeChangedSignal("AIState"):Connect(function()
		local aiState = model:GetAttribute("AIState")
		local now = os.clock()
		if aiState == "Chase" and now - state.LastAlert > ALERT_COOLDOWN then
			state.LastAlert = now
			voice(state, "Alert")
			if name == "Brute" then
				voice(state, "DeathCry", { Volume = 0.45, Pitch = 1.1, Delay = 0.1 }) -- big roar layer
			end
			if nearListener(model, Config.MusicRules.CombatHostileRange) then
				ctx.NoteCombat()
			end
		end
	end)

	model:GetAttributeChangedSignal("AttackSeq"):Connect(function()
		local seq = model:GetAttribute("AttackSeq") or 0
		if seq <= state.AttackSeq then
			state.AttackSeq = seq
			return
		end
		state.AttackSeq = seq
		if name == "Goblin" and not state.Alerted then
			state.Alerted = true
			if rng:NextNumber() < 0.6 then
				voice(state, "Alert")
			end
		end
		voice(state, "AttackWindup")
		-- impact on the animation's strike frame (AnimationEvents), with a timed fallback
		state.PendingHit = true
		task.delay(0.35, function()
			if state.PendingHit then
				state.PendingHit = false
				voice(state, "AttackImpact", { Volume = 0.8 })
			end
		end)
		if nearListener(model, Config.MusicRules.CombatHostileRange) then
			ctx.NoteCombat()
		end
	end)

	model:GetAttributeChangedSignal("LastAttackAt"):Connect(function()
		if name == "Golem" then
			voice(state, "AttackWindup")
		end
	end)

	model:GetAttributeChangedSignal("DiedAt"):Connect(function()
		if state.Dead then
			return
		end
		state.Dead = true
		voice(state, "Death", { Follow = false })
		voice(state, "DeathCry", { Volume = 0.6, Follow = false })
	end)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			creatures[model] = nil
		end
	end)
end

local function onAnimationEvent(eventName, model, data)
	local state = creatures[model]
	if not state or state.Dead then
		return
	end
	if eventName == "Footstep" then
		if nearListener(model, 60) then
			voice(state, "Step", { Volume = data and data.Volume or 1 })
		end
	elseif eventName == "AttackHit" and state.PendingHit then
		state.PendingHit = false
		voice(state, "AttackImpact", { Volume = 0.8 })
	end
end

local function idlePass()
	local now = os.clock()
	for model, state in pairs(creatures) do
		if not state.Dead and now >= state.NextIdle then
			local interval = state.Profile.IdleInterval or { 10, 20 }
			state.NextIdle = now + rng:NextNumber(interval[1], interval[2])
			local aiState = model:GetAttribute("AIState")
			if state.Profile.Idle and (aiState == nil or aiState == "Idle" or aiState == "Return") and nearListener(model, IDLE_RANGE) then
				if state.Name ~= "Goblin" or rng:NextNumber() < 0.5 then
					voice(state, "Idle", { Volume = rng:NextNumber(0.7, 1) })
				end
			end
		end
	end
end

function CreatureAudio.Init(context)
	ctx = context
	Manager = ctx.Manager
	Config = ctx.Config
	for _, tag in ipairs({ "RF_Monster", "RF_Creep" }) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			task.spawn(track, model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
			task.spawn(track, model)
		end)
	end
	ctx.AnimationEvents.Event:Connect(onAnimationEvent)
	task.spawn(function()
		while true do
			task.wait(1)
			if ctx.InMatch() then
				local ok, err = pcall(idlePass)
				if not ok then
					warn("[Audio] creature idle", err)
				end
			end
		end
	end)
	return CreatureAudio
end

return CreatureAudio
