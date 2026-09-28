-- CharacterFactory: builds hero rigs (bots), class appearance (gear welded to
-- R15 rigs) and a lightweight server-side animator for bots.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
-- uploaded idle / run animations per class (Ruinfall Asset Porter); nil -> Roblox defaults below
local AnimationLibrary = require(Shared:WaitForChild("AnimationLibrary"))

-- Constants
local SKIN = Color3.fromRGB(226, 180, 140)
local WOOD = Color3.fromRGB(110, 75, 45)
local METAL = Color3.fromRGB(170, 175, 190)
local DARK = Color3.fromRGB(25, 25, 32)
local GOLD = Color3.fromRGB(240, 190, 70)
local ANIMATIONS = {
	Idle = "rbxassetid://507766666",
	Run = "rbxassetid://507767714",
	-- Attack swings are now procedural per class (client AttackAnimationController)
}
local SCALES = {
	Assassin = { Height = 0.98, Width = 0.88 },
	Mage = { Height = 1.0, Width = 0.95 },
	Marksman = { Height = 1.02, Width = 0.95 },
	Tank = { Height = 1.12, Width = 1.25 },
	Fighter = { Height = 1.06, Width = 1.08 },
}

-- Gear that would clash with a real avatar's hair/hats/clothes is skipped in avatar mode
local AVATAR_SKIP_GEAR = { Chestplate = true, Mantle = true, Pauldron = true, PauldronR = true, PauldronL = true, Belt = true }

-- Blender weapon meshes (ServerStorage.RuinfallWeapons). When present they replace the
-- primitive weapon parts; everything else (hoods, hats, belts...) is unchanged.
local WeaponLibrary = ServerStorage:FindFirstChild("RuinfallWeapons")
local HALF_PI = math.pi / 2
local REPLACED_BY_MESH = {
	Dagger = true, DaggerGuard = true,
	Staff = true, StaffOrb = true,
	BowUpper = true, BowLower = true, BowString = true, BowGem = true, Quiver = true, Fletching = true,
	TowerShield = true, ShieldEmblem = true,
	Hilt = true, Guard = true, Blade = true, BladeEdge = true,
}
-- Grip frames are in the attach part's space; each weapon mesh points along its +Y.
local WEAPON_SETS = {
	Fighter = {
		{ Asset = "W_Sword", Attach = "RightHand", Grip = CFrame.new(0, -0.15, -0.05) * CFrame.Angles(-HALF_PI, 0, 0), Scale = 0.85 },
	},
	Assassin = {
		{ Asset = "W_Dagger", Attach = "RightHand", Grip = CFrame.new(0, -0.15, -0.05) * CFrame.Angles(-HALF_PI, 0, 0), Scale = 0.95 },
		{ Asset = "W_Dagger", Attach = "LeftHand", Grip = CFrame.new(0, -0.15, -0.05) * CFrame.Angles(-HALF_PI, 0, 0), Scale = 0.95 },
	},
	Mage = {
		{ Asset = "W_Staff", Attach = "RightHand", Grip = CFrame.new(0, -0.1, -0.2), Scale = 0.8 },
		{ Asset = "W_StaffCrystal", Attach = "RightHand", Grip = CFrame.new(0, -0.1, -0.2), Scale = 0.8, Neon = true, Light = true },
	},
	Marksman = {
		{ Asset = "W_Bow", Attach = "LeftHand", Grip = CFrame.new(0, 0, -0.1), Scale = 0.85 },
		{ Asset = "W_Quiver", Attach = "UpperTorso", Grip = CFrame.new(0.45, 0.15, 0.72) * CFrame.Angles(0, 0, -0.35), Scale = 0.85 },
	},
	Tank = {
		{ Asset = "W_Shield", Attach = "LeftHand", Grip = CFrame.new(-0.2, 0.1, 0) * CFrame.Angles(0, HALF_PI, 0), Scale = 0.85 },
		{ Asset = "W_ShieldCrest", Attach = "LeftHand", Grip = CFrame.new(-0.2, 0.1, 0) * CFrame.Angles(0, HALF_PI, 0), Scale = 0.85, Tint = true },
		{ Asset = "W_Mace", Attach = "RightHand", Grip = CFrame.new(0, -0.15, -0.05) * CFrame.Angles(-HALF_PI, 0, 0), Scale = 0.8 },
	},
}

-- State
local CharacterFactory = {}
local avatarMode = false
local meshWeapons = false

-- Functions
local function weldGear(model, attachTo, name, size, offset, color, material, shape, transparency)
	if not attachTo then
		return nil
	end
	if avatarMode and (attachTo.Name == "Head" or AVATAR_SKIP_GEAR[name]) then
		return nil
	end
	if meshWeapons and REPLACED_BY_MESH[name] then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.Transparency = transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = attachTo.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = part
	weld.Parent = part
	local folder = model:FindFirstChild("ClassGear")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClassGear"
		folder.Parent = model
	end
	part.Parent = folder
	return part
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y

local GEAR_BUILDERS = {}

GEAR_BUILDERS.Assassin = function(model, classDef)
	local head, torso = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso")
	local color, dark = classDef.Color, classDef.SecondaryColor
	weldGear(model, head, "Hood", Vector3.new(1.5, 1.45, 1.5), CFrame.new(0, 0.12, 0.1), dark, Enum.Material.Fabric)
	weldGear(model, head, "EyeSlit", Vector3.new(1.05, 0.14, 0.1), CFrame.new(0, 0.05, -0.74), color, Enum.Material.Neon)
	weldGear(model, torso, "Scarf", Vector3.new(0.5, 0.15, 1.5), CFrame.new(0.35, 0.55, 0.95) * CFrame.Angles(math.rad(-35), 0, 0), color, Enum.Material.Fabric)
	for _, handName in ipairs({ "RightHand", "LeftHand" }) do
		local hand = model:FindFirstChild(handName)
		weldGear(model, hand, "Dagger", Vector3.new(0.12, 0.28, 1.9), CFrame.new(0, -0.15, -0.95), color, Enum.Material.Neon)
		weldGear(model, hand, "DaggerGuard", Vector3.new(0.55, 0.12, 0.14), CFrame.new(0, -0.15, -0.05), DARK, Enum.Material.Metal)
	end
end

GEAR_BUILDERS.Mage = function(model, classDef)
	local head, torso, hand = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso"), model:FindFirstChild("RightHand")
	local color, dark = classDef.Color, classDef.SecondaryColor
	if head then
		local top = head.Size.Y / 2
		weldGear(model, head, "HatBrim", Vector3.new(0.15, 2.9, 2.9), CFrame.new(0, top + 0.02, 0) * VERTICAL, dark, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldGear(model, head, "HatTier1", Vector3.new(0.75, 1.5, 1.5), CFrame.new(0, top + 0.45, 0) * VERTICAL, dark, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldGear(model, head, "HatTier2", Vector3.new(0.7, 1.0, 1.0), CFrame.new(0, top + 1.1, 0.08) * VERTICAL, dark, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldGear(model, head, "HatTier3", Vector3.new(0.6, 0.55, 0.55), CFrame.new(0, top + 1.65, 0.18) * VERTICAL, dark, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldGear(model, head, "HatGem", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, top + 2.05, 0.25), color, Enum.Material.Neon, Enum.PartType.Ball)
		weldGear(model, head, "HatBand", Vector3.new(0.2, 1.55, 1.55), CFrame.new(0, top + 0.2, 0) * VERTICAL, color, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
	weldGear(model, torso, "Mantle", Vector3.new(2.4, 0.4, 1.35), CFrame.new(0, 0.72, 0), dark, Enum.Material.Fabric)
	weldGear(model, hand, "Staff", Vector3.new(5.6, 0.28, 0.28), CFrame.new(0, 0.8, -0.25) * VERTICAL, Color3.fromRGB(70, 45, 90), Enum.Material.Wood, Enum.PartType.Cylinder)
	local orb = weldGear(model, hand, "StaffOrb", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 3.75, -0.25), color, Enum.Material.Neon, Enum.PartType.Ball)
	if orb then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = orb
	end
end

GEAR_BUILDERS.Marksman = function(model, classDef)
	local head, torso, hand = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso"), model:FindFirstChild("LeftHand")
	local color = classDef.Color
	local hoodColor = color:Lerp(Color3.new(0, 0, 0), 0.45)
	weldGear(model, head, "Hood", Vector3.new(1.45, 0.75, 1.5), CFrame.new(0, (head and head.Size.Y / 2 or 0.6) - 0.1, 0.1), hoodColor, Enum.Material.Fabric)
	weldGear(model, head, "HoodBack", Vector3.new(1.3, 1.2, 0.35), CFrame.new(0, 0, 0.72), hoodColor, Enum.Material.Fabric)
	weldGear(model, hand, "BowUpper", Vector3.new(0.2, 2.0, 0.24), CFrame.new(0, 0.95, -0.3) * CFrame.Angles(math.rad(-18), 0, 0), WOOD, Enum.Material.Wood)
	weldGear(model, hand, "BowLower", Vector3.new(0.2, 2.0, 0.24), CFrame.new(0, -0.95, -0.3) * CFrame.Angles(math.rad(18), 0, 0), WOOD, Enum.Material.Wood)
	weldGear(model, hand, "BowString", Vector3.new(0.05, 3.7, 0.05), CFrame.new(0, 0, 0.05), Color3.fromRGB(235, 235, 235), Enum.Material.Neon)
	weldGear(model, hand, "BowGem", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, 0, -0.45), color, Enum.Material.Neon, Enum.PartType.Ball)
	weldGear(model, torso, "Quiver", Vector3.new(0.65, 1.9, 0.65), CFrame.new(0.45, 0.25, 0.7) * CFrame.Angles(0, 0, math.rad(-20)), WOOD, Enum.Material.Leather)
	weldGear(model, torso, "Fletching", Vector3.new(0.5, 0.4, 0.5), CFrame.new(0.8, 1.25, 0.7) * CFrame.Angles(0, 0, math.rad(-20)), color, Enum.Material.Neon)
end

GEAR_BUILDERS.Tank = function(model, classDef)
	local head, torso, hand = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso"), model:FindFirstChild("LeftHand")
	local color, steel = classDef.Color, classDef.SecondaryColor
	weldGear(model, head, "Helmet", Vector3.new(1.55, 1.4, 1.55), CFrame.new(0, 0.1, 0), steel, Enum.Material.Metal)
	weldGear(model, head, "Visor", Vector3.new(1.05, 0.14, 0.1), CFrame.new(0, 0.05, -0.79), color, Enum.Material.Neon)
	weldGear(model, head, "Crest", Vector3.new(0.22, 0.55, 1.5), CFrame.new(0, (head and head.Size.Y / 2 or 0.6) + 0.35, 0), color, Enum.Material.Metal)
	weldGear(model, torso, "PauldronR", Vector3.new(1.35, 0.85, 1.45), CFrame.new(1.35, 0.7, 0), color, Enum.Material.Metal)
	weldGear(model, torso, "PauldronL", Vector3.new(1.35, 0.85, 1.45), CFrame.new(-1.35, 0.7, 0), color, Enum.Material.Metal)
	weldGear(model, torso, "Chestplate", Vector3.new(2.15, 1.5, 1.2), CFrame.new(0, 0, 0), steel, Enum.Material.DiamondPlate)
	weldGear(model, hand, "TowerShield", Vector3.new(0.3, 3.5, 2.5), CFrame.new(-0.4, 0.45, -0.35), steel, Enum.Material.Metal)
	weldGear(model, hand, "ShieldEmblem", Vector3.new(0.12, 1.5, 1.1), CFrame.new(-0.6, 0.5, -0.35), color, Enum.Material.Neon)
end

GEAR_BUILDERS.Fighter = function(model, classDef)
	local head, torso, hand = model:FindFirstChild("Head"), model:FindFirstChild("UpperTorso"), model:FindFirstChild("RightHand")
	local color = classDef.Color
	weldGear(model, head, "Headband", Vector3.new(1.32, 0.28, 1.32), CFrame.new(0, 0.22, 0), color, Enum.Material.Fabric)
	weldGear(model, head, "HeadbandTail", Vector3.new(0.2, 0.2, 0.9), CFrame.new(0.3, 0.1, 0.9) * CFrame.Angles(math.rad(-25), 0, 0), color, Enum.Material.Fabric)
	weldGear(model, torso, "Pauldron", Vector3.new(1.25, 0.65, 1.35), CFrame.new(1.3, 0.72, 0), GOLD, Enum.Material.Metal)
	weldGear(model, torso, "Belt", Vector3.new(2.1, 0.3, 1.15), CFrame.new(0, -0.75, 0), classDef.SecondaryColor, Enum.Material.Leather)
	weldGear(model, hand, "Hilt", Vector3.new(0.25, 0.25, 1.0), CFrame.new(0, -0.1, -0.15), DARK, Enum.Material.Leather)
	weldGear(model, hand, "Guard", Vector3.new(1.1, 0.22, 0.25), CFrame.new(0, -0.1, -0.72), GOLD, Enum.Material.Metal)
	weldGear(model, hand, "Blade", Vector3.new(0.16, 0.6, 3.7), CFrame.new(0, -0.1, -2.65), METAL, Enum.Material.Metal)
	weldGear(model, hand, "BladeEdge", Vector3.new(0.18, 0.14, 3.7), CFrame.new(0, -0.43, -2.65), color, Enum.Material.Neon)
end

local function attachWeapons(model, classKey, classDef)
	local set = WEAPON_SETS[classKey]
	if not set or not WeaponLibrary then
		return
	end
	local folder = model:FindFirstChild("ClassGear")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClassGear"
		folder.Parent = model
	end
	for _, spec in ipairs(set) do
		local source = WeaponLibrary:FindFirstChild(spec.Asset)
		local attachTo = model:FindFirstChild(spec.Attach)
		if source and attachTo then
			local part = source:Clone()
			part.Name = "Weapon_" .. spec.Asset
			local scale = spec.Scale or 1
			part.Size = source.Size * scale
			local grip = (source:GetAttribute("Grip") or Vector3.zero) * scale
			part.CFrame = attachTo.CFrame * spec.Grip * CFrame.new(-grip)
			if spec.Neon then
				part.Color = classDef.Color
			end
			if spec.Tint then
				local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					appearance.Color = classDef.Color:Lerp(Color3.new(1, 1, 1), 0.15)
				end
			end
			if spec.Light then
				local light = Instance.new("PointLight")
				light.Color = classDef.Color
				light.Range = 10
				light.Brightness = 1.2
				light.Shadows = false
				light.Parent = part
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = attachTo
			weld.Part1 = part
			weld.Parent = part
			part.Parent = folder
		end
	end
end

-- Public API --------------------------------------------------------------
function CharacterFactory.BuildDescription(classKey)
	local classDef = ClassDefinitions.Get(classKey)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.TorsoColor = classDef.Color:Lerp(DARK, 0.25)
	description.LeftArmColor = classDef.SecondaryColor
	description.RightArmColor = classDef.SecondaryColor
	description.LeftLegColor = DARK
	description.RightLegColor = DARK
	local scale = SCALES[classKey] or { Height = 1, Width = 1 }
	description.HeightScale = scale.Height
	description.WidthScale = scale.Width
	description.DepthScale = scale.Width
	description.HeadScale = 1
	return description
end

function CharacterFactory.PrepareHumanoid(model, keepAppearance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	if keepAppearance then
		-- Real avatar: keep accessories/clothing but make them purely cosmetic so they
		-- never block mouse raycasts, collide or touch anything (gameplay unchanged).
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant:FindFirstAncestorOfClass("Accessory") then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Massless = true
			end
		end
		return humanoid
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	return humanoid
end

function CharacterFactory.ApplyClassLook(model, classKey, teamColor, isAvatar)
	local classDef = ClassDefinitions.Get(classKey)
	local existing = model:FindFirstChild("ClassGear")
	if existing then
		existing:Destroy()
	end
	local builder = GEAR_BUILDERS[classKey]
	if builder then
		avatarMode = isAvatar == true
		meshWeapons = WeaponLibrary ~= nil and WEAPON_SETS[classKey] ~= nil
		local ok, err = pcall(builder, model, classDef)
		avatarMode = false
		if not ok then
			warn("[Ruinfall] Class gear failed:", err)
		end
		if meshWeapons then
			local weaponsOk, weaponError = pcall(attachWeapons, model, classKey, classDef)
			if not weaponsOk then
				warn("[Ruinfall] Weapon attach failed:", weaponError)
			end
		end
		meshWeapons = false
	end
	-- Team ring under the hero (readable team identification from above)
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		local groundOffset = -(humanoid.HipHeight + root.Size.Y / 2) + 0.12
		weldGear(model, root, "TeamRing", Vector3.new(0.12, 5.2, 5.2), CFrame.new(0, groundOffset, 0) * VERTICAL, teamColor, Enum.Material.Neon, Enum.PartType.Cylinder, 0.35)
		weldGear(model, root, "TeamRingInner", Vector3.new(0.14, 4.4, 4.4), CFrame.new(0, groundOffset, 0) * VERTICAL, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, 0.25)
		-- soft contact shadow so the hero sits on the ground
		local shadow = weldGear(model, root, "ContactShadow", Vector3.new(0.16, 3.2, 3.2), CFrame.new(0, groundOffset + 0.01, 0) * VERTICAL, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, 0.45)
		if shadow then
			shadow.CastShadow = false
		end
	end
end

-- Live weapon swap (Ruinfall Asset Porter, ServerScriptService.AssetHotSwap): rebuild only the
-- Blender weapon meshes of an existing hero from the current ServerStorage.RuinfallWeapons.
function CharacterFactory.RefreshWeapons(model)
	local classKey = model and model:GetAttribute("Class")
	local classDef = classKey and ClassDefinitions.Get(classKey)
	local folder = model and model:FindFirstChild("ClassGear")
	if not classDef or not folder or not WeaponLibrary or not WEAPON_SETS[classKey] then
		return false
	end
	for _, child in ipairs(folder:GetChildren()) do
		if string.sub(child.Name, 1, 7) == "Weapon_" then
			child:Destroy()
		end
	end
	local ok, err = pcall(attachWeapons, model, classKey, classDef)
	if not ok then
		warn("[Ruinfall] Weapon refresh failed:", err)
	end
	return ok
end

-- Bots use a real R15 rig built from a description (server only).
function CharacterFactory.CreateBotCharacter(participant)
	local description = CharacterFactory.BuildDescription(participant.ClassKey)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = participant.Name
	CharacterFactory.PrepareHumanoid(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	return model
end

-- Minimal animation controller for server-owned rigs (bots). Idle / run use the class's
-- uploaded animation (AnimationLibrary <Class>_Idle / <Class>_Run) when one is set, else the
-- Roblox defaults; a slot changed during a playtest is picked up on the next state change.
function CharacterFactory.CreateAnimator(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local tracks = {} -- [animation id] = track | false
	local function trackFor(name)
		local classKey = model:GetAttribute("Class")
		local id = (classKey and AnimationLibrary.GetId(classKey .. "_" .. name)) or ANIMATIONS[name]
		if not id or not animator then
			return nil, id
		end
		if tracks[id] == nil then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Movement
				track.Looped = true
				tracks[id] = track
			else
				tracks[id] = false
			end
		end
		return tracks[id] or nil, id
	end
	local controller = { Current = nil, CurrentId = nil, CurrentTrack = nil }
	function controller.SetMoving(isMoving)
		local wanted = isMoving and "Run" or "Idle"
		local track, id = trackFor(wanted)
		if controller.Current == wanted and controller.CurrentId == id then
			return
		end
		if controller.CurrentTrack then
			controller.CurrentTrack:Stop(0.15)
		end
		controller.Current, controller.CurrentId, controller.CurrentTrack = wanted, id, track
		if track then
			track:Play(0.15)
		end
	end
	function controller.PlayAttack()
		-- attack swings are animated on every client (AttackAnimationController)
	end
	return controller
end

return CharacterFactory
