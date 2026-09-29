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
		-- 3-hit sword combo (resets after a pause): wide forehand slash -> backhand return ->
		-- stepping overhead chop. Each swing: quick wind-up (Out), snapping strike (Snap), slow
		-- settle, with the hips and legs stepping into the blow.
		Combo = {
			{ Duration = 0.44, Keys = {
				{ T = 0.3, Ease = "Out", Pose = { RightShoulder = R(1.9, 0.5, 1.2), RightElbow = R(0.9), RightWrist = R(0.4), Waist = R(0.1, -0.6), Neck = R(0, 0.35), LeftShoulder = R(0.6, 0, -0.4), LeftHip = R(0.25), RightHip = R(-0.15) } },
				{ T = 0.52, Ease = "Snap", Pose = { RightShoulder = R(1.3, -0.4, -1.1), RightElbow = R(0.1), RightWrist = R(-0.6), Waist = R(-0.12, 0.65), Neck = R(0, -0.35), LeftShoulder = R(-0.2, 0, -0.5), RightHip = R(0.4), RightKnee = R(-0.35), LeftHip = R(-0.2) } },
				{ T = 0.72, Ease = "Out", Pose = { RightShoulder = R(1.0, -0.3, -0.9), RightElbow = R(0.2), RightWrist = R(-0.5), Waist = R(-0.08, 0.5), Neck = R(0, -0.25), RightHip = R(0.3), RightKnee = R(-0.25) } },
			} },
			{ Duration = 0.42, Keys = {
				{ T = 0.28, Ease = "Out", Pose = { RightShoulder = R(1.4, -0.5, -1.3), RightElbow = R(1.1), RightWrist = R(-0.5), Waist = R(0.05, 0.6), Neck = R(0, -0.3), LeftShoulder = R(0.4, 0, -0.3), RightHip = R(0.2) } },
				{ T = 0.5, Ease = "Snap", Pose = { RightShoulder = R(1.5, 0.5, 1.25), RightElbow = R(0.15), RightWrist = R(0.5), Waist = R(-0.1, -0.7), Neck = R(0, 0.4), LeftShoulder = R(0.2, 0, -0.9), LeftHip = R(0.4), LeftKnee = R(-0.35), RightHip = R(-0.2) } },
				{ T = 0.72, Ease = "Out", Pose = { RightShoulder = R(1.2, 0.4, 1.0), RightElbow = R(0.25), RightWrist = R(0.3), Waist = R(-0.05, -0.5), Neck = R(0, 0.3), LeftHip = R(0.3), LeftKnee = R(-0.25) } },
			} },
			{ Duration = 0.55, Keys = {
				{ T = 0.36, Ease = "Out", Pose = { RightShoulder = R(3.0, 0, 0.25), LeftShoulder = R(2.7, 0, -0.25), RightElbow = R(0.8), LeftElbow = R(0.8), RightWrist = R(0.5), Waist = R(0.3), Neck = R(-0.2), RightHip = R(-0.1), LeftHip = R(0.15) } },
				{ T = 0.52, Ease = "Snap", Pose = { RightShoulder = R(0.6, 0, 0.1), LeftShoulder = R(0.5, 0, -0.1), RightElbow = R(0.05), LeftElbow = R(0.1), RightWrist = R(-0.7), Waist = R(-0.45), Neck = R(0.25), RightHip = R(0.7), RightKnee = R(-0.7), LeftHip = R(-0.35) } },
				{ T = 0.78, Ease = "Out", Pose = { RightShoulder = R(0.5), LeftShoulder = R(0.45), RightWrist = R(-0.5), Waist = R(-0.3), Neck = R(0.15), RightHip = R(0.5), RightKnee = R(-0.5), LeftHip = R(-0.2) } },
			} },
		},
		Trail = true,
		Ability = { Duration = 0.7, Keys = {
			{ T = 0.3, Pose = { RightShoulder = R(2.5, 0, 0.7), LeftShoulder = R(2.5, 0, -0.7), RightElbow = R(0.4), LeftElbow = R(0.4), Waist = R(0.28), Neck = R(0.35) } },
			{ T = 0.7, Pose = { RightShoulder = R(2.4, 0, 0.8), LeftShoulder = R(2.4, 0, -0.8), RightElbow = R(0.5), LeftElbow = R(0.5), Waist = R(0.22), Neck = R(0.3) } },
		} },
	},
	Assassin = {
		-- fast dagger string: right stab -> left stab -> crossing double slash
		Combo = {
			{ Duration = 0.3, Keys = {
				{ T = 0.3, Ease = "Out", Pose = { RightShoulder = R(0.5, 0, 0.35), RightElbow = R(1.9), Waist = R(0.05, -0.4), LeftShoulder = R(0.4, 0, -0.3), LeftElbow = R(0.9), RightHip = R(-0.2) } },
				{ T = 0.5, Ease = "Snap", Pose = { RightShoulder = R(1.6, 0, -0.15), RightElbow = R(0), RightWrist = R(-0.2), Waist = R(-0.2, 0.45), LeftShoulder = R(0.2, 0, -0.3), LeftElbow = R(1.0), RightHip = R(0.45), RightKnee = R(-0.4) } },
			} },
			{ Duration = 0.3, Keys = {
				{ T = 0.3, Ease = "Out", Pose = { LeftShoulder = R(0.5, 0, -0.35), LeftElbow = R(1.9), Waist = R(0.05, 0.4), RightShoulder = R(0.4, 0, 0.3), RightElbow = R(0.9), LeftHip = R(-0.2) } },
				{ T = 0.5, Ease = "Snap", Pose = { LeftShoulder = R(1.6, 0, 0.15), LeftElbow = R(0), LeftWrist = R(-0.2), Waist = R(-0.2, -0.45), RightShoulder = R(0.2, 0, 0.3), RightElbow = R(1.0), LeftHip = R(0.45), LeftKnee = R(-0.4) } },
			} },
			{ Duration = 0.38, Keys = {
				{ T = 0.32, Ease = "Out", Pose = { RightShoulder = R(2.2, 0, 0.9), LeftShoulder = R(2.2, 0, -0.9), RightElbow = R(0.6), LeftElbow = R(0.6), Waist = R(0.2), Neck = R(-0.15) } },
				{ T = 0.52, Ease = "Snap", Pose = { RightShoulder = R(0.9, 0, -0.9), LeftShoulder = R(0.9, 0, 0.9), RightElbow = R(0.1), LeftElbow = R(0.1), Waist = R(-0.35), Neck = R(0.2), RightHip = R(0.5), LeftHip = R(0.5), RightKnee = R(-0.6), LeftKnee = R(-0.6) } },
			} },
		},
		Trail = true,
		Ability = { Duration = 0.4, Keys = {
			{ T = 0.35, Pose = { RightShoulder = R(-0.9, 0, 0.35), LeftShoulder = R(-0.9, 0, -0.35), Waist = R(-0.4), Neck = R(0.3) } },
			{ T = 0.75, Pose = { RightShoulder = R(-0.7, 0, 0.3), LeftShoulder = R(-0.7, 0, -0.3), Waist = R(-0.3), Neck = R(0.25) } },
		} },
	},
	Mage = {
		Attack = { Duration = 0.5, Keys = {
			{ T = 0.4, Ease = "Out", Pose = { RightShoulder = R(1.25, 0, 0.15), RightElbow = R(0.45), RightWrist = R(-1.6), Waist = R(0.12, -0.15), LeftShoulder = R(0.6, 0, -0.25), LeftElbow = R(0.6), RightHip = R(-0.15) } },
			{ T = 0.58, Ease = "Snap", Pose = { RightShoulder = R(1.6), RightElbow = R(0), RightWrist = R(-2.3), Waist = R(-0.2, 0.15), LeftShoulder = R(1.2, 0, -0.1), LeftElbow = R(0.2), RightHip = R(0.35), RightKnee = R(-0.3) } },
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
		-- heavy blows behind the shield: overhead smash -> shield bash -> rising uppercut swing
		Combo = {
			{ Duration = 0.56, Keys = {
				{ T = 0.4, Ease = "Out", Pose = { RightShoulder = R(2.9, 0, 0.3), RightElbow = R(0.9), Waist = R(0.2, -0.25), Neck = R(-0.1), LeftShoulder = R(1.1, 0, 0.2), LeftElbow = R(1.0), LeftHip = R(0.15) } },
				{ T = 0.56, Ease = "Snap", Pose = { RightShoulder = R(0.6, 0, -0.15), RightElbow = R(0.05), RightWrist = R(-0.5), Waist = R(-0.4, 0.25), Neck = R(0.2), LeftShoulder = R(1.0, 0, 0.2), LeftElbow = R(1.0), RightHip = R(0.6), RightKnee = R(-0.6), LeftHip = R(-0.25) } },
				{ T = 0.8, Ease = "Out", Pose = { RightShoulder = R(0.5, 0, -0.1), Waist = R(-0.25, 0.15), LeftShoulder = R(0.9, 0, 0.2), LeftElbow = R(0.9), RightHip = R(0.4), RightKnee = R(-0.4) } },
			} },
			{ Duration = 0.5, Keys = {
				{ T = 0.35, Ease = "Out", Pose = { LeftShoulder = R(0.8, 0, 0.5), LeftElbow = R(1.6), Waist = R(0.1, 0.45), RightShoulder = R(0.4, 0, 0.3), RightElbow = R(0.8) } },
				{ T = 0.55, Ease = "Snap", Pose = { LeftShoulder = R(1.6, 0, 0.05), LeftElbow = R(0.2), Waist = R(-0.25, -0.35), RightShoulder = R(0.2, 0, 0.3), LeftHip = R(0.55), LeftKnee = R(-0.5), RightHip = R(-0.2) } },
			} },
			{ Duration = 0.55, Keys = {
				{ T = 0.35, Ease = "Out", Pose = { RightShoulder = R(-0.4, 0, 0.5), RightElbow = R(0.6), Waist = R(0.25, -0.5), LeftShoulder = R(1.1, 0, 0.2), LeftElbow = R(1.0), RightHip = R(-0.2), RightKnee = R(-0.3) } },
				{ T = 0.55, Ease = "Snap", Pose = { RightShoulder = R(2.6, 0, -0.3), RightElbow = R(0.3), RightWrist = R(0.4), Waist = R(-0.2, 0.45), Neck = R(-0.2), LeftShoulder = R(1.0, 0, 0.2), LeftElbow = R(1.0), RightHip = R(0.5), RightKnee = R(-0.4) } },
				{ T = 0.8, Ease = "Out", Pose = { RightShoulder = R(2.0, 0, -0.2), RightElbow = R(0.4), Waist = R(-0.1, 0.3), LeftShoulder = R(0.9, 0, 0.2), LeftElbow = R(0.9) } },
			} },
		},
		Trail = true,
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
-- class active items, set 2
ITEM_ANIMATIONS.Assassinate = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.VenomToxin = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.DeathMark = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.RicochetBlade = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.Evasion = ITEM_ANIMATIONS.Blink
ITEM_ANIMATIONS.ChainLightning = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.Meteor = ITEM_ANIMATIONS.FrostNova
ITEM_ANIMATIONS.VoidRift = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.ManaAegis = ITEM_ANIMATIONS.SpikedScale
ITEM_ANIMATIONS.TimeWarp = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.Snipe = ITEM_ANIMATIONS.WindPull
ITEM_ANIMATIONS.BearTrap = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.HuntersMark = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.Buckshot = ITEM_ANIMATIONS.Bulwark
ITEM_ANIMATIONS.ArrowStorm = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.ChainHook = ITEM_ANIMATIONS.Fireball
ITEM_ANIMATIONS.Challenge = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.StoneForm = ITEM_ANIMATIONS.SpikedScale
ITEM_ANIMATIONS.Fissure = ITEM_ANIMATIONS.CrushingLeap
ITEM_ANIMATIONS.Sanctuary = ITEM_ANIMATIONS.RallyingHorn
ITEM_ANIMATIONS.CrimsonCleave = ITEM_ANIMATIONS.Whirlwind
ITEM_ANIMATIONS.RendingCharge = ITEM_ANIMATIONS.PointStrike
ITEM_ANIMATIONS.BattleStandard = ITEM_ANIMATIONS.CrushingLeap
ITEM_ANIMATIONS.Guillotine = ITEM_ANIMATIONS.CrushingLeap
ITEM_ANIMATIONS.LastStand = ITEM_ANIMATIONS.SpikedScale
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
-- per-key easing: Out = fast start, soft stop (wind-ups / settles); Snap = a whip-fast strike
-- that lands hard; In = slow start; default = smooth in-out
local EASES = {
	InOut = function(a)
		return a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
	end,
	Out = function(a)
		return 1 - (1 - a) ^ 3
	end,
	In = function(a)
		return a * a * a
	end,
	Snap = function(a)
		return 1 - (1 - a) ^ 5
	end,
}
local function ease(alpha, style)
	return (EASES[style or "InOut"] or EASES.InOut)(math.clamp(alpha, 0, 1))
end

local COMBO_RESET = 1.4 -- seconds without attacking before a combo starts over

-- Weapon trail: a glowing ribbon from the blade's hilt to its tip while a melee swing plays
local ClassDefinitions = nil
pcall(function()
	ClassDefinitions = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ClassDefinitions", 10))
end)
local function findBlade(model)
	local best, bestLength = nil, 0
	local gear = model:FindFirstChild("ClassGear")
	for _, part in ipairs(gear and gear:GetDescendants() or model:GetDescendants()) do
		if part:IsA("BasePart") and (string.find(part.Name, "Weapon_") or part.Name == "Blade" or part.Name == "Dagger" or part.Name == "MaceHead") then
			local length = math.max(part.Size.X, part.Size.Y, part.Size.Z)
			if length > bestLength then
				best, bestLength = part, length
			end
		end
	end
	return best
end
local function ensureTrail(record)
	local trail = record.Trail
	if trail and trail.Parent and trail.Attachment0 and trail.Attachment0.Parent then
		return trail
	end
	local blade = findBlade(record.Model)
	if not blade then
		return nil
	end
	local size = blade.Size
	local axis = (size.X >= size.Y and size.X >= size.Z) and Vector3.xAxis or (size.Y >= size.Z and Vector3.yAxis or Vector3.zAxis)
	local half = math.max(size.X, size.Y, size.Z) / 2
	local a0 = Instance.new("Attachment")
	a0.Name = "RF_TrailBase"
	a0.Position = -axis * half * 0.2
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "RF_TrailTip"
	a1.Position = axis * half
	a1.Parent = blade
	-- mesh blades are gripped at one end: put the trail on the side farther from the hand
	local hand = record.Model:FindFirstChild("RightHand")
	if hand and (a1.WorldPosition - hand.Position).Magnitude < (blade.CFrame:PointToWorldSpace(-axis * half) - hand.Position).Magnitude then
		a1.Position = -axis * half
		a0.Position = axis * half * 0.2
	end
	trail = Instance.new("Trail")
	trail.Name = "RF_SwingTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	local classDef = ClassDefinitions and ClassDefinitions.Get(record.Model:GetAttribute("Class") or "")
	local color = classDef and classDef.Color or Color3.fromRGB(255, 220, 160)
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Enabled = false
	trail.Parent = blade
	record.Trail = trail
	return trail
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
	local playing = active[record]
	if playing and playing.Trail then
		playing.Trail.Enabled = false
	end
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
	if kind == "Attack" and classAnimations and classAnimations.Combo then
		-- combos: next swing of the chain, back to the first after a pause
		local now = os.clock()
		if now - (record.LastSwingAt or 0) > COMBO_RESET then
			record.ComboIndex = 0
		end
		record.LastSwingAt = now
		record.ComboIndex = (record.ComboIndex or 0) % #classAnimations.Combo + 1
		definition = classAnimations.Combo[record.ComboIndex]
	end
	if kind == "Item" then
		-- item skills: dedicated animation, or fall back to the class attack/ability swing
		definition = ITEM_ANIMATIONS[itemAbility or ""] or (itemAbility == "CleavingArc" and classAnimations and (classAnimations.Attack or (classAnimations.Combo and classAnimations.Combo[1]))) or (classAnimations and classAnimations.Ability)
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
	local trail = nil
	if classAnimations and classAnimations.Trail and (kind == "Attack" or kind == "Item") then
		trail = ensureTrail(record)
		if trail then
			trail.Enabled = true
		end
	end
	active[record] = { Keys = keys, Duration = math.max(0.12, duration), Elapsed = 0, Trail = trail }
end

local function poseAt(keys, alpha)
	-- implicit neutral keys at 0 and 1
	local previousT, previousPose = 0, nil
	for _, key in ipairs(keys) do
		if alpha <= key.T then
			return previousPose, key.Pose, ease((alpha - previousT) / math.max(1e-3, key.T - previousT), key.Ease)
		end
		previousT, previousPose = key.T, key.Pose
	end
	-- recovery back to neutral: soft ease-out
	return previousPose, nil, ease((alpha - previousT) / math.max(1e-3, 1 - previousT), "Out")
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
