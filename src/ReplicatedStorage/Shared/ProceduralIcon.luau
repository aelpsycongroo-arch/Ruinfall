-- ProceduralIcon: generates rich visual icons for items without image assets.
-- Used by UITheme.ItemIcon (shop) and HUD.AbilityBar (in-game HUD).
-- Call Populate(frame, definition) to add a procedural icon to a frame.
-- Call Clear(frame) to remove it.

local ProceduralIcon = {}

local CLASS_COLORS = {
	Assassin = Color3.fromRGB(150, 50, 200),
	Mage = Color3.fromRGB(80, 150, 220),
	Marksman = Color3.fromRGB(120, 200, 80),
	Tank = Color3.fromRGB(100, 130, 200),
	Fighter = Color3.fromRGB(220, 100, 50),
	General = Color3.fromRGB(200, 170, 100),
}

local RARITY_COLORS = {
	Mythic = Color3.fromRGB(255, 200, 80),
	Passive = Color3.fromRGB(180, 100, 220),
}

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function ProceduralIcon.Clear(frame)
	if not frame then return end
	local proc = frame:FindFirstChild("ProcIcon")
	if proc then
		proc:Destroy()
	end
end

function ProceduralIcon.Populate(frame, definition)
	if not frame or not definition then return end
	ProceduralIcon.Clear(frame)

	local zIndex = frame.ZIndex or 1
	local itemColor = definition.Color or Color3.fromRGB(60, 50, 40)
	local lighter = itemColor:Lerp(Color3.new(1, 1, 1), 0.2)
	local darker = itemColor:Lerp(Color3.new(0, 0, 0), 0.3)
	local rarity = definition.Rarity or "Mythic"
	local borderColor = RARITY_COLORS[rarity] or RARITY_COLORS.Mythic
	local classKey = definition.Class or "General"
	local classColor = CLASS_COLORS[classKey] or CLASS_COLORS.General

	local proc = Instance.new("Frame")
	proc.Name = "ProcIcon"
	proc.BackgroundTransparency = 1
	proc.Size = UDim2.fromScale(1, 1)
	proc.ZIndex = zIndex + 1
	proc.Parent = frame

	-- Background with gradient
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.new(1, -2, 1, -2)
	bg.Position = UDim2.fromOffset(1, 1)
	bg.BackgroundColor3 = itemColor
	bg.BorderSizePixel = 0
	bg.ZIndex = zIndex + 1
	bg.Parent = proc
	makeCorner(bg, 3)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(lighter, darker)
	grad.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = borderColor
	stroke.Thickness = 1.5
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg

	-- Class color bar at top
	local classBar = Instance.new("Frame")
	classBar.Name = "ClassBar"
	classBar.Size = UDim2.new(1, -6, 0, 2)
	classBar.Position = UDim2.fromOffset(3, 3)
	classBar.BackgroundColor3 = classColor
	classBar.BorderSizePixel = 0
	classBar.ZIndex = zIndex + 2
	classBar.Parent = bg
	makeCorner(classBar, 1)

	-- Glyph text (large, centered, medieval font)
	local glyph = Instance.new("TextLabel")
	glyph.Name = "ProcGlyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.new(1, -4, 1, -12)
	glyph.Position = UDim2.fromOffset(2, 5)
	glyph.Font = Enum.Font.Fondamento
	glyph.Text = definition.Glyph or "?"
	glyph.TextColor3 = Color3.new(1, 1, 1)
	glyph.TextStrokeColor3 = Color3.new(0, 0, 0)
	glyph.TextStrokeTransparency = 0.3
	glyph.TextScaled = true
	glyph.TextXAlignment = Enum.TextXAlignment.Center
	glyph.TextYAlignment = Enum.TextYAlignment.Center
	glyph.ZIndex = zIndex + 3
	glyph.Parent = bg

	-- Slot type indicator at bottom
	local ind = Instance.new("Frame")
	ind.Name = "SlotIndicator"
	ind.Size = UDim2.fromOffset(10, 8)
	ind.Position = UDim2.new(0.5, -5, 1, -11)
	ind.BackgroundTransparency = 1
	ind.ZIndex = zIndex + 3
	ind.Parent = bg

	if definition.SlotType == "Boots" then
		-- Two chevrons for movement / boots
		for i = 0, 1 do
			local ch = Instance.new("Frame")
			ch.Size = UDim2.fromOffset(6, 2)
			ch.Position = UDim2.fromOffset(2, 1 + i * 3)
			ch.BackgroundColor3 = borderColor
			ch.BorderSizePixel = 0
			ch.Rotation = -20
			ch.ZIndex = zIndex + 4
			ch.Parent = ind
			makeCorner(ch, 1)
		end
	elseif definition.SlotType == "Passive" then
		-- Diamond shape for passive items
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(6, 6)
		d.Position = UDim2.fromOffset(2, 1)
		d.BackgroundColor3 = borderColor
		d.BorderSizePixel = 0
		d.Rotation = 45
		d.ZIndex = zIndex + 4
		d.Parent = ind
		makeCorner(d, 1)
	else
		-- Mythic: small rounded gem shape
		local s = Instance.new("Frame")
		s.Size = UDim2.fromOffset(6, 6)
		s.Position = UDim2.fromOffset(2, 1)
		s.BackgroundColor3 = borderColor
		s.BorderSizePixel = 0
		s.ZIndex = zIndex + 4
		s.Parent = ind
		makeCorner(s, 3)
	end

	return proc
end

return ProceduralIcon