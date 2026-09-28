-- GolemAnimationController: procedural animations for the Golem Heart stone golem
-- (CreepService builds it as a Motor6D rig, Rig = "Golem"). Drives Motor6D.Transform locally:
--   Summon - crashes down into a deep crouch, then rises (SpawnedAt)
--   Walk   - heavy lumbering stride: stomping legs, swinging knuckle-dragging arms, body sway
--   Idle   - slow breathing, shoulders rolling, head turning, fists flexing
--   Attack - both fists raised overhead, then a double-handed ground smash (server bumps AttackSeq)
--   Death  - crumbles: knees buckle, it topples forward and sinks while fading (DiedAt)
-- Purely visual; the server owns movement, damage and timing.

-- Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Constants
local TAG = "RF_Creep"
local STRIDE = 5.5 -- studs per full gait cycle (long, slow steps)
local ATTACK_TIME = 0.75
local SUMMON_TIME = 0.9
local DEATH_TIME = 1.2
local TAU = math.pi * 2
local MOTORS = {
	Waist = "Torso", Neck = "Head",
	R_Shoulder = "RUpperArm", R_Elbow = "RForearm", L_Shoulder = "LUpperArm", L_Elbow = "LForearm",
	R_Hip = "RThigh", R_Knee = "RShin", L_Hip = "LThigh", L_Knee = "LShin",
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
	local waited = 0
	while model:GetAttribute("Rig") == nil and waited < 3 and model.Parent do
		waited += task.wait(0.1)
	end
	if model:GetAttribute("Rig") ~= "Golem" then
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
		Parts = {},
		Core = nil,
	}
	for motorName, partName in pairs(MOTORS) do
		local part = model:WaitForChild(partName, 5)
		rig.Motors[motorName] = part and part:WaitForChild(motorName, 5)
	end
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item ~= rig.Root then
			table.insert(rig.Parts, item)
			if item.Name == "Core" then
				rig.Core = item
				rig.CoreSize = item.Size
			end
		end
	end
	model:GetAttributeChangedSignal("AttackSeq"):Connect(function()
		local seq = model:GetAttribute("AttackSeq") or 0
		if seq ~= rig.LastSeq then
			rig.LastSeq = seq
			rig.AttackStart = os.clock()
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

-- Poses: joint space == model space (X right, Y up, -Z forward); +X rotation swings a limb
-- forward, -X on the waist leans the body forward.
local function basePose(rig, now, pose)
	local move = rig.Move
	local idle = 1 - move
	local p = rig.Phase * TAU
	local t = now + rig.Seed
	local breathe = math.sin(t * 1.6)
	-- heavy side-to-side sway and a thump on every step
	local stomp = math.abs(math.sin(p)) * move
	pose.Waist = CFrame.new(math.sin(p) * 0.25 * move, -0.2 * stomp + breathe * 0.06 * idle, 0)
		* angles(-0.18 * move - 0.05 * idle + breathe * 0.03 * idle, math.sin(p) * 0.12 * move, -math.sin(p) * 0.1 * move)
	pose.Neck = angles(0.15 * move + math.sin(t * 0.7) * 0.05 * idle, math.sin(t * 0.45) * 0.35 * idle - math.sin(p) * 0.1 * move, 0)
	for side, sign in pairs({ R = 1, L = -1 }) do
		local legPhase = p + (side == "L" and math.pi or 0)
		local swing = math.sin(legPhase) * 0.55 * move
		local lift = math.max(0, math.cos(legPhase)) * move
		pose[side .. "_Hip"] = angles(swing + 0.08 * idle, 0, sign * 0.06)
		pose[side .. "_Knee"] = angles(-lift * 0.9 - 0.1 * idle, 0, 0)
		-- knuckle-dragging arms swing against the legs; idle: slow shoulder roll and fist flex
		local armSwing = -math.sin(legPhase) * 0.5 * move
		pose[side .. "_Shoulder"] = angles(armSwing + 0.15 + math.sin(t * 1.1 + sign) * 0.06 * idle, 0, sign * (0.1 + 0.08 * breathe * idle))
		pose[side .. "_Elbow"] = angles(0.25 + math.max(0, -math.sin(legPhase)) * 0.35 * move + math.sin(t * 2.2 + sign) * 0.05 * idle, 0, 0)
	end
end

local function summonPose(rig, since, pose)
	if since < 0 or since > SUMMON_TIME then
		return
	end
	local u = since / SUMMON_TIME
	-- lands in a deep crouch with the fists on the ground, then rises up
	local crouch = 1 - smooth((u - 0.25) / 0.75)
	pose.Waist = pose.Waist * CFrame.new(0, -0.9 * crouch, 0) * angles(-0.45 * crouch, 0, 0)
	pose.Neck = pose.Neck * angles(0.3 * crouch, 0, 0)
	for side, sign in pairs({ R = 1, L = -1 }) do
		pose[side .. "_Hip"] = pose[side .. "_Hip"] * angles(0.7 * crouch, 0, sign * 0.1 * crouch)
		pose[side .. "_Knee"] = pose[side .. "_Knee"] * angles(-1.1 * crouch, 0, 0)
		pose[side .. "_Shoulder"] = pose[side .. "_Shoulder"] * angles(0.5 * crouch, 0, sign * 0.3 * crouch)
	end
end

local function attackPose(rig, now, pose)
	local t = now - rig.AttackStart
	if t < 0 or t > ATTACK_TIME then
		return
	end
	local u = t / ATTACK_TIME
	-- raise 0-0.3, smash 0.3-0.42 (damage lands here), hold, recover 0.6-1
	local raise = u < 0.3 and smooth(u / 0.3) or (1 - smooth((u - 0.3) / 0.12))
	local smash = u < 0.3 and 0 or (u < 0.42 and smooth((u - 0.3) / 0.12) or (1 - smooth((u - 0.6) / 0.4)))
	pose.Waist = pose.Waist * CFrame.new(0, 0.25 * raise - 0.35 * smash, 0.3 * raise - 0.4 * smash) * angles(0.3 * raise - 0.55 * smash, 0, 0)
	pose.Neck = pose.Neck * angles(-0.25 * raise + 0.2 * smash, 0, 0)
	for side, sign in pairs({ R = 1, L = -1 }) do
		-- both arms high overhead, then slammed down in front
		pose[side .. "_Shoulder"] = pose[side .. "_Shoulder"] * angles(2.6 * raise + 0.9 * smash, 0, -sign * 0.25 * raise + sign * 0.1 * smash)
		pose[side .. "_Elbow"] = pose[side .. "_Elbow"] * angles(0.6 * raise - 0.2 * smash, 0, 0)
		pose[side .. "_Hip"] = pose[side .. "_Hip"] * angles(0.25 * smash, 0, sign * 0.08 * smash)
		pose[side .. "_Knee"] = pose[side .. "_Knee"] * angles(-0.2 * raise - 0.45 * smash, 0, 0)
	end
end

local function deathPose(rig, since, pose)
	local f = smooth(since / (DEATH_TIME * 0.6))
	local root = rig.Root
	if root and root.Parent and root.Anchored then
		rig.DeathBase = rig.DeathBase or root.CFrame
		-- topples forward and sinks into the ground
		local sink = smooth((since - 0.35) / (DEATH_TIME - 0.35))
		root.CFrame = rig.DeathBase * CFrame.new(0, -1.5 * f - 2.5 * sink, -0.8 * f) * angles(-0.6 * f, 0, 0.1 * f)
	end
	pose.Waist = angles(-0.5 * f, 0.15 * f, 0)
	pose.Neck = angles(0.5 * f, 0, 0.2 * f)
	for side, sign in pairs({ R = 1, L = -1 }) do
		pose[side .. "_Shoulder"] = angles(-0.3 * f, 0, sign * 0.8 * f)
		pose[side .. "_Elbow"] = angles(0.5 * f, 0, 0)
		pose[side .. "_Hip"] = angles(1.0 * f, 0, sign * 0.3 * f)
		pose[side .. "_Knee"] = angles(-1.4 * f, 0, 0)
	end
	local fade = smooth((since - 0.5) / (DEATH_TIME - 0.5))
	for _, part in ipairs(rig.Parts) do
		part.LocalTransparencyModifier = fade
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
			rig.Move = lerp(rig.Move, math.clamp((speed - 0.5) / 8, 0, 1), math.clamp(dt * 8, 0, 1))
			rig.Phase = (rig.Phase + speed * dt / STRIDE) % 1
			basePose(rig, now, pose)
			summonPose(rig, serverNow - (model:GetAttribute("SpawnedAt") or -100), pose)
			attackPose(rig, now, pose)
			-- the rune core pulses
			if rig.Core and rig.Core.Parent then
				local pulse = 1 + 0.12 * math.sin(now * 3 + rig.Seed)
				rig.Core.Size = rig.CoreSize * pulse
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
