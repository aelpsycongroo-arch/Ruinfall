-- FogController: lightweight client-side fog of war.
-- A grid of dark tiles floats above the arena. Cells in line of sight of your
-- team (heroes + intact flag) become clear, previously seen cells stay dimmed,
-- unexplored cells are nearly black. Enemy heroes are hidden separately using
-- the server's visibility list, so this layer is presentation only.

-- Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Constants
local STATE = Constants.MatchState
local CELL = Constants.Map.FOG_CELL
local FOG_HEIGHT = Constants.Map.FOG_HEIGHT
local UPDATE_INTERVAL = 0.2
-- puffs overlap ~4x, so per-puff values are lighter than the old single-tile values
local UNEXPLORED = 0.22
local EXPLORED = 0.72
local CLEAR = 1
local FADE_SPEED = 4

-- State
local FogController = {}
local ClientState = nil
local tiles = {} -- [key] = tile
local animating = {} -- [tile] = true
local visibleKeys = {}
local folder = nil
local builtSeed = nil
local revealAll = false
local losParams = RaycastParams.new()
local fogTemplate = nil
local accumulator = 0

-- Functions
local function cellIndex(value)
	return math.floor(value / CELL)
end

local function cellKey(ix, iz)
	return ix * 4096 + iz
end

local function setTarget(tile, target)
	if tile.Target ~= target then
		tile.Target = target
		animating[tile] = true
	end
end

function FogController.Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(tiles)
	table.clear(animating)
	table.clear(visibleKeys)
	builtSeed = nil
end

function FogController.Build(radius, seed)
	FogController.Clear()
	builtSeed = seed
	local clientAssets = game:GetService("ReplicatedStorage"):FindFirstChild("RuinfallClientAssets")
	fogTemplate = clientAssets and clientAssets:FindFirstChild("FogPuff")
	folder = Instance.new("Folder")
	folder.Name = "LocalFog"
	local count = math.ceil((radius + CELL) / CELL)
	for ix = -count, count - 1 do
		for iz = -count, count - 1 do
			local center = Vector3.new((ix + 0.5) * CELL, 0, (iz + 0.5) * CELL)
			if center.Magnitude <= radius + CELL * 1.5 then
				local part
				if fogTemplate then
					-- soft, overlapping fog puffs (Blender alpha texture) instead of hard squares
					part = fogTemplate:Clone()
					part.Name = "Fog"
					local spread = CELL * 2.2
					part.Size = Vector3.new(spread, fogTemplate.Size.Y, spread)
					part.CFrame = CFrame.new(center + Vector3.new(0, FOG_HEIGHT + ((ix + iz) % 3) * 0.05, 0)) * CFrame.Angles(0, ((ix * 7 + iz * 13) % 12) * 0.52, 0)
				else
					part = Instance.new("Part")
					part.Name = "Fog"
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Material = Enum.Material.SmoothPlastic
					part.Color = Color3.fromRGB(5, 5, 12)
					part.Size = Vector3.new(CELL, 0.2, CELL)
					part.Position = center + Vector3.new(0, FOG_HEIGHT, 0)
				end
				part.Transparency = UNEXPLORED
				part.Parent = folder
				tiles[cellKey(ix, iz)] = { Part = part, Center = center, Current = UNEXPLORED, Target = UNEXPLORED, Explored = false }
			end
		end
	end
	folder.Parent = workspace
	local map = workspace:FindFirstChild("RuinfallMap")
	losParams.FilterType = Enum.RaycastFilterType.Include
	losParams.FilterDescendantsInstances = { map and map:FindFirstChild("Blockers") }
end

local function collectViewers()
	local viewers = {}
	local myTeam = ClientState.GetMyTeam()
	for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
		if model:GetAttribute("Team") == myTeam and model:GetAttribute("Dead") ~= true then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(viewers, { Position = root.Position, Radius = Constants.Vision.RADIUS })
			end
		end
	end
	local teamState = ClientState.GetTeamState(myTeam)
	if teamState and teamState.FlagState == "Intact" then
		table.insert(viewers, { Position = teamState.Position, Radius = Constants.Flag.VISION_RADIUS })
	end
	return viewers
end

local function recompute()
	local newVisible = {}
	if not revealAll then
		for _, viewer in ipairs(collectViewers()) do
			local origin = Vector3.new(viewer.Position.X, 3, viewer.Position.Z)
			local radius = viewer.Radius
			for ix = cellIndex(origin.X - radius), cellIndex(origin.X + radius) do
				for iz = cellIndex(origin.Z - radius), cellIndex(origin.Z + radius) do
					local key = cellKey(ix, iz)
					local tile = tiles[key]
					if tile and not newVisible[key] then
						local target = Vector3.new(tile.Center.X, 3, tile.Center.Z)
						local offset = target - origin
						local distance = offset.Magnitude
						if distance <= radius then
							local clear = distance < CELL
							if not clear then
								local hit = workspace:Raycast(origin, offset, losParams)
								clear = hit == nil or (hit.Position - origin).Magnitude >= distance - CELL * 0.7
							end
							if clear then
								newVisible[key] = true
							end
						end
					end
				end
			end
		end
	end
	for key, tile in pairs(tiles) do
		local visible = revealAll or newVisible[key] == true
		if visible then
			tile.Explored = true
			setTarget(tile, CLEAR)
		else
			setTarget(tile, tile.Explored and EXPLORED or UNEXPLORED)
		end
	end
	visibleKeys = newVisible
end

local function onRender(dt)
	local state = ClientState.GetMatchState()
	local inMatch = state == STATE.STARTING or state == STATE.ACTIVE or state == STATE.ENDING
	if inMatch then
		local seed = workspace:GetAttribute("MatchSeed")
		if seed and seed ~= builtSeed and workspace:FindFirstChild("RuinfallMap") then
			FogController.Build(workspace:GetAttribute("ArenaRadius") or Constants.Map.RADIUS, seed)
		end
	elseif folder then
		FogController.Clear()
	end
	if not folder then
		return
	end
	local me = ClientState.GetMe()
	revealAll = state == STATE.ENDING or (me ~= nil and (me.State == "Eliminated" or me.Spectator == true))
	accumulator += dt
	if accumulator >= UPDATE_INTERVAL then
		accumulator = 0
		recompute()
	end
	local step = FADE_SPEED * dt
	for tile in pairs(animating) do
		local difference = tile.Target - tile.Current
		if math.abs(difference) <= step then
			tile.Current = tile.Target
			animating[tile] = nil
		else
			tile.Current += math.sign(difference) * step
		end
		tile.Part.Transparency = tile.Current
	end
end

-- Public API
function FogController.IsVisible(position)
	if not folder or revealAll then
		return true
	end
	return visibleKeys[cellKey(cellIndex(position.X), cellIndex(position.Z))] == true
end

function FogController.IsExplored(position)
	if not folder or revealAll then
		return true
	end
	local tile = tiles[cellKey(cellIndex(position.X), cellIndex(position.Z))]
	return tile ~= nil and tile.Explored
end

function FogController.Init(clientState)
	ClientState = clientState
	RunService.RenderStepped:Connect(onRender)
end

return FogController
