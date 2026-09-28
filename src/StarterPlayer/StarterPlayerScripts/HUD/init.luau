--[[
	HUD - controller for the in-match HUD (StarterGui.MainHUD).

	The layout lives in the folder ReplicatedStorage.HUD (MainHUD ScreenGui) as real GUI objects -
	edit or replace it by hand (see ReplicatedStorage.HUD.README), or regenerate it with
	ServerStorage.HUDTools.MainHUDBuilder. It is NOT in StarterGui, so it never appears in the hub:
	this controller clones it into PlayerGui only on match servers and shows it only during a match.
	Missing / renamed elements are skipped with one warning (HUD.Bind). Components:
		HUD.Theme         colours, fonts, art, key mapping
		HUD.TopLeftPanel  team plaque, next ruin, own flag, minion wave
		HUD.Scoreboard    team scoreboard (top centre)
		HUD.PlayerInfo    portrait, class, health, gold, status chips (bottom left)
		HUD.AbilityBar    LM / Q / E / R / MR controls with cooldowns (bottom right)
	The minimap draws into Root.Minimap.MapHolder (MinimapController).

	Public API (used by UIController / MobileController / ClientController):
		HUD.new(screen, clientState, combatController), :SetVisible(bool), :Update(state),
		:Tick(), :SetMobileLayout(bool), .Root
	Data flow: Update() runs on replicated match-state changes; Tick() is called every frame but
	only animates cooldown overlays each frame - text and chips refresh at 10 Hz, health reacts
	to the character's attribute signals.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Theme = require(script:WaitForChild("Theme"))
local TopLeftPanel = require(script:WaitForChild("TopLeftPanel"))
local Scoreboard = require(script:WaitForChild("Scoreboard"))
local PlayerInfo = require(script:WaitForChild("PlayerInfo"))
local AbilityBar = require(script:WaitForChild("AbilityBar"))
local Bind = require(script:WaitForChild("Bind"))
local find, deep = Bind.find, Bind.deep

-- Constants
local STATE = Constants.MatchState
local SLOW_INTERVAL = 0.1
-- The character panel (portrait, class, level, health, mana, status chips) blocked the view, so it
-- is hidden: health + mana show on the hero's overhead bar (UnitDisplayController) and gold sits
-- next to the ability bar (on touch devices: on the SHOP button). Set true to bring it back.
local SHOW_CHARACTER_PANEL = true
local CHARACTER_PANEL_PARTS = { "Portrait", "LevelBadge", "ClassName", "Role", "HealthBar", "ManaBar", "Chips" }
local player = Players.LocalPlayer

-- State
local HUD = {}
HUD.__index = HUD
HUD.Theme = Theme

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Clone the layout from ReplicatedStorage.HUD into PlayerGui (match servers only)
local function findGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local folder = ReplicatedStorage:WaitForChild("HUD", 10)
	local template = folder and (folder:FindFirstChild("MainHUD") or folder:FindFirstChildWhichIsA("ScreenGui"))
	-- a copy left in StarterGui (e.g. while editing) is replaced by the folder version
	local stray = playerGui:FindFirstChild("MainHUD")
	if stray and template and not stray:GetAttribute("FromHUDFolder") then
		warn("[HUD] a MainHUD was found in StarterGui - move it back into ReplicatedStorage.HUD so it does not show in the hub")
		stray:Destroy()
	end
	local gui
	if template then
		gui = template:Clone()
		gui.Name = "MainHUD"
		gui:SetAttribute("FromHUDFolder", true)
	else
		warn("[HUD] ReplicatedStorage.HUD.MainHUD is missing - using an empty HUD")
		gui = Instance.new("ScreenGui")
		gui.Name = "MainHUD"
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)
		root.Parent = gui
	end
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = true
	gui.Parent = playerGui
	return gui
end

function HUD.new(_screen, clientState, combatController)
	local self = setmetatable({}, HUD)
	self.ClientState = clientState
	self.CombatController = combatController
	local gui = findGui()
	local root = gui:FindFirstChild("Root") or gui
	if root:IsA("GuiObject") then
		root.Visible = false
	end
	gui.Enabled = false
	self.Gui = gui
	self.Root = root
	self.TopLeft = TopLeftPanel.new(deep(root, "TopLeft", "Frame"))
	self.Scoreboard = Scoreboard.new(deep(root, "Scoreboard", "Frame"))
	self.PlayerInfo = PlayerInfo.new(deep(root, "PlayerInfo", "Frame"))
	self.AbilityBar = AbilityBar.new(deep(root, "AbilityBar", "Frame"), clientState, combatController)
	-- bottom strip (portrait + panel + ability bar art) if the layout has one
	self.Bottom = root:FindFirstChild("BottomHUD", true)
	self:ApplyCharacterPanel()
	-- every image / frame marked with the attribute TeamTint = true follows the team colour
	self.TeamTints = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("TeamTint") then
			table.insert(self.TeamTints, d)
		end
	end
	-- overlays
	self.LastStand = find(root, "LastStand", "Frame")
	self.LastStandHint = find(root, "LastStand.Hint", "TextLabel")
	self.LastStandTimer = find(root, "LastStand.Timer", "TextLabel")
	self.Channel = find(root, "Channel", "Frame")
	self.ChannelFill = find(root, "Channel.Bar.Fill", "Frame")
	self.CenterTitle = find(root, "CenterTitle", "TextLabel")
	self.CenterSub = find(root, "CenterSub", "TextLabel")
	-- compatibility with older callers
	self.BottomPanel = self.PlayerInfo.Group
	self.SkillBar = self.AbilityBar.Group
	self.ItemSlots = self.AbilityBar.ItemSlots
	self.NextSlow = 0
	return self
end

-- hides the character panel + its background art, keeping gold as a small pill left of the skills
function HUD:ApplyCharacterPanel()
	if SHOW_CHARACTER_PANEL then
		return
	end
	local group = self.PlayerInfo.Group
	for _, name in ipairs(CHARACTER_PANEL_PARTS) do
		local part = group:FindFirstChild(name)
		if part and part:IsA("GuiObject") then
			part.Visible = false
		end
	end
	if self.Bottom then
		for _, name in ipairs({ "ArtLeft", "TintLeft" }) do
			local art = self.Bottom:FindFirstChild(name)
			if art and art:IsA("GuiObject") then
				art.Visible = false
			end
		end
	end
	local gold = group:FindFirstChild("Gold")
	if gold and gold:IsA("GuiObject") then
		gold.AnchorPoint = Vector2.new(1, 0.5)
		gold.Position = UDim2.fromScale(0.535, 0.58)
		if gold.BackgroundTransparency > 0.9 then
			gold.BackgroundColor3 = Color3.fromRGB(14, 12, 10)
			gold.BackgroundTransparency = 0.3
			if not gold:FindFirstChildOfClass("UICorner") then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = gold
			end
		end
	end
end

function HUD:GetSlotItem(key)
	return self.AbilityBar:GetSlotItem(key)
end

function HUD:RequestSwap()
	self.AbilityBar:RequestSwap()
end

function HUD:SetVisible(visible)
	self.Shown = visible
	if self.Root:IsA("GuiObject") then
		self.Root.Visible = visible
	end
	self.Gui.Enabled = visible
end

-- Touch devices: the mobile action buttons replace the ability bar; the player panel moves to
-- the top centre under the scoreboard so both bottom corners stay free for thumbs.
function HUD:SetMobileLayout(enabled)
	if self.MobileLayout == enabled then
		return
	end
	self.MobileLayout = enabled
	local bottom = self.Bottom
	if bottom then
		-- combined bottom strip: keep the portrait + panel half, centred under the scoreboard
		for _, d in ipairs(bottom:GetDescendants()) do
			if d:GetAttribute("DesktopOnly") and d:IsA("GuiObject") then
				d.Visible = not enabled
			end
		end
		if not SHOW_CHARACTER_PANEL then
			-- touch: the mobile buttons replace the ability bar and the character panel is hidden,
			-- so the whole strip goes away (gold shows on the mobile SHOP button)
			bottom.Visible = not enabled
			return
		end
		if enabled then
			self.DesktopBottom = self.DesktopBottom or { AnchorPoint = bottom.AnchorPoint, Position = bottom.Position }
			bottom.AnchorPoint = Vector2.new(0.25, 0)
			bottom.Position = UDim2.fromScale(0.5, 0.12)
		elseif self.DesktopBottom then
			bottom.AnchorPoint = self.DesktopBottom.AnchorPoint
			bottom.Position = self.DesktopBottom.Position
		end
		return
	end
	local info = self.PlayerInfo.Group
	self.AbilityBar.Group.Visible = not enabled
	if enabled then
		self.DesktopInfo = self.DesktopInfo or { AnchorPoint = info.AnchorPoint, Position = info.Position }
		info.AnchorPoint = Vector2.new(0.5, 0)
		info.Position = UDim2.fromScale(0.5, 0.13)
	elseif self.DesktopInfo then
		info.AnchorPoint = self.DesktopInfo.AnchorPoint
		info.Position = self.DesktopInfo.Position
	end
end

-- replicated match state changed
function HUD:Update(state)
	if not self.Shown then
		return
	end
	local clientState = self.ClientState
	local myTeam = clientState.GetMyTeam()
	local myTeamState = clientState.GetTeamState(myTeam)
	local me = clientState.GetMe()
	if myTeam and myTeam ~= self.TintTeam then
		self.TintTeam = myTeam
		local tint = Theme.TintColor(Constants.GetTeamColor(myTeam))
		for _, d in ipairs(self.TeamTints) do
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				d.ImageColor3 = tint
			elseif d:IsA("GuiObject") then
				d.BackgroundColor3 = tint
			end
		end
	end
	self.Scoreboard:Update(state)
	self.TopLeft:Update(state, myTeam, myTeamState)
	self.PlayerInfo:Update(me, myTeam and Constants.GetTeamColor(myTeam))
	self.AbilityBar:Update(me)
	-- Last Stand overlay
	local inLastStand = myTeamState ~= nil and myTeamState.FlagState == "LastStand" and state.State == STATE.ACTIVE
	self.LastStand.Visible = inLastStand
	if inLastStand then
		if myTeamState.Secured then
			setText(self.LastStandHint, "FRAGMENT SECURED - timer frozen! Bring it to your flag.")
			setText(self.LastStandTimer, "TIME REMAINING: " .. math.ceil(myTeamState.LastStandRemaining) .. "  (FROZEN)")
		else
			setText(self.LastStandHint, "Find a Core Fragment and restore your anchor.")
			setText(self.LastStandTimer, "TIME REMAINING: " .. math.max(0, math.ceil(myTeamState.LastStandRemaining)))
		end
	end
end

function HUD:UpdateCenter(state, me, now)
	local title, sub, color, size = nil, nil, Theme.Colors.Text, 0.07
	if state.State == STATE.STARTING then
		title = tostring(math.max(1, math.ceil((state.StateEndsAt or now) - now)))
		sub = "Destroy enemy flags. Protect your own."
		size = 0.11
	elseif state.State == STATE.ENDING then
		local myTeam = self.ClientState.GetMyTeam()
		if state.Winner == nil then
			title, color = "DRAW", Theme.Colors.Muted
		elseif state.Winner == myTeam then
			title, color = "VICTORY", Theme.Colors.GoldBright
		else
			title, color = "DEFEAT", Theme.Colors.Red
		end
		sub = state.Winner and (string.upper(Constants.GetTeamName(state.Winner)) .. " WINS") or ""
		size = 0.11
	elseif me and me.State == "Dead" then
		if me.RespawnAt and me.RespawnAt > 0 then
			title = "RESPAWNING IN " .. math.max(0, math.ceil(me.RespawnAt - now))
			sub = "You will respawn at your flag"
		else
			title, color = "AWAITING RESTORATION", Color3.fromRGB(255, 190, 80)
			sub = "Your flag is down - a teammate must re-anchor it with a Core Fragment"
		end
	elseif me and me.State == "Eliminated" and state.Royale then
		title, sub = nil, nil -- RoyaleUI shows placement + spectate panel
	elseif me and me.State == "Eliminated" then
		title, color, sub = "ELIMINATED", Theme.Colors.Red, "Spectating - the match continues"
	elseif me and me.Spectator then
		title, color, sub = "SPECTATING", Theme.Colors.Muted, "A match is in progress - you will join the next one"
	end
	self.CenterTitle.Visible = title ~= nil
	self.CenterSub.Visible = sub ~= nil
	if title then
		setText(self.CenterTitle, title)
		self.CenterTitle.TextColor3 = color
		self.CenterTitle.Size = UDim2.fromScale(0.6, size)
	end
	if sub then
		setText(self.CenterSub, sub)
	end
end

-- every frame from UIController
function HUD:Tick()
	if not self.Shown then
		return
	end
	local clientState = self.ClientState
	local state = clientState.Game
	if not state then
		return
	end
	local now = workspace:GetServerTimeNow()
	local me = clientState.GetMe()
	local character = clientState.GetLocalCharacter()
	self.AbilityBar:Tick(character, now, me)
	local channel = character and character:GetAttribute("ChannelProgress") or 0
	self.Channel.Visible = channel > 0
	if channel > 0 then
		self.ChannelFill.Size = UDim2.fromScale(math.clamp(channel, 0, 1), 1)
	end
	local clock = os.clock()
	if clock < self.NextSlow then
		return
	end
	self.NextSlow = clock + SLOW_INTERVAL
	local active = state.State == STATE.ACTIVE or state.State == STATE.ENDING
	self.TopLeft:Tick(state, now, me, active)
	self.PlayerInfo:Tick(character, now, me, state, state.State == STATE.STARTING)
	self:UpdateCenter(state, me, now)
end

return HUD
