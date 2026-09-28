-- HUD.AbilityBar: bottom-right combat / item controls.
--   LM = MELEE (basic attack)   Q = class ability (BLOOD RUSH for the Fighter)
--   E / R = ITEM slots (mythic item 1 / 2)   MR = BOOTS
--   PASSIVE 1 / 2 / 3 = passive items (automatic, no hotkey), next to the boots
-- Hovering the boots or a passive cell shows SlotTooltip (item name + effect).
-- Cooldowns come from replicated character attributes / participant state. Drag E onto R (or
-- back) to swap the two item slots; the hotkeys follow automatically (server-side swap).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local ProceduralIcon = require(Shared:WaitForChild("ProceduralIcon"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local find = require(script.Parent:WaitForChild("Bind")).find

local C, A = Theme.Colors, Theme.Art

local AbilityBar = {}
AbilityBar.__index = AbilityBar

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

-- mouse position in the same space as GuiObject.AbsolutePosition (GetMouseLocation counts the
-- top-bar inset, AbsolutePosition does not - true for every ScreenGui, IgnoreGuiInset or not)
local function mouseInGui()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function isOver(frame, pos)
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return frame.Parent ~= nil and s.X > 0 and pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

-- item text shown in a RichText label
local function esc(text)
	return (string.gsub(string.gsub(string.gsub(text or "", "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

function AbilityBar.new(group, clientState, combatController)
	local self = setmetatable({}, AbilityBar)
	self.Group = group
	self.ClientState = clientState
	self.CombatController = combatController
	self.Remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.Slots = {}
	for _, def in ipairs(Theme.Slots) do
		local frameKey = def.Frame or def.Key -- the painted HUD slot this key uses
		local slot = "Slot" .. frameKey
		self.Slots[def.Key] = {
			Def = def, Frame = find(group, slot, "Frame"), Icon = find(group, slot .. ".Icon", "ImageLabel"), Glyph = find(group, slot .. ".Glyph", "TextLabel"),
			Cooldown = find(group, slot .. ".Cooldown", "Frame"), Timer = find(group, slot .. ".Timer", "TextLabel"), Count = find(group, slot .. ".Count", "Frame"),
			CountValue = find(group, slot .. ".Count.Value", "TextLabel"), Ready = find(group, slot .. ".Ready", "UIStroke"),
			Name = find(group, "Name" .. frameKey, "TextLabel"), KeyLabel = find(group, "Key" .. frameKey, "TextLabel"),
		}
		setText(self.Slots[def.Key].Name, def.Name)
	end
	-- item slot table (same shape the rest of the client used before)
	self.ItemSlots = {
		E = { Frame = self.Slots.E.Frame, Index = 1, KeyName = "E" },
		R = { Frame = self.Slots.R.Frame, Index = 2, KeyName = "R" },
		SPACE = { Frame = self.Slots.SPACE.Frame, Index = 3, KeyName = "SPACE" },
		M2 = { Frame = self.Slots.MR.Frame, Index = ItemDefinitions.BOOT_SLOT, KeyName = "M2", IsBoots = true },
	}
	-- passive item slots (no hotkey): PASSIVE 1 / 2 / 3, filled from me.Passives
	self.PassiveSlots = {}
	for n = 1, ItemDefinitions.MAX_PASSIVE_SLOTS or 3 do
		local path = "Passive" .. n
		self.PassiveSlots[n] = {
			Index = n, Frame = find(group, path, "Frame"), Icon = find(group, path .. ".Icon", "ImageLabel"), Glyph = find(group, path .. ".Glyph", "TextLabel"),
			Number = find(group, path .. ".Number", "TextLabel"), Caption = find(group, path .. ".Caption", "TextLabel"), Highlight = find(group, path .. ".Highlight", "UIStroke"),
		}
	end
	self.Tooltip = {
		Frame = find(group, "SlotTooltip", "Frame"), Title = find(group, "SlotTooltip.Title", "TextLabel"),
		Sub = find(group, "SlotTooltip.Sub", "TextLabel"), Body = find(group, "SlotTooltip.Body", "TextLabel"),
	}
	self.Tooltip.Frame.Visible = false
	self:StyleTooltip()
	self:FitIcons()
	self:StyleKeyBadges()
	self:SetupDragging()
	return self
end

function AbilityBar:GetSlotItem(key)
	local me = self.ClientState.GetMe()
	local entry = self.ItemSlots[key]
	if not entry or not me then
		return nil
	end
	local itemId = entry.IsBoots and me.Boots or (me.Mythics and me.Mythics[entry.Index])
	if not itemId or itemId == "" then
		return nil
	end
	return ItemDefinitions.GetItem(itemId)
end

function AbilityBar:GetPassiveItem(index)
	local me = self.ClientState.GetMe()
	local itemId = me and me.Passives and me.Passives[index]
	if not itemId or itemId == "" then
		return nil
	end
	return ItemDefinitions.GetItem(itemId)
end

function AbilityBar:RequestSwap(from, to)
	if from and to and from ~= to then
		self.Remotes.ItemRequest:FireServer("Swap", from, to)
	end
end

function AbilityBar:SetupDragging()
	local function over(frame, pos)
		local p, s = frame.AbsolutePosition, frame.AbsoluteSize
		return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
	end
	-- mouse positions are converted to AbsolutePosition space (see mouseInGui)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not self.Group.Visible or not self.Group:FindFirstAncestorWhichIsA("GuiObject").Visible then
			return
		end
		local mouse = mouseInGui()
		for key, entry in pairs(self.ItemSlots) do
			if not entry.IsBoots and over(entry.Frame, mouse) and self:GetSlotItem(key) then
				self.Dragging = entry
				return
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not self.Dragging then
			return
		end
		local from = self.Dragging
		self.Dragging = nil
		local mouse = mouseInGui()
		for _, entry in pairs(self.ItemSlots) do
			if entry ~= from and not entry.IsBoots and over(entry.Frame, mouse) then
				self:RequestSwap(from.Index, entry.Index)
				break
			end
		end
	end)
end

-- on replicated match-state change: labels / icons that depend on the class
function AbilityBar:Update(me)
	local classDef = me and ClassDefinitions.Get(me.ClassKey)
	if not classDef then
		return
	end
	local q = self.Slots.Q
	self.QManaCost = classDef.Ability and classDef.Ability.ManaCost or 0
	local abilityName = classDef.Ability and classDef.Ability.Name or "ABILITY"
	setText(q.Name, string.upper(abilityName))
	q.Icon.Image = Theme.AbilityIcons[abilityName] or classDef.IconImage or A.IconBloodRush
end

local function cooldown(slot, remaining, total, hasContent, aiming)
	local fraction = total > 0 and math.clamp(remaining / total, 0, 1) or 0
	slot.Cooldown.Size = UDim2.fromScale(1, fraction)
	slot.Cooldown.Visible = fraction > 0.001
	setText(slot.Timer, remaining > 0.05 and total > 1.5 and tostring(math.ceil(remaining)) or "")
	slot.Ready.Color = aiming and Color3.fromRGB(255, 90, 70) or C.GoldBright
	slot.Ready.Transparency = (aiming or (hasContent and remaining <= 0)) and 0.25 or 1
end

-- per-frame (cheap): cooldown overlays; item icons only change when the item changes
function AbilityBar:Tick(character, now, me)
	local targeting = self.CombatController and self.CombatController.Targeting
	if character then
		local abilityCd = character:GetAttribute("AbilityCooldown") or 1
		-- Q with a mana cost (Mage Arcane Burst): tint the icon blue while there is not enough mana
		local q = self.Slots.Q
		local qManaCost = self.QManaCost or 0
		local qNoMana = qManaCost > 0 and (character:GetAttribute("Mana") or 0) < qManaCost
		if q.NoMana ~= qNoMana then
			q.NoMana = qNoMana
			q.Icon.ImageColor3 = qNoMana and Color3.fromRGB(95, 125, 225) or Color3.new(1, 1, 1)
		end
		cooldown(q, (character:GetAttribute("AbilityReadyAt") or 0) - now, abilityCd, not qNoMana, false)
	else
		cooldown(self.Slots.Q, 0, 1, false, false)
	end
	for key, entry in pairs(self.ItemSlots) do
		local slot = entry.IsBoots and self.Slots.MR or self.Slots[key]
		local item = self:GetSlotItem(key)
		local itemId = item and item.Id or false
		if slot.ItemId ~= itemId then
			slot.ItemId = itemId
			local placeholder = entry.IsBoots and A.IconBoots or A.IconItem
			local hasArt = item ~= nil and item.Icon ~= nil and item.Icon ~= ""
			slot.Icon.Image = hasArt and item.Icon or (item and "" or placeholder)
			slot.Icon.ImageTransparency = item and 0 or 0.6
			slot.Glyph.Visible = false
			slot.Glyph.Text = ""
			if item and not hasArt then
				ProceduralIcon.Populate(slot.Frame, item)
				slot.Icon.ImageTransparency = 1
			else
				ProceduralIcon.Clear(slot.Frame)
			end
		end
		local ability = item and ItemDefinitions.GetAbility(item.Ability)
		local remaining, total = 0, 1
		if item and ability then
			remaining = (me and me.ItemReadyAt and me.ItemReadyAt[item.Id] or 0) - now
			-- Cooldown Reduction (item stat) shortens the server cooldown; match it here
			total = (ability.Cooldown or 1) * (1 - (character and character:GetAttribute("CooldownReduction") or 0))
		end
		-- E / R cost mana (boots only when their skill sets ManaCost): tint the icon blue while there is not enough
		local mana = character and character:GetAttribute("Mana")
		local noMana = ability ~= nil and mana ~= nil and mana < ItemDefinitions.GetSlotManaCost(ability, entry.IsBoots)
		if slot.NoMana ~= noMana then
			slot.NoMana = noMana
			slot.Icon.ImageColor3 = noMana and Color3.fromRGB(95, 125, 225) or Color3.new(1, 1, 1)
		end
		cooldown(slot, remaining, total, item ~= nil and ability ~= nil and not noMana, targeting and targeting.Key == key)
		local charges = item and me and me.ItemCharges and me.ItemCharges[item.Id]
		slot.Count.Visible = charges ~= nil and charges > 1
		if charges then
			setText(slot.CountValue, tostring(charges))
		end
	end
	-- passive slots: icons change only when the equipped item changes (right after a purchase)
	for index, slot in ipairs(self.PassiveSlots) do
		local item = self:GetPassiveItem(index)
		local itemId = item and item.Id or false
		if slot.ItemId ~= itemId then
			slot.ItemId = itemId
			local hasArt = item ~= nil and item.Icon ~= nil and item.Icon ~= ""
			slot.Icon.Image = hasArt and item.Icon or ""
			slot.Icon.Visible = hasArt
			slot.Glyph.Visible = false
			slot.Glyph.Text = ""
			if item and not hasArt then
				ProceduralIcon.Populate(slot.Frame, item)
			else
				ProceduralIcon.Clear(slot.Frame)
			end
			slot.Number.Visible = item == nil
			slot.Caption.Visible = item == nil
		end
	end
	self:UpdateTooltip()
end

-- The icon images in the place cover only ~80% of their slot and are stretched when a slot
-- is not perfectly square. Make every icon fill its whole slot edge to edge, cropped (never
-- squashed), with the slot's rounded corners.
function AbilityBar:FitIcons()
	local cells = {}
	for _, slot in pairs(self.Slots) do
		table.insert(cells, slot)
	end
	for _, slot in ipairs(self.PassiveSlots) do
		table.insert(cells, slot)
	end
	for _, cell in ipairs(cells) do
		local icon, frame = cell.Icon, cell.Frame
		if icon and frame then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(1, 1)
			icon.ScaleType = Enum.ScaleType.Crop
			icon.BackgroundTransparency = 1
			local frameCorner = frame:FindFirstChildOfClass("UICorner")
			if frameCorner and not icon:FindFirstChildOfClass("UICorner") then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = frameCorner.CornerRadius
				corner.Parent = icon
			end
		end
	end
end

-- The key tabs painted into the bar art end up underneath the slot frame and
-- icon. Draw a real badge instead: parented to its slot, centred on it horizontally, resting on
-- the slot's top edge, above everything in the slot (and large enough to hide the painted tab).
local BADGE_Z = 12
function AbilityBar:StyleKeyBadges()
	for _, slot in pairs(self.Slots) do
		local badge, frame = slot.KeyLabel, slot.Frame
		if badge and frame then
			frame.ClipsDescendants = false
			badge.Parent = frame
			badge.AnchorPoint = Vector2.new(0.5, 1)
			badge.Position = UDim2.new(0.5, 0, 0.1, 0)
			-- a full-width plate: wide and tall enough to hide the old painted key tab completely
			badge.Size = UDim2.fromScale(1.1, 0.46)
			badge.ZIndex = BADGE_Z
			badge.Text = slot.Def.Key
			badge.TextXAlignment = Enum.TextXAlignment.Center
			badge.TextYAlignment = Enum.TextYAlignment.Center
			badge.Font = Enum.Font.Merriweather
			badge.TextScaled = true
			badge.TextColor3 = Color3.fromRGB(245, 225, 175)
			badge.TextStrokeTransparency = 0.5
			badge.BackgroundColor3 = Color3.fromRGB(34, 20, 14)
			badge.BackgroundTransparency = 0
			if not badge:FindFirstChild("BadgeCorner") then
				local corner = Instance.new("UICorner")
				corner.Name = "BadgeCorner"
				corner.CornerRadius = UDim.new(0.2, 0)
				corner.Parent = badge
				local stroke = Instance.new("UIStroke")
				stroke.Name = "BadgeStroke"
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Color = Color3.fromRGB(214, 170, 80)
				stroke.Thickness = 1.5
				stroke.Parent = badge
				local padding = Instance.new("UIPadding")
				padding.PaddingTop = UDim.new(0.14, 0)
				padding.PaddingBottom = UDim.new(0.14, 0)
				padding.PaddingLeft = UDim.new(0.1, 0)
				padding.PaddingRight = UDim.new(0.1, 0)
				padding.Parent = badge
				local limit = Instance.new("UITextSizeConstraint")
				limit.MaxTextSize = 16
				limit.Parent = badge
			end
		end
	end
end

-- The tooltip in the place shrinks its text to fit a small fixed box (unreadable for long
-- passives). Use a wider box with fixed, readable text sizes that grows upward to fit the text.
local TIP_WIDTH, TIP_PAD, TIP_BODY_TOP = 400, 12, 58
function AbilityBar:StyleTooltip()
	local tip = self.Tooltip
	tip.Frame.AnchorPoint = Vector2.new(1, 1)
	tip.Frame.Position = UDim2.new(1, 0, 0, -8)
	tip.Frame.ZIndex = math.max(tip.Frame.ZIndex, 20)
	local function style(label, top, height, size)
		label.TextScaled = false
		label.TextSize = size
		label.TextWrapped = true
		label.Position = UDim2.fromOffset(TIP_PAD, top)
		label.Size = UDim2.new(1, -TIP_PAD * 2, 0, height)
		label.ZIndex = tip.Frame.ZIndex + 1
		local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
		if constraint then
			constraint:Destroy()
		end
	end
	style(tip.Title, 8, 24, 21)
	style(tip.Sub, 34, 18, 14)
	style(tip.Body, TIP_BODY_TOP, 40, 16)
	tip.Body.TextYAlignment = Enum.TextYAlignment.Top
	self:FitTooltip()
end

function AbilityBar:FitTooltip()
	local tip = self.Tooltip
	local width = TIP_WIDTH - TIP_PAD * 2
	tip.Body.Size = UDim2.new(1, -TIP_PAD * 2, 0, 1000)
	local height = math.max(20, tip.Body.TextBounds.Y)
	tip.Body.Size = UDim2.new(1, -TIP_PAD * 2, 0, height + 4)
	tip.Frame.Size = UDim2.fromOffset(width + TIP_PAD * 2, TIP_BODY_TOP + height + 14)
end

-- hover tooltip for the boots cell and the passive cells (mouse position, checked per frame)
function AbilityBar:UpdateTooltip()
	local hovered, kind = nil, nil
	if self.Group.Visible and not self.Dragging then
		local mouse = mouseInGui()
		if isOver(self.Slots.MR.Frame, mouse) then
			hovered, kind = self.Slots.MR, "Boots"
		else
			for _, slot in ipairs(self.PassiveSlots) do
				if isOver(slot.Frame, mouse) then
					hovered, kind = slot, "Passive"
					break
				end
			end
		end
	end
	for _, slot in ipairs(self.PassiveSlots) do
		slot.Highlight.Transparency = slot == hovered and 0 or (slot.ItemId and 0.45 or 1)
	end
	local key = hovered and (kind .. tostring(hovered.Index) .. ":" .. tostring(hovered.ItemId)) or nil
	if key == self.TooltipKey then
		return
	end
	self.TooltipKey = key
	local tip = self.Tooltip
	tip.Frame.Visible = hovered ~= nil
	if not hovered then
		return
	end
	if kind == "Boots" then
		local item = self:GetSlotItem("M2")
		local ability = item and ItemDefinitions.GetAbility(item.Ability)
		setText(tip.Title, item and string.upper(item.Name) or "BOOTS")
		setText(tip.Sub, "BOOTS  |  MR (right mouse)")
		tip.Body.Text = item and string.format("<b>%s</b> - %s", esc(ability and ability.Name or "Ability"), esc(ability and ability.Summary or item.Description))
			or "Empty. Buy boots in the shop (B)."
	else
		local index = hovered.Index
		local item = self:GetPassiveItem(index)
		setText(tip.Title, item and string.upper(item.Name) or ("PASSIVE " .. index))
		setText(tip.Sub, string.format("PASSIVE %d  |  automatic, no hotkey", index))
		if item then
			local passive = item.Passive or {}
			local stats = ItemDefinitions.GetStatText(item)
			-- live bonus of stacking passives (per match)
			local me = self.ClientState.GetMe()
			local stacks = me and me.PassiveStacks or {}
			local live = ""
			if passive.Effect == "SoulHarvest" then
				live = string.format(" <font color=\"#E2B85A\">(now +%d max HP)</font>", stacks.SoulHarvest or 0)
			elseif passive.Effect == "Overgrowth" then
				live = string.format(" <font color=\"#E2B85A\">(now +%d max HP)</font>", stacks.OvergrowthHP or 0)
			end
			tip.Body.Text = string.format("<b>%s:</b> %s%s%s%s", esc(passive.Name or "Passive"), esc(passive.Description),
				passive.Details and (" " .. esc(passive.Details)) or "", live,
				stats ~= "" and ("\n<font color=\"#B0A28A\">" .. esc(stats) .. "</font>") or "")
		else
			tip.Body.Text = "Empty. Passive items bought in the shop (B) go here automatically - up to 3."
		end
	end
	self:FitTooltip()
	task.defer(function() -- TextBounds of RichText settles after layout
		if self.TooltipKey == key then
			self:FitTooltip()
		end
	end)
end

return AbilityBar
