-- AttackAnimationController: procedural, class-specific attack and ability animations.
-- Visual only: every client animates every hero (players and bots) by offsetting the
-- R15 joints whenever the server-replicated LastAttackAt / AbilityReadyAt
-- (classic rigs: Motor6D.C0; upgraded avatar joints: the kinematic AnimationConstraint's
-- parent-side rig attachment)
-- attributes change. No assets to upload and no effect on gameplay or hit timing.

-- Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Uploaded animations (Ruinfall Asset Porter) replace a procedural swing when their slot is set:
-- <Class>_Attack, <Class>_Ability, Skill_<AbilityId>  (see Shared.AnimationLibrary)
local AnimationLibrary = nil
pcall(function()
	AnimationLibrary = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("AnimationLibrary", 10))
end)

-- Constants
local HERO_TAG = "RF_Hero"
local JOINTS = {
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	Waist = "UpperTorso", Neck = "Head",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", LeftHip = "LeftUpperLeg",
}
local function R(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

-- Keyframes: { T = 0..1, Pose = { Joint = CFrame } }; joints missing from a pose are neutral.
local ANIMATIONS = {
	Fighter = {
		Attack = { Duration = 0.46, Keys = {
			{ T = 0.36, Pose = { RightShoulder = R(2.6, 0, 0.45), RightElbow = R(0.7), RightWrist = R(0.3), Waist = R(0.08, -0.45), LeftShoulder = R(0.5, 0, -0.25) } },
			{ T = 0.62, Pose = { RightShoulder = R(0.55, 0, -0.55), RightElbow = R(0.15), RightWrist = R(-0.7), Waist = R(-0.18, 0.5), LeftShoulder = R(-0.3, 0, -0.2) } },
			{ T = 0.8, Pose = { RightShoulder = R(0.45, 0, -0.45), RightElbow = R(0.2), RightWrist = R(-0.5), Waist = R(-0.1, 0.35) } },
		} },
		Ability = { Duration = 0.7, Keys = {
			{ T = 0.3, Pose = { RightShoulder = R(2.5, 0, 0.7), LeftShoulder = R(2.5, 0, -0.7), RightElbow = R(0.4), LeftElbow = R(0.4), Waist = R(0.28), Neck = R(0.35) } },
			{ T = 0.7, Pose = { RightShoulder = R(2.4, 0, 0.8), LeftShoulder = R(2.4, 0, -0.8), RightElbow = R(0.5), LeftElbow = R(0.5), Waist = R(0.22), Neck = R(0.3) } },
		} },
	},
	Assassin = {
		Attack = { Duration = 0.32, Alternate = true, Keys = {
			{ T = 0.35, Pose = { RightShoulder = R(0.5, 0, 0.25), RightElbow = R(1.7), Waist = R(0, -0.3), LeftShoulder = R(0.3, 0, -0.2), LeftElbow = R(0.6) } },
			{ T = 0.6, Pose = { RightShoulder = R(1.5, 0, -0.1), RightElbow = R(0.05), RightWrist = R(-0.2), Waist = R(-0.15, 0.35), LeftShoulder = R(0.2, 0, -0.2), LeftElbow = R(0.9) } },
		} },
		Ability = { Duration = 0.4, Keys = {
			{ T = 0.35, Pose = { RightShoulder = R(-0.9, 0, 0.35), LeftShoulder = R(-0.9, 0, -0.35), Waist = R(-0.4), Neck = R(0.3) } },
			{ T = 0.75, Pose = { RightShoulder = R(-0.7, 0, 0.3), LeftShoulder = R(-0.7, 0, -0.3), Waist = R(-0.3), Neck = R(0.25) } },
		} },
	},
	Mage = {
		Attack = { Duration = 0.5, Keys = {
			{ T = 0.4, Pose = { RightShoulder = R(1.25, 0, 0.15), RightElbow = R(0.45), RightWrist = R(-1.6), Waist = R(0.12, -0.15), LeftShoulder = R(0.6, 0, -0.25), LeftElbow = R(0.6) } },
			{ T = 0.62, Pose = { RightShoulder = R(1.5), RightElbow = R(0), RightWrist = R(-2.3), Waist = R(-0.15, 0.1), LeftShoulder = R(1.2, 0, -0.1), LeftElbow = R(0.2) } },
			{ T = 0.8, Pose = { RightShoulder = R(1.3), RightElbow = R(0.1), RightWrist = R(-2.0), Waist = R(-0.1), LeftShoulder = R(0.9, 0, -0.1) } },
		} },
		Ability = { Duration = 0.65, Keys = {
			{ T = 0.35, Pose = { RightShoulder = R(2.8, 0, 0.1), RightElbow = R(0.2), RightWrist = R(-0.5), LeftShoulder = R(2.2, 0, -0.5), Waist = R(0.2), Neck = R(0.3) } },
			{ T = 0.6, Pose = { RightShoulder = R(1.4), RightWrist = R(-2.2), LeftShoulder = R(1.3, 0, -0.3), Waist = R(-0.25) } },
		} },
	},
	Marksman = {
		-- Authored in Blender (Documents/RuinfallAssets/animations/Marksman_Attack.blend, action
		-- Marksman_Attack_Improved) and exported with its Export_To_Roblox.py text block:
		-- nock -> full side-on draw (elbow back, hand at the jaw, head on target) -> short hold ->
		-- snap release early (the arrow leaves on the attack) -> follow-through -> recover.
		Attack = { Duration = 0.5, Keys = {
			{ T = 0.12, Pose = { Waist = R(0.03, -0.45, 0), Neck = R(-0.019, 0.36, 0.007), LeftShoulder = R(1.265, 0.144, -0.428), LeftElbow = R(0.35, 0, 0), LeftWrist = R(-1.584, 0, 0), RightShoulder = R(0.789, 1.249, 0.495), RightElbow = R(1.257, 0, 0), LeftHip = R(0.09, 0, 0), RightHip = R(-0.09, 0, 0) } },
			{ T = 0.26, Pose = { Waist = R(0, -0.72, 0), Neck = R(0, 0.576, 0), LeftShoulder = R(1.571, 0, -0.72), LeftElbow = R(0.03, 0, 0), LeftWrist = R(-1.601, 0, 0), RightShoulder = R(-1.423, 2.02, -0.479), RightElbow = R(2.564, 0, 0), RightWrist = R(0.15, 0, 0), LeftHip = R(0.12, 0, 0), RightHip = R(-0.12, 0, 0) } },
			{ T = 0.34, Pose = { Waist = R(-0.02, -0.75, 0), Neck = R(0.015, 0.6, -0.008), LeftShoulder = R(1.571, 0, -0.75), LeftElbow = R(0.02, 0, 0), LeftWrist = R(-1.591, 0, 0), RightShoulder = R(-1.432, 2.121, -0.52), RightElbow = R(2.567, 0, 0), RightWrist = R(0.2, 0, 0), LeftHip = R(0.12, 0, 0), RightHip = R(-0.12, 0, 0) } },
			{ T = 0.38, Pose = { Waist = R(-0.07, -0.68, 0), Neck = R(0.049, 0.543, -0.025), LeftShoulder = R(1.695, -0.1, -0.674), LeftElbow = R(0.03, 0, 0), LeftWrist = R(-1.759, 0, 0), RightShoulder = R(-0.444, -0.987, 1.529), RightElbow = R(0.26, 0, 0), RightWrist = R(-0.3, 0, 0), LeftHip = R(0.12, 0, 0), RightHip = R(-0.12, 0, 0) } },
			{ T = 0.55, Pose = { Waist = R(-0.03, -0.58, 0), Neck = R(0.02, 0.464, -0.009), LeftShoulder = R(1.604, -0.022, -0.58), LeftElbow = R(0.06, 0, 0), LeftWrist = R(-1.671, 0, 0), RightShoulder = R(-0.737, -0.682, 1.193), RightElbow = R(0.133, 0, 0), RightWrist = R(-0.2, 0, 0), LeftHip = R(0.1, 0, 0), RightHip = R(-0.1, 0, 0) } },
			{ T = 0.78, Pose = { Waist = R(-0.01, -0.203, 0.002), Neck = R(0.006, 0.162, -0.002), LeftShoulder = R(0.559, 0.105, -0.198), LeftElbow = R(0.021, 0, 0), LeftWrist = R(-0.585, 0, 0), RightShoulder = R(-0.337, -0.133, 0.453), RightElbow = R(0.047, 0, 0), RightWrist = R(-0.07, 0, 0), LeftHip = R(0.035, 0, 0), RightHip = R(-0.035, 0, 0) } },
		} },
		Ability = { Duration = 0.4, Keys = {
			{ T = 0.3, Pose = { LeftShoulder = R(1.55, 0, 0.1), LeftWrist = R(-1.55), RightShoulder = R(1.5, 0, 0.1), RightElbow = R(2.3), Waist = R(-0.25, -0.3) } },
			{ T = 0.6, Pose = { LeftShoulder = R(1.5, 0, 0.1), LeftWrist = R(-1.5), RightShoulder = R(1.2, 0, 0.7), RightElbow = R(1.1), Waist = R(-0.2, -0.3) } },
		} },
	},
	Tank = {
		Attack = { Duration = 0.55, Keys = {
			{ T = 0.42, Pose = { RightShoulder = R(2.8, 0, 0.25), RightElbow = R(0.9), Waist = R(0.18, -0.2), LeftShoulder = R(0.9, 0, -0.1), LeftElbow = R(0.8) } },
			{ T = 0.64, Pose = { RightShoulder = R(0.7, 0, -0.15), RightElbow = R(0.1), RightWrist = R(-0.4), Waist = R(-0.32, 0.2), LeftShoulder = R(0.8, 0, -0.1), LeftElbow = R(0.8) } },
			{ T = 0.8, Pose = { RightShoulder = R(0.6, 0, -0.1), RightElbow = R(0.15), Waist = R(-0.2, 0.1), LeftShoulder = R(0.7), LeftElbow = R(0.7) } },
		} },
		Ability = { Duration = 0.7, Keys = {
			{ T = 0.35, Pose = { LeftShoulder = R(2.0, 0, -0.2), LeftElbow = R(0.5), RightShoulder = R(2.6, 0, 0.3), RightElbow = R(0.6), Waist = R(0.25), Neck = R(0.2) } },
			{ T = 0.58, Pose = { LeftShoulder = R(1.1), LeftElbow = R(0.3), RightShoulder = R(0.9), RightElbow = R(0.2), Waist = R(-0.45), Neck = R(-0.1) } },
			{ T = 0.8, Pose = { LeftShoulder = R(1.0), RightShoulder = R(0.8), Waist = R(-0.35) } },
		} },
	},
}
-- Mythic item skills (E/R), keyed by ability id - played on every client when the
-- server sets ItemCastAt / ItemCastAbility on the caster.
local ITEM_ANIMATIONS = {
	HeavyKick = { Duration = 0.55, Keys = {
		{ T = 0.3, Pose = { RightHip = R(-0.5), RightKnee = R(-1.3), Waist = R(0.05, -0.2), LeftShoulder = R(0.4, 0, -0.3), RightShoulder = R(-0.3, 0, 0.3) } },
		{ T = 0.55, Pose = { RightHip = R(1.45), RightKnee = R(-0.05), Waist = R(0.28, 0.1), LeftShoulder = R(0.7, 0, -0.5), RightShoulder = R(-0.5, 0, 0.4), LeftHip = R(-0.15) } },
		{ T = 0.75, Pose = { RightHip = R(1.2), RightKnee = R(-0.2), Waist = R(0.2), LeftShoulder = R(0.5, 0, -0.4) } },
	} },
	PointStrike = { Duration = 0.4, Keys = {
		{ T = 0.3, Pose = { RightShoulder = R(0.3, 0, 0.3), RightElbow = R(1.8), Waist = R(0.05, -0.35), LeftShoulder = R(0.9, 0, -0.2) } },
		{ T = 0.55, Pose = { RightShoulder = R(1.6, 0, -0.1), RightElbow = R(0), Waist = R(-0.25, 0.35), RightHip = R(0.4), LeftHip = R(-0.4) } },
	} },
	WindPull = { Duration = 0.7, Keys = {
		{ T = 0.3, Pose = { RightShoulder = R(1.6, 0, 0.35), LeftShoulder = R(1.6, 0, -0.35), RightWrist = R(-1.5), Waist = R(-0.15) } },
		{ T = 0.7, Pose = { RightShoulder = R(0.6, 0, 0.5), LeftShoulder = R(0.6, 0, -0.5), RightElbow = R(1.6), LeftElbow = R(1.6), RightWrist = R(-0.8), Waist = R(0.2) } },
	} },
	SpikedScale = { Duration = 0.6, Keys = {
		{ T = 0.4, Pose = { RightShoulder = R(0.3, 0, 0.9), LeftShoulder = R(0.3, 0, -0.9), RightElbow = R(1.3), LeftElbow = R(1.3), Waist = R(0.2), Neck = R(0.3) } },
		{ T = 0.75, Pose = { RightShoulder = R(0.2, 0, 0.8), LeftShoulder = R(0.2, 0, -0.8), RightElbow = R(1.2), LeftElbow = R(1.2), Waist = R(0.15) } },
	} },
	Bulwark = { Duration = 0.6, Keys = {
		{ T = 0.4, Pose = { LeftShoulder = R(1.5, 0, 0.2), LeftElbow = R(0.9), RightShoulder = R(1.2, 0, -0.1), RightElbow = R(1.2), Waist = R(-0.1) } },
		{ T = 0.8, Pose = { LeftShoulder = R(1.4, 0, 0.2), LeftElbow = R(0.9), RightShoulder = R(1.1), RightElbow = R(1.2) } },
	} },
	Blink = { Duration = 0.35, Keys = {
		{ T = 0.4, Pose = { Waist = R(-0.45), RightShoulder = R(-0.7, 0, 0.3), LeftShoulder = R(-0.7, 0, -0.3), RightHip = R(0.5), LeftHip = R(0.5) } },
	} },
	Fireball = { Duration = 0.5, Keys = {
		{ T = 0.35, Pose = { RightShoulder = R(0.4, 0, 0.6), RightElbow = R(1.7), Waist = R(0.05, -0.4), LeftShoulder = R(0.5, 0, -0.3) } },
		{ T = 0.6, Pose = { RightShoulder = R(1.7, 0, -0.1), RightElbow = R(0.1), RightWrist = R(-0.6), Waist = R(-0.2, 0.35), LeftShoulder = R(0.3, 0, -0.4) } },
	} },
	FrostNova = { Duration = 0.6, Keys = {
		{ T = 0.35, Pose = { RightShoulder = R(2.6, 0, 0.3), LeftShoulder = R(2.6, 0, -0.3), Waist = R(-0.2), Neck = R(-0.2) } },
		{ T = 0.6, Pose = { RightShoulder = R(0.5, 0, 1.1), LeftShoulder = R(0.5, 0, -1.1), Waist = R(0.35), RightHip = R(0.5), LeftHip = R(0.5), RightKnee = R(-0.8), LeftKnee = R(-0.8) } },
	} },
	Whirlwind = { Duration = 0.6, Keys = {
		{ T = 0.3, Pose = { Waist = R(0, -1.2), RightShoulder = R(0.3, 0, 1.3), LeftShoulder = R(0.2, 0, -1.2) } },
		{ T = 0.6, Pose = { Waist = R(0, 1.4), RightShoulder = R(0.3, 0, 1.4), LeftShoulder = R(0.2, 0, -1.3) } },
		{ T = 0.85, Pose = { Waist = R(0, 0.4), RightShoulder = R(0.3, 0, 1.2), LeftShoulder = R(0.2, 0, -1.1) } },
	} },
	CrushingLeap = { Duration = 0.55, Keys = {
		{ T = 0.4, Pose = { RightShoulder = R(2.8), LeftShoulder = R(2.8), Waist = R(-0.3), RightHip = R(0.8), LeftHip = R(0.3), RightKnee = R(-1.0) } },
		{ T = 0.7, Pose = { RightShoulder = R(0.6), LeftShoulder = R(0.6), Waist = R(0.5), RightHip = R(0.9), LeftHip = R(0.9), RightKnee = R(-1.2), LeftKnee = R(-1.2) } },
	} },
	RallyingHorn = { Duration = 0.7, Keys = {
		{ T = 0.4, Pose = { RightShoulder = R(2.2, 0, -0.4), RightElbow = R(1.5), Neck = R(-0.35), Waist = R(-0.25), LeftShoulder = R(0.5, 0, -0.9) } },
		{ T = 0.8, Pose = { RightShoulder = R(2.1, 0, -0.4), RightElbow = R(1.5), Neck = R(-0.3), Waist = R(-0.2), LeftShoulder = R(1.0, 0, -1.2) } },
	} },
	SummonGolem = { Duration = 0.8, Keys = {
		{ T = 0.4, Pose = { RightShoulder = R(2.4, 0, 0.4), LeftShoulder = R(2.4, 0, -0.4), Neck = R(-0.3), Waist = R(-0.2) } },
		{ T = 0.75, Pose = { RightShoulder = R(1.2, 0, 0.3), LeftShoulder = R(1.2, 0, -0.3), Waist = R(0.45), RightHip = R(0.6), LeftHip = R(0.6), RightKnee = R(-0.9), LeftKnee = R(-0.9) } },
	} },
}
-- new role skills that reuse an existing pose
ITEM_ANIMATIONS.ShadowDash = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.SmokeVeil = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.PiercingArrow = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.Tumble = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.ShieldBash = ITEM_ANIMATIONS.Bulwark
-- boot skills (right mouse)
ITEM_ANIMATIONS.CripplingStrike = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.BladeDance = ITEM_ANIMATIONS.Whirlwind
ITEM_ANIMATIONS.Vanish = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.ShadeLeap = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.GaleBurst = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.ArcaneTempo = ITEM_ANIMATIONS.FrostNova
ITEM_ANIMATIONS.Tailwind = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.SearingRay = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.PhaseShift = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.PinningShot = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.DeadeyeRhythm = ITEM_ANIMATIONS.Bulwark
ITEM_ANIMATIONS.EvasiveStride = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.RainOfArrows = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.EarthenShackles = ITEM_ANIMATIONS.CrushingLeap
ITEM_ANIMATIONS.ThornedRhythm = ITEM_ANIMATIONS.SpikedScale
ITEM_ANIMATIONS.UnstoppableMarch = ITEM_ANIMATIONS.SpikedScale
ITEM_ANIMATIONS.ShoulderCharge = ITEM_ANIMATIONS.Bulwark
ITEM_ANIMATIONS.BattleTrance = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.Warpath = ITEM_ANIMATIONS.Whirlwind
ITEM_ANIMATIONS.SkullSplitter = ITEM_ANIMATIONS.CrushingLeap
ITEM_ANIMATIONS.LeapingBound = ITEM_ANIMATIONS.CrushingLeap
-- reworked mythic skills (Mage skills are cast at range)
ITEM_ANIMATIONS.GlacialPrison = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.ArcaneBarrage = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.FanOfKnives = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.RapidVolley = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.DrumsOfWar = ITEM_ANIMATIONS.RallyingHorn

local MIRROR = { RightShoulder = "LeftShoulder", LeftShoulder = "RightShoulder", RightElbow = "LeftElbow", LeftElbow = "RightElbow", RightWrist = "LeftWrist", LeftWrist = "RightWrist" }

-- State
local records = {} -- [model] = record
local active = {} -- [record] = playing animation

-- Functions
local function ease(alpha)
	return alpha < 0.5 and 2 * alpha * alpha or 1 - (-2 * alpha + 2) ^ 2 / 2
end

local function mirrorPose(pose)
	local mirrored = {}
	for joint, offset in pairs(pose) do
		local x, y, z = offset:ToEulerAnglesXYZ()
		if MIRROR[joint] then
			mirrored[MIRROR[joint]] = R(x, -y, -z)
		else
			mirrored[joint] = R(x, -y, -z)
		end
	end
	return mirrored
end

-- A joint handle: { Instance, Property } whose CFrame we offset.
local function findJoints(model)
	local joints = {}
	for jointName, partName in pairs(JOINTS) do
		local part = model:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint then
			if joint:IsA("Motor6D") then
				joints[jointName] = { Instance = joint, Property = "C0" }
			elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
				joints[jointName] = { Instance = joint.Attachment0, Property = "CFrame" }
			end
		end
	end
	return joints
end

local function restore(record)
	for jointName, handle in pairs(record.Joints) do
		local base = record.Base[jointName]
		if base and handle.Instance.Parent then
			handle.Instance[handle.Property] = base
		end
	end
	active[record] = nil
end

local function play(record, kind, itemAbility)
	local model = record.Model
	if AnimationLibrary and not model:GetAttribute("Dead") then
		local key = kind == "Item" and ("Skill_" .. tostring(itemAbility)) or ((model:GetAttribute("Class") or "") .. "_" .. kind)
		local ok, track = pcall(AnimationLibrary.Play, model, key, 0.05, 1, Enum.AnimationPriority.Action)
		if ok and track then
			return -- uploaded animation plays instead of the procedural one
		end
	end
	local classAnimations = ANIMATIONS[model:GetAttribute("Class") or ""]
	local definition = classAnimations and classAnimations[kind]
	if kind == "Item" then
		-- item skills: dedicated animation, or fall back to the class attack/ability swing
		definition = ITEM_ANIMATIONS[itemAbility or ""] or (itemAbility == "CleavingArc" and classAnimations and classAnimations.Attack) or (classAnimations and classAnimations.Ability)
	end
	if not definition or model:GetAttribute("Dead") then
		return
	end
	-- (re)capture neutral C0s when idle so avatar rescaling is respected
	if not active[record] then
		record.Joints = findJoints(model)
		record.Base = {}
		for jointName, handle in pairs(record.Joints) do
			record.Base[jointName] = handle.Instance[handle.Property]
		end
	end
	local keys = definition.Keys
	if definition.Alternate then
		record.Flip = not record.Flip
		if record.Flip then
			local flipped = {}
			for index, key in ipairs(keys) do
				flipped[index] = { T = key.T, Pose = mirrorPose(key.Pose) }
			end
			keys = flipped
		end
	end
	local duration = definition.Duration
	if kind == "Attack" then
		local cooldown = model:GetAttribute("AttackCooldown")
		if cooldown and cooldown > 0 then
			duration = math.min(duration, cooldown * 0.9)
		end
	end
	active[record] = { Keys = keys, Duration = math.max(0.12, duration), Elapsed = 0 }
end

local function poseAt(keys, alpha)
	-- implicit neutral keys at 0 and 1
	local previousT, previousPose = 0, nil
	for _, key in ipairs(keys) do
		if alpha <= key.T then
			return previousPose, key.Pose, ease((alpha - previousT) / math.max(1e-3, key.T - previousT))
		end
		previousT, previousPose = key.T, key.Pose
	end
	return previousPose, nil, ease((alpha - previousT) / math.max(1e-3, 1 - previousT))
end

local function step(dt)
	for record, animation in pairs(active) do
		animation.Elapsed += dt
		local alpha = animation.Elapsed / animation.Duration
		if alpha >= 1 or not record.Model.Parent then
			restore(record)
		else
			local fromPose, toPose, t = poseAt(animation.Keys, alpha)
			for jointName, handle in pairs(record.Joints) do
				local base = record.Base[jointName]
				if base and handle.Instance.Parent then
					local a = fromPose and fromPose[jointName] or CFrame.identity
					local b = toPose and toPose[jointName] or CFrame.identity
					handle.Instance[handle.Property] = base * a:Lerp(b, t)
				end
			end
		end
	end
end

local function track(model)
	if records[model] or not model:IsA("Model") then
		return
	end
	local record = { Model = model, Joints = {}, Base = {}, Connections = {} }
	records[model] = record
	local lastAttack = model:GetAttribute("LastAttackAt") or 0
	local lastAbility = model:GetAttribute("AbilityReadyAt") or 0
	table.insert(record.Connections, model:GetAttributeChangedSignal("LastAttackAt"):Connect(function()
		local value = model:GetAttribute("LastAttackAt") or 0
		if value > lastAttack then
			play(record, "Attack")
		end
		lastAttack = value
	end))
	table.insert(record.Connections, model:GetAttributeChangedSignal("AbilityReadyAt"):Connect(function()
		local value = model:GetAttribute("AbilityReadyAt") or 0
		if value > lastAbility and value > workspace:GetServerTimeNow() then
			play(record, "Ability")
		end
		lastAbility = value
	end))
	local lastItemCast = model:GetAttribute("ItemCastAt") or 0
	table.insert(record.Connections, model:GetAttributeChangedSignal("ItemCastAt"):Connect(function()
		local value = model:GetAttribute("ItemCastAt") or 0
		if value > lastItemCast then
			play(record, "Item", model:GetAttribute("ItemCastAbility"))
		end
		lastItemCast = value
	end))
	table.insert(record.Connections, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			active[record] = nil
			for _, connection in ipairs(record.Connections) do
				connection:Disconnect()
			end
			records[model] = nil
		end
	end))
end

-- Init
for _, model in ipairs(CollectionService:GetTagged(HERO_TAG)) do
	track(model)
end
CollectionService:GetInstanceAddedSignal(HERO_TAG):Connect(track)
RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(step, dt)
	if not ok then
		warn("[Ruinfall] Attack animation error:", err)
	end
end)
