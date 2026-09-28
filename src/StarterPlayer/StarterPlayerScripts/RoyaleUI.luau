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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

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

	-- gear list with drop buttons (left edge)
	local gear = Panel({ Name = "Gear", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(250, 262), ZIndex = 6, Parent = overlay })
	Label({ Text = "YOUR GEAR", Font = FONTS.Title, TextSize = 16, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), ZIndex = 7, Parent = gear })
	self.GearRows = {}
	local slots = {
		{ Key = "Skill", Label = "Q" }, { Key = 1, Label = "E" }, { Key = 2, Label = "R" }, { Key = BOOT_SLOT, Label = "RMB" },
		{ Key = PASSIVE_BASE + 1, Label = "P1" }, { Key = PASSIVE_BASE + 2, Label = "P2" }, { Key = PASSIVE_BASE + 3, Label = "P3" },
	}
	for index, slot in ipairs(slots) do
		local y = 32 + (index - 1) * 32
		local row = New("Frame", { Position = UDim2.fromOffset(8, y), Size = UDim2.new(1, -16, 0, 28), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.35, ZIndex = 7, Parent = gear })
		UITheme.Corner(row, 4)
		Label({ Text = slot.Label, Font = FONTS.Title, TextSize = 14, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(34, 20), ZIndex = 8, Parent = row })
		local name = Label({ Text = "-", Font = FONTS.Medium, TextSize = 13, Position = UDim2.fromOffset(42, 4), Size = UDim2.new(1, -110, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8, Parent = row })
		local drop = Button({ Text = "DROP", Font = FONTS.Title, TextSize = 12, BackgroundColor3 = Color3.fromRGB(95, 45, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(58, 22), ZIndex = 8, Parent = row }, function()
			self.Remotes.LootRequest:FireServer("Drop", slot.Key)
		end)
		self.GearRows[index] = { Key = slot.Key, Name = name, Drop = drop }
	end
	Label({ Text = "F: take loot   H: drink potion", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(12, 258 - 22), Size = UDim2.new(1, -24, 0, 16), ZIndex = 7, Parent = gear })

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
		if processed or input.KeyCode ~= Enum.KeyCode.H then
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
	local local_ = (screenPosition - holder.AbsolutePosition) * (MAP_PX / size.X)
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
		local color = mine and COLORS.Gold or Constants.GetTeamColor(pick.Team)
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
		marker.Name.Text = mine and "YOU" or pick.Name
		marker.Name.TextColor3 = color
	end
	for id, marker in pairs(self.PickMarkers) do
		if not marker.Seen then
			marker.Zone:Destroy()
			self.PickMarkers[id] = nil
		end
	end
end

-- Update ------------------------------------------------------------------------------------
function RoyaleUI:Update(state)
	local royale = state.Royale
	local matchState = state.State
	local inMatch = matchState == STATE.STARTING or matchState == STATE.ACTIVE or matchState == STATE.ENDING
	local me = self.ClientState.GetMe()

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
				local text = nil
				if row.Key == "Skill" then
					local ability = me.Skill ~= "" and ClassDefinitions.GetAbility("Wanderer", me.Skill) or nil
					text = ability and ability.Name or nil
				elseif row.Key == 1 or row.Key == 2 then
					local item = ItemDefinitions.GetItem(me.Mythics and me.Mythics[row.Key])
					text = item and item.Name or nil
				elseif row.Key == BOOT_SLOT then
					local item = ItemDefinitions.GetItem(me.Boots)
					text = item and item.Name or nil
				else
					local item = ItemDefinitions.GetItem(me.Passives and me.Passives[row.Key - PASSIVE_BASE])
					text = item and item.Name or nil
				end
				row.Name.Text = text or "- empty -"
				row.Name.TextColor3 = text and COLORS.Text or COLORS.Subtext
				row.Drop.Visible = text ~= nil
			end
		end
	end

	-- potions (both modes)
	self.Potion.Visible = inMatch and me ~= nil
	if me then
		self.PotionText.Text = string.format("x%d", me.Potions or 0)
	end
end

-- per frame: out-of-zone warning
function RoyaleUI:Tick()
	local zone = self.Overlay.Visible and self.Zone
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local outside = false
	if zone and root then
		outside = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(zone.X, 0, zone.Z)).Magnitude > zone.Radius
	end
	self.OutWarning.Visible = outside
	self.OutVignette.BackgroundTransparency = outside and (0.8 + 0.06 * math.sin(os.clock() * 5)) or 1
end

return RoyaleUI
