-- PropBuilder: organic, textured map props built from primitives and the
-- Blender-baked MaterialVariants (MaterialService.RF_*). Gameplay collision
-- always lives on a single invisible collider; everything visual is
-- non-colliding decoration so line of sight and pathing stay predictable.

-- Services
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")

-- Constants
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local SIDEWAYS = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z
local VARIANTS = {
	Stone = { Name = "RF_StoneWall", Base = Enum.Material.Rock },
	Ruin = { Name = "RF_RuinStone", Base = Enum.Material.Sandstone },
	Ground = { Name = "RF_Ground", Base = Enum.Material.Slate },
	Cobble = { Name = "RF_Cobble", Base = Enum.Material.Cobblestone },
	Leaves = { Name = "RF_Leaves", Base = Enum.Material.LeafyGrass },
}
local STONE_TINT = Color3.fromRGB(215, 210, 225)
local RUIN_TINT = Color3.fromRGB(235, 225, 210)

-- State
local PropBuilder = {}
PropBuilder.Variants = VARIANTS

-- Functions
function PropBuilder.ApplyVariant(part, kind)
	local variant = VARIANTS[kind]
	if not variant then
		return part
	end
	part.Material = variant.Base
	if MaterialService:FindFirstChild(variant.Name) then
		part.MaterialVariant = variant.Name
	end
	return part
end

-- Non-colliding visual piece
function PropBuilder.Piece(parent, kind, size, cframe, color, shape, extra)
	local part = Instance.new(extra and extra.ClassName or "Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color or STONE_TINT
	if kind == "Neon" then
		part.Material = Enum.Material.Neon
		part.CastShadow = false
	else
		PropBuilder.ApplyVariant(part, kind)
	end
	if extra then
		for key, value in pairs(extra) do
			if key ~= "ClassName" then
				part[key] = value
			end
		end
	end
	part.Parent = parent
	return part
end

-- Invisible gameplay collider (blocks movement, projectiles and line of sight)
function PropBuilder.Collider(parent, name, size, cframe, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Transparency = 1
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function tint(base, rng, amount)
	local k = 1 - rng:NextNumber(0, amount)
	return Color3.new(base.R * k, base.G * k, base.B * k)
end

-- Stacked-stone wall along segment a -> b ----------------------------------------------
function PropBuilder.Wall(blockers, decor, a, b, height, thickness, rng)
	local middle = (a + b) / 2
	local length = (b - a).Magnitude + thickness
	local frame = CFrame.lookAt(Vector3.new(middle.X, 0, middle.Z), Vector3.new(b.X, 0, b.Z))
	local collider = PropBuilder.Collider(blockers, "Wall", Vector3.new(thickness, height, length), frame * CFrame.new(0, height / 2, 0))
	collider:SetAttribute("MinimapShape", "Box")

	local model = Instance.new("Model")
	model.Name = "StoneWall"
	local courses = { 3.6, 3.4, 3.0 }
	local y = 0
	for courseIndex, courseHeight in ipairs(courses) do
		local z = -length / 2 + (courseIndex % 2 == 0 and rng:NextNumber(0.8, 1.8) or 0)
		local inset = (courseIndex - 1) * 0.12
		if courseIndex % 2 == 0 then
			local first = z + length / 2
			PropBuilder.Piece(model, "Stone", Vector3.new(thickness - inset, courseHeight, first), frame * CFrame.new(0, y + courseHeight / 2, -length / 2 + first / 2), tint(STONE_TINT, rng, 0.18))
		end
		while z < length / 2 - 0.3 do
			local blockLength = math.min(rng:NextNumber(3.2, 5.6), length / 2 - z)
			local blockHeight = courseHeight * rng:NextNumber(0.92, 1.03)
			if courseIndex == #courses then
				blockHeight = courseHeight * rng:NextNumber(0.7, 1.0)
			end
			local wobble = CFrame.Angles(rng:NextNumber(-0.03, 0.03), rng:NextNumber(-0.05, 0.05), rng:NextNumber(-0.03, 0.03))
			local depth = (thickness - inset) * rng:NextNumber(0.94, 1.1)
			PropBuilder.Piece(model, "Stone", Vector3.new(depth, blockHeight, blockLength - 0.12), frame * CFrame.new(rng:NextNumber(-0.12, 0.12), y + blockHeight / 2, z + blockLength / 2) * wobble, tint(STONE_TINT, rng, 0.22))
			z += blockLength
		end
		y += courseHeight
	end
	-- Moss clumps on top and rubble at the foot
	for _ = 1, math.max(1, math.floor(length / 9)) do
		local size = rng:NextNumber(1.4, 2.6)
		PropBuilder.Piece(model, "Leaves", Vector3.new(size, size, size), frame * CFrame.new(rng:NextNumber(-0.6, 0.6), height - 0.2, rng:NextNumber(-length / 2 + 1, length / 2 - 1)), Color3.fromRGB(170, 215, 150), Enum.PartType.Ball)
	end
	for _ = 1, rng:NextInteger(2, 3) do
		local size = rng:NextNumber(1.2, 2.4)
		local side = rng:NextNumber() < 0.5 and -1 or 1
		PropBuilder.Piece(model, "Stone", Vector3.new(size, size, size), frame * CFrame.new(side * (thickness / 2 + size * 0.3), size * 0.25, rng:NextNumber(-length / 2, length / 2)), tint(STONE_TINT, rng, 0.3), Enum.PartType.Ball)
	end
	model.Parent = decor
	return collider, model
end

-- Classical column (defensive pillars, ruin columns) --------------------------------------
function PropBuilder.Column(parent, position, height, options)
	options = options or {}
	local kind = options.Kind or "Stone"
	local color = options.Color or (kind == "Ruin" and RUIN_TINT or STONE_TINT)
	local rng = options.Random or Random.new()
	local model = Instance.new("Model")
	model.Name = "Column"
	local base = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	PropBuilder.Piece(model, kind, Vector3.new(3.2, 0.7, 3.2), base * CFrame.new(0, 0.35, 0), color)
	PropBuilder.Piece(model, kind, Vector3.new(0.5, 2.9, 2.9), base * CFrame.new(0, 0.95, 0) * VERTICAL, color, Enum.PartType.Cylinder)
	local shaftHeight = height - 2.3
	if options.Broken then
		shaftHeight = height * rng:NextNumber(0.35, 0.6)
	end
	PropBuilder.Piece(model, kind, Vector3.new(shaftHeight, 2.15, 2.15), base * CFrame.new(0, 1.2 + shaftHeight / 2, 0) * VERTICAL, color, Enum.PartType.Cylinder)
	-- fluting ridges
	for index = 0, 5 do
		local angle = index * math.pi / 3
		PropBuilder.Piece(model, kind, Vector3.new(0.35, shaftHeight - 0.4, 0.35), base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 1.2 + shaftHeight / 2, 1.02), color:Lerp(Color3.new(0, 0, 0), 0.08))
	end
	local top = 1.2 + shaftHeight
	if options.Broken then
		for index = 1, 3 do
			local shard = rng:NextNumber(0.6, 1.3)
			PropBuilder.Piece(model, kind, Vector3.new(0.9, shard, 1.1), base * CFrame.Angles(0, index * 2.1, 0) * CFrame.new(0, top + shard / 2 - 0.1, 0.5) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), color, nil, { ClassName = "WedgePart" })
		end
		local drum = rng:NextNumber(1.4, 2.2)
		PropBuilder.Piece(model, kind, Vector3.new(drum, 2.1, 2.1), base * CFrame.new(rng:NextNumber(2.2, 3), 1.05, rng:NextNumber(-1, 1)) * SIDEWAYS * CFrame.Angles(rng:NextNumber(0, 1), 0, 0), color, Enum.PartType.Cylinder)
	else
		PropBuilder.Piece(model, kind, Vector3.new(0.5, 2.8, 2.8), base * CFrame.new(0, top + 0.25, 0) * VERTICAL, color, Enum.PartType.Cylinder)
		PropBuilder.Piece(model, kind, Vector3.new(3.1, 0.6, 3.1), base * CFrame.new(0, top + 0.8, 0), color)
		if options.Accent then
			PropBuilder.Piece(model, "Neon", Vector3.new(0.3, 2.3, 2.3), base * CFrame.new(0, 1.2 + shaftHeight * 0.62, 0) * VERTICAL, options.Accent, Enum.PartType.Cylinder)
			local orb = PropBuilder.Piece(model, "Neon", Vector3.new(1.1, 1.1, 1.1), base * CFrame.new(0, top + 1.7, 0), options.Accent, Enum.PartType.Ball)
			orb.Transparency = 0.1
		end
	end
	model.Parent = parent
	return model
end

-- Boulder cluster ----------------------------------------------------------------------------
function PropBuilder.Boulder(parent, position, radius, rng, color)
	local model = Instance.new("Model")
	model.Name = "Boulder"
	color = color or STONE_TINT
	local main = radius * 2.1
	PropBuilder.Piece(model, "Stone", Vector3.new(main, main, main), CFrame.new(position + Vector3.new(0, radius * 0.45, 0)), tint(color, rng, 0.15), Enum.PartType.Ball)
	for _ = 1, rng:NextInteger(2, 4) do
		local size = radius * rng:NextNumber(0.9, 1.4)
		local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * radius * rng:NextNumber(0.5, 0.9)
		PropBuilder.Piece(model, "Stone", Vector3.new(size, size, size), CFrame.new(position + offset + Vector3.new(0, size * 0.25, 0)), tint(color, rng, 0.25), Enum.PartType.Ball)
	end
	if rng:NextNumber() < 0.6 then
		local moss = radius * 0.9
		PropBuilder.Piece(model, "Leaves", Vector3.new(moss, moss * 0.6, moss), CFrame.new(position + Vector3.new(0, radius * 1.35, 0)), Color3.fromRGB(165, 210, 140), Enum.PartType.Ball)
	end
	model.Parent = parent
	return model
end

-- Leafy bush patch (brush zone) ---------------------------------------------------------------
function PropBuilder.Bush(parent, cframe, size, rng)
	local model = Instance.new("Model")
	model.Name = "Bush"
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Size = size
	zone.CFrame = cframe
	zone.Parent = model
	model.PrimaryPart = zone
	local count = math.clamp(math.floor(size.X * size.Z / 11), 6, 18)
	for index = 1, count do
		local diameter = rng:NextNumber(3.4, 5.2)
		local x = rng:NextNumber(-size.X / 2 + diameter * 0.35, size.X / 2 - diameter * 0.35)
		local z = rng:NextNumber(-size.Z / 2 + diameter * 0.35, size.Z / 2 - diameter * 0.35)
		local green = Color3.fromRGB(rng:NextInteger(150, 205), rng:NextInteger(215, 255), rng:NextInteger(150, 200))
		local leaf = PropBuilder.Piece(model, "Leaves", Vector3.new(diameter, diameter, diameter), cframe * CFrame.new(x, -size.Y / 2 + diameter * 0.32, z), green, Enum.PartType.Ball)
		leaf.Name = "Leaf" .. index
		leaf.CastShadow = false
	end
	for _ = 1, rng:NextInteger(1, 4) do
		local flower = PropBuilder.Piece(model, "Neon", Vector3.new(0.45, 0.45, 0.45), cframe * CFrame.new(rng:NextNumber(-size.X / 2 + 1, size.X / 2 - 1), size.Y / 2 + 0.6, rng:NextNumber(-size.Z / 2 + 1, size.Z / 2 - 1)), ({ Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 220, 90), Color3.fromRGB(170, 120, 255) })[rng:NextInteger(1, 3)], Enum.PartType.Ball)
		flower.Name = "Flower"
	end
	CollectionService:AddTag(model, "RF_Bush")
	model.Parent = parent
	return model, zone
end

-- Cliff boulders behind the arena boundary ---------------------------------------------------
function PropBuilder.Cliff(parent, position, rng)
	local model = Instance.new("Model")
	model.Name = "Cliff"
	local dark = Color3.fromRGB(130, 125, 145)
	for _ = 1, 2 do
		local size = rng:NextNumber(8, 13)
		local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		PropBuilder.Piece(model, "Stone", Vector3.new(size, size, size), CFrame.new(position + offset + Vector3.new(0, size * 0.28, 0)), tint(dark, rng, 0.2), Enum.PartType.Ball)
	end
	model.Parent = parent
	return model
end

-- Ancient ruin (destructible objective) -------------------------------------------------------
function PropBuilder.Ruin(parent, position, runeColor, rng)
	local model = Instance.new("Model")
	model.Name = "Ruin"
	local floor = PropBuilder.Piece(model, "Cobble", Vector3.new(0.8, 14, 14), CFrame.new(position + Vector3.new(0, 0.2, 0)) * VERTICAL, Color3.fromRGB(205, 190, 170), Enum.PartType.Cylinder)
	floor.Name = "Platform"
	PropBuilder.Piece(model, "Neon", Vector3.new(0.12, 11.5, 11.5), CFrame.new(position + Vector3.new(0, 0.62, 0)) * VERTICAL, runeColor, Enum.PartType.Cylinder, { Transparency = 0.55 })
	for index = 1, 3 do
		local angle = (index - 1) * (2 * math.pi / 3) + rng:NextNumber(-0.3, 0.3)
		local columnPosition = position + Vector3.new(math.sin(angle) * 5.2, 0.6, math.cos(angle) * 5.2)
		PropBuilder.Column(model, columnPosition, rng:NextNumber(6, 8.5), { Kind = "Ruin", Broken = rng:NextNumber() < 0.7, Random = rng })
	end
	-- Tapered obelisk: stacked, alternately rotated carved blocks + pyramid cap
	local y = 0.6
	local root = nil
	local widths = { 3.4, 2.7, 2.3, 2.0, 1.75 }
	local heights = { 1.1, 1.8, 1.8, 1.7, 1.5 }
	for index, width in ipairs(widths) do
		local h = heights[index]
		local twist = CFrame.Angles(0, index % 2 == 0 and math.rad(45) or 0, 0)
		local block = PropBuilder.Piece(model, "Ruin", Vector3.new(width, h, width), CFrame.new(position + Vector3.new(0, y + h / 2, 0)) * twist, RUIN_TINT)
		if index == 2 then
			block.Name = "Obelisk"
			block.CanCollide = true
			block.Size = Vector3.new(width, h, width)
			root = block
		else
			block.CanCollide = index == 1
		end
		y += h
		if index >= 2 then
			PropBuilder.Piece(model, "Neon", Vector3.new(0.14, width + 0.1, width + 0.1), CFrame.new(position + Vector3.new(0, y - 0.05, 0)) * twist * VERTICAL, runeColor, Enum.PartType.Cylinder, { Transparency = 0.25 })
		end
	end
	local capWidth = 1.75
	for side = 0, 3 do
		PropBuilder.Piece(model, "Ruin", Vector3.new(capWidth, 1.6, capWidth / 2), CFrame.new(position + Vector3.new(0, y + 0.8, 0)) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -capWidth / 4), RUIN_TINT, nil, { ClassName = "WedgePart" })
	end
	local crystal = PropBuilder.Piece(model, "Neon", Vector3.new(1.3, 1.3, 1.3), CFrame.new(position + Vector3.new(0, y + 3, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), runeColor)
	crystal.Name = "Crystal"
	local light = Instance.new("PointLight")
	light.Color = runeColor
	light.Range = 16
	light.Brightness = 1.4
	light.Parent = crystal
	model.PrimaryPart = root
	model.Parent = parent
	return model, root
end

----------------------------------------------------------------------------------------------
-- Blender mesh library (ServerStorage.RuinfallAssets). When present, these builders replace the
-- primitive versions above; the primitive versions remain as a fallback.
----------------------------------------------------------------------------------------------
local ServerStorage = game:GetService("ServerStorage")
local Library = ServerStorage:FindFirstChild("RuinfallAssets")
local Legacy = {
	Wall = PropBuilder.Wall,
	Column = PropBuilder.Column,
	Boulder = PropBuilder.Boulder,
	Bush = PropBuilder.Bush,
	Cliff = PropBuilder.Cliff,
}
local WARM_FIRE = Color3.fromRGB(255, 150, 60)

function PropBuilder.HasAssets()
	return Library ~= nil and Library:FindFirstChild("Wall_Straight") ~= nil
end

-- Clone a library mesh. `cframe` is the ground contact point (bottom centre).
-- `scale` is a number (uniform) or Vector3 (per axis, applied to the mesh's own size).
function PropBuilder.Asset(name, parent, cframe, scale)
	local source = Library and Library:FindFirstChild(name)
	if not source then
		return nil
	end
	local part = source:Clone()
	local size = source.Size
	if typeof(scale) == "Vector3" then
		size = Vector3.new(size.X * scale.X, size.Y * scale.Y, size.Z * scale.Z)
	elseif type(scale) == "number" then
		size = size * scale
	end
	part.Size = size
	part.CFrame = cframe * CFrame.new(0, size.Y / 2, 0)
	part.Parent = parent
	return part
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local function scatterSmall(parent, position, radius, rng, count, allowFlowers)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * rng:NextNumber(0.75, 1.15)
		local spot = position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local name
		if allowFlowers and rng:NextNumber() < 0.3 then
			name = pick(rng, { "Flowers_White", "Flowers_Yellow", "Flowers_Pink", "Flowers_White", "Flowers_Blue" })
		else
			name = rng:NextNumber() < 0.5 and "Grass_Clump_A" or "Grass_Clump_B"
		end
		PropBuilder.Asset(name, parent, CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.2))
	end
end
PropBuilder.ScatterSmall = scatterSmall

function PropBuilder.Wall(blockers, decor, a, b, height, thickness, rng)
	if not PropBuilder.HasAssets() then
		return Legacy.Wall(blockers, decor, a, b, height, thickness, rng)
	end
	local middle = (a + b) / 2
	local length = (b - a).Magnitude + thickness
	local frame = CFrame.lookAt(Vector3.new(middle.X, 0, middle.Z), Vector3.new(b.X, 0, b.Z))
	local collider = PropBuilder.Collider(blockers, "Wall", Vector3.new(thickness, height, length), frame * CFrame.new(0, height / 2, 0))
	collider:SetAttribute("MinimapShape", "Box")
	local model = Instance.new("Model")
	model.Name = "RuinWall"
	local modules = math.max(1, math.floor(length / 11 + 0.5))
	local moduleLength = length / modules
	for index = 1, modules do
		local z = -length / 2 + moduleLength * (index - 0.5)
		local name
		if modules > 1 and (index == 1 or index == modules) and rng:NextNumber() < 0.35 then
			name = "Wall_End"
		else
			name = rng:NextNumber() < 0.3 and "Wall_Broken" or "Wall_Straight"
		end
		local source = Library[name]
		local flip = (name == "Wall_End" and index == 1) and math.pi or 0
		local yaw = math.pi / 2 + flip + (rng:NextNumber() < 0.5 and math.pi or 0) * (name == "Wall_End" and 0 or 1)
		local scale = Vector3.new(moduleLength * 1.06 / source.Size.X, height * 0.9 / source.Size.Y, thickness / 3)
		PropBuilder.Asset(name, model, frame * CFrame.new(0, 0, z) * CFrame.Angles(0, yaw, 0), scale)
		if rng:NextNumber() < 0.35 then
			local side = rng:NextNumber() < 0.5 and -1 or 1
			PropBuilder.Asset("Vines_Hanging", model, frame * CFrame.new(side * (thickness / 2 + 0.12), height * 0.9 - 3.2, z) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(moduleLength / 7.5 * 0.8, 1, 1))
		end
	end
	for _ = 1, math.max(2, modules * 2) do
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local spot = frame * CFrame.new(side * (thickness / 2 + rng:NextNumber(0.8, 2.2)), 0, rng:NextNumber(-length / 2, length / 2))
		local name = rng:NextNumber() < 0.75 and (rng:NextNumber() < 0.5 and "Grass_Clump_A" or "Grass_Clump_B") or "Flowers_White"
		PropBuilder.Asset(name, model, spot * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.3))
	end
	model.Parent = decor
	return collider, model
end

function PropBuilder.Column(parent, position, height, options)
	options = options or {}
	if not PropBuilder.HasAssets() or options.Kind == "Ruin" then
		return Legacy.Column(parent, position, height, options)
	end
	local rng = options.Random or Random.new()
	local model = Instance.new("Model")
	model.Name = "Column"
	local yaw = options.Facing or rng:NextNumber(0, math.pi * 2)
	local ground = CFrame.new(position.X, 0, position.Z) * CFrame.Angles(0, yaw, 0)
	if options.Broken then
		local name = rng:NextNumber() < 0.5 and "Pillar_Broken" or "Pillar_Ruined"
		PropBuilder.Asset(name, model, ground, height / Library[name].Size.Y * (name == "Pillar_Ruined" and 1.2 or 1))
	else
		local name = options.Accent and "Pillar_With_Banner" or "Pillar_Tall"
		local scale = height / Library[name].Size.Y * 1.1
		local pillar = PropBuilder.Asset(name, model, ground, scale)
		if options.Accent and pillar then
			local half = pillar.Size.Z / 2
			local banner = PropBuilder.Asset("Banner_Cloth", model, ground * CFrame.new(0, pillar.Size.Y * 0.42, -(half * 0.72 + 0.2)), scale * 0.95)
			if banner then
				local appearance = banner:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					appearance.Color = options.Accent:Lerp(Color3.new(0.25, 0.22, 0.22), 0.25)
				end
				banner.Name = "Banner"
			end
		end
	end
	scatterSmall(model, position, 2.2, rng, 3, true)
	model.Parent = parent
	return model
end

function PropBuilder.Boulder(parent, position, radius, rng, color)
	if not PropBuilder.HasAssets() then
		return Legacy.Boulder(parent, position, radius, rng, color)
	end
	local model = Instance.new("Model")
	model.Name = "Boulder"
	local name = pick(rng, { "Rock_Large", "Rock_Mossy", "Rock_Medium", "Rock_Broken", "Rock_Large" })
	local source = Library[name]
	local footprint = math.max(source.Size.X, source.Size.Z)
	local scale = radius * 2.3 / footprint
	local rock = PropBuilder.Asset(name, model, CFrame.new(position.X, -0.2, position.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(scale, scale * rng:NextNumber(1.1, 1.5), scale))
	if rng:NextNumber() < 0.7 then
		PropBuilder.Asset("Rock_Small", model, CFrame.new(position + Vector3.new(radius * 1.1, 0, rng:NextNumber(-radius, radius))) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.4))
	end
	scatterSmall(model, position, radius * 1.15, rng, rng:NextInteger(2, 4), true)
	model.Parent = parent
	return model, rock
end

function PropBuilder.Bush(parent, cframe, size, rng)
	if not PropBuilder.HasAssets() then
		return Legacy.Bush(parent, cframe, size, rng)
	end
	local model = Instance.new("Model")
	model.Name = "Bush"
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Size = size
	zone.CFrame = cframe
	zone.Parent = model
	model.PrimaryPart = zone
	local ground = cframe * CFrame.new(0, -size.Y / 2, 0)
	local step = 4.6
	local nx = math.max(1, math.floor(size.X / step + 0.5))
	local nz = math.max(1, math.floor(size.Z / step + 0.5))
	for ix = 1, nx do
		for iz = 1, nz do
			local x = (ix - 0.5) / nx * size.X - size.X / 2 + rng:NextNumber(-0.8, 0.8)
			local z = (iz - 0.5) / nz * size.Z - size.Z / 2 + rng:NextNumber(-0.8, 0.8)
			local name = pick(rng, { "Bush_Medium", "Bush_Large", "Bush_Flowering", "Bush_Dark", "Bush_Light", "Bush_Medium", "Bush_Dark" })
			local source = Library[name]
			local fit = math.min(size.X / nx, size.Z / nz) * 1.45 / math.max(source.Size.X, source.Size.Z)
			local scale = math.clamp(fit, 0.75, 1.5)
			local bush = PropBuilder.Asset(name, model, ground * CFrame.new(x, -0.3, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(scale, scale * 1.15, scale))
			if bush then
				bush.Name = "Leaf" .. ix .. "_" .. iz
			end
		end
	end
	for _ = 1, rng:NextInteger(2, 4) do
		local spot = ground * CFrame.new(rng:NextNumber(-size.X / 2, size.X / 2) * 1.1, 0, (rng:NextNumber() < 0.5 and -1 or 1) * (size.Z / 2 + 0.6))
		PropBuilder.Asset(rng:NextNumber() < 0.6 and "Grass_Clump_B" or "Flowers_Pink", model, spot * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), 1)
	end
	CollectionService:AddTag(model, "RF_Bush")
	model.Parent = parent
	return model, zone
end

function PropBuilder.Cliff(parent, position, rng)
	if not PropBuilder.HasAssets() then
		return Legacy.Cliff(parent, position, rng)
	end
	local model = Instance.new("Model")
	model.Name = "Cliff"
	local name = rng:NextNumber() < 0.6 and "Rock_Large" or "Rock_Mossy"
	local scale = rng:NextNumber(1.6, 2.4)
	PropBuilder.Asset(name, model, CFrame.new(position.X, -0.5, position.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(scale, scale * rng:NextNumber(1.3, 1.9), scale))
	if rng:NextNumber() < 0.45 then
		local outward = Vector3.new(position.X, 0, position.Z).Unit
		PropBuilder.Asset(pick(rng, { "Bush_Dark", "Bush_Large", "Bush_Medium" }), model, CFrame.new(position + outward * 4) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(1.1, 1.6))
	end
	model.Parent = parent
	return model
end

-- Old medieval road along a -> b, built from 16-stud road modules with slight irregularity.
function PropBuilder.Road(parent, a, b, width, rng)
	if not PropBuilder.HasAssets() then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Road"
	local direction = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = direction.Magnitude
	local frame = CFrame.lookAt(Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z))
	local modules = math.max(1, math.ceil(length / 15))
	local moduleLength = length / modules
	for index = 1, modules do
		local name = pick(rng, { "Road_Segment", "Road_Segment", "Road_Damaged", "Road_Overgrown" })
		local source = Library[name]
		local offset = rng:NextNumber(-0.7, 0.7)
		local yaw = math.rad(rng:NextNumber(-4, 4)) + (rng:NextNumber() < 0.5 and math.pi or 0)
		local scale = Vector3.new(width / 12, 1, moduleLength * 1.04 / source.Size.Z)
		PropBuilder.Asset(name, model, frame * CFrame.new(offset, -0.28, -moduleLength * (index - 0.5)) * CFrame.Angles(0, yaw, 0), scale)
	end
	model.Parent = parent
	return model
end

-- Stone shrine platform (bases and arena centre). Returns the model.
function PropBuilder.Shrine(parent, position, radius, rng)
	if not PropBuilder.HasAssets() then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Shrine"
	local source = Library.Shrine_Platform
	local scale = radius * 2 / source.Size.X
	PropBuilder.Asset("Shrine_Platform", model, CFrame.new(position.X, -0.3, position.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(scale, 1, scale))
	-- dark worn stone floor inside the innermost ring
	local inner = PropBuilder.Piece(model, "Ruin", Vector3.new(0.3, 4.4 * scale * 2, 4.4 * scale * 2), CFrame.new(position.X, 0.02, position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 112, 105), Enum.PartType.Cylinder)
	inner.Name = "ShrineCenter"
	inner.CastShadow = false
	model.Parent = parent
	return model
end

function PropBuilder.Brazier(parent, position)
	local brazier = PropBuilder.Asset("Brazier", parent, CFrame.new(position.X, 0, position.Z), 1.15)
	if not brazier then
		return nil
	end
	local flame = Instance.new("Attachment")
	flame.Position = Vector3.new(0, brazier.Size.Y / 2 + 0.2, 0)
	flame.Parent = brazier
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = WARM_FIRE
	fire.SecondaryColor = Color3.fromRGB(255, 70, 30)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = WARM_FIRE
	light.Range = 14
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = flame
	return brazier
end

-- Ground dressing: soft dirt / grass-tone decals and small plants across open ground.
function PropBuilder.GroundDecal(parent, name, position, size, rng)
	local source = Library and Library:FindFirstChild(name)
	if not source then
		return nil
	end
	local scale = size / source.Size.X
	local decal = PropBuilder.Asset(name, parent, CFrame.new(position.X, 0.03 + rng:NextNumber(0, 0.04), position.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(scale, 1, scale * rng:NextNumber(0.7, 1.2)))
	local appearance = decal and decal:FindFirstChildOfClass("SurfaceAppearance")
	if appearance then
		if name:match("Dirt") then
			appearance.Color = Color3.fromRGB(240, 228, 205) -- soft earthy patch that blends into the grass
			decal.Transparency = 0.3
		elseif name == "Ground_GrassDark" then
			appearance.Color = Color3.fromRGB(200, 215, 170)
			decal.Transparency = 0.35
		end
	end
	return decal
end

return PropBuilder
