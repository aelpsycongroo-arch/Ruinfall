-- GameSettings (client): the player's hotkeys and HUD size. Loaded from / saved to the server
-- (GameSettingsServer, DataStore) so they follow the player between servers.
--   GameSettings.Matches(input, "Shop")  -> did this input press the Shop key?
--   GameSettings.ActionFor(input)         -> the action bound to this input (or nil)
--   GameSettings.Label("Ability")         -> short key text for the HUD, e.g. "Q" / "RMB"
--   GameSettings.SetBind / SetHudScale / Reset, and .Changed (BindableEvent) for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsSchema"))

local SAVE_DELAY = 1.2

local GameSettings = {}
GameSettings.Schema = SettingsSchema
GameSettings.Settings = SettingsSchema.Defaults()
GameSettings.Changed = Instance.new("BindableEvent")

local remote = nil
local saveToken = 0

local function inputName(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.MouseButton3 then
		return kind.Name
	end
	if kind == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name
	end
	return nil
end
GameSettings.InputName = inputName

function GameSettings.Bind(action)
	return GameSettings.Settings.Binds[action]
end

function GameSettings.Matches(input, action)
	local name = inputName(input)
	return name ~= nil and name == GameSettings.Settings.Binds[action]
end

function GameSettings.ActionFor(input)
	local name = inputName(input)
	if not name then
		return nil
	end
	for action, bind in pairs(GameSettings.Settings.Binds) do
		if bind == name then
			return action
		end
	end
	return nil
end

function GameSettings.Label(action)
	return SettingsSchema.Label(GameSettings.Settings.Binds[action])
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken and remote then
			remote:FireServer("Save", GameSettings.Settings)
		end
	end)
end

local function changed()
	GameSettings.Changed:Fire(GameSettings.Settings)
	scheduleSave()
end

-- binding a key already used by another action swaps the two
function GameSettings.SetBind(action, bind)
	if not SettingsSchema.IsValidBind(bind) then
		return false
	end
	local binds = GameSettings.Settings.Binds
	local previous = binds[action]
	for other, otherBind in pairs(binds) do
		if other ~= action and otherBind == bind then
			binds[other] = previous
		end
	end
	binds[action] = bind
	changed()
	return true
end

function GameSettings.SetHudScale(scale)
	GameSettings.Settings.HudScale = math.clamp(scale, SettingsSchema.HUD_SCALE_MIN, SettingsSchema.HUD_SCALE_MAX)
	changed()
end

function GameSettings.ResetBinds()
	GameSettings.Settings.Binds = SettingsSchema.Defaults().Binds
	changed()
end

task.spawn(function()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SettingsEvent", 30)
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(kind, payload)
		if kind == "Settings" then
			GameSettings.Settings = SettingsSchema.Sanitize(payload)
			GameSettings.Changed:Fire(GameSettings.Settings)
		end
	end)
	remote:FireServer("Load")
end)

return GameSettings
