-- AssetSwap: live image / texture id swaps made with the Ruinfall Asset Porter plugin during a
-- playtest. The plugin appends StringValues ("oldId|newId", named 1, 2, 3...) to
-- ReplicatedStorage.RuinfallAssetSwaps; the server (AssetHotSwap) and every client
-- (AssetHotSwapClient) patch their already-loaded config tables and the instances they own.
-- In Edit mode the plugin rewrites the scripts / instances directly, so this log only exists
-- inside a running playtest and a published game never has one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetSwap = {}
AssetSwap.LOG_NAME = "RuinfallAssetSwaps"
-- instance properties that hold image / texture content ids
AssetSwap.PROPERTIES = { "Image", "HoverImage", "PressedImage", "Texture", "TextureID", "TextureId" }

local function replaceWithPrefix(text, prefix, old, new)
	local needle = prefix .. old
	local parts, start = {}, 1
	while true do
		local a, b = string.find(text, needle, start, true)
		if not a then
			break
		end
		if string.match(string.sub(text, b + 1, b + 1), "%d") then
			table.insert(parts, string.sub(text, start, b)) -- a longer id that only starts the same
		else
			table.insert(parts, string.sub(text, start, a - 1) .. prefix .. new)
		end
		start = b + 1
	end
	table.insert(parts, string.sub(text, start))
	return table.concat(parts)
end

-- replaces asset id `old` with `new` (digit strings) in "rbxassetid://ID", "...?id=ID", "&id=ID"
function AssetSwap.ReplaceId(text, old, new)
	if type(text) ~= "string" or not string.find(text, old, 1, true) then
		return text
	end
	text = replaceWithPrefix(text, "rbxassetid://", old, new)
	return replaceWithPrefix(text, "id=", old, new)
end

function AssetSwap.PatchTable(root, old, new)
	local seen = {}
	local function walk(t)
		if seen[t] then
			return
		end
		seen[t] = true
		for key, value in pairs(t) do
			if type(value) == "string" then
				local replaced = AssetSwap.ReplaceId(value, old, new)
				if replaced ~= value then
					pcall(function()
						t[key] = replaced
					end)
				end
			elseif type(value) == "table" then
				walk(value)
			end
		end
	end
	if type(root) == "table" then
		walk(root)
	end
end

function AssetSwap.PatchInstance(instance, old, new)
	for _, property in ipairs(AssetSwap.PROPERTIES) do
		local ok, value = pcall(function()
			return instance[property]
		end)
		if ok and type(value) == "string" then
			local replaced = AssetSwap.ReplaceId(value, old, new)
			if replaced ~= value then
				pcall(function()
					instance[property] = replaced
				end)
			end
		end
	end
end

function AssetSwap.PatchInstances(root, old, new)
	AssetSwap.PatchInstance(root, old, new)
	for _, descendant in ipairs(root:GetDescendants()) do
		AssetSwap.PatchInstance(descendant, old, new)
	end
end

-- callback(oldId, newId) for every swap in the log, in order, now and as they arrive
function AssetSwap.Watch(callback)
	local done = {}
	local function handle(child)
		if done[child] or not child:IsA("StringValue") then
			return
		end
		local old, new = string.match(child.Value, "^(%d+)|(%d+)$")
		if old then
			done[child] = true
			task.spawn(callback, old, new)
		end
	end
	local function hook(folder)
		local children = folder:GetChildren()
		table.sort(children, function(a, b)
			return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
		end)
		for _, child in ipairs(children) do
			handle(child)
		end
		folder.ChildAdded:Connect(handle)
	end
	local folder = ReplicatedStorage:FindFirstChild(AssetSwap.LOG_NAME)
	if folder then
		hook(folder)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == AssetSwap.LOG_NAME then
			hook(child)
		end
	end)
end

return AssetSwap
