-- UITheme: shared palette, fonts and small widget helpers for Ruinfall UI.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ProceduralIcon = require(Shared:WaitForChild("ProceduralIcon"))

-- State
local UITheme = {}

-- Medieval skin: UI-only palette overrides (world colours in Constants stay untouched)
UITheme.Medieval = {
	Wood = Color3.fromRGB(36, 27, 21),
	WoodLight = Color3.fromRGB(58, 44, 33),
	Trim = Color3.fromRGB(201, 164, 96),
	TrimDark = Color3.fromRGB(112, 84, 46),
	TrimBright = Color3.fromRGB(255, 214, 128),
	Parchment = Color3.fromRGB(238, 226, 200),
	Crimson = Color3.fromRGB(176, 30, 42),
}
local UI_OVERRIDES = {
	Background = Color3.fromRGB(20, 14, 11),
	Panel = UITheme.Medieval.Wood,
	PanelLight = UITheme.Medieval.WoodLight,
	Stroke = UITheme.Medieval.TrimDark,
	Text = UITheme.Medieval.Parchment,
	Subtext = Color3.fromRGB(176, 160, 132),
	Accent = Color3.fromRGB(214, 170, 96),
}
UITheme.Colors = {}
for key, value in pairs(Constants.Colors) do
	UITheme.Colors[key] = UI_OVERRIDES[key] or value
end
UITheme.Fonts = {
	Title = Enum.Font.Fondamento,
	Bold = Enum.Font.Merriweather,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
	Mono = Enum.Font.RobotoMono,
}
UITheme.StyleColors = {
	Info = Constants.Colors.Accent,
	Success = Constants.Colors.Success,
	Warning = Constants.Colors.Warning,
	Danger = Constants.Colors.Danger,
	Ruin = Constants.Colors.Gold,
	Buff = Constants.Colors.Gold,
	Fragment = Constants.Colors.Fragment,
}

-- Public API
function UITheme.New(className, properties, children)
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(properties or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if instance:IsA("GuiObject") and properties and properties.BorderSizePixel == nil then
		instance.BorderSizePixel = 0
	end
	instance.Parent = parent
	return instance
end

function UITheme.Corner(parent, radius)
	return UITheme.New("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

function UITheme.Stroke(parent, color, thickness, transparency)
	return UITheme.New("UIStroke", {
		Color = color or UITheme.Colors.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UITheme.Padding(parent, pixels)
	return UITheme.New("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
		Parent = parent,
	})
end

-- Wood plaque with gold trim, inner bronze border and optional corner rivets.
-- Idempotent: safe to call more than once on the same frame.
function UITheme.MedievalPanel(frame, rivets)
	local medieval = UITheme.Medieval
	local corner = frame:FindFirstChildOfClass("UICorner") or UITheme.Corner(frame, 5)
	corner.CornerRadius = UDim.new(0, 5)
	local stroke = frame:FindFirstChildOfClass("UIStroke") or UITheme.Stroke(frame, medieval.Trim, 2, 0)
	stroke.Color = medieval.Trim
	stroke.Thickness = 2
	stroke.Transparency = 0
	if not frame:FindFirstChild("PlaqueShade") then
		UITheme.New("UIGradient", { Name = "PlaqueShade", Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 150, 140)), Parent = frame })
	end
	if not frame:FindFirstChild("TrimInner") then
		local inner = UITheme.New("Frame", { Name = "TrimInner", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, Parent = frame })
		UITheme.Corner(inner, 3)
		UITheme.Stroke(inner, medieval.TrimDark, 1, 0.15)
	end
	if rivets and not frame:FindFirstChild("Rivet") then
		for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
			UITheme.New("Frame", { Name = "Rivet", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(anchor.X, anchor.X == 0 and 3 or -3, anchor.Y, anchor.Y == 0 and 3 or -3), Size = UDim2.fromOffset(6, 6), Rotation = 45, BackgroundColor3 = medieval.Trim, ZIndex = 6, Parent = frame })
		end
	end
	return frame
end

function UITheme.Panel(properties)
	properties.BackgroundColor3 = properties.BackgroundColor3 or UITheme.Colors.Panel
	properties.BackgroundTransparency = properties.BackgroundTransparency or 0.08
	local frame = UITheme.New("Frame", properties)
	UITheme.Corner(frame, 5)
	UITheme.Stroke(frame, UITheme.Colors.Stroke, 1, 0.35)
	UITheme.MedievalPanel(frame, false)
	return frame
end

function UITheme.Label(properties)
	properties.BackgroundTransparency = properties.BackgroundTransparency or 1
	properties.Font = properties.Font or UITheme.Fonts.Bold
	properties.TextColor3 = properties.TextColor3 or UITheme.Colors.Text
	properties.TextSize = properties.TextSize or 16
	properties.TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left
	return UITheme.New("TextLabel", properties)
end

function UITheme.Button(properties, onClick)
	local baseColor = properties.BackgroundColor3 or UITheme.Colors.PanelLight
	properties.BackgroundColor3 = baseColor
	properties.AutoButtonColor = false
	properties.Font = properties.Font or UITheme.Fonts.Bold
	properties.TextColor3 = properties.TextColor3 or UITheme.Colors.Text
	properties.TextSize = properties.TextSize or 16
	local button = UITheme.New("TextButton", properties)
	UITheme.Corner(button, 5)
	local stroke = UITheme.Stroke(button, UITheme.Colors.Stroke, 1.5, 0.3)
	button:SetAttribute("BaseColor", baseColor)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = button:GetAttribute("BaseColor"):Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = button:GetAttribute("BaseColor") }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button, stroke
end

function UITheme.SetButtonColor(button, color)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

-- Horizontal bar with a fill; returns { Frame, Fill, Set(fraction, color) }
function UITheme.Bar(properties, fillColor)
	local radius = properties.CornerRadius or 6
	properties.CornerRadius = nil
	properties.BackgroundColor3 = properties.BackgroundColor3 or Color3.fromRGB(12, 12, 18)
	local frame = UITheme.New("Frame", properties)
	UITheme.Corner(frame, radius)
	local fill = UITheme.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = fillColor or UITheme.Colors.Success,
		Parent = frame,
	})
	UITheme.Corner(fill, radius)
	local bar = { Frame = frame, Fill = fill, Fraction = 1 }
	function bar.Set(fraction, color)
		fraction = math.clamp(fraction or 0, 0, 1)
		bar.Fraction = fraction
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.Visible = fraction > 0.001
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return bar
end

-- Item icon tile shared by the shop and HUD. view.Set(definition) shows the item's
-- rendered icon (Icon asset) or, until one exists, a class-coloured heraldic glyph.
function UITheme.ItemIcon(properties)
	local zIndex = properties.ZIndex or 1
	properties.BackgroundColor3 = properties.BackgroundColor3 or UITheme.Medieval.WoodLight
	local frame = UITheme.New("Frame", properties)
	UITheme.Corner(frame, 4)
	UITheme.Stroke(frame, UITheme.Medieval.TrimDark, 1.5, 0)
	UITheme.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(105, 95, 85)), Parent = frame })
	-- painted icons fill the whole tile (cropped, never squashed)
	local image = UITheme.New("ImageLabel", { Name = "Image", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, Visible = false, ZIndex = zIndex + 1, Parent = frame })
	UITheme.Corner(image, 4)
	local glyph = UITheme.Label({ Name = "Glyph", Text = "", Font = UITheme.Fonts.Title, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UITheme.Medieval.Parchment, TextStrokeTransparency = 0.35, Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5), ZIndex = zIndex + 1, Parent = frame })
	local view = { Frame = frame, Image = image, Glyph = glyph }
	function view.Set(definition)
		if not definition then
			frame.BackgroundColor3 = Color3.fromRGB(38, 30, 24)
			image.Visible = false
			glyph.Text = "-"
			glyph.TextColor3 = UITheme.Colors.Subtext
			return
		end
		frame.BackgroundColor3 = definition.Color or UITheme.Medieval.WoodLight
		glyph.TextColor3 = UITheme.Medieval.Parchment
		if definition.Icon and definition.Icon ~= "" then
			image.Image = definition.Icon
			image.Visible = true
			glyph.Text = ""
			ProceduralIcon.Clear(frame)
		else
			image.Visible = false
			glyph.Text = ""
			ProceduralIcon.Populate(frame, definition)
		end
	end
	return view
end

function UITheme.HealthColor(fraction)
	if fraction > 0.5 then
		return UITheme.Colors.Success
	elseif fraction > 0.25 then
		return UITheme.Colors.Warning
	end
	return UITheme.Colors.Danger
end

return UITheme
