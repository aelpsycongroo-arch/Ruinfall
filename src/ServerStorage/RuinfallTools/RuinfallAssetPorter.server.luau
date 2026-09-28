--[[
	RUINFALL ASSET PORTER  v1.0  -  Roblox Studio plugin (Plugins tab > Ruinfall > Asset Porter)

	Port assets and animations into RUINFALL and swap the ones the game uses.

	Tabs                                  stored in                               used by
	  Weapons     hero weapon meshes      ServerStorage.RuinfallWeapons           CharacterFactory
	  Animations  uploaded animations     ReplicatedStorage.RuinfallAnimations    Shared.AnimationLibrary
	  Props       map meshes              ServerStorage.RuinfallAssets            PropBuilder
	  Monsters    creature templates      ServerStorage.MonsterAssets             MonsterService / CreepService
	  Images      icons and HUD art ids   item / class / shop / HUD Theme scripts shop, HUD

	A new asset comes from
	  * an asset ID or a Creator Store / library URL (Model, Mesh, Image, Decal or Animation), or
	  * the Studio selection: e.g. an FBX you brought in with the 3D Importer, an Animation or
	    KeyframeSequence, an ImageLabel / ImageButton / Decal / Texture.

	Edit mode    swaps are saved into the place (Ctrl+Z or Revert undoes them) and the next
	             playtest spawns with them.
	Playtest     swaps appear in the running game right away (ServerScriptService.AssetHotSwap,
	             AssetHotSwapClient, CustomAnimationController) and are saved into the place when
	             the playtest stops.
]]

--------------------------------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------------------------------
local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local plugin = plugin
local IS_TEST = type(plugin) == "table" and plugin.__test == true

--------------------------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------------------------
local VERSION = "1.0"
local ANIMATION_FOLDER = "RuinfallAnimations"
local SWAP_LOG = "RuinfallAssetSwaps"
local BACKUP_FOLDER = "AssetPorterBackups"
local MAX_BACKUPS = 5

-- plugin settings shared by the Edit / Server / Client copies of this plugin
local KEY_PENDING = "RAP_PendingSaves" -- live swaps waiting to be saved into the place
local KEY_REQUESTS = "RAP_Requests" -- swaps asked for from the client / edit view during a playtest
local KEY_RESULTS = "RAP_Results"
local KEY_LIVE = "RAP_LiveHeartbeat" -- unix ms, written by the playtest server copy
local LIVE_TIMEOUT_MS = 6000

local KINDS = {
	{ Key = "Weapons", Type = "Mesh", Folder = "RuinfallWeapons",
		Hint = "Needs ONE MeshPart pointing along +Y like the old weapon. 'Match size' scales it to the old weapon's length and the hand grip offset (Grip attribute) is kept. Every hero of that class carries it." },
	{ Key = "Animations", Type = "Animation",
		Hint = "Animation asset ID (published from the Animation Editor / Moon / Blender and owned by you or the game's group), or select an Animation or KeyframeSequence (a KeyframeSequence gets a temporary Studio-only id). Clear = back to the built-in animation." },
	{ Key = "Props", Type = "Mesh", Folder = "RuinfallAssets",
		Hint = "Needs ONE MeshPart. 'Match size' keeps the old footprint so the map layout stays the same. Every placed copy on the map is replaced." },
	{ Key = "Monsters", Type = "Model", Folder = "MonsterAssets",
		Hint = "A Model. Humanoids and scripts are removed (the game adds its own) and loose parts are welded to the root. The procedural walk / attack only drives the original rig: for a new rig, upload Monster_* / Minion_* animations in the Animations tab." },
	{ Key = "Images", Type = "Image",
		Hint = "Image or Decal asset ID (a decal is converted to its image), or select an ImageLabel / ImageButton / Decal / Texture. Every script and GUI that uses the old image is updated." },
}
local KIND_BY_KEY = {}
for _, kind in ipairs(KINDS) do
	KIND_BY_KEY[kind.Key] = kind
end

local WEAPON_LABELS = {
	W_Sword = "Fighter - sword",
	W_Dagger = "Assassin - daggers (both hands)",
	W_Staff = "Mage - staff",
	W_StaffCrystal = "Mage - staff crystal (glows in class colour)",
	W_Bow = "Marksman - bow",
	W_Quiver = "Marksman - quiver (back)",
	W_Shield = "Tank - shield",
	W_ShieldCrest = "Tank - shield crest (class tint)",
	W_Mace = "Tank - mace",
}
local MONSTER_LABELS = {
	StoneWarden = "Jungle monster - Stone Warden",
	GoblinMinion = "Lane minion - Goblin",
}
local MONSTER_PREFIX = { StoneWarden = "Monster", GoblinMinion = "Minion" }

-- scripts whose image ids are listed in the Images tab: { path, group }
local IMAGE_SOURCES = {
	{ { "ReplicatedStorage", "Shared", "ItemDefinitions" }, "Item icons" },
	{ { "ReplicatedStorage", "Shared", "ClassDefinitions" }, "Class emblems" },
	{ { "ReplicatedStorage", "Shared", "ShopDefinitions" }, "Shop icons" },
	{ { "StarterPlayer", "StarterPlayerScripts", "HUD", "Theme" }, "HUD art" },
}
-- where an image swap made in Edit mode rewrites scripts and instances
local EDIT_ROOTS = { "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer", "StarterPack", "ServerScriptService", "ServerStorage", "Lighting" }
local SKIP_FOLDERS = { ScriptBackups = true, [BACKUP_FOLDER] = true, RuinfallOldDraft = true }
local IMAGE_PROPERTIES = { "Image", "HoverImage", "PressedImage", "Texture", "TextureID", "TextureId" }

--------------------------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------------------------
local function role()
	if not RunService:IsRunning() then
		return "Edit"
	end
	return RunService:IsServer() and "Server" or "Client"
end

local function nowMs()
	return DateTime.now().UnixTimestampMillis
end

local function getSetting(key)
	local ok, value = pcall(function()
		return plugin:GetSetting(key)
	end)
	return ok and value or nil
end

local function setSetting(key, value)
	pcall(function()
		plugin:SetSetting(key, value)
	end)
end

local function liveSessionActive()
	local beat = getSetting(KEY_LIVE)
	return type(beat) == "number" and nowMs() - beat < LIVE_TIMEOUT_MS
end

-- "123", "rbxassetid://123", ".../asset/?id=123", "https://create.roblox.com/store/asset/123/Name"
local function parseAssetId(text)
	if type(text) ~= "string" then
		return nil
	end
	text = string.gsub(text, "%s", "")
	if text == "" then
		return nil
	end
	return string.match(text, "id=(%d+)") or string.match(text, "rbxassetid://(%d+)") or string.match(text, "(%d%d%d%d+)")
end

local function replaceWithPrefix(text, prefix, old, new)
	local needle = prefix .. old
	local parts, start = {}, 1
	while true do
		local a, b = string.find(text, needle, start, true)
		if not a then
			break
		end
		if string.match(string.sub(text, b + 1, b + 1), "%d") then
			table.insert(parts, string.sub(text, start, b))
		else
			table.insert(parts, string.sub(text, start, a - 1) .. prefix .. new)
		end
		start = b + 1
	end
	table.insert(parts, string.sub(text, start))
	return table.concat(parts)
end

-- swap asset id `old` for `new` (digit strings) in rbxassetid:// and ?id= / &id= references
local function replaceId(text, old, new)
	if type(text) ~= "string" or not string.find(text, old, 1, true) then
		return text
	end
	return replaceWithPrefix(replaceWithPrefix(text, "rbxassetid://", old, new), "id=", old, new)
end

local function pathOf(instance)
	local names = {}
	local current = instance
	while current and current ~= game do
		if current.Parent == game then
			table.insert(names, 1, current.ClassName)
		else
			table.insert(names, 1, current.Name)
		end
		current = current.Parent
	end
	return current == game and names or nil
end

local function resolvePath(path)
	if type(path) ~= "table" or #path == 0 then
		return nil
	end
	local ok, current = pcall(function()
		return game:GetService(path[1])
	end)
	if not ok or not current then
		return nil
	end
	for index = 2, #path do
		current = current:FindFirstChild(path[index])
		if not current then
			return nil
		end
	end
	return current
end

local function pathText(path)
	return type(path) == "table" and table.concat(path, ".") or "?"
end

-- like pathOf, but each name carries its index among same-named siblings ("Icon#3"), so an
-- instance can be found again exactly (used to undo image swaps precisely)
local function indexedPathOf(instance)
	local names = {}
	local current = instance
	while current and current ~= game do
		local parent = current.Parent
		if parent == game then
			table.insert(names, 1, current.ClassName)
		else
			local index = 0
			for _, sibling in ipairs(parent and parent:GetChildren() or {}) do
				if sibling.Name == current.Name then
					index += 1
					if sibling == current then
						break
					end
				end
			end
			table.insert(names, 1, current.Name .. "#" .. index)
		end
		current = parent
	end
	return current == game and names or nil
end

local function resolveIndexedPath(path)
	if type(path) ~= "table" or #path == 0 then
		return nil
	end
	local ok, current = pcall(function()
		return game:GetService(path[1])
	end)
	if not ok or not current then
		return nil
	end
	for index = 2, #path do
		local name, wanted = string.match(path[index], "^(.*)#(%d+)$")
		wanted = tonumber(wanted) or 1
		local found, seen = nil, 0
		for _, child in ipairs(current:GetChildren()) do
			if child.Name == (name or path[index]) then
				seen += 1
				if seen == wanted then
					found = child
					break
				end
			end
		end
		if not found then
			return nil
		end
		current = found
	end
	return current
end

local function isSkipped(instance)
	local current = instance
	while current and current ~= game do
		if current.Parent == ServerStorage and SKIP_FOLDERS[current.Name] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function getLibrary(kind, create)
	local folder = ServerStorage:FindFirstChild(kind.Folder)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = kind.Folder
		folder.Parent = ServerStorage
	end
	return folder
end

local function getAnimationFolder(create)
	local folder = ReplicatedStorage:FindFirstChild(ANIMATION_FOLDER)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = ANIMATION_FOLDER
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function humanize(name)
	return (string.gsub(name, "_", " "))
end

--------------------------------------------------------------------------------------------------
-- Backups (Edit mode): ServerStorage.AssetPorterBackups.<Kind>.<Slot>
--------------------------------------------------------------------------------------------------
local function backupSlotFolder(kindKey, slot, create)
	local root = ServerStorage:FindFirstChild(BACKUP_FOLDER)
	if not root then
		if not create then
			return nil
		end
		root = Instance.new("Folder")
		root.Name = BACKUP_FOLDER
		root.Parent = ServerStorage
	end
	local kindFolder = root:FindFirstChild(kindKey)
	if not kindFolder then
		if not create then
			return nil
		end
		kindFolder = Instance.new("Folder")
		kindFolder.Name = kindKey
		kindFolder.Parent = root
	end
	local slotFolder = kindFolder:FindFirstChild(slot)
	if not slotFolder and create then
		slotFolder = Instance.new("Folder")
		slotFolder.Name = slot
		slotFolder.Parent = kindFolder
	end
	return slotFolder
end

local function sortedBackups(folder)
	local list = folder and folder:GetChildren() or {}
	table.sort(list, function(a, b)
		return (a:GetAttribute("SwappedAt") or 0) > (b:GetAttribute("SwappedAt") or 0)
	end)
	return list
end

local function trimBackups(folder)
	for index, child in ipairs(sortedBackups(folder)) do
		if index > MAX_BACKUPS then
			child:Destroy()
		end
	end
end

local function backupInstance(kindKey, slot, instance)
	local folder = backupSlotFolder(kindKey, slot, true)
	instance:SetAttribute("SwappedAt", nowMs())
	instance.Parent = folder
	trimBackups(folder)
end

local function backupValue(kindKey, slot, value)
	local folder = backupSlotFolder(kindKey, slot, true)
	local entry = Instance.new("StringValue")
	entry.Name = "Previous"
	entry.Value = value
	entry:SetAttribute("SwappedAt", nowMs())
	entry.Parent = folder
	trimBackups(folder)
end

local function backupCount(kindKey, slot)
	local folder = backupSlotFolder(kindKey, slot, false)
	return folder and #folder:GetChildren() or 0
end

--------------------------------------------------------------------------------------------------
-- Loading a source
--------------------------------------------------------------------------------------------------
local function loadAssetById(id, wantPart)
	local uri = "rbxassetid://" .. id
	-- models / packages / anything saved as an instance tree
	local ok, objects = pcall(function()
		return game:GetObjects(uri)
	end)
	if ok and type(objects) == "table" and #objects > 0 then
		if #objects == 1 then
			return objects[1]
		end
		local model = Instance.new("Model")
		model.Name = "Asset_" .. id
		for _, object in ipairs(objects) do
			object.Parent = model
		end
		return model
	end
	-- mesh assets (uploaded .fbx / .obj meshes)
	if wantPart then
		local okContent, part = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(uri))
		end)
		if okContent and part then
			return part
		end
		local okInsert, meshPart = pcall(function()
			return InsertService:CreateMeshPartAsync(uri, Enum.CollisionFidelity.Default, Enum.RenderFidelity.Automatic)
		end)
		if okInsert and meshPart then
			return meshPart
		end
	end
	-- group / owned assets through InsertService
	local okLoad, container = pcall(function()
		return InsertService:LoadAsset(tonumber(id))
	end)
	if okLoad and container then
		local children = container:GetChildren()
		if #children == 1 then
			return children[1]
		end
		return container
	end
	return nil, "Could not load asset " .. id .. " - check the ID and that it is a Model or Mesh you own (or that is public)."
end

-- a Creator Store "Decal" id is not the image id itself: open the decal to find its image
local function imageValueFromId(id)
	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if ok and type(objects) == "table" and objects[1] then
		local object = objects[1]
		local decal = object:IsA("Decal") and object or object:FindFirstChildWhichIsA("Decal", true)
		local imageId = decal and string.match(decal.Texture, "%d+")
		if imageId then
			return "rbxassetid://" .. imageId, string.format(" (decal %s -> image %s)", id, imageId)
		end
	end
	return "rbxassetid://" .. id, ""
end

-- turns a source spec into an Instance (mesh / model kinds) or a content string
local function resolveSource(kind, source)
	if type(source) ~= "table" then
		return nil, "No source - enter an asset ID or use the selection"
	end
	if kind.Type == "Mesh" or kind.Type == "Model" then
		if source.Type == "Id" then
			return loadAssetById(source.Id, kind.Type == "Mesh")
		elseif source.Type == "Path" then
			local instance = resolvePath(source.Path)
			if not instance then
				return nil, "Could not find " .. pathText(source.Path) .. " (it may only have existed during the playtest)"
			end
			return instance
		end
	elseif kind.Type == "Animation" then
		if source.Type == "Id" then
			return "rbxassetid://" .. source.Id
		elseif source.Type == "Value" then
			return source.Value
		elseif source.Type == "Clear" then
			return ""
		end
	elseif kind.Type == "Image" then
		if source.Type == "Id" then
			local value, note = imageValueFromId(source.Id)
			return value, nil, note
		elseif source.Type == "Value" then
			return source.Value
		end
	end
	return nil, "That source does not fit the " .. kind.Key .. " tab"
end

-- Selection -> source spec for this tab (or nil, reason)
local function sourceFromSelection(kind)
	local selected = Selection:Get()[1]
	if not selected then
		return nil, "Select something in the Explorer first"
	end
	if kind.Type == "Mesh" then
		if selected:IsA("BasePart") or selected:IsA("Model") or selected:IsA("Folder") then
			return { Type = "Path", Path = pathOf(selected) }, selected:GetFullName()
		end
		return nil, "Select a MeshPart (or a Model holding one)"
	elseif kind.Type == "Model" then
		if selected:IsA("Model") or selected:IsA("BasePart") then
			return { Type = "Path", Path = pathOf(selected) }, selected:GetFullName()
		end
		return nil, "Select a Model"
	elseif kind.Type == "Animation" then
		if selected:IsA("Animation") and selected.AnimationId ~= "" then
			return { Type = "Value", Value = selected.AnimationId }, selected.AnimationId
		elseif selected:IsA("KeyframeSequence") then
			local ok, id = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(selected)
			end)
			if ok and id then
				return { Type = "Value", Value = id }, id .. "  (temporary: works in Studio only - publish it for a permanent id)"
			end
			return nil, "Could not register that KeyframeSequence: " .. tostring(id)
		end
		return nil, "Select an Animation (with an AnimationId) or a KeyframeSequence"
	elseif kind.Type == "Image" then
		for _, property in ipairs({ "Image", "Texture", "TextureID" }) do
			local ok, value = pcall(function()
				return selected[property]
			end)
			if ok and type(value) == "string" and value ~= "" then
				return { Type = "Value", Value = value }, value
			end
		end
		return nil, "Select an ImageLabel, ImageButton, Decal, Texture or textured MeshPart"
	end
	return nil, "Nothing to use"
end

--------------------------------------------------------------------------------------------------
-- Applying swaps
--------------------------------------------------------------------------------------------------
local function toSinglePart(instance)
	if instance:IsA("BasePart") then
		local clone = instance:Clone()
		if not clone then
			return nil, "'" .. instance.Name .. "' cannot be copied (Archivable is off)"
		end
		return clone
	end
	local parts = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 1 then
		local clone = parts[1]:Clone()
		if not clone then
			return nil, "'" .. parts[1].Name .. "' cannot be copied (Archivable is off)"
		end
		return clone
	elseif #parts == 0 then
		return nil, "'" .. instance.Name .. "' has no mesh in it"
	end
	return nil, string.format("'%s' has %d parts - this slot needs ONE MeshPart. Join the meshes in Blender (Ctrl+J) before exporting, or select just the part you want.", instance.Name, #parts)
end

local function cleanPart(part)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") or descendant:IsA("Constraint")
			or descendant:IsA("BaseScript") or descendant:IsA("BasePart") then
			descendant:Destroy()
		end
	end
end

local function applyMesh(kind, slot, sourceInstance, options, live, isNew)
	local folder = getLibrary(kind, true)
	local old = folder:FindFirstChild(slot)
	if isNew and old then
		return false, "There is already an entry called '" .. slot .. "'"
	elseif not isNew and not old then
		return false, "'" .. slot .. "' is not in ServerStorage." .. kind.Folder
	end
	local part, reason = toSinglePart(sourceInstance)
	if not part then
		return false, reason
	end
	cleanPart(part)
	part.Name = slot
	local notes = {}
	if old and old:IsA("BasePart") then
		for key, value in pairs(old:GetAttributes()) do
			if key ~= "SwappedAt" and part:GetAttribute(key) == nil then
				part:SetAttribute(key, value)
			end
		end
		part.Anchored = old.Anchored
		part.CanCollide = old.CanCollide
		part.CanQuery = old.CanQuery
		part.CanTouch = old.CanTouch
		part.CastShadow = old.CastShadow
		part.Massless = old.Massless
		if options.MatchSize ~= false then
			local oldMax = math.max(old.Size.X, old.Size.Y, old.Size.Z)
			local newMax = math.max(part.Size.X, part.Size.Y, part.Size.Z)
			if newMax > 0 then
				part.Size = part.Size * (oldMax / newMax)
				table.insert(notes, "scaled to the old size")
			end
		end
		if kind.Key == "Weapons" and old:GetAttribute("Grip") ~= nil then
			table.insert(notes, "grip offset kept")
		end
	else
		part.Anchored = kind.Key == "Props"
		part.CanCollide = false
	end
	if type(options.Texture) == "string" and options.Texture ~= "" then
		if part:IsA("MeshPart") then
			part.TextureID = options.Texture
			table.insert(notes, "texture set")
		end
	end
	if old then
		if live then
			old:Destroy()
		else
			backupInstance(kind.Key, slot, old)
		end
	end
	part.Parent = folder
	local where = kind.Key == "Weapons" and "every hero of that class" or "every placed copy"
	local message
	if isNew then
		message = string.format("Added '%s' to %s", slot, kind.Folder)
	elseif live then
		message = string.format("Swapped '%s' - %s updates now", slot, where)
	else
		message = string.format("Swapped '%s' - saved; the next playtest uses it", slot)
	end
	if #notes > 0 then
		message ..= " (" .. table.concat(notes, ", ") .. ")"
	end
	return true, message
end

local function prepareCreature(model, oldTemplate, matchSize)
	local notes = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Humanoid") or descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		return false, "The model has no parts"
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = model.PrimaryPart
	end
	if not root then
		local boxCFrame, boxSize = model:GetBoundingBox()
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(math.max(1, boxSize.X * 0.5), math.max(1, boxSize.Y * 0.5), math.max(1, boxSize.Z * 0.5))
		root.CFrame = boxCFrame
		root.Transparency = 1
		root.CanCollide = false
		root.Parent = model
		table.insert(parts, root)
		table.insert(notes, "added an invisible HumanoidRootPart")
	end
	model.PrimaryPart = root
	-- weld every part that is not already joined to the root (imports are loose, anchored parts)
	local links = {}
	local function link(a, b)
		if a and b then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			link(descendant.Part0, descendant.Part1)
		end
	end
	local connected = { [root] = true }
	local queue = { root }
	while #queue > 0 do
		local current = table.remove(queue)
		for _, other in ipairs(links[current] or {}) do
			if not connected[other] then
				connected[other] = true
				table.insert(queue, other)
			end
		end
	end
	local welded = 0
	for _, part in ipairs(parts) do
		part.Anchored = false
		if part ~= root then
			part.CanCollide = false
			part.Massless = true
			if not connected[part] then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
				welded += 1
			end
		end
	end
	if welded > 0 then
		table.insert(notes, welded .. " part(s) welded to the root")
	end
	if oldTemplate then
		for key, value in pairs(oldTemplate:GetAttributes()) do
			if key ~= "SwappedAt" and model:GetAttribute(key) == nil then
				model:SetAttribute(key, value)
			end
		end
		if matchSize ~= false then
			local ok = pcall(function()
				local _, oldSize = oldTemplate:GetBoundingBox()
				local _, newSize = model:GetBoundingBox()
				if newSize.Y > 0 then
					model:ScaleTo(model:GetScale() * oldSize.Y / newSize.Y)
				end
			end)
			if ok then
				table.insert(notes, "scaled to the old height")
			end
		end
		local oldTorso = oldTemplate:FindFirstChild("Torso")
		local oldProcedural = (oldTorso and oldTorso:FindFirstChild("RootJoint")) or oldTemplate:FindFirstChild("Hips", true)
		if oldProcedural and not model:FindFirstChild(oldProcedural.Parent.Name) then
			table.insert(notes, "new rig: set " .. (MONSTER_PREFIX[oldTemplate.Name] or "Monster") .. "_* animations or it will not animate")
		end
	end
	return true, notes
end

local function applyModel(kind, slot, sourceInstance, options, live, isNew)
	local folder = getLibrary(kind, true)
	local old = folder:FindFirstChild(slot)
	if isNew and old then
		return false, "There is already an entry called '" .. slot .. "'"
	elseif not isNew and not old then
		return false, "'" .. slot .. "' is not in ServerStorage." .. kind.Folder
	end
	local model
	if sourceInstance:IsA("Model") then
		model = sourceInstance:Clone()
	elseif sourceInstance:IsA("BasePart") then
		model = Instance.new("Model")
		sourceInstance:Clone().Parent = model
	else
		return false, "Pick a Model"
	end
	if not model then
		return false, "That model cannot be copied (Archivable is off)"
	end
	model.Name = slot
	local ok, notes = prepareCreature(model, old, options.MatchSize)
	if not ok then
		return false, notes
	end
	if old then
		if live then
			old:Destroy()
		else
			backupInstance(kind.Key, slot, old)
		end
	end
	model.Parent = folder
	local message
	if isNew then
		message = string.format("Added '%s' to %s", slot, kind.Folder)
	else
		message = string.format("Swapped '%s' - %s", slot, live and "the next spawn uses it" or "saved; the next playtest uses it")
	end
	if #notes > 0 then
		message ..= " (" .. table.concat(notes, ", ") .. ")"
	end
	return true, message
end

local function applyAnimation(slot, value, live)
	local folder = getAnimationFolder(true)
	local animation = folder:FindFirstChild(slot)
	if animation and not animation:IsA("Animation") then
		return false, "'" .. slot .. "' in " .. ANIMATION_FOLDER .. " is not an Animation"
	end
	if not animation then
		animation = Instance.new("Animation")
		animation.Name = slot
		animation.Parent = folder
	end
	local old = animation.AnimationId
	if old == value then
		return true, "No change - " .. slot .. " already uses that animation"
	end
	if not live then
		backupValue("Animations", slot, old)
	end
	animation.AnimationId = value
	if value == "" then
		return true, slot .. " is back to the built-in animation" .. (live and " (live now)" or "")
	end
	local note = ""
	if string.find(value, "rbxassetid://", 1, true) then
		local ok = pcall(function()
			KeyframeSequenceProvider:GetKeyframeSequenceAsync(value)
		end)
		if not ok then
			note = " - warning: could not load it here; make sure the animation is owned by you / the game's group"
		end
	end
	return true, string.format("%s now plays %s%s%s", slot, value, live and " (live now)" or " (saved)", note)
end

local function writeSource(script, source)
	local wrote = pcall(function()
		ScriptEditorService:UpdateSourceAsync(script, function()
			return source
		end)
	end)
	if not wrote then
		script.Source = source
	end
end

-- rewrites every script line / image property that uses oldId; returns the exact changes so
-- a revert touches only these (other places that already used newId stay as they were)
local function applyImageEdit(oldId, newId)
	local scripts, instances = 0, 0
	local changes = { Scripts = {}, Instances = {} }
	for _, serviceName in ipairs(EDIT_ROOTS) do
		local ok, service = pcall(function()
			return game:GetService(serviceName)
		end)
		if ok and service then
			for _, descendant in ipairs(service:GetDescendants()) do
				if not isSkipped(descendant) then
					if descendant:IsA("LuaSourceContainer") then
						local source = descendant.Source
						if string.find(source, oldId, 1, true) then
							local lines = string.split(source, "\n")
							local changed = {}
							for index, line in ipairs(lines) do
								local updated = replaceId(line, oldId, newId)
								if updated ~= line then
									table.insert(changed, { Before = line, After = updated })
									lines[index] = updated
								end
							end
							if #changed > 0 then
								writeSource(descendant, table.concat(lines, "\n"))
								table.insert(changes.Scripts, { Path = indexedPathOf(descendant), Lines = changed })
								scripts += 1
							end
						end
					else
						for _, property in ipairs(IMAGE_PROPERTIES) do
							local okRead, value = pcall(function()
								return descendant[property]
							end)
							if okRead and type(value) == "string" then
								local updated = replaceId(value, oldId, newId)
								if updated ~= value and pcall(function()
									descendant[property] = updated
								end) then
									table.insert(changes.Instances, { Path = indexedPathOf(descendant), Property = property, Before = value, After = updated })
									instances += 1
								end
							end
						end
					end
				end
			end
		end
	end
	return scripts, instances, changes
end

-- undoes exactly the changes recorded by applyImageEdit
local function revertImageChanges(changes)
	local scripts, instances = 0, 0
	for _, record in ipairs(changes.Scripts or {}) do
		local script = resolveIndexedPath(record.Path)
		if script and script:IsA("LuaSourceContainer") then
			local lines = string.split(script.Source, "\n")
			local used, changed = {}, false
			for _, change in ipairs(record.Lines or {}) do
				for index, line in ipairs(lines) do
					if not used[index] and line == change.After then
						lines[index] = change.Before
						used[index] = true
						changed = true
						break
					end
				end
			end
			if changed then
				writeSource(script, table.concat(lines, "\n"))
				scripts += 1
			end
		end
	end
	for _, record in ipairs(changes.Instances or {}) do
		local instance = resolveIndexedPath(record.Path)
		if instance then
			local ok, value = pcall(function()
				return instance[record.Property]
			end)
			if ok and value == record.After and pcall(function()
				instance[record.Property] = record.Before
			end) then
				instances += 1
			end
		end
	end
	return scripts, instances
end

local function applyImage(oldId, value, live, note)
	local newId = string.match(value or "", "%d+")
	if not newId then
		return false, "That image is not an asset id (rbxassetid://...)"
	end
	if newId == oldId then
		return true, "No change - it already uses that image"
	end
	if live then
		local log = ReplicatedStorage:FindFirstChild(SWAP_LOG)
		if not log then
			log = Instance.new("Folder")
			log.Name = SWAP_LOG
			log.Parent = ReplicatedStorage
		end
		local entry = Instance.new("StringValue")
		entry.Name = tostring(#log:GetChildren() + 1)
		entry.Value = oldId .. "|" .. newId
		entry.Parent = log
		return true, string.format("Image %s -> %s is live now%s", oldId, newId, note or "")
	end
	local scripts, instances, changes = applyImageEdit(oldId, newId)
	backupValue("Images", newId, HttpService:JSONEncode({ Old = oldId, Changes = changes }))
	return true, string.format("Image %s -> %s%s: %d script(s) and %d GUI / texture(s) updated", oldId, newId, note or "", scripts, instances)
end

local function revertLocal(kind, slot)
	local folder = backupSlotFolder(kind.Key, slot, false)
	local latest = sortedBackups(folder)[1]
	if not latest then
		return false, "Nothing to revert for " .. slot
	end
	if kind.Type == "Mesh" or kind.Type == "Model" then
		local library = getLibrary(kind, true)
		local current = library:FindFirstChild(slot)
		if current then
			current:Destroy()
		end
		latest:SetAttribute("SwappedAt", nil)
		latest.Name = slot
		latest.Parent = library
		return true, "Reverted '" .. slot .. "' to the previous version"
	elseif kind.Type == "Animation" then
		local animation = getAnimationFolder(true):FindFirstChild(slot)
		if animation and animation:IsA("Animation") then
			animation.AnimationId = latest.Value
		end
		latest:Destroy()
		return true, "Reverted " .. slot .. (latest.Value == "" and " to the built-in animation" or (" to " .. latest.Value))
	elseif kind.Type == "Image" then
		local previous, changes = latest.Value, nil
		local okJson, decoded = pcall(function()
			return HttpService:JSONDecode(latest.Value)
		end)
		if okJson and type(decoded) == "table" and decoded.Old then
			previous, changes = tostring(decoded.Old), decoded.Changes
		end
		latest:Destroy()
		local scripts, instances
		if type(changes) == "table" then
			scripts, instances = revertImageChanges(changes)
		else
			scripts, instances = applyImageEdit(slot, previous)
		end
		return true, string.format("Reverted image %s -> %s: %d script(s), %d GUI / texture(s)", slot, previous, scripts, instances)
	end
	return false, "Cannot revert this"
end

-- one swap in THIS datamodel (live = inside a running playtest)
local function applyLocal(action, kindKey, slot, source, options, live)
	local kind = KIND_BY_KEY[kindKey]
	if not kind then
		return false, "Unknown tab " .. tostring(kindKey)
	end
	options = options or {}
	if action == "Revert" then
		return revertLocal(kind, slot)
	end
	local value, reason, note = resolveSource(kind, action == "Clear" and { Type = "Clear" } or source)
	if value == nil then
		return false, reason
	end
	if kind.Type == "Mesh" then
		return applyMesh(kind, slot, value, options, live, action == "Add")
	elseif kind.Type == "Model" then
		return applyModel(kind, slot, value, options, live, action == "Add")
	elseif kind.Type == "Animation" then
		return applyAnimation(slot, value, live)
	elseif kind.Type == "Image" then
		return applyImage(slot, value, live, note)
	end
	return false, "Unsupported"
end

local function recorded(name, fn)
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording(name)
	end)
	local ok, a, b = pcall(fn)
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, (ok and a ~= false) and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
		end)
	end
	if not ok then
		return false, "Error: " .. tostring(a)
	end
	return a, b
end

--------------------------------------------------------------------------------------------------
-- Core: routes a swap to the right datamodel
--------------------------------------------------------------------------------------------------
local Core = {}
local onPendingSaved = nil -- UI callback(count, failures)

local function queuePending(action, kindKey, slot, source, options)
	local pending = getSetting(KEY_PENDING)
	if type(pending) ~= "table" then
		pending = {}
	end
	table.insert(pending, { Action = action, Kind = kindKey, Slot = slot, Source = source, Options = options, At = nowMs() })
	setSetting(KEY_PENDING, pending)
end

local function forward(action, kindKey, slot, source, options)
	local id = HttpService:GenerateGUID(false)
	local requests = getSetting(KEY_REQUESTS)
	if type(requests) ~= "table" then
		requests = {}
	end
	table.insert(requests, { Id = id, Action = action, Kind = kindKey, Slot = slot, Source = source, Options = options })
	setSetting(KEY_REQUESTS, requests)
	local deadline = os.clock() + 12
	while os.clock() < deadline do
		task.wait(0.25)
		local results = getSetting(KEY_RESULTS)
		local result = type(results) == "table" and results[id]
		if result then
			results[id] = nil
			setSetting(KEY_RESULTS, results)
			return result.Ok == true, tostring(result.Message)
		end
	end
	return false, "The playtest server did not answer. Switch Studio's view to Server (Test tab > Client/Server) and swap there."
end

function Core.Execute(action, kindKey, slot, source, options)
	options = options or {}
	local current = role()
	if current == "Client" or (current == "Edit" and liveSessionActive()) then
		if action == "Revert" then
			return false, "Revert works in Edit mode - stop the playtest first"
		end
		if not liveSessionActive() then
			return false, "Live swaps run on the server: switch Studio's view to Server (Test tab > Client/Server) and use Asset Porter there."
		end
		return forward(action, kindKey, slot, source, options)
	end
	local live = current == "Server"
	if live then
		if action == "Revert" then
			return false, "Revert works in Edit mode - stop the playtest first"
		end
		local ok, message = applyLocal(action, kindKey, slot, source, options, true)
		if ok and not string.find(message, "No change", 1, true) then
			queuePending(action, kindKey, slot, source, options)
			message ..= " - saved to the place when you stop"
		end
		return ok, message
	end
	return recorded("Asset Porter: " .. action .. " " .. tostring(slot), function()
		return applyLocal(action, kindKey, slot, source, options, false)
	end)
end

-- Edit copy: saves swaps made during the playtest once it is over
local savingPending = false
local function savePendingSwaps()
	if savingPending or role() ~= "Edit" or liveSessionActive() then
		return
	end
	local pending = getSetting(KEY_PENDING)
	if type(pending) ~= "table" or #pending == 0 then
		return
	end
	savingPending = true
	setSetting(KEY_PENDING, {})
	local saved, failures = 0, {}
	recorded("Asset Porter: save playtest swaps", function()
		for _, entry in ipairs(pending) do
			local ok, message = applyLocal(entry.Action, entry.Kind, entry.Slot, entry.Source, entry.Options, false)
			if ok then
				saved += 1
			else
				table.insert(failures, tostring(entry.Slot) .. ": " .. tostring(message))
			end
		end
		return true
	end)
	savingPending = false
	if onPendingSaved then
		onPendingSaved(saved, failures)
	end
end

-- Server copy: answers swaps requested from the client / edit view, and signals it is alive
local function serveRequests()
	local requests = getSetting(KEY_REQUESTS)
	if type(requests) ~= "table" or #requests == 0 then
		return
	end
	setSetting(KEY_REQUESTS, {})
	for _, request in ipairs(requests) do
		local ok, message = Core.Execute(request.Action, request.Kind, request.Slot, request.Source, request.Options)
		local results = getSetting(KEY_RESULTS)
		if type(results) ~= "table" then
			results = {}
		end
		results[request.Id] = { Ok = ok, Message = message }
		setSetting(KEY_RESULTS, results)
	end
end

--------------------------------------------------------------------------------------------------
-- Catalog (what each tab lists)
--------------------------------------------------------------------------------------------------
local function meshSub(part)
	local mesh = part:IsA("MeshPart") and string.match(part.MeshId, "%d+")
	local size = part.Size
	return string.format("%s  -  %.1f x %.1f x %.1f", mesh and ("mesh " .. mesh) or part.ClassName, size.X, size.Y, size.Z)
end

local function imageLabel(lines, index, column)
	local before = string.sub(lines[index], 1, column - 1)
	local key = string.match(before, "([%a_][%w_]*)%s*=%s*[\"']?$")
	local owner = string.match(before, "Id%s*=%s*\"([%w_]+)\"") or string.match(before, "Key%s*=%s*\"([%w_]+)\"")
	if not owner then
		for j = index - 1, math.max(1, index - 15), -1 do
			local line = lines[j]
			owner = string.match(line, "Id%s*=%s*\"([%w_]+)\"") or string.match(line, "Key%s*=%s*\"([%w_]+)\"")
			if owner then
				break
			end
			local opener = string.match(line, "^%s*([%a_][%w_]*)%s*=%s*{%s*$") or string.match(line, "^%s*local%s+([%a_][%w_]*)%s*=%s*{%s*$")
			if opener then
				owner = opener
				break
			end
			if string.match(line, "^%s*}") then
				break
			end
		end
	end
	if owner and string.upper(owner) == owner then
		owner = nil -- a CONSTANT_TABLE, the key is the useful part
	end
	if owner and key and owner ~= key then
		return owner .. " - " .. key
	end
	return key or owner or ("line " .. index)
end

local function imageCatalog()
	local entries, byId = {}, {}
	for _, spec in ipairs(IMAGE_SOURCES) do
		local script = resolvePath(spec[1])
		if script and script:IsA("LuaSourceContainer") then
			local lines = string.split(script.Source, "\n")
			for index, line in ipairs(lines) do
				local start = 1
				while true do
					local a, b, id = string.find(line, "rbxassetid://(%d+)", start)
					if not a then
						break
					end
					start = b + 1
					local label = imageLabel(lines, index, a)
					local entry = byId[id]
					if entry then
						entry.Uses += 1
					else
						entry = { Slot = id, Label = label, Group = spec[2], Uses = 1, Image = "rbxassetid://" .. id }
						byId[id] = entry
						table.insert(entries, entry)
					end
				end
			end
		end
	end
	for _, entry in ipairs(entries) do
		entry.Sub = "rbxassetid://" .. entry.Slot .. (entry.Uses > 1 and ("  -  used " .. entry.Uses .. "x") or "")
	end
	return entries
end

local animationSlotsCache = nil
local function animationSlots()
	if animationSlotsCache then
		return animationSlotsCache
	end
	local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("AnimationLibrary")
	local ok, slots = false, nil
	if module then
		ok, slots = pcall(function()
			return require(module).GetSlots()
		end)
	end
	if not ok or type(slots) ~= "table" then
		return {}
	end
	animationSlotsCache = slots
	return slots
end

function Core.Catalog(kindKey)
	local kind = KIND_BY_KEY[kindKey]
	local entries = {}
	if kind.Type == "Mesh" or kind.Type == "Model" then
		local folder = getLibrary(kind, false)
		for _, child in ipairs(folder and folder:GetChildren() or {}) do
			if (kind.Type == "Mesh" and child:IsA("BasePart")) or (kind.Type == "Model" and child:IsA("Model")) then
				local label, group
				if kind.Key == "Weapons" then
					label = WEAPON_LABELS[child.Name] or humanize(child.Name)
					group = nil
				elseif kind.Key == "Monsters" then
					label = MONSTER_LABELS[child.Name] or humanize(child.Name)
				else
					label = humanize(child.Name)
					group = string.match(child.Name, "^([%a]+)_") or "Other"
				end
				local sub
				if child:IsA("BasePart") then
					sub = child.Name .. "  -  " .. meshSub(child)
				else
					local parts = 0
					for _, descendant in ipairs(child:GetDescendants()) do
						if descendant:IsA("BasePart") then
							parts += 1
						end
					end
					sub = child.Name .. "  -  " .. parts .. " parts"
				end
				table.insert(entries, { Slot = child.Name, Label = label, Sub = sub, Group = group, Instance = child })
			end
		end
		table.sort(entries, function(a, b)
			if (a.Group or "") ~= (b.Group or "") then
				return (a.Group or "") < (b.Group or "")
			end
			return a.Label < b.Label
		end)
	elseif kind.Type == "Animation" then
		local folder = getAnimationFolder(false)
		for _, slot in ipairs(animationSlots()) do
			local animation = folder and folder:FindFirstChild(slot.Key)
			local id = animation and animation:IsA("Animation") and animation.AnimationId or ""
			local builtIn = (string.match(slot.Key, "_Idle$") or string.match(slot.Key, "_Run$")) and slot.Group == "Heroes" and "built-in (Roblox default)" or "built-in (procedural)"
			table.insert(entries, { Slot = slot.Key, Label = slot.Label, Group = slot.Group, Custom = id ~= "",
				Sub = slot.Key .. "  -  " .. (id ~= "" and id or builtIn), Value = id })
		end
	elseif kind.Type == "Image" then
		entries = imageCatalog()
	end
	for _, entry in ipairs(entries) do
		entry.Backups = backupCount(kind.Key, entry.Slot)
	end
	return entries
end

--------------------------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------------------------
local Studio = settings().Studio
local FALLBACK_COLORS = {
	MainBackground = Color3.fromRGB(46, 46, 46), Titlebar = Color3.fromRGB(53, 53, 53), MainText = Color3.fromRGB(230, 230, 230),
	DimmedText = Color3.fromRGB(140, 140, 140), SubText = Color3.fromRGB(170, 170, 170), InputFieldBackground = Color3.fromRGB(37, 37, 37),
	InputFieldBorder = Color3.fromRGB(26, 26, 26), Button = Color3.fromRGB(60, 60, 60), ButtonText = Color3.fromRGB(230, 230, 230),
	Border = Color3.fromRGB(34, 34, 34), Item = Color3.fromRGB(46, 46, 46), MainButton = Color3.fromRGB(0, 162, 255),
	DialogMainButtonText = Color3.fromRGB(255, 255, 255), ErrorText = Color3.fromRGB(255, 90, 90), WarningText = Color3.fromRGB(255, 170, 60),
	Tab = Color3.fromRGB(53, 53, 53), ViewPortBackground = Color3.fromRGB(37, 37, 37), ButtonBorder = Color3.fromRGB(26, 26, 26),
}
local STATUS_COLORS = { ok = Color3.fromRGB(80, 200, 120), error = nil, warn = nil, info = nil }

local function themeColor(name, modifier)
	local ok, color = pcall(function()
		return Studio.Theme:GetColor(Enum.StudioStyleGuideColor[name], Enum.StudioStyleGuideModifier[modifier or "Default"])
	end)
	return ok and color or FALLBACK_COLORS[name] or Color3.new(1, 0, 1)
end

local themed = setmetatable({}, { __mode = "k" }) -- [instance] = { [property] = { name, modifier } }
local function paint(instance, property, name, modifier)
	themed[instance] = themed[instance] or {}
	themed[instance][property] = { name, modifier }
	instance[property] = themeColor(name, modifier)
end

local function new(className, properties, children)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

local function corner(instance, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = instance })
end

local function label(properties)
	local instance = new("TextLabel", {
		BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in pairs(properties) do
		if key ~= "Parent" and key ~= "ColorName" then
			instance[key] = value
		end
	end
	paint(instance, "TextColor3", properties.ColorName or "MainText")
	instance.Parent = properties.Parent
	return instance
end

local function button(text, properties, main)
	local instance = new("TextButton", {
		Text = text, Font = main and Enum.Font.SourceSansBold or Enum.Font.SourceSans, TextSize = 14, AutoButtonColor = true,
		Size = UDim2.new(0, 90, 0, 26),
	})
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	paint(instance, "BackgroundColor3", main and "MainButton" or "Button")
	paint(instance, "TextColor3", main and "DialogMainButtonText" or "ButtonText")
	corner(instance, 4)
	local stroke = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = instance })
	paint(stroke, "Color", "ButtonBorder")
	instance.Parent = properties and properties.Parent
	return instance
end

local function textBox(placeholder, properties)
	local instance = new("TextBox", {
		Text = "", PlaceholderText = placeholder, ClearTextOnFocus = false, Font = Enum.Font.SourceSans, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	paint(instance, "BackgroundColor3", "InputFieldBackground")
	paint(instance, "TextColor3", "MainText")
	paint(instance, "PlaceholderColor3", "DimmedText")
	corner(instance, 4)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = instance })
	local stroke = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = instance })
	paint(stroke, "Color", "InputFieldBorder")
	instance.Parent = properties and properties.Parent
	return instance
end

local function viewportPreview(parent, source)
	local frame = new("ViewportFrame", {
		Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 5), Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -0.6), Parent = parent,
	})
	paint(frame, "BackgroundColor3", "ViewPortBackground")
	corner(frame, 4)
	pcall(function()
		local clone = source:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BaseScript") or descendant:IsA("Sound") or descendant:IsA("ParticleEmitter") or descendant:IsA("Light") then
				descendant:Destroy()
			end
		end
		local boxCFrame, boxSize
		if clone:IsA("Model") then
			boxCFrame, boxSize = clone:GetBoundingBox()
		else
			boxCFrame, boxSize = clone.CFrame, clone.Size
		end
		clone.Parent = frame
		local camera = new("Camera", { FieldOfView = 40, Parent = frame })
		frame.CurrentCamera = camera
		local distance = (boxSize.Magnitude / 2) / math.tan(math.rad(20)) * 1.05
		camera.CFrame = CFrame.lookAt(boxCFrame.Position + Vector3.new(0.55, 0.45, 0.7).Unit * distance, boxCFrame.Position)
	end)
	return frame
end

local UI = {}

local function buildUI(container)
	local state = { Tab = "Weapons", Search = "", Selected = nil, Source = nil, SourceText = "", MatchSize = true, Busy = false, Entries = {} }
	UI.State = state

	local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = container })
	paint(root, "BackgroundColor3", "MainBackground")

	-- header
	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BorderSizePixel = 0, Parent = root })
	paint(header, "BackgroundColor3", "Titlebar")
	label({ Text = "RUINFALL ASSET PORTER", Font = Enum.Font.SourceSansBold, TextSize = 16, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20), Parent = header })
	local modeDot = new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(10, 31), BorderSizePixel = 0, Parent = header })
	corner(modeDot, 4)
	local modeText = label({ Text = "", TextSize = 13, ColorName = "SubText", Position = UDim2.fromOffset(24, 25), Size = UDim2.new(1, -34, 0, 20), Parent = header })

	-- tabs
	local tabBar = new("Frame", { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 52), BackgroundTransparency = 1, Parent = root })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabBar })
	local tabButtons = {}
	for _, kind in ipairs(KINDS) do
		local tab = button(kind.Key, { Size = UDim2.new(1 / #KINDS, -4, 1, 0), TextSize = 13, Parent = tabBar })
		tabButtons[kind.Key] = tab
	end

	-- search
	local searchRow = new("Frame", { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 82), BackgroundTransparency = 1, Parent = root })
	local search = textBox("Search...", { Size = UDim2.new(1, -82, 1, 0), Parent = searchRow })
	local refresh = button("Refresh", { Size = UDim2.new(0, 76, 1, 0), Position = UDim2.new(1, -76, 0, 0), Parent = searchRow })

	-- list
	local DETAIL_HEIGHT = 300
	local list = new("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, -(114 + DETAIL_HEIGHT + 22)), Position = UDim2.fromOffset(6, 112), BorderSizePixel = 0,
		ScrollBarThickness = 8, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = root,
	})
	paint(list, "BackgroundColor3", "InputFieldBackground")
	paint(list, "ScrollBarImageColor3", "DimmedText")
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	-- detail panel
	local detail = new("ScrollingFrame", {
		Size = UDim2.new(1, -12, 0, DETAIL_HEIGHT), Position = UDim2.new(0, 6, 1, -(DETAIL_HEIGHT + 24)), BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = root,
	})
	paint(detail, "BackgroundColor3", "Titlebar")
	corner(detail, 4)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = detail })
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = detail })
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local titleLabel = label({ Text = "Select a slot above", Font = Enum.Font.SourceSansBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(), Parent = detail })
	local currentBox = new("TextBox", {
		Text = "", TextEditable = false, ClearTextOnFocus = false, BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = nextOrder(), Parent = detail,
	})
	paint(currentBox, "TextColor3", "DimmedText")

	local idRow = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = detail })
	local idBox = textBox("Asset ID or URL", { Size = UDim2.new(1, -118, 1, 0), Parent = idRow })
	local useSelection = button("Use Selection", { Size = UDim2.new(0, 112, 1, 0), Position = UDim2.new(1, -112, 0, 0), Parent = idRow })
	local sourceLabel = label({ Text = "", TextSize = 13, ColorName = "SubText", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = nextOrder(), Parent = detail })

	local optionRow = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = detail })
	local textureBox = textBox("Texture ID (optional, for mesh IDs)", { Size = UDim2.new(1, -150, 1, 0), Parent = optionRow })
	local matchToggle = button("[x] Match old size", { Size = UDim2.new(0, 144, 1, 0), Position = UDim2.new(1, -144, 0, 0), Parent = optionRow })

	local actionRow = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = detail })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = actionRow })
	local swapButton = button("SWAP", { Size = UDim2.new(0, 110, 1, 0), Parent = actionRow }, true)
	local revertButton = button("Revert", { Size = UDim2.new(0, 90, 1, 0), Parent = actionRow })
	local clearButton = button("Use built-in", { Size = UDim2.new(0, 100, 1, 0), Parent = actionRow })

	local newRow = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = detail })
	local newNameBox = textBox("Name for a NEW library entry", { Size = UDim2.new(1, -118, 1, 0), Parent = newRow })
	local addButton = button("Port as new", { Size = UDim2.new(0, 112, 1, 0), Position = UDim2.new(1, -112, 0, 0), Parent = newRow })

	local hintLabel = label({ Text = "", TextSize = 13, ColorName = "DimmedText", TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nextOrder(), Parent = detail })
	local statusLabel = label({ Text = "", TextSize = 14, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Font = Enum.Font.SourceSansSemibold,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nextOrder(), Parent = detail })

	local footer = label({ Text = "", TextSize = 12, ColorName = "DimmedText", Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 18), Parent = root })

	-- helpers -------------------------------------------------------------------------------------
	local function setStatus(text, kind)
		statusLabel.Text = text or ""
		if kind == "ok" then
			statusLabel.TextColor3 = STATUS_COLORS.ok
		elseif kind == "error" then
			statusLabel.TextColor3 = themeColor("ErrorText")
		elseif kind == "warn" then
			statusLabel.TextColor3 = themeColor("WarningText")
		else
			statusLabel.TextColor3 = themeColor("MainText")
		end
	end
	UI.SetStatus = setStatus

	local function currentKind()
		return KIND_BY_KEY[state.Tab]
	end

	local function selectedEntry()
		for _, entry in ipairs(state.Entries) do
			if entry.Slot == state.Selected then
				return entry
			end
		end
		return nil
	end

	local function updateMode()
		local current = role()
		local live = liveSessionActive()
		if current == "Edit" and not live then
			modeDot.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
			modeText.Text = "EDIT - swaps are saved into the place; press Play to see them"
		elseif current == "Server" then
			modeDot.BackgroundColor3 = Color3.fromRGB(255, 160, 50)
			modeText.Text = "PLAYTEST - swaps show up in the game now and are saved when you stop"
		elseif live then
			modeDot.BackgroundColor3 = Color3.fromRGB(255, 160, 50)
			modeText.Text = "PLAYTEST - swaps are sent to the running game and saved when you stop"
		else
			modeDot.BackgroundColor3 = Color3.fromRGB(230, 80, 80)
			modeText.Text = "PLAYTEST (client view) - switch Studio to the Server view to swap live"
		end
		local pending = getSetting(KEY_PENDING)
		local count = type(pending) == "table" and #pending or 0
		if current ~= "Edit" or live then
			footer.Text = count > 0 and (count .. " swap(s) will be saved into the place when the playtest stops") or ("Asset Porter " .. VERSION)
		elseif not string.find(footer.Text, "Saved", 1, true) then
			footer.Text = "Asset Porter " .. VERSION .. "  -  backups: ServerStorage." .. BACKUP_FOLDER
		end
	end
	UI.UpdateMode = updateMode

	local function sourceSpec()
		local kind = currentKind()
		if kind.Type == "Animation" or kind.Type == "Image" or kind.Type == "Mesh" or kind.Type == "Model" then
			local id = parseAssetId(idBox.Text)
			if id then
				return { Type = "Id", Id = id }
			end
			if kind.Type == "Animation" and string.match(idBox.Text, "^%s*rbx%a+://") then
				return { Type = "Value", Value = (string.gsub(idBox.Text, "%s", "")) }
			end
		end
		return state.Source
	end

	local function updateDetail()
		local kind = currentKind()
		local entry = selectedEntry()
		local meshKind = kind.Type == "Mesh" or kind.Type == "Model"
		optionRow.Visible = meshKind
		textureBox.Visible = kind.Type == "Mesh"
		matchToggle.Text = (state.MatchSize and "[x] " or "[  ] ") .. (kind.Type == "Model" and "Match old height" or "Match old size")
		newRow.Visible = meshKind
		clearButton.Visible = kind.Type == "Animation"
		hintLabel.Text = kind.Hint
		if entry then
			titleLabel.Text = entry.Label
			currentBox.Text = "Current: " .. (entry.Sub or entry.Slot)
		else
			titleLabel.Text = "Select a slot above"
			currentBox.Text = meshKind and "(or port a brand-new entry below)" or ""
		end
		local liveNow = role() ~= "Edit" or liveSessionActive()
		swapButton.Active = entry ~= nil and not state.Busy
		swapButton.AutoButtonColor = swapButton.Active
		swapButton.TextTransparency = swapButton.Active and 0 or 0.5
		local canRevert = entry ~= nil and not liveNow and (entry.Backups or 0) > 0 and not state.Busy
		revertButton.Active = canRevert
		revertButton.TextTransparency = canRevert and 0 or 0.5
		revertButton.Text = (entry and (entry.Backups or 0) > 0) and ("Revert (" .. entry.Backups .. ")") or "Revert"
		local canClear = entry ~= nil and entry.Custom == true and not state.Busy
		clearButton.Active = canClear
		clearButton.TextTransparency = canClear and 0 or 0.5
		if state.Source and state.SourceText ~= "" and parseAssetId(idBox.Text) == nil then
			sourceLabel.Text = "Source: selection - " .. state.SourceText
		else
			local id = parseAssetId(idBox.Text)
			sourceLabel.Text = id and ("Source: asset " .. id) or "Source: -"
		end
	end
	UI.UpdateDetail = updateDetail

	local rowCleanup = {}
	local function rebuildList()
		for _, item in ipairs(rowCleanup) do
			item:Destroy()
		end
		table.clear(rowCleanup)
		local kind = currentKind()
		local ok, entries = pcall(Core.Catalog, state.Tab)
		if not ok then
			setStatus("Could not list " .. state.Tab .. ": " .. tostring(entries), "error")
			entries = {}
		end
		state.Entries = entries
		local query = string.lower(state.Search)
		local layoutOrder, lastGroup, shown = 0, nil, 0
		for _, entry in ipairs(entries) do
			local haystack = string.lower((entry.Label or "") .. " " .. (entry.Sub or "") .. " " .. entry.Slot)
			if query == "" or string.find(haystack, query, 1, true) then
				if entry.Group and entry.Group ~= lastGroup then
					lastGroup = entry.Group
					layoutOrder += 1
					local groupLabel = label({ Text = string.upper(entry.Group), Font = Enum.Font.SourceSansBold, TextSize = 12, ColorName = "DimmedText",
						Size = UDim2.new(1, -8, 0, 20), LayoutOrder = layoutOrder, Parent = list })
					new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = groupLabel })
					table.insert(rowCleanup, groupLabel)
				end
				layoutOrder += 1
				shown += 1
				local selected = entry.Slot == state.Selected
				local row = new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(1, -8, 0, 54), LayoutOrder = layoutOrder, BorderSizePixel = 0, Parent = list })
				paint(row, "BackgroundColor3", "Item", selected and "Selected" or "Default")
				table.insert(rowCleanup, row)
				if entry.Instance then
					viewportPreview(row, entry.Instance)
				elseif entry.Image then
					local image = new("ImageLabel", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 5), Image = entry.Image, ScaleType = Enum.ScaleType.Fit, Parent = row })
					paint(image, "BackgroundColor3", "ViewPortBackground")
					corner(image, 4)
				else
					local glyph = label({ Text = entry.Custom and "ANIM" or "built-in", TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.SourceSansBold,
						TextSize = entry.Custom and 13 or 11, Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 5), BackgroundTransparency = 0, Parent = row })
					glyph.BackgroundColor3 = entry.Custom and Color3.fromRGB(0, 120, 200) or themeColor("ViewPortBackground")
					glyph.TextColor3 = entry.Custom and Color3.new(1, 1, 1) or themeColor("DimmedText")
					corner(glyph, 4)
				end
				label({ Text = entry.Label, Font = Enum.Font.SourceSansSemibold, TextSize = 14, Position = UDim2.fromOffset(58, 8), Size = UDim2.new(1, -66, 0, 18), Parent = row })
				label({ Text = (entry.Sub or entry.Slot) .. ((entry.Backups or 0) > 0 and ("  -  " .. entry.Backups .. " backup(s)") or ""), TextSize = 12,
					ColorName = "DimmedText", Position = UDim2.fromOffset(58, 28), Size = UDim2.new(1, -66, 0, 16), Parent = row })
				row.MouseButton1Click:Connect(function()
					state.Selected = entry.Slot
					for _, other in ipairs(rowCleanup) do
						if other:IsA("TextButton") then
							paint(other, "BackgroundColor3", "Item", other == row and "Selected" or "Default")
						end
					end
					updateDetail()
				end)
			end
		end
		if shown == 0 then
			local empty = label({ Text = kind.Type == "Animation" and "No animation slots found (is Shared.AnimationLibrary missing?)" or "Nothing here yet",
				ColorName = "DimmedText", TextSize = 13, Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 1, Parent = list })
			new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = empty })
			table.insert(rowCleanup, empty)
		end
		for key, tab in pairs(tabButtons) do
			paint(tab, "BackgroundColor3", key == state.Tab and "MainButton" or "Button")
			paint(tab, "TextColor3", key == state.Tab and "DialogMainButtonText" or "ButtonText")
		end
		updateDetail()
		updateMode()
	end
	UI.Rebuild = rebuildList

	local function resetInputs()
		idBox.Text = ""
		textureBox.Text = ""
		newNameBox.Text = ""
		state.Source, state.SourceText = nil, ""
	end

	local function run(action, slot, source, options)
		if state.Busy then
			return
		end
		state.Busy = true
		setStatus("Working...", "info")
		updateDetail()
		task.spawn(function()
			local ok, message = Core.Execute(action, state.Tab, slot, source, options)
			state.Busy = false
			setStatus(message, ok and "ok" or "error")
			if ok then
				resetInputs()
				if action == "Add" then
					state.Selected = slot
				end
			end
			rebuildList()
		end)
	end

	-- events --------------------------------------------------------------------------------------
	for key, tab in pairs(tabButtons) do
		tab.MouseButton1Click:Connect(function()
			if state.Tab ~= key then
				state.Tab = key
				state.Selected = nil
				resetInputs()
				setStatus("", "info")
				list.CanvasPosition = Vector2.zero
				rebuildList()
			end
		end)
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		state.Search = search.Text
		rebuildList()
	end)
	refresh.MouseButton1Click:Connect(function()
		animationSlotsCache = nil
		rebuildList()
	end)
	idBox:GetPropertyChangedSignal("Text"):Connect(function()
		if parseAssetId(idBox.Text) then
			state.Source, state.SourceText = nil, ""
		end
		updateDetail()
	end)
	useSelection.MouseButton1Click:Connect(function()
		local source, text = sourceFromSelection(currentKind())
		if not source then
			setStatus(text, "warn")
			return
		end
		idBox.Text = ""
		state.Source, state.SourceText = source, text
		setStatus("Using the selection: " .. text, "info")
		updateDetail()
	end)
	matchToggle.MouseButton1Click:Connect(function()
		state.MatchSize = not state.MatchSize
		updateDetail()
	end)
	swapButton.MouseButton1Click:Connect(function()
		local entry = selectedEntry()
		if not entry or state.Busy then
			return
		end
		local source = sourceSpec()
		if not source then
			setStatus("Enter an asset ID / URL or click Use Selection first", "warn")
			return
		end
		local textureId = parseAssetId(textureBox.Text)
		run("Swap", entry.Slot, source, { MatchSize = state.MatchSize, Texture = textureId and ("rbxassetid://" .. textureId) or nil })
	end)
	revertButton.MouseButton1Click:Connect(function()
		local entry = selectedEntry()
		if entry and revertButton.Active then
			run("Revert", entry.Slot, nil, nil)
		end
	end)
	clearButton.MouseButton1Click:Connect(function()
		local entry = selectedEntry()
		if entry and clearButton.Active then
			run("Clear", entry.Slot, { Type = "Clear" }, nil)
		end
	end)
	addButton.MouseButton1Click:Connect(function()
		local name = string.gsub(newNameBox.Text, "[^%w_]", "")
		if name == "" then
			setStatus("Type a name for the new entry (letters, digits, _)", "warn")
			return
		end
		local source = sourceSpec()
		if not source then
			setStatus("Enter an asset ID / URL or click Use Selection first", "warn")
			return
		end
		local textureId = parseAssetId(textureBox.Text)
		run("Add", name, source, { MatchSize = false, Texture = textureId and ("rbxassetid://" .. textureId) or nil })
	end)
	Studio.ThemeChanged:Connect(function()
		for instance, properties in pairs(themed) do
			if instance.Parent then
				for property, spec in pairs(properties) do
					pcall(function()
						instance[property] = themeColor(spec[1], spec[2])
					end)
				end
			end
		end
	end)

	onPendingSaved = function(count, failures)
		local text = string.format("Saved %d swap(s) from the playtest into the place", count)
		if #failures > 0 then
			text ..= ". Not saved: " .. table.concat(failures, "; ")
		end
		setStatus(text, #failures > 0 and "warn" or "ok")
		footer.Text = text
		rebuildList()
	end

	rebuildList()
	return root
end

--------------------------------------------------------------------------------------------------
-- Plugin wiring
--------------------------------------------------------------------------------------------------
local container
local toolbarButton
if IS_TEST then
	container = new("ScreenGui", { Name = "RuinfallAssetPorterTest", ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false, Parent = CoreGui })
	new("Frame", { Name = "Holder", Size = UDim2.fromOffset(440, 700), BackgroundTransparency = 1, Parent = container })
	buildUI(container.Holder)
else
	local toolbar = plugin:CreateToolbar("Ruinfall")
	toolbarButton = toolbar:CreateButton("RuinfallAssetPorter", "Port and swap RUINFALL assets & animations (weapons, animations, props, monsters, images)", "", "Asset Porter")
	toolbarButton.ClickableWhenViewportHidden = true
	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 440, 720, 360, 520)
	container = plugin:CreateDockWidgetPluginGui("RuinfallAssetPorter_" .. role(), info)
	container.Title = "Ruinfall Asset Porter" .. (role() ~= "Edit" and (" (" .. role() .. ")") or "")
	container.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	buildUI(container)
	toolbarButton.Click:Connect(function()
		container.Enabled = not container.Enabled
	end)
	container:GetPropertyChangedSignal("Enabled"):Connect(function()
		toolbarButton:SetActive(container.Enabled)
		if container.Enabled and UI.Rebuild then
			UI.Rebuild()
		end
	end)
	toolbarButton:SetActive(container.Enabled)
end

-- background loops: heartbeat + requests (server copy), saving playtest swaps (edit copy)
local alive = true
task.spawn(function()
	local beatClock = 0
	while alive do
		local current = role()
		if current == "Server" then
			if os.clock() - beatClock > 2 then
				beatClock = os.clock()
				setSetting(KEY_LIVE, nowMs())
			end
			pcall(serveRequests)
		elseif current == "Edit" then
			pcall(savePendingSwaps)
		end
		if UI.UpdateMode then
			pcall(UI.UpdateMode)
		end
		task.wait(current == "Server" and 0.3 or 1.5)
	end
end)

-- test / automation hook (used by tooling; harmless for users)
local hook = CoreGui:FindFirstChild("RuinfallAssetPorterHook")
if hook then
	hook:Destroy()
end
hook = new("BindableFunction", { Name = "RuinfallAssetPorterHook", Archivable = false })
hook.OnInvoke = function(command, ...)
	if command == "role" then
		return role()
	elseif command == "version" then
		return VERSION
	elseif command == "catalog" then
		local out = {}
		for _, entry in ipairs(Core.Catalog(...)) do
			table.insert(out, { Slot = entry.Slot, Label = entry.Label, Sub = entry.Sub, Group = entry.Group, Custom = entry.Custom, Backups = entry.Backups })
		end
		return out
	elseif command == "execute" then
		return Core.Execute(...)
	elseif command == "pending" then
		return getSetting(KEY_PENDING)
	elseif command == "getsetting" then
		return getSetting(...)
	elseif command == "setsetting" then
		setSetting(...)
		return true
	elseif command == "live" then
		return liveSessionActive()
	elseif command == "savepending" then
		savePendingSwaps()
		return true
	elseif command == "ui" then
		local action, value = ...
		if action == "tab" and UI.State then
			UI.State.Tab = value
			UI.State.Selected = nil
			UI.Rebuild()
		elseif action == "select" and UI.State then
			UI.State.Selected = value
			UI.UpdateDetail()
		end
		return UI.State and { Tab = UI.State.Tab, Selected = UI.State.Selected, Entries = #UI.State.Entries } or nil
	end
	return nil
end
hook.Parent = CoreGui

local function shutdown()
	alive = false
	if role() == "Server" then
		setSetting(KEY_LIVE, 0)
	end
	if hook then
		hook:Destroy()
	end
	if IS_TEST and container then
		container:Destroy()
	end
end
if IS_TEST then
	UI.Shutdown = shutdown
	return { Core = Core, UI = UI, Shutdown = shutdown }
else
	plugin.Unloading:Connect(shutdown)
end
