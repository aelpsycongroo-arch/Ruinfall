-- MapGenerator: seeded, rotationally symmetric procedural arenas.
-- Features are generated inside one sector and rotated for every base slot,
-- so every team gets an equivalent layout (balanced, never impossible).

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MapDefinitions = require(Shared:WaitForChild("MapDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local PropBuilder = require(script.Parent:WaitForChild("PropBuilder"))

-- Constants
local GEN = MapDefinitions.Generation
local PALETTE = MapDefinitions.Palette
local WALL_HEIGHT = Constants.Map.WALL_HEIGHT
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y

-- State
local MapGenerator = {}
MapGenerator.Current = nil

-- Functions
local function makePart(properties)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local parent = properties.Parent
	for key, value in pairs(properties) do
		if key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = parent
	return part
end

local function makeDecor(properties)
	properties.CanCollide = false
	properties.CanQuery = false
	properties.CanTouch = false
	return makePart(properties)
end

local function flatDisc(position, diameter, height, color, material, parent, transparency)
	return makeDecor({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * VERTICAL,
		Color = color,
		Material = material,
		Transparency = transparency or 0,
		CastShadow = false,
		Parent = parent,
	})
end

-- Ground + boundary -------------------------------------------------------------
local function buildGround(mapData, folders)
	local radius = mapData.Radius
	local outer = makePart({
		Name = "OuterGround",
		Size = Vector3.new(900, 2, 900),
		Position = Vector3.new(0, -1.1, 0),
		Color = Color3.fromRGB(95, 90, 110),
		Parent = folders.Ground,
	})
	if PropBuilder.HasAssets() then
		outer.Material = Enum.Material.Grass
		outer.Color = Color3.fromRGB(62, 86, 42)
	else
		PropBuilder.ApplyVariant(outer, "Stone")
	end
	local floor = makePart({
		Name = "ArenaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, radius * 2 + 10, radius * 2 + 10),
		CFrame = CFrame.new(0, -1, 0) * VERTICAL,
		Color = Color3.fromRGB(225, 220, 235),
		Parent = folders.Ground,
	})
	if PropBuilder.HasAssets() then
		-- stylised grass; colour variation comes from the ground decals (see buildGroundDressing)
		floor.Material = Enum.Material.Grass
		floor.Color = Color3.fromRGB(96, 128, 56)
	else
		PropBuilder.ApplyVariant(floor, "Ground")
	end
end

local function buildBoundary(mapData, folders)
	local radius = mapData.Radius
	local segments = mapData.BoundarySegments or GEN.BOUNDARY_SEGMENTS
	local height = GEN.BOUNDARY_HEIGHT
	local segmentLength = 2 * math.pi * (radius + 2) / segments + 1.5
	for index = 1, segments do
		local angle = (index - 0.5) * 2 * math.pi / segments
		local position = Util.RotateY(Vector3.new(0, 0, radius + 2), angle)
		local cframe = CFrame.lookAt(Vector3.new(position.X, height / 2, position.Z), Vector3.new(0, height / 2, 0))
		local wall = PropBuilder.Collider(folders.Blockers, "Boundary", Vector3.new(segmentLength, height, 4), cframe)
		wall:SetAttribute("Boundary", true)
		if not mapData.Crater then -- the crater rim replaces the loose cliff boulders
			PropBuilder.Cliff(folders.Decor, Util.RotateY(Vector3.new(0, 0, radius + 6), angle), mapData.DecorRandom)
		end
		if index % 4 == 0 then
			makeDecor({
				Name = "BoundaryCrystal",
				Size = Vector3.new(1.4, 3.5, 1.4),
				CFrame = cframe * CFrame.new(0, height / 2 + 1.2, 0) * CFrame.Angles(0, math.rad(45), math.rad(15)),
				Color = Color3.fromRGB(130, 90, 255),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = folders.Decor,
			})
		end
	end
end

-- Bases -------------------------------------------------------------------------
local function buildBases(mapData, folders, activeSet)
	local radius = mapData.Radius
	local ring = radius - GEN.BASE_RING_OFFSET
	local platformRadius = GEN.BASE_PLATFORM_RADIUS
	for slot = 1, mapData.SlotCount do
		local angle = (slot - 1) * mapData.SectorAngle
		local position = Util.RotateY(Vector3.new(0, 0, ring), angle)
		local active = activeSet[slot] == true
		local color = active and Constants.GetTeamColor(slot) or PALETTE.InactiveBase
		local toCenter = Util.FlatDirection(position, Vector3.zero)
		local base = {
			Slot = slot,
			Team = slot,
			Position = position,
			Angle = angle,
			Active = active,
			ToCenter = toCenter,
			SpawnPoints = {},
		}
		local baseFolder = Instance.new("Folder")
		baseFolder.Name = "Base" .. slot
		baseFolder.Parent = folders.Bases
		base.Folder = baseFolder

		if PropBuilder.Shrine(baseFolder, position, platformRadius, mapData.DecorRandom) then
			-- capture shrine: worn stone rings + a subtle team-colour glow at the rim and around the flag
			flatDisc(position + Vector3.new(0, -0.35, 0), platformRadius * 2 + 1.4, 0.6, color, Enum.Material.Neon, baseFolder, active and 0.55 or 0.92)
			flatDisc(position + Vector3.new(0, 0.33, 0), 9.4, 0.06, color, Enum.Material.Neon, baseFolder, active and 0.82 or 0.95)
			if active then
				for _, side in ipairs({ -1, 1 }) do
					local spot = position + Util.RotateY(toCenter, math.rad(side * 42)) * (platformRadius + 1.2)
					PropBuilder.Brazier(baseFolder, spot)
				end
			end
		else
			PropBuilder.ApplyVariant(flatDisc(position + Vector3.new(0, -0.3, 0), platformRadius * 2, 1, Color3.fromRGB(215, 210, 225):Lerp(color, active and 0.18 or 0.05), Enum.Material.Slate, baseFolder), "Cobble")
			flatDisc(position + Vector3.new(0, -0.4, 0), platformRadius * 2 + 1.6, 0.9, color, Enum.Material.Neon, baseFolder, active and 0.4 or 0.8)
			flatDisc(position + Vector3.new(0, 0.22, 0), 9, 0.1, color, Enum.Material.Neon, baseFolder, active and 0.8 or 0.9)
		end

		-- Defensive pillars (leave an entrance toward the arena center)
		for _, degrees in ipairs({ 65, 115, 180, 245, 295 }) do
			local direction = Util.RotateY(toCenter, math.rad(degrees))
			local pillarPosition = position + direction * (platformRadius - 1.8)
			local pillarHeight = active and 8 or 5
			local pillar = PropBuilder.Collider(folders.Blockers, "BasePillar", Vector3.new(2.4, pillarHeight, 2.4), CFrame.new(pillarPosition + Vector3.new(0, pillarHeight / 2, 0)))
			pillar:SetAttribute("MinimapShape", "Box")
			local inward = -direction
			PropBuilder.Column(baseFolder, pillarPosition, pillarHeight, {
				Broken = not active,
				Accent = active and color or nil,
				Random = mapData.DecorRandom,
				Facing = math.atan2(-inward.X, -inward.Z),
			})
		end

		-- Spawn points around the flag, on the side facing the arena
		for index = 1, 6 do
			local offsetAngle = math.rad(-55 + (index - 1) * 22)
			local direction = Util.RotateY(toCenter, offsetAngle)
			table.insert(base.SpawnPoints, position + direction * GEN.SPAWN_RING_RADIUS + Vector3.new(0, 0.2, 0))
		end
		if Constants.DEBUG_MODE then
			for _, spawnPoint in ipairs(base.SpawnPoints) do
				makeDecor({
					Name = "DebugSpawn",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(0.8, 0.8, 0.8),
					Position = spawnPoint + Vector3.new(0, 0.5, 0),
					Color = Color3.new(0, 1, 0),
					Material = Enum.Material.Neon,
					Parent = folders.Markers,
				})
			end
		end

		mapData.Bases[slot] = base
		table.insert(mapData.Reserved, { Position = position, Radius = GEN.BASE_RESERVED_RADIUS, Kind = "Base" })
	end
end

-- Lanes, center, camps ------------------------------------------------------------
local function buildLanes(mapData, folders)
	for _, base in ipairs(mapData.Bases) do
		local a = base.Position + base.ToCenter * (GEN.BASE_PLATFORM_RADIUS + 1)
		local b = Vector3.zero - base.ToCenter * GEN.CENTER_RESERVED_RADIUS
		local length = (b - a).Magnitude
		local middle = (a + b) / 2
		if not PropBuilder.Road(folders.Decor, a, b, GEN.LANE_WIDTH, mapData.DecorRandom) then
			local lane = makeDecor({
				Name = "Lane",
				Size = Vector3.new(GEN.LANE_WIDTH, 0.1, length),
				CFrame = CFrame.lookAt(Vector3.new(middle.X, 0.04, middle.Z), Vector3.new(b.X, 0.04, b.Z)),
				Color = Color3.fromRGB(205, 198, 210),
				CastShadow = false,
				Parent = folders.Decor,
			})
			PropBuilder.ApplyVariant(lane, "Cobble")
		end
		table.insert(mapData.Lanes, { A = a, B = b, Width = GEN.LANE_WIDTH })
	end
end

local function buildCenter(mapData, folders)
	if PropBuilder.Shrine(folders.Decor, Vector3.zero, GEN.CENTER_RESERVED_RADIUS, mapData.DecorRandom) then
		flatDisc(Vector3.new(0, 0.07, 0), 11, 0.1, Color3.fromRGB(150, 120, 200), Enum.Material.Neon, folders.Decor, 0.8)
	else
		PropBuilder.ApplyVariant(flatDisc(Vector3.new(0, 0.05, 0), GEN.CENTER_RESERVED_RADIUS * 2, 0.12, Color3.fromRGB(200, 190, 225), Enum.Material.Slate, folders.Decor), "Cobble")
		flatDisc(Vector3.new(0, 0.07, 0), 12, 0.12, Color3.fromRGB(140, 100, 255), Enum.Material.Neon, folders.Decor, 0.6)
	end
	PropBuilder.ApplyVariant(flatDisc(Vector3.new(0, 0.09, 0), 9, 0.12, Color3.fromRGB(235, 225, 210), Enum.Material.Slate, folders.Decor), "Ruin")
	table.insert(mapData.Reserved, { Position = Vector3.zero, Radius = GEN.CENTER_RESERVED_RADIUS, Kind = "Center" })
end

local function placeCamp(mapData, folders, rng, index, position, angle)
	local campFolder = Instance.new("Folder")
	campFolder.Name = "Camp" .. index
	campFolder.Parent = folders.Camps
	local dirt = PropBuilder.GroundDecal(campFolder, "Ground_Dirt_A", position, 24, mapData.DecorRandom)
	if not dirt then
		flatDisc(position + Vector3.new(0, 0.05, 0), 22, 0.12, PALETTE.Camp, Enum.Material.Ground, campFolder)
	end
	for rockIndex = 1, 7 do
		local rockAngle = (rockIndex / 7) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local rockPosition = position + Util.RotateY(Vector3.new(0, 0, 10.5), rockAngle)
		local size = rng:NextNumber(1.4, 2.4)
		if not PropBuilder.Asset(rockIndex % 3 == 0 and "Rock_Flat" or "Rock_Small", campFolder, CFrame.new(rockPosition) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), size * 0.7) then
			PropBuilder.Piece(campFolder, "Stone", Vector3.new(size, size, size), CFrame.new(rockPosition + Vector3.new(0, size * 0.3, 0)), Color3.fromRGB(190, 180, 170), Enum.PartType.Ball)
		end
	end
	table.insert(mapData.Camps, { Id = "Camp" .. index, Position = position, Angle = angle, Folder = campFolder })
	table.insert(mapData.Reserved, { Position = position, Radius = GEN.CAMP_RESERVED_RADIUS, Kind = "Camp" })
end

local function buildCamps(mapData, folders, rng)
	local campCount = math.max(mapData.SlotCount, GEN.MIN_CAMPS)
	local campRadius = mapData.Radius * GEN.CAMP_RING_FACTOR
	for index = 1, campCount do
		local angle = (index - 0.5) * 2 * math.pi / campCount
		local position = Util.RotateY(Vector3.new(0, 0, campRadius), angle)
		placeCamp(mapData, folders, rng, index, position, angle)
	end
end

-- Spatial validation ---------------------------------------------------------------
local function segmentIsClear(mapData, a, b, halfThickness)
	local limit = mapData.Radius - 12
	if Util.Flat(a).Magnitude > limit or Util.Flat(b).Magnitude > limit then
		return false
	end
	for _, reserved in ipairs(mapData.Reserved) do
		if Util.PointSegmentDistance2D(reserved.Position, a, b) < reserved.Radius + halfThickness + 3 then
			return false
		end
	end
	for _, lane in ipairs(mapData.Lanes) do
		if Util.SegmentDistance2D(a, b, lane.A, lane.B) < lane.Width / 2 + halfThickness + 3 then
			return false
		end
	end
	for _, wall in ipairs(mapData.Walls) do
		if Util.SegmentDistance2D(a, b, wall.A, wall.B) < GEN.WALL_SPACING + halfThickness * 2 then
			return false
		end
	end
	for _, rock in ipairs(mapData.Rocks) do
		if Util.PointSegmentDistance2D(rock.Position, a, b) < rock.Radius + halfThickness + GEN.WALL_SPACING then
			return false
		end
	end
	return true
end

local function circleIsClear(mapData, position, radius, spacing)
	if Util.Flat(position).Magnitude > mapData.Radius - 12 - radius then
		return false
	end
	for _, reserved in ipairs(mapData.Reserved) do
		if Util.FlatDistance(reserved.Position, position) < reserved.Radius + radius + 2 then
			return false
		end
	end
	for _, lane in ipairs(mapData.Lanes) do
		if Util.PointSegmentDistance2D(position, lane.A, lane.B) < lane.Width / 2 + radius + 1 then
			return false
		end
	end
	for _, wall in ipairs(mapData.Walls) do
		if Util.PointSegmentDistance2D(position, wall.A, wall.B) < radius + wall.Thickness / 2 + spacing then
			return false
		end
	end
	for _, rock in ipairs(mapData.Rocks) do
		if Util.FlatDistance(rock.Position, position) < rock.Radius + radius + spacing then
			return false
		end
	end
	return true
end

-- Walls -------------------------------------------------------------------------------
local function buildWallPart(folders, a, b, rng)
	PropBuilder.Wall(folders.Blockers, folders.Decor, a, b, WALL_HEIGHT, GEN.WALL_THICKNESS, rng)
end

local function buildWalls(mapData, folders, rng)
	local slotCount = mapData.SlotCount
	local half = GEN.WALL_THICKNESS / 2
	local perSector = math.ceil(GEN.TOTAL_WALLS / slotCount)
	local placed, attempts = 0, 0
	while placed < perSector and attempts < 400 do
		attempts += 1
		local distance = rng:NextNumber(28, mapData.Radius - 22)
		local theta = rng:NextNumber(0, mapData.SectorAngle)
		local center = Util.RotateY(Vector3.new(0, 0, distance), theta)
		local length = rng:NextNumber(GEN.WALL_MIN_LENGTH, GEN.WALL_MAX_LENGTH)
		local orientation = rng:NextNumber(0, math.pi)
		local direction = Vector3.new(math.cos(orientation), 0, math.sin(orientation))
		local a = center - direction * length / 2
		local b = center + direction * length / 2
		local pieces = { { a, b } }
		if rng:NextNumber() < 0.35 then
			local perpendicular = Vector3.new(-direction.Z, 0, direction.X) * (rng:NextNumber() < 0.5 and 1 or -1)
			table.insert(pieces, { b, b + perpendicular * rng:NextNumber(8, 14) })
		end

		-- Validate every rotated copy against the map and against each other
		local accepted = {}
		local valid = true
		for copyIndex = 0, slotCount - 1 do
			local rotation = copyIndex * mapData.SectorAngle
			local rotated = {}
			for _, piece in ipairs(pieces) do
				local ra, rb = Util.RotateY(piece[1], rotation), Util.RotateY(piece[2], rotation)
				if not segmentIsClear(mapData, ra, rb, half) then
					valid = false
					break
				end
				for _, other in ipairs(accepted) do
					if Util.SegmentDistance2D(ra, rb, other[1], other[2]) < GEN.WALL_SPACING + half * 2 then
						valid = false
						break
					end
				end
				if not valid then
					break
				end
				table.insert(rotated, { ra, rb })
			end
			if not valid then
				break
			end
			for _, segment in ipairs(rotated) do
				table.insert(accepted, segment)
			end
		end

		if valid then
			for _, segment in ipairs(accepted) do
				table.insert(mapData.Walls, { A = segment[1], B = segment[2], Thickness = GEN.WALL_THICKNESS })
				buildWallPart(folders, segment[1], segment[2], mapData.DecorRandom)
			end
			placed += 1
		end
	end
end

local function buildRocks(mapData, folders, rng)
	local slotCount = mapData.SlotCount
	local perSector = math.ceil(GEN.TOTAL_ROCKS / slotCount)
	local placed, attempts = 0, 0
	while placed < perSector and attempts < 300 do
		attempts += 1
		local rockRadius = rng:NextNumber(2.5, 4.5)
		local distance = rng:NextNumber(24, mapData.Radius - 18)
		local theta = rng:NextNumber(0, mapData.SectorAngle)
		local position = Util.RotateY(Vector3.new(0, 0, distance), theta)
		local copies = {}
		local valid = true
		for copyIndex = 0, slotCount - 1 do
			local rotated = Util.RotateY(position, copyIndex * mapData.SectorAngle)
			if not circleIsClear(mapData, rotated, rockRadius, 6) then
				valid = false
				break
			end
			for _, other in ipairs(copies) do
				if Util.FlatDistance(other, rotated) < rockRadius * 2 + 6 then
					valid = false
					break
				end
			end
			if not valid then
				break
			end
			table.insert(copies, rotated)
		end
		if valid then
			local height = rng:NextNumber(5, 8)
			local spin = rng:NextNumber(0, math.pi * 2)
			for _, rockPosition in ipairs(copies) do
				table.insert(mapData.Rocks, { Position = rockPosition, Radius = rockRadius })
				local rock = PropBuilder.Collider(folders.Blockers, "Rock", Vector3.new(height, rockRadius * 2, rockRadius * 2), CFrame.new(rockPosition + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, spin, 0) * VERTICAL, Enum.PartType.Cylinder)
				rock:SetAttribute("MinimapShape", "Circle")
				PropBuilder.Boulder(folders.Decor, rockPosition, rockRadius, mapData.DecorRandom)
			end
			placed += 1
		end
	end
end

-- Brush ---------------------------------------------------------------------------------
local function brushIsClear(mapData, position, halfDiagonal)
	if Util.Flat(position).Magnitude > mapData.Radius - 10 - halfDiagonal then
		return false
	end
	for _, reserved in ipairs(mapData.Reserved) do
		local clearance = reserved.Kind == "Base" and reserved.Radius or 10
		if Util.FlatDistance(reserved.Position, position) < clearance + halfDiagonal then
			return false
		end
	end
	for _, wall in ipairs(mapData.Walls) do
		if Util.PointSegmentDistance2D(position, wall.A, wall.B) < halfDiagonal + wall.Thickness / 2 + 1 then
			return false
		end
	end
	for _, rock in ipairs(mapData.Rocks) do
		if Util.FlatDistance(rock.Position, position) < rock.Radius + halfDiagonal + 1 then
			return false
		end
	end
	for _, zone in ipairs(mapData.BrushZones) do
		if Util.FlatDistance(zone.CFrame.Position, position) < zone.HalfDiagonal + halfDiagonal + 3 then
			return false
		end
	end
	return true
end

local function buildBrush(mapData, folders, rng)
	local slotCount = mapData.SlotCount
	local perSector = math.ceil(GEN.TOTAL_BRUSH / slotCount)
	local placed, attempts = 0, 0
	while placed < perSector and attempts < 300 do
		attempts += 1
		local width = rng:NextNumber(GEN.BRUSH_MIN_SIZE, GEN.BRUSH_MAX_SIZE)
		local depth = rng:NextNumber(GEN.BRUSH_MIN_SIZE, GEN.BRUSH_MAX_SIZE)
		local halfDiagonal = math.sqrt(width * width + depth * depth) / 2
		local distance = rng:NextNumber(20, mapData.Radius - 16)
		local theta = rng:NextNumber(0, mapData.SectorAngle)
		local yaw = rng:NextNumber(0, math.pi)
		local position = Util.RotateY(Vector3.new(0, 0, distance), theta)
		local copies = {}
		local valid = true
		for copyIndex = 0, slotCount - 1 do
			local rotated = Util.RotateY(position, copyIndex * mapData.SectorAngle)
			if not brushIsClear(mapData, rotated, halfDiagonal) then
				valid = false
				break
			end
			for _, other in ipairs(copies) do
				if Util.FlatDistance(other.Position, rotated) < halfDiagonal * 2 + 3 then
					valid = false
					break
				end
			end
			if not valid then
				break
			end
			table.insert(copies, { Position = rotated, Yaw = yaw + copyIndex * mapData.SectorAngle })
		end
		if valid then
			for _, copy in ipairs(copies) do
				local height = GEN.BRUSH_HEIGHT
				local cframe = CFrame.new(copy.Position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, copy.Yaw, 0)
				local size = Vector3.new(width, height, depth)
				local _, brush = PropBuilder.Bush(folders.Brush, cframe, size, mapData.DecorRandom)
				table.insert(mapData.BrushZones, { CFrame = cframe, Size = size, Part = brush, HalfDiagonal = halfDiagonal })
			end
			placed += 1
		end
	end
end

-- Soft dirt / darker / lighter grass decals + sparse plants so the grass never reads as a flat plane
local function buildGroundDressing(mapData, folders, rng)
	if not PropBuilder.HasAssets() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "GroundDressing"
	folder.Parent = folders.Decor
	local kinds = { "Ground_GrassDark", "Ground_GrassDark", "Ground_Dirt_A", "Ground_Dirt_B" }
	for _ = 1, 45 do
		local position = Util.RotateY(Vector3.new(0, 0, math.sqrt(rng:NextNumber()) * (mapData.Radius - 6)), rng:NextNumber(0, math.pi * 2))
		PropBuilder.GroundDecal(folder, kinds[rng:NextInteger(1, #kinds)], position, rng:NextNumber(10, 22), rng)
	end
	-- worn dirt beside the roads
	for _, lane in ipairs(mapData.Lanes) do
		for t = 0.1, 0.9, 0.2 do
			local p = lane.A:Lerp(lane.B, t + rng:NextNumber(-0.05, 0.05))
			local side = Vector3.new(-(lane.B - lane.A).Unit.Z, 0, (lane.B - lane.A).Unit.X) * (rng:NextNumber() < 0.5 and -1 or 1)
			PropBuilder.GroundDecal(folder, rng:NextNumber() < 0.5 and "Ground_Dirt_A" or "Ground_Dirt_B", p + side * rng:NextNumber(5, 7), rng:NextNumber(7, 11), rng)
		end
	end
	for _ = 1, 70 do
		local position = Util.RotateY(Vector3.new(0, 0, rng:NextNumber(18, mapData.Radius - 8)), rng:NextNumber(0, math.pi * 2))
		if circleIsClear(mapData, position, 1, 0.5) then
			PropBuilder.ScatterSmall(folder, position, 1.2, rng, rng:NextInteger(1, 3), true)
		end
	end
end

local function buildDecor(mapData, folders, rng)
	if PropBuilder.HasAssets() then
		for _ = 1, 26 do
			local position = Util.RotateY(Vector3.new(0, 0, rng:NextNumber(20, mapData.Radius - 8)), rng:NextNumber(0, math.pi * 2))
			if circleIsClear(mapData, position, 1.5, 1) then
				local name = ({ "Rock_Small", "Rock_Small", "Rock_Flat", "Bush_Small" })[rng:NextInteger(1, 4)]
				PropBuilder.Asset(name, folders.Decor, CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.3))
			end
		end
		buildGroundDressing(mapData, folders, rng)
		return
	end
	for _ = 1, 40 do
		local position = Util.RotateY(Vector3.new(0, 0, rng:NextNumber(20, mapData.Radius - 8)), rng:NextNumber(0, math.pi * 2))
		if circleIsClear(mapData, position, 1, 1) then
			local size = rng:NextNumber(0.8, 1.6)
			if rng:NextNumber() < 0.35 then
				PropBuilder.Piece(folders.Decor, "Leaves", Vector3.new(size * 1.3, size * 1.3, size * 1.3), CFrame.new(position + Vector3.new(0, size * 0.3, 0)), Color3.fromRGB(165, 215, 150), Enum.PartType.Ball)
			else
				PropBuilder.Piece(folders.Decor, "Stone", Vector3.new(size, size, size), CFrame.new(position + Vector3.new(0, size * 0.2, 0)), Color3.fromRGB(190, 185, 200), Enum.PartType.Ball)
			end
		end
	end
end

-- CraterArena: the arena sits in the floor of an ancient impact crater ------------------
-- Purely cosmetic and entirely OUTSIDE the play area / on the floor as flat paint:
-- the layout (walls, rocks, brush, camps, ruin spots) is untouched. Uses its own Random
-- so the seeded layout and prop variation stay exactly the same as before.
local CRATER = {
	RimStart = 4, -- rim slope starts this far outside the arena edge
	RimDepth = 64,
	RimHeight = 40,
	Segments = 72,
	Plateau = 150, -- flat crater lip beyond the slope
	Rock = Color3.fromRGB(92, 78, 66),
	RockDark = Color3.fromRGB(58, 48, 42),
	Scorch = Color3.fromRGB(46, 36, 30),
	Ember = Color3.fromRGB(255, 120, 40),
}

local function buildCrater(mapData, folders)
	local radius = mapData.Radius
	local rng = Random.new(mapData.Seed + 313)
	local folder = Instance.new("Folder")
	folder.Name = "Crater"
	folder.Parent = folders.Decor
	-- the sloped rim: wedges whose low edge faces the arena (inner slope of the crater)
	local segments = CRATER.Segments
	local midRadius = radius + CRATER.RimStart + CRATER.RimDepth / 2
	local width = 2 * math.pi * (radius + CRATER.RimStart + CRATER.RimDepth) / segments + 2
	for index = 1, segments do
		local angle = (index - 0.5) * 2 * math.pi / segments
		local height = CRATER.RimHeight * rng:NextNumber(0.85, 1.12)
		local center = Util.RotateY(Vector3.new(0, 0, midRadius), angle)
		local wedge = Instance.new("WedgePart")
		wedge.Name = "CraterRim"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.Size = Vector3.new(width, height, CRATER.RimDepth)
		-- front (-Z, the low edge) points at the arena centre; the tall back faces outward
		wedge.CFrame = CFrame.lookAt(Vector3.new(center.X, height / 2 - 0.6, center.Z), Vector3.new(0, height / 2 - 0.6, 0))
		wedge.Color = CRATER.Rock:Lerp(CRATER.RockDark, rng:NextNumber(0, 0.6))
		wedge.Material = Enum.Material.Basalt
		wedge.Parent = folder
		-- crater lip beyond the slope
		local lip = makeDecor({
			Name = "CraterLip",
			Size = Vector3.new(width * (radius + CRATER.RimStart + CRATER.RimDepth + CRATER.Plateau / 2) / (radius + CRATER.RimStart + CRATER.RimDepth), 4, CRATER.Plateau),
			CFrame = CFrame.lookAt(Vector3.new(0, 0, 0), Util.RotateY(Vector3.new(0, 0, 1), angle)) * CFrame.new(0, height - 2.6, -(radius + CRATER.RimStart + CRATER.RimDepth + CRATER.Plateau / 2 - 1)),
			Color = CRATER.RockDark:Lerp(CRATER.Rock, rng:NextNumber(0, 0.5)),
			Material = Enum.Material.Rock,
			Parent = folder,
		})
		lip.CastShadow = true
		-- jagged spires along the lip
		if index % 3 == 0 then
			local spireHeight = rng:NextNumber(10, 22)
			local base = Util.RotateY(Vector3.new(0, 0, radius + CRATER.RimStart + CRATER.RimDepth + rng:NextNumber(2, 16)), angle + rng:NextNumber(-0.03, 0.03))
			makeDecor({
				Name = "RimSpire",
				Size = Vector3.new(rng:NextNumber(5, 9), spireHeight, rng:NextNumber(5, 9)),
				CFrame = CFrame.new(base + Vector3.new(0, height + spireHeight / 2 - 3, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6.28), rng:NextNumber(-0.25, 0.25)),
				Color = CRATER.RockDark,
				Material = Enum.Material.Slate,
				Parent = folder,
			})
		end
		-- glowing ember veins running down the rim slope
		if index % 4 == 1 then
			local top = Util.RotateY(Vector3.new(0, 0, radius + CRATER.RimStart + CRATER.RimDepth - 4), angle)
			local bottom = Util.RotateY(Vector3.new(0, 0, radius + CRATER.RimStart + 6), angle + rng:NextNumber(-0.02, 0.02))
			local topY, bottomY = height - 4, 1.2
			local a = Vector3.new(top.X, topY, top.Z)
			local b = Vector3.new(bottom.X, bottomY, bottom.Z)
			makeDecor({
				Name = "EmberVein",
				Size = Vector3.new(0.6, 0.25, (b - a).Magnitude),
				CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, 0.2, 0),
				Color = CRATER.Ember,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CastShadow = false,
				Parent = folder,
			})
		end
		-- fallen boulders on the slope
		if rng:NextNumber() < 0.55 then
			local d = rng:NextNumber(10, CRATER.RimDepth - 12)
			local spot = Util.RotateY(Vector3.new(0, 0, radius + CRATER.RimStart + d), angle + rng:NextNumber(-0.04, 0.04))
			local y = height * (d / CRATER.RimDepth)
			local size = rng:NextNumber(4, 9)
			makeDecor({
				Name = "RimBoulder",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = spot + Vector3.new(0, y + size * 0.1, 0),
				Color = CRATER.RockDark:Lerp(CRATER.Rock, rng:NextNumber()),
				Material = Enum.Material.Basalt,
				Parent = folder,
			})
		end
	end
	-- the crater floor: scorched rings darkening toward the impact centre (thin paint layers)
	for index, ring in ipairs({ { 1.0, 0.86 }, { 0.72, 0.82 }, { 0.44, 0.76 }, { 0.2, 0.7 } }) do
		flatDisc(Vector3.new(0, 0.012 + index * 0.004, 0), radius * 2 * ring[1], 0.02, CRATER.Scorch, Enum.Material.Ground, folder, ring[2])
	end
	-- a shock-ring near the rim foot
	flatDisc(Vector3.new(0, 0.03, 0), (radius + 3) * 2, 0.02, CRATER.RockDark, Enum.Material.Rock, folder, 0.35)
	-- glowing impact cracks radiating from the centre (flat, under everything)
	for index = 1, 14 do
		local angle = (index / 14) * 2 * math.pi + rng:NextNumber(-0.12, 0.12)
		local r0 = GEN.CENTER_RESERVED_RADIUS + rng:NextNumber(0, 6)
		local length = rng:NextNumber(radius * 0.18, radius * 0.42)
		local points = { Util.RotateY(Vector3.new(0, 0, r0), angle) }
		for step = 1, 4 do
			points[step + 1] = Util.RotateY(Vector3.new(0, 0, r0 + length * step / 4), angle + rng:NextNumber(-0.09, 0.09))
		end
		for step = 1, 4 do
			local a, b = points[step], points[step + 1]
			local mid = (a + b) / 2
			makeDecor({
				Name = "ImpactCrack",
				Size = Vector3.new(0.45 * (1 - step * 0.18) + 0.1, 0.04, (b - a).Magnitude + 0.4),
				CFrame = CFrame.lookAt(Vector3.new(mid.X, 0.06, mid.Z), Vector3.new(b.X, 0.06, b.Z)),
				Color = CRATER.Ember,
				Material = Enum.Material.Neon,
				Transparency = 0.35 + step * 0.12,
				CastShadow = false,
				Parent = folder,
			})
		end
	end
	-- smouldering vents on the rim slope (particles, outside the play area)
	for index = 1, 10 do
		local angle = (index / 10) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local spot = Util.RotateY(Vector3.new(0, 0, radius + CRATER.RimStart + 16), angle)
		local vent = makeDecor({ Name = "SmokeVent", Size = Vector3.new(2, 0.5, 2), Position = spot + Vector3.new(0, CRATER.RimHeight * 16 / CRATER.RimDepth, 0), Transparency = 1, Parent = folder })
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(70, 60, 55)
		smoke.Opacity = 0.18
		smoke.RiseVelocity = 3
		smoke.Size = 6
		smoke.Parent = vent
	end
end

-- Public API ---------------------------------------------------------------------------
function MapGenerator.Clear()
	local existing = workspace:FindFirstChild("RuinfallMap")
	if existing then
		existing:Destroy()
	end
	MapGenerator.Current = nil
end

function MapGenerator.Generate(seed, slotCount, activeTeams)
	MapGenerator.Clear()
	local rng = Random.new(seed)
	local activeSet = {}
	for _, team in ipairs(activeTeams) do
		activeSet[team] = true
	end

	local root = Instance.new("Folder")
	root.Name = "RuinfallMap"
	local folders = {}
	for _, name in ipairs({ "Ground", "Blockers", "Brush", "Bases", "Camps", "Decor", "Markers" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end

	local mapData = {
		Seed = seed,
		Radius = Constants.Map.RADIUS,
		SlotCount = slotCount,
		SectorAngle = 2 * math.pi / slotCount,
		Folder = root,
		Folders = folders,
		Blockers = folders.Blockers,
		Bases = {},
		Camps = {},
		BrushZones = {},
		Walls = {},
		Rocks = {},
		Lanes = {},
		Reserved = {},
		DecorRandom = Random.new(seed + 99), -- cosmetic only, never affects layout
		MapName = "CraterArena",
		Crater = true,
	}

	buildGround(mapData, folders)
	buildBoundary(mapData, folders)
	buildBases(mapData, folders, activeSet)
	buildLanes(mapData, folders)
	buildCenter(mapData, folders)
	buildCamps(mapData, folders, rng)
	buildWalls(mapData, folders, rng)
	buildRocks(mapData, folders, rng)
	buildBrush(mapData, folders, rng)
	buildDecor(mapData, folders, rng)
	buildCrater(mapData, folders)

	root.Parent = workspace
	workspace:SetAttribute("MapName", mapData.MapName)
	workspace:SetAttribute("ArenaRadius", mapData.Radius)
	workspace:SetAttribute("MatchSeed", seed)
	MapGenerator.Current = mapData
	return mapData
end

-- Royale: "The Shattered Expanse" - one huge free-for-all map with no bases or lanes.
-- Walls, rocks, brush and monster camps are scattered over the whole disc (no rotational
-- symmetry: landing spots are chosen by the players themselves).
function MapGenerator.GenerateRoyale(seed)
	MapGenerator.Clear()
	local rng = Random.new(seed)
	local root = Instance.new("Folder")
	root.Name = "RuinfallMap"
	local folders = {}
	for _, name in ipairs({ "Ground", "Blockers", "Brush", "Bases", "Camps", "Decor", "Markers" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end
	local mapData = {
		Seed = seed,
		Radius = Constants.Royale.MAP_RADIUS,
		SlotCount = 1,
		SectorAngle = 2 * math.pi,
		Folder = root,
		Folders = folders,
		Blockers = folders.Blockers,
		Bases = {},
		Camps = {},
		BrushZones = {},
		Walls = {},
		Rocks = {},
		Lanes = {},
		Reserved = {},
		DecorRandom = Random.new(seed + 99),
		BoundarySegments = 110,
		MapName = "ShatteredExpanse",
		Royale = true,
	}
	buildGround(mapData, folders)
	buildBoundary(mapData, folders)
	buildCenter(mapData, folders)
	-- monster camps spread over the whole map
	local campIndex, attempts = 0, 0
	while campIndex < 16 and attempts < 600 do
		attempts += 1
		local position = Util.RotateY(Vector3.new(0, 0, rng:NextNumber(60, mapData.Radius - 40)), rng:NextNumber(0, math.pi * 2))
		local ok = true
		for _, camp in ipairs(mapData.Camps) do
			if Util.FlatDistance(camp.Position, position) < 110 then
				ok = false
				break
			end
		end
		if ok and circleIsClear(mapData, position, GEN.CAMP_RESERVED_RADIUS, 4) then
			campIndex += 1
			placeCamp(mapData, folders, rng, campIndex, position, math.atan2(position.X, position.Z))
		end
	end
	for _ = 1, 5 do
		buildWalls(mapData, folders, rng)
	end
	for _ = 1, 5 do
		buildRocks(mapData, folders, rng)
	end
	for _ = 1, 6 do
		buildBrush(mapData, folders, rng)
	end
	buildDecor(mapData, folders, rng)
	-- ruined watchtowers as landmarks (decor only, sit on rocks-free ground)
	local drng = mapData.DecorRandom
	for _ = 1, 18 do
		local position = Util.RotateY(Vector3.new(0, 0, drng:NextNumber(40, mapData.Radius - 30)), drng:NextNumber(0, math.pi * 2))
		if circleIsClear(mapData, position, 4, 2) then
			PropBuilder.Column(folders.Decor, position, drng:NextNumber(9, 16), { Broken = drng:NextNumber() < 0.7, Random = drng })
		end
	end
	root.Parent = workspace
	workspace:SetAttribute("MapName", mapData.MapName)
	workspace:SetAttribute("ArenaRadius", mapData.Radius)
	workspace:SetAttribute("MatchSeed", seed)
	MapGenerator.Current = mapData
	return mapData
end

-- Royale landing spots: inside the map, not inside walls / rocks / camps.
function MapGenerator.IsSpawnClear(position)
	local mapData = MapGenerator.Current
	if not mapData then
		return false
	end
	return circleIsClear(mapData, position, 3, 1)
end

function MapGenerator.GetBrushZoneIndex(position)
	local mapData = MapGenerator.Current
	if not mapData then
		return nil
	end
	for index, zone in ipairs(mapData.BrushZones) do
		if Util.PointInBox2D(position, zone.CFrame, zone.Size) then
			return index
		end
	end
	return nil
end

-- Finds a valid ruin location: not in walls, bases, camps, brush or near other ruins.
-- center / maxRadius (optional): search inside that circle instead (Royale play zone).
function MapGenerator.FindRuinLocation(rng, existingPositions, center, maxRadius)
	local mapData = MapGenerator.Current
	if not mapData then
		return nil
	end
	center = center and Vector3.new(center.X, 0, center.Z) or Vector3.zero
	maxRadius = math.min(maxRadius or math.huge, mapData.Radius - 28)
	for _ = 1, 100 do
		local position = center + Util.RotateY(Vector3.new(0, 0, rng:NextNumber(0, math.max(1, maxRadius))), rng:NextNumber(0, math.pi * 2))
		if Util.Flat(position).Magnitude > mapData.Radius - 28 then
			position = Util.Flat(position).Unit * (mapData.Radius - 28)
		end
		local valid = true
		for _, base in ipairs(mapData.Bases) do
			if Util.FlatDistance(position, base.Position) < GEN.RUIN_MIN_BASE_DISTANCE then
				valid = false
				break
			end
		end
		if valid then
			for _, camp in ipairs(mapData.Camps) do
				if Util.FlatDistance(position, camp.Position) < GEN.RUIN_MIN_CAMP_DISTANCE then
					valid = false
					break
				end
			end
		end
		if valid then
			for _, wall in ipairs(mapData.Walls) do
				if Util.PointSegmentDistance2D(position, wall.A, wall.B) < GEN.RUIN_WALL_CLEARANCE + wall.Thickness / 2 then
					valid = false
					break
				end
			end
		end
		if valid then
			for _, rock in ipairs(mapData.Rocks) do
				if Util.FlatDistance(position, rock.Position) < rock.Radius + GEN.RUIN_WALL_CLEARANCE then
					valid = false
					break
				end
			end
		end
		if valid then
			for _, zone in ipairs(mapData.BrushZones) do
				if Util.FlatDistance(position, zone.CFrame.Position) < zone.HalfDiagonal + 6 then
					valid = false
					break
				end
			end
		end
		if valid then
			for _, other in ipairs(existingPositions or {}) do
				if Util.FlatDistance(position, other) < GEN.RUIN_MIN_RUIN_DISTANCE then
					valid = false
					break
				end
			end
		end
		if valid then
			return position
		end
	end
	return nil
end

return MapGenerator
