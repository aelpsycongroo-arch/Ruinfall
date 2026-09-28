-- CustomAnimationController: plays UPLOADED animations (Ruinfall Asset Porter plugin) where the
-- game would otherwise use a built-in one. Slots: Shared.AnimationLibrary.
--   * your own hero's idle / run: points the default Animate script at <Class>_Idle / <Class>_Run
--     (Animate replicates to everyone; clearing a slot restores the original animation)
--   * jungle monsters (RF_Monster) and lane minions (RF_Creep): Monster_* / Minion_* idle, walk,
--     attack and death replace the procedural rig animation while any of those slots is set
--     (the model gets the local RF_CustomAnim attribute so the procedural controllers step aside)
-- Slots are read every update, so swaps made during a playtest show up right away.

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationLibrary"))

-- Constants
local player = Players.LocalPlayer
local CREATURE_TAGS = { RF_Monster = "Monster", RF_Creep = "Minion" }
local LOCOMOTION = {
	Idle = { { "idle", "Animation1" }, { "idle", "Animation2" } },
	Run = { { "run", "RunAnim" }, { "walk", "WalkAnim" } },
}
local UPDATE_INTERVAL = 0.1

-- State
local originals = setmetatable({}, { __mode = "k" }) -- [Animate's Animation] = original id
local creatures = {} -- [model] = state
local accumulator = 0
local locomotionClock = 0

-- Local hero locomotion ----------------------------------------------------------------------
local function applyLocomotion()
	local character = player.Character
	local animate = character and character:FindFirstChild("Animate")
	local classKey = character and character:GetAttribute("Class")
	if not animate or not classKey then
		return
	end
	for state, targets in pairs(LOCOMOTION) do
		local id = AnimationLibrary.GetId(classKey .. "_" .. state)
		for _, target in ipairs(targets) do
			local holder = animate:FindFirstChild(target[1])
			local animation = holder and holder:FindFirstChild(target[2])
			if animation and animation:IsA("Animation") then
				if originals[animation] == nil then
					originals[animation] = animation.AnimationId
				end
				local wanted = id or originals[animation]
				if animation.AnimationId ~= wanted then
					animation.AnimationId = wanted -- Animate reloads its set when an Animation changes
				end
			end
		end
	end
end

-- Creatures ----------------------------------------------------------------------------------
local function hasCustom(prefix)
	for _, state in ipairs(AnimationLibrary.CREATURE_STATES) do
		if AnimationLibrary.GetId(prefix .. "_" .. state) then
			return true
		end
	end
	return false
end

local function stopAll(state)
	for _, track in pairs(state.Tracks) do
		pcall(function()
			track:Stop(0.2)
		end)
	end
	table.clear(state.Tracks)
	state.Loop, state.LoopId = nil, nil
end

local function playTrack(state, model, key, looped, priority, fade)
	local track = AnimationLibrary.GetTrack(model, key)
	if not track then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	track:Play(fade or 0.15)
	state.Tracks[key] = track
	return track
end

local function holdLastFrame(track)
	task.spawn(function()
		local waited = 0
		while track.Length <= 0 and waited < 3 do
			waited += task.wait(0.05)
		end
		if track.Length > 0 then
			task.wait(math.max(0, track.Length * 0.97))
			if track.IsPlaying then
				track:AdjustSpeed(0)
			end
		end
	end)
end

local function updateCreature(model, state, activeByPrefix)
	local active = activeByPrefix[state.Prefix]
	if active ~= state.Active then
		state.Active = active
		model:SetAttribute("RF_CustomAnim", active or nil)
		if not active then
			stopAll(state)
			state.DeathPlayed = false
		end
	end
	if not active then
		return
	end
	local prefix = state.Prefix
	if model:GetAttribute("DiedAt") ~= nil or model:GetAttribute("Dead") == true then
		if not state.DeathPlayed then
			state.DeathPlayed = true
			stopAll(state)
			local track = playTrack(state, model, prefix .. "_Death", false, Enum.AnimationPriority.Action, 0.1)
			if track then
				holdLastFrame(track)
			end
		end
		return
	end
	local seq = model:GetAttribute("AttackSeq") or 0
	if seq ~= state.LastSeq then
		state.LastSeq = seq
		playTrack(state, model, prefix .. "_Attack", false, Enum.AnimationPriority.Action, 0.05)
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local speed = 0
	if root then
		local velocity = root.AssemblyLinearVelocity
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	local wanted = speed > 1 and "Walk" or "Idle"
	local key = prefix .. "_" .. wanted
	if not AnimationLibrary.GetId(key) then
		key = prefix .. "_" .. (wanted == "Walk" and "Idle" or "Walk") -- only one loop uploaded: use it for both
	end
	local id = AnimationLibrary.GetId(key)
	if key ~= state.Loop or id ~= state.LoopId then
		local previous = state.Loop and state.Tracks[state.Loop]
		if previous then
			previous:Stop(0.2)
			state.Tracks[state.Loop] = nil
		end
		state.Loop, state.LoopId = key, id
		if id then
			playTrack(state, model, key, true, Enum.AnimationPriority.Movement, 0.2)
		end
	end
end

local function trackCreature(model, prefix)
	if creatures[model] or not model:IsA("Model") then
		return
	end
	creatures[model] = { Prefix = prefix, Tracks = {}, Active = false, LastSeq = model:GetAttribute("AttackSeq") or 0 }
end

local function step(dt)
	accumulator += dt
	locomotionClock += dt
	if locomotionClock >= 0.5 then
		locomotionClock = 0
		applyLocomotion()
	end
	if accumulator < UPDATE_INTERVAL then
		return
	end
	accumulator = 0
	local activeByPrefix = { Monster = hasCustom("Monster"), Minion = hasCustom("Minion") }
	for model, state in pairs(creatures) do
		if not model.Parent then
			creatures[model] = nil
		else
			local ok, err = pcall(updateCreature, model, state, activeByPrefix)
			if not ok then
				warn("[Ruinfall] Custom creature animation error:", err)
				creatures[model] = nil
			end
		end
	end
end

-- Init
for tag, prefix in pairs(CREATURE_TAGS) do
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		trackCreature(model, prefix)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		trackCreature(model, prefix)
	end)
end
RunService.Heartbeat:Connect(step)
