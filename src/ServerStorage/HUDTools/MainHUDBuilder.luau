--[[
	MainHUDBuilder (edit-time tool) - builds ReplicatedStorage.HUD.MainHUD, the in-match HUD, as
	real GUI objects. Runtime scripts (StarterPlayerScripts.HUD) only bind data to these objects;
	they never rebuild the layout. (Not in StarterGui on purpose: it must not show in the hub.)

	Re-run from the command bar:  require(game.ServerStorage.HUDTools.MainHUDBuilder:Clone()).Build()
	All positions are authored on the 1500 x 900 reference screen and stored as Scale, with a
	UIAspectRatioConstraint per corner group, so proportions hold on 16:9 / 16:10 / 21:9 / mobile.
]]

-- require a fresh copy: Studio caches module results, so an edited Theme would otherwise be stale
local Theme = require(game:GetService("StarterPlayer").StarterPlayerScripts:WaitForChild("HUD"):WaitForChild("Theme"):Clone())
local C, F, A = Theme.Colors, Theme.Fonts, Theme.Art
local REF = Theme.Reference

local Builder = {}

-- Components -------------------------------------------------------------------------------
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- A corner group: sized in reference px, kept at its aspect ratio, anchored to a screen edge.
local function group(parent, name, w, h, anchor, pos)
	local frame = new("Frame", {
		Name = name, BackgroundTransparency = 1, AnchorPoint = anchor, Position = pos,
		Size = UDim2.fromScale(w / REF.X, h / REF.Y),
	}, parent)
	new("UIAspectRatioConstraint", { AspectRatio = w / h, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, frame)
	frame:SetAttribute("RefSize", Vector2.new(w, h))
	return frame
end

-- place(child) in its group's reference px
local function rect(g, x, y, w, h)
	local s = g:GetAttribute("RefSize") or g.Parent:GetAttribute("RefSize")
	return UDim2.fromScale(x / s.X, y / s.Y), UDim2.fromScale(w / s.X, h / s.Y)
end

local function image(g, name, art, x, y, w, h, z, props)
	local pos, size = rect(g, x, y, w, h)
	local img = new("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = art or "", Position = pos, Size = size, ZIndex = z or 1, ScaleType = Enum.ScaleType.Stretch }, g)
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

-- Metal-rimmed progress bar: Track (dark) > Fill (gradient) + Value text
local function bar(g, name, x, y, w, h, fill, z, withText)
	local pos, size = rect(g, x, y, w, h)
	local track = new("Frame", { Name = name, BackgroundColor3 = C.Track, Position = pos, Size = size, ZIndex = z or 3, BorderSizePixel = 0 }, g)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, track)
	new("UIStroke", { Color = C.Gold, Thickness = 1.2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, track)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)) }, track)
	local f = new("Frame", { Name = "Fill", BackgroundColor3 = fill, Size = UDim2.fromScale(1, 1), ZIndex = (z or 3) + 1, BorderSizePixel = 0 }, track)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 180)), ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 90, 90)) }) }, f)
	if withText then
		new("TextLabel", {
			Name = "Value", BackgroundTransparency = 1, Text = "", FontFace = F.Number, TextColor3 = C.Text, TextScaled = true,
			Size = UDim2.fromScale(1, 0.92), Position = UDim2.fromScale(0, 0.04), ZIndex = (z or 3) + 3, TextStrokeTransparency = 0.25,
		}, track)
	end
	return track
end

-- Cyan pill badge: [o] LABEL        value
local function chip(parent, name, text, value, w, order)
	local frame = new("Frame", { Name = name, BackgroundColor3 = Color3.fromRGB(6, 22, 26), BackgroundTransparency = 0.15, Size = UDim2.fromScale(w, 1), LayoutOrder = order, ZIndex = 4, BorderSizePixel = 0, Visible = true }, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	local stroke = new("UIStroke", { Name = "Stroke", Color = C.Cyan, Thickness = 1.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	local dot = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.09, 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Cyan, ZIndex = 5, BorderSizePixel = 0 }, frame)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, dot)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	new("UIStroke", { Color = Color3.fromRGB(180, 250, 255), Thickness = 1, Transparency = 0.3 }, dot)
	new("TextLabel", { Name = "Label", BackgroundTransparency = 1, Text = text, FontFace = F.Title, TextColor3 = C.Cyan, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromScale(0.19, 0.18), Size = UDim2.fromScale(0.56, 0.64), ZIndex = 5 }, frame)
	new("TextLabel", { Name = "Value", BackgroundTransparency = 1, Text = value, FontFace = F.Number, TextColor3 = C.Text, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.7, 0.2), Size = UDim2.fromScale(0.24, 0.6), ZIndex = 5 }, frame)
	return frame, stroke
end

local function banner(g, name, x, y, w, h, color, z)
	local holder = image(g, name, A.BannerCloth, x, y, w, h, z or 2, { ImageColor3 = color })
	new("ImageLabel", { Name = "Trim", BackgroundTransparency = 1, Image = A.BannerTrim, Size = UDim2.fromScale(1, 1), ZIndex = (z or 2) + 1 }, holder)
	return holder
end

-- Build ------------------------------------------------------------------------------------
function Builder.Build(parent)
	if not parent then
		local rs = game:GetService("ReplicatedStorage")
		parent = rs:FindFirstChild("HUD") or Instance.new("Folder")
		parent.Name = "HUD"
		parent.Parent = rs
	end
	local old = parent:FindFirstChild("MainHUD")
	if old then
		old:Destroy()
	end
	local gui = new("ScreenGui", { Name = "MainHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Global }, nil)
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local teamRed = Color3.fromRGB(190, 34, 42)
	local teamBlue = Color3.fromRGB(40, 104, 184)

	-- TOP LEFT: team plaque + own flag -----------------------------------------------------
	-- Painted plaques (Theme.Art.TopTeam* / TopFlag*), placed exactly as on the source sheet:
	-- coordinates in this group are pixels of that sheet (443 x 359, scaled by TOP_SCALE).
	local TOP_SCALE = 0.78
	local crimson, azure = Color3.fromRGB(235, 70, 70), Color3.fromRGB(70, 150, 255)
	local tl = group(root, "TopLeft", 443 * TOP_SCALE, 359 * TOP_SCALE, Vector2.new(0, 0), UDim2.new(4 / REF.X, 0, 0, 48))
	tl:SetAttribute("RefSize", Vector2.new(443, 359))
	local team = new("Frame", { Name = "TeamPanel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, tl)
	image(tl, "Frame", A.TopTeamBase, 1, 7, 431, 221, 1).Parent = team
	local teamTint = image(tl, "Tint", A.TopTeamTint, 1, 7, 431, 221, 2, { ImageColor3 = Theme.TintColor(crimson) })
	teamTint:SetAttribute("TeamTint", true)
	teamTint.Parent = team
	-- "TEAM" and the divider are painted; the team name, hourglass and timer are live.
	-- (text heights: the fonts' capitals are ~0.6 of the label height -> label = art cap / 0.6)
	label(tl, "TeamName", "CRIMSON", 176, 83.5, 220, 35, F.Title, Theme.TintColor(crimson), nil, 4).Parent = team
	image(tl, "Hourglass", A.TopHourglass, 171, 132, 34, 41, 3).Parent = team
	label(tl, "RuinLabel", "Next Ruin", 212, 140, 118, 25, F.Title, C.GoldBright, nil, 4).Parent = team
	label(tl, "RuinTime", "0:46", 318, 140, 74, 25, F.Number, Color3.fromRGB(255, 212, 70), Enum.TextXAlignment.Right, 4).Parent = team

	local flag = new("Frame", { Name = "FlagPanel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, tl)
	image(tl, "Frame", A.TopFlagBase, 0, 210, 443, 149, 1).Parent = flag
	local flagTint = image(tl, "Tint", A.TopFlagTint, 0, 210, 443, 149, 2, { ImageColor3 = Theme.TintColor(crimson) })
	flagTint:SetAttribute("TeamTint", true)
	flagTint.Parent = flag
	-- "YOUR FLAG" and the little flag are painted; value + bar are live
	label(tl, "Value", "2500 / 2500", 270, 252.5, 124, 23, F.Number, C.Text, Enum.TextXAlignment.Right, 4).Parent = flag
	bar(tl, "Bar", 115, 287, 279, 13, Theme.TintColor(crimson), 3, false).Parent = flag
	label(tl, "MinionWave", "Minion wave 0:18  |  Lv 1", 24, 357, 380, 17, F.Body, C.Muted, nil, 4, { TextStrokeTransparency = 0.7 })

	-- TOP CENTER: scoreboard ----------------------------------------------------------------
	-- Painted plaque (Theme.Art.Score*), 764 x 202 px. Team names, alive counts, flag bars and
	-- flag numbers were erased from the art and are drawn here at the same places.
	-- One plaque shows two teams (Left / Right). 4- and 6-team modes add copies of the same
	-- plaque (Scoreboard2 = teams 3-4, Scoreboard3 = teams 5-6) in a row under it; the HUD
	-- recolours every side with its team's colour.
	local function fillPlaque(sb, colors, names)
		image(sb, "Frame", A.ScoreBase, 0, 0, 764, 202, 1)
		for _, side in ipairs({ "Left", "Right" }) do
			local left = side == "Left"
			local color = left and colors[1] or colors[2]
			local s = new("Frame", { Name = side, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, sb)
			image(sb, "Tint", left and A.ScoreTintL or A.ScoreTintR, 0, 0, 764, 202, 2, { ImageColor3 = Theme.TintColor(color) }).Parent = s
			if left then
				label(sb, "TeamName", names[1], 176, 60, 124, 23, F.Title, Theme.TeamNameColor(color), nil, 4).Parent = s
				label(sb, "Alive", "1/1", 281, 60.5, 50, 24, F.Number, C.Text, Enum.TextXAlignment.Right, 4).Parent = s
			else
				label(sb, "TeamName", names[2], 478, 60, 100, 23, F.Title, Theme.TeamNameColor(color), Enum.TextXAlignment.Right, 4).Parent = s
				label(sb, "Alive", "1/1", 433, 60.5, 50, 24, F.Number, C.Text, Enum.TextXAlignment.Left, 4).Parent = s
			end
			-- flag-health bar inside the painted rim (the fill shrinks towards the team's banner)
			local bpos, bsize = rect(sb, left and 154 or 429, 92.5, left and 178 or 177, 15)
			local track = new("Frame", { Name = "Bar", BackgroundTransparency = 1, Position = bpos, Size = bsize, ZIndex = 3 }, s)
			local fill = new("Frame", { Name = "Fill", BackgroundColor3 = Theme.TintColor(color), AnchorPoint = Vector2.new(left and 0 or 1, 0), Position = UDim2.fromScale(left and 0 or 1, 0), Size = UDim2.fromScale(1, 1), ZIndex = 3, BorderSizePixel = 0 }, track)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 205)), ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(205, 205, 205)), ColorSequenceKeypoint.new(1, Color3.fromRGB(165, 165, 165)) }) }, fill)
			label(sb, "Flag", "Flag 2500", left and 152 or 433, 115.5, 172, 23, F.BodyBold, C.Cream, Enum.TextXAlignment.Center, 4).Parent = s
		end
	end
	local sb = group(root, "Scoreboard", 764 * TOP_SCALE, 202 * TOP_SCALE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 2 / REF.Y))
	sb:SetAttribute("RefSize", Vector2.new(764, 202))
	fillPlaque(sb, { crimson, azure }, { "CRIMSON", "AZURE" })

	-- extra plaques (hidden until a match has 3+ teams), centred in a row under the main one
	local EXTRA_SCALE = 0.64
	local ew, eh = 764 * TOP_SCALE * EXTRA_SCALE, 202 * TOP_SCALE * EXTRA_SCALE
	local boards = group(root, "ExtraBoards", ew * 2 + 8, eh, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 138 / REF.Y))
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(8 / (ew * 2 + 8), 0), SortOrder = Enum.SortOrder.LayoutOrder }, boards)
	local extraTeams = {
		{ Color3.fromRGB(70, 210, 120), Color3.fromRGB(245, 200, 60), "VERDANT", "GILDED" },
		{ Color3.fromRGB(175, 110, 255), Color3.fromRGB(255, 140, 50), "VIOLET", "EMBER" },
	}
	for i, def in ipairs(extraTeams) do
		local plaque = new("Frame", { Name = "Scoreboard" .. (i + 1), BackgroundTransparency = 1, Size = UDim2.fromScale(ew / (ew * 2 + 8), 1), LayoutOrder = i + 1, Visible = false }, boards)
		plaque:SetAttribute("RefSize", Vector2.new(764, 202))
		fillPlaque(plaque, { def[1], def[2] }, { def[3], def[4] })
	end
	local extra = new("Frame", { Name = "ExtraTeams", BackgroundTransparency = 1, Position = UDim2.fromScale(0.15, 0.97), Size = UDim2.fromScale(0.7, 0.14), Visible = false }, sb)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }, extra)

	-- TOP RIGHT: minimap (MinimapController draws into MapHolder) ---------------------------
	-- Border art (Theme.Art.MinimapBorder*) is 440 x 454; coordinates below are in its pixels.
	-- Its red accents live in the white MinimapBorderTint image, recoloured with the team colour.
	local mm = group(root, "Minimap", 300, 300 * 454 / 440, Vector2.new(1, 0), UDim2.new(1 - 4 / REF.X, 0, 2 / REF.Y, 0))
	mm:SetAttribute("RefSize", Vector2.new(440, 454))
	local pos, size = rect(mm, 224 - 176, 222 - 176, 352, 352) -- the round hole, slightly under the rim
	local holder = new("CanvasGroup", { Name = "MapHolder", BackgroundColor3 = Color3.fromRGB(28, 26, 24), Position = pos, Size = size, ZIndex = 1, BorderSizePixel = 0 }, mm)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, holder)
	image(mm, "Frame", A.MinimapBorder, 0, 0, 440, 454, 3)
	image(mm, "FrameTint", A.MinimapBorderTint, 0, 0, 440, 454, 4, { ImageColor3 = teamRed }):SetAttribute("TeamTint", true)
	-- zoom: two small bronze-rimmed medallions tucked under the bottom-right corner
	for _, b in ipairs({ { "ZoomOut", 318, false }, { "ZoomIn", 370, true } }) do
		local p, s = rect(mm, b[2], 410, 44, 44)
		local btn = new("ImageButton", { Name = b[1], BackgroundColor3 = C.Black, BackgroundTransparency = 0.08, Image = "", Position = p, Size = s, ZIndex = 6, AutoButtonColor = true, BorderSizePixel = 0 }, mm)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, btn)
		new("UIStroke", { Color = C.Gold, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
		local function stroke(w, h)
			local f = new("Frame", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(w, h), BackgroundColor3 = C.GoldBright, BorderSizePixel = 0, ZIndex = 7 }, btn)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
		end
		stroke(0.5, 0.12)
		if b[3] then
			stroke(0.12, 0.5)
		end
	end

	-- BOTTOM: portrait + class / health / buffs + LM / Q / E / R / MR + PASSIVE 1-3 ---------------
	-- One piece of art (Theme.Art.Bottom*), split in two tiles each for resolution. The *Tint
	-- tiles hold only the red accents in white: the HUD colours them with the team colour
	-- (any ImageLabel with the attribute TeamTint = true is recoloured the same way).
	-- Coordinates inside BottomHUD are in pixels of that art (1627 x 353).
	local bh = group(root, "BottomHUD", 1088, 236, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1 - 2 / REF.Y))
	bh:SetAttribute("RefSize", Vector2.new(1627, 353))
	local ART_W = 815
	image(bh, "ArtLeft", A.BottomBaseL, 0, 0, ART_W, 353, 3)
	image(bh, "ArtRight", A.BottomBaseR, 812, 0, ART_W, 353, 3):SetAttribute("DesktopOnly", true)
	image(bh, "TintLeft", A.BottomTintL, 0, 0, ART_W, 353, 4, { ImageColor3 = teamRed }):SetAttribute("TeamTint", true)
	local tr = image(bh, "TintRight", A.BottomTintR, 812, 0, ART_W, 353, 4, { ImageColor3 = teamRed })
	tr:SetAttribute("TeamTint", true)
	tr:SetAttribute("DesktopOnly", true)

	local pi = new("Frame", { Name = "PlayerInfo", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, bh)
	local p2, s2 = rect(bh, 74.5, 82, 214, 214)
	local portrait = new("Frame", { Name = "Portrait", BackgroundColor3 = Color3.fromRGB(150, 60, 50), Position = p2, Size = s2, ZIndex = 1, BorderSizePixel = 0 }, pi)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, portrait)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(90, 80, 75)) }, portrait)
	new("ImageLabel", { Name = "Emblem", BackgroundTransparency = 1, Image = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), ZIndex = 1 }, portrait)
	local avatar = new("ImageLabel", { Name = "Avatar", BackgroundTransparency = 1, Image = "", Size = UDim2.fromScale(1, 1), ZIndex = 2 }, portrait)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, avatar)
	local p5, s5 = rect(bh, 58, 230, 68, 66)
	local badge = new("Frame", { Name = "LevelBadge", BackgroundTransparency = 1, Position = p5, Size = s5, ZIndex = 6 }, pi)
	new("TextLabel", { Name = "Level", BackgroundTransparency = 1, Text = "8", FontFace = F.Number, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.55, 0.55), ZIndex = 7, TextStrokeTransparency = 0.4 }, badge)
	label(bh, "ClassName", "FIGHTER", 334, 166, 300, 34, F.Title, C.Text, nil, 6).Parent = pi
	label(bh, "Role", "Balanced Bruiser", 336, 201, 300, 22, F.Body, C.Muted, nil, 6, { TextStrokeTransparency = 0.8 }).Parent = pi
	local p3, s3 = rect(bh, 658, 170, 124, 26)
	local gold = new("Frame", { Name = "Gold", BackgroundTransparency = 1, Position = p3, Size = s3, ZIndex = 6 }, pi)
	local coin = new("Frame", { Name = "Coin", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.16, 0.82), BackgroundColor3 = C.GoldBright, ZIndex = 7, BorderSizePixel = 0 }, gold)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, coin)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, coin)
	new("UIStroke", { Color = Color3.fromRGB(110, 76, 30), Thickness = 1.2 }, coin)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 248, 210), Color3.fromRGB(180, 120, 40)) }, coin)
	new("TextLabel", { Name = "Value", BackgroundTransparency = 1, Text = "0", FontFace = F.Number, TextColor3 = C.GoldBright, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.8, 1), ZIndex = 7, TextStrokeTransparency = 0.5 }, gold)
	local hp = bar(bh, "HealthBar", 334, 229, 448, 24, C.Red, 6, true)
	hp.Parent = pi
	hp.Value.Text = "786 / 850"
	local shield = new("Frame", { Name = "Shield", BackgroundColor3 = Color3.fromRGB(150, 210, 255), Size = UDim2.fromScale(0, 0.3), ZIndex = 8, BorderSizePixel = 0, Visible = false }, hp)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shield)
	-- mana (only E / R item skills cost mana): thin blue bar under the health bar
	local mana = bar(bh, "ManaBar", 334, 256, 448, 12, C.Mana, 6, true)
	mana.Parent = pi
	mana.BackgroundColor3 = C.ManaTrack
	mana.Value.Text = "300 / 300"
	local p4, s4 = rect(bh, 334, 271, 448, 25)
	local chips = new("Frame", { Name = "Chips", BackgroundTransparency = 1, Position = p4, Size = s4, ZIndex = 6 }, pi)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, chips)
	for _, c in ipairs({ { "Buff", "SPEED CORE", "52s", 0.47, 1 }, { "Fragment", "CORE FRAGMENT", "", 0.5, 2 }, { "Status", "STUNNED", "", 0.3, 3 } }) do
		local f = chip(chips, c[1], c[2], c[3], c[4], c[5])
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex += 3
			end
		end
		f.ZIndex += 3
		f.Visible = c[1] ~= "Status"
	end

	-- combat / item controls: slot boxes and key tabs (LM Q E R MR) are part of the art
	local ab = new("Frame", { Name = "AbilityBar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, bh)
	ab:SetAttribute("DesktopOnly", true)
	local boxes = { { 885, 990 }, { 1021, 1128 }, { 1157, 1265 }, { 1296, 1402 } }
	local icons = { A.IconMelee, A.IconBloodRush, A.IconItem, A.IconItem, A.IconBoots }
	-- Right compartment (art x 1428..1577) is a 2 x 2 grid of small framed cells (62 x 62 art px,
	-- frames painted in the art): top-left = BOOTS (MR, with its own small key tab), the other
	-- three = PASSIVE 1 / 2 / 3. GRID.Boots = boots cell, GRID[1..3] = passive cells (top-left px).
	local CELL = 62
	local GRID = { Boots = { 1435, 148 }, { 1503, 148 }, { 1435, 216 }, { 1503, 216 } }
	for i, def in ipairs(Theme.Slots) do
		local small = def.Key == "MR"
		local p, s, cx
		if small then
			local cell = GRID.Boots
			cx = cell[1] + CELL / 2
			p, s = rect(bh, cell[1] + 3, cell[2] + 3, CELL - 6, CELL - 6)
		else
			local x0, x1 = boxes[i][1], boxes[i][2]
			cx = (x0 + x1) / 2
			p, s = rect(bh, x0 + 4, 158, x1 - x0 - 8, 93)
		end
		local slot = new("Frame", { Name = "Slot" .. def.Key, BackgroundTransparency = 1, BorderSizePixel = 0, Position = p, Size = s, ZIndex = 6 }, ab)
		slot:SetAttribute("Key", def.Key)
		slot:SetAttribute("Kind", def.Kind)
		new("UICorner", { CornerRadius = UDim.new(0.06, 0) }, slot)
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icons[i], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.78), ScaleType = Enum.ScaleType.Fit, ZIndex = 6, ImageTransparency = def.Kind == "Item" and 0.55 or 0 }, slot)
		new("TextLabel", { Name = "Glyph", BackgroundTransparency = 1, Text = "", FontFace = F.Title, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), ZIndex = 6, Visible = false }, slot)
		local cd = new("Frame", { Name = "Cooldown", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 7, BorderSizePixel = 0 }, slot)
		new("UICorner", { CornerRadius = UDim.new(0.06, 0) }, cd)
		new("TextLabel", { Name = "Timer", BackgroundTransparency = 1, Text = "", FontFace = F.Number, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.45), ZIndex = 8, TextStrokeTransparency = 0.2 }, slot)
		local count = new("Frame", { Name = "Count", BackgroundColor3 = Color3.fromRGB(14, 10, 8), AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(0.97, 0.97), Size = UDim2.fromScale(0.28, 0.26), ZIndex = 8, BorderSizePixel = 0, Visible = false }, slot)
		new("UIStroke", { Color = C.Gold, Thickness = 1 }, count)
		new("TextLabel", { Name = "Value", BackgroundTransparency = 1, Text = "", FontFace = F.Number, TextColor3 = C.Text, TextScaled = true, Size = UDim2.fromScale(1, 1), ZIndex = 9 }, count)
		new("UIStroke", { Name = "Ready", Color = C.GoldBright, Thickness = 1.5, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, slot)
		-- key letters are drawn in the art; these labels are optional overrides (empty = art shows)
		if small then
			label(bh, "Key" .. def.Key, "", cx - 18, 130, 36, 20, F.Title, C.Text, Enum.TextXAlignment.Center, 9).Parent = ab
			-- no room for a name line under the small cell: the boots name shows in the hover tooltip
			label(bh, "Name" .. def.Key, def.Name, cx - 70, 263, 140, 26, F.Title, C.Text, Enum.TextXAlignment.Center, 6, { Visible = false }).Parent = ab
		else
			label(bh, "Key" .. def.Key, "", cx - 24, 132, 48, 28, F.Title, C.Text, Enum.TextXAlignment.Center, 9).Parent = ab
			label(bh, "Name" .. def.Key, def.Name, cx - 70, 263, 140, 26, F.Title, C.Text, Enum.TextXAlignment.Center, 6).Parent = ab
		end
	end

	-- PASSIVE 1 / 2 / 3: automatic passive items (no hotkey). HUD.AbilityBar shows the equipped
	-- item's icon (or glyph) and hides the empty-state number + caption.
	for n, cell in ipairs(GRID) do
		local p, s = rect(bh, cell[1] + 3, cell[2] + 3, CELL - 6, CELL - 6)
		local slot = new("Frame", { Name = "Passive" .. n, BackgroundTransparency = 1, BorderSizePixel = 0, Position = p, Size = s, ZIndex = 6 }, ab)
		slot:SetAttribute("PassiveSlot", n)
		new("UICorner", { CornerRadius = UDim.new(0.08, 0) }, slot)
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.82, 0.82), ScaleType = Enum.ScaleType.Fit, ZIndex = 7, Visible = false }, slot)
		new("TextLabel", { Name = "Glyph", BackgroundTransparency = 1, Text = "", FontFace = F.Title, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), ZIndex = 7, Visible = false, TextStrokeTransparency = 0.4 }, slot)
		new("TextLabel", { Name = "Number", BackgroundTransparency = 1, Text = tostring(n), FontFace = F.Number, TextColor3 = C.Gold, TextTransparency = 0.35, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.12), Size = UDim2.fromScale(0.6, 0.44), ZIndex = 7, TextStrokeTransparency = 0.7 }, slot)
		new("TextLabel", { Name = "Caption", BackgroundTransparency = 1, Text = "PASSIVE", FontFace = F.Title, TextColor3 = C.Muted, TextTransparency = 0.25, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(0.9, 0.22), ZIndex = 7, TextStrokeTransparency = 0.7 }, slot)
		new("UIStroke", { Name = "Highlight", Color = C.GoldBright, Thickness = 1.5, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, slot)
	end

	-- hover tooltip for the boots / passive cells: sits above the right compartment (never over
	-- E / R); HUD.AbilityBar fills it and shows it while the mouse is over one of those cells
	local tp, ts = rect(bh, 1577, 116, 330, 124)
	local tip = new("Frame", { Name = "SlotTooltip", BackgroundColor3 = C.Black, BackgroundTransparency = 0.04, AnchorPoint = Vector2.new(1, 1), Position = tp, Size = ts, ZIndex = 20, BorderSizePixel = 0, Visible = false }, ab)
	new("UICorner", { CornerRadius = UDim.new(0.06, 0) }, tip)
	new("UIStroke", { Color = C.Gold, Thickness = 1.5, Transparency = 0.1 }, tip)
	new("TextLabel", { Name = "Title", BackgroundTransparency = 1, Text = "PASSIVE 1", FontFace = F.Title, TextColor3 = C.GoldBright, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.2), ZIndex = 21, TextStrokeTransparency = 0.6 }, tip)
	new("TextLabel", { Name = "Sub", BackgroundTransparency = 1, Text = "", FontFace = F.BodyBold, TextColor3 = C.Muted, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromScale(0.04, 0.27), Size = UDim2.fromScale(0.92, 0.13), ZIndex = 21 }, tip)
	local body = new("TextLabel", { Name = "Body", BackgroundTransparency = 1, Text = "", RichText = true, FontFace = F.Body, TextColor3 = C.Text, TextScaled = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromScale(0.04, 0.44), Size = UDim2.fromScale(0.92, 0.5), ZIndex = 21 }, tip)
	new("UITextSizeConstraint", { MaxTextSize = 14 }, body)

	-- CENTRE overlays ---------------------------------------------------------------------------
	local ls = group(root, "LastStand", 560, 175, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.14))
	ls.Visible = false
	image(ls, "Frame", A.PlayerPanel, -20, -20, 600, 215, 1)
	label(ls, "Warning", "FLAG DESTROYED", 0, 22, 560, 22, F.Title, C.Red, Enum.TextXAlignment.Center)
	label(ls, "Title", "LAST STAND", 0, 46, 560, 44, F.Title, C.Text, Enum.TextXAlignment.Center)
	label(ls, "Hint", "Find a Core Fragment and restore your anchor.", 40, 96, 480, 22, F.Body, C.Text, Enum.TextXAlignment.Center)
	label(ls, "Timer", "TIME REMAINING: 15", 0, 124, 560, 28, F.Title, C.GoldBright, Enum.TextXAlignment.Center)

	local ch = group(root, "Channel", 320, 40, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.7))
	ch.Visible = false
	label(ch, "Label", "RE-ANCHORING...", 0, 0, 320, 16, F.Title, C.Cyan, Enum.TextXAlignment.Center)
	bar(ch, "Bar", 0, 20, 320, 14, C.Cyan, 3, false)

	new("TextLabel", { Name = "CenterTitle", BackgroundTransparency = 1, Text = "", FontFace = F.Title, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.6, 0.09), ZIndex = 10, TextStrokeTransparency = 0.35, Visible = false }, root)
	new("TextLabel", { Name = "CenterSub", BackgroundTransparency = 1, Text = "", FontFace = F.Body, TextColor3 = C.Text, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.465), Size = UDim2.fromScale(0.6, 0.03), ZIndex = 10, TextStrokeTransparency = 0.45, Visible = false }, root)

	gui.Parent = parent
	return gui
end

return Builder
