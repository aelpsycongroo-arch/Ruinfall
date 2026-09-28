-- ResultsUI: end-of-match screen (VICTORY / ELIMINATED), scoreboard and
-- return-to-lobby.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label, Button, Panel = UITheme.New, UITheme.Label, UITheme.Button, UITheme.Panel
local COLUMNS = {
	{ Key = "Name", Title = "PLAYER", X = 16, Width = 190, Align = Enum.TextXAlignment.Left },
	{ Key = "Class", Title = "CLASS", X = 210, Width = 100, Align = Enum.TextXAlignment.Left },
	{ Key = "Team", Title = "TEAM", X = 312, Width = 90, Align = Enum.TextXAlignment.Left },
	{ Key = "Kills", Title = "K", X = 404, Width = 44, Align = Enum.TextXAlignment.Center },
	{ Key = "Deaths", Title = "D", X = 450, Width = 44, Align = Enum.TextXAlignment.Center },
	{ Key = "Damage", Title = "DAMAGE", X = 496, Width = 80, Align = Enum.TextXAlignment.Center },
	{ Key = "Flags", Title = "FLAGS", X = 578, Width = 56, Align = Enum.TextXAlignment.Center },
	{ Key = "Ruins", Title = "RUINS", X = 636, Width = 56, Align = Enum.TextXAlignment.Center },
	{ Key = "Status", Title = "STATUS", X = 694, Width = 100, Align = Enum.TextXAlignment.Center },
}

-- State
local ResultsUI = {}
ResultsUI.__index = ResultsUI

function ResultsUI.new(screen, clientState)
	local self = setmetatable({}, ResultsUI)
	self.ClientState = clientState
	self.Rows = {}
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local root = New("Frame", { Name = "Results", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Visible = false, Parent = screen })
	self.Root = root
	local container = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 620), BackgroundTransparency = 1, Parent = root })
	local uiScale = New("UIScale", { Parent = container })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.min(1, viewport.X / 880, viewport.Y / 660)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	self.Title = Label({ Text = "VICTORY", Font = FONTS.Title, TextSize = 88, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 96), TextStrokeTransparency = 0.5, Parent = container })
	New("UIStroke", { Color = Color3.fromRGB(40, 24, 12), Thickness = 2.5, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = self.Title })
	self.Subtitle = Label({ Text = "", Font = FONTS.Bold, TextSize = 22, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 26), Parent = container })

	local board = Panel({ Name = "Scoreboard", Position = UDim2.fromOffset(0, 140), Size = UDim2.fromOffset(820, 380), Parent = container })
	UITheme.MedievalPanel(board, true)
	for _, column in ipairs(COLUMNS) do
		Label({ Text = column.Title, Font = FONTS.Title, TextSize = 12, TextColor3 = COLORS.Subtext, TextXAlignment = column.Align, Position = UDim2.fromOffset(column.X, 14), Size = UDim2.fromOffset(column.Width, 16), Parent = board })
	end
	-- up to Constants.MAX_PARTICIPANTS rows in a scrolling list
	local rowList = New("ScrollingFrame", { Name = "RowList", Position = UDim2.fromOffset(8, 38), Size = UDim2.fromOffset(810, 334), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.fromOffset(0, 0), Parent = board })
	self.RowList = rowList
	for index = 1, Constants.MAX_PARTICIPANTS do
		local rowFrame = New("Frame", { Position = UDim2.fromOffset(0, (index - 1) * 54), Size = UDim2.fromOffset(798, 48), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.3, Parent = rowList })
		UITheme.Corner(rowFrame, 8)
		local teamBar = New("Frame", { Size = UDim2.fromOffset(5, 48), BackgroundColor3 = COLORS.Stroke, Parent = rowFrame })
		local cells = {}
		for _, column in ipairs(COLUMNS) do
			cells[column.Key] = Label({ Text = "", Font = column.Key == "Name" and FONTS.Bold or FONTS.Medium, TextSize = 15, TextXAlignment = column.Align, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(column.X - 8, 0), Size = UDim2.fromOffset(column.Width, 48), Parent = rowFrame })
		end
		self.Rows[index] = { Frame = rowFrame, TeamBar = teamBar, Cells = cells }
	end

	self.ReturnButton = Button({ Name = "ReturnButton", Text = "RETURN TO LOBBY", Font = FONTS.Title, TextSize = 22, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 540), Size = UDim2.fromOffset(340, 56), Parent = container }, function()
		remotes.MatchRequest:FireServer("ReturnToLobby")
	end)
	self.Countdown = Label({ Text = "", Font = FONTS.Medium, TextSize = 14, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 600), Size = UDim2.new(1, 0, 0, 18), Parent = container })
	return self
end

function ResultsUI:SetVisible(visible)
	self.Root.Visible = visible
end

function ResultsUI:Update(state)
	if not self.Root.Visible then
		return
	end
	local myTeam = self.ClientState.GetMyTeam()
	if state.Winner == nil then
		self.Title.Text = "DRAW"
		self.Title.TextColor3 = COLORS.Subtext
		self.Subtitle.Text = "No team survived"
	elseif state.Winner == myTeam then
		self.Title.Text = "VICTORY"
		self.Title.TextColor3 = COLORS.Gold
		self.Subtitle.Text = string.upper(state.WinnerName or Constants.GetTeamName(state.Winner)) .. " WINS"
	else
		self.Title.Text = "ELIMINATED"
		self.Title.TextColor3 = COLORS.Danger
		-- free for all: the winner is a player, not a team
		self.Subtitle.Text = string.upper(state.WinnerName or Constants.GetTeamName(state.Winner)) .. " WINS"
	end

	local list = {}
	for _, participant in ipairs(state.Participants) do
		if not participant.Spectator and participant.Team then
			table.insert(list, participant)
		end
	end
	-- free for all: rank by placement (winner #1, then reverse elimination order)
	local placement = nil
	if state.Royale and state.EliminationOrder then
		placement = {}
		for index, team in ipairs(state.EliminationOrder) do
			placement[team] = #list - index + 1
		end
		if state.Winner then
			placement[state.Winner] = 1
		end
	end
	table.sort(list, function(a, b)
		if placement and (placement[a.Team] or 1) ~= (placement[b.Team] or 1) then
			return (placement[a.Team] or 1) < (placement[b.Team] or 1)
		end
		if (a.Team == state.Winner) ~= (b.Team == state.Winner) then
			return a.Team == state.Winner
		end
		return (a.Stats.Kills * 1000 + a.Stats.Damage) > (b.Stats.Kills * 1000 + b.Stats.Damage)
	end)
	self.RowList.CanvasSize = UDim2.fromOffset(0, math.min(#list, #self.Rows) * 54)
	for index, row in ipairs(self.Rows) do
		local participant = list[index]
		row.Frame.Visible = participant ~= nil
		if participant then
			local classDef = ClassDefinitions.Get(participant.ClassKey)
			row.TeamBar.BackgroundColor3 = Constants.GetTeamColor(participant.Team)
			row.Cells.Name.Text = participant.Name .. (participant.IsBot and "  (bot)" or "")
			row.Cells.Class.Text = classDef and classDef.DisplayName or "?"
			row.Cells.Class.TextColor3 = classDef and classDef.Color or COLORS.Text
			row.Cells.Team.Text = Constants.GetTeamName(participant.Team)
			row.Cells.Team.TextColor3 = Constants.GetTeamColor(participant.Team)
			row.Cells.Kills.Text = tostring(participant.Stats.Kills)
			row.Cells.Deaths.Text = tostring(participant.Stats.Deaths)
			row.Cells.Damage.Text = tostring(math.floor(participant.Stats.Damage))
			row.Cells.Flags.Text = tostring(participant.Stats.Flags)
			row.Cells.Ruins.Text = tostring(participant.Stats.Ruins)
			local won = participant.Team == state.Winner
			row.Cells.Status.Text = won and "WINNER" or (placement and ("#" .. tostring(placement[participant.Team] or "?")) or "ELIMINATED")
			row.Cells.Status.TextColor3 = won and COLORS.Gold or COLORS.Danger
		end
	end
	local isHost = self.ClientState.IsHost()
	self.ReturnButton.Visible = isHost
	local remaining = math.max(0, math.ceil((state.StateEndsAt or 0) - workspace:GetServerTimeNow()))
	self.Countdown.Text = (isHost and "" or "Waiting for host - ") .. "Returning to lobby in " .. remaining .. "s"
end

return ResultsUI
