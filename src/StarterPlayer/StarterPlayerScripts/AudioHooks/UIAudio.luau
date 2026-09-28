--[[
	UIAudio - interface feedback.

	* Every GuiButton in PlayerGui automatically gets hover + click sounds (disabled buttons -
	  Active = false / Interactable = false / attribute Disabled = true - give the "Disabled"
	  sound). Per-button overrides via attributes:
	      ClickSound = "UI.Confirm"  (any cue)   HoverSound = false   NoAudio = true
	  Mobile ability buttons are skipped (they already produce combat sounds).
	* Menus: showing / hiding the Shop, Results and Lobby panels plays open / close.
	* Notifications (existing Notify remote): the server may name a sound in
	  payload.Options.Sound (purchases, mythic items, sells, upgrades); otherwise the style
	  decides (AudioConfig.NotifyStyles).
	* Match flow: minion waves (workspace MinionNextWaveAt), hub notices.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local SKIP_GUIS = { RuinfallMobile = true, Freecam = true }
local MENU_FRAMES = { Shop = true, Results = true, Lobby = true }
local player = Players.LocalPlayer

-- State
local UIAudio = {}
local ctx, Manager, Config = nil, nil, nil
local hooked = setmetatable({}, { __mode = "k" })
local lastHoverAt = 0

local function isDisabled(button)
	if button:GetAttribute("Disabled") == true or button.Active == false then
		return true
	end
	local ok, interactable = pcall(function()
		return button.Interactable
	end)
	return ok and interactable == false
end

local function hookButton(button)
	if hooked[button] then
		return
	end
	hooked[button] = true
	local screen = button:FindFirstAncestorWhichIsA("LayerCollector")
	if screen and SKIP_GUIS[screen.Name] then
		return
	end
	button.MouseEnter:Connect(function()
		if button:GetAttribute("NoAudio") or button:GetAttribute("HoverSound") == false then
			return
		end
		local now = os.clock()
		if now - lastHoverAt < 0.05 then
			return
		end
		lastHoverAt = now
		Manager:Play("UI.Hover")
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("NoAudio") then
			return
		end
		if isDisabled(button) then
			Manager:Play("UI.Disabled")
		else
			Manager:Play(button:GetAttribute("ClickSound") or "UI.Click")
		end
	end)
end

local function hookMenu(frame)
	if hooked[frame] then
		return
	end
	hooked[frame] = true
	local wasVisible = frame.Visible
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible == wasVisible then
			return
		end
		wasVisible = frame.Visible
		if frame.Name == "Results" and frame.Visible then
			return -- the victory / defeat music cue covers it
		end
		Manager:Play(frame.Visible and "UI.MenuOpen" or "UI.MenuClose")
	end)
end

local function scan(item)
	if item:IsA("GuiButton") then
		hookButton(item)
	elseif item:IsA("Frame") and MENU_FRAMES[item.Name] and item.Parent and item.Parent:IsA("ScreenGui") then
		hookMenu(item)
	end
end

local function onNotify(payload)
	if type(payload) ~= "table" then
		return
	end
	local options = payload.Options or {}
	local cue = options.Sound
	if type(cue) ~= "string" then
		cue = Config.NotifyStyles[payload.Style or "Info"]
	end
	if cue then
		Manager:Play(cue, { Source = "Notify" })
	end
end

function UIAudio.Init(context)
	ctx = context
	Manager = ctx.Manager
	Config = ctx.Config
	local playerGui = player:WaitForChild("PlayerGui")
	for _, item in ipairs(playerGui:GetDescendants()) do
		scan(item)
	end
	playerGui.DescendantAdded:Connect(scan)
	-- notifications: same remote the Notifications UI uses
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("Notify").OnClientEvent:Connect(function(payload)
		pcall(onNotify, payload)
	end)
	local hubState = remotes:FindFirstChild("HubState")
	if hubState then
		hubState.OnClientEvent:Connect(function(kind)
			if kind == "Notice" then
				Manager:Play("UI.Notification")
			end
		end)
	end
	-- a new minion wave marches (the server moves the next-wave timer forward)
	local lastWaveAt = workspace:GetAttribute("MinionNextWaveAt") or 0
	workspace:GetAttributeChangedSignal("MinionNextWaveAt"):Connect(function()
		local nextAt = workspace:GetAttribute("MinionNextWaveAt") or 0
		if nextAt > lastWaveAt + 5 and lastWaveAt > 0 and ctx.InMatch() then
			Manager:Play("Objectives.MinionWave")
		end
		lastWaveAt = nextAt
	end)
	return UIAudio
end

return UIAudio
