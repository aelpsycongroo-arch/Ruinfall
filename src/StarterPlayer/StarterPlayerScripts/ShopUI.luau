-- ShopUI: the Ruinfall Armory - medieval item shop (toggle with B).
-- One tab per role (ItemDefinitions.Roles): GENERAL (open items any class can equip),
-- ASSASSIN / MAGE / MARKSMAN / TANK / FIGHTER (class-locked items, shown LOCKED
-- "Requires X" to other classes) and SUPPLIES (stat items + team minion upgrade). The shop opens on
-- the player's own class tab. Every role page has three sections:
--   MYTHICS  (E / R)          max 2, slot 1 -> E, slot 2 -> R
--   BOOTS    (right mouse)    one pair
--   PASSIVES (automatic)      max 3 different passive items, no hotkey
-- Compact cards (3 per row), a small detail panel and the equipped panel sit in one panel that
-- scales with the screen. Cards are selected by CLICK only (never on hover) and each card has
-- its own BUY button. Every number shown comes from ItemDefinitions/ShopDefinitions (the same
-- tables the server uses). The client only sends intents; the server validates everything.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ShopDefinitions = require(Shared:WaitForChild("ShopDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local AbilityScaling = require(Shared:WaitForChild("AbilityScaling"))
local Util = require(Shared:WaitForChild("Util"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local STATE = Constants.MatchState
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local MEDIEVAL = UITheme.Medieval
local New, Label, Button = UITheme.New, UITheme.Label, UITheme.Button
local PARCHMENT = Color3.fromRGB(226, 208, 170)
local INK = Color3.fromRGB(52, 34, 22)
local INK_SOFT = Color3.fromRGB(100, 76, 52)
local CRIMSON = MEDIEVAL.Crimson
local GOOD = Color3.fromRGB(120, 200, 110)
local BAD = Color3.fromRGB(235, 95, 80)
local DISABLED = Color3.fromRGB(120, 105, 85)
local BOOT_SLOT = ItemDefinitions.BOOT_SLOT
local MAX_MYTHICS = ItemDefinitions.MAX_MYTHIC_SLOTS
local MAX_PASSIVES = ItemDefinitions.MAX_PASSIVE_SLOTS or 3
local PASSIVE_BASE = ItemDefinitions.PASSIVE_SLOT_BASE or 4

-- Layout (design units; the whole panel is scaled to the screen with a UIScale)
local PANEL_W, PANEL_H = 1000, 620
local CATALOG_X, CATALOG_W = 12, 690
local SIDE_X, SIDE_W = 712, 276
local CARD = Vector2.new(222, 62) -- mythic / boots / stat item card
local PASSIVE_CARD = Vector2.new(222, 104) -- passive cards also show stats + the passive text
local GAP = 6
local player = Players.LocalPlayer

-- State
local ShopUI = {}
ShopUI.__index = ShopUI

-- Helpers -------------------------------------------------------------------------------
local function plaque(properties, rivets)
	local frame = UITheme.Panel(properties)
	UITheme.MedievalPanel(frame, rivets)
	return frame
end

local function sectionHeader(parent, text, order, info)
	local frame = New("Frame", { Name = "Header_" .. text, Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Label({ Text = text, Font = FONTS.Title, TextSize = 15, TextColor3 = MEDIEVAL.Trim, Size = UDim2.new(1, 0, 0, 19), Parent = frame })
	if info then
		Label({ Name = "Info", Text = info, Font = FONTS.Medium, TextSize = 10, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, -2, 0, 16), Parent = frame })
	end
	New("Frame", { Name = "Rule", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = MEDIEVAL.TrimDark, BorderSizePixel = 0, Parent = frame })
	return frame
end

local function grid(parent, name, order, cellSize, count)
	local rows = math.max(1, math.ceil(count / 3))
	local frame = New("Frame", { Name = name, Size = UDim2.new(1, -8, 0, rows * (cellSize.Y + GAP)), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
	return frame
end

local function note(parent, name, order, text)
	return Label({ Name = name, Text = text, Font = FONTS.Medium, TextSize = 11, TextColor3 = COLORS.Subtext, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 22), Parent = parent })
end

-- mouse position in GuiObject.AbsolutePosition space (GetMouseLocation includes the top-bar inset)
local function mouseInGui()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function smallButton(properties, onClick)
	local button = Button(properties, onClick)
	button.TextScaled = true
	New("UITextSizeConstraint", { MaxTextSize = properties.TextSize or 12, Parent = button })
	return button
end

function ShopUI.new(screen, clientState)
	local self = setmetatable({}, ShopUI)
	self.ClientState = clientState
	self.Remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.Cards = {} -- [kind:id] = card
	self.Selected = nil -- { Kind = "Mythic"|"Consumable"|"WarBand", Id = key } (Mythic covers boots + passives)
	self.SellConfirm = nil -- { Slot, Expires }

	local root = New("Frame", { Name = "Shop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 10, Parent = screen })
	self.Root = root
	New("TextButton", { Name = "Dim", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Parent = root })

	local panel = plaque({ Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundColor3 = MEDIEVAL.Wood, BackgroundTransparency = 0.02, Parent = root }, true)
	self.Panel = panel
	-- responsive: fill most of the screen on any resolution (shrinks on small screens, grows on big ones)
	local uiScale = New("UIScale", { Parent = panel })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X * 0.94 / PANEL_W, viewport.Y * 0.9 / PANEL_H), 0.45, 1.5)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Header
	Label({ Text = "ITEM SHOP", Font = FONTS.Title, TextSize = 26, TextColor3 = MEDIEVAL.TrimBright, Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(160, 32), Parent = panel })
	Label({ Text = "The Ruinfall Armory", Font = FONTS.Bold, TextSize = 11, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(170, 18), Size = UDim2.fromOffset(200, 16), Parent = panel })
	self.GoldLabel = Label({ Text = "PLAYER GOLD: 0000", Font = FONTS.Title, TextSize = 20, TextColor3 = COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -306, 0, 8), Size = UDim2.fromOffset(250, 24), Parent = panel })
	self.AccessLabel = Label({ Text = "", Font = FONTS.Bold, TextSize = 11, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -306, 0, 32), Size = UDim2.fromOffset(250, 14), Parent = panel })
	local close = Button({ Name = "Close", Text = "X", Font = FONTS.Title, TextSize = 16, BackgroundColor3 = CRIMSON:Lerp(Color3.new(0, 0, 0), 0.35), Position = UDim2.new(1, -44, 0, 12), Size = UDim2.fromOffset(28, 28), Parent = panel }, function()
		self:SetVisible(false)
	end)
	close.ZIndex = 3

	-- Catalog (left): one tab per role so each class's items sit together -------------
	local ROLE_INFO = {
		General = "Any class can equip these",
		Assassin = "Only Assassins can equip these",
		Mage = "Only Mages can equip these",
		Marksman = "Only Marksmen can equip these",
		Tank = "Only Tanks can equip these",
		Fighter = "Only Fighters can equip these",
		Supplies = "Stat items stack - upgrade your team's minions",
	}
	self.Tabs = {}
	self.Pages = {}
	local tabKeys = table.clone(ItemDefinitions.Roles)
	table.insert(tabKeys, "Supplies")
	local tabBar = New("Frame", { Name = "Tabs", Position = UDim2.fromOffset(CATALOG_X, 50), Size = UDim2.fromOffset(CATALOG_W, 30), BackgroundTransparency = 1, Parent = panel })
	New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabBar })
	local tabWidth = math.floor((CATALOG_W - 3 * (#tabKeys - 1)) / #tabKeys)
	for index, key in ipairs(tabKeys) do
		local tab = New("TextButton", { Name = "Tab_" .. key, Text = "", AutoButtonColor = false, LayoutOrder = index, Size = UDim2.fromOffset(tabWidth, 30), BackgroundColor3 = MEDIEVAL.WoodLight, Parent = tabBar })
		UITheme.Corner(tab, 4)
		local stroke = UITheme.Stroke(tab, MEDIEVAL.TrimDark, 1.5, 0)
		local title = Label({ Text = string.upper(key), Font = FONTS.Title, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 16), Parent = tab })
		local sub = Label({ Text = "", Font = FONTS.Bold, TextSize = 8, TextColor3 = COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 10), Parent = tab })
		tab.Activated:Connect(function()
			self:ShowTab(key, true)
		end)
		self.Tabs[key] = { Frame = tab, Stroke = stroke, Title = title, Sub = sub }

		local page = New("ScrollingFrame", { Name = "Page_" .. key, Position = UDim2.fromOffset(CATALOG_X, 86), Size = UDim2.fromOffset(CATALOG_W, PANEL_H - 98), BackgroundTransparency = 1, ScrollBarThickness = 5, ScrollBarImageColor3 = MEDIEVAL.Trim, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, BorderSizePixel = 0, Parent = panel })
		New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		self.Pages[key] = page
		if key == "Supplies" then
			sectionHeader(page, "STAT ITEMS", 1, ROLE_INFO[key])
			local consumables = ShopDefinitions.Order
			local otherGrid = grid(page, "OtherGrid", 2, CARD, #consumables)
			for order, consumableKey in ipairs(consumables) do
				self:BuildCard(otherGrid, "Consumable", consumableKey, order)
			end
			sectionHeader(page, "MINIONS  (a wave spawns every " .. ItemDefinitions.MinionWaves.Interval .. " sec)", 3)
			local bandHolder = New("Frame", { Name = "BandGrid", Size = UDim2.new(1, -8, 0, 64), BackgroundTransparency = 1, LayoutOrder = 4, Parent = page })
			local band = self:BuildCard(bandHolder, "WarBand", ItemDefinitions.CreepWave.Id, 1)
			band.Frame.Size = UDim2.new(1, 0, 1, 0)
		else
			local upper = string.upper(key)
			-- 1) mythics (E / R) - everything in RoleItems that is not one of the role's boots
			local boots = ItemDefinitions.RoleBoots and ItemDefinitions.RoleBoots[key] or {}
			local inBootSection = {}
			for _, id in ipairs(boots) do
				inBootSection[id] = true
			end
			local ids = {}
			for _, id in ipairs(ItemDefinitions.RoleItems[key] or {}) do
				local item = ItemDefinitions.GetItem(id)
				if item and not inBootSection[id] and not ItemDefinitions.IsBoots(item) then
					table.insert(ids, id)
				end
			end
			sectionHeader(page, upper .. " MYTHICS  (SPACE / E / R)", 1, ROLE_INFO[key])
			local itemGrid = grid(page, "Grid", 2, CARD, #ids)
			for order, id in ipairs(ids) do
				self:BuildCard(itemGrid, "Mythic", id, order)
			end
			-- 2) boots (right mouse, one pair)
			if #boots > 0 then
				sectionHeader(page, upper .. " BOOTS  (right mouse)", 3, "One pair at a time - buying another replaces it")
				local bootGrid = grid(page, "BootGrid", 4, CARD, #boots)
				for order, id in ipairs(boots) do
					self:BuildCard(bootGrid, "Mythic", id, order)
				end
			end
			-- 3) passive items (automatic, up to 3, no hotkey)
			local passives = ItemDefinitions.RolePassives and ItemDefinitions.RolePassives[key] or {}
			sectionHeader(page, upper .. " PASSIVE ITEMS", 5, string.format("Automatic, no hotkey - up to %d different", MAX_PASSIVES))
			if #passives > 0 then
				local passiveGrid = grid(page, "PassiveGrid", 6, PASSIVE_CARD, #passives)
				for order, id in ipairs(passives) do
					self:BuildCard(passiveGrid, "Mythic", id, order)
				end
			else
				note(page, "PassiveNone", 6, "No passive items for this class yet.")
			end
		end
	end

	-- Details (right, parchment) ----------------------------------------------------------
	local details = New("Frame", { Name = "Details", Position = UDim2.fromOffset(SIDE_X, 50), Size = UDim2.fromOffset(SIDE_W, 330), BackgroundColor3 = PARCHMENT, Parent = panel })
	UITheme.Corner(details, 4)
	UITheme.Stroke(details, MEDIEVAL.TrimDark, 2, 0)
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 200, 175)), Parent = details })
	self.DetailIcon = UITheme.ItemIcon({ Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(48, 48), Parent = details })
	self.DetailName = Label({ Text = "", Font = FONTS.Title, TextSize = 18, TextColor3 = INK, TextScaled = true, Position = UDim2.fromOffset(66, 8), Size = UDim2.fromOffset(200, 20), Parent = details })
	New("UITextSizeConstraint", { MaxTextSize = 18, Parent = self.DetailName })
	self.DetailClass = Label({ Text = "", Font = FONTS.Bold, TextSize = 11, TextColor3 = INK_SOFT, TextScaled = true, Position = UDim2.fromOffset(66, 29), Size = UDim2.fromOffset(200, 13), Parent = details })
	New("UITextSizeConstraint", { MaxTextSize = 11, Parent = self.DetailClass })
	self.DetailPrice = Label({ Text = "", Font = FONTS.Title, TextSize = 13, TextColor3 = Color3.fromRGB(150, 100, 20), TextScaled = true, Position = UDim2.fromOffset(66, 43), Size = UDim2.fromOffset(200, 15), Parent = details })
	New("UITextSizeConstraint", { MaxTextSize = 13, Parent = self.DetailPrice })
	local bodyScroll = New("ScrollingFrame", { Name = "BodyScroll", Position = UDim2.fromOffset(10, 64), Size = UDim2.fromOffset(SIDE_W - 16, 208), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = INK_SOFT, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = details })
	self.DetailBody = Label({ Text = "", Font = FONTS.Medium, TextSize = 11, TextColor3 = INK, TextWrapped = true, RichText = true, TextYAlignment = Enum.TextYAlignment.Top, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -6, 0, 0), Parent = bodyScroll })
	self.DetailStatus = Label({ Text = "", Font = FONTS.Bold, TextSize = 11, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Position = UDim2.fromOffset(10, 276), Size = UDim2.fromOffset(SIDE_W - 20, 14), Parent = details })
	New("UITextSizeConstraint", { MaxTextSize = 11, Parent = self.DetailStatus })
	self.ActionButton = Button({ Name = "Action", Text = "BUY", Font = FONTS.Title, TextSize = 16, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, Position = UDim2.fromOffset(10, 296), Size = UDim2.fromOffset(160, 26), Parent = details }, function()
		self:OnAction()
	end)
	self.SellButton = Button({ Name = "Sell", Text = "SELL", Font = FONTS.Title, TextSize = 13, BackgroundColor3 = CRIMSON:Lerp(Color3.new(0, 0, 0), 0.25), Position = UDim2.fromOffset(178, 296), Size = UDim2.fromOffset(SIDE_W - 188, 26), Parent = details }, function()
		self:OnSellSelected()
	end)

	-- Equipped: E / R mythics (swappable), boots (RMB) and 3 passive slots ----------------
	local equipped = plaque({ Name = "Equipped", Position = UDim2.fromOffset(SIDE_X, 388), Size = UDim2.fromOffset(SIDE_W, PANEL_H - 400), BackgroundColor3 = MEDIEVAL.WoodLight, Parent = panel }, false)
	Label({ Text = "EQUIPPED", Font = FONTS.Title, TextSize = 14, TextColor3 = MEDIEVAL.Trim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 16), Parent = equipped })
	local TILE_W, TILE_H = 60, 84
	local passiveX0 = math.floor((SIDE_W - (3 * TILE_W + 2 * 8)) / 2)
	local TILE_LAYOUT = {
		{ X = 4, Y = 22, Caption = "E" },
		{ X = 68, Y = 22, Caption = "R" },
		{ X = 132, Y = 22, Caption = "SPACE" },
		{ X = 208, Y = 22, Caption = "BOOTS (RMB)" },
	}
	for index = 1, MAX_PASSIVES do
		TILE_LAYOUT[PASSIVE_BASE + index] = { X = passiveX0 + (index - 1) * (TILE_W + 8), Y = 124, Caption = "PASSIVE " .. index }
	end
	New("Frame", { Name = "BootDivider", Position = UDim2.fromOffset(200, 26), Size = UDim2.fromOffset(1, TILE_H - 6), BackgroundColor3 = MEDIEVAL.TrimDark, BorderSizePixel = 0, Parent = equipped })
	Label({ Text = "PASSIVES  (automatic)", Font = FONTS.Bold, TextSize = 9, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 12), Parent = equipped })
	self.SlotTiles = {}
	for index, layout in pairs(TILE_LAYOUT) do
		local isMythic = index <= MAX_MYTHICS
		local tile = New("TextButton", { Name = index == BOOT_SLOT and "BootSlot" or (isMythic and ("Slot" .. index) or ("PassiveSlot" .. (index - PASSIVE_BASE))), Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(layout.X, layout.Y), Size = UDim2.fromOffset(TILE_W, TILE_H), BackgroundColor3 = MEDIEVAL.Wood, Parent = equipped })
		UITheme.Corner(tile, 4)
		local stroke = UITheme.Stroke(tile, MEDIEVAL.TrimDark, 1.5, 0)
		local caption = Label({ Text = layout.Caption, Font = FONTS.Bold, TextSize = 8, TextColor3 = MEDIEVAL.TrimBright, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 0, 10), Parent = tile })
		New("UITextSizeConstraint", { MaxTextSize = 8, Parent = caption })
		local icon = UITheme.ItemIcon({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 13), Size = UDim2.fromOffset(40, 40), Parent = tile })
		local name = Label({ Text = "EMPTY", Font = FONTS.Bold, TextSize = 8, TextColor3 = COLORS.Text, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 54), Size = UDim2.new(1, -4, 0, 11), Parent = tile })
		local sell = smallButton({ Name = "Sell", Text = "SELL", Font = FONTS.Bold, TextSize = 9, BackgroundColor3 = CRIMSON:Lerp(Color3.new(0, 0, 0), 0.3), Position = UDim2.fromOffset(4, 66), Size = UDim2.new(1, -8, 0, 15), Parent = tile }, function()
			self:OnSellSlot(index)
		end)
		if isMythic then
			tile.MouseButton1Down:Connect(function()
				if self:GetSlotItem(index) then
					self.Dragging = index
					self.DragGhost.Set(self:GetSlotItem(index))
				end
			end)
			tile.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and self:GetSlotItem(index) and not self.Dragging then
					self.Dragging = index
					self.DragGhost.Set(self:GetSlotItem(index))
				end
			end)
		end
		tile.Activated:Connect(function()
			local item = self:GetSlotItem(index)
			if item then
				self:Select("Mythic", item.Id)
			end
		end)
		self.SlotTiles[index] = { Frame = tile, Stroke = stroke, Icon = icon, Name = name, Sell = sell }
	end
	-- (drag a mythic onto another mythic slot to swap them; this button swaps E and R)
	self.SwapButton = smallButton({ Name = "Swap", Text = "SWAP", Font = FONTS.Bold, TextSize = 8, Position = UDim2.fromOffset(4, 108), Size = UDim2.fromOffset(40, 14), Parent = equipped }, function()
		self.Remotes.ItemRequest:FireServer("Swap", 1, 2)
	end)
	self.DragGhost = UITheme.ItemIcon({ Name = "DragGhost", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(52, 52), Visible = false, ZIndex = 60, Parent = root })
	UserInputService.InputChanged:Connect(function(input)
		if self.Dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local mouse = mouseInGui() - root.AbsolutePosition
			self.DragGhost.Frame.Position = UDim2.fromOffset(mouse.X, mouse.Y)
			self.DragGhost.Frame.Visible = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not self.Dragging then
			return
		end
		local from = self.Dragging
		self.Dragging = nil
		self.DragGhost.Frame.Visible = false
		local mouse = mouseInGui()
		for index = 1, MAX_MYTHICS do
			local tile = self.SlotTiles[index]
			local topLeft, size = tile.Frame.AbsolutePosition, tile.Frame.AbsoluteSize
			if index ~= from and mouse.X >= topLeft.X and mouse.X <= topLeft.X + size.X and mouse.Y >= topLeft.Y and mouse.Y <= topLeft.Y + size.Y then
				self.Remotes.ItemRequest:FireServer("Swap", from, index)
			end
		end
	end)

	-- Replace dialog (both mythic slots full) ---------------------------------------------
	local dialog = New("TextButton", { Name = "ReplaceDialog", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Visible = false, ZIndex = 20, Parent = panel })
	local box = plaque({ Name = "Box", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 210), ZIndex = 21, Parent = dialog }, true)
	Label({ Text = "MYTHIC SLOTS FULL", Font = FONTS.Title, TextSize = 24, TextColor3 = BAD, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 28), ZIndex = 22, Parent = box })
	self.ReplaceText = Label({ Text = "", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(20, 44), Size = UDim2.new(1, -40, 0, 50), ZIndex = 22, Parent = box })
	self.ReplaceButtons = {}
	for index = 1, MAX_MYTHICS do
		local replaceButton = Button({ Name = "Replace" .. index, Text = "", Font = FONTS.Bold, TextSize = 12, TextWrapped = true, BackgroundColor3 = MEDIEVAL.WoodLight, Position = UDim2.fromOffset(20 + (index - 1) * 197, 100), Size = UDim2.fromOffset(187, 46), ZIndex = 22, Parent = box }, function()
			self:ConfirmReplace(index)
		end)
		self.ReplaceButtons[index] = replaceButton
	end
	Button({ Name = "Cancel", Text = "CANCEL", Font = FONTS.Title, TextSize = 15, BackgroundColor3 = CRIMSON:Lerp(Color3.new(0, 0, 0), 0.3), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 158), Size = UDim2.fromOffset(150, 34), ZIndex = 22, Parent = box }, function()
		dialog.Visible = false
	end)
	self.ReplaceDialog = dialog

	-- Toggle with the Shop key (B by default, rebindable in SETTINGS)
	local GameSettings = require(script.Parent:WaitForChild("GameSettings"))
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or GameSettings.Capturing then
			return
		end
		if GameSettings.Matches(input, "Shop") then
			local game = self.ClientState and self.ClientState.Game
			if game and game.Royale then
				self:SetVisible(false) -- free for all: no shop, gear comes from ruins
				return
			end
			self:SetVisible(not self.Root.Visible)
		end
	end)

	self:ShowTab("General")
	return self
end

-- Tabs ---------------------------------------------------------------------------------
function ShopUI:ShowTab(key, manual)
	if not self.Pages[key] then
		key = "General"
	end
	self.CurrentTab = key
	if manual then
		self.TabChosenManually = true
	end
	for pageKey, page in pairs(self.Pages) do
		page.Visible = pageKey == key
	end
	self:RefreshTabs()
	-- show the first entry of the tab in the details panel (selection is click-only)
	if key == "Supplies" then
		self:Select("Consumable", ShopDefinitions.Order[1])
	else
		local ids = ItemDefinitions.RoleItems[key]
		if ids and ids[1] then
			self:Select("Mythic", ids[1])
		end
	end
end

function ShopUI:RefreshTabs()
	local me = self:GetMe()
	local classKey = me and me.ClassKey
	for key, tab in pairs(self.Tabs) do
		local active = key == self.CurrentTab
		local mine = key == classKey
		tab.Frame.BackgroundColor3 = active and MEDIEVAL.Trim:Lerp(MEDIEVAL.Wood, 0.45) or MEDIEVAL.WoodLight
		tab.Stroke.Color = active and MEDIEVAL.TrimBright or (mine and COLORS.Gold or MEDIEVAL.TrimDark)
		tab.Stroke.Thickness = active and 2 or 1.5
		tab.Title.TextColor3 = active and Color3.fromRGB(255, 245, 220) or COLORS.Text
		tab.Sub.Text = mine and "YOUR CLASS" or (key == "General" and "ANY CLASS" or (key == "Supplies" and "STATS + ARMY" or ""))
	end
end

-- Cards --------------------------------------------------------------------------------
-- Compact card: icon left, name / tag / price right, small BUY button bottom-right.
-- Passive cards are taller and also list the stats and the passive effect.
function ShopUI:BuildCard(parent, kind, id, order)
	local definition = kind == "Mythic" and ItemDefinitions.GetItem(id) or (kind == "Consumable" and ShopDefinitions.Get(id) or ItemDefinitions.CreepWave)
	local card = New("TextButton", { Name = id, Text = "", AutoButtonColor = false, LayoutOrder = order, BackgroundColor3 = MEDIEVAL.WoodLight, Parent = parent })
	UITheme.Corner(card, 4)
	local stroke = UITheme.Stroke(card, MEDIEVAL.TrimDark, 1.5, 0)
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 135, 120)), Parent = card })
	local entry = { Kind = kind, Id = id, Frame = card, Stroke = stroke, Definition = definition }
	if kind == "WarBand" then
		entry.Icon = UITheme.ItemIcon({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(48, 48), Parent = card })
		entry.Title = Label({ Text = "UPGRADE MINIONS", Font = FONTS.Title, TextSize = 16, Position = UDim2.fromOffset(66, 6), Size = UDim2.fromOffset(330, 20), Parent = card })
		entry.Desc = Label({ Text = "", Font = FONTS.Medium, TextSize = 11, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(66, 26), Size = UDim2.fromOffset(420, 14), Parent = card })
		entry.Price = Label({ Text = "", Font = FONTS.Title, TextSize = 14, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(66, 42), Size = UDim2.fromOffset(140, 16), Parent = card })
		entry.Status = Label({ Text = "", Font = FONTS.Bold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -250, 0, 42), Size = UDim2.fromOffset(150, 14), Parent = card })
		entry.Summon = Button({ Name = "Upgrade", Text = "UPGRADE", Font = FONTS.Title, TextSize = 15, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(92, 32), Parent = card }, function()
			self:Select("WarBand", id)
			self:OnAction()
		end)
		entry.Icon.Set(definition)
	else
		local passive = kind == "Mythic" and ItemDefinitions.IsPassive(definition)
		entry.Icon = UITheme.ItemIcon({ Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(passive and 42 or 46, passive and 42 or 46), Parent = card })
		local textX = passive and 54 or 58
		local textW = passive and (-textX - 90) or (-textX - 4) -- passive BUY sits top-right
		local nameLabel = Label({ Text = definition.Name or definition.DisplayName, Font = FONTS.Bold, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(textX, 4), Size = UDim2.new(1, textW, 0, 16), Parent = card })
		nameLabel.TextScaled = true
		New("UITextSizeConstraint", { MaxTextSize = 12, Parent = nameLabel })
		entry.Tag = Label({ Text = "", Font = FONTS.Medium, TextSize = 10, TextColor3 = COLORS.Subtext, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(textX, 20), Size = UDim2.new(1, textW, 0, 13), Parent = card })
		entry.TagWidth = textW
		entry.Price = Label({ Text = definition.Price .. " g", Font = FONTS.Title, TextSize = 14, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(textX, passive and 34 or 40), Size = UDim2.fromOffset(70, 17), Parent = card })
		entry.Status = Label({ Text = "", Font = FONTS.Bold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, passive and 36 or 20), Size = UDim2.fromOffset(passive and 80 or 90, 12), Parent = card })
		-- the card's own BUY button (clicking the card body only selects it)
		entry.Buy = smallButton({ Name = "Buy", Text = "BUY", Font = FONTS.Title, TextSize = 12, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, AnchorPoint = Vector2.new(1, passive and 0 or 1), Position = passive and UDim2.new(1, -6, 0, 6) or UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(78, 22), Parent = card }, function()
			self:Select(kind, id)
			self:OnAction()
		end)
		if passive then
			-- stats + passive effect lines (the passive is the item's reason to exist)
			local statText = ItemDefinitions.GetStatText(definition)
			local statsLabel = Label({ Name = "Stats", Text = statText ~= "" and statText or "No stats", Font = FONTS.Medium, TextSize = 10, TextColor3 = COLORS.Text, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 53), Size = UDim2.new(1, -12, 0, 13), Parent = card })
			statsLabel.TextScaled = true
			New("UITextSizeConstraint", { MaxTextSize = 10, Parent = statsLabel })
			local passiveDef = definition.Passive or {}
			local passiveText = Label({ Name = "PassiveText", RichText = true, Text = string.format("<font color=\"#E2B85A\"><b>%s</b></font>  %s", passiveDef.Name or "Passive", passiveDef.Description or ""), Font = FONTS.Medium, TextSize = 10, TextColor3 = COLORS.Subtext, TextWrapped = true, TextScaled = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(6, 68), Size = UDim2.new(1, -12, 0, 32), Parent = card })
			New("UITextSizeConstraint", { MaxTextSize = 10, MinTextSize = 7, Parent = passiveText })
		end
		if kind == "Consumable" then
			entry.Icon.Set({ Icon = definition.Icon, Glyph = string.sub(definition.DisplayName, 1, 1), Color = Color3.fromRGB(90, 70, 50) })
		else
			entry.Icon.Set(definition)
		end
	end
	card.Activated:Connect(function()
		self:Select(kind, id)
	end)
	self.Cards[kind .. ":" .. id] = entry
	return entry
end

-- State helpers ------------------------------------------------------------------------
function ShopUI:GetMe()
	return self.ClientState.GetMe()
end

function ShopUI:GetGold()
	local attribute = player:GetAttribute("Gold")
	if attribute then
		return math.floor(attribute)
	end
	local me = self:GetMe()
	return math.floor(me and me.Stats and me.Stats.Gold or 0)
end

-- index 1 / 2 / 3 = mythic slots (E / R / SPACE), BOOT_SLOT (4) = boot slot (right mouse),
-- PASSIVE_BASE + 1..3 (5..7) = passive slots
function ShopUI:GetSlotItem(index)
	local me = self:GetMe()
	local id
	if index == BOOT_SLOT then
		id = me and me.Boots
	elseif index > PASSIVE_BASE then
		id = me and me.Passives and me.Passives[index - PASSIVE_BASE]
	else
		id = me and me.Mythics and me.Mythics[index]
	end
	return (id and id ~= "") and ItemDefinitions.GetItem(id) or nil
end

function ShopUI:OwnedSlot(itemId)
	local boots = self:GetSlotItem(BOOT_SLOT)
	if boots and boots.Id == itemId then
		return BOOT_SLOT
	end
	for index = 1, MAX_MYTHICS do
		local item = self:GetSlotItem(index)
		if item and item.Id == itemId then
			return index
		end
	end
	for index = PASSIVE_BASE + 1, PASSIVE_BASE + MAX_PASSIVES do
		local item = self:GetSlotItem(index)
		if item and item.Id == itemId then
			return index
		end
	end
	return nil
end

function ShopUI:SlotsFull()
	for index = 1, MAX_MYTHICS do
		if self:GetSlotItem(index) == nil then
			return false
		end
	end
	return true
end

function ShopUI:PassiveSlotsFull()
	for index = PASSIVE_BASE + 1, PASSIVE_BASE + MAX_PASSIVES do
		if not self:GetSlotItem(index) then
			return false
		end
	end
	return true
end

local function slotText(slot)
	if slot == BOOT_SLOT then
		return "BOOT SLOT (RMB)"
	elseif slot > PASSIVE_BASE then
		return "PASSIVE SLOT " .. (slot - PASSIVE_BASE)
	end
	return string.format("SLOT %d (%s)", slot, ItemDefinitions.SLOT_KEYS[slot])
end

-- Mirrors ShopService.CanShop so the UI can explain why buying is unavailable
function ShopUI:CanShopNow()
	if self.ClientState.GetMatchState() ~= STATE.ACTIVE then
		return false, "Shop opens during a match"
	end
	local me = self:GetMe()
	if not me then
		return false, ""
	end
	if me.State == "Dead" then
		return true, "Shopping while dead"
	end
	local character = self.ClientState.GetLocalCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local teamState = self.ClientState.GetTeamState(me.Team)
	if root and teamState and teamState.Position then
		if Util.FlatDistance(root.Position, teamState.Position) <= Constants.Flag.HEAL_RADIUS then
			return true, "At your base"
		end
		return false, "Return to your base to buy"
	end
	return true, ""
end

-- Returns statusText, color, canBuy (mythics, boots and passive items)
function ShopUI:GetMythicStatus(item)
	local me = self:GetMe()
	local slot = self:OwnedSlot(item.Id)
	if slot then
		return "EQUIPPED - " .. slotText(slot), GOOD, false
	end
	if not ItemDefinitions.CanClassUse(item, me and me.ClassKey) then
		return "LOCKED - Requires " .. item.Class, BAD, false
	end
	if ItemDefinitions.IsPassive(item) then
		if self:PassiveSlotsFull() then
			return string.format("PASSIVE SLOTS FULL (%d/%d) - sell one first", MAX_PASSIVES, MAX_PASSIVES), BAD, false
		end
		if self:GetGold() < item.Price then
			return "NOT ENOUGH GOLD", BAD, false
		end
		return "AVAILABLE - PASSIVE SLOT", COLORS.Gold, true
	end
	if ItemDefinitions.IsBoots(item) then
		-- boots never compete with mythics: they go to their own slot
		if self:GetGold() < item.Price then
			return "NOT ENOUGH GOLD", BAD, false
		end
		return "AVAILABLE - BOOT SLOT", COLORS.Gold, true
	end
	if self:GetGold() < item.Price and not self:SlotsFull() then
		return "NOT ENOUGH GOLD", BAD, false
	end
	if self:SlotsFull() then
		return "MYTHIC SLOTS FULL - replace?", COLORS.Warning, true
	end
	return "AVAILABLE", COLORS.Gold, true
end

-- Team minion upgrade level (replicated by CreepService as workspace attributes)
function ShopUI:GetMinionLevel()
	local me = self:GetMe()
	return me and me.Team and (workspace:GetAttribute("MinionLevel_" .. me.Team) or 0) or 0
end

function ShopUI:GetNextWaveIn()
	local at = workspace:GetAttribute("MinionNextWaveAt") or 0
	return math.max(0, at - workspace:GetServerTimeNow())
end

-- Returns statusText, color, canBuy, level, price (nil when maxed)
function ShopUI:GetWarBandStatus()
	local level = self:GetMinionLevel()
	local price = ItemDefinitions.GetMinionUpgradePrice(level)
	if not price then
		return "MAX LEVEL", GOOD, false, level, nil
	end
	if self:GetGold() < price then
		return "NOT ENOUGH GOLD", BAD, false, level, price
	end
	return string.format("LEVEL %d  >  %d", level, level + 1), GOOD, true, level, price
end

-- Selection / details ------------------------------------------------------------------
function ShopUI:Select(kind, id)
	self.Selected = { Kind = kind, Id = id }
	self.SellConfirm = nil
	self:RefreshDetails()
end

local function statLines(lines)
	local parts = {}
	for _, line in ipairs(lines) do
		table.insert(parts, string.format("<b>%s:</b> %s", line[1], line[2]))
	end
	return table.concat(parts, "\n")
end

function ShopUI:RefreshDetails()
	local selected = self.Selected
	if not selected then
		return
	end
	local canShop, accessReason = self:CanShopNow()
	self.SellButton.Visible = false
	if selected.Kind == "Mythic" then
		local item = ItemDefinitions.GetItem(selected.Id)
		local ability = ItemDefinitions.GetAbility(item.Ability)
		local isPassive = ItemDefinitions.IsPassive(item)
		self.DetailIcon.Set(item)
		self.DetailName.Text = item.Name
		local kindText = isPassive and "PASSIVE ITEM (automatic)" or (ItemDefinitions.IsBoots(item) and (string.upper(item.BootType or "") .. " BOOTS (RMB)") or "MYTHIC (SPACE / E / R)")
		self.DetailClass.Text = (item.Class and ("CLASS: " .. string.upper(item.Class)) or "CLASS: ANY") .. "   |   " .. kindText
		self.DetailPrice.Text = string.format("PRICE: %d GOLD   (sells for %d)", item.Price, ItemDefinitions.GetSellValue(item))
		local stats = ItemDefinitions.GetStatText(item)
		local statGold, skillGold, passiveGold = ItemDefinitions.GetItemGoldValue(item)
		local value = string.format("<b>Value:</b> stats %dg%s%s", statGold, skillGold > 0 and string.format(" + skill %dg", skillGold) or "", passiveGold > 0 and string.format(" + passive %dg", passiveGold) or "")
		if isPassive then
			local passiveDef = item.Passive or {}
			self.DetailBody.Text = string.format("<i>%s</i>\n<b>Stats:</b> %s\n\n<b>PASSIVE: %s</b>\n%s%s\n\n%s\n<font color=\"#644C34\">Works automatically while equipped - no hotkey.</font>",
				item.Description or "", stats ~= "" and stats or "none", string.upper(passiveDef.Name or "-"), passiveDef.Description or "",
				passiveDef.Details and ("\n<font color=\"#644C34\">" .. passiveDef.Details .. "</font>") or "", value)
		else
			self.DetailBody.Text = string.format("<i>%s</i>\n%s\n%s\n<b>ABILITY: %s</b>\n%s\n%s", item.Description or "",
				stats ~= "" and ("<b>Stats:</b> " .. stats) or "", value,
				ability and string.upper(ability.Name) or "-", ability and ability.Summary or "",
				ability and statLines(ItemDefinitions.GetAbilityStatLines(ability, AbilityScaling.StatsFromModel(self.ClientState.GetLocalCharacter()))) or "")
			local manaCost = ability and ItemDefinitions.GetSlotManaCost(ability, ItemDefinitions.IsBoots(item)) or 0
			if manaCost > 0 then
				self.DetailBody.Text ..= string.format("\n<b>Mana cost:</b> %d", manaCost)
			end
		end
		local text, color, canBuy = self:GetMythicStatus(item)
		local owned = self:OwnedSlot(item.Id)
		self.DetailStatus.Text = owned and text or (canShop and text or (text .. "  |  " .. accessReason))
		self.DetailStatus.TextColor3 = color:Lerp(INK, 0.45)
		self.ActionButton.Text = owned and "EQUIPPED" or (text:find("LOCKED") and "LOCKED" or (text:find("PASSIVE SLOTS FULL") and "SLOTS FULL" or "BUY"))
		UITheme.SetButtonColor(self.ActionButton, (canBuy and canShop) and COLORS.Gold or DISABLED)
		if owned then
			self.SellButton.Visible = true
			local confirming = self.SellConfirm and self.SellConfirm.Slot == owned and os.clock() < self.SellConfirm.Expires
			self.SellButton.Text = confirming and string.format("CONFIRM +%d", ItemDefinitions.GetSellValue(item)) or "SELL"
		end
	elseif selected.Kind == "Consumable" then
		local item = ShopDefinitions.Get(selected.Id)
		local me = self:GetMe()
		local count = me and me.Purchases and me.Purchases[item.Key] or 0
		self.DetailIcon.Set({ Icon = item.Icon, Glyph = string.sub(item.DisplayName, 1, 1), Color = Color3.fromRGB(90, 70, 50) })
		self.DetailName.Text = item.DisplayName
		self.DetailClass.Text = "CLASS: ANY   |   STAT ITEM (stacks)"
		self.DetailPrice.Text = string.format("PRICE: %d GOLD", ShopDefinitions.GetBuyPrice(item, count))
		local sellText = ""
		if count > 0 then
			local stamps = me.PurchaseTimestamps and me.PurchaseTimestamps[item.Key]
			local oldest = stamps and stamps[1] or os.time()
			local price = ShopDefinitions.GetSellPrice(item, oldest)
			sellText = string.format("\n<b>Sell value:</b> %d gold%s", price, price >= item.Price and " (full refund)" or "")
			self.SellButton.Visible = true
			self.SellButton.Text = "SELL 1"
		end
		self.DetailBody.Text = string.format("%s\n\n<b>Owned:</b> x%d%s\n\nFull refund within %ds of buying, then %d%%.", item.Description, count, sellText,
			ShopDefinitions.FULL_REFUND_WINDOW, ShopDefinitions.SELL_RATIO * 100)
		local affordable = self:GetGold() >= ShopDefinitions.GetBuyPrice(item, count)
		self.DetailStatus.Text = not canShop and accessReason or (affordable and "AVAILABLE" or "NOT ENOUGH GOLD")
		self.DetailStatus.TextColor3 = ((canShop and affordable) and GOOD or BAD):Lerp(INK, 0.45)
		self.ActionButton.Text = "BUY"
		UITheme.SetButtonColor(self.ActionButton, (canShop and affordable) and COLORS.Gold or DISABLED)
	else
		local upgrade, waves, band = ItemDefinitions.MinionUpgrade, ItemDefinitions.MinionWaves, ItemDefinitions.CreepWave
		local text, color, canBuy, level, price = self:GetWarBandStatus()
		local now = ItemDefinitions.GetMinionStats(level)
		local nextStats = price and ItemDefinitions.GetMinionStats(level + 1) or nil
		self.DetailIcon.Set(upgrade)
		self.DetailName.Text = "UPGRADE MINIONS"
		self.DetailClass.Text = string.format("TEAM UPGRADE   |   LEVEL %d / %d", level, upgrade.MaxLevel)
		self.DetailPrice.Text = price and string.format("NEXT LEVEL: %d GOLD", price) or "FULLY UPGRADED"
		local function statRow(label, current, nextValue)
			return nextValue and string.format("<b>%s:</b> %d  >  <b>%d</b>", label, current, nextValue) or string.format("<b>%s:</b> %d", label, current)
		end
		self.DetailBody.Text = string.format("<i>%s</i>\n\nEvery %d sec your base sends %d minions toward the nearest enemy base. Upgrades apply to your WHOLE team's minions (current and future) and teammates' purchases stack.\n\n%s\n%s\n%s\n<b>Next wave in:</b> %d sec\n<b>Enemy reward:</b> +%d gold per minion killed",
			upgrade.Description, waves.Interval, waves.Count,
			statRow("Health", now.MaxHealth, nextStats and nextStats.MaxHealth),
			statRow("Damage", now.Damage, nextStats and nextStats.Damage),
			statRow("Armor", now.Armor, nextStats and nextStats.Armor),
			math.ceil(self:GetNextWaveIn()), band.KillReward)
		self.DetailStatus.Text = canShop and text or (text .. "  |  " .. accessReason)
		self.DetailStatus.TextColor3 = color:Lerp(INK, 0.45)
		self.ActionButton.Text = price and "UPGRADE" or "MAXED"
		UITheme.SetButtonColor(self.ActionButton, (canBuy and canShop) and COLORS.Gold or DISABLED)
	end
end

-- Actions ------------------------------------------------------------------------------
function ShopUI:OnAction()
	local selected = self.Selected
	if not selected then
		return
	end
	local canShop, reason = self:CanShopNow()
	if not canShop then
		self.ClientState.LocalMessage:Fire(reason ~= "" and reason or "You cannot shop right now", "Warning")
		return
	end
	if selected.Kind == "Mythic" then
		local item = ItemDefinitions.GetItem(selected.Id)
		if self:OwnedSlot(item.Id) then
			return
		end
		local me = self:GetMe()
		if not ItemDefinitions.CanClassUse(item, me and me.ClassKey) then
			self.ClientState.LocalMessage:Fire("LOCKED - Requires " .. item.Class, "Warning")
			return
		end
		if ItemDefinitions.IsPassive(item) then
			if self:PassiveSlotsFull() then
				self.ClientState.LocalMessage:Fire(string.format("Passive slots full (%d/%d) - sell a passive item first", MAX_PASSIVES, MAX_PASSIVES), "Warning")
				return
			end
		elseif self:SlotsFull() and not ItemDefinitions.IsBoots(item) then
			self:OpenReplaceDialog(item)
			return
		end
		self.Remotes.ItemRequest:FireServer("Buy", item.Id)
	elseif selected.Kind == "Consumable" then
		self.Remotes.ShopRequest:FireServer(selected.Id)
	else
		self.Remotes.ItemRequest:FireServer("UpgradeMinions")
	end
end

function ShopUI:OnSellSelected()
	local selected = self.Selected
	if not selected then
		return
	end
	if selected.Kind == "Consumable" then
		self.Remotes.SellRequest:FireServer(selected.Id)
	elseif selected.Kind == "Mythic" then
		local slot = self:OwnedSlot(selected.Id)
		if slot then
			self:OnSellSlot(slot)
		end
	end
end

-- Two-step sell for equipped items so an item is never deleted by a single misclick
function ShopUI:OnSellSlot(index)
	local item = self:GetSlotItem(index)
	if not item then
		return
	end
	if self.SellConfirm and self.SellConfirm.Slot == index and os.clock() < self.SellConfirm.Expires then
		self.SellConfirm = nil
		self.Remotes.ItemRequest:FireServer("Sell", index)
	else
		self.Selected = { Kind = "Mythic", Id = item.Id }
		self:RefreshDetails()
		self.SellConfirm = { Slot = index, Expires = os.clock() + 3 }
		self.ClientState.LocalMessage:Fire(string.format("Click SELL again to sell %s for %d gold", item.Name, ItemDefinitions.GetSellValue(item)), "Info")
	end
	self:Refresh()
end

function ShopUI:OpenReplaceDialog(item)
	self.PendingReplace = item.Id
	self.ReplaceText.Text = string.format("All mythic slots are occupied. Choose a slot for %s - the item there is sold back for half its price. Nothing is replaced unless you choose.", item.Name)
	for index, button in ipairs(self.ReplaceButtons) do
		local current = self:GetSlotItem(index)
		button.Text = current and string.format("REPLACE SLOT %d (%s)\n%s  (+%d gold)", index, ItemDefinitions.SLOT_KEYS[index], current.Name, ItemDefinitions.GetSellValue(current)) or ("SLOT " .. index)
	end
	self.ReplaceDialog.Visible = true
end

function ShopUI:ConfirmReplace(index)
	self.ReplaceDialog.Visible = false
	if self.PendingReplace then
		self.Remotes.ItemRequest:FireServer("Buy", self.PendingReplace, index)
		self.PendingReplace = nil
	end
end

-- Refresh ------------------------------------------------------------------------------
local function itemTag(item)
	if ItemDefinitions.IsPassive(item) then
		return item.Class and (item.Class .. " only") or "Any class"
	elseif ItemDefinitions.IsBoots(item) then
		return item.BootType and (item.BootType .. " boots - RMB") or "Boots - Right Mouse"
	end
	local ability = ItemDefinitions.GetAbility(item.Ability)
	return (ability and (ability.Name .. " - ") or "") .. (item.Class and ("Requires " .. item.Class) or "Any class")
end

function ShopUI:Refresh()
	if not self.Root.Visible then
		return
	end
	local gold = self:GetGold()
	self.GoldLabel.Text = string.format("PLAYER GOLD: %04d", gold)
	local canShop, reason = self:CanShopNow()
	self.AccessLabel.Text = (reason ~= "" and reason or "") .. "   [B] close"
	self.AccessLabel.TextColor3 = canShop and COLORS.Subtext or BAD
	local me = self:GetMe()
	self:RefreshTabs()
	local passiveFull = self:PassiveSlotsFull()
	for _, entry in pairs(self.Cards) do
		local text, color
		if entry.Kind == "Mythic" then
			local item = entry.Definition
			text, color = self:GetMythicStatus(item)
			entry.Tag.Text = itemTag(item)
			local locked = text:find("LOCKED") ~= nil
			local owned = self:OwnedSlot(item.Id)
			entry.Frame.BackgroundColor3 = locked and Color3.fromRGB(40, 32, 28) or MEDIEVAL.WoodLight
			entry.Icon.Frame.BackgroundTransparency = locked and 0.5 or 0
			entry.Stroke.Color = owned and GOOD or (locked and Color3.fromRGB(80, 50, 40) or MEDIEVAL.TrimDark)
			local buyText, buyColor
			if owned then
				text = slotText(owned)
				buyText, buyColor = "OWNED", GOOD:Lerp(Color3.new(0, 0, 0), 0.35)
			elseif locked then
				text = ""
				buyText, buyColor = "LOCKED", Color3.fromRGB(70, 55, 45)
			elseif ItemDefinitions.IsPassive(item) and passiveFull then
				text = "3/3 PASSIVES"
				buyText, buyColor = "FULL", DISABLED
			elseif self:SlotsFull() and not ItemDefinitions.IsBoots(item) and not ItemDefinitions.IsPassive(item) then
				text = "SLOTS FULL"
				buyText, buyColor = "REPLACE", canShop and COLORS.Gold or DISABLED
			elseif gold < item.Price then
				text = ""
				buyText, buyColor = string.format("NEED %d", item.Price - gold), DISABLED
			else
				text = canShop and "" or "AT BASE ONLY"
				buyText, buyColor = "BUY", canShop and COLORS.Gold or DISABLED
			end
			entry.Buy.Text = buyText
			UITheme.SetButtonColor(entry.Buy, buyColor)
			if not ItemDefinitions.IsPassive(item) then
				entry.Tag.Size = UDim2.new(1, text ~= "" and (entry.TagWidth - 92) or entry.TagWidth, 0, 13)
			end
		elseif entry.Kind == "Consumable" then
			local count = me and me.Purchases and me.Purchases[entry.Id] or 0
			local buyPrice = ShopDefinitions.GetBuyPrice(entry.Definition, count)
			entry.Tag.Text = entry.Definition.Description
			entry.Price.Text = buyPrice .. " g"
			local affordable = gold >= buyPrice
			text, color = "", COLORS.Gold
			if count > 0 then
				text = string.format("OWNED x%d", count)
				color = GOOD
			end
			entry.Buy.Text = affordable and "BUY" or string.format("NEED %d", buyPrice - gold)
			UITheme.SetButtonColor(entry.Buy, (affordable and canShop) and COLORS.Gold or DISABLED)
			entry.Tag.Size = UDim2.new(1, text ~= "" and (entry.TagWidth - 92) or entry.TagWidth, 0, 13)
		else
			local canBuy, level, price
			text, color, canBuy, level, price = self:GetWarBandStatus()
			entry.Title.Text = string.format("UPGRADE MINIONS  -  LV %d / %d", level, ItemDefinitions.MinionUpgrade.MaxLevel)
			local stats = ItemDefinitions.GetMinionStats(level)
			entry.Desc.Text = string.format("Team minions: %d HP, %d dmg, %d armor  |  next wave in %ds", stats.MaxHealth, stats.Damage, stats.Armor, math.ceil(self:GetNextWaveIn()))
			entry.Price.Text = price and (price .. " GOLD") or "MAXED"
			entry.Summon.Text = price and "UPGRADE" or "MAX"
			UITheme.SetButtonColor(entry.Summon, (canBuy and canShop) and COLORS.Gold or DISABLED)
		end
		entry.Status.Text = text
		entry.Status.TextColor3 = color
	end
	for index, tile in pairs(self.SlotTiles) do
		local item = self:GetSlotItem(index)
		tile.Icon.Set(item)
		tile.Name.Text = item and item.Name or "EMPTY"
		tile.Name.TextColor3 = item and COLORS.Text or COLORS.Subtext
		tile.Sell.Visible = item ~= nil
		local confirming = self.SellConfirm and self.SellConfirm.Slot == index and os.clock() < self.SellConfirm.Expires
		tile.Sell.Text = item and (confirming and string.format("OK +%d", ItemDefinitions.GetSellValue(item)) or string.format("SELL %d", ItemDefinitions.GetSellValue(item))) or ""
		tile.Stroke.Color = item and MEDIEVAL.Trim or MEDIEVAL.TrimDark
	end
	self:RefreshDetails()
end

function ShopUI:SetVisible(visible)
	if visible and self.ClientState.GetMatchState() ~= STATE.ACTIVE then
		return
	end
	self.Root.Visible = visible
	if not visible then
		self.ReplaceDialog.Visible = false
		self.Dragging = nil
		self.DragGhost.Frame.Visible = false
	else
		-- open on the player's own class tab unless they picked a tab since the last class change
		local me = self:GetMe()
		local classKey = me and me.ClassKey
		if classKey ~= self.LastClass then
			self.LastClass = classKey
			self.TabChosenManually = false
		end
		if not self.TabChosenManually then
			self:ShowTab(self.Pages[classKey] and classKey or "General")
		end
		self:Refresh()
		if not self.RefreshLoop then
			self.RefreshLoop = true
			task.spawn(function()
				while self.Root.Visible do
					self:Refresh()
					task.wait(0.25)
				end
				self.RefreshLoop = false
			end)
		end
	end
end

function ShopUI:Update(state)
	if state and state.State ~= STATE.ACTIVE and self.Root.Visible then
		self:SetVisible(false)
		return
	end
	self:Refresh()
end

return ShopUI
