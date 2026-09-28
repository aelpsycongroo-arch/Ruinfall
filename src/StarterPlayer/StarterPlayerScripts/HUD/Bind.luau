--[[
	HUD.Bind - looks up elements of the MainHUD layout by name.

	The layout (ReplicatedStorage.HUD.MainHUD) is meant to be edited or replaced by hand, so the
	HUD code never assumes an element exists: a missing or renamed element is reported ONCE in the
	output and replaced by an unparented stand-in, so the rest of the HUD keeps working.

		Bind.find(parent, "TeamPanel.TeamName", "TextLabel")
]]

local Bind = {}
local warned = {}

function Bind.find(parent, path, className)
	local node = parent
	local missing = nil -- first path segment that does not exist (one warning per missing piece)
	local walked = parent and parent.Parent and parent:GetFullName() or "MainHUD"
	for name in string.gmatch(path, "[^%.]+") do
		walked ..= "." .. name
		local child = node and node.Parent ~= nil and node:FindFirstChild(name) or nil
		if not child and not missing then
			missing = walked
		end
		node = child
	end
	if node then
		return node
	end
	local key = missing or walked
	if not warned[key] then
		warned[key] = true
		warn("[HUD] layout element not found (skipped): " .. key)
	end
	return Instance.new(className or "Frame")
end

-- Optional element (art-dependent extras such as a tintable banner): nil when absent, no warning
function Bind.optional(parent, path)
	local node = parent
	for name in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Finds a named group anywhere under parent (groups may be nested, e.g. BottomHUD.PlayerInfo)
function Bind.deep(parent, name, className)
	local node = parent and parent:FindFirstChild(name, true)
	if node then
		return node
	end
	return Bind.find(parent, name, className)
end

return Bind
