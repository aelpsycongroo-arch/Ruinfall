-- MinimapController: live top-right minimap inside the HUD's ornate border (team-tinted accents,
-- - / + zoom buttons). Static layer (walls, rocks, brush, lanes) is drawn once per map; the dynamic
-- layer (flags, ruins, camps, fragments, heroes) refreshes at 10 Hz and respects fog of war.
-- Zoomed in, the map follows the local hero.

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local COLORS = UITheme.Colors
local New, Label = UITheme.New, UITheme.Label
local SIZE = 237 -- map drawing space (px); scaled to the HUD's MapHolder at runtime
local FRAME = 300 -- ornate ring image size
local GOLD = Color3.fromRGB(248, 206, 112)
local ZOOMS = { 1, 1.6, 2.4 }
local UPDATE_INTERVAL = 0.1
local player = Players.LocalPlayer

-- State
local MinimapController = {}
local ClientState = nil
local FogController = nil
local frame = nil
local world = nil
local worldScale = nil
local staticLayer = nil
local dynamicLayer = nil
local builtSeed = nil
local scale = 1
local zoomIndex = 1
local pools = {} -- [kind] = { items, used }
local accumulator = 0

-- Functions
local function toMapXY(position)
	return SIZE / 2 + position.X * scale, SIZE / 2 + position.Z * scale
end

local function toMap(position)
	return UDim2.fromOffset(toMapXY(position))
end

local function yawDegrees(cframe)
	local _, yaw = cframe:ToOrientation()
	return -math.deg(yaw)
end

local function buildStatic(radius)
	staticLayer:ClearAllChildren()
	scale = SIZE / (2 * (radius + 4))
	local arena = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(radius * 2 * scale, radius * 2 * scale), BackgroundColor3 = Color3.fromRGB(38, 40, 38), Parent = staticLayer })
	UITheme.Corner(arena, math.floor(radius * scale))
	UITheme.Stroke(arena, Color3.fromRGB(150, 118, 68), 2, 0.2)
	local map = workspace:FindFirstChild("RuinfallMap")
	if not map then
		return
	end
	local decor = map:FindFirstChild("Decor")
	if decor then
		for _, part in ipairs(decor:GetChildren()) do
			if part.Name == "Lane" and part:IsA("BasePart") then
				New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(part.Position), Size = UDim2.fromOffset(math.max(2, part.Size.X * scale), part.Size.Z * scale), Rotation = yawDegrees(part.CFrame), BackgroundColor3 = Color3.fromRGB(112, 112, 108), Parent = staticLayer })
			elseif part.Name == "Road" and part:IsA("Model") then
				-- mesh road modules (visual upgrade) drawn as lane strips
				for _, module in ipairs(part:GetChildren()) do
					if module:IsA("BasePart") then
						New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(module.Position), Size = UDim2.fromOffset(math.max(2, module.Size.X * scale), module.Size.Z * scale + 1), Rotation = yawDegrees(module.CFrame), BackgroundColor3 = Color3.fromRGB(112, 112, 108), Parent = staticLayer })
					end
				end
			end
		end
	end
	local brush = map:FindFirstChild("Brush")
	if brush then
		for _, part in ipairs(brush:GetChildren()) do
			if part:IsA("BasePart") then
				New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(part.Position), Size = UDim2.fromOffset(part.Size.X * scale, part.Size.Z * scale), Rotation = yawDegrees(part.CFrame), BackgroundColor3 = Color3.fromRGB(62, 80, 58), BackgroundTransparency = 0.35, Parent = staticLayer })
			end
		end
	end
	local blockers = map:FindFirstChild("Blockers")
	if blockers then
		for _, part in ipairs(blockers:GetChildren()) do
			local shape = part:GetAttribute("MinimapShape")
			if shape == "Box" then
				New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(part.Position), Size = UDim2.fromOffset(math.max(2, part.Size.X * scale), math.max(2, part.Size.Z * scale)), Rotation = yawDegrees(part.CFrame), BackgroundColor3 = Color3.fromRGB(150, 150, 146), Parent = staticLayer })
			elseif shape == "Circle" then
				local diameter = math.max(3, part.Size.Y * scale)
				local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(part.Position), Size = UDim2.fromOffset(diameter, diameter), BackgroundColor3 = Color3.fromRGB(122, 122, 118), Parent = staticLayer })
				UITheme.Corner(dot, math.ceil(diameter / 2))
			end
		end
	end
end

local function acquire(kind, factory)
	local pool = pools[kind]
	if not pool then
		pool = { Items = {}, Used = 0 }
		pools[kind] = pool
	end
	pool.Used += 1
	local item = pool.Items[pool.Used]
	if not item then
		item = factory()
		item.Parent = dynamicLayer
		pool.Items[pool.Used] = item
	end
	item.Visible = true
	return item
end

local function beginPools()
	for _, pool in pairs(pools) do
		pool.Used = 0
	end
end

local function endPools()
	for _, pool in pairs(pools) do
		for index = pool.Used + 1, #pool.Items do
			pool.Items[index].Visible = false
		end
	end
end

local function dotFactory(size, stroke)
	return function()
		local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), ZIndex = 5 })
		UITheme.Corner(dot, math.ceil(size / 2))
		if stroke then
			UITheme.Stroke(dot, stroke, 1.5, 0)
		end
		return dot
	end
end

local function diamondFactory(size)
	return function()
		return New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), Rotation = 45, ZIndex = 4 })
	end
end

local function flagFactory()
	local icon = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), ZIndex = 3 })
	UITheme.Corner(icon, 4)
	UITheme.Stroke(icon, Color3.new(1, 1, 1), 1.5, 0.2)
	return icon
end

local function updateDynamic()
	local state = ClientState.Game
	if not state then
		return
	end
	local myTeam = ClientState.GetMyTeam()
	local blink = math.floor(os.clock() * 3) % 2 == 0
	beginPools()
	for _, teamState in ipairs(state.Teams or {}) do
		local icon = acquire("Flag", flagFactory)
		icon.Position = toMap(teamState.Position)
		local color = Constants.GetTeamColor(teamState.Team)
		if teamState.Eliminated or teamState.FlagState == "Lost" then
			icon.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
		elseif teamState.FlagState == "LastStand" then
			icon.BackgroundColor3 = blink and COLORS.Danger or color
		else
			icon.BackgroundColor3 = color
		end
	end
	for _, camp in ipairs(state.Camps or {}) do
		if FogController.IsExplored(camp.Position) then
			local dot = acquire("Camp", dotFactory(9, Color3.fromRGB(20, 10, 10)))
			dot.Position = toMap(camp.Position)
			dot.BackgroundColor3 = camp.State == "Alive" and Color3.fromRGB(220, 110, 60) or Color3.fromRGB(90, 70, 60)
		end
	end
	for _, ruin in ipairs(state.Ruins or {}) do
		local icon = acquire("Ruin", diamondFactory(11))
		icon.Position = toMap(ruin.Position)
		icon.BackgroundColor3 = COLORS.Gold
	end
	-- Royale: shrinking play zone (purple), the next zone (white) and gear lying around
	local royale = state.Royale
	if royale and royale.Zone then
		local zone = royale.Zone
		local function zoneRing(kind, color, x, z, radius, thickness)
			local ringFrame = acquire(kind, function()
				local frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 6 })
				New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
				UITheme.Stroke(frame, color, thickness, 0)
				return frame
			end)
			ringFrame.Position = toMap(Vector3.new(x, 0, z))
			ringFrame.Size = UDim2.fromOffset(radius * 2 * scale, radius * 2 * scale)
		end
		zoneRing("ZoneNext", Color3.fromRGB(245, 245, 255), zone.NextX, zone.NextZ, zone.NextRadius, 1)
		zoneRing("Zone", Color3.fromRGB(190, 110, 255), zone.X, zone.Z, zone.Radius, 2)
		for _, loot in ipairs(royale.Loot or {}) do
			if loot.Kind ~= "Potion" then
				local icon = acquire("Loot", diamondFactory(6))
				icon.Position = toMap(loot.Position)
				icon.BackgroundColor3 = loot.Kind == "Skill" and Color3.fromRGB(200, 150, 255) or Color3.fromRGB(255, 200, 90)
			end
		end
	end
	for _, fragment in ipairs(state.Fragments or {}) do
		local icon = acquire("Fragment", diamondFactory(8))
		icon.Position = toMap(fragment.Position)
		icon.BackgroundColor3 = COLORS.Fragment
	end
	local myCharacter = player.Character
	for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and model:GetAttribute("Dead") ~= true and model ~= myCharacter then
			local team = model:GetAttribute("Team")
			if team == myTeam then
				local dot = acquire("Ally", dotFactory(8, Color3.new(1, 1, 1)))
				dot.Position = toMap(root.Position)
				dot.BackgroundColor3 = Constants.GetTeamColor(team)
			elseif ClientState.IsHeroVisible(model) then
				local dot = acquire("Enemy", dotFactory(8, Color3.new(0, 0, 0)))
				dot.Position = toMap(root.Position)
				dot.BackgroundColor3 = Constants.GetTeamColor(team)
			end
		end
	end
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	if myRoot and myCharacter:GetAttribute("EntityId") then
		local arrow = acquire("Self", function()
			local holder = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, ZIndex = 8 })
			Label({ Name = "Arrow", Text = "\u{25B2}", TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = holder })
			return holder
		end)
		arrow.Position = toMap(myRoot.Position)
		local look = myRoot.CFrame.LookVector
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
	endPools()
end

-- Zoom: 1 = whole arena; higher levels follow the local hero. The SIZE-px drawing space is
-- scaled to the MapHolder's on-screen size, so the map follows the HUD's responsive layout.
local holder = nil
local function applyZoom()
	local zoom = ZOOMS[zoomIndex]
	local span = holder.AbsoluteSize.X
	local base = span > 0 and span / SIZE or 1
	worldScale.Scale = base * zoom
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if zoom <= 1 or not root then
		world.Position = UDim2.fromOffset(span / 2 - SIZE / 2 * base * zoom, span / 2 - SIZE / 2 * base * zoom)
		return
	end
	local x, y = toMapXY(root.Position)
	world.Position = UDim2.fromOffset(span / 2 - x * base * zoom, span / 2 - y * base * zoom)
end

-- Public API
function MinimapController.Init(clientState, fogController, parent)
	ClientState = clientState
	FogController = fogController
	-- frame art, N badge and zoom tiles are part of the HUD layout (StarterGui.MainHUD);
	-- the map itself is drawn into its round MapHolder (CanvasGroup clips to the circle)
	frame = parent:FindFirstChild("Minimap", true)
	holder = frame and frame:FindFirstChild("MapHolder")
	if not holder then
		frame = New("Frame", { Name = "Minimap", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(FRAME, FRAME), BackgroundTransparency = 1, Parent = parent })
		holder = New("CanvasGroup", { Name = "MapHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(SIZE, SIZE), BackgroundColor3 = Color3.fromRGB(28, 26, 24), Parent = frame })
		New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = holder })
	end
	local map = holder
	world = New("Frame", { Name = "World", Size = UDim2.fromOffset(SIZE, SIZE), BackgroundTransparency = 1, Parent = map })
	worldScale = New("UIScale", { Parent = world })
	staticLayer = New("Frame", { Name = "Static", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = world })
	dynamicLayer = New("Frame", { Name = "Dynamic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = world })
	-- inner shadow under the ring
	local shade = New("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = map })
	New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shade })
	UITheme.Stroke(shade, Color3.new(0, 0, 0), 6, 0.45)

	-- zoom tiles (magnifiers are drawn in the frame art)
	local zoomIn, zoomOut = frame:FindFirstChild("ZoomIn"), frame:FindFirstChild("ZoomOut")
	if zoomIn then
		zoomIn.Activated:Connect(function()
			zoomIndex = math.min(#ZOOMS, zoomIndex + 1)
			applyZoom()
		end)
	end
	if zoomOut then
		zoomOut.Activated:Connect(function()
			zoomIndex = math.max(1, zoomIndex - 1)
			applyZoom()
		end)
	end

	RunService.RenderStepped:Connect(function(dt)
		if not ClientState.InMatch() then
			builtSeed = nil
			return
		end
		local seed = workspace:GetAttribute("MatchSeed")
		if seed and seed ~= builtSeed and workspace:FindFirstChild("RuinfallMap") then
			builtSeed = seed
			buildStatic(workspace:GetAttribute("ArenaRadius") or Constants.Map.RADIUS)
		end
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			updateDynamic()
		end
		applyZoom()
	end)
end

return MinimapController
