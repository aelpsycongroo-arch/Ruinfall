-- SettingsSchema: the player's game settings (hotkeys + interface), shared by the server
-- (GameSettingsServer validates and saves them) and the client (GameSettings applies them).
-- Audio volumes live in AudioService / AudioManager and are edited on the same menu.

local SettingsSchema = {}

-- rebindable actions, in menu order. Bind values are Enum.KeyCode names or a mouse button
-- ("MouseButton2" / "MouseButton3"). Movement (WASD), attack (left mouse) and Escape stay fixed.
SettingsSchema.Actions = {
	{ Key = "Ability", Label = "Class ability", Default = "Q" },
	{ Key = "ItemSpace", Label = "Active item (SPACE slot)", Default = "Space" },
	{ Key = "ItemE", Label = "Active item (E slot)", Default = "E" },
	{ Key = "ItemR", Label = "Active item (R slot)", Default = "R" },
	{ Key = "Boots", Label = "Boots skill", Default = "MouseButton2" },
	{ Key = "Potion", Label = "Drink potion", Default = "H" },
	{ Key = "Shop", Label = "Open shop", Default = "B" },
	{ Key = "Gear", Label = "Gear panel (Shattered Expanse)", Default = "I" },
	{ Key = "Scoreboard", Label = "Scoreboard (toggle)", Default = "Tab" },
}

SettingsSchema.Reserved = {
	W = true, A = true, S = true, D = true, Up = true, Down = true, Left = true, Right = true,
	Escape = true, Slash = true, Backquote = true, Unknown = true, MouseButton1 = true,
}

SettingsSchema.HUD_SCALE_MIN = 0.7
SettingsSchema.HUD_SCALE_MAX = 1.3

local MOUSE = { MouseButton2 = true, MouseButton3 = true }
local validKeys = nil
local function isValidBind(name)
	if type(name) ~= "string" or SettingsSchema.Reserved[name] then
		return false
	end
	if MOUSE[name] then
		return true
	end
	if not validKeys then
		validKeys = {}
		for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
			validKeys[item.Name] = true
		end
	end
	return validKeys[name] == true
end
SettingsSchema.IsValidBind = isValidBind

function SettingsSchema.Defaults()
	local binds = {}
	for _, action in ipairs(SettingsSchema.Actions) do
		binds[action.Key] = action.Default
	end
	return { Binds = binds, HudScale = 1 }
end

-- cleans untrusted data: unknown actions dropped, invalid / duplicate binds reset to defaults
function SettingsSchema.Sanitize(data)
	local clean = SettingsSchema.Defaults()
	if type(data) ~= "table" then
		return clean
	end
	local used = {}
	if type(data.Binds) == "table" then
		for _, action in ipairs(SettingsSchema.Actions) do
			local bind = data.Binds[action.Key]
			if isValidBind(bind) and not used[bind] then
				clean.Binds[action.Key] = bind
			end
			used[clean.Binds[action.Key]] = true
		end
	end
	if type(data.HudScale) == "number" and data.HudScale == data.HudScale then
		clean.HudScale = math.clamp(data.HudScale, SettingsSchema.HUD_SCALE_MIN, SettingsSchema.HUD_SCALE_MAX)
	end
	return clean
end

local SHORT = {
	MouseButton2 = "RMB", MouseButton3 = "MMB", Space = "SPACE", LeftShift = "SHIFT", RightShift = "RSHIFT",
	LeftControl = "CTRL", RightControl = "RCTRL", LeftAlt = "ALT", RightAlt = "RALT", CapsLock = "CAPS",
	Return = "ENTER", Backspace = "BKSP", One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
	Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0", Minus = "-", Equals = "=",
	LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".",
}
-- short label for a bind, e.g. "RMB", "SPACE", "F"
function SettingsSchema.Label(bind)
	if not bind then
		return "-"
	end
	return SHORT[bind] or string.upper(bind)
end

return SettingsSchema
