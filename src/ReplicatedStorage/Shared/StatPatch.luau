-- StatPatch: applies stat edits made with the Ruinfall Stats Editor plugin DURING a playtest to the
-- definition tables the running game already loaded. The plugin's playtest-server copy adds one
-- StringValue (JSON patch) per edit to ReplicatedStorage.RuinfallStatPatches; that folder
-- replicates, so the server (ServerScriptService.StatsHotSwap) and every client
-- (StarterPlayerScripts.StatsHotSwapClient) apply the same edits in order. In Edit mode the plugin
-- writes the numbers straight into ItemDefinitions / ClassDefinitions instead, so a published game
-- never has this folder and these scripts stay idle.
--
-- Patch = { Kind = "Item" | "Ability" | "Class", Key = "Bloodaxe", Path = { "Stats", "AttackDamage" },
--           Value = 20, Remove = false }

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatPatch = {}
StatPatch.FOLDER = "RuinfallStatPatches"

function StatPatch.Target(kind, key)
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	if kind == "Item" or kind == "Ability" then
		local defs = require(Shared:WaitForChild("ItemDefinitions"))
		local list = kind == "Item" and defs.Items or defs.Abilities
		return list and list[key]
	elseif kind == "Class" then
		local defs = require(Shared:WaitForChild("ClassDefinitions"))
		return defs.Classes and defs.Classes[key]
	end
	return nil
end

-- sets (or removes) root[path[1]][path[2]]...; creates missing sub-tables when setting
function StatPatch.ApplyTo(root, path, value, remove)
	if type(root) ~= "table" or type(path) ~= "table" or #path == 0 then
		return false
	end
	local node = root
	for index = 1, #path - 1 do
		local key = path[index]
		if type(node[key]) ~= "table" then
			if remove then
				return true
			end
			node[key] = {}
		end
		node = node[key]
	end
	if remove then
		node[path[#path]] = nil
	else
		node[path[#path]] = value
	end
	return true
end

function StatPatch.Decode(text)
	local ok, patch = pcall(HttpService.JSONDecode, HttpService, text)
	if ok and type(patch) == "table" and type(patch.Kind) == "string" and type(patch.Key) == "string" and type(patch.Path) == "table" then
		return patch
	end
	return nil
end

function StatPatch.Apply(patch)
	return StatPatch.ApplyTo(StatPatch.Target(patch.Kind, patch.Key), patch.Path, patch.Value, patch.Remove == true)
end

-- applies every patch already in the folder (in order) and every later one; callback(patch) after each
function StatPatch.Listen(callback)
	local seen = {}
	local function onPatch(child)
		if seen[child] or not child:IsA("StringValue") then
			return
		end
		seen[child] = true
		local patch = StatPatch.Decode(child.Value)
		if patch and StatPatch.Apply(patch) and callback then
			task.spawn(callback, patch)
		end
	end
	local function watch(folder)
		local children = folder:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, child in ipairs(children) do
			onPatch(child)
		end
		folder.ChildAdded:Connect(function(child)
			task.defer(onPatch, child)
		end)
	end
	local folder = ReplicatedStorage:FindFirstChild(StatPatch.FOLDER)
	if folder then
		watch(folder)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == StatPatch.FOLDER and child:IsA("Folder") then
			watch(child)
		end
	end)
end

return StatPatch
