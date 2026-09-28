-- MinionAnimationController: procedural animations for the goblin lane minions
-- (Blender rig in ServerStorage.MonsterAssets.GoblinMinion). Drives Motor6D.Transform locally:
--   Walk   - hunched goblin run: stride synced to ground speed, arm swing, body bob/twist
--   Idle   - crouched, twitchy breathing, head darting around, claws flexing
--   Attack - wind-up and diagonal claw slash, alternating hands (server bumps AttackSeq)
--   Death  - knocked back onto the ground and fades (server sets DiedAt)
-- Purely visual; the server owns movement, damage and timing.

-- Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Animation markers for audio (footfalls / strike frame) - see ReplicatedStorage.Audio.AnimationEvents
local AnimationEvents = nil
pcall(function()
	AnimationEvents = require(game:GetService("ReplicatedStorage"):WaitForChild("Audio", 10):WaitForChild("AnimationEvents", 10))
end)
local function marker(name, model, data)
	if AnimationEvents then
		AnimationEvents.Fire(name, model, data)
	end
end

-- true when the gait phase passed `contact` between two frames (wraps at 1)
local function crossed(previous, current, contact)
	if current >= previous then
		return previous < contact and contact <= current
	end
	return previous < contact or contact <= current
end

-- Constants
local TAG = "RF_Creep"
local STRIDE = 3.2 -- studs per full gait cycle
local ATTACK_TIME = 0.5
local DEATH_FALL = 0.45
local DEATH_FADE_START = 0.55
local DEATH_FADE_END = 1.05
local TAU = math.pi * 2
local MOTORS = {
	Waist = "Torso", Neck = "Head",
	R_Shoulder = "RUA", R_Elbow = "RLA", L_Shoulder = "LUA", L_Elbow = "LLA",
	R_Hip = "RUL", R_Knee = "RLL", L_Hip = "LUL", L_Knee = "LLL",
}

-- State
local rigs = {}

-- Functions
local function angles(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function setup(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	-- only the goblin rig (golems / legacy minions are skipped)
	local waited = 0
	while model:GetAttribute("Rig") == nil and waited < 3 and model.Parent do
		waited += task.wait(0.1)
	end
	if model:GetAttribute("Rig") ~= "Goblin" then
		return
	end
	local rig = {
		Model = model,
		Root = model:WaitForChild("HumanoidRootPart", 5),
		Motors = {},
		Phase = math.random(),
		Move = 0,
		Seed = math.random() * 20,
		LastSeq = model:GetAttribute("AttackSeq") or 0,
		AttackStart = -10,
		AttackSide = 1,
		Parts = {},
	}
	for motorName, partName in pairs(MOTORS) do
		local part = model:WaitForChild(partName, 5)
		rig.Motors[motorName] = part and part:WaitForChild(motorName, 5)
	end
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item ~= rig.Root then
			table.insert(rig.Parts, item)
		end
	end
	model:GetAttributeChangedSignal("AttackSeq"):Connect(function()
		local seq = model:GetAttribute("AttackSeq") or 0
		if seq ~= rig.LastSeq then
			rig.LastSeq = seq
			rig.AttackStart = os.clock()
			rig.HitFired = false
			rig.AttackSide = seq % 2 == 0 and "L" or "R"
		end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			rigs[model] = nil
		end
	end)
	if model.Parent then
		rigs[model] = rig
	end
end

-- Poses: joint space == model space (X right, Y up, -Z forward).
-- +X rotation swings a limb forward; -X on the waist leans the upper body forward.
local function basePose(rig, now, pose)
	local move = rig.Move
	local p = rig.Phase * TAU
	local idle = 1 - move
	local t = now + rig.Seed
	-- body: hunched, bobbing run / twitchy idle breathing
	local bob = math.abs(math.sin(p)) * 0.16 * move + math.sin(t * 3.1) * 0.025 * idle
	pose.Waist = CFrame.new(0, bob - 0.06 * idle, 0)
		* angles(-0.28 * move - 0.12 * idle + math.sin(t * 3.1) * 0.03 * idle, math.sin(p) * 0.18 * move, math.sin(p) * 0.05 * move)
	-- head: counter the torso twist, dart around while idle
	local dart = math.sin(t * 0.9) + 0.5 * math.sin(t * 2.3)
	pose.Neck = angles(0.18 * move + 0.08 * idle + math.sin(p * 2) * 0.05 * move, -math.sin(p) * 0.15 * move + dart * 0.3 * idle, math.sin(t * 1.3) * 0.08 * idle)
	-- legs
	for side, sign in pairs({ R = 1, L = -1 }) do
		local legPhase = p + (side == "L" and math.pi or 0)
		local swing = math.sin(legPhase) * 0.75 * move
		local lift = math.max(0, math.cos(legPhase)) * move
		pose[side .. "_Hip"] = angles(swing + 0.12 * idle, 0, sign * 0.04 * idle)
		pose[side .. "_Knee"] = angles(-lift * 1.1 - 0.15 * move - 0.12 * idle, 0, 0)
		-- arms swing against the legs, claws held forward
		local armSwing = -math.sin(legPhase) * 0.7 * move
		pose[side .. "_Shoulder"] = angles(armSwing + math.sin(t * 2 + sign) * 0.06 * idle, 0, sign * (0.12 * move + 0.05 * idle))
		pose[side .. "_Elbow"] = angles(0.35 * move + 0.15 * idle + math.max(0, -math.sin(legPhase)) * 0.4 * move + math.sin(t * 4 + sign) * 0.05 * idle, 0, 0)
	end
end

local function attackPose(rig, now, pose)
	local t = now - rig.AttackStart
	if t < 0 or t > ATTACK_TIME then
		return
	end
	local u = t / ATTACK_TIME
	-- wind-up 0-0.3, slash 0.3-0.45, recover 0.45-1
	local wind = u < 0.3 and smooth(u / 0.3) or (1 - smooth((u - 0.3) / 0.12))
	local slash = u < 0.3 and 0 or (u < 0.45 and smooth((u - 0.3) / 0.15) or (1 - smooth((u - 0.45) / 0.55)))
	local side = rig.AttackSide
	local other = side == "R" and "L" or "R"
	local sign = side == "R" and 1 or -1 -- +X is the goblin's right
	-- torso coils away, then whips into the slash with a little hop forward
	pose.Waist = pose.Waist
		* CFrame.new(0, 0.1 * wind - 0.12 * slash, 0.15 * wind - 0.35 * slash)
		* angles(0.15 * wind - 0.35 * slash, -sign * (0.45 * wind - 0.55 * slash), 0)
	pose.Neck = pose.Neck * angles(0.1 * wind - 0.15 * slash, sign * (0.3 * wind - 0.3 * slash), 0)
	-- attacking arm: raised high and back, then raked down across the body
	pose[side .. "_Shoulder"] = pose[side .. "_Shoulder"] * angles(2.3 * wind + 0.4 * slash, sign * 0.3 * wind, sign * (0.6 * wind - 0.5 * slash))
	pose[side .. "_Elbow"] = pose[side .. "_Elbow"] * angles(0.9 * wind - 0.2 * slash, 0, 0)
	-- off arm pulls back for balance
	pose[other .. "_Shoulder"] = pose[other .. "_Shoulder"] * angles(-0.4 * slash + 0.3 * wind, 0, -sign * 0.25 * slash)
	-- lunge step with the leg on the slashing side
	pose[side .. "_Hip"] = pose[side .. "_Hip"] * angles(0.45 * slash, 0, 0)
	pose[side .. "_Knee"] = pose[side .. "_Knee"] * angles(-0.3 * slash, 0, 0)
	pose[other .. "_Hip"] = pose[other .. "_Hip"] * angles(-0.3 * slash, 0, 0)
	pose[other .. "_Knee"] = pose[other .. "_Knee"] * angles(-0.35 * wind - 0.25 * slash, 0, 0)
end

local function deathPose(rig, since, pose)
	local f = smooth(since / DEATH_FALL)
	-- knocked over backwards: the (server-anchored) root is tipped locally around the heels
	local root = rig.Root
	if root and root.Parent and root.Anchored then
		rig.DeathBase = rig.DeathBase or root.CFrame
		local heels = rig.DeathBase * CFrame.new(0, -2.0, 0.25)
		root.CFrame = heels * angles(1.35 * f, 0, 0.12 * f) * CFrame.new(0, 2.0 - 1.1 * f, -0.25)
	end
	pose.Waist = angles(0.15 * f, 0.2 * f, 0)
	pose.Neck = angles(0.3 * f, 0.4 * f, 0)
	for side, sign in pairs({ R = 1, L = -1 }) do
		pose[side .. "_Shoulder"] = angles(0.9 * f, 0, sign * 1.0 * f)
		pose[side .. "_Elbow"] = angles(0.4 * f, 0, 0)
		pose[side .. "_Hip"] = angles((side == "R" and 0.5 or 0.2) * f, 0, sign * 0.2 * f)
		pose[side .. "_Knee"] = angles(-(side == "R" and 0.3 or 0.9) * f, 0, 0)
	end
	local fade = smooth((since - DEATH_FADE_START) / (DEATH_FADE_END - DEATH_FADE_START))
	if fade > 0 then
		for _, part in ipairs(rig.Parts) do
			part.LocalTransparencyModifier = fade
		end
	end
end

local function step(dt)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, rig in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		if model:GetAttribute("RF_CustomAnim") then
			continue -- uploaded Minion_* animations drive this rig (CreatureAnimationController)
		end
		local pose = {}
		local diedAt = model:GetAttribute("DiedAt")
		if diedAt then
			deathPose(rig, math.max(0, serverNow - diedAt), pose)
		else
			local speed = 0
			if rig.Root and rig.Root.Parent then
				local v = rig.Root.AssemblyLinearVelocity
				speed = Vector3.new(v.X, 0, v.Z).Magnitude
			end
			rig.Move = lerp(rig.Move, math.clamp((speed - 0.5) / 5, 0, 1), math.clamp(dt * 10, 0, 1))
			local previousPhase = rig.Phase
			rig.Phase = (rig.Phase + speed * dt / STRIDE) % 1
			if rig.Move > 0.3 then
				-- each foot plants when its forward swing peaks (right at 0.25, left at 0.75)
				for _, contact in ipairs({ 0.25, 0.75 }) do
					if crossed(previousPhase, rig.Phase, contact) then
						marker("Footstep", model, { Volume = 0.7 * rig.Move })
					end
				end
			end
			basePose(rig, now, pose)
			attackPose(rig, now, pose)
			if not rig.HitFired and now - rig.AttackStart >= ATTACK_TIME * 0.38 and now - rig.AttackStart < ATTACK_TIME then
				rig.HitFired = true
				marker("AttackHit", model) -- claw rakes through
			end
		end
		for name, motor in pairs(rig.Motors) do
			if motor and motor.Parent then
				motor.Transform = pose[name] or CFrame.identity
			end
		end
	end
end

-- Initialization
for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	task.spawn(setup, model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
	task.spawn(setup, model)
end)
RunService.PreSimulation:Connect(step)
