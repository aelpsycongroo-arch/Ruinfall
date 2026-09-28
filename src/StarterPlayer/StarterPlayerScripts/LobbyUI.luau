-- LobbyUI: game mode, bots, difficulty, class selection and match start.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local STATE = Constants.MatchState
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label, Button, Panel = UITheme.New, UITheme.Label, UITheme.Button, UITheme.Panel
local MODE_DESCRIPTIONS = {
	["2Team"] = "Two squads - classic MOBA",
	["4Team"] = "Up to four squads",
	["6Team"] = "Everyone for themselves",
}
local STAT_ORDER = { { "Health", "HP" }, { "Damage", "DMG" }, { "Range", "RNG" }, { "Speed", "SPD" }, { "Armor", "ARM" } }

-- State
local LobbyUI = {}
LobbyUI.__index = LobbyUI

-- Functions
local function header(parent, text, y)
	return Label({ Text = text, Font = FONTS.Title, TextSize = 15, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 22), Parent = parent })
end

function LobbyUI.new(screen, clientState)
	local self = setmetatable({}, LobbyUI)
	self.ClientState = clientState
	self.Remotes = ReplicatedStorage:WaitForChild("Remotes")
	self.ModeButtons = {}
	self.DifficultyButtons = {}
	self.ClassCards = {}
	self.Rows = {}

	local root = New("Frame", { Name = "Lobby", Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLORS.Background, ZIndex = 1, Parent = screen })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(58, 40, 28), Color3.fromRGB(12, 9, 7)), Parent = root })
	self.Root = root

	local container = New("Frame", { Name = "Container", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1220, 740), BackgroundTransparency = 1, Parent = root })
	local uiScale = New("UIScale", { Parent = container })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.min(1, viewport.X / 1270, viewport.Y / 780)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local title = Label({ Text = "RUINFALL", Font = FONTS.Title, TextSize = 86, Size = UDim2.new(1, 0, 0, 92), TextXAlignment = Enum.TextXAlignment.Center, Parent = container })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 232, 160), Color3.fromRGB(196, 132, 58)), Parent = title })
	UITheme.New("UIStroke", { Color = Color3.fromRGB(40, 24, 12), Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = title })
	Label({ Text = "MULTIPLAYER SEMI-MOBA  -  PROTOTYPE", Font = FONTS.Medium, TextSize = 16, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Parent = container })

	-- Mode + difficulty panel ------------------------------------------------
	local modePanel = Panel({ Name = "ModePanel", Position = UDim2.fromOffset(0, 130), Size = UDim2.fromOffset(300, 500), Parent = container })
	UITheme.MedievalPanel(modePanel, true)
	header(modePanel, "GAME MODE", 16)
	for index, mode in ipairs(Constants.TeamModeOrder) do
		local button, stroke = Button({ Name = mode, Text = "", Position = UDim2.fromOffset(18, 48 + (index - 1) * 74), Size = UDim2.fromOffset(264, 64), Parent = modePanel }, function()
			self.Remotes.LobbyRequest:FireServer("SetMode", mode)
		end)
		Label({ Text = Constants.TeamModeLabels[mode], Font = FONTS.Title, TextSize = 21, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24), Parent = button })
		Label({ Text = MODE_DESCRIPTIONS[mode], Font = FONTS.Medium, TextSize = 13, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 16), Parent = button })
		self.ModeButtons[mode] = { Button = button, Stroke = stroke }
	end
	header(modePanel, "YOUR TEAM", 270)
	self.TeamButtons = {}
	for index, teamInfo in ipairs(Constants.Teams) do
		local teamNum = index
		local button, stroke = Button({ Name = "Team" .. teamNum, Text = "", Position = UDim2.fromOffset(18 + (index - 1) * 44, 298), Size = UDim2.fromOffset(38, 38), Parent = modePanel }, function()
			self.Remotes.LobbyRequest:FireServer("SetTeam", teamNum)
		end)
		local colorBar = New("Frame", { Name = "ColorBar", Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = teamInfo.Color, Parent = button })
		UITheme.Corner(colorBar, 4)
		Label({ Text = string.sub(teamInfo.Name, 1, 1), Font = FONTS.Title, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 2, Parent = colorBar })
		self.TeamButtons[teamNum] = { Button = button, Stroke = stroke, Color = teamInfo.Color }
	end

	header(modePanel, "BOT DIFFICULTY", 348)
	for index, difficulty in ipairs(Constants.BotDifficultyOrder) do
		local button, stroke = Button({ Name = difficulty, Text = string.upper(difficulty), TextSize = 14, Position = UDim2.fromOffset(18 + (index - 1) * 89, 378), Size = UDim2.fromOffset(83, 40), Parent = modePanel }, function()
			self.Remotes.LobbyRequest:FireServer("SetDifficulty", difficulty)
		end)
		self.DifficultyButtons[difficulty] = { Button = button, Stroke = stroke }
	end
	Label({
		Text = "CONTROLS\nWASD move  -  Left click attack\nQ ability  -  E / R items  -  Right click boots\nB shop  -  Mouse wheel zoom\n\nThe host controls mode, bots and difficulty.",
		Font = FONTS.Medium, TextSize = 13, TextColor3 = COLORS.Subtext, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(18, 430), Size = UDim2.new(1, -36, 0, 60), Parent = modePanel,
	})

	-- Participants panel --------------------------------------------------------
	local participantPanel = Panel({ Name = "ParticipantPanel", Position = UDim2.fromOffset(320, 130), Size = UDim2.fromOffset(400, 500), Parent = container })
	UITheme.MedievalPanel(participantPanel, true)
	header(participantPanel, "PARTICIPANTS", 16)
	self.CountLabel = Label({ Text = "0 / " .. Constants.MAX_PARTICIPANTS, Font = FONTS.Title, TextSize = 15, TextColor3 = COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(18, 16), Size = UDim2.new(1, -36, 0, 22), Parent = participantPanel })
	-- up to Constants.MAX_PARTICIPANTS rows in a scrolling list
	local rowList = New("ScrollingFrame", { Name = "RowList", Position = UDim2.fromOffset(16, 48), Size = UDim2.fromOffset(372, 348), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.fromOffset(0, Constants.MAX_PARTICIPANTS * 58), Parent = participantPanel })
	for index = 1, Constants.MAX_PARTICIPANTS do
		local rowFrame = New("Frame", { Name = "Row" .. index, Position = UDim2.fromOffset(0, (index - 1) * 58), Size = UDim2.fromOffset(362, 50), BackgroundColor3 = COLORS.PanelLight, BackgroundTransparency = 0.3, Parent = rowList })
		UITheme.Corner(rowFrame, 8)
		local teamBar = New("Frame", { Name = "TeamBar", Size = UDim2.fromOffset(6, 50), BackgroundColor3 = COLORS.Stroke, Parent = rowFrame })
		UITheme.Corner(teamBar, 3)
		local nameLabel = Label({ Name = "PlayerName", Text = "Open slot", TextSize = 17, Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(210, 20), TextTruncate = Enum.TextTruncate.AtEnd, Parent = rowFrame })
		local tagLabel = Label({ Name = "Tag", Text = "", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(18, 28), Size = UDim2.fromOffset(210, 16), Parent = rowFrame })
		local row = { Frame = rowFrame, TeamBar = teamBar, NameLabel = nameLabel, TagLabel = tagLabel, Participant = nil }
		row.ClassButton = Button({ Name = "ClassButton", Text = "-", TextSize = 13, Position = UDim2.fromOffset(234, 9), Size = UDim2.fromOffset(120, 32), Parent = rowFrame }, function()
			local participant = row.Participant
			if participant and participant.IsBot and self.ClientState.IsHost() then
				self.Remotes.LobbyRequest:FireServer("CycleBotClass", participant.Id)
			end
		end)
		self.Rows[index] = row
	end
	self.AddBotButton = Button({ Name = "AddBot", Text = "+ ADD BOT", Font = FONTS.Title, TextSize = 15, BackgroundColor3 = Color3.fromRGB(40, 70, 55), Position = UDim2.fromOffset(16, 406), Size = UDim2.fromOffset(176, 44), Parent = participantPanel }, function()
		self.Remotes.LobbyRequest:FireServer("AddBot")
	end)
	self.RemoveBotButton = Button({ Name = "RemoveBot", Text = "- REMOVE BOT", Font = FONTS.Title, TextSize = 15, BackgroundColor3 = Color3.fromRGB(75, 40, 45), Position = UDim2.fromOffset(208, 406), Size = UDim2.fromOffset(176, 44), Parent = participantPanel }, function()
		self.Remotes.LobbyRequest:FireServer("RemoveBot")
	end)
	Label({ Text = "Click a bot's class to change it (host).", Font = FONTS.Medium, TextSize = 12, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(16, 460), Size = UDim2.new(1, -32, 0, 18), Parent = participantPanel })

	-- Class panel -------------------------------------------------------------------
	local classPanel = Panel({ Name = "ClassPanel", Position = UDim2.fromOffset(740, 130), Size = UDim2.fromOffset(480, 500), Parent = container })
	UITheme.MedievalPanel(classPanel, true)
	header(classPanel, "CHOOSE YOUR CLASS", 16)
	for index, classKey in ipairs(ClassDefinitions.Order) do
		local classDef = ClassDefinitions.Get(classKey)
		local card, stroke = Button({ Name = classKey, Text = "", Position = UDim2.fromOffset(16, 46 + (index - 1) * 80), Size = UDim2.fromOffset(448, 72), Parent = classPanel }, function()
			self.PendingClass = classKey
			self.Remotes.SelectClass:FireServer(classKey)
			self:RefreshClassCards(classKey)
		end)
		local icon = New("Frame", { Name = "Icon", Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = classDef.Color, Parent = card })
		UITheme.Corner(icon, 28)
		UITheme.Stroke(icon, Color3.new(1, 1, 1), 2, 0.6)
		if classDef.IconImage then
			-- rendered class emblem (its own coloured badge) replaces the letter glyph
			icon.BackgroundTransparency = 1
			New("ImageLabel", { Name = "Emblem", BackgroundTransparency = 1, Image = classDef.IconImage, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.15, 1.15), Parent = icon })
		else
			Label({ Text = classDef.Icon, Font = FONTS.Title, TextSize = 28, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = icon })
		end
		Label({ Text = string.upper(classDef.DisplayName), Font = FONTS.Title, TextSize = 19, Position = UDim2.fromOffset(78, 8), Size = UDim2.fromOffset(200, 22), Parent = card })
		Label({ Text = classDef.Role, Font = FONTS.Medium, TextSize = 13, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(78, 31), Size = UDim2.fromOffset(200, 16), Parent = card })
		Label({ Text = "Q  " .. classDef.Ability.Name, Font = FONTS.Bold, TextSize = 13, TextColor3 = COLORS.Gold, Position = UDim2.fromOffset(78, 49), Size = UDim2.fromOffset(200, 16), Parent = card })
		for statIndex, stat in ipairs(STAT_ORDER) do
			local y = 6 + (statIndex - 1) * 12
			Label({ Text = stat[2], Font = FONTS.Bold, TextSize = 10, TextColor3 = COLORS.Subtext, Position = UDim2.fromOffset(292, y), Size = UDim2.fromOffset(30, 11), Parent = card })
			for pip = 1, 5 do
				local filled = pip <= classDef.Ratings[stat[1]]
				local pipFrame = New("Frame", { Position = UDim2.fromOffset(326 + (pip - 1) * 22, y + 2), Size = UDim2.fromOffset(18, 7), BackgroundColor3 = filled and classDef.Color or Color3.fromRGB(70, 56, 44), Parent = card })
				UITheme.Corner(pipFrame, 3)
			end
		end
		self.ClassCards[classKey] = { Button = card, Stroke = stroke, Color = classDef.Color }
	end
	self.AbilityLabel = Label({ Text = "", Font = FONTS.Medium, TextSize = 13, TextColor3 = COLORS.Text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 450), Size = UDim2.new(1, -36, 0, 44), Parent = classPanel })

	-- Match servers reached from the Ruinfall Hall can walk back to the hub
	if game:GetService("ReplicatedStorage"):GetAttribute("ReservedServer") == true then
		Button({ Name = "ReturnToHall", Text = "< RETURN TO HALL", Font = FONTS.Title, TextSize = 15, BackgroundColor3 = UITheme.Medieval.WoodLight, Position = UDim2.fromOffset(0, 660), Size = UDim2.fromOffset(200, 40), Parent = container }, function()
			self.Remotes.HubRequest:FireServer("ReturnToHall")
		end)
	end

	-- Start -------------------------------------------------------------------------
	self.StartButton = Button({ Name = "StartButton", Text = "START MATCH", Font = FONTS.Title, TextSize = 26, TextColor3 = Color3.fromRGB(30, 20, 10), BackgroundColor3 = COLORS.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 648), Size = UDim2.fromOffset(400, 62), Parent = container }, function()
		if self.ClientState.IsHost() then
			self.Remotes.MatchRequest:FireServer("Start")
		end
	end)
	self.StatusLabel = Label({ Text = "", Font = FONTS.Medium, TextSize = 14, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 716), Size = UDim2.new(1, 0, 0, 20), Parent = container })

	-- Map generation overlay ----------------------------------------------------------
	self.Loading = New("Frame", { Name = "Loading", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, Visible = false, ZIndex = 20, Parent = root })
	self.LoadingLabel = Label({ Text = "GENERATING ARENA...", Font = FONTS.Title, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(800, 50), ZIndex = 21, Parent = self.Loading })
	self.LoadingSub = Label({ Text = "", Font = FONTS.Medium, TextSize = 16, TextColor3 = COLORS.Subtext, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(800, 24), ZIndex = 21, Parent = self.Loading })

	self:RefreshClassCards("Fighter")
	return self
end

function LobbyUI:RefreshClassCards(selectedKey)
	for classKey, card in pairs(self.ClassCards) do
		local selected = classKey == selectedKey
		UITheme.SetButtonColor(card.Button, selected and COLORS.PanelLight:Lerp(card.Color, 0.25) or COLORS.PanelLight)
		card.Stroke.Color = selected and card.Color or COLORS.Stroke
		card.Stroke.Thickness = selected and 2.5 or 1.5
	end
	local classDef = ClassDefinitions.Get(selectedKey)
	if classDef then
		self.AbilityLabel.Text = string.format("%s - %s (%ds cooldown)", classDef.Ability.Name, classDef.Ability.Description, classDef.Ability.Cooldown)
	end
end

function LobbyUI:SetVisible(visible)
	self.Root.Visible = visible
end

function LobbyUI:Update(state)
	local clientState = self.ClientState
	local isHost = clientState.IsHost()
	local me = clientState.GetMe()

	for mode, entry in pairs(self.ModeButtons) do
		local selected = state.Mode == mode
		UITheme.SetButtonColor(entry.Button, selected and Color3.fromRGB(96, 64, 34) or COLORS.PanelLight)
		entry.Stroke.Color = selected and COLORS.Accent or COLORS.Stroke
		entry.Stroke.Thickness = selected and 2.5 or 1.5
	end
	for difficulty, entry in pairs(self.DifficultyButtons) do
		local selected = state.Difficulty == difficulty
		UITheme.SetButtonColor(entry.Button, selected and Color3.fromRGB(96, 64, 34) or COLORS.PanelLight)
		entry.Stroke.Color = selected and COLORS.Accent or COLORS.Stroke
	end

	-- Team selection buttons
	local maxTeams = Constants.TeamModeSlots[state.Mode] or 2
	local myTeam = me and me.Team or nil
	for teamNum, entry in pairs(self.TeamButtons) do
		local visible = teamNum <= maxTeams
		entry.Button.Visible = visible
		if visible then
			local selected = myTeam == teamNum
			entry.Stroke.Color = selected and entry.Color or COLORS.Stroke
			entry.Stroke.Thickness = selected and 3 or 1.5
			UITheme.SetButtonColor(entry.Button, selected and entry.Color:Lerp(Color3.new(0, 0, 0), 0.5) or COLORS.PanelLight)
		end
	end

	local list = {}
	for _, participant in ipairs(state.Participants) do
		if not participant.Spectator then
			table.insert(list, participant)
		end
	end
	self.CountLabel.Text = #list .. " / " .. Constants.MAX_PARTICIPANTS
	for index, row in ipairs(self.Rows) do
		local participant = list[index]
		row.Participant = participant
		if participant then
			local classDef = ClassDefinitions.Get(participant.ClassKey)
			local isMe = me ~= nil and participant.Id == me.Id
			row.Frame.BackgroundTransparency = isMe and 0.05 or 0.3
			row.TeamBar.BackgroundColor3 = Constants.GetTeamColor(participant.Team)
			row.NameLabel.Text = participant.Name
			row.NameLabel.TextColor3 = COLORS.Text
			local tag
			if participant.IsBot then
				tag = "BOT - " .. string.upper(participant.Difficulty or "Normal")
			else
				tag = (isMe and "YOU" or "PLAYER") .. (participant.IsHost and " - HOST" or "")
			end
			row.TagLabel.Text = tag .. "  |  " .. string.upper(Constants.GetTeamName(participant.Team))
			row.ClassButton.Visible = true
			row.ClassButton.Text = string.upper(classDef and classDef.DisplayName or "?")
			UITheme.SetButtonColor(row.ClassButton, classDef and classDef.Color:Lerp(Color3.new(0, 0, 0), 0.45) or COLORS.PanelLight)
			if isMe and not self.PendingClass then
				self:RefreshClassCards(participant.ClassKey)
			elseif isMe and self.PendingClass == participant.ClassKey then
				self.PendingClass = nil
			end
		else
			row.Frame.BackgroundTransparency = 0.7
			row.TeamBar.BackgroundColor3 = COLORS.Stroke
			row.NameLabel.Text = "Open slot"
			row.NameLabel.TextColor3 = COLORS.Subtext
			row.TagLabel.Text = ""
			row.ClassButton.Visible = false
		end
	end

	self.AddBotButton.Visible = isHost
	self.RemoveBotButton.Visible = isHost
	self.StartButton.Text = isHost and "START MATCH" or "WAITING FOR HOST"
	UITheme.SetButtonColor(self.StartButton, isHost and COLORS.Gold or COLORS.PanelLight)
	if me and me.Spectator then
		self.StatusLabel.Text = "The lobby is full - you will join the next match."
	elseif #list < Constants.MIN_PARTICIPANTS then
		self.StatusLabel.Text = "Add at least one bot to start (2 participants minimum)."
	else
		self.StatusLabel.Text = string.format("%s  -  %d participants  -  bots: %s", Constants.TeamModeLabels[state.Mode] or state.Mode, #list, state.Difficulty)
	end

	local loading = state.State == STATE.PREPARING or state.State == STATE.GENERATING
	self.Loading.Visible = loading
	if loading then
		self.LoadingLabel.Text = state.State == STATE.PREPARING and "PREPARING MATCH..." or "GENERATING ARENA..."
		self.LoadingSub.Text = state.Seed and ("Seed " .. tostring(state.Seed)) or ""
	end
end

return LobbyUI
