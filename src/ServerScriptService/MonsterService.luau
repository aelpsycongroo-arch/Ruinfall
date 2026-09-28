-- MonsterService: neutral monster camps. Simple AI:
--   Idle -> detect hero -> Chase -> Attack -> Return (leash) -> Idle
-- Clearing a camp drops a Core Fragment; camps respawn after a delay.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local FragmentService = require(script.Parent:WaitForChild("FragmentService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local MONSTER = Constants.Monster
local CAMP_OFFSETS = { Vector3.new(0, 0, 0), Vector3.new(4.5, 0, 3.5), Vector3.new(-4.5, 0, 3.5) }
-- Blender-made Stone Warden rig (ServerStorage.MonsterAssets.StoneWarden). Animated on the client
-- by MonsterAnimationController (walk / attack / death) via its Motor6D joints.
local MONSTER_TEMPLATE = "StoneWarden"
local DEATH_ANIMATION_TIME = 2.4

-- State
local MonsterService = {}
MonsterService.Camps = {}

local monstersFolder = nil
local runId = 0
local random = Random.new()

-- Functions
local function weldPart(model, root, properties, offset)
	local part = Instance.new(properties.ClassName or "Part")
	properties.ClassName = nil
	for key, value in pairs(properties) do
		part[key] = value
	end
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function createMonsterHumanoid(model, definition, hipHeight)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = definition.MoveSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.MaxHealth = definition.MaxHealth
	humanoid.Health = definition.MaxHealth
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

local function buildRiggedMonster(template, definition, position)
	local s = definition.Scale
	local model = template:Clone()
	model.Name = definition.Name
	if s ~= 1 then
		model:ScaleTo(s)
	end
	local root = model.PrimaryPart
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			local kind = item:GetAttribute("Kind")
			if kind == "Eye" and definition.EyeColor then
				item.Color = definition.EyeColor
			elseif kind == "Stone" and definition.StoneColor then
				item.Color = definition.StoneColor
			end
		elseif item:IsA("PointLight") and definition.EyeColor then
			item.Color = definition.EyeColor
		end
	end
	model:PivotTo(CFrame.new(position + Vector3.new(0, 1.3 * s, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("BarOffset", 3.4 * s)
	model:SetAttribute("RigScale", s)
	local humanoid = createMonsterHumanoid(model, definition, 0.5 * s)
	model.PrimaryPart = root
	return model, root, humanoid
end

local function buildMonsterModel(definition, position)
	local assets = ServerStorage:FindFirstChild("MonsterAssets")
	local template = assets and assets:FindFirstChild(MONSTER_TEMPLATE)
	if template and template.PrimaryPart then
		return buildRiggedMonster(template, definition, position)
	end
	-- Fallback: legacy block monster
	local s = definition.Scale
	local hipHeight = 0.5 * s
	local model = Instance.new("Model")
	model.Name = definition.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4 * s, 1.6 * s, 2.4 * s)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(position + Vector3.new(0, hipHeight + 0.8 * s, 0))
	root.Parent = model

	local color = definition.Color
	weldPart(model, root, { Name = "Body", Size = Vector3.new(3 * s, 2.2 * s, 3.6 * s), Color = color, Material = Enum.Material.Slate }, CFrame.new(0, 0.1 * s, 0))
	weldPart(model, root, { Name = "Head", Size = Vector3.new(2 * s, 1.6 * s, 1.6 * s), Color = color:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.Slate }, CFrame.new(0, 0.5 * s, -2.3 * s))
	for _, side in ipairs({ -1, 1 }) do
		weldPart(model, root, { Name = "Eye", Size = Vector3.new(0.45 * s, 0.3 * s, 0.1), Color = definition.EyeColor, Material = Enum.Material.Neon }, CFrame.new(side * 0.45 * s, 0.75 * s, -3.12 * s))
		for _, front in ipairs({ -1, 1 }) do
			weldPart(model, root, { Name = "Leg", Size = Vector3.new(0.6 * s, 1.0 * s, 0.6 * s), Color = color:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Slate }, CFrame.new(side * 1.25 * s, -0.95 * s, front * 1.2 * s))
		end
	end
	for index, z in ipairs({ -0.9, 0.2, 1.3 }) do
		weldPart(model, root, {
			ClassName = "WedgePart",
			Name = "Spike",
			Size = Vector3.new(0.4 * s, (1.2 - index * 0.15) * s, 1.1 * s),
			Color = definition.EyeColor:Lerp(Color3.new(0, 0, 0), 0.55),
			Material = Enum.Material.Rock,
		}, CFrame.new(0, 1.45 * s, z * s))
	end

	local humanoid = createMonsterHumanoid(model, definition, hipHeight)
	model.PrimaryPart = root
	return model, root, humanoid
end

local function spawnMonster(camp, definition, offset)
	local home = camp.Position + offset
	local model, root, humanoid = buildMonsterModel(definition, home)
	model.Parent = monstersFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local entity = CombatService.Register({
		Kind = "Monster",
		Team = Constants.NEUTRAL_TEAM,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Definition = definition,
		Camp = camp,
		Home = home,
		Health = definition.MaxHealth,
		MaxHealth = definition.MaxHealth,
		Armor = definition.Armor,
		BaseSpeed = definition.MoveSpeed,
		Radius = 1.8 * definition.Scale,
		AIState = "Idle",
		Target = nil,
		LastAttackAt = 0,
	})
	model:SetAttribute("MonsterType", definition.Key)
	model:SetAttribute("CampId", camp.Id)
	table.insert(camp.Monsters, entity)
	return entity
end

local function spawnCamp(camp)
	camp.Monsters = {}
	camp.State = "Alive"
	camp.RespawnAt = 0
	for index, key in ipairs(CombatDefinitions.CampComposition) do
		spawnMonster(camp, CombatDefinitions.Monsters[key], CAMP_OFFSETS[index] or Vector3.zero)
	end
end

local function isValidTarget(monster, target)
	return target ~= nil and target.Alive and target.Kind == "Hero" and not CombatService.IsStealthed(target)
		and Util.FlatDistance(CombatService.GetPosition(target), monster.Camp.Position) <= MONSTER.LEASH_RANGE
end

local function aggroCamp(camp, target)
	for _, monster in ipairs(camp.Monsters) do
		if monster.Alive and (monster.AIState ~= "Chase" or not isValidTarget(monster, monster.Target)) then
			monster.Target = target
			monster.AIState = "Chase"
		end
	end
end

local function think(monster, now, dt)
	if CombatService.IsStunned(monster) then
		return
	end
	local definition = monster.Definition
	local position = CombatService.GetPosition(monster)
	local humanoid = monster.Humanoid
	if monster.TauntedUntil > now and monster.TauntedBy and monster.TauntedBy.Alive then
		monster.Target = monster.TauntedBy
		monster.AIState = "Chase"
	end

	if monster.AIState == "Idle" then
		local target = CombatService.FindNearestEnemy(monster, position, MONSTER.AGGRO_RANGE, function(entity)
			return entity.Kind == "Hero" and not CombatService.IsStealthed(entity)
		end)
		if target then
			aggroCamp(monster.Camp, target)
		end
	elseif monster.AIState == "Chase" then
		local target = monster.Target
		local tooFar = Util.FlatDistance(position, monster.Camp.Position) > MONSTER.LEASH_RANGE + 8
		if not isValidTarget(monster, target) or tooFar then
			monster.AIState = "Return"
			monster.Target = nil
			humanoid:MoveTo(monster.Home)
			return
		end
		local targetPosition = CombatService.GetPosition(target)
		local distance = Util.FlatDistance(position, targetPosition) - target.Radius
		if distance <= definition.AttackRange then
			humanoid:MoveTo(position)
			monster.Root.CFrame = CFrame.lookAt(position, Vector3.new(targetPosition.X, position.Y, targetPosition.Z))
			if now - monster.LastAttackAt >= definition.AttackCooldown then
				monster.LastAttackAt = now
				if monster.Model then
					monster.Model:SetAttribute("AttackSeq", (monster.Model:GetAttribute("AttackSeq") or 0) + 1)
				end
				Net.Effect("Melee", {
					Origin = position,
					Direction = Util.FlatDirection(position, targetPosition),
					Range = definition.AttackRange + 1,
					Arc = 70,
					Color = definition.EyeColor,
				})
				CombatService.ApplyDamage(monster, target, definition.Damage, { BasicAttack = true })
			end
		else
			humanoid:MoveTo(targetPosition)
		end
	elseif monster.AIState == "Return" then
		if Util.FlatDistance(position, monster.Home) < 3 then
			monster.AIState = "Idle"
			CombatService.Heal(monster, monster.MaxHealth)
		else
			humanoid:MoveTo(monster.Home)
			CombatService.Heal(monster, monster.MaxHealth * 0.15 * dt)
		end
	end
	if monster.Model then
		monster.Model:SetAttribute("AIState", monster.AIState)
	end
end

local function onMonsterDied(monster, killer)
	local camp = monster.Camp
	local model = monster.Model
	CombatService.Unregister(monster)
	if killer and killer.Kind == "Hero" and killer.Alive then
		CombatService.Heal(killer, killer.MaxHealth * monster.Definition.KillHealPercent, true)
	end
	-- Freeze the body in place and let the client play the collapse / crumble animation
	local root = monster.Root
	if model and model.Parent then
		model:SetAttribute("DiedAt", workspace:GetServerTimeNow())
		model:SetAttribute("AIState", "Dead")
		if root and root.Parent then
			root.Anchored = true
			root.CanCollide = false
		end
	end
	local isRigged = model and model:GetAttribute("RigScale") ~= nil
	task.delay(isRigged and DEATH_ANIMATION_TIME or 0.5, function()
		if model then
			model:Destroy()
		end
	end)
	if not camp or camp.State ~= "Alive" then
		return
	end
	for _, other in ipairs(camp.Monsters) do
		if other.Alive then
			return
		end
	end
	camp.State = "Cleared"
	camp.RespawnAt = Util.Now() + MONSTER.CAMP_RESPAWN_TIME
	if random:NextNumber() <= MONSTER.FRAGMENT_DROP_CHANCE then
		local fragment = FragmentService.Spawn(camp.Position)
		if fragment and killer and killer.Team then
			Net.Notify(PlayerService.GetTeamPlayers(killer.Team), "Camp cleared - a Core Fragment dropped!", "Fragment")
		end
	end
end

local function tick(dt)
	local now = Util.Now()
	for _, camp in ipairs(MonsterService.Camps) do
		if camp.State == "Cleared" then
			if now >= camp.RespawnAt then
				spawnCamp(camp)
			end
		else
			for _, monster in ipairs(camp.Monsters) do
				if monster.Alive and monster.Humanoid and monster.Humanoid.Parent then
					think(monster, now, dt)
				end
			end
		end
	end
end

-- Public API ---------------------------------------------------------------------------
function MonsterService.Init()
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.Kind == "Monster" then
			onMonsterDied(entity, killer)
		end
	end)
	CombatService.EntityDamaged:Connect(function(entity, source)
		if entity.Kind == "Monster" and entity.Alive and source and source.Kind == "Hero" and entity.Camp then
			if isValidTarget(entity, source) and (entity.AIState ~= "Chase" or not isValidTarget(entity, entity.Target)) then
				aggroCamp(entity.Camp, source)
			end
		end
	end)
end

function MonsterService.Setup(mapData)
	MonsterService.Cleanup()
	monstersFolder = Instance.new("Folder")
	monstersFolder.Name = "Monsters"
	monstersFolder.Parent = mapData.Folder
	for index, campData in ipairs(mapData.Camps) do
		local camp = { Id = campData.Id, Index = index, Position = campData.Position, Monsters = {}, State = "Alive", RespawnAt = 0 }
		table.insert(MonsterService.Camps, camp)
		spawnCamp(camp)
		if Constants.DEBUG_MODE then
			for _, ring in ipairs({ { MONSTER.AGGRO_RANGE, Color3.new(1, 0.3, 0.3) }, { MONSTER.LEASH_RANGE, Color3.new(1, 1, 0.3) } }) do
				local part = Instance.new("Part")
				part.Name = "DebugAggroRing"
				part.Shape = Enum.PartType.Cylinder
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.Transparency = 0.85
				part.Material = Enum.Material.Neon
				part.Color = ring[2]
				part.Size = Vector3.new(0.1, ring[1] * 2, ring[1] * 2)
				part.CFrame = CFrame.new(camp.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				part.Parent = monstersFolder
			end
		end
	end
end

function MonsterService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			local dt = task.wait(MONSTER.THINK_INTERVAL)
			if runId ~= myRun then
				break
			end
			tick(dt)
		end
	end)
end

function MonsterService.Stop()
	runId += 1
	for _, camp in ipairs(MonsterService.Camps) do
		for _, monster in ipairs(camp.Monsters) do
			if monster.Alive and monster.Humanoid and monster.Humanoid.Parent then
				monster.Humanoid:MoveTo(CombatService.GetPosition(monster))
			end
		end
	end
end

function MonsterService.Cleanup()
	MonsterService.Stop()
	for _, camp in ipairs(MonsterService.Camps) do
		for _, monster in ipairs(camp.Monsters) do
			CombatService.Unregister(monster)
			if monster.Model then
				monster.Model:Destroy()
			end
		end
	end
	table.clear(MonsterService.Camps)
	if monstersFolder then
		monstersFolder:Destroy()
		monstersFolder = nil
	end
end

function MonsterService.GetCamps()
	return MonsterService.Camps
end

function MonsterService.Serialize()
	local list = {}
	for _, camp in ipairs(MonsterService.Camps) do
		local alive = 0
		for _, monster in ipairs(camp.Monsters) do
			if monster.Alive then
				alive += 1
			end
		end
		table.insert(list, { Id = camp.Id, Position = camp.Position, State = camp.State, RespawnAt = camp.RespawnAt, Alive = alive })
	end
	return list
end

return MonsterService
