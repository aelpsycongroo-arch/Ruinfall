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

-- Handlers (one per server effect kind) -----------------------------------------------
handlers.Projectile = function(data)
	local style = CombatDefinitions.ProjectileStyles[data.Style] or CombatDefinitions.ProjectileStyles.Default
	local key = "Projectile_" .. (data.Style or "Default")
	local part = acquire(key, style.Shape == "Ball" and Enum.PartType.Ball or Enum.PartType.Block)
	part.Size = style.Size
	part.Color = style.Color
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
	projectiles[data.Id] = { Part = part, Key = key, Origin = data.Origin, Direction = data.Direction, Speed = data.Speed, Range = data.Range, Elapsed = 0 }
end

handlers.ProjectileEnd = function(data)
	local projectile = projectiles[data.Id]
	if projectile then
		projectiles[data.Id] = nil
		release(projectile.Key, projectile.Part)
	end
	if visible(data.Position) then
		local style = CombatDefinitions.ProjectileStyles[data.Style] or CombatDefinitions.ProjectileStyles.Default
		sphereBurst(data.Position, 0.8, 3, style.Color, 0.18)
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

handlers.Melee = function(data)
	if not visible(data.Origin) then
		return
	end
	local direction = data.Direction
	local yaw = math.atan2(-direction.X, -direction.Z)
	local halfArc = math.rad(data.Arc or 90) / 2
	local range = data.Range or 6
	local origin = Vector3.new(data.Origin.X, data.Origin.Y - 0.5, data.Origin.Z)
	local followRoot = attackerRoot(data.EntityId)
	local heightOffset = followRoot and (origin.Y - followRoot.Position.Y) or 0
	local blades = data.Empowered and 2 or 1
	for bladeIndex = 1, blades do
		local part = acquire("Slash")
		part.Color = data.Empowered and Color3.fromRGB(255, 220, 120) or data.Color
		part.Size = Vector3.new(bladeIndex == 1 and 0.5 or 0.9, 0.15, range)
		local duration = 0.13 + (bladeIndex - 1) * 0.05
		animate(duration, function(alpha)
			local angle = -halfArc + halfArc * 2 * alpha
			local center = origin
			if followRoot and followRoot.Parent then
				local p = followRoot.Position
				center = Vector3.new(p.X, p.Y + heightOffset, p.Z) -- stay glued to the attacker
			end
			part.CFrame = CFrame.new(center) * CFrame.Angles(0, yaw + angle, 0) * CFrame.new(0, 0, -range / 2)
			part.Transparency = 0.1 + 0.8 * alpha
		end, function()
			release("Slash", part)
		end)
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
			release(projectile.Key, projectile.Part)
		else
			local position = projectile.Origin + projectile.Direction * math.min(traveled, projectile.Range)
			projectile.Part.CFrame = CFrame.lookAt(position, position + projectile.Direction)
			projectile.Part.Transparency = FogController.IsVisible(position) and 0 or 1
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
			release(projectile.Key, projectile.Part)
		end
	end)
	RunService.RenderStepped:Connect(onRender)
end

return EffectsController
