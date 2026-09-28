-- MobileController: MOBA-style touch controls (phones / tablets).
--   Left side      Roblox dynamic thumbstick moves the hero (camera-relative).
--   ATTACK         hold to auto-attack the nearest enemy in range.
--   Q / E / R      TAP  = auto-aim at the nearest enemy (or cast on self)
--                  DRAG = aim like a joystick (ground indicator), release to cast;
--                         release over CANCEL to abort. E/R follow mythic slots 1/2.
--   SWAP           swap mythic slots (E <-> R).   SHOP  opens the item shop.
--   Camera zoom is fixed (CameraController), so pinching does nothing.
--   The SHOP button also shows your gold (the character panel is hidden - see HUD).
-- Only intents are sent; the server validates every attack/ability as on desktop.

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local ShopDefinitions = require(Shared:WaitForChild("ShopDefinitions"))
local Util = require(Shared:WaitForChild("Util"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local STATE = Constants.MatchState
local MEDIEVAL = UITheme.Medieval
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label = UITheme.New, UITheme.Label
local player = Players.LocalPlayer
local DRAG_THRESHOLD = 16 -- px before a press becomes a drag-aim
local DRAG_RADIUS = 105 -- px of drag = full ability range
local TARGET_TAGS = { "RF_Hero", "RF_Creep", "RF_Monster", "RF_Ruin", "RF_Flag" }
local UNIT_KINDS = { Hero = true, Creep = true, Monster = true }
local SELF_CAST_Q = { BloodRush = true, TauntingShockwave = true }

-- State
local MobileController = {}
local ClientState, CombatController, UIController, CameraController
local gui, cluster, buttons = nil, nil, {}
local active = false
local attackTouch = nil
local aiming = nil -- { Key, Input, Start, Dragging, Aim, Target, Info }
local indicator = {}
local targetHighlight = nil
local lastPinchScale = nil

-- Helpers -------------------------------------------------------------------------------
local function myRoot()
	local character = ClientState.GetLocalCharacter()
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function modelRoot(model)
	return model:IsA("Model") and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) or nil
end

local function isEnemy(model, unitsOnly)
	if not model.Parent or model:GetAttribute("Dead") then
		return false
	end
	local kind = model:GetAttribute("Kind")
	if unitsOnly and not UNIT_KINDS[kind] then
		return false
	end
	if model:GetAttribute("Team") == ClientState.GetMyTeam() then
		return false
	end
	if kind == "Hero" and ((model:GetAttribute("Stealthed") and not ClientState.IsRevealed(model)) or not ClientState.IsHeroVisible(model)) then
		return false
	end
	if kind == "Flag" and model:GetAttribute("FlagState") ~= "Intact" then
		return false
	end
	return true
end

-- Nearest valid enemy to `point` within `range` of the hero. Heroes are preferred,
-- structures (flags/ruins) only when no unit is available.
local function findTarget(point, range, unitsOnly)
	local root = myRoot()
	if not root then
		return nil
	end
	local best, bestScore = nil, math.huge
	for _, tag in ipairs(TARGET_TAGS) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			local targetRoot = modelRoot(model)
			if targetRoot and isEnemy(model, unitsOnly) then
				local fromHero = Util.FlatDistance(targetRoot.Position, root.Position)
				if fromHero <= range + 2 then
					local kind = model:GetAttribute("Kind")
					local score = Util.FlatDistance(targetRoot.Position, point)
					if kind == "Hero" then
						score -= 4
					elseif not UNIT_KINDS[kind] then
						score += 30
					end
					if score < bestScore then
						best, bestScore = model, score
					end
				end
			end
		end
	end
	return best
end

local function facingPoint(distance)
	local root = myRoot()
	if not root then
		return nil
	end
	local look = Util.Flat(CombatController.GetAim() - root.Position)
	if look.Magnitude < 0.5 then
		look = Util.Flat(root.CFrame.LookVector)
	end
	return root.Position + look.Unit * distance
end

-- Resolves what Q/E/R currently do (E/R read the equipped mythic slots).
-- skill buttons: Q (class), E / R (mythic slots), M2 (boot slot = right mouse on desktop)
local SKILL_KEYS = { "Q", "E", "R", "M2" }

local function getSlotInfo(key)
	local me = ClientState.GetMe()
	local character = ClientState.GetLocalCharacter()
	local now = workspace:GetServerTimeNow()
	if key == "Q" then
		local classDef = me and ClassDefinitions.Get(me.ClassKey)
		if not classDef then
			return nil
		end
		-- Royale: the Q skill is the looted one (none yet = no Q button content)
		local skillClass = me.Skill and me.Skill ~= "" and ClassDefinitions.Get(me.Skill) or nil
		local ability = ClassDefinitions.GetAbility(me.ClassKey, me.Skill)
		if not ability then
			return nil
		end
		classDef = skillClass or classDef
		return {
			Name = ability.Name, Color = classDef.Color, Cooldown = ability.Cooldown,
			Remaining = ((character and character:GetAttribute("AbilityReadyAt")) or 0) - now,
			Range = ability.CastRange or ability.DashDistance or ability.Range or 18,
			Radius = ability.Radius, Targeting = SELF_CAST_Q[ability.Key] and "Self" or "Point",
			Glyph = classDef.Icon,
			GlyphImage = classDef.IconImage,
		}
	end
	local item, ability = CombatController.GetSlotItem(key)
	if not item or not ability then
		return nil
	end
	return {
		Name = ability.Name, Color = ability.Color, Cooldown = ability.Cooldown,
		Remaining = CombatController.GetItemReadyAt(item.Id) - now,
		Range = ability.Range or 14, Radius = ability.Radius, Targeting = ability.Targeting, Item = item,
	}
end

-- World aim indicator ----------------------------------------------------------------
local function indicatorPart(name, shape)
	local part = indicator[name]
	if not part then
		part = Instance.new("Part")
		part.Name = "RF_MobileAim_" .. name
		part.Shape = shape or Enum.PartType.Block
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Parent = workspace.CurrentCamera
		indicator[name] = part
	end
	return part
end

local function hideIndicator()
	for _, part in pairs(indicator) do
		part.Transparency = 1
	end
	if targetHighlight then
		targetHighlight.Enabled = false
	end
end

local function showHighlight(model, color)
	if not targetHighlight then
		targetHighlight = Instance.new("Highlight")
		targetHighlight.Name = "RF_MobileTarget"
		targetHighlight.FillTransparency = 0.6
		targetHighlight.OutlineColor = Color3.fromRGB(255, 220, 120)
		targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		targetHighlight.Parent = workspace.CurrentCamera
	end
	targetHighlight.Adornee = model
	targetHighlight.FillColor = color or Color3.fromRGB(255, 60, 60)
	targetHighlight.Enabled = model ~= nil
end

local FLAT = CFrame.Angles(0, 0, math.rad(90))
local function drawIndicator(info, aim, cancelling)
	local root = myRoot()
	if not root then
		hideIndicator()
		return
	end
	local color = cancelling and Color3.fromRGB(230, 60, 50) or info.Color
	local origin = Vector3.new(root.Position.X, 0.35, root.Position.Z)
	local rangeRing = indicatorPart("Range", Enum.PartType.Cylinder)
	rangeRing.Color = color
	rangeRing.Size = Vector3.new(0.1, info.Range * 2, info.Range * 2)
	rangeRing.CFrame = CFrame.new(origin) * FLAT
	rangeRing.Transparency = 0.82
	if info.Targeting == "Self" or not aim then
		if indicator.Line then
			indicator.Line.Transparency = 1
		end
		if indicator.Spot then
			indicator.Spot.Transparency = 1
		end
		return
	end
	local target = Vector3.new(aim.X, 0.4, aim.Z)
	local length = (target - origin).Magnitude
	local line = indicatorPart("Line")
	line.Color = color
	if length > 0.2 then
		line.Size = Vector3.new(0.45, 0.08, length)
		line.CFrame = CFrame.lookAt((origin + target) / 2, target)
		line.Transparency = 0.35
	else
		line.Transparency = 1
	end
	local spot = indicatorPart("Spot", Enum.PartType.Cylinder)
	local radius = info.Radius or 2
	spot.Color = color
	spot.Size = Vector3.new(0.12, radius * 2, radius * 2)
	spot.CFrame = CFrame.new(target) * FLAT
	spot.Transparency = 0.55
end

-- Buttons --------------------------------------------------------------------------------
local function roundButton(name, size, center, parent)
	local frame = New("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = MEDIEVAL.WoodLight, BackgroundTransparency = 0.05, Active = true, Parent = parent })
	New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	local stroke = New("UIStroke", { Color = MEDIEVAL.Trim, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(140, 120, 105)), Parent = frame })
	local cooldown = New("Frame", { Name = "Cooldown", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, Visible = false, ZIndex = 4, Parent = frame })
	New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = cooldown })
	local timer = Label({ Name = "Timer", Text = "", Font = FONTS.Title, TextSize = math.floor(size * 0.36), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = frame })
	return { Frame = frame, Stroke = stroke, Cooldown = cooldown, Timer = timer, Size = size }
end

local function keyTag(entry, text)
	local tag = New("Frame", { Name = "KeyTag", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(22, 16), BackgroundColor3 = MEDIEVAL.Wood, ZIndex = 6, Parent = entry.Frame })
	New("UICorner", { CornerRadius = UDim.new(0, 4), Parent = tag })
	New("UIStroke", { Color = MEDIEVAL.Trim, Thickness = 1, Parent = tag })
	Label({ Text = text, Font = FONTS.Title, TextSize = 11, TextColor3 = MEDIEVAL.TrimBright, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = tag })
end

local function overButton(entry, position)
	local topLeft, size = entry.Frame.AbsolutePosition, entry.Frame.AbsoluteSize
	return position.X >= topLeft.X and position.X <= topLeft.X + size.X and position.Y >= topLeft.Y and position.Y <= topLeft.Y + size.Y
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "RuinfallMobile"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	cluster = New("Frame", { Name = "Cluster", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12), Size = UDim2.fromOffset(340, 300), BackgroundTransparency = 1, Parent = gui })
	local uiScale = New("UIScale", { Parent = cluster })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(viewport.Y / 430, 0.72, 1.35)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local attackCenter = Vector2.new(272, 232)
	-- ATTACK
	local attack = roundButton("Attack", 104, attackCenter, cluster)
	attack.Frame.BackgroundColor3 = MEDIEVAL.Crimson:Lerp(Color3.new(0, 0, 0), 0.25)
	local swordIcon = ShopDefinitions.Get("Power") and ShopDefinitions.Get("Power").Icon or ""
	New("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = swordIcon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.72, 0.72), ZIndex = 2, Parent = attack.Frame })
	Label({ Name = "Caption", Text = "ATTACK", Font = FONTS.Title, TextSize = 12, TextColor3 = MEDIEVAL.TrimBright, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, 0, 0, 14), ZIndex = 3, Parent = attack.Frame })
	buttons.Attack = attack

	-- Q / E / R arc around the attack button
	local offsets = { Q = Vector2.new(-122, 12), E = Vector2.new(-96, -88), R = Vector2.new(-10, -124), M2 = Vector2.new(-192, -40) }
	for _, key in ipairs(SKILL_KEYS) do
		local entry = roundButton(key, key == "M2" and 62 or 72, attackCenter + offsets[key], cluster)
		if key == "Q" then
			entry.Glyph = Label({ Name = "Glyph", Text = "", Font = FONTS.Title, TextSize = 26, TextColor3 = MEDIEVAL.Parchment, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0.6, 0), Position = UDim2.fromScale(0, 0.08), ZIndex = 2, Parent = entry.Frame })
			entry.Emblem = New("ImageLabel", { Name = "ClassEmblem", BackgroundTransparency = 1, Image = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(44, 44), ZIndex = 2, Parent = entry.Frame })
		else
			entry.IconView = UITheme.ItemIcon({ Name = "ItemIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(40, 40), ZIndex = 2, Parent = entry.Frame })
		end
		entry.Name = Label({ Name = "AbilityName", Text = "", Font = FONTS.Bold, TextSize = 9, TextColor3 = MEDIEVAL.Parchment, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(92, 12), ZIndex = 3, Parent = entry.Frame })
		keyTag(entry, key == "M2" and "BT" or key)
		entry.Key = key
		buttons[key] = entry
	end

	-- utility buttons
	local swap = roundButton("Swap", 40, attackCenter + Vector2.new(-150, -150), cluster)
	Label({ Text = "SWAP", Font = FONTS.Title, TextSize = 10, TextColor3 = MEDIEVAL.TrimBright, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = swap.Frame })
	buttons.Swap = swap
	local shop = roundButton("Shop", 52, attackCenter + Vector2.new(-218, 44), cluster)
	shop.Frame.BackgroundColor3 = Color3.fromRGB(120, 88, 30)
	shop.Caption = Label({ Text = "SHOP", Font = FONTS.Title, TextSize = 12, TextColor3 = MEDIEVAL.TrimBright, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = shop.Frame })
	buttons.Shop = shop
	local cancel = roundButton("Cancel", 60, attackCenter + Vector2.new(-212, -118), cluster)
	cancel.Frame.BackgroundColor3 = Color3.fromRGB(110, 25, 25)
	cancel.Frame.Visible = false
	Label({ Text = "CANCEL", Font = FONTS.Title, TextSize = 11, TextColor3 = Color3.fromRGB(255, 220, 210), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = cancel.Frame })
	buttons.Cancel = cancel
end

-- Casting -------------------------------------------------------------------------------
local function beginAim(key, input)
	local info = getSlotInfo(key)
	if not info then
		if key == "M2" then
			ClientState.LocalMessage:Fire("Boot slot is empty - tap SHOP to buy boots", "Info")
		else
			ClientState.LocalMessage:Fire(string.format("%s: mythic slot %d is empty - tap SHOP to buy a Mythic item", key, key == "E" and 1 or 2), "Info")
		end
		return
	end
	if info.Remaining > 0.1 then
		CombatController.AbilityDenied:Fire("Cooldown")
		return
	end
	aiming = { Key = key, Input = input, Start = Vector2.new(input.Position.X, input.Position.Y), Dragging = false, Info = info }
end

local function updateAim(input)
	if not aiming or input ~= aiming.Input then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local offset = position - aiming.Start
	if not aiming.Dragging and offset.Magnitude < DRAG_THRESHOLD then
		return
	end
	aiming.Dragging = true
	buttons.Cancel.Frame.Visible = true
	local cancelling = overButton(buttons.Cancel, position)
	aiming.Cancelling = cancelling
	buttons.Cancel.Stroke.Color = cancelling and Color3.fromRGB(255, 120, 100) or MEDIEVAL.Trim
	local root = myRoot()
	if not root then
		return
	end
	local info = aiming.Info
	if info.Targeting == "Self" then
		drawIndicator(info, nil, cancelling)
		return
	end
	-- screen drag -> world direction (camera-relative, flattened)
	local camera = workspace.CurrentCamera
	local right = Util.Flat(camera.CFrame.RightVector)
	local forward = Util.Flat(camera.CFrame.LookVector)
	right = right.Magnitude > 0 and right.Unit or Vector3.new(1, 0, 0)
	forward = forward.Magnitude > 0 and forward.Unit or Vector3.new(0, 0, -1)
	local direction = right * offset.X - forward * offset.Y
	local fraction = math.clamp(offset.Magnitude / DRAG_RADIUS, 0.15, 1)
	local aim = root.Position + (direction.Magnitude > 0 and direction.Unit or forward) * info.Range * fraction
	aiming.Aim = aim
	if info.Targeting == "Unit" then
		aiming.Target = findTarget(aim, info.Range, true)
		showHighlight(aiming.Target, cancelling and Color3.fromRGB(120, 120, 120) or nil)
		if aiming.Target then
			local targetRoot = modelRoot(aiming.Target)
			aim = targetRoot and targetRoot.Position or aim
		end
	end
	drawIndicator(info, aim, cancelling)
end

local function releaseAim(input)
	if not aiming or input ~= aiming.Input then
		return
	end
	local state = aiming
	aiming = nil
	buttons.Cancel.Frame.Visible = false
	hideIndicator()
	if state.Cancelling then
		return
	end
	local info = state.Info
	local root = myRoot()
	if not root then
		return
	end
	if info.Targeting == "Self" then
		CombatController.CastAbility(state.Key, facingPoint(8))
		return
	end
	if state.Dragging then
		CombatController.CastAbility(state.Key, state.Aim or facingPoint(8), state.Target)
		return
	end
	-- tap: auto-aim at the nearest enemy (prefer heroes)
	local target = findTarget(root.Position, info.Range + (info.Targeting == "Unit" and 0 or 4), true)
	if info.Targeting == "Unit" then
		CombatController.CastAbility(state.Key, target and modelRoot(target).Position or facingPoint(8), target)
	else
		local targetRoot = target and modelRoot(target)
		CombatController.CastAbility(state.Key, targetRoot and targetRoot.Position or facingPoint(math.min(info.Range, 10)))
	end
end

-- Frame update ------------------------------------------------------------------------
local function updateButtons()
	local inMatch = ClientState.GetMatchState() == STATE.ACTIVE or ClientState.GetMatchState() == STATE.STARTING
	local shopOpen = UIController.Shop and UIController.Shop.Root.Visible
	gui.Enabled = active and inMatch and not shopOpen
	if not gui.Enabled then
		return
	end
	local alive = ClientState.GetLocalCharacter() ~= nil
	for _, key in ipairs(SKILL_KEYS) do
		local entry = buttons[key]
		local info = getSlotInfo(key)
		if key == "Q" then
			entry.Emblem.Image = info and info.GlyphImage or ""
			entry.Glyph.Text = (info and info.GlyphImage) and "" or (info and info.Glyph or "?")
			entry.Frame.BackgroundColor3 = info and info.Color:Lerp(MEDIEVAL.Wood, 0.55) or MEDIEVAL.WoodLight
		else
			entry.IconView.Set(info and info.Item or nil)
		end
		entry.Name.Text = info and string.upper(info.Name) or "EMPTY"
		local remaining = info and info.Remaining or 0
		entry.Cooldown.Visible = (info == nil) or remaining > 0 or not alive
		entry.Timer.Text = (info and remaining > 0) and tostring(math.ceil(remaining)) or ""
		local isAiming = aiming and aiming.Key == key
		entry.Stroke.Color = isAiming and Color3.fromRGB(255, 120, 90) or ((info and remaining <= 0) and MEDIEVAL.TrimBright or MEDIEVAL.TrimDark)
	end
	buttons.Attack.Cooldown.Visible = not alive
	-- gold on the SHOP button (the character panel with the gold counter is hidden on touch)
	local me = ClientState.GetMe()
	local gold = me and me.Stats and me.Stats.Gold
	local caption = gold and string.format("SHOP\n%dg", math.floor(gold)) or "SHOP"
	if buttons.Shop.Caption.Text ~= caption then
		buttons.Shop.Caption.Text = caption
	end
end

local function stepAttack()
	if not attackTouch then
		return
	end
	local root = myRoot()
	local me = ClientState.GetMe()
	local classDef = me and ClassDefinitions.Get(me.ClassKey)
	if not root or not classDef then
		return
	end
	local range = (classDef.AttackRange or 8) + 4
	local target = findTarget(root.Position, range, false)
	local targetRoot = target and modelRoot(target)
	showHighlight(target, Color3.fromRGB(255, 80, 60))
	CombatController.SetAimOverride(targetRoot and targetRoot.Position or facingPoint(8), 0.3)
	CombatController.TryAttack()
end

-- Activation -----------------------------------------------------------------------------
local function setActive(enabled)
	if active == enabled then
		return
	end
	active = enabled
	CombatController.SetTouchMode(enabled)
	if UIController.HUD and UIController.HUD.SetMobileLayout then
		UIController.HUD:SetMobileLayout(enabled)
	end
	if not enabled then
		attackTouch = nil
		aiming = nil
		hideIndicator()
	end
end

local function shouldUseTouch()
	if player:GetAttribute("ForceMobileControls") ~= nil then
		return player:GetAttribute("ForceMobileControls") == true
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Public API ----------------------------------------------------------------------------
function MobileController.IsActive()
	return active
end

function MobileController.Init(clientState, combatController, uiController, cameraController)
	ClientState = clientState
	CombatController = combatController
	UIController = uiController
	CameraController = cameraController
	buildGui()

	-- button presses (touch, or mouse when forced on for testing)
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
	end
	buttons.Attack.Frame.InputBegan:Connect(function(input)
		if isPress(input) and not attackTouch then
			attackTouch = input
			buttons.Attack.Stroke.Color = MEDIEVAL.TrimBright
		end
	end)
	for _, key in ipairs(SKILL_KEYS) do
		buttons[key].Frame.InputBegan:Connect(function(input)
			if isPress(input) and not aiming then
				beginAim(key, input)
			end
		end)
	end
	buttons.Swap.Frame.InputBegan:Connect(function(input)
		if isPress(input) then
			ReplicatedStorage.Remotes.ItemRequest:FireServer("Swap")
		end
	end)
	buttons.Shop.Frame.InputBegan:Connect(function(input)
		if isPress(input) and UIController.Shop then
			UIController.Shop:SetVisible(not UIController.Shop.Root.Visible)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			if aiming and (input == aiming.Input or (aiming.Input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
				-- mouse drags report movement on a different input object; follow it
				if input ~= aiming.Input then
					aiming.Input = input
				end
				updateAim(input)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if attackTouch and (input == attackTouch or (input.UserInputType == Enum.UserInputType.MouseButton1 and attackTouch.UserInputType == Enum.UserInputType.MouseButton1)) then
			attackTouch = nil
			buttons.Attack.Stroke.Color = MEDIEVAL.Trim
			showHighlight(nil)
		end
		if aiming and (input == aiming.Input or (input.UserInputType == Enum.UserInputType.MouseButton1 and (aiming.Input.UserInputType == Enum.UserInputType.MouseMovement or aiming.Input.UserInputType == Enum.UserInputType.MouseButton1))) then
			aiming.Input = input
			releaseAim(input)
		end
	end)

	-- pinch to zoom
	UserInputService.TouchPinch:Connect(function(_, scale, _, state, gameProcessed)
		if not active or gameProcessed then
			return
		end
		if state == Enum.UserInputState.Begin then
			lastPinchScale = scale
		elseif lastPinchScale then
			CameraController.Zoom(-(scale - lastPinchScale) * 45)
			lastPinchScale = scale
			if state == Enum.UserInputState.End then
				lastPinchScale = nil
			end
		end
	end)

	-- device detection (switches live on hybrid devices)
	setActive(shouldUseTouch())
	UserInputService.LastInputTypeChanged:Connect(function()
		setActive(shouldUseTouch())
	end)
	player:GetAttributeChangedSignal("ForceMobileControls"):Connect(function()
		setActive(shouldUseTouch())
	end)

	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			updateButtons()
			stepAttack()
		end)
		if not ok then
			warn("[Ruinfall] Mobile controls error:", err)
		end
	end)
end

return MobileController
