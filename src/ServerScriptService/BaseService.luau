-- BaseService: team flags (spawn anchors), base turrets and healing,
-- the Last Stand timer and re-anchoring with Core Fragments.
--
-- Flag states (internal names kept for the rest of the game):
--   Intact    - team respawns and shops normally.
--   LastStand - "FLAG DOWN": the flag base was destroyed and dropped its banner on the
--               ground. An enemy picks it up by walking into it; if the carrier dies it
--               drops where they fell. While the banner is not destroyed the team can
--               re-anchor the base with a Core Fragment (restores the base, banner returns).
--               Dead members wait (no respawn) until then.
--   Lost      - "FLAG DESTROYED": an enemy carried the banner into their own intact base.
--               No respawns, no shopping, no restoring - the team fights on until its
--               last member falls. The last team with living members wins.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local FragmentService = require(script.Parent:WaitForChild("FragmentService"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local FLAG = Constants.Flag
local TICK_INTERVAL = 0.2
local UNDER_ATTACK_COOLDOWN = 8

-- State
local BaseService = {}
BaseService.Teams = {} -- [team] = state
BaseService.FlagDestroyed = Util.Signal.new() -- (team, killer)
BaseService.FlagRestored = Util.Signal.new() -- (team)

local runId = 0

-- Functions
local function newPart(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(properties) do
		part[key] = value
	end
	return part
end

-- Deeper, less blown-out crystal tint for the mesh-library flag core
local function crystalTint(color)
	return color:Lerp(Color3.fromRGB(25, 12, 16), 0.42)
end

local function buildFlag(base, team)
	local color = Constants.GetTeamColor(team)
	local position = base.Position
	local model = Instance.new("Model")
	model.Name = "Flag_" .. Constants.GetTeamName(team)

	local pedestal = newPart({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 7, 7),
		CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 38, 50),
		Material = Enum.Material.Slate,
	})
	pedestal.Parent = model

	local core = newPart({
		Name = "Core",
		Size = Vector3.new(2.6, 4, 2.6),
		CFrame = CFrame.new(position + Vector3.new(0, 4.3, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	core.Parent = model
	local light = Instance.new("PointLight")
	light.Name = "CoreLight"
	light.Color = color
	light.Range = 14
	light.Brightness = 0.9
	light.Parent = core

	-- Visual upgrade: carved stone pedestal + crystal cluster (collider/core logic unchanged)
	local assetLibrary = game:GetService("ServerStorage"):FindFirstChild("RuinfallAssets")
	local drumSource = assetLibrary and assetLibrary:FindFirstChild("Pillar_Small")
	if drumSource then
		pedestal.Transparency = 1
		local drum = drumSource:Clone()
		drum.Name = "PedestalVisual"
		drum.Size = Vector3.new(6.6, 1.9, 6.6)
		drum.CFrame = CFrame.new(position + Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, math.rad(22.5), 0)
		drum.CastShadow = true
		drum.Parent = model
		local prongSource = assetLibrary:FindFirstChild("Pillar_Broken")
		if prongSource then
			for index = 0, 3 do
				local angle = index * math.pi / 2 + math.rad(45)
				local offset = Vector3.new(math.sin(angle), 0, math.cos(angle)) * 2.35
				local prong = prongSource:Clone()
				prong.Name = "CoreProng"
				prong.Size = Vector3.new(0.75, 2.6, 0.9)
				prong.CFrame = CFrame.lookAt(position + offset + Vector3.new(0, 3.05, 0), position + Vector3.new(0, 3.05, 0)) * CFrame.Angles(math.rad(-14), 0, 0)
				prong.CastShadow = true
				prong.Parent = model
			end
		end
		core.Size = Vector3.new(2.1, 3.6, 2.1)
		core.Color = crystalTint(color)
		model:SetAttribute("CrystalCore", true)
		for index = 1, 3 do
			local angle = index * (2 * math.pi / 3)
			local shard = newPart({
				Name = "CoreShard",
				Size = Vector3.new(0.9, 1.9, 0.9),
				CFrame = CFrame.new(position + Vector3.new(math.sin(angle) * 1.25, 3.1, math.cos(angle) * 1.25)) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(22), math.rad(45), 0),
				Color = crystalTint(color),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
			})
			shard.Parent = model
		end
	end

	local back = -base.ToCenter
	local polePosition = position + back * 3 + Vector3.new(0, 8, 0)
	local pole = newPart({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(16, 0.5, 0.5),
		CFrame = CFrame.new(polePosition) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(180, 180, 195),
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	pole.Parent = model
	local tangent = Vector3.new(-base.ToCenter.Z, 0, base.ToCenter.X)
	local cloth = newPart({
		Name = "Cloth",
		Size = Vector3.new(0.15, 3.4, 5.2),
		CFrame = CFrame.fromMatrix(polePosition + Vector3.new(0, 6, 0) + tangent * 2.7, base.ToCenter, Vector3.yAxis),
		Color = color,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		CanQuery = false,
	})
	cloth.Parent = model
	-- Visual upgrade: heraldic banner mesh from the Blender library, tinted to the team colour
	local library = game:GetService("ServerStorage"):FindFirstChild("RuinfallAssets")
	local bannerSource = library and library:FindFirstChild("Banner_Cloth")
	if bannerSource then
		local banner = bannerSource:Clone()
		banner.Name = "Cloth"
		banner.Size = bannerSource.Size * 1.3
		local top = polePosition.Y + 8
		banner.CFrame = CFrame.fromMatrix(Vector3.new(polePosition.X, top - banner.Size.Y / 2 + 0.2, polePosition.Z) + tangent * (banner.Size.X / 2 + 0.15), tangent, Vector3.yAxis)
		local appearance = banner:FindFirstChildOfClass("SurfaceAppearance")
		if appearance then
			appearance.Color = color:Lerp(Color3.fromRGB(60, 50, 50), 0.2)
		end
		banner.Parent = model
		cloth:Destroy()
		cloth = banner
	end

	local anchorRing = newPart({
		Name = "AnchorRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, FLAG.REANCHOR_RADIUS * 2, FLAG.REANCHOR_RADIUS * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Constants.Colors.Fragment,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	anchorRing.Parent = model

	model.PrimaryPart = core
	model.Parent = base.Folder
	return model, core, cloth, anchorRing, pole
end

local function setFlagVisual(state, visual)
	local color = Constants.GetTeamColor(state.Team)
	local core, cloth, ring, pole = state.Core, state.Cloth, state.AnchorRing, state.Pole
	if not core or not core.Parent then
		return
	end
	local light = core:FindFirstChild("CoreLight")
	if visual == "Intact" then
		core.Color = (state.FlagModel and state.FlagModel:GetAttribute("CrystalCore")) and crystalTint(color) or color
		core.Material = Enum.Material.Neon
		cloth.Transparency = 0
		ring.Transparency = 1
		pole.CFrame = state.PoleCFrame
		if light then
			light.Enabled = true
		end
	elseif visual == "Destroyed" then
		core.Color = Color3.fromRGB(55, 55, 62)
		core.Material = Enum.Material.Slate
		cloth.Transparency = 1
		ring.Transparency = 0.35
		pole.CFrame = state.PoleCFrame * CFrame.Angles(0, math.rad(25), 0)
		if light then
			light.Enabled = false
		end
	elseif visual == "Lost" then
		core.Color = Color3.fromRGB(30, 30, 34)
		core.Material = Enum.Material.Slate
		cloth.Transparency = 1
		ring.Transparency = 1
		if light then
			light.Enabled = false
		end
	end
	if state.FlagModel then
		state.FlagModel:SetAttribute("FlagState", state.FlagState)
		for _, shard in ipairs(state.FlagModel:GetChildren()) do
			if shard.Name == "CoreShard" and shard:IsA("BasePart") then
				shard.Color = core.Color
				shard.Material = core.Material
			end
		end
	end
end

local function getAliveMembers(team)
	local alive = {}
	for _, participant in ipairs(PlayerService.GetTeamMembers(team)) do
		local entity = participant.Entity
		if entity and entity.Alive then
			table.insert(alive, entity)
		end
	end
	return alive
end

local function teamHasCarrier(team)
	for _, entity in ipairs(getAliveMembers(team)) do
		if entity.CarryingFragment then
			return true
		end
	end
	return false
end

-- The dropped / carried banner ------------------------------------------------------------
local function bannerModel(team, anchored)
	local color = Constants.GetTeamColor(team)
	local model = Instance.new("Model")
	model.Name = "DroppedFlag_" .. team
	local pole = newPart({ Name = "Pole", Size = Vector3.new(0.35, 7, 0.35), Color = Color3.fromRGB(90, 70, 45), Material = Enum.Material.Wood, CanCollide = false })
	pole.Anchored = anchored
	pole.Parent = model
	local cloth = newPart({ Name = "Cloth", Size = Vector3.new(0.15, 2.6, 3.4), Color = color, Material = Enum.Material.Fabric, CanCollide = false })
	cloth.Anchored = anchored
	cloth.Parent = model
	local glow = newPart({ Name = "Glow", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Color = color, Material = Enum.Material.Neon, CanCollide = false })
	glow.Anchored = anchored
	glow.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = glow
	for _, part in ipairs({ pole, cloth, glow }) do
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	model.PrimaryPart = pole
	return model, pole, cloth, glow
end

local function placeBanner(model, pole, cloth, glow, cframe)
	pole.CFrame = cframe * CFrame.new(0, 3.5, 0)
	cloth.CFrame = cframe * CFrame.new(0, 5.4, -1.8)
	glow.CFrame = cframe * CFrame.new(0, 7.2, 0)
end

local function clearBanner(state)
	if state.BannerModel then
		state.BannerModel:Destroy()
		state.BannerModel = nil
	end
	local carrier = state.Carrier
	if carrier then
		carrier.CarryingFlag = nil
		if carrier.Model then
			carrier.Model:SetAttribute("CarryingFlag", nil)
		end
	end
	state.Carrier = nil
	state.DropPosition = nil
end

local function dropBanner(state, position)
	clearBanner(state)
	local ground = Vector3.new(position.X, state.Base.Position.Y, position.Z)
	local model, pole, cloth, glow = bannerModel(state.Team, true)
	placeBanner(model, pole, cloth, glow, CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(12)))
	model.Parent = state.Base.Folder
	state.BannerModel = model
	state.DropPosition = ground
end

local function pickUpBanner(state, hero)
	clearBanner(state)
	local root = hero.Root
	local model, pole, cloth, glow = bannerModel(state.Team, false)
	placeBanner(model, pole, cloth, glow, root.CFrame * CFrame.new(0.9, -1.2, 0.8))
	for _, part in ipairs({ pole, cloth, glow }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	model.Parent = hero.Model
	state.BannerModel = model
	state.Carrier = hero
	hero.CarryingFlag = state.Team
	hero.Model:SetAttribute("CarryingFlag", state.Team)
	CombatService.BreakStealth(hero)
	local name = hero.Participant and hero.Participant.Name or "An enemy"
	Net.Notify(PlayerService.GetTeamPlayers(state.Team), "YOUR FLAG WAS TAKEN", "Danger", { Banner = true, Sub = name .. " has it - kill them, or restore your base with a Core Fragment!" })
	Net.Notify(PlayerService.GetTeamPlayers(hero.Team), "ENEMY FLAG TAKEN", "Success", { Banner = true, Sub = "Carry it into your own base to destroy it" })
	Net.Notify(nil, string.format("%s took the %s flag", name, Constants.GetTeamName(state.Team)), "Info")
end

local function setLost(state, reason)
	clearBanner(state)
	state.FlagState = "Lost"
	state.LastStandRemaining = 0
	state.Secured = false
	setFlagVisual(state, "Lost")
	local teamName = Constants.GetTeamName(state.Team)
	Net.Effect("FlagDestroyed", { Position = state.Base.Position, Color = Constants.GetTeamColor(state.Team) })
	Net.Notify(PlayerService.GetTeamPlayers(state.Team), "YOUR FLAG WAS DESTROYED", "Danger", { Banner = true, Sub = reason .. " - no more respawns or shopping. Fight to the last!" })
	Net.Notify(nil, teamName .. " FLAG DESTROYED - they fight on without respawns", "Warning")
end

-- enemies walk into a dropped banner to grab it; carriers destroy it at their own base
local function processBanner(state)
	if state.FlagState ~= "LastStand" then
		return
	end
	local carrier = state.Carrier
	if carrier then
		if not carrier.Alive or not carrier.Model or not carrier.Model.Parent then
			local where = state.CarrierLastPosition or state.Base.Position
			dropBanner(state, where)
			Net.Notify(nil, string.format("The %s flag was dropped", Constants.GetTeamName(state.Team)), "Info")
			return
		end
		local position = CombatService.GetPosition(carrier)
		state.CarrierLastPosition = position
		local home = BaseService.Teams[carrier.Team]
		if home and home.FlagState == "Intact" and Util.FlatDistance(position, home.Base.Position) <= FLAG.CAPTURE_RADIUS then
			if carrier.Participant then
				carrier.Participant.Stats.Flags += 1
			end
			local name = carrier.Participant and carrier.Participant.Name or Constants.GetTeamName(carrier.Team)
			setLost(state, name .. " destroyed it at the " .. Constants.GetTeamName(carrier.Team) .. " base")
		end
		return
	end
	if not state.DropPosition then
		return
	end
	local grabber = CombatService.FindNearestEnemy(state.FlagEntity, state.DropPosition, FLAG.PICKUP_RADIUS, function(entity)
		return entity.Kind == "Hero" and entity.Alive and not entity.CarryingFlag
	end)
	if grabber then
		pickUpBanner(state, grabber)
	end
end

local function restoreFlag(state, hero)
	clearBanner(state) -- the banner flies home
	state.FlagState = "Intact"
	state.LastStandRemaining = 0
	state.Secured = false
	CombatService.Revive(state.FlagEntity, FLAG.RESTORE_HEALTH_PERCENT)
	setFlagVisual(state, "Intact")
	local teamName = Constants.GetTeamName(state.Team)
	Net.Effect("FlagRestored", { Position = state.Base.Position, Color = Constants.GetTeamColor(state.Team) })
	Net.Notify(PlayerService.GetTeamPlayers(state.Team), "FLAG RESTORED", "Success", { Banner = true, Sub = (hero.Participant and hero.Participant.Name or "Your team") .. " re-anchored the flag base. Your flag is home and respawns are back!" })
	Net.Notify(nil, teamName .. " restored their flag", "Info")
	BaseService.FlagRestored:Fire(state.Team)
end

local function onFlagDestroyed(state, killer)
	state.FlagState = "LastStand"
	state.LastStandRemaining = 0
	state.Secured = teamHasCarrier(state.Team)
	state.Channels = {}
	setFlagVisual(state, "Destroyed")
	-- the base drops its banner a few steps toward the arena centre
	local toCenter = Util.Flat(Vector3.zero - state.Base.Position)
	toCenter = toCenter.Magnitude > 0.1 and toCenter.Unit or Vector3.new(0, 0, 1)
	dropBanner(state, state.Base.Position + toCenter * FLAG.DROP_OFFSET)
	local teamName = Constants.GetTeamName(state.Team)
	Net.Effect("FlagDestroyed", { Position = state.Base.Position, Color = Constants.GetTeamColor(state.Team) })
	Net.Notify(nil, teamName .. " FLAG BASE DESTROYED - their flag is on the ground!", "Danger")
	Net.Notify(PlayerService.GetTeamPlayers(state.Team), "YOUR FLAG BASE FELL", "Danger", { Banner = true, Sub = "Restore it with a Core Fragment before an enemy carries your flag home" })
	BaseService.FlagDestroyed:Fire(state.Team, killer)
end

local function processChannels(state, dt)
	local flag = state.FlagEntity
	local wantsRestore = state.FlagState == "LastStand"
	local wantsRepair = state.FlagState == "Intact" and flag.Health < flag.MaxHealth * 0.9
	for _, hero in ipairs(getAliveMembers(state.Team)) do
		local inRange = Util.FlatDistance(CombatService.GetPosition(hero), state.Base.Position) <= FLAG.REANCHOR_RADIUS
		if hero.CarryingFragment and inRange and (wantsRestore or wantsRepair) then
			local progress = (state.Channels[hero.Id] or 0) + dt
			state.Channels[hero.Id] = progress
			hero.Model:SetAttribute("ChannelProgress", math.min(1, progress / FLAG.REANCHOR_TIME))
			if progress >= FLAG.REANCHOR_TIME then
				state.Channels[hero.Id] = nil
				hero.Model:SetAttribute("ChannelProgress", 0)
				FragmentService.Consume(hero)
				if wantsRestore then
					restoreFlag(state, hero)
				else
					CombatService.Heal(flag, flag.MaxHealth * FLAG.REPAIR_PERCENT, true)
					Net.Notify(PlayerService.GetTeamPlayers(state.Team), "Flag repaired with a Core Fragment", "Success")
				end
				return
			end
		elseif state.Channels[hero.Id] then
			state.Channels[hero.Id] = nil
			hero.Model:SetAttribute("ChannelProgress", 0)
		end
	end
end

local function tick(dt)
	local now = Util.Now()
	for team, state in pairs(BaseService.Teams) do
		if not state.Eliminated then
			local flag = state.FlagEntity
			local basePosition = state.Base.Position
			if state.FlagState == "Intact" and flag.Alive then
				if now >= state.NextTurretAt then
					local target = CombatService.FindNearestEnemy(flag, basePosition, FLAG.TURRET_RANGE, function(entity)
						-- base defence also shoots enemy war band creeps
						return (entity.Kind == "Hero" or entity.Kind == "Creep") and not CombatService.IsStealthed(entity)
					end)
					if target then
						state.NextTurretAt = now + FLAG.TURRET_INTERVAL
						Net.Effect("Lightning", { From = state.Core.Position + Vector3.new(0, 2, 0), To = CombatService.GetPosition(target), Color = Constants.GetTeamColor(team) })
						-- Fragile debuff: each existing stack adds bonus damage, then a new stack is applied
						local stacks = target.FragileStacks or 0
						local damage = FLAG.TURRET_DAMAGE + stacks * FLAG.FRAGILE_DAMAGE_PER_STACK
						CombatService.ApplyDamage(flag, target, damage)
						if target.Alive then
							target.FragileStacks = stacks + 1
							if target.Model then
								target.Model:SetAttribute("FragileStacks", target.FragileStacks)
							end
							Net.Effect("Fragile", { Position = CombatService.GetPosition(target), Stacks = target.FragileStacks, TargetId = target.Id })
						end
					end
				end
				for _, hero in ipairs(getAliveMembers(team)) do
					if Util.FlatDistance(CombatService.GetPosition(hero), basePosition) <= FLAG.HEAL_RADIUS then
						CombatService.Heal(hero, hero.MaxHealth * FLAG.BASE_REGEN_PERCENT * dt)
					end
				end
			elseif state.FlagState == "LastStand" then
				-- no timer: the flag stays down until it is restored or destroyed
				state.Secured = teamHasCarrier(team)
				processBanner(state)
			end
			if state.FlagState ~= "Lost" then
				processChannels(state, dt)
			end
		end
	end
end

-- Public API ---------------------------------------------------------------------------
function BaseService.Init()
	-- Reset fragile stacks when any entity dies (so respawning starts fresh)
	CombatService.EntityDied:Connect(function(entity)
		if entity.FragileStacks and entity.FragileStacks > 0 then
			entity.FragileStacks = 0
			if entity.Model then
				entity.Model:SetAttribute("FragileStacks", 0)
			end
		end
	end)
	CombatService.EntityDied:Connect(function(entity, killer)
		if entity.CarryingFlag then
			local carried = BaseService.Teams[entity.CarryingFlag]
			if carried and carried.Carrier == entity and carried.FlagState == "LastStand" then
				dropBanner(carried, CombatService.GetPosition(entity))
				Net.Notify(nil, string.format("The %s flag was dropped", Constants.GetTeamName(carried.Team)), "Info")
			end
			entity.CarryingFlag = nil
		end
		if entity.Kind == "Flag" then
			local state = BaseService.Teams[entity.Team]
			if state and state.FlagEntity == entity then
				onFlagDestroyed(state, killer)
			end
		end
	end)
	CombatService.EntityDamaged:Connect(function(entity)
		if entity.Kind == "Flag" then
			local state = BaseService.Teams[entity.Team]
			if state and Util.Now() - state.LastAttackAlert > UNDER_ATTACK_COOLDOWN then
				state.LastAttackAlert = Util.Now()
				Net.Notify(PlayerService.GetTeamPlayers(entity.Team), "Your flag is under attack!", "Warning")
			end
		end
	end)
	FragmentService.Picked:Connect(function(hero)
		local state = BaseService.Teams[hero.Team]
		if state and state.FlagState == "LastStand" then
			state.Secured = true
			Net.Notify(PlayerService.GetTeamPlayers(hero.Team), "CORE FRAGMENT SECURED", "Fragment", { Banner = true, Sub = "Bring it to your flag base to restore it!" })
		end
	end)
end

function BaseService.Setup(mapData, activeTeams)
	BaseService.Cleanup()
	for _, team in ipairs(activeTeams) do
		local base = mapData.Bases[team]
		local model, core, cloth, anchorRing, pole = buildFlag(base, team)
		local entity = CombatService.Register({
			Kind = "Flag",
			Team = team,
			Model = model,
			Root = core,
			Position = base.Position,
			Health = FLAG.MAX_HEALTH,
			MaxHealth = FLAG.MAX_HEALTH,
			Armor = FLAG.ARMOR,
			Radius = 3.8,
		})
		BaseService.Teams[team] = {
			Team = team,
			Base = base,
			FlagEntity = entity,
			FlagModel = model,
			Core = core,
			Cloth = cloth,
			AnchorRing = anchorRing,
			Pole = pole,
			PoleCFrame = pole.CFrame,
			FlagState = "Intact",
			LastStandRemaining = 0,
			Secured = false,
			Eliminated = false,
			NextTurretAt = 0,
			LastAttackAlert = 0,
			Channels = {},
		}
		model:SetAttribute("FlagState", "Intact")
	end
end

function BaseService.GetState(team)
	return BaseService.Teams[team]
end

function BaseService.CanRespawn(team)
	local state = BaseService.Teams[team]
	return state ~= nil and not state.Eliminated and state.FlagState == "Intact"
end

function BaseService.GetSpawnPoint(team, index)
	local state = BaseService.Teams[team]
	if not state then
		return Vector3.new(0, 0.2, 0)
	end
	local points = state.Base.SpawnPoints
	return points[((index - 1) % #points) + 1]
end

function BaseService.MarkEliminated(team)
	local state = BaseService.Teams[team]
	if not state or state.Eliminated then
		return
	end
	state.Eliminated = true
	clearBanner(state)
	if state.FlagEntity.Alive then
		state.FlagEntity.Alive = false
		state.FlagEntity.Model:SetAttribute("Dead", true)
	end
	state.FlagState = "Lost"
	setFlagVisual(state, "Lost")
end

function BaseService.Start()
	runId += 1
	local myRun = runId
	task.spawn(function()
		while runId == myRun do
			local dt = task.wait(TICK_INTERVAL)
			if runId ~= myRun then
				break
			end
			tick(dt)
		end
	end)
end

function BaseService.Stop()
	runId += 1
end

function BaseService.Cleanup()
	BaseService.Stop()
	for _, state in pairs(BaseService.Teams) do
		clearBanner(state)
	end
	table.clear(BaseService.Teams)
end

function BaseService.Serialize()
	local list = {}
	for team, state in pairs(BaseService.Teams) do
		table.insert(list, {
			Team = team,
			FlagState = state.FlagState,
			FlagHealth = math.ceil(state.FlagEntity.Health),
			FlagMaxHealth = state.FlagEntity.MaxHealth,
			LastStandRemaining = state.LastStandRemaining,
			Secured = state.Secured,
			Eliminated = state.Eliminated,
			Position = state.Base.Position,
			DropPosition = state.DropPosition,
			CarrierId = state.Carrier and state.Carrier.Id or nil,
			CarrierName = state.Carrier and state.Carrier.Participant and state.Carrier.Participant.Name or nil,
			CarrierPosition = state.Carrier and state.Carrier.Alive and CombatService.GetPosition(state.Carrier) or nil,
		})
	end
	table.sort(list, function(a, b)
		return a.Team < b.Team
	end)
	return list
end

return BaseService
