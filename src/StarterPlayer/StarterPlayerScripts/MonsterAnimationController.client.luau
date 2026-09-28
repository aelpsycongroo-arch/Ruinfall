-- MonsterAnimationController: procedural animations for the Stone Warden jungle monsters
-- (Blender rig in ServerStorage.MonsterAssets). Drives Motor6D.Transform locally:
--   Walk   - diagonal trot, stride synced to real ground speed, body bob + head sway
--   Idle   - slow breathing and looking around (alert crouch while in combat)
--   Attack - wind-up, lunge + head slam + claw swipe (server bumps AttackSeq)
--   Death  - legs buckle, body slams down, eye goes dark, sinks and fades (server sets DiedAt)
-- Purely visual; all gameplay stays on the server.

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
local TAG = "RF_Monster"
local LEGS = { "FR", "FL", "BR", "BL" }
local LEG_PHASE = { FR = 0, BL = 0, FL = 0.5, BR = 0.5 } -- trot: diagonal pairs move together
local LEG_SIDE = { FR = 1, BR = 1, FL = -1, BL = -1 }
local LEG_FRONT = { FR = true, FL = true, BR = false, BL = false }
local STRIDE = 3.6 -- studs travelled per full gait cycle at scale 1
local ATTACK_TIME = 0.6
local DEATH_COLLAPSE = 0.55
local DEATH_FADE_START = 1.25
local DEATH_FADE_END = 2.3
local TAU = math.pi * 2

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

local function findMotor(model, partName, motorName)
	local part = model:FindFirstChild(partName)
	return part and part:FindFirstChild(motorName)
end

local function setup(model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local torso = model:WaitForChild("Torso", 5)
	if not torso or not torso:WaitForChild("RootJoint", 5) or not model.Parent then
		return -- legacy block monster, nothing to animate
	end
	local rig = {
		Model = model,
		Root = model:FindFirstChild("HumanoidRootPart"),
		Scale = model:GetAttribute("RigScale") or 1,
		Motors = {
			Root = torso:FindFirstChild("RootJoint"),
			Neck = findMotor(model, "Head", "Neck"),
		},
		Phase = math.random(),
		Move = 0,
		Alert = 0,
		Seed = math.random() * 10,
		LastSeq = model:GetAttribute("AttackSeq") or 0,
		AttackStart = -10,
		AttackSide = 1,
		Faded = {},
	}
	for _, leg in ipairs(LEGS) do
		rig.Motors[leg .. "_Hip"] = findMotor(model, leg .. "U", leg .. "_Hip")
		rig.Motors[leg .. "_Knee"] = findMotor(model, leg .. "L", leg .. "_Knee")
	end
	rig.Eye = model:FindFirstChild("Head_Eye")
	rig.EyeColor = rig.Eye and rig.Eye.Color
	rig.EyeLight = rig.Eye and rig.Eye:FindFirstChildOfClass("PointLight")
	rig.EyeLightBrightness = rig.EyeLight and rig.EyeLight.Brightness
	rig.Parts = {}
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
			rig.AttackSide = seq % 2 == 0 and 1 or -1
		end
	end)
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			rigs[model] = nil
		end
	end)
	rigs[model] = rig
end

-- Pose builders --------------------------------------------------------------------------
-- Every pose is a table of joint -> CFrame offsets (joint space == model space: X right,
-- Y up, -Z forward). Positive X rotation swings a leg forward / pitches the front upward.

local function walkPose(rig, now, pose)
	local s = rig.Scale
	local move = rig.Move
	local cycle = rig.Phase * TAU
	local idleT = now + rig.Seed
	-- Body: trot bob (two bumps per cycle) + side roll; idle breathing
	local bob = math.abs(math.sin(cycle)) * 0.14 * s * move
	local breathe = math.sin(idleT * 1.8) * 0.035 * s * (1 - move)
	local crouch = -0.12 * s * rig.Alert * (1 - move)
	pose.Root = CFrame.new(0, bob + breathe + crouch, 0)
		* angles(math.sin(cycle * 2) * 0.04 * move - 0.05 * rig.Alert, math.sin(cycle) * 0.05 * move, math.sin(cycle) * 0.06 * move)
	-- Head: counter-bob while walking, look around while idle, low and focused in combat
	local lookYaw = math.sin(idleT * 0.45) * 0.35 * (1 - move) * (1 - rig.Alert)
	local lookPitch = math.sin(idleT * 0.9) * 0.06 * (1 - move)
	pose.Neck = angles(-math.sin(cycle * 2) * 0.08 * move + lookPitch - 0.12 * rig.Alert, lookYaw - math.sin(cycle) * 0.06 * move, 0)
	-- Legs
	for _, leg in ipairs(LEGS) do
		local p = (rig.Phase + LEG_PHASE[leg]) * TAU
		local swing = math.sin(p) * 0.55 * move
		local lift = math.max(0, math.cos(p)) * move -- leg travelling forward -> lift the foot
		local knee = LEG_FRONT[leg] and (-lift * 0.75) or (lift * 0.6)
		local spread = LEG_SIDE[leg] * 0.05 * (1 - move) * math.sin(idleT * 1.8)
		pose[leg .. "_Hip"] = angles(swing, 0, spread)
		pose[leg .. "_Knee"] = angles(knee, 0, 0)
	end
end

local function attackPose(rig, now, pose)
	local t = now - rig.AttackStart
	if t < 0 or t > ATTACK_TIME then
		return
	end
	local s = rig.Scale
	local u = t / ATTACK_TIME
	-- wind-up: rear back (0 -> 0.2), strike: lunge forward (0.2 -> 0.4), recover (0.4 -> 1)
	local wind = u < 0.2 and smooth(u / 0.2) or (1 - smooth((u - 0.2) / 0.12))
	local strike = u < 0.2 and 0 or (u < 0.36 and smooth((u - 0.2) / 0.16) or (1 - smooth((u - 0.36) / 0.64)))
	local side = rig.AttackSide
	pose.Root = pose.Root
		* CFrame.new(0, 0.25 * s * wind - 0.2 * s * strike, 0.45 * s * wind - 0.75 * s * strike)
		* angles(0.28 * wind - 0.22 * strike, 0.12 * side * strike, -0.08 * side * strike)
	pose.Neck = pose.Neck * angles(0.45 * wind - 0.55 * strike, -0.2 * side * strike, 0)
	-- claw swipe with one front paw, the other plants
	local swipe = side == 1 and "FR" or "FL"
	local plant = side == 1 and "FL" or "FR"
	pose[swipe .. "_Hip"] = pose[swipe .. "_Hip"] * angles(0.9 * wind + 0.5 * strike, 0, 0.35 * LEG_SIDE[swipe] * wind - 0.25 * LEG_SIDE[swipe] * strike)
	pose[swipe .. "_Knee"] = pose[swipe .. "_Knee"] * angles(-0.9 * wind + 0.2 * strike, 0, 0)
	pose[plant .. "_Hip"] = pose[plant .. "_Hip"] * angles(-0.25 * strike, 0, 0)
	for _, leg in ipairs({ "BR", "BL" }) do
		-- hind legs push off during the lunge
		pose[leg .. "_Hip"] = pose[leg .. "_Hip"] * angles(0.25 * wind - 0.35 * strike, 0, 0)
		pose[leg .. "_Knee"] = pose[leg .. "_Knee"] * angles(0.3 * wind - 0.2 * strike, 0, 0)
	end
end

local function deathPose(rig, since, pose)
	local s = rig.Scale
	local c = smooth(since / DEATH_COLLAPSE)
	-- small rebound after the body hits the ground
	local bounce = since > DEATH_COLLAPSE and math.sin(math.clamp((since - DEATH_COLLAPSE) / 0.25, 0, 1) * math.pi) * 0.12 * s or 0
	local sink = smooth((since - DEATH_FADE_START) / (DEATH_FADE_END - DEATH_FADE_START)) * 2.2 * s
	local tilt = rig.DeathSide
	pose.Root = CFrame.new(0, -0.95 * s * c + bounce - sink, -0.2 * s * c) * angles(-0.18 * c, 0.1 * tilt * c, 0.22 * tilt * c)
	pose.Neck = angles(-0.55 * c + 0.1 * bounce, 0.35 * tilt * c, 0.2 * tilt * c)
	for _, leg in ipairs(LEGS) do
		local side = LEG_SIDE[leg]
		local front = LEG_FRONT[leg]
		-- legs buckle outward and fold flat under the body
		pose[leg .. "_Hip"] = angles((front and -0.35 or 0.35) * c, 0, side * 0.95 * c)
		pose[leg .. "_Knee"] = angles((front and 0.5 or -0.4) * c, 0, side * 0.35 * c)
	end
	-- eye dims out
	if rig.Eye and rig.EyeColor then
		local dim = smooth(since / 0.8)
		rig.Eye.Color = rig.EyeColor:Lerp(Color3.fromRGB(35, 18, 10), dim)
		if rig.EyeLight then
			rig.EyeLight.Brightness = (rig.EyeLightBrightness or 1) * (1 - dim)
		end
	end
	-- crumble away
	local fade = smooth((since - DEATH_FADE_START) / (DEATH_FADE_END - DEATH_FADE_START))
	if fade > 0 then
		for _, part in ipairs(rig.Parts) do
			part.LocalTransparencyModifier = fade
		end
	end
end

local function apply(rig, pose)
	for name, motor in pairs(rig.Motors) do
		if motor and motor.Parent then
			motor.Transform = pose[name] or CFrame.identity
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
			continue -- uploaded Monster_* animations drive this rig (CreatureAnimationController)
		end
		local pose = {}
		local diedAt = model:GetAttribute("DiedAt")
		if diedAt then
			if not rig.DeathSide then
				rig.DeathSide = math.random() < 0.5 and -1 or 1
			end
			deathPose(rig, math.max(0, serverNow - diedAt), pose)
		else
			local speed = 0
			if rig.Root and rig.Root.Parent then
				local v = rig.Root.AssemblyLinearVelocity
				speed = Vector3.new(v.X, 0, v.Z).Magnitude
			end
			local targetMove = math.clamp((speed - 0.6) / 6, 0, 1)
			rig.Move = lerp(rig.Move, targetMove, math.clamp(dt * 8, 0, 1))
			local state = model:GetAttribute("AIState")
			rig.Alert = lerp(rig.Alert, state == "Chase" and 1 or 0, math.clamp(dt * 4, 0, 1))
			-- advance the gait by distance travelled so feet do not slide
			local previousPhase = rig.Phase
			rig.Phase = (rig.Phase + speed * dt / (STRIDE * rig.Scale)) % 1
			if rig.Move > 0.3 then
				-- trot: a diagonal pair of feet plants twice per cycle
				for _, contact in ipairs({ 0.25, 0.75 }) do
					if crossed(previousPhase, rig.Phase, contact) then
						marker("Footstep", model, { Volume = rig.Move })
					end
				end
			end
			walkPose(rig, now, pose)
			attackPose(rig, now, pose)
			if not rig.HitFired and now - rig.AttackStart >= ATTACK_TIME * 0.3 and now - rig.AttackStart < ATTACK_TIME then
				rig.HitFired = true
				marker("AttackHit", model) -- lunge / slam lands
			end
		end
		apply(rig, pose)
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
