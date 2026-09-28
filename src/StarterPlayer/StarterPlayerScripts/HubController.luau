-- HubController: client UI for the Ruinfall Hall (hub servers).
-- The menu LOOK is ReplicatedStorage.HUD.HallMenu (painted plaques in the same style as the
-- in-match HUD; built by ServerStorage.HUDTools.HallMenuBuilder and safe to edit or replace by
-- hand). This script clones it and fills it: the lobby board (join any lobby), your war party
-- (members, team mode, start / leave) and hall notices. Players can also walk to a gate and
-- press E. The server (HubService) owns all lobby state; this only renders snapshots and sends
-- intents. Missing / renamed layout elements are reported once and skipped (HUD.Bind).

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local HUDModule = script.Parent:WaitForChild("HUD")
local Theme = require(HUDModule:WaitForChild("Theme"))
local Bind = require(HUDModule:WaitForChild("Bind"))

-- Constants
local find = Bind.find
local STYLES = Theme.ButtonStyles
local ZWNJ = utf8.char(0x200C) -- stops the title font from fusing "II" into one glyph
local MEMBER_ROWS_VISIBLE = 8
local player = Players.LocalPlayer

-- State
local HubController = {}
local gui = nil
local connections = {}
local remotes = nil
local lobbyCards = {}
local party = nil
local notice = nil
local lastSnapshot = nil
local noticeToken = 0

-- Helpers -------------------------------------------------------------------------------
local function send(action, value)
	remotes.HubRequest:FireServer(action, value)
end

local function myLobby(snapshot)
	for _, lobby in ipairs(snapshot.Lobbies) do
		for _, member in ipairs(lobby.Members) do
			if member.UserId == player.UserId then
				return lobby, member.IsHost
			end
		end
	end
	return nil, false
end

local function numerals(text)
	return (string.gsub(text, "I", "I" .. ZWNJ))
end

local function setStyle(button, styleName)
	local style = STYLES[styleName] or STYLES.Primary
	button.BackgroundColor3 = style.Fill
	button.TextColor3 = style.Text
	button.AutoButtonColor = styleName ~= "Disabled"
	local rim = button:FindFirstChild("Rim")
	if rim and rim:IsA("UIStroke") then
		rim.Color = style.Stroke
	end
end

local function showNotice(text, style)
	if not notice then
		return
	end
	noticeToken += 1
	local token = noticeToken
	notice.Message.Text = text
	notice.Tint.ImageColor3 = Theme.TintColor(UITheme.StyleColors[style or "Info"] or Theme.Colors.GoldBright)
	notice.Frame.Visible = true
	task.delay(3.5, function()
		if token == noticeToken and notice then
			notice.Frame.Visible = false
		end
	end)
end

-- Build (bind the template) ---------------------------------------------------------------
local render

local function buildGui()
	local folder = ReplicatedStorage:FindFirstChild("HUD")
	local template = folder and folder:FindFirstChild("HallMenu")
	if template then
		gui = template:Clone()
	else
		warn("[Hub] ReplicatedStorage.HUD.HallMenu is missing - run ServerStorage.HUDTools.HallMenuBuilder.Build()")
		gui = Instance.new("ScreenGui")
		gui.Name = "HallMenu"
	end
	gui.ResetOnSpawn = false
	gui.Enabled = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = find(gui, "Root", "Frame")

	-- class emblems on the title plaque
	local classes = find(root, "LeftColumn.Title.Classes", "Frame")
	for index, classKey in ipairs(ClassDefinitions.Order) do
		local classDef = ClassDefinitions.Get(classKey)
		local emblem = Instance.new("ImageLabel")
		emblem.Name = "Class_" .. classKey
		emblem.BackgroundTransparency = 1
		emblem.Image = classDef.IconImage or ""
		emblem.Size = UDim2.fromScale(0.16, 0.9)
		emblem.ZIndex = 4
		emblem.LayoutOrder = index
		Instance.new("UIAspectRatioConstraint").Parent = emblem
		emblem.Parent = classes
	end

	-- lobby board
	for index = 1, 4 do
		local path = "LeftColumn.LobbyBoard.Lobby" .. index
		local card = {
			Frame = find(root, path, "Frame"), Tint = find(root, path .. ".Tint", "ImageLabel"),
			Selected = find(root, path .. ".Selected", "Frame"), Name = find(root, path .. ".LobbyName", "TextLabel"),
			Sub = find(root, path .. ".Sub", "TextLabel"), Info = find(root, path .. ".Info", "TextLabel"),
			Join = find(root, path .. ".Join", "TextButton"),
		}
		table.insert(connections, card.Join.Activated:Connect(function()
			send("Join", index)
		end))
		lobbyCards[index] = card
	end

	-- war party
	party = {
		Frame = find(root, "WarParty", "Frame"),
		HeaderTint = find(root, "WarParty.Header.Tint", "ImageLabel"), Name = find(root, "WarParty.Header.Heading", "TextLabel"),
		Gate = find(root, "WarParty.Header.Gate", "TextLabel"), Count = find(root, "WarParty.Header.Count", "TextLabel"),
		PanelTint = find(root, "WarParty.Panel.Tint", "ImageLabel"), List = find(root, "WarParty.Panel.Members", "ScrollingFrame"),
		RowTemplate = find(root, "WarParty.Panel.MemberTemplate", "Frame"), Modes = {},
		HostHint = find(root, "WarParty.Panel.HostHint", "TextLabel"), Start = find(root, "WarParty.Panel.Start", "TextButton"),
		Leave = find(root, "WarParty.Panel.Leave", "TextButton"), StudioNote = find(root, "WarParty.Panel.StudioNote", "TextLabel"),
	}
	party.Frame.Visible = false
	for index = 1, 3 do
		local button = find(root, "WarParty.Panel.Mode" .. index, "TextButton")
		table.insert(connections, button.Activated:Connect(function()
			local mode = lastSnapshot and lastSnapshot.Modes[index]
			if mode then
				send("SetMode", mode.Key)
			end
		end))
		party.Modes[index] = button
	end
	table.insert(connections, party.Start.Activated:Connect(function()
		send("Start")
	end))
	table.insert(connections, party.Leave.Activated:Connect(function()
		send("Leave")
	end))
	-- member rows are sized from the list's on-screen height: re-render when it changes
	table.insert(connections, party.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if lastSnapshot then
			render(lastSnapshot)
		end
	end))

	-- notices
	notice = { Frame = find(root, "Notice", "Frame"), Tint = find(root, "Notice.Tint", "ImageLabel"), Message = find(root, "Notice.Message", "TextLabel") }
	notice.Frame.Visible = false
end

-- Render --------------------------------------------------------------------------------
local function renderMembers(mine)
	for _, child in ipairs(party.List:GetChildren()) do
		if child.Name == "Member" then
			child:Destroy()
		end
	end
	local rowHeight = math.max(16, math.floor(party.List.AbsoluteSize.Y / MEMBER_ROWS_VISIBLE) - 4)
	for order, member in ipairs(mine.Members) do
		local isMe = member.UserId == player.UserId
		local row = party.RowTemplate:Clone()
		row.Name = "Member"
		row.LayoutOrder = order
		row.Visible = true
		row.Size = UDim2.new(1, -8, 0, rowHeight)
		row.BackgroundTransparency = isMe and 0.05 or 0.35
		local nameLabel = row:FindFirstChild("PlayerName")
		if nameLabel then
			nameLabel.Text = member.Name
		end
		local host = row:FindFirstChild("Host")
		if host then
			host.Visible = member.IsHost == true
		end
		local rim = row:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Transparency = isMe and 0.1 or 0.6
		end
		row.Parent = party.List
	end
end

function render(snapshot)
	lastSnapshot = snapshot
	local mine, amHost = myLobby(snapshot)
	for index, card in ipairs(lobbyCards) do
		local lobby = snapshot.Lobbies[index]
		card.Frame.Visible = lobby ~= nil
		if lobby then
			card.Tint.ImageColor3 = Theme.TintColor(lobby.Color)
			card.Name.Text = numerals(lobby.Name)
			card.Name.TextColor3 = lobby.Color
			card.Sub.Text = lobby.Title
			local state = lobby.State == "Launching" and "MARCHING OUT" or string.upper(lobby.ModeLabel)
			card.Info.Text = string.format("%s  |  %d / %d", state, #lobby.Members, lobby.Max)
			local isMine = mine ~= nil and mine.Id == lobby.Id
			card.Selected.Visible = isMine
			local joinable = lobby.State == "Open" and #lobby.Members < lobby.Max and not isMine
			card.Join.Text = isMine and "HERE" or (lobby.State ~= "Open" and "BUSY" or (#lobby.Members >= lobby.Max and "FULL" or "JOIN"))
			setStyle(card.Join, isMine and "Gold" or (joinable and "Primary" or "Disabled"))
		end
	end
	party.Frame.Visible = mine ~= nil
	if not mine then
		return
	end
	local tint = Theme.TintColor(mine.Color)
	party.HeaderTint.ImageColor3 = tint
	party.PanelTint.ImageColor3 = tint
	party.Name.Text = numerals(mine.Name)
	party.Name.TextColor3 = mine.Color
	party.Gate.Text = mine.Title
	party.Count.Text = string.format("%d / %d", #mine.Members, mine.Max)
	renderMembers(mine)
	for index, button in ipairs(party.Modes) do
		local mode = snapshot.Modes[index]
		button.Visible = mode ~= nil
		if mode then
			button.Text = string.upper(mode.Label)
			local selected = mode.Key == mine.Mode
			setStyle(button, selected and "Gold" or (amHost and "Dark" or "Disabled"))
		end
	end
	local launching = mine.State == "Launching"
	party.HostHint.Text = amHost and "You are the host - pick a mode and march when ready" or "Waiting for the host to start..."
	party.Start.Visible = amHost
	party.Start.Text = launching and "MARCHING OUT..." or "MARCH TO BATTLE"
	setStyle(party.Start, launching and "Disabled" or "Primary")
	party.StudioNote.Text = snapshot.Studio and "Studio: the match runs on this server (no teleport)" or "Your party is teleported to its own battle server"
end

-- Public API ---------------------------------------------------------------------------
function HubController.Run()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	buildGui()
	table.insert(connections, remotes:WaitForChild("HubState").OnClientEvent:Connect(function(kind, payload)
		if kind == "State" and type(payload) == "table" then
			render(payload)
		elseif kind == "Notice" and type(payload) == "table" then
			showNotice(payload.Text or "", payload.Style)
		end
	end))
	send("Sync")
end

function HubController.Stop()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
	end
	notice = nil
	table.clear(lobbyCards)
	party = nil
	lastSnapshot = nil
end

return HubController
