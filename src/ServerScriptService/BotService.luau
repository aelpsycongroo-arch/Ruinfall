-- BotService: AI for bot heroes. Bots use exactly the same server combat API
-- as players (PerformBasicAttack / AbilityService.Use), with reaction delays
-- and aim error from their difficulty profile.
--
-- Priority each think:
--   stunned -> low health: retreat -> flag in Last Stand: fragment run ->
--   defend own flag -> fight visible enemy -> nearby ruin -> strategy
--   (Push enemy flag / Farm camp / Roam) -> hunt remaining enemies

-- Services
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local AbilityService = require(script.Parent:WaitForChild("AbilityService"))
local VisibilityService = require(script.Parent:WaitForChild("VisibilityService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local FragmentService = require(script.Parent:WaitForChild("FragmentService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local RuinService = require(script.Parent:WaitForChild("RuinService"))
local CharacterFactory = require(script.Parent:WaitForChild("CharacterFactory"))

-- Constants
local LOOP_INTERVAL = 0.1
local PATH_REFRESH = 1.5
local STUCK_TIME = 1.2
local PATH_PARAMS = { AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 }

-- State
local BotService = {}
local brains = {} -- [participantId] = brain
local runId = 0
local random = Random.new()

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function setState(brain, state)
	brain.State = state
	if brain.DebugLabel then
		local target = brain.TargetId and (" > " .. brain.TargetId) or ""
		brain.DebugLabel.Text = string.format("%s [%s]%s", state, brain.Strategy or "-", target)
	end
end

local function aimError(brain)
	local radius = random:NextNumber(0, brain.Difficulty.AimError)
	local angle = random:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function predictAim(brain, target)
	local entity = brain.Entity
	local targetPosition = CombatService.GetPosition(target)
	local projectile = entity.Class.Projectile
	if brain.Difficulty.LeadTargets and projectile and target.Root then
		local travelTime = Util.FlatDistance(CombatService.GetPosition(entity), targetPosition) / projectile.Speed
		targetPosition += Util.Flat(target.Root.AssemblyLinearVelocity) * travelTime
	end
	return targetPosition + aimError(brain)
end

local function face(brain, position)
	local root = brain.Entity.Root
	local origin = root.Position
	local flatTarget = Vector3.new(position.X, origin.Y, position.Z)
	if (flatTarget - origin).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(origin, flatTarget)
	end
end

local function stopMoving(brain)
	brain.Path = nil
	brain.Moving = false
	brain.Entity.Humanoid:MoveTo(CombatService.GetPosition(brain.Entity))
end

local function computePath(brain, goal)
	if brain.Computing then
		return
	end
	brain.Computing = true
	brain.NextPathAt = Util.Now() + PATH_REFRESH
	local start = CombatService.GetPosition(brain.Entity)
	task.spawn(function()
		local ok = pcall(function()
			brain.PathObject:ComputeAsync(start, goal)
		end)
		brain.Computing = false
		if ok and brain.PathObject.Status == Enum.PathStatus.Success then
			brain.Path = brain.PathObject:GetWaypoints()
			brain.PathIndex = math.min(2, #brain.Path)
			brain.PathGoal = goal
		else
			brain.Path = nil
		end
	end)
end

-- Move toward goal: straight line when clear, pathfinding around walls otherwise.
local function moveTo(brain, goal)
	local entity = brain.Entity
	local position = CombatService.GetPosition(entity)
	goal = CombatService.ClampToArena(Vector3.new(goal.X, position.Y, goal.Z))
	brain.Moving = true
	brain.Goal = goal
	if Util.FlatDistance(position, goal) < 2 then
		stopMoving(brain)
		return
	end
	if CombatService.HasLineOfSight(position, goal) then
		brain.Path = nil
		entity.Humanoid:MoveTo(goal)
		return
	end
	local now = Util.Now()
	if not brain.Path or not brain.PathGoal or Util.FlatDistance(brain.PathGoal, goal) > 8 or now >= brain.NextPathAt then
		computePath(brain, goal)
	end
	local waypoint = brain.Path and brain.Path[brain.PathIndex]
	entity.Humanoid:MoveTo(waypoint and waypoint.Position or goal)
end

local function isEnemyHeroTargetable(entity, other)
	return other.Kind == "Hero" and other.Alive and other.Team ~= entity.Team and VisibilityService.CanTeamSee(entity.Team, other)
end

local function selectEnemyHero(brain, position, range)
	local entity = brain.Entity
	local current = brain.TargetId and CombatService.GetEntity(brain.TargetId)
	if current and isEnemyHeroTargetable(entity, current) and Util.FlatDistance(position, CombatService.GetPosition(current)) <= range * 1.25 then
		return current
	end
	local best, bestScore = nil, math.huge
	for _, other in pairs(CombatService.Entities) do
		if isEnemyHeroTargetable(entity, other) then
			local distance = Util.FlatDistance(position, CombatService.GetPosition(other))
			if distance <= range then
				local score = distance
				if brain.Difficulty.FocusWeakest then
					score = distance * 0.5 + (other.Health / other.MaxHealth) * 30
				end
				if score < bestScore then
					best, bestScore = other, score
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Combat behaviour
----------------------------------------------------------------------------
local function tryAbility(brain, target, isHero)
	local entity = brain.Entity
	local now = Util.Now()
	if now < brain.NextAbilityCheck or not AbilityService.IsReady(entity) then
		return
	end
	brain.NextAbilityCheck = now + 0.5
	if random:NextNumber() > brain.Difficulty.AbilityChance * (isHero and 1 or 0.5) then
		return
	end
	local ability = entity.Class.Ability
	if not ability then
		return -- Royale Wanderer without a looted skill
	end
	local position = CombatService.GetPosition(entity)
	local targetPosition = CombatService.GetPosition(target)
	local distance = Util.FlatDistance(position, targetPosition)
	local key = ability.Key
	local use = false
	local aim = targetPosition
	if key == "ShadowStep" then
		use = isHero and distance > 9 and distance < ability.DashDistance + 2
	elseif key == "ArcaneBurst" then
		use = distance < ability.CastRange
		aim = isHero and predictAim(brain, target) or targetPosition
	elseif key == "DashShot" then
		use = (isHero and distance < 14) or distance < ability.Range * 0.7
		aim = targetPosition + aimError(brain)
	elseif key == "TauntingShockwave" then
		use = distance < ability.Radius - 3
	elseif key == "BloodRush" then
		use = distance < 10
	end
	if use and AbilityService.Use(entity, aim) then
		brain.Animator.PlayAttack()
	end
end

local function tryEscape(brain, threat)
	local entity = brain.Entity
	if not AbilityService.IsReady(entity) or not threat then
		return
	end
	if not entity.Class.Ability then
		return
	end
	local key = entity.Class.Ability.Key
	local position = CombatService.GetPosition(entity)
	local baseState = BaseService.GetState(entity.Team)
	local home = baseState and baseState.Base.Position or Vector3.zero
	if key == "ShadowStep" then
		AbilityService.Use(entity, position + Util.FlatDirection(position, home) * 24)
	elseif key == "DashShot" then
		AbilityService.Use(entity, CombatService.GetPosition(threat))
	elseif key == "TauntingShockwave" and Util.FlatDistance(position, CombatService.GetPosition(threat)) < 12 then
		AbilityService.Use(entity, CombatService.GetPosition(threat))
	end
end

local function basicAttack(brain, target, aim)
	if CombatService.PerformBasicAttack(brain.Entity, aim) then
		brain.Animator.PlayAttack()
	end
end

-- Approach/kite and attack an enemy hero.
local function engage(brain, enemy)
	local entity = brain.Entity
	local classDef = entity.Class
	local now = Util.Now()
	local position = CombatService.GetPosition(entity)
	local targetPosition = CombatService.GetPosition(enemy)
	local distance = Util.FlatDistance(position, targetPosition)
	if brain.TargetId ~= enemy.Id then
		brain.TargetId = enemy.Id
		brain.ReactionUntil = now + brain.Difficulty.ReactionDelay
	end
	tryAbility(brain, enemy, true)
	local reach = classDef.AttackRange + enemy.Radius
	local hasSight = CombatService.HasLineOfSight(position, targetPosition)
	if classDef.AttackType == "Melee" then
		if distance > reach - 0.8 or not hasSight then
			moveTo(brain, targetPosition)
		else
			stopMoving(brain)
			face(brain, targetPosition)
		end
	else
		if distance > classDef.AttackRange * 0.85 or not hasSight then
			moveTo(brain, targetPosition)
		elseif distance < classDef.AttackRange * 0.35 then
			moveTo(brain, position + Util.FlatDirection(targetPosition, position) * 10)
		else
			-- strafe while shooting so bots are not sitting ducks
			if now >= brain.NextStrafeAt then
				brain.NextStrafeAt = now + random:NextNumber(0.8, 1.6)
				brain.StrafeSign = random:NextNumber() < 0.5 and -1 or 1
			end
			local toTarget = Util.FlatDirection(position, targetPosition)
			local side = Vector3.new(-toTarget.Z, 0, toTarget.X) * brain.StrafeSign
			moveTo(brain, position + side * 6)
		end
	end
	if now >= brain.ReactionUntil and distance <= reach + 1 and hasSight then
		local aim = classDef.AttackType == "Melee" and targetPosition or predictAim(brain, enemy)
		basicAttack(brain, enemy, aim)
	end
end

-- Attack a non-hero objective (flag, ruin, monster).
local function attackObjective(brain, target)
	local entity = brain.Entity
	local classDef = entity.Class
	local position = CombatService.GetPosition(entity)
	local targetPosition = CombatService.GetPosition(target)
	local distance = Util.FlatDistance(position, targetPosition)
	local reach = classDef.AttackRange + target.Radius
	local desired = classDef.AttackType == "Melee" and reach - 1 or math.min(reach - 2, classDef.AttackRange * 0.75)
	if target.Kind == "Flag" then
		desired = math.min(desired, Constants.Flag.SIEGE_RANGE - 4)
	end
	local hasSight = CombatService.HasLineOfSight(position, targetPosition)
	if distance > desired or not hasSight then
		moveTo(brain, targetPosition)
	else
		stopMoving(brain)
		face(brain, targetPosition)
	end
	tryAbility(brain, target, false)
	if distance <= reach + 0.5 and hasSight then
		basicAttack(brain, target, targetPosition + aimError(brain) * 0.3)
	end
end

----------------------------------------------------------------------------
-- Strategy
----------------------------------------------------------------------------
local function nearestAliveCamp(position, maxDistance)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, camp in ipairs(MonsterService.GetCamps()) do
		if camp.State == "Alive" then
			local distance = Util.FlatDistance(position, camp.Position)
			if distance < bestDistance then
				best, bestDistance = camp, distance
			end
		end
	end
	return best
end

local function nearestRuin(position, maxDistance)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, ruin in pairs(RuinService.Ruins) do
		if ruin.Entity.Alive then
			local distance = Util.FlatDistance(position, ruin.Position)
			if distance < bestDistance then
				best, bestDistance = ruin, distance
			end
		end
	end
	return best
end

local function nearestEnemyFlag(entity, position)
	local best, bestDistance = nil, math.huge
	for team, state in pairs(BaseService.Teams) do
		if team ~= entity.Team and not state.Eliminated and state.FlagState == "Intact" and state.FlagEntity.Alive then
			local distance = Util.FlatDistance(position, state.Base.Position)
			if distance < bestDistance then
				best, bestDistance = state.FlagEntity, distance
			end
		end
	end
	return best
end

local function nearestEnemyHeroAnywhere(entity, position)
	local best, bestDistance = nil, math.huge
	for _, other in pairs(CombatService.Entities) do
		if other.Kind == "Hero" and other.Alive and other.Team ~= entity.Team then
			local distance = Util.FlatDistance(position, CombatService.GetPosition(other))
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function farmCamp(brain, camp)
	local entity = brain.Entity
	local position = CombatService.GetPosition(entity)
	local best, bestDistance = nil, math.huge
	for _, monster in ipairs(camp.Monsters) do
		if monster.Alive then
			local distance = Util.FlatDistance(position, CombatService.GetPosition(monster))
			if distance < bestDistance then
				best, bestDistance = monster, distance
			end
		end
	end
	if best then
		setState(brain, "Farm")
		attackObjective(brain, best)
		return true
	end
	return false
end

local function chooseStrategy(brain, now)
	if now < brain.StrategyUntil then
		return
	end
	local aggression = brain.Difficulty.Aggression
	local roll = random:NextNumber()
	local pushWeight = 0.3 + 0.3 * aggression
	local farmWeight = brain.Entity.CarryingFragment and 0.05 or 0.3
	if roll < pushWeight then
		brain.Strategy = "Push"
	elseif roll < pushWeight + farmWeight then
		brain.Strategy = "Farm"
	else
		brain.Strategy = "Roam"
	end
	brain.StrategyUntil = now + random:NextNumber(10, 18)
	brain.RoamPoint = Util.RotateY(Vector3.new(0, 0, random:NextNumber(0, 60)), random:NextNumber(0, math.pi * 2))
	brain.HuntOffset = Util.RotateY(Vector3.new(0, 0, random:NextNumber(4, 14)), random:NextNumber(0, math.pi * 2))
end

----------------------------------------------------------------------------
-- Royale (free for all): stay in the zone, loot, fight, drink potions
----------------------------------------------------------------------------
-- lazy: RoyaleService / LootService sit above MatchManager in the require graph
local function royaleModules()
	return require(script.Parent:WaitForChild("RoyaleService")), require(script.Parent:WaitForChild("LootService"))
end

local function royaleThink(brain)
	local Royale, Loot = royaleModules()
	local entity = brain.Entity
	local participant = brain.Participant
	local now = Util.Now()
	local classDef = entity.Class
	local position = CombatService.GetPosition(entity)
	local healthRatio = entity.Health / entity.MaxHealth
	local zone = Royale.GetZone()
	local center = zone and zone.Center or Vector3.zero
	local safeRadius = zone and math.max(4, zone.Radius - 10) or math.huge
	local inZone = Util.FlatDistance(position, center) <= safeRadius
	local function insideZone(point)
		return not zone or Util.FlatDistance(point, center) <= safeRadius
	end

	-- drink a potion when hurt
	if healthRatio < 0.55 and (participant.Potions or 0) > 0 then
		Loot.UsePotion(participant)
	end
	-- 1. get back into the zone
	if not inZone then
		setState(brain, "Zone")
		local enemy = selectEnemyHero(brain, position, classDef.AttackRange + 2)
		if enemy then
			basicAttack(brain, enemy, CombatService.GetPosition(enemy))
		end
		moveTo(brain, zone.NextCenter and zone.NextCenter:Lerp(center, 0.5) or center)
		return
	end
	local engageRange = (classDef.AttackRange + 30) * (0.6 + 0.4 * brain.Difficulty.Aggression)
	local enemy = selectEnemyHero(brain, position, engageRange)
	if entity.TauntedUntil > now and entity.TauntedBy and entity.TauntedBy.Alive and entity.TauntedBy.Kind == "Hero" then
		enemy = entity.TauntedBy
	end
	if not enemy then
		brain.TargetId = nil
	end
	-- 2. badly hurt: break away toward the zone centre
	if enemy and healthRatio < brain.Difficulty.RetreatHealth and (participant.Potions or 0) == 0 then
		setState(brain, "Flee")
		tryEscape(brain, enemy)
		local away = position + Util.FlatDirection(CombatService.GetPosition(enemy), position) * 20
		moveTo(brain, insideZone(away) and away or center)
		return
	end
	-- 3. fight
	if enemy then
		setState(brain, "Fight")
		engage(brain, enemy)
		return
	end
	-- 4. loot on the ground (a skill first if we have none)
	local wantsSkill = not classDef.Ability
	local loot = wantsSkill and Loot.FindNearest(position, 90, function(l)
		return l.Kind == "Skill" and insideZone(l.Position)
	end) or nil
	loot = loot or Loot.FindNearest(position, 60, function(l)
		return insideZone(l.Position) and (l.Kind ~= "Potion" or (participant.Potions or 0) < Constants.Loot.MAX_POTIONS)
	end)
	if loot then
		setState(brain, "Loot")
		moveTo(brain, loot.Position)
		return
	end
	-- 5. break a ruin
	local ruin = nearestRuin(position, 110)
	if ruin and insideZone(ruin.Position) then
		setState(brain, "Ruin")
		attackObjective(brain, ruin.Entity)
		return
	end
	-- 6. farm a camp for potions
	if healthRatio > 0.6 then
		local camp = nearestAliveCamp(position, 80)
		if camp and insideZone(camp.Position) and farmCamp(brain, camp) then
			return
		end
	end
	-- 7. roam inside the zone, drifting toward where it will shrink
	if now >= brain.StrategyUntil or not insideZone(brain.RoamPoint) or Util.FlatDistance(position, brain.RoamPoint) < 8 then
		brain.StrategyUntil = now + random:NextNumber(8, 15)
		local target = zone and zone.NextCenter or center
		local spread = zone and math.max(6, math.min(zone.NextRadius or safeRadius, safeRadius) * 0.8) or 60
		brain.RoamPoint = target + Util.RotateY(Vector3.new(0, 0, random:NextNumber(0, spread)), random:NextNumber(0, math.pi * 2))
		if not insideZone(brain.RoamPoint) then
			brain.RoamPoint = center
		end
	end
	local anyRuin = nearestRuin(position)
	if anyRuin and insideZone(anyRuin.Position) and Util.FlatDistance(position, anyRuin.Position) < 200 then
		setState(brain, "Seek Ruin")
		attackObjective(brain, anyRuin.Entity)
		return
	end
	setState(brain, "Roam")
	moveTo(brain, brain.RoamPoint)
end

----------------------------------------------------------------------------
-- Decision making
----------------------------------------------------------------------------
local function think(brain)
	local entity = brain.Entity
	local now = Util.Now()
	if not entity.Alive or not entity.Root or not entity.Root.Parent then
		return
	end
	if CombatService.IsStunned(entity) then
		setState(brain, "Stunned")
		return
	end
	if entity.ClassKey == "Wanderer" then
		return royaleThink(brain) -- free-for-all battle royale bots
	end
	local difficulty = brain.Difficulty
	local classDef = entity.Class
	local position = CombatService.GetPosition(entity)
	local healthRatio = entity.Health / entity.MaxHealth
	local baseState = BaseService.GetState(entity.Team)
	local home = baseState and baseState.Base.Position
	local engageRange = (classDef.AttackRange + 32) * (0.6 + 0.4 * difficulty.Aggression)
	local enemy = selectEnemyHero(brain, position, engageRange)
	if entity.TauntedUntil > now and entity.TauntedBy and entity.TauntedBy.Alive and entity.TauntedBy.Kind == "Hero" then
		enemy = entity.TauntedBy
	end
	if not enemy then
		brain.TargetId = nil
	end

	-- 1. Retreat to heal at an intact base
	if home and baseState.FlagState == "Intact" and (healthRatio < difficulty.RetreatHealth or (brain.Retreating and healthRatio < 0.85)) then
		brain.Retreating = true
		setState(brain, "Retreat")
		tryEscape(brain, enemy)
		if enemy and Util.FlatDistance(position, CombatService.GetPosition(enemy)) <= classDef.AttackRange + 2 then
			basicAttack(brain, enemy, CombatService.GetPosition(enemy))
		end
		moveTo(brain, home)
		return
	end
	brain.Retreating = false

	-- 2. Own flag destroyed: Core Fragment run
	if baseState and baseState.FlagState == "LastStand" then
		if entity.CarryingFragment then
			setState(brain, "Re-anchor")
			if enemy and Util.FlatDistance(position, CombatService.GetPosition(enemy)) <= classDef.AttackRange + 1 then
				basicAttack(brain, enemy, CombatService.GetPosition(enemy))
			end
			moveTo(brain, home)
			return
		end
		local fragment = FragmentService.FindNearest(position)
		if fragment then
			setState(brain, "Fetch Fragment")
			moveTo(brain, fragment.Position)
			return
		end
		local camp = nearestAliveCamp(position)
		if camp and farmCamp(brain, camp) then
			return
		end
	end
	if entity.CarryingFragment and baseState and baseState.FlagState == "Intact" and baseState.FlagEntity.Health < baseState.FlagEntity.MaxHealth * 0.7 then
		setState(brain, "Repair Flag")
		moveTo(brain, home)
		return
	end

	-- 3. Defend own flag
	if baseState and baseState.FlagState == "Intact" and now - baseState.FlagEntity.LastDamagedAt < 4 and Util.FlatDistance(position, home) < 90 then
		local intruder = selectEnemyHero(brain, home, 30)
		if intruder then
			setState(brain, "Defend")
			engage(brain, intruder)
			return
		elseif not enemy then
			setState(brain, "Defend")
			moveTo(brain, home)
			return
		end
	end

	-- 4. Fight visible enemies
	if enemy then
		setState(brain, "Fight")
		engage(brain, enemy)
		return
	end

	-- 5. Nearby ruin
	local ruin = nearestRuin(position, 55)
	if ruin then
		setState(brain, "Ruin")
		attackObjective(brain, ruin.Entity)
		return
	end

	-- 6. Loose Core Fragment nearby (insurance for Last Stand)
	if not entity.CarryingFragment then
		local fragment = FragmentService.FindNearest(position, 45)
		if fragment then
			setState(brain, "Grab Fragment")
			moveTo(brain, fragment.Position)
			return
		end
	end

	-- 7. Longer-term strategy
	chooseStrategy(brain, now)
	if brain.Strategy == "Farm" and healthRatio > 0.55 then
		local camp = nearestAliveCamp(position, 130)
		if camp and farmCamp(brain, camp) then
			return
		end
		brain.StrategyUntil = 0
	elseif brain.Strategy == "Roam" then
		local anyRuin = nearestRuin(position)
		if anyRuin then
			setState(brain, "Roam: Ruin")
			attackObjective(brain, anyRuin.Entity)
			return
		end
		if Util.FlatDistance(position, brain.RoamPoint) < 6 then
			brain.StrategyUntil = 0
		end
		setState(brain, "Roam")
		moveTo(brain, brain.RoamPoint)
		return
	end

	local flag = nearestEnemyFlag(entity, position)
	if flag then
		setState(brain, "Push")
		attackObjective(brain, flag)
		return
	end

	-- 8. No flags left to push: hunt down remaining enemies
	local prey = nearestEnemyHeroAnywhere(entity, position)
	if prey then
		setState(brain, "Hunt")
		moveTo(brain, CombatService.GetPosition(prey) + brain.HuntOffset)
		return
	end
	setState(brain, "Idle")
	moveTo(brain, brain.RoamPoint)
end

local function updateMovement(brain, dt, now)
	local entity = brain.Entity
	local root = entity.Root
	if not root or not root.Parent then
		return
	end
	local position = root.Position
	if brain.Path then
		local waypoint = brain.Path[brain.PathIndex]
		if waypoint and Util.FlatDistance(position, waypoint.Position) < 3 then
			brain.PathIndex += 1
			local nextWaypoint = brain.Path[brain.PathIndex]
			if nextWaypoint then
				entity.Humanoid:MoveTo(nextWaypoint.Position)
			else
				brain.Path = nil
			end
		elseif not waypoint then
			brain.Path = nil
		end
	end
	local speed = Util.Flat(root.AssemblyLinearVelocity).Magnitude
	brain.Animator.SetMoving(speed > 1.5)
	if brain.Moving and entity.Humanoid.WalkSpeed > 0 then
		if Util.FlatDistance(position, brain.LastPosition) < 0.35 then
			brain.StuckTime += dt
		else
			brain.StuckTime = 0
		end
		if brain.StuckTime > STUCK_TIME then
			brain.StuckTime = 0
			brain.Path = nil
			local escape = position + Util.RotateY(Vector3.new(0, 0, 9), random:NextNumber(0, math.pi * 2))
			entity.Humanoid:MoveTo(CombatService.ClampToArena(escape))
			brain.UnstickUntil = now + 0.7
		end
	else
		brain.StuckTime = 0
	end
	brain.LastPosition = position
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------
function BotService.Init() end

function BotService.Attach(participant, entity)
	local difficulty = Constants.BotDifficulty[participant.Difficulty] or Constants.BotDifficulty.Normal
	local brain = {
		Participant = participant,
		Entity = entity,
		Difficulty = difficulty,
		Animator = CharacterFactory.CreateAnimator(entity.Model),
		PathObject = PathfindingService:CreatePath(PATH_PARAMS),
		NextThinkAt = 0,
		ReactionUntil = 0,
		NextAbilityCheck = 0,
		NextPathAt = 0,
		NextStrafeAt = 0,
		StrafeSign = 1,
		StrategyUntil = 0,
		HuntOffset = Vector3.zero,
		RoamPoint = Vector3.zero,
		LastPosition = CombatService.GetPosition(entity),
		StuckTime = 0,
		UnstickUntil = 0,
		State = "Spawned",
	}
	if Constants.DEBUG_MODE and entity.Model:FindFirstChild("Head") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "BotDebug"
		billboard.Size = UDim2.fromOffset(220, 24)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.TextColor3 = Color3.new(1, 1, 0.4)
		label.TextScaled = true
		label.Font = Enum.Font.Code
		label.Parent = billboard
		billboard.Parent = entity.Model.Head
		brain.DebugLabel = label
	end
	brain.Animator.SetMoving(false)
	brains[participant.Id] = brain
	return brain
end

function BotService.Detach(participant)
	local brain = brains[participant.Id]
	if brain then
		brains[participant.Id] = nil
	end
end

function BotService.GetBrain(participantId)
	return brains[participantId]
end

function BotService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			local dt = task.wait(LOOP_INTERVAL)
			if runId ~= myRun then
				break
			end
			local now = Util.Now()
			for _, brain in pairs(brains) do
				if brain.Entity.Alive then
					local ok, err = pcall(updateMovement, brain, dt, now)
					if not ok then
						warn("[Ruinfall] Bot movement error:", err)
					end
					if now >= brain.NextThinkAt and now >= brain.UnstickUntil then
						brain.NextThinkAt = now + brain.Difficulty.ThinkInterval
						local thinkOk, thinkErr = pcall(think, brain)
						if not thinkOk then
							warn("[Ruinfall] Bot think error:", thinkErr)
						end
					end
				end
			end
		end
	end)
end

function BotService.Stop()
	runId += 1
	for _, brain in pairs(brains) do
		local humanoid = brain.Entity.Humanoid
		if humanoid and humanoid.Parent then
			humanoid:MoveTo(CombatService.GetPosition(brain.Entity))
		end
		brain.Animator.SetMoving(false)
	end
end

function BotService.Cleanup()
	BotService.Stop()
	table.clear(brains)
end

return BotService
