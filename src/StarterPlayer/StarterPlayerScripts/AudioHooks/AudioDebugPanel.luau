--[[
	AudioDebugPanel - STUDIO ONLY developer tools (never created in live servers).

	F7 (AudioConfig.Debug.TestPanelKey) toggles a panel that lists every cue in AudioConfig
	with a PLAY button, so any sound can be auditioned without triggering the ability /
	monster / UI that normally plays it. "LOG" toggles the "[Audio] Playing: ..." output
	(cue, category, volume, position, priority). Stats show voices, drops and the music track.
	Command bar (client):  _G.RFAudio:Play("Combat.CriticalHit")   _G.RFAudio:SetDebug(true)
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- State
local AudioDebugPanel = {}

function AudioDebugPanel.Init(ctx)
	if not RunService:IsStudio() then
		return AudioDebugPanel
	end
	local Manager = ctx.Manager
	_G.RFAudio = Manager
	local gui, statsLabel = nil, nil

	local function build()
		gui = Instance.new("ScreenGui")
		gui.Name = "RF_AudioDebug"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 60
		gui.Enabled = false
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(1, 0.5)
		frame.Position = UDim2.new(1, -12, 0.5, 0)
		frame.Size = UDim2.fromOffset(300, 460)
		frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		frame.BackgroundTransparency = 0.1
		frame.Parent = gui
		Instance.new("UICorner").Parent = frame
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, -80, 0, 28)
		title.Position = UDim2.fromOffset(10, 4)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(255, 220, 140)
		title.Text = "AUDIO TEST (F7)"
		title.Parent = frame
		local logButton = Instance.new("TextButton")
		logButton.Size = UDim2.fromOffset(64, 22)
		logButton.Position = UDim2.new(1, -72, 0, 7)
		logButton.Font = Enum.Font.GothamBold
		logButton.TextSize = 11
		logButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		logButton.TextColor3 = Color3.new(1, 1, 1)
		logButton:SetAttribute("NoAudio", true)
		logButton.Parent = frame
		local function refreshLog()
			logButton.Text = Manager:IsDebug() and "LOG ON" or "LOG OFF"
		end
		logButton.Activated:Connect(function()
			Manager:SetDebug(not Manager:IsDebug())
			refreshLog()
		end)
		refreshLog()
		statsLabel = Instance.new("TextLabel")
		statsLabel.BackgroundTransparency = 1
		statsLabel.Size = UDim2.new(1, -20, 0, 18)
		statsLabel.Position = UDim2.fromOffset(10, 32)
		statsLabel.Font = Enum.Font.Code
		statsLabel.TextSize = 11
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
		statsLabel.Parent = frame
		local scroll = Instance.new("ScrollingFrame")
		scroll.Position = UDim2.fromOffset(8, 54)
		scroll.Size = UDim2.new(1, -16, 1, -62)
		scroll.BackgroundTransparency = 1
		scroll.ScrollBarThickness = 6
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.Parent = scroll
		for _, cue in ipairs(Manager:GetCueNames()) do
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -8, 0, 20)
			button.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
			button.TextColor3 = Color3.fromRGB(230, 230, 235)
			button.Font = Enum.Font.Code
			button.TextSize = 12
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.Text = "  > " .. cue
			button:SetAttribute("NoAudio", true)
			button.Parent = scroll
			button.Activated:Connect(function()
				local section = string.match(cue, "^(%w+)%.")
				if section == "Music" then
					Manager:PlayMusic(string.sub(cue, 7), { Fade = 0.5 })
				else
					local character = Players.LocalPlayer.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					Manager:Play(cue, { Position = root and (root.Position + root.CFrame.LookVector * 6) or nil, IgnoreCooldown = true, Source = "Test panel" })
				end
			end)
		end
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= ctx.Config.Debug.TestPanelKey then
			return
		end
		if not gui then
			build()
		end
		gui.Enabled = not gui.Enabled
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui and gui.Enabled and statsLabel then
				local stats = Manager:GetStats()
				statsLabel.Text = string.format("voices %d  played %d  dropped %d  stolen %d  loops %d  music %s",
					stats.Busy, stats.Played, stats.Dropped, stats.Stolen, stats.Loops, tostring(stats.Music))
			end
		end
	end)
	return AudioDebugPanel
end

return AudioDebugPanel
