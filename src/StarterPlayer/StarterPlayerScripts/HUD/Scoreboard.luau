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
		if teamState.CarrierName and teamState.CarrierTeam == teamState.Team then
			return "Flag Returning", Theme.Colors.GoldBright
		end
		return teamState.CarrierName and "Flag Taken!" or "Flag Down", Theme.Colors.Red
	end
	return "Flag Destroyed", Theme.Colors.Muted
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

-- 4 / 6 teams: every plaque sits in ONE horizontal row across the top (the extra plaques
-- used to stack under the main one): [teams 3-4] [teams 1-2] [teams 5-6]. 2 teams: the main
-- plaque alone, as designed.
local PLAQUE_ASPECT = 3.78
local ROW_GAP = 0.012
function Scoreboard:ArrangeRow(count)
	if self.RowCount == count then
		return
	end
	self.RowCount = count
	local main = self.Group
	local row = self.Plaques[2] and self.Plaques[2].Frame.Parent
	if not row or row == main.Parent then
		return
	end
	self.Home = self.Home or { Parent = main.Parent, Position = main.Position, Size = main.Size, AnchorPoint = main.AnchorPoint, LayoutOrder = main.LayoutOrder }
	self.RowHome = self.RowHome or { Position = row.Position, Size = row.Size, AnchorPoint = row.AnchorPoint }
	local layout = row:FindFirstChildOfClass("UIListLayout")
	local aspect = row:FindFirstChildOfClass("UIAspectRatioConstraint")
	if count <= 1 then
		main.Parent = self.Home.Parent
		main.Position, main.Size, main.AnchorPoint, main.LayoutOrder = self.Home.Position, self.Home.Size, self.Home.AnchorPoint, self.Home.LayoutOrder
		if self.MainScale then
			self.MainScale.Parent = main
		end
		row.Position, row.Size, row.AnchorPoint = self.RowHome.Position, self.RowHome.Size, self.RowHome.AnchorPoint
		return
	end
	-- the row carries the HUD-size scale for all plaques; the main plaque's own one would double it
	self.MainScale = self.MainScale or main:FindFirstChild("UserHudScale")
	if self.MainScale then
		self.MainScale.Parent = nil
	end
	local width = math.min(0.56, count * 0.25)
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, 0.0022)
	row.Size = UDim2.fromScale(width, 0.2)
	if aspect then
		aspect.AspectRatio = PLAQUE_ASPECT * count / (1 - ROW_GAP * (count - 1))
	end
	if layout then
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.Padding = UDim.new(ROW_GAP, 0)
	end
	local plaqueWidth = (1 - ROW_GAP * (count - 1)) / count
	main.Parent = row
	main.AnchorPoint = Vector2.zero
	main.Position = UDim2.new()
	main.Size = UDim2.fromScale(plaqueWidth, 1)
	main.LayoutOrder = 2
	for index = 2, #self.Plaques do
		local frame = self.Plaques[index].Frame
		frame.Size = UDim2.fromScale(plaqueWidth, 1)
		frame.LayoutOrder = index == 2 and 1 or index + 1
	end
end

function Scoreboard:Update(state)
	local teams = state.Teams or {}
	local shown = math.clamp(math.ceil(#teams / 2), 1, #self.Plaques)
	self:ArrangeRow(shown)
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
