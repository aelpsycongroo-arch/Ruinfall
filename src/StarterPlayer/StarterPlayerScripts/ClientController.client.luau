-- ClientController: Ruinfall client entry point. Wires up every controller.
-- On hub servers (the Ruinfall Hall) it only runs HubController until the server
-- becomes a match server (Studio fallback); real matches run on reserved servers.

-- Services
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local scripts = script.Parent

-- Hub gate ---------------------------------------------------------------------------
do
	local waited = 0
	while ReplicatedStorage:GetAttribute("ServerRole") == nil and waited < 10 do
		waited += task.wait(0.1)
	end
	if ReplicatedStorage:GetAttribute("ServerRole") == "Hub" then
		local HubController = require(scripts:WaitForChild("HubController"))
		HubController.Run()
		while ReplicatedStorage:GetAttribute("ServerRole") == "Hub" do
			ReplicatedStorage:GetAttributeChangedSignal("ServerRole"):Wait()
		end
		HubController.Stop()
	end
end

local ClientState = require(scripts:WaitForChild("ClientState"))
local FogController = require(scripts:WaitForChild("FogController"))
local CombatController = require(scripts:WaitForChild("CombatController"))
local CameraController = require(scripts:WaitForChild("CameraController"))
local InputController = require(scripts:WaitForChild("InputController"))
local EffectsController = require(scripts:WaitForChild("EffectsController"))
local UnitDisplayController = require(scripts:WaitForChild("UnitDisplayController"))
local UIController = require(scripts:WaitForChild("UIController"))
local MinimapController = require(scripts:WaitForChild("MinimapController"))
local MobileController = require(scripts:WaitForChild("MobileController"))

-- Functions
local function configureCoreGui()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	-- Resetting would bypass the flag/Last Stand rules, so it is disabled
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end

-- Initialization
ClientState.Init()
FogController.Init(ClientState)
CombatController.Init(ClientState)
CameraController.Init(ClientState, CombatController)
InputController.Init(CombatController)
EffectsController.Init(ClientState, FogController)
UnitDisplayController.Init(ClientState, FogController)
UIController.Init(ClientState, CombatController)
MinimapController.Init(ClientState, FogController, UIController.HUD.Root)
MobileController.Init(ClientState, CombatController, UIController, CameraController)
CombatController.MoveOrdered:Connect(EffectsController.MoveMarker)
task.spawn(configureCoreGui)
