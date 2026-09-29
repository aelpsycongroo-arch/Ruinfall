--[[
	AudioSettingsUI - the player's SETTINGS menu (small SETTINGS button, left side), three tabs:
	  AUDIO      volume sliders + music / SFX toggles (this file, AudioManager)
	  CONTROLS   rebind every hotkey (GameSettings: click a key, press the new one)
	  INTERFACE  HUD size (GameSettings)

	Sliders: Master, Music, SFX, Combat, Ambient, UI.  Toggles: Music ON/OFF, SFX ON/OFF.
	Changes apply instantly through AudioManager (SoundGroup volumes) and are saved on the
	server (AudioService, DataStore) so they persist between sessions. If saving is not
	available (e.g. Studio without API access) the settings still work for the session.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Constants
local SLIDERS = {
	{ Key = "Master", Label = "MASTER" },
	{ Key = "Music", Label = "MUSIC" },
	{ Key = "SFX", Label = "SOUND EFFECTS" },
	{ Key = "Combat", Label = "COMBAT" },
	{ Key = "Ambient", Label = "AMBIENT" },
	{ Key = "UI", Label = "INTERFACE" },
}
local TOGGLES = { { Key = "MusicEnabled", Label = "MUSIC" }, { Key = "SFXEnabled", Label = "SFX" } }
local SAVE_DELAY = 1.5
local player = Players.LocalPlayer

-- State
local AudioSettingsUI = {}
local ctx, Manager = nil, nil
local remote = nil
local sliderRefs, toggleRefs = {}, {}
local saveToken = 0
local panel = nil
local buildControls, buildInterface -- tab builders (defined below)

-- Theme (reuses the game's medieval palette when available)
local COLORS = {
	Wood = Color3.fromRGB(46, 32, 22), WoodLight = Color3.fromRGB(78, 56, 38), Trim = Color3.fromRGB(176, 136, 72),
	TrimBright = Color3.fromRGB(232, 196, 120), Parchment = Color3.fromRGB(236, 222, 190), Crimson = Color3.fromRGB(150, 40, 40),
	Off = Color3.fromRGB(70, 64, 58),
}
pcall(function()
	local UITheme = require(player:WaitForChild("PlayerScripts"):WaitForChild("UITheme"))
	for key, value in pairs(UITheme.Medieval or {}) do
		if typeof(value) == "Color3" then
			COLORS[key] = value
		end
	end
end)

local function new(className, properties, children)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken and remote then
			remote:FireServer("SaveSettings", Manager:GetSettings())
		end
	end)
end

local function refresh()
	local settings = Manager.Settings
	for key, refs in pairs(sliderRefs) do
		local value = settings[key] or 0
		refs.Fill.Size = UDim2.fromScale(value, 1)
		refs.Knob.Position = UDim2.new(value, 0, 0.5, 0)
		refs.Value.Text = string.format("%d%%", math.floor(value * 100 + 0.5))
	end
	for key, refs in pairs(toggleRefs) do
		local on = settings[key] ~= false
		refs.Button.Text = refs.Label .. (on and "  ON" or "  OFF")
		refs.Button.BackgroundColor3 = on and COLORS.Trim or COLORS.Off
		refs.Button.TextColor3 = on and COLORS.Wood or COLORS.Parchment
	end
end

local function buildSlider(parent, definition, order)
	local row = new("Frame", { Name = definition.Key, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = order, Parent = parent })
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(0.42, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = COLORS.Parchment, TextXAlignment = Enum.TextXAlignment.Left, Text = definition.Label, Parent = row,
	})
	local bar = new("TextButton", {
		Name = "Bar", AutoButtonColor = false, Text = "", BackgroundColor3 = COLORS.Wood, Size = UDim2.new(0.44, 0, 0, 10),
		Position = UDim2.new(0.42, 0, 0.5, -5), Parent = row,
	}, { corner(5), stroke(COLORS.Trim, 1) })
	bar:SetAttribute("NoAudio", true)
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = COLORS.Trim, Size = UDim2.fromScale(0.5, 1), BorderSizePixel = 0, Parent = bar }, { corner(5) })
	local knob = new("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = COLORS.TrimBright, Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromScale(0.5, 0.5), Parent = bar,
	}, { corner(8), stroke(COLORS.Wood, 2) })
	local value = new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.new(0.88, 0, 0, 0), Font = Enum.Font.GothamBold,
		TextSize = 13, TextColor3 = COLORS.TrimBright, TextXAlignment = Enum.TextXAlignment.Right, Text = "50%", Parent = row,
	})
	sliderRefs[definition.Key] = { Fill = fill, Knob = knob, Value = value }

	local dragging = false
	local function setFromX(x)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		alpha = math.floor(alpha * 20 + 0.5) / 20 -- 5% steps
		Manager:SetSetting(definition.Key, alpha)
		refresh()
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			Manager:Play("UI.Click")
			scheduleSave()
		end
	end)
end

-- CONTROLS tab: every rebindable action with its key; click a key, then press the new one
-- (Esc cancels). Choosing a key that another action uses swaps the two.
buildControls = function(panel, GameSettings)
	local Schema = GameSettings.Schema
	local page = new("ScrollingFrame", {
		Name = "Controls", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 1, -96),
		ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = panel,
	}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	local keyButtons = {}
	local capturing = nil
	local function refreshKeys()
		for action, button in pairs(keyButtons) do
			button.Text = capturing == action and "PRESS A KEY..." or GameSettings.Label(action)
			button.BackgroundColor3 = capturing == action and COLORS.Crimson or COLORS.WoodLight
		end
	end
	for order, action in ipairs(Schema.Actions) do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 34), LayoutOrder = order, Parent = page })
		new("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(0.62, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = COLORS.Parchment, TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(action.Label), Parent = row,
		})
		local button = new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.36, 0, 0, 30), BackgroundColor3 = COLORS.WoodLight,
			Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = COLORS.TrimBright, Text = "", Parent = row,
		}, { corner(6), stroke(COLORS.Trim, 1.5) })
		keyButtons[action.Key] = button
		button.Activated:Connect(function()
			capturing = action.Key
			GameSettings.Capturing = true
			refreshKeys()
		end)
	end
	local footer = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 60), LayoutOrder = 100, Parent = page })
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = COLORS.Parchment,
		TextTransparency = 0.3, TextWrapped = true, Text = "WASD move, left click attack and Esc are fixed. Esc cancels.", Parent = footer,
	})
	local reset = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(180, 30), BackgroundColor3 = COLORS.Crimson,
		Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = COLORS.Parchment, Text = "RESET TO DEFAULT", Parent = footer,
	}, { corner(6) })
	reset.Activated:Connect(function()
		capturing = nil
		GameSettings.Capturing = false
		GameSettings.ResetBinds()
		refreshKeys()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not capturing then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			capturing = nil
		else
			local name = GameSettings.InputName(input)
			if not name then
				return -- e.g. mouse movement / left click on the menu: keep waiting
			end
			if Schema.Reserved[name] then
				return -- movement / attack / menu keys cannot be rebound
			end
			if not GameSettings.SetBind(capturing, name) then
				return
			end
			Manager:Play("UI.Click")
			capturing = nil
		end
		task.defer(function()
			GameSettings.Capturing = capturing ~= nil -- after this key press has been ignored everywhere
		end)
		refreshKeys()
	end)
	GameSettings.Changed.Event:Connect(refreshKeys)
	refreshKeys()
	return page
end

-- INTERFACE tab: HUD size
buildInterface = function(panel, GameSettings)
	local Schema = GameSettings.Schema
	local page = new("Frame", { Name = "Interface", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 1, -96), Visible = false, Parent = panel })
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(0.4, 0, 0, 40), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = COLORS.Parchment,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "HUD SIZE", Parent = page,
	})
	local bar = new("TextButton", {
		Name = "Bar", AutoButtonColor = false, Text = "", BackgroundColor3 = COLORS.Wood, Size = UDim2.new(0.44, 0, 0, 10),
		Position = UDim2.new(0.4, 0, 0, 15), Parent = page,
	}, { corner(5), stroke(COLORS.Trim, 1) })
	bar:SetAttribute("NoAudio", true)
	local fill = new("Frame", { BackgroundColor3 = COLORS.Trim, Size = UDim2.fromScale(0.5, 1), BorderSizePixel = 0, Parent = bar }, { corner(5) })
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = COLORS.TrimBright, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromScale(0.5, 0.5), Parent = bar,
	}, { corner(8), stroke(COLORS.Wood, 2) })
	local value = new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(0.14, 0, 0, 40), Position = UDim2.new(0.86, 0, 0, 0), Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = COLORS.TrimBright, TextXAlignment = Enum.TextXAlignment.Right, Text = "100%", Parent = page,
	})
	new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 36), Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = COLORS.Parchment, TextTransparency = 0.3, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Scales the in-match HUD: ability bar, player panel, minimap and scoreboards.", Parent = page,
	})
	local reset = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(160, 30), BackgroundColor3 = COLORS.Crimson,
		Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = COLORS.Parchment, Text = "RESET TO 100%", Parent = page,
	}, { corner(6) })
	local range = Schema.HUD_SCALE_MAX - Schema.HUD_SCALE_MIN
	local function refreshScale()
		local scale = GameSettings.Settings.HudScale or 1
		local alpha = (scale - Schema.HUD_SCALE_MIN) / range
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		value.Text = string.format("%d%%", math.floor(scale * 100 + 0.5))
	end
	local dragging = false
	local function setFromX(x)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		local scale = Schema.HUD_SCALE_MIN + range * alpha
		GameSettings.SetHudScale(math.floor(scale * 20 + 0.5) / 20) -- 5% steps
		refreshScale()
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			Manager:Play("UI.Click")
		end
	end)
	reset.Activated:Connect(function()
		GameSettings.SetHudScale(1)
		refreshScale()
	end)
	GameSettings.Changed.Event:Connect(refreshScale)
	refreshScale()
	return page
end

local function build()
	local gui = new("ScreenGui", { Name = "RF_AudioSettings", ResetOnSpawn = false, DisplayOrder = 40, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local toggleButton = new("TextButton", {
		Name = "SettingsButton", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(12, 260), Size = UDim2.fromOffset(96, 30),
		BackgroundColor3 = COLORS.Wood, Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = COLORS.TrimBright, Text = "SETTINGS", Parent = gui,
	}, { corner(6), stroke(COLORS.Trim, 1.5) })
	-- sits under the HUD's top-left team / flag plaques (same 1500x900 layout scale as the HUD)
	local buttonScale = new("UIScale", { Parent = toggleButton })
	local function placeButton()
		local viewport = workspace.CurrentCamera.ViewportSize
		local s = math.min(viewport.X / 1500, viewport.Y / 900)
		buttonScale.Scale = math.max(s, 0.6)
		local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("MainHUD")
		local hudShown = hud ~= nil and hud:IsA("ScreenGui") and hud.Enabled
		if ReplicatedStorage:GetAttribute("ServerRole") == "Hub" or not hudShown then
			-- hub / pre-match lobby: bottom-left corner (their menus use the top-left)
			toggleButton.AnchorPoint = Vector2.new(0, 1)
			toggleButton.Position = UDim2.new(0, 14, 1, -24)
		else
			-- match: under MainHUD's TopLeft plaques + minion-wave line (48 px down, ~292 ref-px
			-- tall, scaled by s)
			toggleButton.AnchorPoint = Vector2.zero
			toggleButton.Position = UDim2.fromOffset(viewport.X * 4 / 1500 + 18 * s, 48 + 298 * s)
		end
	end
	placeButton()
	ReplicatedStorage:GetAttributeChangedSignal("ServerRole"):Connect(placeButton)
	-- follow the in-match HUD being shown / hidden (it is cloned in only on match servers)
	local function watchHud(child)
		if child.Name == "MainHUD" and child:IsA("ScreenGui") then
			child:GetPropertyChangedSignal("Enabled"):Connect(placeButton)
			placeButton()
		end
	end
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(watchHud)
	for _, child in ipairs(playerGui:GetChildren()) do
		watchHud(child)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeButton)
	panel = new("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 480),
		BackgroundColor3 = COLORS.Wood, Visible = false, Parent = gui,
	}, { corner(10), stroke(COLORS.Trim, 2.5) })
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = COLORS.TrimBright,
		Text = "SETTINGS", Parent = panel,
	})
	new("UIScale", { Name = "Fit", Parent = panel })
	local function fitPanel()
		local viewport = workspace.CurrentCamera.ViewportSize
		panel.Fit.Scale = math.clamp(math.min(viewport.X / 520, viewport.Y / 540), 0.55, 1)
	end
	fitPanel()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
	-- tabs
	local pages, tabButtons = {}, {}
	local tabBar = new("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 44), Size = UDim2.new(1, -40, 0, 30), Parent = panel }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	local function showTab(name)
		for key, page in pairs(pages) do
			page.Visible = key == name
			tabButtons[key].BackgroundColor3 = key == name and COLORS.Trim or COLORS.WoodLight
			tabButtons[key].TextColor3 = key == name and COLORS.Wood or COLORS.Parchment
		end
	end
	for order, name in ipairs({ "AUDIO", "CONTROLS", "INTERFACE" }) do
		local button = new("TextButton", {
			Name = name, LayoutOrder = order, Size = UDim2.fromOffset(128, 30), BackgroundColor3 = COLORS.WoodLight, Font = Enum.Font.GothamBlack,
			TextSize = 12, TextColor3 = COLORS.Parchment, Text = name, Parent = tabBar,
		}, { corner(6), stroke(COLORS.Trim, 1) })
		tabButtons[name] = button
		button.Activated:Connect(function()
			showTab(name)
		end)
	end
	local close = new("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = COLORS.Crimson, Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = COLORS.Parchment, Text = "X", Parent = panel,
	}, { corner(6) })
	local list = new("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 1, -96), Parent = panel }, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	for index, definition in ipairs(SLIDERS) do
		buildSlider(list, definition, index)
	end
	local toggleRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 20, Parent = list }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for _, definition in ipairs(TOGGLES) do
		local button = new("TextButton", {
			Name = definition.Key, Size = UDim2.fromOffset(150, 34), BackgroundColor3 = COLORS.Trim, Font = Enum.Font.GothamBlack,
			TextSize = 13, TextColor3 = COLORS.Wood, Text = definition.Label, Parent = toggleRow,
		}, { corner(6), stroke(COLORS.TrimBright, 1) })
		toggleRefs[definition.Key] = { Button = button, Label = definition.Label }
		button.Activated:Connect(function()
			Manager:SetSetting(definition.Key, not (Manager.Settings[definition.Key] ~= false))
			refresh()
			scheduleSave()
		end)
	end
	new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 30, Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = COLORS.Parchment, TextTransparency = 0.35, Text = "Settings are saved to your account", Parent = list,
	})
	pages.AUDIO = list
	local okSettings, GameSettings = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("GameSettings", 10))
	end)
	if okSettings and GameSettings then
		pages.CONTROLS = buildControls(panel, GameSettings)
		pages.INTERFACE = buildInterface(panel, GameSettings)
	else
		tabButtons.CONTROLS.Visible = false
		tabButtons.INTERFACE.Visible = false
	end
	showTab("AUDIO")
	local function setOpen(open)
		panel.Visible = open
		if not open and okSettings and GameSettings then
			GameSettings.Capturing = false
		end
		Manager:Play(open and "UI.MenuOpen" or "UI.MenuClose")
	end
	toggleButton:SetAttribute("NoAudio", true)
	close:SetAttribute("NoAudio", true)
	toggleButton.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and panel.Visible and not (okSettings and GameSettings and GameSettings.Capturing) then
			setOpen(false)
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	refresh()
end

function AudioSettingsUI.Init(context)
	ctx = context
	Manager = ctx.Manager
	build()
	Manager.SettingsChanged.Event:Connect(refresh)
	task.spawn(function()
		remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AudioEvent", 30)
		if not remote then
			return
		end
		remote.OnClientEvent:Connect(function(kind, payload)
			if kind == "Settings" and type(payload) == "table" then
				Manager:ApplySettings(payload)
			elseif kind == "Cue" and type(payload) == "table" and type(payload.Cue) == "string" then
				Manager:Play(payload.Cue, { Position = payload.Position, Source = "Server (private)" })
			end
		end)
		remote:FireServer("LoadSettings")
	end)
	return AudioSettingsUI
end

return AudioSettingsUI
