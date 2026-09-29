-- ScoreboardUI: the in-match scoreboard, toggled with the Scoreboard key (Tab by default,
-- rebindable in SETTINGS; touch devices get a small SCORE button). Every player grouped by
-- team: class, name, K / D / A and the gear they have built (SPACE / E / R active items,
-- boots, 3 passives). Free for all: one list, living players first, most kills on top.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local GameSettings = require(script.Parent:WaitForChild("GameSettings"))

-- Constants
local STATE = Constants.MatchState
local COLORS, FONTS, MEDIEVAL = UITheme.Colors, UITheme.Fonts, UITheme.Medieval
local New, Label = UITheme.New, UITheme.Label
local PANEL_W = 900
local ROW_H = 40
local HEADER_H = 26
local MAX_ROWS = Constants.MAX_PARTICIPANTS or 18
local ICON = 30
-- gear columns: mythic slot order on the HUD (SPACE, E, R), then boots and passives
local GEAR = {
	{ Kind = "Mythic", Index = 3, Tag = "SPC" }, { Kind = "Mythic", Index = 1, Tag = "E" }, { Kind = "Mythic", Index = 2, Tag = "R" },
	{ Kind = "Boots", Tag = "RMB" },
	{ Kind = "Passive", Index = 1, Tag = "P1" }, { Kind = "Passive", Index = 2, Tag = "P2" }, { Kind = "Passive", Index = 3, Tag = "P3" },
}
local player = Players.LocalPlayer

-- State
local ScoreboardUI = {}
ScoreboardUI.__index = ScoreboardUI

local function gearItem(participant, gear)
	local id
	if gear.Kind == "Mythic" then
		id = participant.Mythics and participant.Mythics[gear.Index]
	elseif gear.Kind == "Boots" then
		id = participant.Boots
	else
		id = participant.Passives and participant.Passives[gear.Index]
	end
	return (id and id ~= "") and ItemDefinitions.GetItem(id) or nil
end

function ScoreboardUI.new(screen, clientState)
	local self = setmetatable({}, ScoreboardUI)
	self.ClientState = clientState
	self.Open = false

	local root = New("Frame", { Name = "Scoreboard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, 120), BackgroundColor3 = MEDIEVAL.Wood, BackgroundTransparency = 0.08, Visible = false, ZIndex = 40, Parent = screen })
	UITheme.MedievalPanel(root, true)
	local fit = New("UIScale", { Parent = root })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		fit.Scale = math.clamp(math.min((viewport.X - 30) / PANEL_W, (viewport.Y - 30) / math.max(200, root.Size.Y.Offset)), 0.45, 1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	self.Rescale = rescale
	self.Root = root
	self.Title = Label({ Text = "SCOREBOARD", Font = FONTS.Title, TextSize = 22, TextColor3 = COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 26), ZIndex = 41, Parent = root })
	self.Hint = Label({ Text = "", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(240, 16), ZIndex = 41, Parent = root })
	-- column headers
	local head = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 18), ZIndex = 41, Parent = root })
	local function header(text, x, width, align)
		Label({ Text = text, Font = FONTS.Title, TextSize = 12, TextColor3 = COLORS.Subtext, TextXAlignment = align or Enum.TextXAlignment.Center, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, 18), ZIndex = 41, Parent = head })
	end
	header("PLAYER", 44, 230, Enum.TextXAlignment.Left)
	header("K", 282, 40)
	header("D", 322, 40)
	header("A", 362, 40)
	header("DAMAGE", 404, 72)
	for index, gear in ipairs(GEAR) do
		header(gear.Tag, 490 + (index - 1) * (ICON + 18) + (index > 3 and 10 or 0) + (index > 4 and 10 or 0), ICON + 8)
	end
	self.List = New("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 62), Size = UDim2.new(1, -32, 1, -72), ZIndex = 41, Parent = root })

	-- pooled team headers and player rows
	self.Headers, self.Rows = {}, {}
	for index = 1, MAX_ROWS do
		local teamHeader = New("Frame", { Visible = false, Size = UDim2.new(1, 0, 0, HEADER_H - 4), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.2, ZIndex = 41, Parent = self.List })
		UITheme.Corner(teamHeader, 5)
		local headerText = Label({ Text = "", Font = FONTS.Title, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 42, Parent = teamHeader })
		self.Headers[index] = { Frame = teamHeader, Text = headerText }

		local row = New("Frame", { Visible = false, Size = UDim2.new(1, 0, 0, ROW_H - 4), BackgroundColor3 = MEDIEVAL.WoodLight, BackgroundTransparency = 0.35, ZIndex = 41, Parent = self.List })
		UITheme.Corner(row, 5)
		local stroke = UITheme.Stroke(row, COLORS.Gold, 1.5, 1)
		local bar = New("Frame", { Size = UDim2.new(0, 5, 1, 0), BorderSizePixel = 0, ZIndex = 42, Parent = row })
		local emblem = New("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 3), Size = UDim2.fromOffset(30, 30), ScaleType = Enum.ScaleType.Fit, ZIndex = 42, Parent = row })
		local name = Label({ Text = "", Font = FONTS.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(46, 2), Size = UDim2.fromOffset(226, 18), ZIndex = 42, Parent = row })
		local sub = Label({ Text = "", Font = FONTS.Medium, TextSize = 11, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(46, 19), Size = UDim2.fromOffset(226, 14), ZIndex = 42, Parent = row })
		local function stat(x, width)
			return Label({ Text = "0", Font = FONTS.Title, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, width, 1, 0), ZIndex = 42, Parent = row })
		end
		local kills, deaths, assists, damage = stat(282, 40), stat(322, 40), stat(362, 40), stat(404, 72)
		damage.TextSize = 13
		local icons = {}
		for gearIndex = 1, #GEAR do
			local x = 490 + (gearIndex - 1) * (ICON + 18) + (gearIndex > 3 and 10 or 0) + (gearIndex > 4 and 10 or 0)
			icons[gearIndex] = UITheme.ItemIcon({ Position = UDim2.fromOffset(x + 4, 3), Size = UDim2.fromOffset(ICON, ICON), ZIndex = 42, Parent = row })
		end
		self.Rows[index] = { Frame = row, Stroke = stroke, Bar = bar, Emblem = emblem, Name = name, Sub = sub, K = kills, D = deaths, A = assists, Damage = damage, Icons = icons, Items = {} }
	end

	-- mobile: a small SCORE button (no Tab key)
	self.TouchButton = UITheme.Button({ Name = "ScoreButton", Text = "SCORE", Font = FONTS.Title, TextSize = 12, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0.37, 0), Size = UDim2.fromOffset(70, 28), Visible = false, ZIndex = 8, Parent = screen }, function()
		self:SetOpen(not self.Open)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or GameSettings.Capturing then
			return
		end
		if GameSettings.Matches(input, "Scoreboard") then
			self:SetOpen(not self.Open)
		end
	end)
	local function hint()
		self.Hint.Text = "[" .. GameSettings.Label("Scoreboard") .. "] close"
	end
	hint()
	GameSettings.Changed.Event:Connect(hint)
	clientState.StateChanged:Connect(function(matchState)
		self:ApplyMatchState(matchState)
	end)
	self:ApplyMatchState(clientState.GetMatchState())
	return self
end

function ScoreboardUI:InMatch()
	local matchState = self.ClientState.GetMatchState()
	return matchState == STATE.STARTING or matchState == STATE.ACTIVE or matchState == STATE.ENDING
end

function ScoreboardUI:ApplyMatchState()
	local inMatch = self:InMatch()
	-- Tab opens our scoreboard in matches, so hide Roblox's own player list there
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not inMatch)
	end)
	self.TouchButton.Visible = inMatch and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if not inMatch then
		self:SetOpen(false)
	end
end

function ScoreboardUI:SetOpen(open)
	open = open and self:InMatch()
	self.Open = open
	self.Root.Visible = open
	if open then
		self:Update(self.ClientState.Game)
	end
end

-- groups of { Team, Members } in display order
local function groups(state)
	local byTeam, order = {}, {}
	for _, participant in ipairs(state.Participants or {}) do
		if not participant.Spectator and participant.Team then
			if not byTeam[participant.Team] then
				byTeam[participant.Team] = {}
				table.insert(order, participant.Team)
			end
			table.insert(byTeam[participant.Team], participant)
		end
	end
	local function score(p)
		return (p.Stats and p.Stats.Kills or 0) * 1000 + (p.Stats and p.Stats.Damage or 0) / 100
	end
	if state.Royale then
		local everyone = {}
		for _, team in ipairs(order) do
			for _, p in ipairs(byTeam[team]) do
				table.insert(everyone, p)
			end
		end
		table.sort(everyone, function(a, b)
			local aOut, bOut = a.State == "Eliminated", b.State == "Eliminated"
			if aOut ~= bOut then
				return not aOut
			end
			return score(a) > score(b)
		end)
		return { { Team = nil, Members = everyone } }
	end
	table.sort(order)
	local list = {}
	for _, team in ipairs(order) do
		table.sort(byTeam[team], function(a, b)
			return score(a) > score(b)
		end)
		table.insert(list, { Team = team, Members = byTeam[team] })
	end
	return list
end

local function flagLabel(state, team)
	for _, teamState in ipairs(state.Teams or {}) do
		if teamState.Team == team then
			if teamState.Eliminated then
				return "ELIMINATED"
			elseif teamState.FlagState == "Intact" then
				return string.format("Flag %d / %d", teamState.FlagHealth or 0, teamState.FlagMaxHealth or 0)
			elseif teamState.FlagState == "LastStand" then
				return teamState.CarrierName and "Flag taken" or "Flag down"
			end
			return "Flag destroyed"
		end
	end
	return ""
end

function ScoreboardUI:Update(state)
	if not self.Open or not state then
		return
	end
	local me = self.ClientState.GetMe()
	local y, rowIndex, headerIndex = 0, 0, 0
	self.Title.Text = state.Royale and "SCOREBOARD - FREE FOR ALL" or "SCOREBOARD"
	for _, group in ipairs(groups(state)) do
		if group.Team then
			headerIndex += 1
			local header = self.Headers[headerIndex]
			if header then
				local color = Constants.GetTeamColor(group.Team)
				header.Frame.Visible = true
				header.Frame.Position = UDim2.fromOffset(0, y)
				header.Frame.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6)
				local kills = 0
				for _, p in ipairs(group.Members) do
					kills += p.Stats and p.Stats.Kills or 0
				end
				header.Text.Text = string.format("%s   -   %d kills   -   %s", string.upper(Constants.GetTeamName(group.Team)), kills, flagLabel(state, group.Team))
				header.Text.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
				y += HEADER_H
			end
		end
		for _, participant in ipairs(group.Members) do
			rowIndex += 1
			local row = self.Rows[rowIndex]
			if not row then
				break
			end
			local stats = participant.Stats or {}
			local classDef = ClassDefinitions.Get(participant.ClassKey)
			local teamColor = participant.Team and Constants.GetTeamColor(participant.Team) or COLORS.Stroke
			local isMe = me ~= nil and participant.Id == me.Id
			row.Frame.Visible = true
			row.Frame.Position = UDim2.fromOffset(0, y)
			row.Frame.BackgroundTransparency = participant.State == "Eliminated" and 0.65 or 0.35
			row.Stroke.Transparency = isMe and 0 or 1
			row.Bar.BackgroundColor3 = teamColor
			row.Emblem.Image = classDef and classDef.IconImage or ""
			row.Name.Text = participant.Name .. (participant.IsBot and "  (bot)" or "")
			row.Name.TextColor3 = isMe and COLORS.Gold or COLORS.Text
			local status = participant.State == "Eliminated" and (participant.Placement and ("OUT  #" .. participant.Placement) or "OUT")
				or participant.State == "Dead" and "DEAD" or ""
			row.Sub.Text = (classDef and string.upper(classDef.DisplayName or participant.ClassKey) or "") .. (status ~= "" and ("   " .. status) or "")
			row.K.Text = tostring(stats.Kills or 0)
			row.D.Text = tostring(stats.Deaths or 0)
			row.A.Text = tostring(stats.Assists or 0)
			row.Damage.Text = tostring(math.floor(stats.Damage or 0))
			for gearIndex, gear in ipairs(GEAR) do
				local item = gearItem(participant, gear)
				local id = item and item.Id or false
				if row.Items[gearIndex] ~= id then
					row.Items[gearIndex] = id
					row.Icons[gearIndex].Set(item)
				end
			end
			y += ROW_H
		end
	end
	for index = headerIndex + 1, #self.Headers do
		self.Headers[index].Frame.Visible = false
	end
	for index = rowIndex + 1, #self.Rows do
		self.Rows[index].Frame.Visible = false
	end
	self.Root.Size = UDim2.fromOffset(PANEL_W, 72 + y + 8)
	self.Rescale()
end

return ScoreboardUI
