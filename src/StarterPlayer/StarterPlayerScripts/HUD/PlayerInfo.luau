-- HUD.PlayerInfo: bottom-left portrait (avatar headshot, level/kill badge), class, role, gold,
-- health (+ shield), mana and status chips. Health / mana react to the character's replicated
-- attributes (Health, MaxHealth, Shield, Mana, MaxMana).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local CombatDefinitions = require(Shared:WaitForChild("CombatDefinitions"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local find = require(script.Parent:WaitForChild("Bind")).find

local C = Theme.Colors
local player = Players.LocalPlayer

local PlayerInfo = {}
PlayerInfo.__index = PlayerInfo

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

function PlayerInfo.new(group)
	local self = setmetatable({}, PlayerInfo)
	self.Group = group
	self.Portrait = find(group, "Portrait", "Frame")
	self.Avatar = find(group, "Portrait.Avatar", "ImageLabel")
	self.Emblem = find(group, "Portrait.Emblem", "ImageLabel")
	self.Level = find(group, "LevelBadge.Level", "TextLabel")
	self.ClassName = find(group, "ClassName", "TextLabel")
	self.Role = find(group, "Role", "TextLabel")
	self.Gold = find(group, "Gold.Value", "TextLabel")
	self.HealthFill = find(group, "HealthBar.Fill", "Frame")
	self.HealthText = find(group, "HealthBar.Value", "TextLabel")
	self.Shield = find(group, "HealthBar.Shield", "Frame")
	self.ManaFill = find(group, "ManaBar.Fill", "Frame")
	self.ManaText = find(group, "ManaBar.Value", "TextLabel")
	local function chipParts(name)
		local path = "Chips." .. name
		return {
			Frame = find(group, path, "Frame"), Label = find(group, path .. ".Label", "TextLabel"), Value = find(group, path .. ".Value", "TextLabel"),
			Stroke = find(group, path .. ".Stroke", "UIStroke"), Icon = find(group, path .. ".Icon", "Frame"),
		}
	end
	self.Buff = chipParts("Buff")
	self.Fragment = chipParts("Fragment")
	self.Status = chipParts("Status")
	if player.UserId > 0 then
		self.Avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId)
	end
	self.Avatar.Visible = player.UserId > 0
	self.Connections = {}
	return self
end

-- health/shield react instantly to the (server-authoritative) character attributes
function PlayerInfo:SetCharacter(character)
	if character == self.Character and self.Bound then
		return
	end
	self.Bound = true
	for _, c in ipairs(self.Connections) do
		c:Disconnect()
	end
	table.clear(self.Connections)
	self.Character = character
	if character then
		for _, attr in ipairs({ "Health", "MaxHealth", "Shield" }) do
			table.insert(self.Connections, character:GetAttributeChangedSignal(attr):Connect(function()
				self:RefreshHealth()
			end))
		end
		for _, attr in ipairs({ "Mana", "MaxMana" }) do
			table.insert(self.Connections, character:GetAttributeChangedSignal(attr):Connect(function()
				self:RefreshMana()
			end))
		end
	end
	self:RefreshHealth()
	self:RefreshMana()
end

function PlayerInfo:RefreshMana()
	local character = self.Character
	local maxMana = character and character:GetAttribute("MaxMana")
	if not maxMana or maxMana <= 0 then
		self.ManaFill.Visible = false
		setText(self.ManaText, "")
		return
	end
	local mana = character:GetAttribute("Mana") or 0
	local fraction = math.clamp(mana / maxMana, 0, 1)
	self.ManaFill.Size = UDim2.fromScale(fraction, 1)
	self.ManaFill.Visible = fraction > 0.001
	setText(self.ManaText, string.format("%d / %d", mana, maxMana))
end

function PlayerInfo:RefreshHealth()
	local character = self.Character
	if not character then
		self.HealthFill.Size = UDim2.fromScale(0, 1)
		self.HealthFill.Visible = false
		self.Shield.Visible = false
		setText(self.HealthText, "DOWN")
		return
	end
	local health = character:GetAttribute("Health") or 0
	local maxHealth = math.max(1, character:GetAttribute("MaxHealth") or 1)
	local shield = character:GetAttribute("Shield") or 0
	local fraction = math.clamp(health / maxHealth, 0, 1)
	self.HealthFill.Size = UDim2.fromScale(fraction, 1)
	self.HealthFill.Visible = fraction > 0.001
	-- health follows the team colour (red team red, blue team blue...); darker when low
	local teamColor = self.TeamColor
	if teamColor then
		self.HealthFill.BackgroundColor3 = fraction > 0.25 and teamColor or teamColor:Lerp(Color3.new(0, 0, 0), 0.35)
	else
		self.HealthFill.BackgroundColor3 = fraction > 0.25 and C.Red or C.Crimson
	end
	self.Shield.Visible = shield > 0
	self.Shield.Size = UDim2.fromScale(math.clamp(shield / maxHealth, 0, 1), 0.3)
	setText(self.HealthText, shield > 0 and string.format("%d / %d  (+%d)", health, maxHealth, shield) or string.format("%d / %d", health, maxHealth))
end

-- on replicated match-state change. teamColor (optional) tints the portrait backdrop so the
-- whole bottom panel follows the team; without it the class colour is used.
function PlayerInfo:Update(me, teamColor)
	if not me then
		return
	end
	if self.TeamColor ~= teamColor then
		self.TeamColor = teamColor
		self:RefreshHealth()
	end
	local classDef = ClassDefinitions.Get(me.ClassKey)
	if classDef then
		setText(self.ClassName, string.upper(classDef.DisplayName))
		setText(self.Role, classDef.Role or "")
		self.Portrait.BackgroundColor3 = teamColor and teamColor:Lerp(Color3.new(0, 0, 0), 0.2) or classDef.Color
		self.Emblem.Image = classDef.IconImage or ""
	end
	setText(self.Level, tostring(me.Stats and me.Stats.Kills or 0))
end

local function setChip(chip, visible, label, value, color)
	chip.Frame.Visible = visible
	if visible then
		setText(chip.Label, label)
		setText(chip.Value, value or "")
		chip.Label.TextColor3 = color
		chip.Stroke.Color = color
		chip.Icon.BackgroundColor3 = color
	end
end

-- throttled per-frame: gold, chips
function PlayerInfo:Tick(character, now, me, state, startingState)
	self:SetCharacter(character)
	if me and me.Stats then
		setText(self.Gold, tostring(math.floor(me.Stats.Gold or 0)))
	end
	-- Shattered Expanse has no gold economy: hide the counter there
	local goldFrame = self.Gold and self.Gold.Parent
	if goldFrame and goldFrame:IsA("GuiObject") then
		goldFrame.Visible = not (state and state.Royale)
	end
	if not character then
		self.Buff.Frame.Visible, self.Fragment.Frame.Visible, self.Status.Frame.Visible = false, false, false
		return
	end
	local buffKey = character:GetAttribute("BuffKey")
	local buff = buffKey and CombatDefinitions.Buffs[buffKey]
	local remaining = (character:GetAttribute("BuffEndsAt") or 0) - now
	setChip(self.Buff, buff ~= nil and remaining > 0, buff and string.upper(buff.Name) or "", string.format("%ds", math.ceil(math.max(0, remaining))), C.Cyan)
	setChip(self.Fragment, character:GetAttribute("HasFragment") == true, "CORE FRAGMENT", "", C.Cyan)
	local status, color = nil, C.Cyan
	if (character:GetAttribute("StunnedUntil") or 0) > now then
		status, color = startingState and "GET READY" or "STUNNED", Color3.fromRGB(255, 190, 80)
	elseif (character:GetAttribute("SlowedUntil") or 0) > now then
		status, color = "SLOWED", Color3.fromRGB(150, 170, 255)
	elseif (character:GetAttribute("UnstoppableUntil") or 0) > now then
		status, color = "UNSTOPPABLE", Color3.fromRGB(240, 200, 100)
	elseif (character:GetAttribute("SpikedScaleUntil") or 0) > now then
		status, color = "SPIKED SCALE", Color3.fromRGB(230, 90, 60)
	elseif (character:GetAttribute("ThornsUntil") or 0) > now then
		status, color = "THORNS", Color3.fromRGB(220, 120, 70)
	elseif character:GetAttribute("Stealthed") then
		status, color = "STEALTHED", Color3.fromRGB(190, 170, 255)
	elseif character:GetAttribute("BloodRush") then
		status, color = "BLOOD RUSH", C.Red
	elseif (character:GetAttribute("HasteUntil") or 0) > now then
		status, color = "HASTE", Color3.fromRGB(120, 230, 200)
	elseif character:GetAttribute("EmpoweredAttack") then
		status, color = "EMPOWERED", C.GoldBright
	elseif character:GetAttribute("InBrush") then
		status, color = "IN BRUSH", Color3.fromRGB(110, 220, 120)
	end
	setChip(self.Status, status ~= nil, status or "", "", color)
end

return PlayerInfo
