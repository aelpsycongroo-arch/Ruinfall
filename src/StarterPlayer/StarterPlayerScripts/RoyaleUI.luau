-- RoyaleUI: client screens for the 18-player free-for-all (Royale) plus the health potion
-- widget used in BOTH modes.
--   * Deploy map (MatchState "Deploying"): the whole map drawn from above; click to choose
--     where you land. Every pick shows its blocked circle (nobody else may land inside it).
--   * In-match (Royale): zone timer, heroes alive, out-of-zone warning and your gear with
--     DROP buttons (dropped gear lands at your feet for anyone to take).
--   * Potions (both modes): count + H to drink (natural monsters drop them).
-- The server validates everything; this only renders snapshots and sends intents.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local ZoneMath = require(Shared:WaitForChild("ZoneMath"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local ZoneWall = require(script.Parent:WaitForChild("ZoneWall"))

-- Constants
local STATE = Constants.MatchState
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label, Button, Panel = UITheme.New, UITheme.Label, UITheme.Button, UITheme.Panel
local MAP_PX = 600
local ZONE_COLOR = Color3.fromRGB(190, 110, 255)
local player = Players.LocalPlayer
local BOOT_SLOT = ItemDefinitions.BOOT_SLOT
local PASSIVE_BASE = ItemDefinitions.PASSIVE_SLOT_BASE

-- State
local RoyaleUI = {}
RoyaleUI.__index = RoyaleUI

-- Helpers -------------------------------------------------------------------------------
local function circle(parent, diameter, color, transparency, zIndex)
	local frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(diameter, diameter), BackgroundColor3 = color, BackgroundTransparency = transparency or 0, ZIndex = zIndex or 2, Parent = parent })
	New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	return frame
end

local function ring(parent, diameter, color, thickness, zIndex)
	local frame = circle(parent, diameter, color, 1, zIndex)
	UITheme.Stroke(frame, color, thickness or 2, 0)
	return frame
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function yawDegrees(cframe)
	local _, yaw = cframe:ToOrientation()
	return -math.deg(yaw)
end

-- Construction ----------------------------------------------------------------------------
function RoyaleUI.new(screen, clientState)
	local self = setmetatable({}, RoyaleUI)
	self.ClientState = clientState
	self.Remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.Scale = 1
	self.Radius = Constants.Royale.MAP_RADIUS
	self.BuiltSeed = nil
	self.Wall = ZoneWall.new()
	self.WallZone = nil

	-- Deploy screen -------------------------------------------------------------------------
	local deploy = New("Frame", { Name = "RoyaleDeploy", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 12), BackgroundTransparency = 0.05, Visible = false, ZIndex = 30, Parent = screen })
	self.Deploy = deploy
	Label({ Text = "CHOOSE YOUR LANDING SPOT", Font = FONTS.Title, TextSize = 38, TextColor3 = COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(900, 44), ZIndex = 31, Parent = deploy })
	self.DeployHint = Label({ Text = "Click the map. The circle around each pick is blocked for everyone else.", Font = FONTS.Medium, TextSize = 16, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(900, 20), ZIndex = 31, Parent = deploy })
	self.DeployTimer = Label({ Text = "", Font = FONTS.Title, TextSize = 30, TextColor3 = COLORS.Text, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(600, 36), ZIndex = 31, Parent = deploy })
	local holder = New("Frame", { Name = "MapHolder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromOffset(MAP_PX, MAP_PX), BackgroundTransparency = 1, ZIndex = 31, Parent = deploy })
	New("UIScale", { Name = "Fit", Parent = holder })
	self.MapHolder = holder
	self.MapStatic = New("Frame", { Name = "Static", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 32, Parent = holder })
	self.MapDynamic = New("Frame", { Name = "Dynamic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 34, Parent = holder })
	self.Hover = ring(holder, 20, COLORS.Success, 2, 40)
	self.Hover.Visible = false
	self.PickMarkers = {}
	local clickArea = New("TextButton", { Name = "ClickArea", Text = "", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 45, Parent = holder })
	-- the screen ignores the GUI inset, so use full-screen coordinates everywhere
	local function pointer(input)
		if input and input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X, input.Position.Y) + inset
		end
		return UserInputService:GetMouseLocation()
	end
	clickArea.MouseMoved:Connect(function()
		self:UpdateHover(pointer(nil))
	end)
	clickArea.MouseLeave:Connect(function()
		self.Hover.Visible = false
	end)
	clickArea.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local world = self:ScreenToWorld(pointer(input))
			if world then
				self.Remotes.RoyaleRequest:FireServer("Pick", world)
			end
		end
	end)

	-- In-match overlay (Royale) ------------------------------------------------------------------
	local overlay = New("Frame", { Name = "RoyaleOverlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = screen })
	self.Overlay = overlay
	local zoneBox = Panel({ Name = "ZoneBox", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(330, 58), ZIndex = 6, Parent = overlay })
	self.ZoneText = Label({ Text = "", Font = FONTS.Title, TextSize = 20, TextColor3 = ZONE_COLOR, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 24), ZIndex = 7, Parent = zoneBox })
	self.AliveText = Label({ Text = "", Font = FONTS.Medium, TextSize = 14, TextColor3 = COLORS.Text, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 32), Size = UDim2.new(1, -16, 0, 18), ZIndex = 7, Parent = zoneBox })
	self.OutWarning = Label({ Text = "OUTSIDE THE ZONE - GET TO THE PURPLE RING", Font = FONTS.Title, TextSize = 24, TextColor3 = COLORS.Danger, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 134), Size = UDim2.fromOffset(700, 30), Visible = false, ZIndex = 7, Parent = overlay })
	self.OutVignette = New("Frame", { Name = "StormTint", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 40, 200), BackgroundTransparency = 1, ZIndex = 5, Parent = overlay })

	-- gear panel (left edge): weapon (= class), items with DROP, revive cross. It is also the
	-- drop target when dragging loot out of a chest.
	local ROW_H = 38
	local gear = Panel({ Name = "Gear", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(272, 36 + 9 * (ROW_H + 3) + 24), ZIndex = 6, Parent = overlay })
	self.GearPanel = gear
	self.GearHighlight = UITheme.Stroke(gear, COLORS.Success, 3, 1)
	Label({ Text = "YOUR GEAR", Font = FONTS.Title, TextSize = 16, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), ZIndex = 7, Parent = gear })
	self.GearRows = {}
	local slots = {
		{ Key = "Weapon", Label = "WPN" }, { Key = 1, Label = "E" }, { Key = 2, Label = "R" }, { Key = BOOT_SLOT, Label = "RMB" },
		{ Key = PASSIVE_BASE + 1, Label = "P1" }, { Key = PASSIVE_BASE + 2, Label = "P2" }, { Key = PASSIVE_BASE + 3, Label = "P3" },
		{ Key = "Cross", Label = "\u{271D}" },
	}
	for index, slot in ipairs(slots) do
		local y = 32 + (index - 1) * (ROW_H + 3)
		local row = New("Frame", { Position = UDim2.fromOffset(8, y), Size = UDim2.new(1, -16, 0, ROW_H), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.35, ZIndex = 7, Parent = gear })
		UITheme.Corner(row, 4)
		Label({ Text = slot.Label, Font = FONTS.Title, TextSize = 14, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(6, 9), Size = UDim2.fromOffset(34, 20), ZIndex = 8, Parent = row })
		local name = Label({ Text = "-", Font = FONTS.Bold, TextSize = 13, Position = UDim2.fromOffset(42, 2), Size = UDim2.new(1, -112, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8, Parent = row })
		local sub = Label({ Text = "", Font = FONTS.Medium, TextSize = 11, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(42, 19), Size = UDim2.new(1, -112, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8, Parent = row })
		local buttonText = slot.Key == "Cross" and "PLANT" or "DROP"
		local action = Button({ Text = buttonText, Font = FONTS.Title, TextSize = 12, BackgroundColor3 = slot.Key == "Cross" and Color3.fromRGB(50, 80, 55) or Color3.fromRGB(95, 45, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(62, 24), ZIndex = 8, Parent = row }, function()
			if slot.Key == "Cross" then
				self.Remotes.LootRequest:FireServer("PlantCross")
			elseif type(slot.Key) == "number" then
				self.Remotes.LootRequest:FireServer("Drop", slot.Key)
			end
		end)
		self.GearRows[index] = { Key = slot.Key, Name = name, Sub = sub, Action = action }
	end
	Label({ Text = "F: open chest   H: potion   I: hide", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, Position = UDim2.new(0, 12, 1, -22), Size = UDim2.new(1, -24, 0, 16), ZIndex = 7, Parent = gear })

	-- Supply chest window: every entry with its short stats; drag an entry onto YOUR GEAR
	-- (or tap it on touch screens) to take it.
	local chestFrame = Panel({ Name = "Chest", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 60, 0.5, 0), Size = UDim2.fromOffset(420, 360), Visible = false, ZIndex = 20, Parent = screen })
	self.ChestFrame = chestFrame
	UITheme.MedievalPanel(chestFrame, true)
	self.ChestTitle = Label({ Text = "SUPPLY CHEST", Font = FONTS.Title, TextSize = 20, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -60, 0, 24), ZIndex = 21, Parent = chestFrame })
	Label({ Text = "Right-click to equip, or drag onto YOUR GEAR. What it replaces goes back in the chest.", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, TextWrapped = true, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 30), ZIndex = 21, Parent = chestFrame })
	Button({ Text = "X", Font = FONTS.Title, TextSize = 16, BackgroundColor3 = Color3.fromRGB(95, 45, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(30, 26), ZIndex = 22, Parent = chestFrame }, function()
		self:CloseChest(true)
	end)
	self.ChestList = New("ScrollingFrame", { Name = "Entries", Position = UDim2.fromOffset(10, 66), Size = UDim2.new(1, -20, 1, -76), BackgroundTransparency = 1, ScrollBarThickness = 5, CanvasSize = UDim2.new(), ZIndex = 21, Parent = chestFrame })
	New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.ChestList })
	self.DragGhost = Label({ Text = "", Font = FONTS.Bold, TextSize = 14, BackgroundColor3 = Color3.fromRGB(40, 32, 26), BackgroundTransparency = 0.1, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(200, 30), Visible = false, ZIndex = 50, Parent = screen })
	UITheme.Corner(self.DragGhost, 5)
	UITheme.Stroke(self.DragGhost, COLORS.Gold, 1.5, 0)
	self.Screen = screen

	self.Remotes.LootRequest.OnClientEvent:Connect(function(kind, payload)
		if kind == "Chest" and type(payload) == "table" then
			self:ShowChest(payload)
		elseif kind == "ChestClosed" and type(payload) == "table" and self.OpenChestId == payload.Id then
			self:CloseChest(false)
		end
	end)
	-- drag release anywhere: drop onto the gear panel = take
	UserInputService.InputEnded:Connect(function(input)
		if not self.Dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local drag = self.Dragging
		self.Dragging = nil
		self.DragGhost.Visible = false
		self.GearHighlight.Transparency = 1
		local point = input.UserInputType == Enum.UserInputType.Touch and (Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()) or UserInputService:GetMouseLocation()
		local moved = (point - drag.Start).Magnitude
		if self:OverGear(point) or (input.UserInputType == Enum.UserInputType.Touch and moved < 10) then
			self.Remotes.LootRequest:FireServer("Take", drag.ChestId, drag.Index)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if self.Dragging then
			local point = self.Dragging.Touch and self.Dragging.Last or UserInputService:GetMouseLocation()
			self.DragGhost.Position = UDim2.fromOffset(point.X, point.Y)
			self.GearHighlight.Transparency = self:OverGear(point) and 0 or 0.6
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if self.Dragging and self.Dragging.Touch and input.UserInputType == Enum.UserInputType.Touch then
			self.Dragging.Last = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		end
	end)

	-- Potion widget (both modes) -------------------------------------------------------------
	local potion = Button({ Name = "Potion", Text = "", BackgroundColor3 = Color3.fromRGB(70, 24, 30), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -200), Size = UDim2.fromOffset(150, 46), Visible = false, ZIndex = 6, Parent = screen }, function()
		self.Remotes.LootRequest:FireServer("UsePotion")
	end)
	UITheme.MedievalPanel(potion, false)
	local flask = circle(potion, 26, Color3.fromRGB(255, 70, 90), 0, 7)
	flask.Position = UDim2.fromOffset(24, 23)
	self.PotionText = Label({ Text = "x0", Font = FONTS.Title, TextSize = 20, Position = UDim2.fromOffset(44, 4), Size = UDim2.fromOffset(100, 22), ZIndex = 7, Parent = potion })
	Label({ Text = "[H] drink", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(44, 26), Size = UDim2.fromOffset(100, 16), ZIndex = 7, Parent = potion })
	self.Potion = potion

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			self.GearToggled = not self.GearToggled
			return
		end
		if input.KeyCode ~= Enum.KeyCode.H then
			return
		end
		if self.ClientState.GetMatchState() == STATE.ACTIVE then
			self.Remotes.LootRequest:FireServer("UsePotion")
		end
	end)
	return self
end

-- Deploy map --------------------------------------------------------------------------------
function RoyaleUI:WorldToMap(x, z)
	return MAP_PX / 2 + x * self.Scale, MAP_PX / 2 + z * self.Scale
end

function RoyaleUI:ScreenToWorld(screenPosition)
	local holder = self.MapHolder
	local size = holder.AbsoluteSize
	if size.X <= 0 then
		return nil
	end
	-- screenPosition is full-screen (GetMouseLocation); AbsolutePosition never counts the top-bar inset
	local local_ = (screenPosition - GuiService:GetGuiInset() - holder.AbsolutePosition) * (MAP_PX / size.X)
	local x = (local_.X - MAP_PX / 2) / self.Scale
	local z = (local_.Y - MAP_PX / 2) / self.Scale
	return Vector3.new(x, 0, z)
end

function RoyaleUI:BuildStatic(state)
	local static = self.MapStatic
	static:ClearAllChildren()
	local royale = state.Royale
	local radius = royale and royale.MapRadius or Constants.Royale.MAP_RADIUS
	self.Radius = radius
	self.Scale = MAP_PX / (2 * (radius + 6))
	local arena = circle(static, radius * 2 * self.Scale, Color3.fromRGB(46, 58, 40), 0, 32)
	arena.Position = UDim2.fromScale(0.5, 0.5)
	UITheme.Stroke(arena, Color3.fromRGB(170, 130, 70), 3, 0)
	local margin = ring(static, (radius - (royale and royale.EdgeMargin or 30)) * 2 * self.Scale, Color3.fromRGB(120, 110, 90), 1, 33)
	margin.Position = UDim2.fromScale(0.5, 0.5)
	local map = workspace:FindFirstChild("RuinfallMap")
	if not map then
		return false
	end
	local function place(frame, position)
		local x, y = self:WorldToMap(position.X, position.Z)
		frame.Position = UDim2.fromOffset(x, y)
	end
	local brush = map:FindFirstChild("Brush")
	if brush then
		for _, part in ipairs(brush:GetChildren()) do
			if part:IsA("BasePart") then
				local frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(part.Size.X * self.Scale, part.Size.Z * self.Scale), Rotation = yawDegrees(part.CFrame), BackgroundColor3 = Color3.fromRGB(70, 100, 60), BackgroundTransparency = 0.25, ZIndex = 33, Parent = static })
				place(frame, part.Position)
			end
		end
	end
	local blockers = map:FindFirstChild("Blockers")
	if blockers then
		for _, part in ipairs(blockers:GetChildren()) do
			local shape = part:GetAttribute("MinimapShape")
			if shape == "Box" then
				local frame = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(math.max(2, part.Size.X * self.Scale), math.max(2, part.Size.Z * self.Scale)), Rotation = yawDegrees(part.CFrame), BackgroundColor3 = Color3.fromRGB(160, 155, 145), ZIndex = 33, Parent = static })
				place(frame, part.Position)
			elseif shape == "Circle" then
				local dot = circle(static, math.max(3, part.Size.Y * self.Scale), Color3.fromRGB(130, 125, 118), 0, 33)
				place(dot, part.Position)
			end
		end
	end
	for _, camp in ipairs(state.Camps or {}) do
		local dot = circle(static, 9, Color3.fromRGB(220, 110, 60), 0, 33)
		UITheme.Stroke(dot, Color3.new(0, 0, 0), 1, 0.2)
		place(dot, camp.Position)
	end
	return true
end

function RoyaleUI:IsSpotFree(world, royale)
	if Vector3.new(world.X, 0, world.Z).Magnitude > self.Radius - (royale.EdgeMargin or 30) then
		return false
	end
	local me = self.ClientState.GetMe()
	for _, pick in ipairs(royale.Picks or {}) do
		if (not me or pick.Id ~= me.Id) and (Vector3.new(pick.X, 0, pick.Z) - Vector3.new(world.X, 0, world.Z)).Magnitude < royale.Exclusion then
			return false
		end
	end
	return true
end

function RoyaleUI:UpdateHover(screenPosition)
	local state = self.ClientState.Game
	local royale = state and state.Royale
	local world = royale and self:ScreenToWorld(screenPosition)
	if not world then
		self.Hover.Visible = false
		return
	end
	local x, y = self:WorldToMap(world.X, world.Z)
	self.Hover.Position = UDim2.fromOffset(x, y)
	self.Hover.Size = UDim2.fromOffset(royale.Exclusion * 2 * self.Scale, royale.Exclusion * 2 * self.Scale)
	local free = self:IsSpotFree(world, royale)
	self.Hover:FindFirstChildOfClass("UIStroke").Color = free and COLORS.Success or COLORS.Danger
	self.Hover.Visible = true
end

function RoyaleUI:RenderPicks(royale)
	local me = self.ClientState.GetMe()
	for _, marker in pairs(self.PickMarkers) do
		marker.Seen = false
	end
	for _, pick in ipairs(royale.Picks or {}) do
		local marker = self.PickMarkers[pick.Id]
		local mine = me ~= nil and pick.Id == me.Id
		local color = mine and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(235, 60, 60) -- you green, others red
		if not marker then
			local zone = circle(self.MapDynamic, 10, color, 0.75, 35)
			UITheme.Stroke(zone, color, 1.5, 0.1)
			local dot = circle(zone, 10, color, 0, 36)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			UITheme.Stroke(dot, Color3.new(0, 0, 0), 1.5, 0)
			local name = Label({ Text = pick.Name, Font = FONTS.Bold, TextSize = 12, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 8), Size = UDim2.fromOffset(140, 14), ZIndex = 37, Parent = zone })
			marker = { Zone = zone, Dot = dot, Name = name }
			self.PickMarkers[pick.Id] = marker
		end
		marker.Seen = true
		local x, y = self:WorldToMap(pick.X, pick.Z)
		marker.Zone.Position = UDim2.fromOffset(x, y)
		marker.Zone.Size = UDim2.fromOffset(royale.Exclusion * 2 * self.Scale, royale.Exclusion * 2 * self.Scale)
		marker.Zone.BackgroundColor3 = color
		marker.Zone:FindFirstChildOfClass("UIStroke").Color = color
		marker.Dot.BackgroundColor3 = color
		marker.Dot.Size = UDim2.fromOffset(mine and 14 or 10, mine and 14 or 10)
		marker.Name.Text = mine and "YOU" or "" -- other players stay anonymous on the landing map
		marker.Name.Visible = mine
		marker.Name.TextColor3 = color
	end
	for id, marker in pairs(self.PickMarkers) do
		if not marker.Seen then
			marker.Zone:Destroy()
			self.PickMarkers[id] = nil
		end
	end
end

-- Supply chest -----------------------------------------------------------------------------------
function RoyaleUI:OverGear(point)
	local gear = self.GearPanel
	if not gear or not self.Overlay.Visible then
		return false
	end
	point -= GuiService:GetGuiInset() -- to AbsolutePosition space
	local position, size = gear.AbsolutePosition, gear.AbsoluteSize
	return point.X >= position.X and point.X <= position.X + size.X and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

function RoyaleUI:ShowChest(payload)
	self.OpenChestId = payload.Id
	self.ChestPosition = payload.Position
	if not self.ChestOpenDistance then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		self.ChestOpenDistance = (root and payload.Position) and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(payload.Position.X, 0, payload.Position.Z)).Magnitude or 6
	end
	local list = self.ChestList
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.ChestTitle.Text = string.format("SUPPLY CHEST  (%d)", #payload.Entries)
	for order, entry in ipairs(payload.Entries) do
		local row = New("TextButton", { Name = "Entry", Text = "", AutoButtonColor = false, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 50), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.2, ZIndex = 22, Parent = list })
		UITheme.Corner(row, 5)
		UITheme.Stroke(row, entry.Color or COLORS.Gold, 1.5, 0.3)
		local icon = New("Frame", { Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = (entry.Color or COLORS.Gold):Lerp(Color3.new(0, 0, 0), 0.5), ZIndex = 23, Parent = row })
		UITheme.Corner(icon, 5)
		if entry.Icon and entry.Icon ~= "" then
			local art = New("ImageLabel", { BackgroundTransparency = 1, Image = entry.Icon, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 24, Parent = icon })
			UITheme.Corner(art, 5)
		else
			Label({ Text = entry.Kind == "Potion" and "+" or string.sub(entry.Name, 1, 1), Font = FONTS.Title, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = icon })
		end
		-- where it will go when taken
		local slot = entry.Slot == "Weapon" and "WEAPON + Q" or entry.Slot == "Boots" and "M2" or entry.Slot == "Passive" and "PASSIVE" or entry.Slot == "Potion" and "POTION" or "E / R"
		Label({ Text = entry.Name, Font = FONTS.Bold, TextSize = 14, TextColor3 = entry.Color or COLORS.Text, Position = UDim2.fromOffset(52, 5), Size = UDim2.new(1, -140, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 23, Parent = row })
		local slotTag = Label({ Text = slot, Font = FONTS.Title, TextSize = 12, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, BackgroundTransparency = 0.1, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5), Size = UDim2.fromOffset(78, 17), ZIndex = 23, Parent = row })
		UITheme.Corner(slotTag, 4)
		Label({ Text = entry.Summary or "", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Text, Position = UDim2.fromOffset(52, 25), Size = UDim2.new(1, -60, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 23, Parent = row })
		-- right click: equip straight away (a GUI click, so it never casts the boots skill)
		row.MouseButton2Click:Connect(function()
			self.Remotes.LootRequest:FireServer("Take", payload.Id, entry.Index)
		end)
		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local touch = input.UserInputType == Enum.UserInputType.Touch
				local start = touch and (Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()) or UserInputService:GetMouseLocation()
				self.Dragging = { ChestId = payload.Id, Index = entry.Index, Touch = touch, Start = start, Last = start }
				self.DragGhost.Text = entry.Name
				self.DragGhost.TextColor3 = entry.Color or COLORS.Text
				self.DragGhost.Visible = true
			end
		end)
	end
	list.CanvasSize = UDim2.fromOffset(0, #payload.Entries * 55)
	self.ChestFrame.Visible = true
end

function RoyaleUI:CloseChest(tellServer)
	if tellServer and self.OpenChestId then
		self.Remotes.LootRequest:FireServer("CloseChest")
	end
	self.OpenChestId = nil
	self.ChestPosition = nil
	self.ChestOpenDistance = nil
	self.ChestFrame.Visible = false
	self.Dragging = nil
	self.DragGhost.Visible = false
end

-- Update ------------------------------------------------------------------------------------
function RoyaleUI:Update(state)
	local royale = state.Royale
	local matchState = state.State
	local inMatch = matchState == STATE.STARTING or matchState == STATE.ACTIVE or matchState == STATE.ENDING
	local me = self.ClientState.GetMe()
	-- the storm wall is drawn locally from the zone snapshot (smooth, see ZoneWall)
	self.WallZone = royale and (inMatch or matchState == STATE.RESULTS) and royale.Zone or nil

	-- deploy map
	local deploying = royale ~= nil and matchState == STATE.DEPLOYING
	self.Deploy.Visible = deploying
	if deploying then
		-- shrink the map on small screens (clicks are converted with the on-screen size)
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
		self.MapHolder.Fit.Scale = math.clamp(math.min(viewport.X - 40, viewport.Y - 170) / MAP_PX, 0.4, 1)
		if self.BuiltSeed ~= state.Seed and workspace:FindFirstChild("RuinfallMap") then
			if self:BuildStatic(state) then
				self.BuiltSeed = state.Seed
			end
		end
		local myPick = nil
		for _, pick in ipairs(royale.Picks or {}) do
			if me and pick.Id == me.Id then
				myPick = pick
			end
		end
		self:RenderPicks(royale)
		local remaining = (state.StateEndsAt or 0) - workspace:GetServerTimeNow()
		self.DeployTimer.Text = string.format("%s  -  %d / %d landed", myPick and "SPOT CHOSEN - click again to change" or "PICK A SPOT", #(royale.Picks or {}), #state.Participants) .. string.format("   (%ds)", math.max(0, math.ceil(remaining)))
	else
		self.BuiltSeed = nil
		for id, marker in pairs(self.PickMarkers) do
			marker.Zone:Destroy()
			self.PickMarkers[id] = nil
		end
	end

	-- royale overlay
	self.Overlay.Visible = royale ~= nil and inMatch
	-- the gear panel stays hidden unless a chest is open or it is toggled with I
	self.GearPanel.Visible = self.OpenChestId ~= nil or self.GearToggled == true
	if royale and inMatch then
		local zone = royale.Zone
		if zone then
			local left = (zone.PhaseEndsAt or 0) - workspace:GetServerTimeNow()
			if zone.State == "Waiting" then
				self.ZoneText.Text = string.format("ZONE CLOSES IN %s", clock(left))
			elseif zone.State == "Shrinking" then
				self.ZoneText.Text = string.format("ZONE CLOSING  %s", clock(left))
			elseif zone.State == "Final" then
				self.ZoneText.Text = "FINAL ZONE"
			else
				self.ZoneText.Text = "ZONE"
			end
			self.AliveText.Text = string.format("%d ALIVE  |  PHASE %d / %d", royale.Alive or 0, math.max(1, zone.Phase or 1), zone.PhaseCount or 5)
			self.Zone = zone
		end
		-- gear rows
		if me then
			for _, row in ipairs(self.GearRows) do
				local item, text, sub = nil, nil, ""
				if row.Key == "Weapon" then
					local classDef = ClassDefinitions.Get(me.ClassKey)
					text = ClassDefinitions.GetWeaponName(me.ClassKey)
					sub = classDef and string.format("%s  |  Q %s", classDef.DisplayName, classDef.Ability and classDef.Ability.Name or "-") or ""
				elseif row.Key == "Cross" then
					local crossState = me.CrossState or ""
					text = "Revive Cross"
					sub = crossState == "Held" and "Plant it - if you fall, you rise there" or crossState == "Planted" and "Planted - F at the cross to pick it up"
						or crossState == "Used" and "Used" or crossState == "Lost" and "Destroyed" or ""
				elseif row.Key == 1 or row.Key == 2 then
					item = ItemDefinitions.GetItem(me.Mythics and me.Mythics[row.Key])
				elseif row.Key == BOOT_SLOT then
					item = ItemDefinitions.GetItem(me.Boots)
				else
					item = ItemDefinitions.GetItem(me.Passives and me.Passives[row.Key - PASSIVE_BASE])
				end
				if item then
					text = item.Name
					sub = ItemDefinitions.GetShortSummary(item)
				end
				row.Name.Text = text or "- empty -"
				row.Name.TextColor3 = text and COLORS.Text or COLORS.Subtext
				row.Sub.Text = sub
				if row.Key == "Weapon" then
					row.Action.Visible = false -- swap weapons from chests; the old one goes back in
				elseif row.Key == "Cross" then
					row.Action.Visible = me.CrossState == "Held"
				else
					row.Action.Visible = item ~= nil
				end
			end
		end
	end
	if not (royale and inMatch) and self.OpenChestId then
		self:CloseChest(false)
	end

	-- potions (both modes)
	self.Potion.Visible = inMatch and me ~= nil
	if me then
		self.PotionText.Text = string.format("x%d", me.Potions or 0)
	end
end

-- per frame: out-of-zone warning
function RoyaleUI:Tick()
	-- close the chest as soon as the hero walks away from it
	if self.OpenChestId and self.ChestPosition then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local distance = root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(self.ChestPosition.X, 0, self.ChestPosition.Z)).Magnitude or math.huge
		if distance > math.max((self.ChestOpenDistance or 6) + 2.5, 7) then
			self:CloseChest(true)
		end
	end
	self.GearPanel.Visible = self.Overlay.Visible and (self.OpenChestId ~= nil or self.GearToggled == true)
	local now = workspace:GetServerTimeNow()
	local wallOk, wallErr = pcall(self.Wall.Render, self.Wall, self.WallZone, now)
	if not wallOk then
		warn("[RoyaleUI] zone wall:", wallErr)
	end
	local zone = self.Overlay.Visible and self.Zone
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local outside = false
	if zone and root then
		local zx, zz, radius = ZoneMath.At(zone, now)
		outside = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(zx, 0, zz)).Magnitude > radius
	end
	self.OutWarning.Visible = outside
	self.OutVignette.BackgroundTransparency = outside and (0.72 + 0.08 * math.sin(os.clock() * 5)) or 1
	-- inside the storm the whole world turns purple and washed out (client-only effect)
	local tint = self.StormTint
	if not tint or not tint.Parent then
		tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "RoyaleStormTint"
		tint.Enabled = false
		tint.Parent = game:GetService("Lighting")
		self.StormTint = tint
	end
	tint.Enabled = outside
	if outside then
		tint.TintColor = Color3.fromRGB(205, 160, 255)
		tint.Saturation = -0.45
		tint.Contrast = 0.1
		tint.Brightness = -0.05
	end
end

return RoyaleUI
