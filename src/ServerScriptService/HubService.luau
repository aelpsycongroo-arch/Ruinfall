-- HubService: the Ruinfall Hall. Public servers are a walkable medieval hub hall with
-- lobby gates; reserved (private) servers run matches.
--   * Players walk up to a gate (proximity prompt) or use the lobby board to join one
--     of LOBBY_COUNT lobbies. The first member is the host and picks the team mode.
--   * When the host starts, the server reserves a private server of THIS place and
--     teleports the lobby there with TeleportData { Mode, Lobby, HostUserId }. That
--     server detects it is reserved and runs the normal Ruinfall match flow.
--   * Teleporting is impossible inside Roblox Studio, so there START runs the match
--     on this same server instead (the hall is removed, the match lobby opens).
-- Server-authoritative: clients only send Join / Leave / SetMode / Start intents.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local LOBBY_COUNT = 4
local LOBBY_NAMES = { "LOBBY I", "LOBBY II", "LOBBY III", "LOBBY IV" }
local LOBBY_TITLES = { "The Iron Gate", "The Ember Gate", "The Frost Gate", "The Verdant Gate" }
local LOBBY_COLORS = {
	Color3.fromRGB(255, 190, 90), Color3.fromRGB(235, 90, 60), Color3.fromRGB(110, 190, 255), Color3.fromRGB(110, 220, 120),
}
local MODES = { "2Team", "4Team", "6Team" }
local DEFAULT_MODE = "2Team"
local LAUNCH_TIMEOUT = 25 -- seconds before a stuck launch reopens the lobby
local REQUEST_INTERVAL = 0.25
local HALL_FLOOR_Y = 400 -- the hall floats high above the (unused) arena area

-- State
local HubService = {}
HubService.Lobbies = {}
local hallFolder = nil
local onLocalStart = nil
local lastRequest = setmetatable({}, { __mode = "k" })
local connections = {}
local active = false
local parkedMap = nil -- the saved arena preview, hidden while the hub runs

-- Role --------------------------------------------------------------------------------
-- "Match" on reserved servers (teleported lobbies), "Hub" everywhere else.
function HubService.DetermineRole()
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return "Match"
	end
	if ServerStorage:GetAttribute("ForceMatchRole") == true then
		return "Match" -- debug switch: skip the hall entirely
	end
	return "Hub"
end

-- Hall construction ------------------------------------------------------------------
local function part(properties)
	local p = Instance.new(properties.ClassName or "Part")
	properties.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(properties) do
		p[key] = value
	end
	if not p.Parent then
		p.Parent = hallFolder
	end
	return p
end

local function surfaceText(target, face, lines)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local labels = {}
	for index, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line.Name or ("Line" .. index)
		label.BackgroundTransparency = 1
		label.Position = line.Position
		label.Size = line.Size
		label.Font = line.Font or Enum.Font.Fondamento
		label.TextScaled = true
		label.Text = line.Text or ""
		label.TextColor3 = line.Color or Color3.fromRGB(255, 225, 160)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
		labels[label.Name] = label
	end
	return gui, labels
end

local function torch(position)
	part({ Name = "TorchPost", Size = Vector3.new(0.6, 2.4, 0.6), Position = position, Color = Color3.fromRGB(80, 55, 35), Material = Enum.Material.Wood })
	local bowl = part({ Name = "TorchBowl", Size = Vector3.new(1.2, 0.5, 1.2), Position = position + Vector3.new(0, 1.4, 0), Color = Color3.fromRGB(60, 58, 55), Material = Enum.Material.Metal })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 80, 20)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 20
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = bowl
end

local function pillar(position, height)
	part({ Name = "PillarBase", Size = Vector3.new(5, 1.2, 5), Position = position + Vector3.new(0, 0.6, 0), Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Limestone })
	part({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 3.6, 3.6), CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 142, 128), Material = Enum.Material.Limestone })
	part({ Name = "PillarCap", Size = Vector3.new(5, 1.2, 5), Position = position + Vector3.new(0, height - 0.6, 0), Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Limestone })
end

local function buildHall()
	hallFolder = Instance.new("Folder")
	hallFolder.Name = "RuinfallHall"
	hallFolder.Parent = workspace
	local y = HALL_FLOOR_Y
	local width, depth, height = 120, 96, 30
	local stone = Color3.fromRGB(96, 90, 84)
	-- floor, rug, walls
	part({ Name = "Floor", Size = Vector3.new(width, 2, depth), Position = Vector3.new(0, y - 1, 0), Color = Color3.fromRGB(88, 82, 76), Material = Enum.Material.Slate })
	part({ Name = "FloorTrim", Size = Vector3.new(width - 8, 0.1, depth - 8), Position = Vector3.new(0, y + 0.02, 0), Color = Color3.fromRGB(110, 100, 88), Material = Enum.Material.Cobblestone })
	part({ Name = "Rug", Size = Vector3.new(16, 0.12, depth - 20), Position = Vector3.new(0, y + 0.1, 4), Color = Color3.fromRGB(120, 24, 28), Material = Enum.Material.Fabric })
	part({ Name = "RugBorderL", Size = Vector3.new(0.8, 0.14, depth - 20), Position = Vector3.new(-8, y + 0.11, 4), Color = Color3.fromRGB(200, 160, 70), Material = Enum.Material.Fabric })
	part({ Name = "RugBorderR", Size = Vector3.new(0.8, 0.14, depth - 20), Position = Vector3.new(8, y + 0.11, 4), Color = Color3.fromRGB(200, 160, 70), Material = Enum.Material.Fabric })
	part({ Name = "WallBack", Size = Vector3.new(width, height, 3), Position = Vector3.new(0, y + height / 2, -depth / 2 - 1.5), Color = stone, Material = Enum.Material.Cobblestone })
	part({ Name = "WallFront", Size = Vector3.new(width, height, 3), Position = Vector3.new(0, y + height / 2, depth / 2 + 1.5), Color = stone, Material = Enum.Material.Cobblestone })
	part({ Name = "WallLeft", Size = Vector3.new(3, height, depth + 6), Position = Vector3.new(-width / 2 - 1.5, y + height / 2, 0), Color = stone, Material = Enum.Material.Cobblestone })
	part({ Name = "WallRight", Size = Vector3.new(3, height, depth + 6), Position = Vector3.new(width / 2 + 1.5, y + height / 2, 0), Color = stone, Material = Enum.Material.Cobblestone })
	-- roof beams (open roof lets the sun in)
	for z = -depth / 2 + 8, depth / 2 - 8, 14 do
		part({ Name = "Beam", Size = Vector3.new(width + 6, 1.6, 2), Position = Vector3.new(0, y + height - 1, z), Color = Color3.fromRGB(70, 48, 30), Material = Enum.Material.Wood })
	end
	-- colonnades + torches
	for _, x in ipairs({ -34, 34 }) do
		for _, z in ipairs({ -22, -4, 14, 32 }) do
			pillar(Vector3.new(x, y, z), height - 2)
		end
	end
	for _, x in ipairs({ -width / 2 + 2, width / 2 - 2 }) do
		for _, z in ipairs({ -30, -10, 10, 30 }) do
			torch(Vector3.new(x, y + 7, z))
		end
	end
	-- title board above the gates
	local title = part({ Name = "TitleBoard", Size = Vector3.new(56, 7, 0.6), Position = Vector3.new(0, y + 24, -depth / 2 + 0.4), Color = Color3.fromRGB(60, 38, 24), Material = Enum.Material.Wood })
	surfaceText(title, Enum.NormalId.Back, {
		{ Text = "RUINFALL", Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.62), Font = Enum.Font.Fondamento },
		{ Text = "Choose a gate to gather your war party", Position = UDim2.fromScale(0.1, 0.64), Size = UDim2.fromScale(0.8, 0.3), Font = Enum.Font.Merriweather, Color = Color3.fromRGB(230, 210, 180) },
	})
	-- class banners (rendered class emblems) along the side walls
	for index, classKey in ipairs(ClassDefinitions.Order) do
		local classDef = ClassDefinitions.Get(classKey)
		local side = index % 2 == 1 and -1 or 1
		local z = -26 + (index - 1) * 13
		local banner = part({ Name = "Banner_" .. classKey, Size = Vector3.new(0.3, 12, 6), Position = Vector3.new(side * (width / 2 - 0.4), y + 16, z), Color = classDef.Color:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Fabric })
		local gui = Instance.new("SurfaceGui")
		gui.Face = side < 0 and Enum.NormalId.Right or Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.Parent = banner
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = classDef.IconImage or ""
		image.Size = UDim2.fromScale(0.9, 0.45)
		image.Position = UDim2.fromScale(0.05, 0.12)
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = gui
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Text = string.upper(classDef.DisplayName)
		name.Font = Enum.Font.Fondamento
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(255, 225, 160)
		name.Size = UDim2.fromScale(0.9, 0.12)
		name.Position = UDim2.fromScale(0.05, 0.62)
		name.Parent = gui
		part({ Name = "BannerRod", Size = Vector3.new(0.5, 0.5, 7), Position = Vector3.new(side * (width / 2 - 0.6), y + 22.2, z), Color = Color3.fromRGB(200, 160, 70), Material = Enum.Material.Metal })
	end
	-- lobby gates along the back wall
	local gateX = { -42, -14, 14, 42 }
	for id = 1, LOBBY_COUNT do
		local x = gateX[id]
		local z = -depth / 2 + 3
		local color = LOBBY_COLORS[id]
		for _, side in ipairs({ -1, 1 }) do
			part({ Name = "GatePillar", Size = Vector3.new(3, 17, 3), Position = Vector3.new(x + side * 6, y + 8.5, z), Color = Color3.fromRGB(130, 122, 110), Material = Enum.Material.Limestone })
		end
		part({ Name = "GateLintel", Size = Vector3.new(15, 3, 3.4), Position = Vector3.new(x, y + 18.5, z), Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Limestone })
		local portal = part({ Name = "Portal", Size = Vector3.new(9, 15, 0.4), Position = Vector3.new(x, y + 7.5, z - 0.6), Color = color, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false })
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = 16
		glow.Brightness = 1.4
		glow.Parent = portal
		local sign = part({ Name = "GateSign", Size = Vector3.new(13, 5, 0.5), Position = Vector3.new(x, y + 12.5, z + 1.9), Color = Color3.fromRGB(56, 36, 22), Material = Enum.Material.Wood })
		local _, labels = surfaceText(sign, Enum.NormalId.Back, {
			{ Name = "Title", Text = LOBBY_NAMES[id], Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.36), Color = color },
			{ Name = "Sub", Text = LOBBY_TITLES[id], Position = UDim2.fromScale(0.1, 0.38), Size = UDim2.fromScale(0.8, 0.2), Font = Enum.Font.Merriweather, Color = Color3.fromRGB(230, 210, 180) },
			{ Name = "Status", Text = "", Position = UDim2.fromScale(0.05, 0.62), Size = UDim2.fromScale(0.9, 0.32), Font = Enum.Font.Merriweather },
		})
		local pedestal = part({ Name = "GatePedestal", Size = Vector3.new(3.4, 1.4, 3.4), Position = Vector3.new(x, y + 0.7, z + 7), Color = Color3.fromRGB(110, 102, 92), Material = Enum.Material.Limestone })
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "JoinPrompt"
		prompt.ActionText = "Join " .. LOBBY_NAMES[id]
		prompt.ObjectText = LOBBY_TITLES[id]
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal
		table.insert(connections, prompt.Triggered:Connect(function(player)
			HubService.Join(player, id)
		end))
		torch(Vector3.new(x - 8.5, y + 0.2, z + 3))
		torch(Vector3.new(x + 8.5, y + 0.2, z + 3))
		HubService.Lobbies[id].Sign = labels
		HubService.Lobbies[id].Prompt = prompt
	end
	-- spawn dais near the front of the hall, facing the gates
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HallSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 8)
	spawn.CFrame = CFrame.new(0, y + 0.5, depth / 2 - 10) -- default facing -Z (toward the gates)
	spawn.Color = Color3.fromRGB(150, 120, 60)
	spawn.Material = Enum.Material.Limestone
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hallFolder
end

-- Lobby state -------------------------------------------------------------------------
local function maxMembers()
	return Constants.MAX_PARTICIPANTS
end

local function findLobbyOf(player)
	for _, lobby in ipairs(HubService.Lobbies) do
		for index, member in ipairs(lobby.Members) do
			if member == player then
				return lobby, index
			end
		end
	end
	return nil
end

local function modeLabel(mode)
	return (Constants.TeamModeLabels and Constants.TeamModeLabels[mode]) or mode
end

local function snapshot()
	local lobbies = {}
	for _, lobby in ipairs(HubService.Lobbies) do
		local members = {}
		for _, member in ipairs(lobby.Members) do
			table.insert(members, { UserId = member.UserId, Name = member.DisplayName, IsHost = member == lobby.Host })
		end
		table.insert(lobbies, {
			Id = lobby.Id, Name = lobby.Name, Title = lobby.Title, Mode = lobby.Mode, ModeLabel = modeLabel(lobby.Mode),
			State = lobby.State, Members = members, Max = maxMembers(), Color = lobby.Color,
		})
	end
	local modes = {}
	for _, mode in ipairs(MODES) do
		table.insert(modes, { Key = mode, Label = modeLabel(mode) })
	end
	return { Lobbies = lobbies, Modes = modes, Studio = RunService:IsStudio() }
end

local function refreshSigns()
	for _, lobby in ipairs(HubService.Lobbies) do
		if lobby.Sign and lobby.Sign.Status then
			local state = lobby.State == "Launching" and "MARCHING OUT..." or string.format("%s  -  %d / %d", string.upper(modeLabel(lobby.Mode)), #lobby.Members, maxMembers())
			lobby.Sign.Status.Text = state
		end
	end
end

function HubService.Broadcast()
	if not active then
		return
	end
	refreshSigns()
	Net.Get("HubState"):FireAllClients("State", snapshot())
end

local function notice(player, text, style)
	if player and player.Parent then
		Net.Get("HubState"):FireClient(player, "Notice", { Text = text, Style = style or "Info" })
	end
end

local function noticeLobby(lobby, text, style)
	for _, member in ipairs(lobby.Members) do
		notice(member, text, style)
	end
end

function HubService.Leave(player, silent)
	local lobby, index = findLobbyOf(player)
	if not lobby then
		return false
	end
	table.remove(lobby.Members, index)
	if lobby.Host == player then
		lobby.Host = lobby.Members[1]
		if lobby.Host then
			notice(lobby.Host, "You are now the host of " .. lobby.Name, "Info")
		end
	end
	if #lobby.Members == 0 then
		lobby.State = "Open"
		lobby.Mode = DEFAULT_MODE
	end
	if not silent then
		notice(player, "You left " .. lobby.Name, "Info")
	end
	HubService.Broadcast()
	return true
end

function HubService.Join(player, lobbyId)
	local lobby = HubService.Lobbies[lobbyId]
	if not lobby then
		return false
	end
	local current = findLobbyOf(player)
	if current == lobby then
		notice(player, "You are already in " .. lobby.Name, "Info")
		return true
	end
	if lobby.State ~= "Open" then
		notice(player, lobby.Name .. " is marching out - pick another gate", "Warning")
		return false
	end
	if #lobby.Members >= maxMembers() then
		notice(player, lobby.Name .. " is full", "Warning")
		return false
	end
	if current then
		HubService.Leave(player, true)
	end
	table.insert(lobby.Members, player)
	if not lobby.Host then
		lobby.Host = player
	end
	notice(player, string.format("Joined %s%s", lobby.Name, lobby.Host == player and " - you are the host" or ""), "Success")
	HubService.Broadcast()
	return true
end

function HubService.SetMode(player, mode)
	local lobby = findLobbyOf(player)
	if not lobby or lobby.Host ~= player or lobby.State ~= "Open" then
		return false
	end
	if not table.find(MODES, mode) then
		return false
	end
	lobby.Mode = mode
	HubService.Broadcast()
	return true
end

local function reopen(lobby, message)
	if lobby.State == "Launching" then
		lobby.State = "Open"
		if message then
			noticeLobby(lobby, message, "Warning")
		end
		HubService.Broadcast()
	end
end

function HubService.Start(player)
	local lobby = findLobbyOf(player)
	if not lobby then
		return false
	end
	if lobby.Host ~= player then
		notice(player, "Only the lobby host can start", "Warning")
		return false
	end
	if lobby.State ~= "Open" then
		return false
	end
	lobby.State = "Launching"
	HubService.Broadcast()
	local members = table.clone(lobby.Members)
	if RunService:IsStudio() then
		-- Studio cannot teleport: run the match on this server instead
		noticeLobby(lobby, "Studio: starting the match on this server", "Info")
		task.delay(0.6, function()
			if onLocalStart then
				onLocalStart({ Mode = lobby.Mode, Name = lobby.Name, Host = lobby.Host, Members = members })
			end
		end)
		return true
	end
	noticeLobby(lobby, "Marching out - preparing your battlefield...", "Success")
	task.spawn(function()
		local ok, code = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if not ok or not code then
			warn("[Ruinfall] ReserveServer failed:", code)
			reopen(lobby, "Could not create a match server - try again")
			return
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ Mode = lobby.Mode, Lobby = lobby.Name, HostUserId = lobby.Host and lobby.Host.UserId or 0 })
		local online = {}
		for _, member in ipairs(members) do
			if member.Parent == Players then
				table.insert(online, member)
			end
		end
		local teleported, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, online, options)
		end)
		if not teleported then
			warn("[Ruinfall] Teleport failed:", err)
			reopen(lobby, "Teleport failed - try again")
			return
		end
		task.delay(LAUNCH_TIMEOUT, function()
			reopen(lobby, #lobby.Members > 0 and "Teleport timed out - try again" or nil)
		end)
	end)
	return true
end

local function handleRequest(player, action, value)
	if type(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_INTERVAL then
		return
	end
	lastRequest[player] = now
	if action == "Join" and type(value) == "number" then
		HubService.Join(player, math.floor(value))
	elseif action == "Leave" then
		HubService.Leave(player)
	elseif action == "SetMode" and type(value) == "string" then
		HubService.SetMode(player, value)
	elseif action == "Start" then
		HubService.Start(player)
	elseif action == "Sync" then
		Net.Get("HubState"):FireClient(player, "State", snapshot())
	end
end

-- Characters: whatever spawns them (default loading or the ForceR6Avatar script, which
-- parents a new model without positioning it), move every hub character onto the hall
-- spawn dais so nobody falls out of the floating hall.
local function placeInHall(character)
	task.defer(function()
		if not active or not hallFolder or not character.Parent then
			return
		end
		local spawn = hallFolder:FindFirstChild("HallSpawn")
		if spawn then
			character:PivotTo(spawn.CFrame * CFrame.new(math.random(-4, 4), 4, math.random(-2, 2)))
		end
	end)
end

local function trackPlayer(player)
	table.insert(connections, player.CharacterAdded:Connect(placeInHall))
	if player.Character then
		placeInHall(player.Character)
	end
	-- nothing spawned a character (no auto-load and no spawner script): load one
	task.delay(4, function()
		if active and player.Parent == Players and not player.Character then
			pcall(player.LoadCharacter, player)
		end
	end)
end

-- Public API ---------------------------------------------------------------------------
-- options.OnLocalStart(lobbyInfo): Studio-only fallback that turns this server into a match.
function HubService.Init(options)
	active = true
	onLocalStart = options and options.OnLocalStart
	for id = 1, LOBBY_COUNT do
		HubService.Lobbies[id] = { Id = id, Name = LOBBY_NAMES[id], Title = LOBBY_TITLES[id], Color = LOBBY_COLORS[id], Mode = DEFAULT_MODE, Members = {}, Host = nil, State = "Open" }
	end
	buildHall()
	local map = workspace:FindFirstChild("RuinfallMap")
	if map then
		parkedMap = map
		map.Parent = ServerStorage
	end
	Players.RespawnTime = 2
	for _, player in ipairs(Players:GetPlayers()) do
		trackPlayer(player)
	end
	table.insert(connections, Net.Get("HubRequest").OnServerEvent:Connect(handleRequest))
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		trackPlayer(player)
		task.wait(1)
		Net.Get("HubState"):FireClient(player, "State", snapshot())
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		HubService.Leave(player, true)
	end))
	table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		notice(player, "Teleport failed: " .. tostring(message), "Warning")
		local lobby = findLobbyOf(player)
		if lobby then
			reopen(lobby, nil)
		end
	end))
	HubService.Broadcast()
end

-- Removes the hall and hub characters (Studio fallback before the local match starts)
function HubService.Teardown()
	active = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	Players.CharacterAutoLoads = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			player.Character:Destroy()
			player.Character = nil
		end
	end
	if hallFolder then
		hallFolder:Destroy()
		hallFolder = nil
	end
	if parkedMap and parkedMap.Parent == ServerStorage then
		parkedMap.Parent = workspace
	end
	parkedMap = nil
end

-- Debug harness: start a local match immediately (Studio / tests)
function HubService.ForceLocalStart(mode)
	if not active or not onLocalStart then
		return false
	end
	onLocalStart({ Mode = mode or DEFAULT_MODE, Name = "DEBUG", Members = Players:GetPlayers() })
	return true
end

function HubService.IsActive()
	return active
end

return HubService
