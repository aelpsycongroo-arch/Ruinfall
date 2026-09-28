-- UnitDisplayController: overhead health bars, fog/stealth/brush hiding of
-- models, shield bubbles, buff auras and fragment pickup animation.

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label = UITheme.New, UITheme.Label
local UPDATE_INTERVAL = 1 / 15
local MANA_COLOR = COLORS.Mana or Color3.fromRGB(70, 140, 255)
local player = Players.LocalPlayer
local KIND_CONFIG = {
	Hero = { Tag = "RF_Hero", Width = 110, BarHeight = 8, ManaHeight = 4, Offset = 4.6, ShowName = true }, -- mana bar under health
	Monster = { Tag = "RF_Monster", Width = 70, BarHeight = 6, Offset = 3.2, ShowName = false },
	Flag = { Tag = "RF_Flag", Width = 150, BarHeight = 10, Offset = 5, ShowName = true },
	Ruin = { Tag = "RF_Ruin", Width = 120, BarHeight = 9, Offset = 6, ShowName = true },
	Creep = { Tag = "RF_Creep", Width = 54, BarHeight = 5, Offset = 2.8, ShowName = false },
}

-- State
local UnitDisplayController = {}
local ClientState = nil
local FogController = nil
local units = {} -- [model] = record
local barFolder = nil
local accumulator = 0

-- Functions
local function collectParts(model)
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Visuals that LocalTransparencyModifier does NOT hide (a Mage staff's glow, accessory
-- particles / trails / lights, attached guis, highlights). They are switched off while an
-- enemy is hidden (fog, brush, behind walls, stealth), together with the parts' shadows,
-- so a hidden hero is completely undetectable.
local HIDEABLE_CLASSES = { "Light", "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "LayerCollector", "Highlight" }
local function isHideable(instance)
	for _, className in ipairs(HIDEABLE_CLASSES) do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function collectExtras(model)
	local extras = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if isHideable(descendant) then
			table.insert(extras, descendant)
		end
	end
	return extras
end

-- hide one instance (remembering what to restore)
local function hideInstance(record, instance)
	if instance:IsA("BasePart") then
		if instance.CastShadow then
			record.Saved[instance] = true
			instance.CastShadow = false
		end
	elseif instance.Enabled then
		record.Saved[instance] = true
		instance.Enabled = false
	end
end

-- hidden = true: no shadows, lights, particles, trails or guis; false restores them
local function setHidden(record, hidden)
	if hidden then
		if not record.Hidden then
			record.Hidden = true
			record.Saved = {}
			for _, part in ipairs(record.Parts) do
				if part.Parent and part:IsA("BasePart") then
					hideInstance(record, part)
				end
			end
		end
		-- re-check every tick: the server may switch an effect back on while the hero is hidden
		for _, extra in ipairs(record.Extras) do
			if extra.Parent then
				hideInstance(record, extra)
			end
		end
	elseif record.Hidden then
		record.Hidden = false
		for instance in pairs(record.Saved) do
			if instance.Parent then
				if instance:IsA("BasePart") then
					instance.CastShadow = true
				else
					instance.Enabled = true
				end
			end
		end
		record.Saved = {}
	end
end

local function setModelTransparency(record, modifier)
	if record.Modifier == modifier then
		return
	end
	record.Modifier = modifier
	for _, part in ipairs(record.Parts) do
		if part.Parent then
			part.LocalTransparencyModifier = modifier
		end
	end
end

local function buildBillboard(model, kind)
	local config = KIND_CONFIG[kind]
	local adornee = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local billboard = New("BillboardGui", {
		Name = "Bar_" .. model.Name,
		Adornee = adornee,
		Size = UDim2.fromOffset(model:GetAttribute("BarWidth") or config.Width, (config.ShowName and 32 or 12) + (config.ManaHeight and config.ManaHeight + 1 or 0)),
		StudsOffsetWorldSpace = Vector3.new(0, model:GetAttribute("BarOffset") or config.Offset, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 250,
		ResetOnSpawn = false,
		Parent = barFolder,
	})
	local nameLabel = nil
	if config.ShowName then
		nameLabel = Label({ Text = "", Font = FONTS.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, Size = UDim2.new(1, 0, 0, 16), Parent = billboard })
	end
	local manaGap = config.ManaHeight and config.ManaHeight + 1 or 0
	local bar = UITheme.Bar({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -manaGap), Size = UDim2.new(1, 0, 0, config.BarHeight), CornerRadius = 3 }, COLORS.Danger)
	bar.Frame.Parent = billboard
	UITheme.Stroke(bar.Frame, Color3.new(0, 0, 0), 1, 0.2)
	-- heroes: a thin mana bar right under the health bar
	local mana = nil
	if config.ManaHeight then
		mana = UITheme.Bar({ Name = "Mana", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, config.ManaHeight), CornerRadius = 2 }, MANA_COLOR)
		mana.Frame.Parent = billboard
		UITheme.Stroke(mana.Frame, Color3.new(0, 0, 0), 1, 0.2)
	end
	local shield = New("Frame", { Size = UDim2.fromScale(0, 0.45), BackgroundColor3 = COLORS.Shield, ZIndex = 2, Parent = bar.Frame })
	local tagLabel = Label({ Text = "", Font = FONTS.Title, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, 40, 0, 14), Parent = billboard })
	return billboard, nameLabel, bar, shield, tagLabel, mana
end

local function track(model, kind)
	if units[model] or not barFolder then
		return
	end
	local waited = 0
	while not (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) and waited < 5 and model.Parent do
		waited += task.wait(0.1)
	end
	if not model.Parent or units[model] then
		return
	end
	local billboard, nameLabel, bar, shield, tagLabel, mana = buildBillboard(model, kind)
	local record = { Model = model, Kind = kind, Billboard = billboard, NameLabel = nameLabel, Bar = bar, Shield = shield, Tag = tagLabel, Mana = mana,
		Parts = collectParts(model), Extras = collectExtras(model), Saved = {}, Hidden = false, Modifier = 0 }
	record.Connection = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(record.Parts, descendant)
			descendant.LocalTransparencyModifier = record.Modifier
			if record.Hidden and descendant:IsA("BasePart") then
				hideInstance(record, descendant)
			end
		elseif isHideable(descendant) then
			table.insert(record.Extras, descendant)
			if record.Hidden then
				hideInstance(record, descendant)
			end
		end
	end)
	units[model] = record
end

local function untrack(model)
	local record = units[model]
	if not record then
		return
	end
	units[model] = nil
	record.Connection:Disconnect()
	record.Billboard:Destroy()
	if record.Bubble then
		record.Bubble:Destroy()
	end
	if record.Aura then
		record.Aura:Destroy()
	end
	if record.Highlight then
		record.Highlight:Destroy()
	end
end

local function updateAura(record, root, color)
	if color then
		if not record.Aura or not record.Aura.Parent then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "BuffAura"
			emitter.LightEmission = 1
			emitter.Rate = 14
			emitter.Lifetime = NumberRange.new(0.4, 0.7)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new(0.2)
			emitter.Parent = root
			record.Aura = emitter
		end
		record.Aura.Color = ColorSequence.new(color)
		record.Aura.Enabled = record.Modifier < 1
	elseif record.Aura then
		record.Aura:Destroy()
		record.Aura = nil
	end
end

local function updateBubble(record, root, shieldAmount)
	if shieldAmount > 0 and record.Modifier < 1 then
		if not record.Bubble then
			local bubble = Instance.new("Part")
			bubble.Name = "ShieldBubble"
			bubble.Shape = Enum.PartType.Ball
			bubble.Size = Vector3.new(7, 7, 7)
			bubble.Anchored = true
			bubble.CanCollide = false
			bubble.CanQuery = false
			bubble.CanTouch = false
			bubble.CastShadow = false
			bubble.Material = Enum.Material.ForceField
			bubble.Color = COLORS.Shield
			bubble.Transparency = 0.1
			bubble.Parent = workspace
			record.Bubble = bubble
		end
		record.Bubble.CFrame = CFrame.new(root.Position)
	elseif record.Bubble then
		record.Bubble:Destroy()
		record.Bubble = nil
	end
end

local function updateHero(record, now, myTeam)
	local model = record.Model
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dead = model:GetAttribute("Dead") == true
	local team = model:GetAttribute("Team")
	local isMine = model == player.Character
	local isAlly = team == myTeam
	local stealthed = model:GetAttribute("Stealthed") == true
	local visible = not dead and ClientState.IsHeroVisible(model)

	local modifier = 0
	if not visible and not dead then
		modifier = 1
	elseif isAlly and stealthed then
		modifier = 0.65
	elseif isAlly and model:GetAttribute("InBrush") then
		modifier = 0.4
	end
	setModelTransparency(record, modifier)
	setHidden(record, modifier >= 1)

	if isAlly and stealthed and not dead then
		if not record.Highlight then
			record.Highlight = New("Highlight", {
				Adornee = model,
				FillTransparency = 1,
				OutlineColor = Constants.GetTeamColor(team),
				OutlineTransparency = 0.2,
				DepthMode = Enum.HighlightDepthMode.Occluded,
				Parent = barFolder,
			})
		end
	elseif record.Highlight then
		record.Highlight:Destroy()
		record.Highlight = nil
	end

	-- Bar only for heroes this client can actually see: an enemy in fog, in brush, behind a
	-- wall or stealthed shows nothing at all (no bar, name, tags, aura or shield bubble)
	local showBar = visible and not dead
	record.Billboard.Enabled = showBar
	if showBar then
		local health = model:GetAttribute("Health") or 0
		local maxHealth = math.max(1, model:GetAttribute("MaxHealth") or 1)
		local teamColor = Constants.GetTeamColor(team)
		record.Bar.Set(health / maxHealth, teamColor) -- every hero's bar (yours too) is its team's colour
		record.Shield.Size = UDim2.fromScale(math.clamp((model:GetAttribute("Shield") or 0) / maxHealth, 0, 1), 0.45)
		if record.Mana then
			local maxMana = model:GetAttribute("MaxMana") or 0
			record.Mana.Frame.Visible = maxMana > 0
			if maxMana > 0 then
				record.Mana.Set((model:GetAttribute("Mana") or 0) / maxMana)
			end
		end
		local classDef = ClassDefinitions.Get(model:GetAttribute("Class"))
		record.NameLabel.Text = (classDef and ("[" .. classDef.Icon .. "] ") or "") .. (model:GetAttribute("DisplayName") or model.Name)
		record.NameLabel.TextColor3 = isMine and Color3.new(1, 1, 1) or teamColor:Lerp(Color3.new(1, 1, 1), 0.35)
		local tags = {}
		local hasFragment = model:GetAttribute("HasFragment") == true
		if hasFragment then
			table.insert(tags, "FRAGMENT")
		end
		if (model:GetAttribute("StunnedUntil") or 0) > now then
			table.insert(tags, "STUNNED")
		end
		record.Tag.Text = table.concat(tags, "  ")
		record.Tag.TextColor3 = hasFragment and COLORS.Fragment or COLORS.Warning
	end

	local auraColor = nil
	if model:GetAttribute("BloodRush") then
		auraColor = Color3.fromRGB(255, 40, 60)
	else
		local buffKey = model:GetAttribute("BuffKey")
		local buff = buffKey and CombatDefinitions.Buffs[buffKey]
		if buff and (model:GetAttribute("BuffEndsAt") or 0) > now then
			auraColor = buff.Color
		end
	end
	updateAura(record, root, showBar and auraColor or nil)
	updateBubble(record, root, showBar and (model:GetAttribute("Shield") or 0) or 0)
end

local function updateObjective(record)
	local model = record.Model
	local adornee = record.Billboard.Adornee
	if not adornee then
		record.Billboard.Enabled = false
		return
	end
	local dead = model:GetAttribute("Dead") == true
	local position = adornee.Position
	local health = model:GetAttribute("Health") or 0
	local maxHealth = math.max(1, model:GetAttribute("MaxHealth") or 1)
	if record.Kind == "Creep" then
		-- war band creeps: team-coloured bar; enemy creeps are hidden in fog of war
		local team = model:GetAttribute("Team")
		local seen = team == ClientState.GetMyTeam() or FogController.IsVisible(position)
		setModelTransparency(record, seen and 0 or 1)
		setHidden(record, not seen)
		record.Billboard.Enabled = seen and not dead
		record.Bar.Set(health / maxHealth, Constants.GetTeamColor(team))
	elseif record.Kind == "Monster" then
		record.Billboard.Enabled = not dead
		record.Bar.Set(health / maxHealth, Color3.fromRGB(235, 120, 60))
	elseif record.Kind == "Ruin" then
		record.Billboard.Enabled = not dead
		record.Bar.Set(health / maxHealth, COLORS.Gold)
		record.NameLabel.Text = "RUIN"
		record.NameLabel.TextColor3 = COLORS.Gold
	elseif record.Kind == "Flag" then
		local team = model:GetAttribute("Team")
		local flagState = model:GetAttribute("FlagState") or "Intact"
		record.Billboard.Enabled = true
		record.NameLabel.Text = string.upper(Constants.GetTeamName(team)) .. " FLAG"
		record.NameLabel.TextColor3 = Constants.GetTeamColor(team)
		if flagState == "Intact" and not dead then
			record.Bar.Set(health / maxHealth, Constants.GetTeamColor(team))
			record.Tag.Text = ""
		else
			record.Bar.Set(0)
			record.Tag.Text = flagState == "LastStand" and "LAST STAND - RE-ANCHOR HERE" or "FLAGLESS"
			record.Tag.TextColor3 = flagState == "LastStand" and COLORS.Fragment or COLORS.Subtext
		end
	end
end

local function updateAll()
	local now = workspace:GetServerTimeNow()
	local myTeam = ClientState.GetMyTeam()
	for model, record in pairs(units) do
		if not model.Parent then
			untrack(model)
		elseif record.Kind == "Hero" then
			updateHero(record, now, myTeam)
		else
			updateObjective(record)
		end
	end
end

-- Fragment pickups: local spin/bob + label
local fragments = {} -- [model] = { Base = CFrame, Billboard }
local function trackFragment(model)
	local crystal = model:WaitForChild("Crystal", 5)
	if not crystal or fragments[model] then
		return
	end
	local billboard = New("BillboardGui", { Adornee = crystal, Size = UDim2.fromOffset(120, 18), StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 200, Parent = barFolder })
	Label({ Text = "CORE FRAGMENT", Font = FONTS.Title, TextSize = 12, TextColor3 = COLORS.Fragment, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Size = UDim2.fromScale(1, 1), Parent = billboard })
	fragments[model] = { Crystal = crystal, Base = crystal.CFrame, Billboard = billboard }
end

local function untrackFragment(model)
	local entry = fragments[model]
	if entry then
		entry.Billboard:Destroy()
		fragments[model] = nil
	end
end

-- Public API
function UnitDisplayController.Init(clientState, fogController)
	ClientState = clientState
	FogController = fogController
	-- Use a ScreenGui with ResetOnSpawn=false as container so the bar folder
	-- survives character respawns (a plain Folder in PlayerGui gets destroyed
	-- when the player's character spawns).
	local playerGui = player:WaitForChild("PlayerGui")
	local container = playerGui:FindFirstChild("RuinfallBarsGui")
	if not container then
		container = Instance.new("ScreenGui")
		container.Name = "RuinfallBarsGui"
		container.ResetOnSpawn = false
		container.DisplayOrder = 10
		container.IgnoreGuiInset = true
		container.Parent = playerGui
	end
	barFolder = container:FindFirstChild("RuinfallBars")
	if not barFolder then
		barFolder = Instance.new("Folder")
		barFolder.Name = "RuinfallBars"
		barFolder.Parent = container
	end
	for kind, config in pairs(KIND_CONFIG) do
		for _, model in ipairs(CollectionService:GetTagged(config.Tag)) do
			task.spawn(track, model, kind)
		end
		CollectionService:GetInstanceAddedSignal(config.Tag):Connect(function(model)
			task.spawn(track, model, kind)
		end)
		CollectionService:GetInstanceRemovedSignal(config.Tag):Connect(untrack)
	end
	for _, model in ipairs(CollectionService:GetTagged("RF_Fragment")) do
		task.spawn(trackFragment, model)
	end
	CollectionService:GetInstanceAddedSignal("RF_Fragment"):Connect(function(model)
		task.spawn(trackFragment, model)
	end)
	CollectionService:GetInstanceRemovedSignal("RF_Fragment"):Connect(untrackFragment)
	clientState.VisibilityChanged:Connect(updateAll)

	RunService.RenderStepped:Connect(function(dt)
		local clock = os.clock()
		for model, entry in pairs(fragments) do
			if entry.Crystal.Parent then
				entry.Crystal.CFrame = entry.Base * CFrame.new(0, math.sin(clock * 3) * 0.4, 0) * CFrame.Angles(0, clock * 2, 0)
			else
				untrackFragment(model)
			end
		end
		for _, record in pairs(units) do
			if record.Bubble then
				local root = record.Model:FindFirstChild("HumanoidRootPart")
				if root then
					record.Bubble.CFrame = CFrame.new(root.Position)
				end
			end
		end
		accumulator += dt
		if accumulator >= UPDATE_INTERVAL then
			accumulator = 0
			updateAll()
		end
	end)
end

return UnitDisplayController
