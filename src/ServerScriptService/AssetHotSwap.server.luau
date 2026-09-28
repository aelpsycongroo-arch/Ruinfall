-- AssetHotSwap: makes asset swaps done with the Ruinfall Asset Porter plugin DURING a playtest
-- show up in the running game immediately (in Edit mode the plugin saves them into the place and
-- the next playtest simply builds with the new assets):
--   weapons  (ServerStorage.RuinfallWeapons) -> every hero's weapon meshes are rebuilt
--   props    (ServerStorage.RuinfallAssets)  -> every placed copy on the map is replaced in place
--   monsters (ServerStorage.MonsterAssets)   -> the next monster / minion spawn uses the new model
--   images   (ReplicatedStorage.RuinfallAssetSwaps log) -> server config tables + instances
--   animations need nothing here: everything reads ReplicatedStorage.RuinfallAnimations live
-- Nothing changes these folders in a published game, so this script just stays idle there.

-- Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetSwap = require(Shared:WaitForChild("AssetSwap"))
local CharacterFactory = require(ServerScriptService:WaitForChild("CharacterFactory"))

-- Weapons --------------------------------------------------------------------------------------
local weaponRefreshQueued = false
local function refreshWeapons()
	weaponRefreshQueued = false
	local count = 0
	for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
		if model.Parent and model:FindFirstChild("ClassGear") then
			local ok, refreshed = pcall(CharacterFactory.RefreshWeapons, model)
			if ok and refreshed then
				count += 1
			end
		end
	end
	print(string.format("[Ruinfall] Asset swap: weapons rebuilt on %d hero(es)", count))
end
local function queueWeaponRefresh()
	if not weaponRefreshQueued then
		weaponRefreshQueued = true
		task.delay(0.2, refreshWeapons)
	end
end
local weapons = ServerStorage:FindFirstChild("RuinfallWeapons")
if weapons then
	weapons.ChildAdded:Connect(queueWeaponRefresh)
	weapons.ChildRemoved:Connect(queueWeaponRefresh)
end

-- Props ----------------------------------------------------------------------------------------
local known = {} -- [name] = { Size, MeshId } of the current library entry
local removed = {} -- [name] = what the entry looked like right before it was swapped out
local function describe(part)
	return { Size = part.Size, MeshId = part:IsA("MeshPart") and part.MeshId or nil }
end

-- replace one placed copy, keeping its footprint (per-axis scale), rotation, ground contact,
-- physics flags, tint, attributes, tags and builder-added children (lights, fire...)
local function replacePlaced(instance, source, oldSize)
	local factor = Vector3.new(instance.Size.X / oldSize.X, instance.Size.Y / oldSize.Y, instance.Size.Z / oldSize.Z)
	local clone = source:Clone()
	clone.Size = Vector3.new(source.Size.X * factor.X, source.Size.Y * factor.Y, source.Size.Z * factor.Z)
	local bottom = instance.CFrame * CFrame.new(0, -instance.Size.Y / 2, 0)
	clone.CFrame = bottom * CFrame.new(0, clone.Size.Y / 2, 0)
	clone.Anchored = instance.Anchored
	clone.CanCollide = instance.CanCollide
	clone.CanQuery = instance.CanQuery
	clone.CanTouch = instance.CanTouch
	clone.CastShadow = instance.CastShadow
	clone.Transparency = instance.Transparency
	for key, value in pairs(instance:GetAttributes()) do
		clone:SetAttribute(key, value)
	end
	for _, tag in ipairs(CollectionService:GetTags(instance)) do
		CollectionService:AddTag(clone, tag)
	end
	local oldLook = instance:FindFirstChildOfClass("SurfaceAppearance")
	local newLook = clone:FindFirstChildOfClass("SurfaceAppearance")
	if oldLook and newLook then
		pcall(function()
			newLook.Color = oldLook.Color
		end)
	end
	for _, child in ipairs(instance:GetChildren()) do
		if not child:IsA("SurfaceAppearance") and not child:IsA("JointInstance") and not child:IsA("Constraint") and not child:IsA("WeldConstraint") then
			child.Parent = clone
		end
	end
	clone.Parent = instance.Parent
	instance:Destroy()
end

local function replaceOnMap(name, old, source)
	local map = workspace:FindFirstChild("RuinfallMap")
	if not map then
		return
	end
	local count = 0
	for _, instance in ipairs(map:GetDescendants()) do
		if instance:IsA("BasePart") and instance.Name == name and instance.Parent
			and (old.MeshId == nil or (instance:IsA("MeshPart") and instance.MeshId == old.MeshId)) then
			local ok, err = pcall(replacePlaced, instance, source, old.Size)
			if ok then
				count += 1
			else
				warn("[Ruinfall] Asset swap: could not replace a placed " .. name .. ":", err)
			end
		end
	end
	print(string.format("[Ruinfall] Asset swap: replaced %d placed '%s' on the map", count, name))
end

local library = ServerStorage:FindFirstChild("RuinfallAssets")
if library then
	for _, child in ipairs(library:GetChildren()) do
		if child:IsA("BasePart") then
			known[child.Name] = describe(child)
		end
	end
	library.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			removed[child.Name] = describe(child)
		end
	end)
	library.ChildAdded:Connect(function(child)
		task.defer(function()
			if not child:IsA("BasePart") or child.Parent ~= library then
				return
			end
			local old = removed[child.Name] or known[child.Name]
			removed[child.Name] = nil
			known[child.Name] = describe(child)
			if old then
				replaceOnMap(child.Name, old, child)
			end
		end)
	end)
end

-- Monsters / minions: MonsterService and CreepService read the template at every spawn -------------
local monsters = ServerStorage:FindFirstChild("MonsterAssets")
if monsters then
	monsters.ChildAdded:Connect(function(child)
		print("[Ruinfall] Asset swap: '" .. child.Name .. "' will be used from the next spawn")
	end)
end

-- Images -----------------------------------------------------------------------------------------
AssetSwap.Watch(function(old, new)
	for _, name in ipairs({ "ItemDefinitions", "ClassDefinitions", "ShopDefinitions", "Constants" }) do
		local module = Shared:FindFirstChild(name)
		if module then
			local ok, data = pcall(require, module)
			if ok then
				AssetSwap.PatchTable(data, old, new)
			end
		end
	end
	for _, root in ipairs({ workspace, ReplicatedStorage, game:GetService("StarterGui") }) do
		AssetSwap.PatchInstances(root, old, new)
	end
	print(string.format("[Ruinfall] Asset swap: image %s -> %s", old, new))
end)
