-- EffectsController: pooled, lightweight client visuals for server events.
-- One RenderStepped loop drives every running effect; parts are recycled.
-- Effects in fogged areas are skipped (except global objective events).

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))

-- Constants
local FAR = CFrame.new(0, -500, 0)
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local GLOBAL_EFFECTS = { FlagDestroyed = true, FlagRestored = true, RuinDestroyed = true, RuinSpawn = true }
local NUMBER_COLORS = {
	Damage = Color3.fromRGB(255, 235, 235),
	Crit = Color3.fromRGB(255, 205, 70),
	Shield = Color3.fromRGB(150, 210, 255),
	Heal = Color3.fromRGB(110, 255, 140),
}
local player = Players.LocalPlayer

-- State
local EffectsController = {}
local ClientState = nil
local FogController = nil
local folder = nil
local pools = {}
local animations = {}
local projectiles = {}
local numberAnchor = nil
local numberPool = {}
local random = Random.new()
local handlers = {}
local hitFlash -- defined with the Damage handler

-- Pooling ------------------------------------------------------------------------
local function acquire(key, shape, material)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	local part = table.remove(pool)
	if not part then
		part = Instance.new("Part")
		part.Name = key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Shape = shape or Enum.PartType.Block
		part.Material = material or Enum.Material.Neon
		part.Parent = folder
	end
	part.Transparency = 0
	return part
end

local function release(key, part)
	part.CFrame = FAR
	part.Transparency = 1
	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = false
	end
	table.insert(pools[key], part)
end

-- Runs step(alpha) every frame for `duration` seconds, then finish().
local function animate(duration, step, finish)
	table.insert(animations, { Duration = duration, Elapsed = 0, Step = step, Finish = finish })
end

local function visible(position)
	return position ~= nil and FogController.IsVisible(position)
end

-- Primitive effects ----------------------------------------------------------------
local function sphereBurst(position, fromSize, toSize, color, duration, startTransparency)
	local part = acquire("Sphere", Enum.PartType.Ball)
	part.Color = color
	animate(duration, function(alpha)
		local size = fromSize + (toSize - fromSize) * alpha
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(position)
		part.Transparency = (startTransparency or 0.2) + (1 - (startTransparency or 0.2)) * alpha
	end, function()
		release("Sphere", part)
	end)
end

local function ring(position, fromRadius, toRadius, color, duration, startTransparency)
	local part = acquire("Ring", Enum.PartType.Cylinder)
	part.Color = color
	animate(duration, function(alpha)
		local diameter = (fromRadius + (toRadius - fromRadius) * alpha) * 2
		part.Size = Vector3.new(0.2, diameter, diameter)
		part.CFrame = CFrame.new(position.X, 0.35, position.Z) * FLAT
		part.Transparency = (startTransparency or 0.3) + (1 - (startTransparency or 0.3)) * alpha
	end, function()
		release("Ring", part)
	end)
end

local function pillar(position, color, height, radius, duration)
	local part = acquire("Pillar", Enum.PartType.Cylinder)
	part.Color = color
	animate(duration, function(alpha)
		local width = radius * 2 * (1 - alpha * 0.6)
		part.Size = Vector3.new(height, width, width)
		part.CFrame = CFrame.new(position.X, height / 2, position.Z) * FLAT
		part.Transparency = 0.25 + 0.75 * alpha
	end, function()
		release("Pillar", part)
	end)
end

local function beam(from, to, color, width, duration)
	local part = acquire("Beam")
	part.Color = color
	local length = (to - from).Magnitude
	if length < 0.1 then
		release("Beam", part)
		return
	end
	local cframe = CFrame.lookAt((from + to) / 2, to)
	animate(duration, function(alpha)
		local thickness = width * (1 - alpha * 0.7)
		part.Size = Vector3.new(thickness, thickness, length)
		part.CFrame = cframe
		part.Transparency = 0.2 + 0.8 * alpha
	end, function()
		release("Beam", part)
	end)
end

local function floatingNumber(position, text, color, big)
	local billboard = table.remove(numberPool)
	-- pooled billboards can be destroyed when their parent GUI is rebuilt; discard those
	while billboard and (billboard.Parent == nil or not billboard:FindFirstChild("Label")) do
		billboard = table.remove(numberPool)
	end
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(90, 30)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 300
		billboard.Adornee = numberAnchor
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Name = "RF_FloatingNumber"
		billboard.ResetOnSpawn = false
		billboard.Parent = player:WaitForChild("PlayerGui"):FindFirstChild("RuinfallBars") or player.PlayerGui
	end
	local label = billboard:FindFirstChild("Label")
	label.Text = text
	label.TextColor3 = color
	label.TextSize = big and 26 or 18
	billboard.Enabled = true
	local jitter = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
	local base = position + Vector3.new(0, 4, 0) + jitter
	animate(0.75, function(alpha)
		billboard.StudsOffsetWorldSpace = base + Vector3.new(0, alpha * 3, 0)
		local fade = math.clamp((alpha - 0.45) / 0.55, 0, 1)
		label.TextTransparency = fade
		label.TextStrokeTransparency = 0.3 + 0.7 * fade
	end, function()
		billboard.Enabled = false
		table.insert(numberPool, billboard)
	end)
end

-- small glowing chips that fly out of an impact, arc down and fade
local function sparks(position, color, count, speed)
	for _ = 1, count do
		local part = acquire("Spark")
		part.Color = color
		part.Size = Vector3.new(0.22, 0.22, 0.22)
		local velocity = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.4, 1.2), random:NextNumber(-1, 1)).Unit * (speed or 18) * random:NextNumber(0.6, 1)
		local spin = random:NextNumber(-12, 12)
		local life = random:NextNumber(0.22, 0.38)
		animate(life, function(alpha)
			local t = alpha * life
			local offset = velocity * t + Vector3.new(0, -30 * t * t, 0)
			part.CFrame = CFrame.new(position + offset) * CFrame.Angles(spin * t, spin * t * 0.7, 0)
			part.Transparency = 0.1 + 0.9 * alpha
		end, function()
			release("Spark", part)
		end)
	end
end

-- Projectiles --------------------------------------------------------------------------------
-- Every projectile gets a glowing trail; fireballs / arcane bolts flicker with particles and
-- pulse, knives spin, arrows and power shots leave long streaks. Launch flash + impact burst.
local PROJECTILE_FX = {
	Default = { Trail = 0.12, Width = 0.5 },
	Arrow = { Trail = 0.18, Width = 0.25, Streak = true },
	PowerShot = { Trail = 0.28, Width = 0.8, Streak = true, Sparks = 8 },
	Knife = { Trail = 0.12, Width = 0.3, Spin = 26 },
	Fireball = { Trail = 0.3, Width = 1.4, Pulse = true, Particles = "Fire", Sparks = 10 },
	Arcane = { Trail = 0.25, Width = 1.1, Pulse = true, Particles = "Arcane", Sparks = 7 },
}

local function dressProjectile(part, style, fx)
	if part:GetAttribute("Dressed") then
		return
	end
	part:SetAttribute("Dressed", true)
	local length = math.max(style.Size.X, style.Size.Y, style.Size.Z)
	local back = Instance.new("Attachment")
	back.Name = "TrailA"
	back.Position = Vector3.new(0, fx.Width / 2, length / 2)
	back.Parent = part
	local back2 = Instance.new("Attachment")
	back2.Name = "TrailB"
	back2.Position = Vector3.new(0, -fx.Width / 2, length / 2)
	back2.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = back, back2
	trail.Lifetime = fx.Trail
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.Streak and 0.1 or 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), style.Color)
	trail.Parent = part
	if fx.Particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Flicker"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.LightEmission = 1
		emitter.Color = fx.Particles == "Fire" and ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 70, 20)) or ColorSequence.new(Color3.fromRGB(230, 200, 255), style.Color)
		emitter.Size = NumberSequence.new(0.7, 0)
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.Lifetime = NumberRange.new(0.2, 0.35)
		emitter.Rate = 60
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = part
	end
end

local function setProjectileFx(part, on)
	local trail = part:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = on
		if on then
			trail:Clear()
		end
	end
	local emitter = part:FindFirstChild("Flicker")
	if emitter then
		emitter.Enabled = on
	end
end

handlers.Projectile = function(data)
	local style = CombatDefinitions.ProjectileStyles[data.Style] or CombatDefinitions.ProjectileStyles.Default
	local fx = PROJECTILE_FX[data.Style or "Default"] or PROJECTILE_FX.Default
	local key = "Projectile_" .. (data.Style or "Default")
	local part = acquire(key, style.Shape == "Ball" and Enum.PartType.Ball or Enum.PartType.Block)
	part.Size = style.Size
	part.Color = style.Color
	dressProjectile(part, style, fx)
	-- start at the launch point before the trail switches on (no streak from the pool position)
	part.CFrame = CFrame.lookAt(data.Origin, data.Origin + data.Direction)
	setProjectileFx(part, true)
	if style.Light then
		local light = part:FindFirstChildOfClass("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Range = 8
			light.Brightness = 2
			light.Parent = part
		end
		light.Color = style.Color
		light.Enabled = true
	end
	if visible(data.Origin) then
		sphereBurst(data.Origin, 0.4, fx.Pulse and 2.6 or 1.6, style.Color, 0.12, 0.3) -- launch flash
	end
	projectiles[data.Id] = { Part = part, Key = key, Origin = data.Origin, Direction = data.Direction, Speed = data.Speed, Range = data.Range, Elapsed = 0, Fx = fx, BaseSize = style.Size }
end

handlers.ProjectileEnd = function(data)
	local projectile = projectiles[data.Id]
	if projectile then
		projectiles[data.Id] = nil
		setProjectileFx(projectile.Part, false)
		release(projectile.Key, projectile.Part)
	end
	if visible(data.Position) then
		local style = CombatDefinitions.ProjectileStyles[data.Style] or CombatDefinitions.ProjectileStyles.Default
		local fx = PROJECTILE_FX[data.Style or "Default"] or PROJECTILE_FX.Default
		sphereBurst(data.Position, 0.8, fx.Pulse and 4.5 or 3, style.Color, 0.2)
		ring(data.Position, 0.5, fx.Pulse and 4 or 2.5, style.Color, 0.25, 0.35)
		sparks(data.Position, style.Color, fx.Sparks or 4, fx.Pulse and 22 or 16)
	end
end

-- Root part of the unit that made a melee swing (so the slash follows a moving attacker
-- instead of staying where the server saw it - the server position lags while running)
local function attackerRoot(entityId)
	if not entityId then
		return nil
	end
	for _, tag in ipairs({ "RF_Hero", "RF_Creep" }) do
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
			if model:GetAttribute("EntityId") == entityId then
				return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			end
		end
	end
	return nil
end

-- Melee swoosh: a curved crescent that sweeps across the arc (bright leading edge, fading
-- tail), glued to the attacker. Empowered swings get a wider, double crescent and sparks.
local SWOOSH_SEGMENTS = 9
handlers.Melee = function(data)
	if not visible(data.Origin) then
		return
	end
	local direction = data.Direction
	local yaw = math.atan2(-direction.X, -direction.Z)
	local halfArc = math.rad(math.clamp(data.Arc or 90, 40, 360)) / 2
	local range = data.Range or 6
	local origin = Vector3.new(data.Origin.X, data.Origin.Y - 0.3, data.Origin.Z)
	local followRoot = attackerRoot(data.EntityId)
	local heightOffset = followRoot and (origin.Y - followRoot.Position.Y) or 0
	local color = data.Empowered and Color3.fromRGB(255, 225, 140) or data.Color
	local layers = data.Empowered and 2 or 1
	local duration = 0.24
	local sweep = 0.55 -- share of the duration the leading edge needs to cross the arc
	-- alternate the sweep direction each swing of the same attacker so combos read left/right
	local flip = 1
	if data.EntityId then
		EffectsController.SwingSide = EffectsController.SwingSide or {}
		flip = (EffectsController.SwingSide[data.EntityId] or 1) * -1
		EffectsController.SwingSide[data.EntityId] = flip
	end
	for layer = 1, layers do
		local radius = range * (layer == 1 and 0.72 or 0.9)
		local segments = {}
		for index = 1, SWOOSH_SEGMENTS do
			local part = acquire("Swoosh")
			part.Color = index == SWOOSH_SEGMENTS and Color3.new(1, 1, 1):Lerp(color, 0.4) or color
			part.Transparency = 1
			segments[index] = part
		end
		local segmentAngle = halfArc * 2 / SWOOSH_SEGMENTS
		local chord = 2 * radius * math.sin(segmentAngle / 2) + 0.15
		animate(duration, function(alpha)
			local center = origin
			if followRoot and followRoot.Parent then
				local p = followRoot.Position
				center = Vector3.new(p.X, p.Y + heightOffset, p.Z)
			end
			local lead = math.clamp(alpha / sweep, 0, 1)
			lead = 1 - (1 - lead) ^ 2.5
			for index, part in ipairs(segments) do
				local at = (index - 0.5) / SWOOSH_SEGMENTS
				local angle = flip * (-halfArc + halfArc * 2 * at)
				if at > lead then
					part.Transparency = 1
				else
					-- thick in the middle of the crescent, thin at the tips; older segments fade first
					local shape = math.sin(math.pi * at)
					local age = (lead - at) / math.max(0.05, lead)
					local fade = math.clamp(age * 0.7 + math.max(0, alpha - sweep) / (1 - sweep), 0, 1)
					part.Size = Vector3.new(chord, 0.1, 0.35 + 1.1 * shape * (layer == 1 and 1 or 0.6))
					part.CFrame = CFrame.new(center) * CFrame.Angles(0, yaw + angle, 0) * CFrame.new(0, (layer - 1) * 0.25, -radius)
					part.Transparency = 0.05 + 0.95 * fade
				end
			end
		end, function()
			for _, part in ipairs(segments) do
				release("Swoosh", part)
			end
		end)
	end
	if data.Empowered then
		local tip = origin + Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) * range * 0.7
		sparks(tip, color, 6, 20)
	end
end

handlers.Explosion = function(data)
	if not visible(data.Position) then
		return
	end
	sphereBurst(data.Position + Vector3.new(0, 1, 0), 2, data.Radius * 2, data.Color, 0.35, 0.25)
	ring(data.Position, 1, data.Radius, data.Color, 0.4, 0.2)
end

handlers.Telegraph = function(data)
	if not visible(data.Position) then
		return
	end
	local outline = acquire("Telegraph", Enum.PartType.Cylinder)
	local fill = acquire("TelegraphFill", Enum.PartType.Cylinder)
	outline.Color = data.Color
	fill.Color = data.Color
	local diameter = data.Radius * 2
	animate(data.Duration, function(alpha)
		outline.Size = Vector3.new(0.12, diameter, diameter)
		outline.CFrame = CFrame.new(data.Position.X, 0.25, data.Position.Z) * FLAT
		outline.Transparency = 0.55 + 0.2 * math.sin(alpha * math.pi * 6)
		local fillDiameter = math.max(0.1, diameter * alpha)
		fill.Size = Vector3.new(0.14, fillDiameter, fillDiameter)
		fill.CFrame = CFrame.new(data.Position.X, 0.28, data.Position.Z) * FLAT
		fill.Transparency = 0.45
	end, function()
		release("Telegraph", outline)
		release("TelegraphFill", fill)
	end)
end

-- Meteor (Meteor Codex): a blazing rock falls from the sky onto the target over Delay seconds
handlers.Meteor = function(data)
	if not visible(data.Position) then
		return
	end
	local rock = acquire("MeteorRock", Enum.PartType.Ball, Enum.Material.Basalt)
	local glow = acquire("MeteorGlow", Enum.PartType.Ball)
	rock.Color = Color3.fromRGB(90, 50, 30)
	glow.Color = data.Color
	local target = Vector3.new(data.Position.X, 1, data.Position.Z)
	local start = target + Vector3.new(-18, 70, 10)
	animate(data.Delay or 1, function(alpha)
		local position = start:Lerp(target, alpha * alpha)
		rock.Size = Vector3.new(3.2, 3.2, 3.2)
		rock.CFrame = CFrame.new(position)
		rock.Transparency = 0
		glow.Size = Vector3.new(5.5, 5.5, 5.5)
		glow.CFrame = CFrame.new(position)
		glow.Transparency = 0.45
	end, function()
		release("MeteorRock", rock)
		release("MeteorGlow", glow)
	end)
end

handlers.Shockwave = function(data)
	if not visible(data.Position) then
		return
	end
	ring(data.Position, 2, data.Radius, data.Color, 0.35, 0.1)
	ring(data.Position, 1, data.Radius * 0.7, Color3.new(1, 1, 1), 0.25, 0.3)
	sphereBurst(data.Position, 3, 8, data.Color, 0.25, 0.4)
end

handlers.Dash = function(data)
	if not visible(data.From) and not visible(data.To) then
		return
	end
	beam(data.From, data.To, data.Color, 1.4, 0.35)
end

handlers.Stealth = function(data)
	if not visible(data.Position) then
		return
	end
	local part = acquire("Smoke", Enum.PartType.Ball, Enum.Material.SmoothPlastic)
	part.Color = Color3.fromRGB(35, 20, 45)
	animate(0.45, function(alpha)
		local size = 3 + alpha * 7
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(data.Position)
		part.Transparency = 0.2 + 0.8 * alpha
	end, function()
		release("Smoke", part)
	end)
end

handlers.Lightning = function(data)
	if not visible(data.From) and not visible(data.To) then
		return
	end
	local from = data.From + Vector3.new(0, 1.5, 0)
	local to = data.To + Vector3.new(0, 1.5, 0)
	local points = { from }
	for index = 1, 3 do
		local point = from:Lerp(to, index / 4)
		table.insert(points, point + Vector3.new(random:NextNumber(-1.2, 1.2), random:NextNumber(-0.8, 0.8), random:NextNumber(-1.2, 1.2)))
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		beam(points[index], points[index + 1], data.Color or Color3.fromRGB(255, 240, 120), 0.35, 0.2)
	end
	sphereBurst(to, 1, 3, data.Color or Color3.fromRGB(255, 240, 120), 0.2)
end

-- Hit flash: the struck unit glows white for a split second (stronger on crits / heavy hits)
local HIT_TAGS = { "RF_Hero", "RF_Creep", "RF_Monster" }
local modelCache = {}
local flashes = {}
local function modelForEntity(entityId)
	local cached = modelCache[entityId]
	if cached and cached.Parent and cached:GetAttribute("EntityId") == entityId then
		return cached
	end
	modelCache[entityId] = nil
	for _, tag in ipairs(HIT_TAGS) do
		for _, model in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
			if model:GetAttribute("EntityId") == entityId then
				modelCache[entityId] = model
				return model
			end
		end
	end
	return nil
end
hitFlash = function(entityId, strong)
	if not entityId then
		return
	end
	local model = modelForEntity(entityId)
	if not model then
		return
	end
	local highlight = flashes[model]
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "RF_HitFlash"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 1
		highlight.FillTransparency = 1
		highlight.Parent = model
		flashes[model] = highlight
	end
	-- only enabled while flashing (Roblox renders a limited number of Highlights at once)
	local peak = strong and 0.25 or 0.5
	highlight.Enabled = true
	local token = (highlight:GetAttribute("Token") or 0) + 1
	highlight:SetAttribute("Token", token)
	animate(strong and 0.18 or 0.12, function(alpha)
		highlight.FillTransparency = peak + (1 - peak) * alpha
	end, function()
		if highlight:GetAttribute("Token") == token then
			highlight.FillTransparency = 1
			highlight.Enabled = false
		end
	end)
end

handlers.Damage = function(data)
	if data.Kind == "Miss" then
		if visible(data.Position) then
			floatingNumber(data.Position, "MISS", Color3.fromRGB(200, 200, 210), false)
		end
		return
	end
	if not visible(data.Position) or (data.Amount or 0) <= 0 then
		return
	end
	floatingNumber(data.Position, tostring(data.Amount), NUMBER_COLORS[data.Kind] or NUMBER_COLORS.Damage, data.Kind == "Crit")
	hitFlash(data.TargetId, data.Kind == "Crit" or data.Heavy)
end

-- Smoke Bomb cloud: a ring of drifting grey puffs that fades out when the smoke ends
handlers.SmokeCloud = function(data)
	local center, radius, duration = data.Position, data.Radius or 9, data.Duration or 4
	local folder = Instance.new("Folder")
	folder.Name = "RF_SmokeCloud"
	folder.Parent = workspace
	local puffs = {}
	local count = 16
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local distance = (index % 3 == 0) and random:NextNumber(0, radius * 0.4) or random:NextNumber(radius * 0.35, radius * 0.9)
		local size = random:NextNumber(5, 8)
		local part = Instance.new("Part")
		part.Name = "Puff"
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(105, 108, 115):Lerp(Color3.fromRGB(60, 62, 70), random:NextNumber())
		part.Size = Vector3.new(size, size * 0.8, size)
		part.Position = center + Vector3.new(math.cos(angle) * distance, size * 0.3 + random:NextNumber(0, 1.5), math.sin(angle) * distance)
		part.Transparency = 1
		part.Parent = folder
		table.insert(puffs, { Part = part, Base = part.Position, Phase = random:NextNumber(0, math.pi * 2) })
	end
	local edge = Instance.new("Part")
	edge.Name = "Edge"
	edge.Shape = Enum.PartType.Cylinder
	edge.Anchored = true
	edge.CanCollide = false
	edge.CanQuery = false
	edge.CanTouch = false
	edge.CastShadow = false
	edge.Material = Enum.Material.Neon
	edge.Color = Color3.fromRGB(120, 120, 135)
	edge.Size = Vector3.new(0.12, radius * 2, radius * 2)
	edge.CFrame = CFrame.new(center.X, center.Y + 0.25, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	edge.Transparency = 1
	edge.Parent = folder
	animate(duration, function(alpha)
		local elapsed = alpha * duration
		local fade = math.min(1, elapsed / 0.35, (duration - elapsed) / 0.6)
		for _, puff in ipairs(puffs) do
			if puff.Part.Parent then
				puff.Part.Transparency = 1 - 0.55 * math.max(0, fade)
				puff.Part.Position = puff.Base + Vector3.new(math.sin(elapsed * 0.8 + puff.Phase) * 0.6, elapsed * 0.25, math.cos(elapsed * 0.7 + puff.Phase) * 0.6)
			end
		end
		edge.Transparency = 1 - 0.55 * math.max(0, fade)
	end, function()
		folder:Destroy()
	end)
end

handlers.Heal = function(data)
	if not visible(data.Position) then
		return
	end
	floatingNumber(data.Position, "+" .. tostring(data.Amount), NUMBER_COLORS.Heal, false)
	sphereBurst(data.Position, 2, 4, NUMBER_COLORS.Heal, 0.25, 0.5)
end

handlers.Death = function(data)
	if not visible(data.Position) then
		return
	end
	sphereBurst(data.Position, 2, data.Kind == "Flag" and 16 or 7, data.Color, 0.4, 0.2)
	for _ = 1, 6 do
		local part = acquire("Debris")
		part.Color = data.Color
		part.Size = Vector3.new(0.6, 0.6, 0.6)
		local velocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(8, 16), random:NextNumber(-10, 10))
		local spin = random:NextNumber(-8, 8)
		animate(0.6, function(alpha)
			local t = alpha * 0.6
			local position = data.Position + velocity * t + Vector3.new(0, -30 * t * t, 0)
			part.CFrame = CFrame.new(position) * CFrame.Angles(spin * t, spin * t, 0)
			part.Transparency = alpha
		end, function()
			release("Debris", part)
		end)
	end
end

handlers.RuinSpawn = function(data)
	pillar(data.Position, data.Color, 60, 3, 1.4)
	ring(data.Position, 2, 12, data.Color, 0.8, 0.2)
end

handlers.RuinDestroyed = function(data)
	pillar(data.Position, data.Color, 80, 5, 1.2)
	sphereBurst(data.Position + Vector3.new(0, 3, 0), 3, 20, data.Color, 0.5, 0.2)
	ring(data.Position, 2, 18, data.Color, 0.6, 0.1)
end

handlers.FlagDestroyed = function(data)
	pillar(data.Position, data.Color, 90, 6, 1.6)
	sphereBurst(data.Position + Vector3.new(0, 4, 0), 4, 28, data.Color, 0.6, 0.15)
	ring(data.Position, 2, 26, Color3.new(1, 1, 1), 0.7, 0.2)
end

handlers.FlagRestored = function(data)
	pillar(data.Position, data.Color, 90, 4, 1.4)
	ring(data.Position, 16, 2, data.Color, 0.7, 0.2)
	sphereBurst(data.Position + Vector3.new(0, 4, 0), 2, 12, Constants.Colors.Fragment, 0.5, 0.3)
end

handlers.FragmentSpawn = function(data)
	if FogController.IsExplored(data.Position) then
		pillar(data.Position, data.Color, 30, 1.5, 1)
	end
end

handlers.Pickup = function(data)
	if visible(data.Position) then
		sphereBurst(data.Position + Vector3.new(0, 2, 0), 1, 7, data.Color, 0.35, 0.2)
	end
end

handlers.Shield = function(data)
	if visible(data.Position) then
		sphereBurst(data.Position, 4, 9, Constants.Colors.Shield, 0.4, 0.4)
	end
end

handlers.Stun = function(data)
	if not visible(data.Position) then
		return
	end
	local part = acquire("StunRing", Enum.PartType.Cylinder)
	part.Color = Color3.fromRGB(255, 230, 80)
	part.Size = Vector3.new(0.15, 3, 3)
	local position = data.Position + Vector3.new(0, 3.5, 0)
	animate(data.Duration or 1, function(alpha)
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, alpha * 12, 0) * FLAT
		part.Transparency = 0.2 + 0.6 * alpha
	end, function()
		release("StunRing", part)
	end)
end

handlers.BloodRush = function(data)
	if visible(data.Position) then
		ring(data.Position, 1, 7, data.Color, 0.35, 0.1)
		sphereBurst(data.Position, 2, 6, Color3.fromRGB(255, 40, 60), 0.3, 0.4)
	end
end

handlers.Cast = function(data)
	if visible(data.Position) then
		sphereBurst(data.Position + Vector3.new(0, 1, 0), 1, 5, data.Color, 0.25, 0.3)
	end
end

-- Item ability effects (mythic E/R skills) ----------------------------------------------
handlers.HeavyKick = function(data)
	if not visible(data.Position) then
		return
	end
	local impact = data.Position + Vector3.new(0, 1.2, 0)
	sphereBurst(impact, 1, 5, data.Color, 0.25, 0.1)
	ring(data.Position, 1, 6.5, data.Color, 0.35, 0.05)
	ring(data.Position, 0.5, 3.5, Color3.fromRGB(110, 80, 50), 0.55, 0.3)
	if data.Origin then
		beam(data.Origin + Vector3.new(0, 1, 0), impact, data.Color, 0.9, 0.12)
	end
end

handlers.PointStrike = function(data)
	if not visible(data.Position) and not visible(data.From) then
		return
	end
	local to = data.Position + Vector3.new(0, 2.5, 0)
	beam(data.From + Vector3.new(0, 2.5, 0), to, data.Color, 0.7, 0.2)
	sphereBurst(to, 1, 4.5, data.Color, 0.3, 0.1)
	ring(data.Position, 0.8, 4.5, data.Color, 0.3, 0.1)
end

handlers.WindPull = function(data)
	if not visible(data.Position) then
		return
	end
	local radius = data.Radius or 10
	local duration = data.Duration or 0.6
	-- inward-collapsing gust rings show the pull direction (toward the center)
	for index = 0, 3 do
		task.delay(index * duration / 4, function()
			ring(data.Position, radius, 0.8, data.Color, duration * 0.9, 0.35)
		end)
	end
	pillar(data.Position, data.Color, 7, 1.6, duration + 0.3)
	sphereBurst(data.Position + Vector3.new(0, 1.5, 0), radius * 0.6, 1, Color3.fromRGB(230, 250, 255), duration, 0.75)
end

-- Gale Burst (Mage Boots): outward-blasting gust rings show the push direction (away from the center)
handlers.GalePush = function(data)
	if not visible(data.Position) then
		return
	end
	local radius = data.Radius or 9
	local duration = data.Duration or 0.35
	for index = 0, 2 do
		task.delay(index * 0.08, function()
			ring(data.Position, 0.8, radius + index * 1.5, data.Color, duration + 0.25, 0.3)
		end)
	end
	sphereBurst(data.Position + Vector3.new(0, 1.5, 0), 1, radius * 0.8, Color3.fromRGB(230, 250, 255), duration + 0.2, 0.7)
end

local function findEntityModel(entityId)
	for _, model in ipairs(game:GetService("CollectionService"):GetTagged("RF_Hero")) do
		if model:GetAttribute("EntityId") == entityId then
			return model
		end
	end
	return nil
end

handlers.SpikedScale = function(data)
	local model = findEntityModel(data.EntityId)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	ring(root.Position, 1, 6, data.Color, 0.3, 0.05)
	local part = acquire("SpikeAura", Enum.PartType.Cylinder)
	part.Color = data.Color
	animate(data.Duration or 5, function(alpha)
		if not root.Parent then
			return
		end
		local pulse = 0.5 + 0.5 * math.sin(alpha * (data.Duration or 5) * 8)
		part.Size = Vector3.new(0.15, 6 + pulse * 0.8, 6 + pulse * 0.8)
		part.CFrame = CFrame.new(root.Position.X, 0.4, root.Position.Z) * FLAT
		part.Transparency = FogController.IsVisible(root.Position) and (0.35 + 0.35 * pulse) or 1
	end, function()
		release("SpikeAura", part)
	end)
end

-- Frame update ------------------------------------------------------------------------
local function onRender(dt)
	for id, projectile in pairs(projectiles) do
		projectile.Elapsed += dt
		local traveled = projectile.Speed * projectile.Elapsed
		if traveled > projectile.Range + 6 then
			projectiles[id] = nil
			setProjectileFx(projectile.Part, false)
			release(projectile.Key, projectile.Part)
		else
			local position = projectile.Origin + projectile.Direction * math.min(traveled, projectile.Range)
			local cframe = CFrame.lookAt(position, position + projectile.Direction)
			local fx = projectile.Fx
			if fx and fx.Spin then
				cframe *= CFrame.Angles(0, projectile.Elapsed * fx.Spin, 0) -- thrown blades whirl flat
			end
			projectile.Part.CFrame = cframe
			if fx and fx.Pulse then
				projectile.Part.Size = projectile.BaseSize * (1 + 0.15 * math.sin(projectile.Elapsed * 30))
			end
			local shown = FogController.IsVisible(position)
			projectile.Part.Transparency = shown and 0 or 1
			if projectile.Shown ~= shown then
				projectile.Shown = shown
				setProjectileFx(projectile.Part, shown)
			end
		end
	end
	for index = #animations, 1, -1 do
		local animation = animations[index]
		animation.Elapsed += dt
		local alpha = math.min(1, animation.Elapsed / animation.Duration)
		local ok = pcall(animation.Step, alpha)
		if alpha >= 1 or not ok then
			table.remove(animations, index)
			if animation.Finish then
				pcall(animation.Finish)
			end
		end
	end
end

-- Public API ----------------------------------------------------------------------------
function EffectsController.Play(kind, data)
	local handler = handlers[kind]
	if not handler then
		return
	end
	if not GLOBAL_EFFECTS[kind] and not ClientState.InMatch() then
		return
	end
	local ok, err = pcall(handler, data)
	if not ok then
		warn("[Ruinfall] Effect error", kind, err)
	end
end

function EffectsController.MoveMarker(position)
	ring(position, 2.5, 0.5, Color3.fromRGB(120, 255, 160), 0.35, 0.2)
end

function EffectsController.Init(clientState, fogController)
	ClientState = clientState
	FogController = fogController
	folder = Instance.new("Folder")
	folder.Name = "LocalEffects"
	folder.Parent = workspace
	numberAnchor = Instance.new("Part")
	numberAnchor.Name = "NumberAnchor"
	numberAnchor.Anchored = true
	numberAnchor.CanCollide = false
	numberAnchor.CanQuery = false
	numberAnchor.CanTouch = false
	numberAnchor.Transparency = 1
	numberAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
	numberAnchor.CFrame = CFrame.new()
	numberAnchor.Parent = folder
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("EffectEvent").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then
			return
		end
		for _, item in ipairs(batch) do
			EffectsController.Play(item[1], item[2])
		end
	end)
	clientState.StateChanged:Connect(function()
		for id, projectile in pairs(projectiles) do
			projectiles[id] = nil
			setProjectileFx(projectile.Part, false)
			release(projectile.Key, projectile.Part)
		end
	end)
	RunService.RenderStepped:Connect(onRender)
end

return EffectsController
