-- CreepService: automatic minion waves. Every MinionWaves.Interval seconds each living
-- team sends MinionWaves.Count minions from its base: base -> arena centre -> nearest
-- enemy base, fighting enemy heroes/minions on the way and then the enemy flag. Enemy
-- heroes earn CreepWave.KillReward gold per minion kill (awarded once, in
-- CombatService.Kill). Players buy TEAM-WIDE minion upgrade levels in the shop
-- (ItemDefinitions.MinionUpgrade). Also hosts the Golem Heart golem. Cheap 4 Hz AI.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local AbilityScaling = require(Shared:WaitForChild("AbilityScaling"))
local Net = require(script.Parent:WaitForChild("Net"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local ShopService = require(script.Parent:WaitForChild("ShopService"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

-- Constants
local WAVE = ItemDefinitions.CreepWave
local WAVES = ItemDefinitions.MinionWaves
local UPGRADE = ItemDefinitions.MinionUpgrade
local THINK_INTERVAL = 0.25
local WAYPOINT_REACHED = 6
local FLAG_ENGAGE_RANGE = 20
local FORMATION = {
	Vector3.new(-3, 0, 0), Vector3.new(3, 0, 0), Vector3.new(-3, 0, 3.5),
	Vector3.new(3, 0, 3.5), Vector3.new(-3, 0, 7), Vector3.new(3, 0, 7),
}

-- State
local CreepService = {}
CreepService.Creeps = {} -- [entityId] = creep entity
CreepService.TeamLevels = {} -- [team] = minion upgrade level (0..MaxLevel)
CreepService.NextWaveAt = nil -- server time of the next automatic wave
local folder = nil
local runId = 0
local initialized = false

-- Model -----------------------------------------------------------------------------
local function weld(model, root, className, properties, offset)
	local part = Instance.new(className)
	for key, value in pairs(properties) do
		part[key] = value
	end
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = root.CFrame * offset
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = part
	part.Parent = model
	return part
end

local function createCreepHumanoid(model, hipHeight, maxHealth)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = WAVE.MoveSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Parent = model
	return humanoid
end

-- Blender-made goblin minion (ServerStorage.MonsterAssets.GoblinMinion). Hood, scarf, tabard and
-- tatters are recoloured to the team colour; goggles / vials / gems glow in a lighter team tint.
-- Animated on the client by MinionAnimationController through its Motor6D joints.
local GOBLIN_TEMPLATE = "GoblinMinion"
local function buildGoblinModel(template, position, lookAt, teamColor, name, maxHealth)
	local model = template:Clone()
	model.Name = name
	local cloth = teamColor:Lerp(Color3.new(0, 0, 0), 0.2)
	local glow = teamColor:Lerp(Color3.new(1, 1, 1), 0.35)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local kind = part:GetAttribute("Kind")
			if kind == "Cloth" then
				part.Color = cloth
			elseif kind == "Glow" then
				part.Color = glow
			end
		end
	end
	local rootPosition = position + Vector3.new(0, 2.0, 0)
	model:PivotTo(CFrame.lookAt(rootPosition, Vector3.new(lookAt.X, rootPosition.Y, lookAt.Z)))
	model:SetAttribute("Rig", "Goblin")
	local humanoid = createCreepHumanoid(model, 1.1, maxHealth)
	return model, model.PrimaryPart, humanoid
end

-- Small stylised footsoldier: tabard in team colour, iron helm, round shield, spear.
local function buildCreepModel(position, lookAt, teamColor, name, maxHealth)
	maxHealth = maxHealth or WAVE.MaxHealth
	local assets = ServerStorage:FindFirstChild("MonsterAssets")
	local template = assets and assets:FindFirstChild(GOBLIN_TEMPLATE)
	if template and template.PrimaryPart then
		return buildGoblinModel(template, position, lookAt, teamColor, name, maxHealth)
	end
	-- Fallback: legacy block footsoldier
	local hipHeight = 1.1
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1.6, 1.8, 1.2)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.lookAt(position + Vector3.new(0, hipHeight + 0.9, 0), Vector3.new(lookAt.X, position.Y + hipHeight + 0.9, lookAt.Z))
	root.Parent = model
	local iron = Color3.fromRGB(95, 98, 108)
	local leather = Color3.fromRGB(88, 60, 40)
	weld(model, root, "Part", { Name = "Body", Size = Vector3.new(1.5, 1.7, 1), Color = teamColor:Lerp(Color3.new(0, 0, 0), 0.25), Material = Enum.Material.Fabric }, CFrame.new(0, 0, 0))
	weld(model, root, "Part", { Name = "Belt", Size = Vector3.new(1.55, 0.25, 1.05), Color = leather, Material = Enum.Material.Leather }, CFrame.new(0, -0.55, 0))
	weld(model, root, "Part", { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.05, 1.05, 1.05), Color = Color3.fromRGB(225, 185, 150), Material = Enum.Material.SmoothPlastic }, CFrame.new(0, 1.35, 0))
	weld(model, root, "Part", { Name = "Helm", Size = Vector3.new(1.15, 0.55, 1.15), Color = iron, Material = Enum.Material.Metal }, CFrame.new(0, 1.62, 0))
	weld(model, root, "WedgePart", { Name = "Crest", Size = Vector3.new(0.18, 0.45, 0.9), Color = teamColor, Material = Enum.Material.Fabric }, CFrame.new(0, 2.05, 0.05))
	for _, side in ipairs({ -1, 1 }) do
		weld(model, root, "Part", { Name = "Leg", Size = Vector3.new(0.55, 1.1, 0.6), Color = leather, Material = Enum.Material.Leather }, CFrame.new(side * 0.4, -1.4, 0))
		weld(model, root, "Part", { Name = "Arm", Size = Vector3.new(0.45, 1.3, 0.5), Color = teamColor:Lerp(Color3.new(0, 0, 0), 0.4), Material = Enum.Material.Fabric }, CFrame.new(side * 1.0, 0.1, 0))
	end
	weld(model, root, "Part", { Name = "Shield", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.6, 1.6), Color = teamColor, Material = Enum.Material.Wood }, CFrame.new(-1.35, 0, -0.2))
	weld(model, root, "Part", { Name = "ShieldBoss", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), Color = iron, Material = Enum.Material.Metal }, CFrame.new(-1.48, 0, -0.2))
	weld(model, root, "Part", { Name = "Spear", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 0.14, 0.14), Color = Color3.fromRGB(110, 76, 44), Material = Enum.Material.Wood }, CFrame.new(1.1, 0.2, -0.7) * CFrame.Angles(0, math.rad(90), 0))
	weld(model, root, "WedgePart", { Name = "SpearTip", Size = Vector3.new(0.12, 0.3, 0.55), Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal }, CFrame.new(1.1, 0.2, -2.75) * CFrame.Angles(math.rad(90), 0, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = WAVE.MoveSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Parent = model
	model.PrimaryPart = root
	return model, root, humanoid
end

-- Stone golem summoned by the Golem Heart mythic. A jointed rig (Motor6D: Waist, Neck,
-- shoulders, elbows, hips, knees) so GolemAnimationController can animate it: a hulking
-- boulder body with a glowing rune core, crystal spine, mossy shoulders and huge fists.
-- Coordinates are relative to the root (X right, Y up, -Z forward).
local function buildGolemModel(position, lookAt, teamColor, name, maxHealth)
	local hipHeight = 2.4
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 3.4, 2.4)
	root.Transparency = 1
	root.CanCollide = true
	local y = position.Y + hipHeight + 1.7
	root.CFrame = CFrame.lookAt(Vector3.new(position.X, y, position.Z), Vector3.new(lookAt.X, y, lookAt.Z))
	root.Parent = model
	local stone = Color3.fromRGB(118, 112, 104)
	local darkStone = Color3.fromRGB(76, 73, 70)
	local moss = Color3.fromRGB(78, 110, 58)
	local glow = teamColor:Lerp(Color3.new(1, 1, 1), 0.3)

	local function piece(parent, props, offset)
		local part = Instance.new(props.ClassName or "Part")
		props.ClassName = nil
		for key, value in pairs(props) do
			part[key] = value
		end
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = props.Material ~= Enum.Material.Neon
		part.CFrame = root.CFrame * offset
		part.Parent = model
		if parent then -- decoration: welded to its limb so it follows the animation
			local weldConstraint = Instance.new("WeldConstraint")
			weldConstraint.Part0 = parent
			weldConstraint.Part1 = part
			weldConstraint.Parent = part
		end
		return part
	end
	local function joint(name, part0, part1, pivot)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		local pivotWorld = root.CFrame * pivot
		motor.C0 = part0.CFrame:ToObjectSpace(pivotWorld)
		motor.C1 = part1.CFrame:ToObjectSpace(pivotWorld)
		motor.Part0 = part0
		motor.Part1 = part1
		motor.Parent = part1
		return motor
	end
	local function rock(parent, size, offset, color, material)
		return piece(parent, { Name = "Rock", Size = size, Color = color or darkStone, Material = material or Enum.Material.Slate }, offset)
	end
	local function neon(parent, name, size, offset, shape)
		return piece(parent, { Name = name, Size = size, Color = glow, Material = Enum.Material.Neon, Shape = shape or Enum.PartType.Block }, offset)
	end

	-- torso: a big boulder chest, heavy belly stone, moss mantle, rune core and a crystal spine
	local torso = piece(nil, { Name = "Torso", Size = Vector3.new(4.2, 3.2, 3.0), Color = stone, Material = Enum.Material.Slate }, CFrame.new(0, 0.9, 0) * CFrame.Angles(math.rad(-6), 0, 0))
	joint("Waist", root, torso, CFrame.new(0, -0.6, 0))
	rock(torso, Vector3.new(3.4, 1.5, 2.6), CFrame.new(0, -0.9, -0.1) * CFrame.Angles(0, 0, math.rad(4)), darkStone)
	rock(torso, Vector3.new(1.9, 1.3, 0.8), CFrame.new(-0.95, 1.35, -1.35) * CFrame.Angles(math.rad(12), 0, math.rad(-6)), stone, Enum.Material.Rock)
	rock(torso, Vector3.new(1.9, 1.3, 0.8), CFrame.new(0.95, 1.35, -1.35) * CFrame.Angles(math.rad(12), 0, math.rad(6)), stone, Enum.Material.Rock)
	piece(torso, { Name = "Moss", Size = Vector3.new(4.0, 0.45, 2.8), Color = moss, Material = Enum.Material.Grass }, CFrame.new(0, 2.5, 0.15) * CFrame.Angles(math.rad(-6), 0, 0))
	local core = neon(torso, "Core", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0.85, -1.5), Enum.PartType.Ball)
	rock(torso, Vector3.new(1.8, 0.35, 0.5), CFrame.new(0, 1.55, -1.55), darkStone) -- brow of the core socket
	for index, spec in ipairs({ { -0.9, 0.3, 30 }, { 0.8, 0.9, -25 }, { 0.2, 2.1, 10 }, { -1.2, -0.5, 40 } }) do
		neon(torso, "RuneCrack", Vector3.new(0.14, 0.9 + index * 0.1, 0.1), CFrame.new(spec[1], spec[2], -1.52) * CFrame.Angles(0, 0, math.rad(spec[3])))
	end
	for index, spec in ipairs({ { -0.7, 2.5, 25 }, { 0.3, 2.8, -10 }, { 1.0, 2.3, -30 }, { -0.1, 1.8, 5 } }) do
		neon(torso, "SpineCrystal", Vector3.new(0.55, 1.6 + index * 0.2, 0.55), CFrame.new(spec[1], spec[2], 1.25) * CFrame.Angles(math.rad(-35), 0, math.rad(spec[3])))
	end
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 10
	light.Brightness = 1.6
	light.Parent = core

	-- head: a small heavy-browed rock sunk between the shoulders
	local head = piece(nil, { Name = "Head", Size = Vector3.new(1.8, 1.4, 1.7), Color = darkStone, Material = Enum.Material.Slate }, CFrame.new(0, 3.0, -0.8))
	joint("Neck", torso, head, CFrame.new(0, 2.4, -0.6))
	rock(head, Vector3.new(2.1, 0.45, 0.6), CFrame.new(0, 3.4, -1.55) * CFrame.Angles(math.rad(-10), 0, 0), stone)
	rock(head, Vector3.new(1.5, 0.5, 1.1), CFrame.new(0, 2.35, -1.0), darkStone) -- jaw
	for _, side in ipairs({ -1, 1 }) do
		neon(head, "Eye", Vector3.new(0.38, 0.2, 0.1), CFrame.new(side * 0.42, 3.08, -1.66))
		piece(head, { Name = "Moss", Size = Vector3.new(0.7, 0.25, 0.8), Color = moss, Material = Enum.Material.Grass }, CFrame.new(side * 0.5, 3.72, -0.6))
	end

	-- arms: boulder shoulders, thick upper arms, forearms ending in huge knuckled fists
	for _, side in ipairs({ -1, 1 }) do
		local prefix = side > 0 and "R" or "L"
		local upper = piece(nil, { Name = prefix .. "UpperArm", Size = Vector3.new(1.3, 2.1, 1.3), Color = stone, Material = Enum.Material.Slate }, CFrame.new(side * 2.85, 0.75, 0) * CFrame.Angles(0, 0, math.rad(side * 6)))
		joint(prefix .. "_Shoulder", torso, upper, CFrame.new(side * 2.5, 1.7, 0))
		rock(upper, Vector3.new(2.0, 1.7, 2.0), CFrame.new(side * 2.75, 1.9, 0.05) * CFrame.Angles(math.rad(8), 0, math.rad(side * -14)), darkStone)
		piece(upper, { Name = "Moss", Size = Vector3.new(1.9, 0.35, 1.8), Color = moss, Material = Enum.Material.Grass }, CFrame.new(side * 2.8, 2.78, 0.05) * CFrame.Angles(0, 0, math.rad(side * -14)))
		neon(upper, "ShoulderCrystal", Vector3.new(0.4, 1.1, 0.4), CFrame.new(side * 3.2, 2.8, 0.4) * CFrame.Angles(math.rad(-20), 0, math.rad(side * -35)))
		local fore = piece(nil, { Name = prefix .. "Forearm", Size = Vector3.new(1.5, 1.9, 1.5), Color = stone, Material = Enum.Material.Slate }, CFrame.new(side * 2.95, -1.2, -0.1))
		joint(prefix .. "_Elbow", upper, fore, CFrame.new(side * 2.9, -0.3, 0))
		local fist = rock(fore, Vector3.new(2.0, 1.7, 2.0), CFrame.new(side * 3.0, -2.6, -0.25), darkStone)
		fist.Name = prefix .. "Fist"
		for knuckle = -1, 1 do
			rock(fore, Vector3.new(0.5, 0.5, 0.55), CFrame.new(side * 3.0 + knuckle * 0.6, -2.3, -1.3), stone, Enum.Material.Rock)
		end
		neon(fore, "Rune", Vector3.new(0.12, 1.1, 0.1), CFrame.new(side * 2.95, -1.1, -0.78))
		-- legs: stubby pillars with wide feet
		local thigh = piece(nil, { Name = prefix .. "Thigh", Size = Vector3.new(1.6, 1.7, 1.7), Color = darkStone, Material = Enum.Material.Slate }, CFrame.new(side * 1.05, -1.8, 0))
		joint(prefix .. "_Hip", root, thigh, CFrame.new(side * 1.0, -1.0, 0))
		local shin = piece(nil, { Name = prefix .. "Shin", Size = Vector3.new(1.45, 1.2, 1.55), Color = stone, Material = Enum.Material.Slate }, CFrame.new(side * 1.05, -3.15, 0))
		joint(prefix .. "_Knee", thigh, shin, CFrame.new(side * 1.05, -2.6, 0))
		rock(shin, Vector3.new(1.9, 0.6, 2.3), CFrame.new(side * 1.1, -3.8, -0.3), darkStone)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = ItemDefinitions.Golem.MoveSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("IsGolem", true)
	model:SetAttribute("Rig", "Golem")
	model:SetAttribute("SpawnedAt", workspace:GetServerTimeNow())
	model:SetAttribute("BarWidth", 90)
	model:SetAttribute("BarOffset", 5.6)
	return model, root, humanoid
end

local function ensureFolder()
	if not folder or not folder.Parent then
		local map = workspace:FindFirstChild("RuinfallMap")
		folder = Instance.new("Folder")
		folder.Name = "Creeps"
		folder.Parent = map or workspace
	end
	return folder
end

-- Pathing ----------------------------------------------------------------------------
local function findEnemyBase(team, from)
	local best, bestDistance = nil, math.huge
	for otherTeam, state in pairs(BaseService.Teams) do
		if otherTeam ~= team and not state.Eliminated then
			local distance = Util.FlatDistance(from, state.Base.Position)
			if distance < bestDistance then
				best, bestDistance = state, distance
			end
		end
	end
	return best
end

local function buildRoute(team, start)
	local target = findEnemyBase(team, start)
	if not target then
		return {}, nil
	end
	local center = Vector3.new(0, 0, 0)
	local route = {}
	-- lanes run base -> centre -> base, so only detour via the centre when the enemy base
	-- is not straight ahead
	local direct = Util.Flat(target.Base.Position - start)
	local toCenter = Util.Flat(center - start)
	if direct.Magnitude > 1 and toCenter.Magnitude > 1 and direct.Unit:Dot(toCenter.Unit) < 0.95 then
		table.insert(route, center)
	end
	table.insert(route, target.Base.Position)
	return route, target
end

-- AI ---------------------------------------------------------------------------------
local function isValidTarget(creep, target)
	return target and target.Alive and CombatService.AreEnemies(creep, target)
		and (target.Kind == "Hero" or target.Kind == "Creep") and not CombatService.IsStealthed(target)
end

local function think(creep, now)
	if CombatService.IsStunned(creep) then
		return
	end
	local position = CombatService.GetPosition(creep)
	local humanoid = creep.Humanoid
	-- 1) enemy units nearby
	local target = creep.Target
	if not isValidTarget(creep, target) or Util.FlatDistance(position, CombatService.GetPosition(target)) > WAVE.AggroRange + 6 then
		target = CombatService.FindNearestEnemy(creep, position, WAVE.AggroRange, function(entity)
			return isValidTarget(creep, entity)
		end)
	end
	-- 2) the enemy flag when close to it
	if not target and creep.TargetBase then
		local flag = creep.TargetBase.FlagEntity
		if flag and flag.Alive and Util.FlatDistance(position, CombatService.GetPosition(flag)) <= FLAG_ENGAGE_RANGE then
			target = flag
		end
	end
	creep.Target = target
	if target then
		local targetPosition = CombatService.GetPosition(target)
		local distance = Util.FlatDistance(position, targetPosition) - target.Radius
		if distance <= WAVE.AttackRange then
			humanoid:MoveTo(position)
			creep.Root.CFrame = CFrame.lookAt(position, Vector3.new(targetPosition.X, position.Y, targetPosition.Z))
			if now - creep.LastAttackAt >= WAVE.AttackCooldown then
				creep.LastAttackAt = now
				if creep.Model then
					creep.Model:SetAttribute("AttackSeq", (creep.Model:GetAttribute("AttackSeq") or 0) + 1)
				end
				Net.Effect("Melee", { Origin = position, Direction = Util.FlatDirection(position, targetPosition), Range = WAVE.AttackRange + 1, Arc = 50, Color = Constants.GetTeamColor(creep.Team) })
				CombatService.ApplyDamage(creep, target, creep.HitDamage or WAVE.Damage, { BasicAttack = true })
			end
		else
			humanoid:MoveTo(targetPosition)
		end
		return
	end
	-- 3) march along the route
	local waypoint = creep.Route[creep.RouteIndex]
	if not waypoint then
		-- target base finished (flag gone): pick the next enemy base, if any
		local route, base = buildRoute(creep.Team, position)
		if base and base ~= creep.TargetBase then
			creep.Route, creep.RouteIndex, creep.TargetBase = route, 1, base
		else
			humanoid:MoveTo(position)
		end
		return
	end
	local offsetWaypoint = waypoint + creep.FormationOffset
	if Util.FlatDistance(position, offsetWaypoint) <= WAYPOINT_REACHED then
		if creep.RouteIndex < #creep.Route or not (creep.TargetBase and creep.TargetBase.FlagEntity and creep.TargetBase.FlagEntity.Alive) then
			creep.RouteIndex += 1
		end
	else
		humanoid:MoveTo(offsetWaypoint)
	end
end

-- Golem: guards its summoner. Attacks enemy heroes / creeps / flags near the owner,
-- otherwise follows. Crumbles when its lifetime ends or the owner dies.
local GOLEM = ItemDefinitions.Golem
local GOLEM_TARGET_KINDS = { Hero = true, Creep = true, Flag = true, Monster = true, Ruin = true, Cross = true }
local function isValidGolemTarget(golem, target)
	return target and target.Alive and CombatService.AreEnemies(golem, target)
		and GOLEM_TARGET_KINDS[target.Kind] and not CombatService.IsStealthed(target)
end

local function thinkGolem(golem, now)
	local ownerEntity = golem.OwnerEntity
	if now >= golem.ExpiresAt or not ownerEntity or not ownerEntity.Alive or not CombatService.Active then
		CombatService.Kill(golem, nil) -- crumbles; no one is rewarded
		return
	end
	if CombatService.IsStunned(golem) then
		return
	end
	local position = CombatService.GetPosition(golem)
	local ownerPosition = CombatService.GetPosition(ownerEntity)
	local humanoid = golem.Humanoid
	-- owner teleported / blinked far away: stride back to them
	if Util.FlatDistance(position, ownerPosition) > 45 then
		local back = ownerPosition + Vector3.new(0, 1.5, 3)
		golem.Root.CFrame = CFrame.new(back)
		position = back
	end
	local function leashed(entity)
		return Util.FlatDistance(ownerPosition, CombatService.GetPosition(entity)) <= GOLEM.LeashRange
	end
	local target = golem.Target
	-- always switch to whatever the summoner is hitting right now (focus fire)
	local ownerTarget = ownerEntity.LastTarget
	if ownerTarget and ownerTarget ~= target and isValidGolemTarget(golem, ownerTarget) and leashed(ownerTarget) then
		target = ownerTarget
	end
	if not isValidGolemTarget(golem, target) or not leashed(target) then
		target = nil
		-- otherwise defend the summoner, else the nearest enemy near the golem
		local attacker = ownerEntity.LastAttacker
		if attacker and now - (ownerEntity.LastDamagedAt or 0) < 3 and isValidGolemTarget(golem, attacker) and leashed(attacker) then
			target = attacker -- defend the summoner first
		else
			target = CombatService.FindNearestEnemy(golem, position, GOLEM.AggroRange, function(entity)
				return isValidGolemTarget(golem, entity) and leashed(entity)
			end)
		end
	end
	golem.Target = target
	if target then
		local targetPosition = CombatService.GetPosition(target)
		local distance = Util.FlatDistance(position, targetPosition) - (target.Radius or 1)
		if distance <= GOLEM.AttackRange then
			humanoid:MoveTo(position)
			golem.Root.CFrame = CFrame.lookAt(golem.Root.Position, Vector3.new(targetPosition.X, golem.Root.Position.Y, targetPosition.Z))
			if now - golem.LastAttackAt >= GOLEM.AttackCooldown then
				golem.LastAttackAt = now
				golem.Model:SetAttribute("LastAttackAt", now)
				golem.Model:SetAttribute("AttackSeq", (golem.Model:GetAttribute("AttackSeq") or 0) + 1)
				-- the fists land 0.3 sec into the smash animation
				local victim = target
				task.delay(0.3, function()
					if not golem.Alive or not victim.Alive or not CombatService.Active then
						return
					end
					local impact = CombatService.GetPosition(victim)
					Net.Effect("Shockwave", { Position = impact, Radius = 3.5, Color = Color3.fromRGB(150, 140, 120) })
					Net.Effect("Explosion", { Position = impact, Radius = 2, Color = Color3.fromRGB(120, 110, 95) })
					CombatService.ApplyDamage(golem, victim, golem.HitDamage, { BasicAttack = true })
				end)
			end
		else
			humanoid:MoveTo(targetPosition)
		end
		return
	end
	-- follow: stay a few studs behind / beside the owner
	if Util.FlatDistance(position, ownerPosition) > 7 then
		local away = Util.Flat(position - ownerPosition)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
		humanoid:MoveTo(ownerPosition + away * 5)
	else
		humanoid:MoveTo(position)
	end
end

local function onCreepDied(creep, killer)
	CreepService.Creeps[creep.Id] = nil
	CombatService.Unregister(creep)
	local owner = creep.Owner
	if creep.IsGolem then
		if owner and owner.Golem == creep then
			owner.Golem = nil
		end
		Net.Effect("Explosion", { Position = CombatService.GetPosition(creep), Radius = 5, Color = Color3.fromRGB(120, 112, 100) })
		if killer and killer.Kind == "Hero" and killer.Player then
			Net.Notify(killer.Player, string.format("+%d gold (golem shattered)", creep.KillReward or 0), "Success")
		end
		local model = creep.Model
		-- freeze in place; the client crumbles it into the ground (GolemAnimationController)
		if model and model.Parent then
			model:SetAttribute("DiedAt", workspace:GetServerTimeNow())
			local root = creep.Root
			if root and root.Parent then
				root.Anchored = true
				root.CanCollide = false
			end
		end
		task.delay(1.3, function()
			if model then
				model:Destroy()
			end
		end)
		MatchManager.Broadcast()
		return
	end
	if owner then
		owner.WarBandActive = math.max(0, (owner.WarBandActive or 1) - 1)
		if owner.WarBandActive == 0 and owner.Player then
			Net.Notify(owner.Player, "Your war band has fallen - you may summon another", "Info")
		end
	end
	-- minion kills no longer post a notification (gold is still awarded in CombatService.Kill)
	local model = creep.Model
	local isGoblin = model and model:GetAttribute("Rig") == "Goblin"
	if isGoblin and model.Parent then
		-- freeze in place; the client plays a short fall-down animation
		model:SetAttribute("DiedAt", workspace:GetServerTimeNow())
		local root = creep.Root
		if root and root.Parent then
			root.Anchored = true
			root.CanCollide = false
		end
	end
	task.delay(isGoblin and 1.1 or 0.6, function()
		if model then
			model:Destroy()
		end
	end)
	MatchManager.Broadcast()
end

-- Public API ---------------------------------------------------------------------------
function CreepService.Init()
	if initialized then
		return
	end
	initialized = true
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.Kind == "Creep" and CreepService.Creeps[entity.Id] == entity then
			onCreepDied(entity, killer)
		end
	end)
	runId += 1
	local myRun = runId
	local wasActive = false
	task.spawn(function()
		while runId == myRun do
			task.wait(THINK_INTERVAL)
			if CombatService.Active and not wasActive then
				-- a new match started: fresh upgrade levels, first wave shortly
				table.clear(CreepService.TeamLevels)
				CreepService.NextWaveAt = Util.Now() + WAVES.FirstWaveDelay
				CreepService.Publish()
			elseif not CombatService.Active and wasActive then
				CreepService.NextWaveAt = nil
				CreepService.Publish()
			end
			wasActive = CombatService.Active
			if not CombatService.Active and next(CreepService.Creeps) ~= nil then
				CreepService.Cleanup() -- match over: remove any remaining minions
			elseif CombatService.Active then
				local now = Util.Now()
				-- Royale has no bases: no minion waves (Golem Heart golems below still work)
				local royale = MatchManager.IsRoyale and MatchManager.IsRoyale()
				if CreepService.NextWaveAt and now >= CreepService.NextWaveAt and not royale then
					CreepService.NextWaveAt = now + WAVES.Interval
					local ok, err = pcall(CreepService.SpawnAllWaves)
					if not ok then
						warn("[Ruinfall] Minion wave error:", err)
					end
					CreepService.Publish()
				end
				for _, creep in pairs(CreepService.Creeps) do
					if creep.Alive and creep.Humanoid and creep.Humanoid.Parent then
						local ok, err = pcall(creep.IsGolem and thinkGolem or think, creep, now)
						if not ok then
							warn("[Ruinfall] Creep AI error:", err)
						end
					end
				end
			end
		end
	end)
end

local function reject(player, message)
	if player then
		Net.Notify(player, message, "Warning", { Sound = "UI.PurchaseFail" })
	end
	return false, message
end

-- Replicates wave timer + team upgrade levels for the shop/HUD (read-only for clients)
function CreepService.Publish()
	workspace:SetAttribute("MinionNextWaveAt", CreepService.NextWaveAt or 0)
	for team = 1, 6 do
		workspace:SetAttribute("MinionLevel_" .. team, CreepService.TeamLevels[team] or 0)
	end
end

function CreepService.GetTeamLevel(team)
	return CreepService.TeamLevels[team] or 0
end

-- Server-validated TEAM minion upgrade (replaces the old War Band purchase).
-- Returns true, newLevel.
function CreepService.PurchaseUpgrade(player, participant)
	local canShop, reason = ShopService.CanShop(participant)
	if not canShop then
		return reject(player, reason)
	end
	local team = participant.Team
	if not team then
		return reject(player, "No team")
	end
	local level = CreepService.GetTeamLevel(team)
	local price = ItemDefinitions.GetMinionUpgradePrice(level)
	if not price then
		return reject(player, "Your minions are already at max level")
	end
	local gold = PlayerService.GetGold(participant)
	if gold < price then
		return reject(player, string.format("Not enough gold (%d / %d)", math.floor(gold), price))
	end
	PlayerService.AddGold(participant, -price)
	level += 1
	CreepService.TeamLevels[team] = level
	CreepService.Publish()
	-- tell the whole team
	for _, other in ipairs(PlayerService.GetParticipants()) do
		if other.Team == team and other.Player then
			Net.Notify(other.Player, string.format("%s upgraded your minions to level %d / %d", participant.Name or "A teammate", level, UPGRADE.MaxLevel), "Success", { Sound = "UI.MinionUpgrade" })
		end
	end
	MatchManager.Broadcast()
	return true, level
end

-- Old entry point (debug harness / older clients) now buys an upgrade
CreepService.Purchase = CreepService.PurchaseUpgrade

local function countTeamMinions(team)
	local count = 0
	for _, creep in pairs(CreepService.Creeps) do
		if creep.Alive and not creep.IsGolem and creep.Team == team then
			count += 1
		end
	end
	return count
end

-- One automatic wave for every team that still has a base and an enemy to march on.
function CreepService.SpawnAllWaves()
	local total = 0
	for team, baseState in pairs(BaseService.Teams) do
		if not baseState.Eliminated and baseState.Base then
			local room = WAVES.MaxAlivePerTeam - countTeamMinions(team)
			local count = math.min(WAVES.Count, room)
			if count > 0 then
				local route, targetBase = buildRoute(team, baseState.Base.Position)
				if targetBase then
					total += CreepService.SpawnTeamWave(team, baseState, route, targetBase, count)
				end
			end
		end
	end
	if total > 0 then
		MatchManager.Broadcast()
	end
	return total
end

-- Debug: spawn the next wave immediately
function CreepService.ForceWave()
	CreepService.NextWaveAt = Util.Now()
	return true
end

-- Golem Heart (SummonGolem). Called by ItemService after cooldown/ownership validation.
-- One golem per hero: a new summon replaces the old one. Returns ok, reason.
function CreepService.SpawnGolem(entity, ability, landingPoint)
	if not CombatService.Active then
		return false, "No match in progress"
	end
	local participant = entity and entity.Participant
	if not participant or not entity.Alive or not entity.Team then
		return false, "Cannot summon now"
	end
	if participant.Golem and participant.Golem.Alive then
		CombatService.Kill(participant.Golem, nil)
	end
	local origin = CombatService.GetPosition(entity)
	local forward = entity.Root and Util.Flat(entity.Root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	forward = forward.Magnitude > 0.1 and forward.Unit or Vector3.new(0, 0, -1)
	local spawnPosition = CombatService.ClampToArena(landingPoint or (origin + forward * 4))
	-- ground height under the spawn point
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { entity.Model, ensureFolder() }
	local hit = workspace:Raycast(Vector3.new(spawnPosition.X, origin.Y + 10, spawnPosition.Z), Vector3.new(0, -60, 0), params)
	local ground = hit and hit.Position or Vector3.new(spawnPosition.X, origin.Y - 3, spawnPosition.Z)
	local teamColor = Constants.GetTeamColor(entity.Team)
	-- golem health / hit damage scale with the summoner's current stats
	local ownerStats = AbilityScaling.StatsFromEntity(entity)
	local golemHealth = math.max(1, math.floor(AbilityScaling.Compute(GOLEM.MaxHealth, ownerStats) + 0.5))
	local golemDamage = math.floor(AbilityScaling.Compute(GOLEM.Damage, ownerStats) + 0.5)
	local model, root, humanoid = buildGolemModel(ground, ground + forward * 5, teamColor, "Golem_" .. participant.Id, golemHealth)
	model.Parent = ensureFolder()
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local lifetime = (ability and ability.Duration) or GOLEM.Lifetime
	local golem = CombatService.Register({
		Kind = "Creep",
		IsGolem = true,
		Team = entity.Team,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Health = golemHealth,
		MaxHealth = golemHealth,
		HitDamage = golemDamage,
		Armor = GOLEM.Armor,
		BaseSpeed = GOLEM.MoveSpeed,
		Radius = 2,
		Owner = participant,
		OwnerEntity = entity,
		KillReward = GOLEM.KillReward,
		ExpiresAt = Util.Now() + lifetime,
		LastAttackAt = 0,
	})
	model:SetAttribute("OwnerId", participant.Id)
	model:SetAttribute("ExpiresAt", golem.ExpiresAt)
	CreepService.Creeps[golem.Id] = golem
	participant.Golem = golem
	Net.Effect("Shockwave", { Position = ground, Radius = 6, Color = teamColor })
	MatchManager.Broadcast()
	return true
end

function CreepService.SpawnTeamWave(team, baseState, route, targetBase, count)
	ensureFolder()
	local stats = ItemDefinitions.GetMinionStats(CreepService.GetTeamLevel(team))
	local teamColor = Constants.GetTeamColor(team)
	local basePosition = baseState.Base.Position
	local forward = Util.Flat((route[1] or Vector3.zero) - basePosition)
	forward = forward.Magnitude > 0.1 and forward.Unit or Vector3.new(0, 0, -1)
	local frame = CFrame.lookAt(Vector3.new(basePosition.X, 0, basePosition.Z), Vector3.new(basePosition.X, 0, basePosition.Z) + forward)
	local spawned = 0
	for index = 1, count do
		local slot = FORMATION[index] or Vector3.zero
		-- spawn a little in front of the flag, in formation
		local position = (frame * CFrame.new(slot.X, 0, -10 + slot.Z)).Position
		local model, root, humanoid = buildCreepModel(position, position + forward * 5, teamColor, string.format("Minion_T%d_%d", team, index), stats.MaxHealth)
		model.Parent = folder
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		local entity = CombatService.Register({
			Kind = "Creep",
			Team = team,
			Model = model,
			Root = root,
			Humanoid = humanoid,
			Health = stats.MaxHealth,
			MaxHealth = stats.MaxHealth,
			HitDamage = stats.Damage,
			Level = stats.Level,
			Armor = stats.Armor,
			BaseSpeed = WAVE.MoveSpeed,
			Radius = 1.2,
			Owner = nil, -- team minion
			Route = route,
			RouteIndex = 1,
			TargetBase = targetBase,
			FormationOffset = (frame.Rotation * CFrame.new(slot.X * 0.8, 0, slot.Z * 0.5)).Position,
			LastAttackAt = 0,
		})
		model:SetAttribute("MinionLevel", stats.Level)
		CreepService.Creeps[entity.Id] = entity
		spawned += 1
	end
	Net.Effect("Cast", { Position = basePosition, Color = teamColor })
	return spawned
end

function CreepService.CountAlive(participant)
	local count = 0
	for _, creep in pairs(CreepService.Creeps) do
		if creep.Alive and not creep.IsGolem and (participant == nil or creep.Owner == participant) then
			count += 1
		end
	end
	return count
end

-- Called by MatchManager when a match stops / is cleaned up.
function CreepService.Cleanup()
	for _, creep in pairs(CreepService.Creeps) do
		CombatService.Unregister(creep)
		if creep.Model then
			creep.Model:Destroy()
		end
		if creep.Owner then
			creep.Owner.WarBandActive = 0
			creep.Owner.Golem = nil
		end
	end
	table.clear(CreepService.Creeps)
	table.clear(CreepService.TeamLevels)
	CreepService.Publish()
	if folder then
		folder:Destroy()
		folder = nil
	end
	for _, participant in ipairs(PlayerService.GetParticipants()) do
		participant.WarBandActive = 0
	end
end

return CreepService
