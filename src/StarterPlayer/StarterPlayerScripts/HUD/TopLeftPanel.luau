-- HUD.TopLeftPanel: team plaque (banner, team name, next ruin) + own flag health + minion wave.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Bind = require(script.Parent:WaitForChild("Bind"))
local find, optional = Bind.find, Bind.optional

local TopLeftPanel = {}
TopLeftPanel.__index = TopLeftPanel

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

function TopLeftPanel.new(group)
	local self = setmetatable({}, TopLeftPanel)
	self.Group = group
	-- Banner / FlagIcon are optional: with the painted plaques the banner and the flag icon are
	-- part of the art and follow the team colour through their TeamTint layer instead
	self.Banner = optional(group, "TeamPanel.Banner")
	self.TeamName = find(group, "TeamPanel.TeamName", "TextLabel")
	self.RuinLabel = find(group, "TeamPanel.RuinLabel", "TextLabel")
	self.RuinTime = find(group, "TeamPanel.RuinTime", "TextLabel")
	self.Hourglass = find(group, "TeamPanel.Hourglass", "ImageLabel")
	self.FlagIcon = optional(group, "FlagPanel.FlagIcon")
	self.FlagValue = find(group, "FlagPanel.Value", "TextLabel")
	self.FlagFill = find(group, "FlagPanel.Bar.Fill", "Frame")
	self.MinionWave = find(group, "MinionWave", "TextLabel")
	return self
end

-- on replicated match-state change
function TopLeftPanel:Update(state, myTeam, myTeamState)
	if myTeam then
		local color = Constants.GetTeamColor(myTeam)
		setText(self.TeamName, string.upper(Constants.GetTeamName(myTeam)))
		local deep = Theme.TintColor(color)
		self.TeamName.TextColor3 = deep:Lerp(Color3.new(1, 1, 1), 0.08)
		if self.Banner then
			self.Banner.ImageColor3 = color:Lerp(Color3.new(0, 0, 0), 0.1)
		end
		if self.FlagIcon then
			self.FlagIcon.ImageColor3 = color
		end
		self.FlagFill.BackgroundColor3 = deep
	end
	if not myTeamState then
		return
	end
	local fraction = myTeamState.FlagHealth / math.max(1, myTeamState.FlagMaxHealth)
	if myTeamState.FlagState == "Intact" then
		setText(self.FlagValue, string.format("%d / %d", myTeamState.FlagHealth, myTeamState.FlagMaxHealth))
		self.FlagValue.TextColor3 = Theme.Colors.Text
	elseif myTeamState.FlagState == "LastStand" then
		setText(self.FlagValue, myTeamState.CarrierName and (myTeamState.CarrierTeam == myTeamState.Team and "RETURNING" or "TAKEN!") or "DOWN")
		self.FlagValue.TextColor3 = Theme.Colors.Red
		fraction = 0
	else
		setText(self.FlagValue, myTeamState.Eliminated and "ELIMINATED" or "DESTROYED")
		self.FlagValue.TextColor3 = Theme.Colors.Muted
		fraction = 0
	end
	self.FlagFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	self.FlagFill.Visible = fraction > 0.001
end

-- throttled per-frame: timers
function TopLeftPanel:Tick(state, now, me, active)
	local untilRuin = active and (state.NextRuinAt or 0) - now or 0
	local hasRuin = untilRuin > 0
	self.Hourglass.Visible = hasRuin
	self.RuinLabel.Visible = hasRuin
	setText(self.RuinTime, hasRuin and Util.FormatTime(untilRuin) or "")
	local text = ""
	if active and not state.Debug then
		local untilWave = (workspace:GetAttribute("MinionNextWaveAt") or 0) - now
		local level = me and me.Team and workspace:GetAttribute("MinionLevel_" .. me.Team) or 0
		if untilWave > 0 then
			text = string.format("Minion wave  %s   |   Lv %d", Util.FormatTime(untilWave), level)
		end
	elseif state.Debug and state.Seed then
		text = "seed " .. tostring(state.Seed)
	end
	setText(self.MinionWave, text)
end

return TopLeftPanel
