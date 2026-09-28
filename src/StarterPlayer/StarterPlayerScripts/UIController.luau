-- UIController: owns the RuinfallHUD ScreenGui and switches between lobby,
-- in-match HUD and results based on the server match state.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local LobbyUI = require(script.Parent:WaitForChild("LobbyUI"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local ResultsUI = require(script.Parent:WaitForChild("ResultsUI"))
local Notifications = require(script.Parent:WaitForChild("Notifications"))
local ShopUI = require(script.Parent:WaitForChild("ShopUI"))

-- Constants
local STATE = Constants.MatchState
local player = Players.LocalPlayer

-- State
local UIController = {}
UIController.Screen = nil

-- Public API
function UIController.Init(clientState, combatController)
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("RuinfallHUD")
	if existing then
		existing:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "RuinfallHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 5
	screen.Parent = playerGui
	UIController.Screen = screen

	local lobby = LobbyUI.new(screen, clientState)
	local hud = HUD.new(screen, clientState, combatController)
	local results = ResultsUI.new(screen, clientState)
	local notifications = Notifications.new(screen)
	-- the shop is built in a pcall: if it ever errors, the lobby / HUD / results keep working
	local shopOk, shop = pcall(ShopUI.new, screen, clientState)
	if not shopOk then
		warn("[Ruinfall] Shop UI failed to build:", shop)
		shop = { Root = { Visible = false }, SetVisible = function() end, Update = function() end }
	end
	UIController.Lobby = lobby
	UIController.HUD = hud
	UIController.Results = results
	UIController.Notifications = notifications
	UIController.Shop = shop

	clientState.Notified:Connect(function(payload)
		notifications:Push(payload)
	end)
	clientState.LocalMessage:Connect(function(text, style)
		notifications:ShowToast(text, style)
	end)
	combatController.AbilityDenied:Connect(function(reason)
		if reason == "Cooldown" then
			notifications:ShowToast("Ability on cooldown", "Warning")
		end
	end)

	local function applyMatchState(matchState)
		local inLobby = matchState == STATE.LOBBY or matchState == STATE.PREPARING or matchState == STATE.GENERATING
		local inMatch = matchState == STATE.STARTING or matchState == STATE.ACTIVE or matchState == STATE.ENDING
		lobby:SetVisible(inLobby)
		hud:SetVisible(inMatch)
		results:SetVisible(matchState == STATE.RESULTS)
		if not inMatch then
			shop:SetVisible(false)
		end
	end
	clientState.StateChanged:Connect(applyMatchState)
	clientState.Changed:Connect(function(state)
		lobby:Update(state)
		hud:Update(state)
		results:Update(state)
		shop:Update(state)
	end)
	applyMatchState(clientState.GetMatchState())

	RunService.RenderStepped:Connect(function()
		hud:Tick()
	end)
end

return UIController
