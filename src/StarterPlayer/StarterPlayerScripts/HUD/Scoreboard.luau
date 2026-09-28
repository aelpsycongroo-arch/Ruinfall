-- HUD.Scoreboard: top-centre team scoreboard. Each plaque shows two teams (Left / Right):
-- Scoreboard = teams 1-2, and 4- / 6-team modes use copies of it - Scoreboard2 = teams 3-4,
-- Scoreboard3 = teams 5-6 (anywhere under Root) - each side recoloured with its team colour.
-- Teams beyond the available plaques are listed as compact entries (ExtraTeams).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Bind = require(script.Parent:WaitForChild("Bind"))
local find, optional = Bind.find, Bind.optional

local Scoreboard = {}
Scoreboard.__index = Scoreboard

local function setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

local function flagText(teamState)
	if teamState.Eliminated then
		return "Eliminated", Theme.Colors.Muted
	elseif teamState.FlagState == "Intact" then
		return "Flag " .. teamState.FlagHealth, Theme.Colors.Text
	elseif teamState.FlagState == "LastStand" then
		return teamState.Secured and "Last Stand: Secured" or string.format("Last Stand %d", math.ceil(teamState.LastStandRemaining or 0)), Theme.Colors.Red
	end
	return "Flagless", Theme.Colors.Muted
end

local function bindSides(plaque)
	local sides = {}
	for _, name in ipairs({ "Left", "Right" }) do
		-- Banner / Tint / Line / Bar are optional (depends on the art): Tint = the side's colour
		-- layer of the painted plaque, Bar.Fill = the flag-health bar inside the painted rim
		sides[#sides + 1] = {
			Frame = find(plaque, name, "Frame"), Name = find(plaque, name .. ".TeamName", "TextLabel"),
			Alive = find(plaque, name .. ".Alive", "TextLabel"), Flag = find(plaque, name .. ".Flag", "TextLabel"),
			Banner = optional(plaque, name .. ".Banner"), Tint = optional(plaque, name .. ".Tint"),
			Line = optional(plaque, name .. ".Line"), Fill = optional(plaque, name .. ".Bar.Fill"),
		}
	end
	return sides
end

function Scoreboard.new(group)
	local self = setmetatable({}, Scoreboard)
	self.Group = group
	self.Plaques = { { Frame = group, Sides = bindSides(group) } }
	-- copies of the plaque for the next team pairs: Scoreboard2, Scoreboard3, ...
	local root = group.Parent
	while root do
		local copy = root:FindFirstChild("Scoreboard" .. (#self.Plaques + 1), true)
		if not copy then
			break
		end
		copy.Visible = false
		table.insert(self.Plaques, { Frame = copy, Sides = bindSides(copy) })
	end
	self.Sides = self.Plaques[1].Sides
	self.Extra = find(group, "ExtraTeams", "Frame")
	self.ExtraLabels = {}
	return self
end

local function counts(state, team)
	local alive, total = 0, 0
	for _, participant in ipairs(state.Participants or {}) do
		if participant.Team == team and not participant.Spectator then
			total += 1
			if participant.State == "Alive" then
				alive += 1
			end
		end
	end
	return alive, total
end

local function updateSide(side, teamState, state)
	side.Frame.Visible = teamState ~= nil
	if teamState then
		do
			local color = Constants.GetTeamColor(teamState.Team)
			local alive, total = counts(state, teamState.Team)
			setText(side.Name, string.upper(Constants.GetTeamName(teamState.Team)))
			side.Name.TextColor3 = Theme.TeamNameColor(color)
			side.Name.TextTransparency = teamState.Eliminated and 0.5 or 0
			setText(side.Alive, alive .. "/" .. total)
			local text, textColor = flagText(teamState)
			setText(side.Flag, text)
			side.Flag.TextColor3 = textColor
			if side.Banner then
				side.Banner.ImageColor3 = color:Lerp(Color3.new(0, 0, 0), 0.1)
			end
			if side.Tint then
				side.Tint.ImageColor3 = Theme.TintColor(color)
			end
			if side.Line then
				side.Line.BackgroundColor3 = color
			end
			if side.Fill then
				local intact = teamState.FlagState == "Intact" and not teamState.Eliminated
				local fraction = intact and math.clamp((teamState.FlagHealth or 0) / math.max(1, teamState.FlagMaxHealth or 1), 0, 1) or 0
				side.Fill.Size = UDim2.fromScale(fraction, 1)
				side.Fill.Visible = fraction > 0.001
				side.Fill.BackgroundColor3 = Theme.TintColor(color)
			end
		end
	end
end

function Scoreboard:Update(state)
	local teams = state.Teams or {}
	for p, plaque in ipairs(self.Plaques) do
		local first = 2 * p - 1
		if p > 1 then
			plaque.Frame.Visible = teams[first] ~= nil
		end
		for s, side in ipairs(plaque.Sides) do
			updateSide(side, teams[first + s - 1], state)
		end
	end
	-- teams beyond the plaques: compact entries
	local covered = 2 * #self.Plaques
	self.Extra.Visible = #teams > covered
	for index = covered + 1, math.max(#teams, covered + #self.ExtraLabels) do
		local teamState = teams[index]
		local lbl = self.ExtraLabels[index - covered]
		if teamState and not lbl then
			lbl = Instance.new("TextLabel")
			lbl.BackgroundColor3 = Theme.Colors.Black
			lbl.BackgroundTransparency = 0.2
			lbl.FontFace = Theme.Fonts.Title
			lbl.TextScaled = true
			lbl.Size = UDim2.fromScale(0.22, 1)
			lbl.LayoutOrder = index
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Colors.Gold
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = lbl
			lbl.Parent = self.Extra
			self.ExtraLabels[index - covered] = lbl
		end
		if lbl then
			lbl.Visible = teamState ~= nil
			if teamState then
				local alive, total = counts(state, teamState.Team)
				lbl.TextColor3 = Constants.GetTeamColor(teamState.Team):Lerp(Color3.new(1, 1, 1), 0.2)
				setText(lbl, string.format("%s %d/%d  %s", string.upper(Constants.GetTeamName(teamState.Team)), alive, total, (flagText(teamState))))
			end
		end
	end
end

return Scoreboard
