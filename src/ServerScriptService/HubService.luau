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
local Net = require(script.Parent:WaitForChild("Net"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))

-- Constants
-- One gate per game mode. The CraterArena gate runs the classic team battle (2 / 4 / 6
-- teams, flags, classes, shop); the Shattered Expanse gate runs the 18-player free-for-all
-- battle royale (Constants.Royale). Each lobby only offers its own modes.
local LOBBIES = {
	{
		Name = "CRATER ARENA", Title = "The Crater Gate", Color = Color3.fromRGB(255, 150, 70),
		Modes = { "2Team", "4Team", "6Team" }, Default = "2Team",
		Blurb = "Team battle in the ancient crater - break enemy flags",
	},
	{
		Name = "SHATTERED EXPANSE", Title = "The Storm Gate", Color = Color3.fromRGB(185, 110, 255),
		Modes = { "Royale" }, Default = "Royale",
		Blurb = "18-player free for all - loot ruins, last one standing",
	},
}
local LOBBY_COUNT = #LOBBIES
local DEFAULT_MODE = "2Team"
local LAUNCH_TIMEOUT = 25 -- seconds before a stuck launch reopens the lobby
local REQUEST_INTERVAL = 0.25
local HALL_FLOOR_Y = 400 -- the hall floats high above the (unused) arena area
local MARBLE_A, MARBLE_B = Color3.fromRGB(196, 186, 170), Color3.fromRGB(88, 80, 74)
local GOLD = Color3.fromRGB(214, 170, 80)

-- State
local HubService = {}
HubService.Lobbies = {}
local hallFolder = nil
local onLocalStart = nil
local lastRequest = setmetatable({}, { __mode = "k" })
local connections = {}
local active = false
local parkedMap = nil -- the saved arena preview, hidden while the hub runs
local leaderboardLabels = {} -- [board key] = { Status = TextLabel, Rows = { TextLabel } }
local LEADERBOARD_REFRESH = 60

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

local function neon(properties)
	properties.Material = Enum.Material.Neon
	properties.CanCollide = false
	properties.CastShadow = false
	return part(properties)
end

-- a ring of blocks approximating an arch between two pillars (x0..x1 at height y, radius r)
-- alongZ: the arch spans the Z axis (windows in the side walls) instead of X
local function archOver(center, halfWidth, springY, thickness, depth, color, material, segments, alongZ)
	segments = segments or 9
	local blocks = {}
	local function point(a)
		local h, v = -math.cos(a) * halfWidth, math.sin(a) * halfWidth
		return alongZ and Vector3.new(0, v, h) or Vector3.new(h, v, 0)
	end
	for index = 0, segments - 1 do
		local a0 = math.pi * index / segments
		local a1 = math.pi * (index + 1) / segments
		local p0 = point(a0)
		local p1 = point(a1)
		local mid = (p0 + p1) / 2
		local length = (p1 - p0).Magnitude + 0.3
		local tangent = (p1 - p0).Unit
		local outward = mid.Unit -- from the arch centre through this stone
		local cf = CFrame.fromMatrix(center + Vector3.new(0, springY, 0) + mid, tangent, outward)
		table.insert(blocks, part({ Name = "ArchStone", Size = Vector3.new(length, thickness, depth), CFrame = cf, Color = color, Material = material or Enum.Material.Limestone }))
	end
	return blocks
end

local function chandelier(position)
	local metal = Color3.fromRGB(60, 50, 40)
	part({ Name = "Chain", Size = Vector3.new(0.3, 8, 0.3), Position = position + Vector3.new(0, 4.5, 0), Color = metal, Material = Enum.Material.Metal, CanCollide = false })
	part({ Name = "ChandelierRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 9, 9), CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), Color = metal, Material = Enum.Material.Metal, CanCollide = false })
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		local spot = position + Vector3.new(math.cos(angle) * 4.2, 0.6, math.sin(angle) * 4.2)
		part({ Name = "Candle", Size = Vector3.new(0.35, 0.9, 0.35), Position = spot, Color = Color3.fromRGB(240, 230, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		local flame = neon({ Name = "Flame", Size = Vector3.new(0.22, 0.4, 0.22), Position = spot + Vector3.new(0, 0.65, 0), Color = Color3.fromRGB(255, 190, 90) })
		if index % 2 == 0 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 110)
			light.Range = 22
			light.Brightness = 1.1
			light.Parent = flame
		end
	end
end

local function brazier(position, color)
	part({ Name = "BrazierFoot", Size = Vector3.new(2.6, 0.6, 2.6), Position = position + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(50, 44, 40), Material = Enum.Material.Metal })
	part({ Name = "BrazierStem", Size = Vector3.new(0.8, 3, 0.8), Position = position + Vector3.new(0, 2.1, 0), Color = Color3.fromRGB(50, 44, 40), Material = Enum.Material.Metal })
	local bowl = part({ Name = "BrazierBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 3.6, 3.6), CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Metal })
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 9
	fire.Color = color or Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = (color or Color3.fromRGB(255, 150, 50)):Lerp(Color3.new(1, 0.2, 0), 0.5)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Color = color or Color3.fromRGB(255, 170, 90)
	light.Range = 24
	light.Brightness = 1.8
	light.Shadows = true
	light.Parent = bowl
end

local function dustMotes(parent, color, rate)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new(0.15, 0.05)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(4, 8)
	emitter.Rate = rate or 12
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = parent
end

local function buildHall()
	hallFolder = Instance.new("Folder")
	hallFolder.Name = "RuinfallHall"
	hallFolder.Parent = workspace
	local y = HALL_FLOOR_Y
	local width, depth, height = 140, 110, 44
	local stone = Color3.fromRGB(104, 96, 88)
	local stoneDark = Color3.fromRGB(70, 64, 60)
	local backZ = -depth / 2

	-- Floor: chequered marble with a gold-inlaid mosaic compass in the middle ----------------
	part({ Name = "Floor", Size = Vector3.new(width, 2, depth), Position = Vector3.new(0, y - 1, 0), Color = stoneDark, Material = Enum.Material.Slate })
	local tile = 10
	for ix = 0, width / tile - 1 do
		for iz = 0, depth / tile - 1 do
			local x = -width / 2 + tile / 2 + ix * tile
			local z = -depth / 2 + tile / 2 + iz * tile
			part({ Name = "Tile", Size = Vector3.new(tile - 0.25, 0.1, tile - 0.25), Position = Vector3.new(x, y + 0.03, z), Color = (ix + iz) % 2 == 0 and MARBLE_A or MARBLE_B, Material = Enum.Material.Marble })
		end
	end
	local centerZ = 6
	-- one flat base disc, then gold ring outlines made of thin segments laid ON it (no stacked
	-- overlapping discs -> no flicker), then the compass rays on top
	part({ Name = "MosaicBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 42, 42), CFrame = CFrame.new(0, y + 0.1, centerZ) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(40, 34, 44), Material = Enum.Material.Marble })
	for _, r in ipairs({ 20, 15.5, 11 }) do
		local segments = 48
		for index = 1, segments do
			local a0, a1 = (index - 1) / segments * math.pi * 2, index / segments * math.pi * 2
			local p0 = Vector3.new(math.cos(a0) * r, y + 0.17, centerZ + math.sin(a0) * r)
			local p1 = Vector3.new(math.cos(a1) * r, y + 0.17, centerZ + math.sin(a1) * r)
			neon({ Name = "MosaicRing", Size = Vector3.new(0.5, 0.04, (p1 - p0).Magnitude + 0.05), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = GOLD, Transparency = 0.15 })
		end
	end
	for index = 0, 7 do -- compass star
		local long = index % 2 == 0 and 19 or 12
		part({ Name = "MosaicRay", Size = Vector3.new(index % 2 == 0 and 1.6 or 1, 0.05, long), CFrame = CFrame.new(0, y + 0.19, centerZ) * CFrame.Angles(0, math.rad(index * 45), 0) * CFrame.new(0, 0, -long / 2), Color = index % 2 == 0 and GOLD or Color3.fromRGB(150, 120, 190), Material = Enum.Material.Metal })
	end

	-- Walls: dressed stone with pilasters, a dado of dark stone and a cornice ------------------
	local function wall(name, size, position)
		part({ Name = name, Size = size, Position = position, Color = stone, Material = Enum.Material.Cobblestone })
	end
	wall("WallBack", Vector3.new(width, height, 3), Vector3.new(0, y + height / 2, backZ - 1.5))
	wall("WallFront", Vector3.new(width, height, 3), Vector3.new(0, y + height / 2, depth / 2 + 1.5))
	wall("WallLeft", Vector3.new(3, height, depth + 6), Vector3.new(-width / 2 - 1.5, y + height / 2, 0))
	wall("WallRight", Vector3.new(3, height, depth + 6), Vector3.new(width / 2 + 1.5, y + height / 2, 0))
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Dado", Size = Vector3.new(0.6, 5, depth), Position = Vector3.new(side * (width / 2 - 0.3), y + 2.5, 0), Color = stoneDark, Material = Enum.Material.Slate })
		part({ Name = "Cornice", Size = Vector3.new(2, 1.6, depth), Position = Vector3.new(side * (width / 2 - 1), y + height - 7, 0), Color = Color3.fromRGB(150, 140, 125), Material = Enum.Material.Limestone })
	end
	part({ Name = "DadoFront", Size = Vector3.new(width, 5, 0.6), Position = Vector3.new(0, y + 2.5, depth / 2 - 0.3), Color = stoneDark, Material = Enum.Material.Slate })

	-- Stained-glass windows along both side walls, casting coloured light -------------------
	local glass = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 110, 220), Color3.fromRGB(230, 180, 60), Color3.fromRGB(80, 170, 90), Color3.fromRGB(150, 80, 220) }
	for _, side in ipairs({ -1, 1 }) do
		for index, z in ipairs({ -32, -11, 10, 31 }) do
			local x = side * (width / 2 - 0.2)
			local color = glass[(index + (side > 0 and 2 or 0) - 1) % #glass + 1]
			local pane = part({ Name = "StainedGlass", Size = Vector3.new(0.3, 16, 7), Position = Vector3.new(x, y + 21, z), Color = color, Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false })
			pane.Reflectance = 0.1
			neon({ Name = "GlassGlow", Size = Vector3.new(0.2, 15, 6), Position = Vector3.new(x + side * 0.15, y + 21, z), Color = color, Transparency = 0.55 })
			part({ Name = "Mullion", Size = Vector3.new(0.5, 16, 0.4), Position = Vector3.new(x - side * 0.1, y + 21, z), Color = Color3.fromRGB(40, 36, 34), Material = Enum.Material.Metal, CanCollide = false })
			part({ Name = "Transom", Size = Vector3.new(0.5, 0.4, 7), Position = Vector3.new(x - side * 0.1, y + 24, z), Color = Color3.fromRGB(40, 36, 34), Material = Enum.Material.Metal, CanCollide = false })
			archOver(Vector3.new(x - side * 0.2, y, z), 3.9, 29, 1.2, 1.6, Color3.fromRGB(150, 140, 125), Enum.Material.Limestone, 7, true)
			for _, dz in ipairs({ -4.2, 4.2 }) do
				part({ Name = "Pilaster", Size = Vector3.new(1.4, height - 8, 2), Position = Vector3.new(side * (width / 2 - 0.7), y + (height - 8) / 2, z + dz), Color = Color3.fromRGB(135, 126, 112), Material = Enum.Material.Limestone })
			end
			local spot = Instance.new("SpotLight")
			spot.Color = color
			spot.Brightness = 3
			spot.Range = 40
			spot.Angle = 50
			spot.Face = side < 0 and Enum.NormalId.Right or Enum.NormalId.Left
			spot.Parent = pane
		end
	end

	-- Vaulted ceiling: ribbed arches across the hall + a skylight over the fountain ----------
	part({ Name = "Roof", Size = Vector3.new(width + 6, 2, depth + 6), Position = Vector3.new(0, y + height + 13, 0), Color = stoneDark, Material = Enum.Material.Slate })
	for z = backZ + 8, depth / 2 - 6, 16 do
		archOver(Vector3.new(0, y, z), width / 2, height - 6, 2, 2.4, Color3.fromRGB(120, 110, 98), Enum.Material.Limestone, 14)
	end
	part({ Name = "Ridge", Size = Vector3.new(2, 2, depth), Position = Vector3.new(0, y + height + 13.5 - 1.5, 0), Color = Color3.fromRGB(80, 56, 36), Material = Enum.Material.Wood })
	local shaft = neon({ Name = "Skylight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height + 12, 16, 16), CFrame = CFrame.new(0, y + (height + 12) / 2, centerZ) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 235, 190), Transparency = 0.93 })
	dustMotes(shaft, Color3.fromRGB(255, 230, 170), 18)
	for _, z in ipairs({ -26, centerZ + 20, 38 }) do
		for _, x in ipairs({ -30, 30 }) do
			chandelier(Vector3.new(x, y + height - 12, z))
		end
	end

	-- Colonnade with carved capitals -----------------------------------------------------------
	for _, x in ipairs({ -40, 40 }) do
		for _, z in ipairs({ -30, -10, 10, 30 }) do
			pillar(Vector3.new(x, y, z), height - 6)
			part({ Name = "Capital", Size = Vector3.new(6.5, 1.4, 6.5), Position = Vector3.new(x, y + height - 7.2, z), Color = GOLD, Material = Enum.Material.Metal })
			part({ Name = "PillarBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4.1, 4.1), CFrame = CFrame.new(x, y + 6, z) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Material = Enum.Material.Metal })
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -20, 0, 20 }) do
			torch(Vector3.new(side * (width / 2 - 2), y + 8, z))
		end
	end

	-- Centrepiece: fountain with a floating Ruinfall crystal ----------------------------------
	part({ Name = "FountainRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 20, 20), CFrame = CFrame.new(0, y + 1, centerZ) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(170, 160, 145), Material = Enum.Material.Marble })
	part({ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 17.6, 17.6), CFrame = CFrame.new(0, y + 1.8, centerZ) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 130, 170), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false })
	part({ Name = "FountainPlinth", Size = Vector3.new(4, 7, 4), Position = Vector3.new(0, y + 3.5, centerZ), Color = Color3.fromRGB(150, 140, 125), Material = Enum.Material.Marble })
	part({ Name = "PlinthCap", Size = Vector3.new(5.2, 0.8, 5.2), Position = Vector3.new(0, y + 7.2, centerZ), Color = GOLD, Material = Enum.Material.Metal })
	local crystal = neon({ Name = "HallCrystal", Size = Vector3.new(3, 6, 3), CFrame = CFrame.new(0, y + 13, centerZ) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(150, 110, 255), Transparency = 0.1 })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 130, 255)
	glow.Range = 34
	glow.Brightness = 2.2
	glow.Parent = crystal
	dustMotes(crystal, Color3.fromRGB(190, 160, 255), 20)
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2
		neon({ Name = "CrystalShard", Size = Vector3.new(0.8, 2, 0.8), CFrame = CFrame.new(math.cos(angle) * 4.5, y + 12 + (index % 2) * 1.5, centerZ + math.sin(angle) * 4.5) * CFrame.Angles(0.3, angle, 0.2), Color = Color3.fromRGB(200, 170, 255), Transparency = 0.15 })
	end
	for index = 1, 6 do -- water jets
		local angle = index / 6 * math.pi * 2
		local jet = part({ Name = "WaterJet", Size = Vector3.new(0.4, 0.4, 0.4), Position = Vector3.new(math.cos(angle) * 6.5, y + 2, centerZ + math.sin(angle) * 6.5), Transparency = 1, CanCollide = false })
		local spray = Instance.new("ParticleEmitter")
		spray.Color = ColorSequence.new(Color3.fromRGB(180, 220, 255))
		spray.Size = NumberSequence.new(0.35, 0.1)
		spray.Transparency = NumberSequence.new(0.3, 1)
		spray.Lifetime = NumberRange.new(0.8, 1.1)
		spray.Rate = 25
		spray.Speed = NumberRange.new(9, 11)
		spray.SpreadAngle = Vector2.new(6, 6)
		spray.Acceleration = Vector3.new(0, -22, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Parent = jet
	end

	-- Title board above the gates ---------------------------------------------------------------
	local title = part({ Name = "TitleBoard", Size = Vector3.new(64, 8, 0.6), Position = Vector3.new(0, y + 33, backZ + 0.4), Color = Color3.fromRGB(50, 32, 22), Material = Enum.Material.Wood })
	part({ Name = "TitleFrame", Size = Vector3.new(66, 9.6, 0.4), Position = Vector3.new(0, y + 33, backZ + 0.2), Color = GOLD, Material = Enum.Material.Metal })
	surfaceText(title, Enum.NormalId.Back, {
		{ Text = "RUINFALL", Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.62), Font = Enum.Font.Fondamento },
		{ Text = "Choose your battle", Position = UDim2.fromScale(0.1, 0.64), Size = UDim2.fromScale(0.8, 0.3), Font = Enum.Font.Merriweather, Color = Color3.fromRGB(230, 210, 180) },
	})

	-- Mode gates: grand arches on the back wall ------------------------------------------------
	local gateX = { -30, 30 }
	for id = 1, LOBBY_COUNT do
		local info = LOBBIES[id]
		local x = gateX[id]
		local z = backZ + 3
		local color = info.Color
		local base = Vector3.new(x, y, z)
		-- stepped dais
		part({ Name = "GateStep1", Size = Vector3.new(26, 0.6, 12), Position = Vector3.new(x, y + 0.3, z + 3), Color = Color3.fromRGB(150, 140, 125), Material = Enum.Material.Marble })
		part({ Name = "GateStep2", Size = Vector3.new(22, 0.6, 7), Position = Vector3.new(x, y + 0.9, z + 1), Color = Color3.fromRGB(165, 155, 140), Material = Enum.Material.Marble })
		for _, side in ipairs({ -1, 1 }) do
			part({ Name = "GatePillar", Size = Vector3.new(3.6, 20, 3.6), Position = Vector3.new(x + side * 9, y + 10.6, z), Color = Color3.fromRGB(138, 128, 114), Material = Enum.Material.Limestone })
			part({ Name = "GatePillarCap", Size = Vector3.new(4.6, 1.2, 4.6), Position = Vector3.new(x + side * 9, y + 21.2, z), Color = GOLD, Material = Enum.Material.Metal })
			part({ Name = "GatePillarBase", Size = Vector3.new(4.6, 1.2, 4.6), Position = Vector3.new(x + side * 9, y + 1.8, z), Color = GOLD, Material = Enum.Material.Metal })
		end
		archOver(base, 9, 21.6, 2.4, 3.8, Color3.fromRGB(130, 120, 106), Enum.Material.Limestone, 11)
		local keystone = neon({ Name = "Keystone", Size = Vector3.new(2.2, 2.6, 4.2), Position = Vector3.new(x, y + 31, z), Color = color, Transparency = 0.1 })
		local portal = part({ Name = "Portal", Size = Vector3.new(14, 20, 0.4), Position = Vector3.new(x, y + 11.2, z - 0.8), Color = color, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false })
		part({ Name = "PortalVoid", Size = Vector3.new(14.2, 20.2, 0.3), Position = Vector3.new(x, y + 11.2, z - 1.3), Color = Color3.fromRGB(10, 6, 16), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		local swirl = Instance.new("ParticleEmitter")
		swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		swirl.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		swirl.LightEmission = 1
		swirl.Size = NumberSequence.new(0.6, 0)
		swirl.Lifetime = NumberRange.new(1.5, 2.5)
		swirl.Rate = 30
		swirl.Speed = NumberRange.new(1, 3)
		swirl.RotSpeed = NumberRange.new(-90, 90)
		swirl.SpreadAngle = Vector2.new(60, 60)
		swirl.EmissionDirection = Enum.NormalId.Back
		swirl.Parent = portal
		local glowLight = Instance.new("PointLight")
		glowLight.Color = color
		glowLight.Range = 22
		glowLight.Brightness = 2
		glowLight.Parent = portal
		keystone:SetAttribute("Gate", id)
		-- glowing rods floating beside the portal (ember for the crater, storm for the expanse)
		local rodColor = id == 1 and Color3.fromRGB(255, 140, 60) or color
		for index = 1, 6 do
			local side = index % 2 == 0 and -1 or 1
			neon({ Name = "GateRod", Size = Vector3.new(0.9, 3, 0.9), CFrame = CFrame.new(x + side * (12.5 + index * 0.6), y + 5 + index * 2.4, z + 2) * CFrame.Angles(0.4 * side, index, 0.3), Color = rodColor, Transparency = 0.15 })
		end
		-- braziers stand on the floor OUTSIDE the stepped dais (the dais spans x +-13, z-3 .. z+9)
		brazier(Vector3.new(x - 16.5, y, z + 12), rodColor)
		brazier(Vector3.new(x + 16.5, y, z + 12), rodColor)
		-- carpet runner from the edge of the floor mosaic to the join pedestal
		local toGate = Vector3.new(x, 0, z + 14 - centerZ).Unit
		local runnerA = Vector3.new(toGate.X * 21.5, y + 0.12, centerZ + toGate.Z * 21.5)
		local runnerB = Vector3.new(x, y + 0.12, z + 14)
		part({ Name = "Runner", Size = Vector3.new(7, 0.1, (runnerB - runnerA).Magnitude), CFrame = CFrame.lookAt((runnerA + runnerB) / 2, runnerB), Color = color:Lerp(Color3.new(0.1, 0.05, 0.05), 0.55), Material = Enum.Material.Fabric, CanCollide = false })
		-- gate sign
		local sign = part({ Name = "GateSign", Size = Vector3.new(18, 6.4, 0.5), Position = Vector3.new(x, y + 25.5, z + 2.4), Color = Color3.fromRGB(46, 30, 20), Material = Enum.Material.Wood })
		part({ Name = "GateSignFrame", Size = Vector3.new(19, 7.4, 0.3), Position = Vector3.new(x, y + 25.5, z + 2.1), Color = GOLD, Material = Enum.Material.Metal })
		local _, labels = surfaceText(sign, Enum.NormalId.Back, {
			{ Name = "Title", Text = info.Name, Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.92, 0.36), Color = color },
			{ Name = "Sub", Text = info.Blurb, Position = UDim2.fromScale(0.06, 0.4), Size = UDim2.fromScale(0.88, 0.2), Font = Enum.Font.Merriweather, Color = Color3.fromRGB(230, 210, 180) },
			{ Name = "Status", Text = "", Position = UDim2.fromScale(0.04, 0.63), Size = UDim2.fromScale(0.92, 0.32), Font = Enum.Font.Merriweather },
		})
		-- the join pedestal sits on the floor just in front of the dais (not straddling a step)
		local pedestal = part({ Name = "GatePedestal", Size = Vector3.new(3.6, 3, 3.6), Position = Vector3.new(x, y + 1.5, z + 11.5), Color = Color3.fromRGB(150, 140, 125), Material = Enum.Material.Marble })
		neon({ Name = "PedestalRune", Size = Vector3.new(3.7, 0.3, 3.7), Position = Vector3.new(x, y + 2.8, z + 11.5), Color = color, Transparency = 0.3 })
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "JoinPrompt"
		prompt.ActionText = "Join " .. info.Name
		prompt.ObjectText = info.Title
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pedestal
		table.insert(connections, prompt.Triggered:Connect(function(player)
			HubService.Join(player, id)
		end))
		HubService.Lobbies[id].Sign = labels
		HubService.Lobbies[id].Prompt = prompt
	end

	-- Spawn dais near the front of the hall, facing the gates ---------------------------------
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HallSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1, 9)
	spawn.CFrame = CFrame.new(0, y + 0.5, depth / 2 - 11)
	spawn.Color = Color3.fromRGB(150, 120, 60)
	spawn.Material = Enum.Material.Marble
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hallFolder
	part({ Name = "SpawnTrim", Size = Vector3.new(15, 0.9, 10), Position = Vector3.new(0, y + 0.45, depth / 2 - 11), Color = GOLD, Material = Enum.Material.Metal })

	-- Hall of Fame: lifetime leaderboards on the front wall, facing the gates ----------------
	table.clear(leaderboardLabels)
	for index, board in ipairs(LeaderboardService.Boards) do
		local x = index == 1 and -32 or 32
		local accent = index == 1 and Color3.fromRGB(255, 120, 90) or Color3.fromRGB(150, 200, 255)
		local wallZ = depth / 2
		local panel = part({ Name = "Leaderboard_" .. board.Key, Size = Vector3.new(20, 24, 0.6), Position = Vector3.new(x, y + 15, wallZ - 0.9), Color = Color3.fromRGB(40, 26, 18), Material = Enum.Material.Wood })
		part({ Name = "LeaderboardFrame", Size = Vector3.new(21.6, 25.6, 0.4), Position = Vector3.new(x, y + 15, wallZ - 0.5), Color = GOLD, Material = Enum.Material.Metal })
		neon({ Name = "LeaderboardGlow", Size = Vector3.new(20, 0.3, 0.3), Position = Vector3.new(x, y + 27.4, wallZ - 1.3), Color = accent, Transparency = 0.2 })
		for _, side in ipairs({ -1, 1 }) do
			torch(Vector3.new(x + side * 12.5, y + 8, wallZ - 1.2))
		end
		local lines = {
			{ Name = "Title", Text = board.Title, Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.1), Color = accent },
			{ Name = "Status", Text = "Loading...", Position = UDim2.fromScale(0.05, 0.12), Size = UDim2.fromScale(0.9, 0.05), Font = Enum.Font.Merriweather, Color = Color3.fromRGB(200, 185, 160) },
		}
		for rank = 1, LeaderboardService.TOP_COUNT do
			table.insert(lines, { Name = "Row" .. rank, Text = "", Position = UDim2.fromScale(0.06, 0.19 + (rank - 1) * 0.078), Size = UDim2.fromScale(0.88, 0.066), Font = Enum.Font.Merriweather, Color = rank == 1 and GOLD or Color3.fromRGB(235, 220, 195) })
		end
		local _, labels = surfaceText(panel, Enum.NormalId.Front, lines)
		local rows = {}
		for rank = 1, LeaderboardService.TOP_COUNT do
			rows[rank] = labels["Row" .. rank]
			rows[rank].TextXAlignment = Enum.TextXAlignment.Left
		end
		leaderboardLabels[board.Key] = { Status = labels.Status, Rows = rows }
	end
end

local function refreshLeaderboards()
	for _, board in ipairs(LeaderboardService.Boards) do
		local target = leaderboardLabels[board.Key]
		if not target then
			continue
		end
		local rows = LeaderboardService.GetTop(board, LeaderboardService.TOP_COUNT)
		if not target.Status.Parent then
			return -- the hall was torn down while we were waiting
		end
		if not rows then
			target.Status.Text = "Leaderboard offline (publish the game / enable API access)"
		else
			target.Status.Text = #rows == 0 and "No legends yet - be the first!" or "All-time top " .. LeaderboardService.TOP_COUNT
		end
		for rank, label in ipairs(target.Rows) do
			local row = rows and rows[rank]
			label.Text = row and string.format("%d.  %s  -  %d", rank, row.Name, row.Value) or ""
		end
	end
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
			State = lobby.State, Members = members, Max = maxMembers(), Color = lobby.Color, Blurb = lobby.Blurb,
			Modes = (function()
				local list = {}
				for _, mode in ipairs(lobby.Modes) do
					table.insert(list, { Key = mode, Label = modeLabel(mode) })
				end
				return list
			end)(),
		})
	end
	-- Modes (top level) = the first lobby's modes, kept for older clients
	return { Lobbies = lobbies, Modes = lobbies[1] and lobbies[1].Modes or {}, Studio = RunService:IsStudio() }
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
		lobby.Mode = lobby.Default or DEFAULT_MODE
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
	if not table.find(lobby.Modes, mode) then
		return false -- each gate only offers its own game mode(s)
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
		local info = LOBBIES[id]
		HubService.Lobbies[id] = {
			Id = id, Name = info.Name, Title = info.Title, Color = info.Color, Blurb = info.Blurb,
			Modes = info.Modes, Default = info.Default, Mode = info.Default, Members = {}, Host = nil, State = "Open",
		}
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
	task.spawn(function()
		while active do
			refreshLeaderboards()
			local waited = 0
			while active and waited < LEADERBOARD_REFRESH do
				waited += task.wait(1)
			end
		end
	end)
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
