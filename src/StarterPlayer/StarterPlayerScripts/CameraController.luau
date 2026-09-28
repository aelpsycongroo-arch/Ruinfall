-- CameraController: smooth angled top-down camera at a FIXED zoom (Constants.Camera.HEIGHT -
-- mouse wheel and pinch do nothing) with a slight peek toward the cursor. Spectates teammates
-- while dead.

-- Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

-- Constants
local CAMERA = Constants.Camera
local SNAP_DISTANCE = 140

-- State
local CameraController = {}
local ClientState = nil
local CombatController = nil
local height = CAMERA.HEIGHT
local targetHeight = CAMERA.HEIGHT
local focus = Vector3.zero
local lobbyAngle = 0

-- Functions
local function heroRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function getFocus(dt)
	local character = ClientState.GetLocalCharacter()
	local root = heroRoot(character)
	if ClientState.InMatch() then
		if root then
			local peek = Vector3.zero
			local aim = CombatController.GetAim()
			if aim then
				peek = Util.Flat(aim - root.Position) * CAMERA.PEEK_FACTOR
				if peek.Magnitude > CAMERA.MAX_PEEK then
					peek = peek.Unit * CAMERA.MAX_PEEK
				end
			end
			return Vector3.new(root.Position.X, 0, root.Position.Z) + peek
		end
		-- Dead: follow a living teammate, or anyone when eliminated
		local myTeam = ClientState.GetMyTeam()
		local me = ClientState.GetMe()
		local eliminated = me ~= nil and (me.State == "Eliminated" or me.Spectator == true)
		for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
			local otherRoot = heroRoot(model)
			if otherRoot and model:GetAttribute("Dead") ~= true then
				if model:GetAttribute("Team") == myTeam or (eliminated and ClientState.IsHeroVisible(model)) then
					return Vector3.new(otherRoot.Position.X, 0, otherRoot.Position.Z)
				end
			end
		end
		local teamState = ClientState.GetTeamState(myTeam)
		if teamState then
			return teamState.Position
		end
		return focus
	end
	-- Lobby / results: slow orbit around the arena center
	lobbyAngle += dt * 0.05
	return Vector3.new(math.sin(lobbyAngle) * 30, 0, math.cos(lobbyAngle) * 30)
end

local function update(dt)
	local camera = workspace.CurrentCamera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local wanted = getFocus(dt)
	if (wanted - focus).Magnitude > SNAP_DISTANCE then
		focus = wanted
	else
		focus = focus:Lerp(wanted, 1 - math.exp(-CAMERA.SMOOTHNESS * dt))
	end
	local desiredHeight = ClientState.InMatch() and targetHeight or 90
	height += (desiredHeight - height) * (1 - math.exp(-6 * dt))
	local back = height / math.tan(math.rad(CAMERA.ANGLE))
	camera.FieldOfView = CAMERA.FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, height, back), focus)
end

-- Public API
-- The camera distance is fixed on purpose (every player sees the same range), so zooming is
-- disabled. Kept as a no-op so existing callers (mobile pinch) need no changes.
function CameraController.Zoom(_delta) end

function CameraController.Init(clientState, combatController)
	ClientState = clientState
	CombatController = combatController
	RunService:BindToRenderStep("RuinfallCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
