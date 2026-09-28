--[[
	HallMenuBuilder (edit-time tool) - builds ReplicatedStorage.HUD.HallMenu, the Ruinfall Hall
	(hub) menu, as real GUI objects in the same painted style as the in-match HUD plaques.
	StarterPlayerScripts.HubController clones it on hub servers and fills it with live lobby data;
	it never rebuilds the layout, so HallMenu can be edited or replaced by hand.

	Re-run from the command bar:  require(game.ServerStorage.HUDTools.HallMenuBuilder:Clone()).Build()
	Layout: 1500 x 900 reference screen, stored as Scale + UIAspectRatioConstraint per group.
	Inside a group, coordinates are pixels of the painted plaques (RefSize attribute).
]]

local Theme = require(game:GetService("StarterPlayer").StarterPlayerScripts:WaitForChild("HUD"):WaitForChild("Theme"):Clone())
local C, F, A = Theme.Colors, Theme.Fonts, Theme.Art
local REF = Theme.Reference
local K = 0.78 -- plaque pixels -> reference pixels (same scale as the in-match top plaques)

local Builder = {}

-- Button looks live in HUD.Theme.ButtonStyles (the HubController re-applies them at runtime)
Builder.ButtonStyles = Theme.ButtonStyles

local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function group(parent, name, w, h, anchor, pos, refSize)
	local frame = new("Frame", { Name = name, BackgroundTransparency = 1, AnchorPoint = anchor, Position = pos, Size = UDim2.fromScale(w / REF.X, h / REF.Y) }, parent)
	new("UIAspectRatioConstraint", { AspectRatio = w / h, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, frame)
	frame:SetAttribute("RefSize", refSize)
	return frame
end

local function refOf(g)
	local node = g
	while node and not node:GetAttribute("RefSize") do
		node = node.Parent
	end
	return node and node:GetAttribute("RefSize")
end

-- position/size of a rect given in the nearest RefSize space; `origin` shifts it when the
-- element is parented to a sub-frame that is itself placed inside that space
local function rect(g, x, y, w, h)
	local s = refOf(g)
	return UDim2.fromScale(x / s.X, y / s.Y), UDim2.fromScale(w / s.X, h / s.Y)
end

local function panel(g, name, x, y, w, h)
	local pos, size = rect(g, x, y, w, h)
	local f = new("Frame", { Name = name, BackgroundTransparency = 1, Position = pos, Size = size }, g)
	f:SetAttribute("RefSize", Vector2.new(w, h))
	return f
end

local function image(g, name, art, x, y, w, h, z, props)
	local pos, size = rect(g, x, y, w, h)
	local img = new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = art or "", Position = pos, Size = size, ZIndex = z or 1 }, g)
	for k, v in pairs(props or {}) do
		img[k] = v
	end
	return img
end

local function label(g, name, text, x, y, w, h, font, color, align, z, props)
	local pos, size = rect(g, x, y, w, h)
	local l = new("TextLabel", {
		Name = name, BackgroundTransparency = 1, Text = text, FontFace = font or F.Title, TextColor3 = color or C.Text,
		TextScaled = true, TextXAlignment = align or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Position = pos, Size = size, ZIndex = z or 4, TextStrokeTransparency = 0.55, TextStrokeColor3 = Color3.new(0, 0, 0),
	}, g)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- rounded, gold-rimmed button with the same sheen as the painted flag bars
local function button(g, name, text, x, y, w, h, style, z)
	local pos, size = rect(g, x, y, w, h)
	local s = Builder.ButtonStyles[style or "Primary"]
	local b = new("TextButton", {
		Name = name, Text = text, FontFace = F.Title, TextScaled = true, TextColor3 = s.Text, BackgroundColor3 = s.Fill,
		AutoButtonColor = true, Position = pos, Size = size, ZIndex = z or 5, BorderSizePixel = 0,
		TextStrokeTransparency = 0.7,
	}, g)
	b:SetAttribute("Style", style or "Primary")
	new("UICorner", { CornerRadius = UDim.new(0.28, 0) }, b)
	new("UIStroke", { Name = "Rim", Color = s.Stroke, Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 225)), ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(205, 205, 205)), ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)) }) }, b)
	new("UIPadding", { PaddingTop = UDim.new(0.24, 0), PaddingBottom = UDim.new(0.2, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) }, b)
	return b
end

-- the lion-banner plaque (title / war party header): base + banner tint + 2 text lines
local function bannerPlaque(g, name, x, y, caption, title, tint)
	local p = panel(g, name, x, y, 431, 221)
	image(p, "Frame", A.HallTitleBase, 0, 0, 431, 221, 1)
	image(p, "Tint", A.TopTeamTint, 0, 0, 431, 221, 2, { ImageColor3 = Theme.TintColor(tint) })
	label(p, "Caption", caption, 175, 50, 215, 25, F.Title, C.Text, nil, 4)
	label(p, "Heading", title, 175, 76.5, 215, 35, F.Title, Theme.TintColor(tint):Lerp(Color3.new(1, 1, 1), 0.08), nil, 4)
	return p
end

function Builder.Build(parent)
	if not parent then
		local rs = game:GetService("ReplicatedStorage")
		parent = rs:FindFirstChild("HUD") or Instance.new("Folder")
		parent.Name = "HUD"
		parent.Parent = rs
	end
	local old = parent:FindFirstChild("HallMenu")
	if old then
		old:Destroy()
	end
	local crimson = Color3.fromRGB(235, 70, 70)
	local ember = Color3.fromRGB(255, 120, 60)
	local gui = new("ScreenGui", { Name = "HallMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Global, Enabled = false }, nil)
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

	-- LEFT: title plaque + lobby board ---------------------------------------------------------
	local left = group(root, "LeftColumn", 443 * K, 775 * K, Vector2.new(0, 0), UDim2.new(8 / REF.X, 0, 0, 46), Vector2.new(443, 775))
	local title = bannerPlaque(left, "Title", 6, 0, "WELCOME TO THE", "RUINFALL HALL", crimson)
	local classes = panel(title, "Classes", 175, 124, 217, 40)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.04, 0), SortOrder = Enum.SortOrder.LayoutOrder }, classes)
	label(left, "Subtitle", "Walk to a gate and press E, or choose a lobby below", 12, 224, 420, 22, F.Body, C.Cream, Enum.TextXAlignment.Center, 4, { TextStrokeTransparency = 0.35 })

	local board = panel(left, "LobbyBoard", 0, 250, 443, 525)
	label(board, "Header", "LOBBIES", 18, 4, 160, 30, F.Title, C.GoldBright, nil, 4, { TextStrokeTransparency = 0.35 })
	local pos, size = rect(board, 140, 18, 290, 2)
	local rule = new("Frame", { Name = "Rule", BackgroundColor3 = C.Gold, BorderSizePixel = 0, Position = pos, Size = size, ZIndex = 3 }, board)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, rule)
	for i = 1, 4 do
		local card = panel(board, "Lobby" .. i, 0, 38 + (i - 1) * 112, 443, 149)
		image(card, "Frame", A.HallRowBase, 0, 0, 443, 149, 1)
		image(card, "Tint", A.TopFlagTint, 0, 0, 443, 149, 2, { ImageColor3 = Theme.TintColor(crimson) })
		local sp, ss = rect(card, 42, 28, 364, 92)
		local selected = new("Frame", { Name = "Selected", BackgroundColor3 = C.GoldBright, BackgroundTransparency = 0.9, Position = sp, Size = ss, ZIndex = 3, Visible = false }, card)
		new("UICorner", { CornerRadius = UDim.new(0.14, 0) }, selected)
		new("UIStroke", { Color = C.GoldBright, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, selected)
		label(card, "LobbyName", "LOBBY " .. i, 108, 35, 170, 28, F.Title, C.GoldBright, nil, 4)
		label(card, "Sub", "The Iron Gate", 108, 63, 170, 19, F.Body, C.Muted, nil, 4)
		label(card, "Info", "2 TEAM  |  0 / 18", 108, 83, 170, 21, F.Number, C.GoldBright, nil, 4)
		button(card, "Join", "JOIN", 284, 49, 108, 46, "Primary", 5)
	end

	-- RIGHT: your war party ------------------------------------------------------------------------
	local party = group(root, "WarParty", 443 * K, 785 * K, Vector2.new(1, 0), UDim2.new(1 - 8 / REF.X, 0, 0, 46), Vector2.new(443, 785))
	party.Visible = false
	local header = bannerPlaque(party, "Header", 6, 0, "YOUR WAR PARTY", "LOBBY II", ember)
	label(header, "Gate", "The Ember Gate", 175, 131, 150, 24, F.Body, C.Cream, nil, 4)
	label(header, "Count", "1 / 18", 318, 129, 74, 27, F.Number, C.GoldBright, Enum.TextXAlignment.Right, 4)
	local body = panel(party, "Panel", 0, 205, 443, 580)
	image(body, "Frame", A.HallTallBase, 0, 0, 443, 580, 1)
	image(body, "Tint", A.HallTallTint, 0, 0, 443, 580, 2, { ImageColor3 = Theme.TintColor(ember) })
	local lp, ls = rect(body, 52, 44, 339, 252)
	local list = new("ScrollingFrame", { Name = "Members", BackgroundTransparency = 1, Position = lp, Size = ls, ZIndex = 4, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Gold, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, body)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	-- one member row, cloned per member by the HubController (edit it to restyle every row)
	local row = new("Frame", { Name = "MemberTemplate", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, Size = UDim2.new(1, -8, 0, 30), Visible = false, ZIndex = 4, BorderSizePixel = 0 }, body)
	new("UICorner", { CornerRadius = UDim.new(0.2, 0) }, row)
	new("UIStroke", { Name = "Rim", Color = C.Gold, Thickness = 1, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
	new("TextLabel", { Name = "PlayerName", BackgroundTransparency = 1, Text = "Player", FontFace = F.BodyBold, TextScaled = true, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromScale(0.04, 0.18), Size = UDim2.fromScale(0.68, 0.64), ZIndex = 5 }, row)
	new("TextLabel", { Name = "Host", BackgroundTransparency = 1, Text = "HOST", FontFace = F.Title, TextScaled = true, TextColor3 = C.GoldBright, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.74, 0.2), Size = UDim2.fromScale(0.22, 0.6), ZIndex = 5, Visible = false }, row)
	label(body, "ModeTitle", "TEAM MODE", 56, 305, 200, 24, F.Title, C.GoldBright, nil, 4)
	for i = 1, 3 do
		button(body, "Mode" .. i, ({ "2 TEAM", "4 TEAM", "6 TEAM" })[i], 52 + (i - 1) * 115, 333, 109, 40, i == 1 and "Gold" or "Dark", 5)
	end
	label(body, "HostHint", "You are the host - pick a mode and march when ready", 52, 380, 339, 18, F.Body, C.Muted, Enum.TextXAlignment.Center, 4)
	button(body, "Start", "MARCH TO BATTLE", 52, 404, 339, 54, "Primary", 5)
	button(body, "Leave", "LEAVE LOBBY", 52, 468, 339, 38, "Danger", 5)
	label(body, "StudioNote", "Your party is teleported to its own battle server", 52, 514, 339, 16, F.Body, C.Muted, Enum.TextXAlignment.Center, 4)

	-- TOP CENTRE: notices (the little flag takes the notice colour) ---------------------------------
	local notice = group(root, "Notice", 443 * 0.66, 149 * 0.66, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 46), Vector2.new(443, 149))
	notice.Visible = false
	image(notice, "Frame", A.HallRowBase, 0, 0, 443, 149, 1)
	image(notice, "Tint", A.TopFlagTint, 0, 0, 443, 149, 2, { ImageColor3 = Theme.TintColor(C.GoldBright) })
	label(notice, "Message", "Joined Lobby II", 108, 38, 290, 72, F.BodyBold, C.Text, Enum.TextXAlignment.Center, 4, { TextWrapped = true })

	gui.Parent = parent
	return gui
end

return Builder
