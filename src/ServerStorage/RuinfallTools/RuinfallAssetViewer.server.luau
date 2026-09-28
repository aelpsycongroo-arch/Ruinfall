--[[
	RUINFALL ASSET VIEWER  v1.1  -  Roblox Studio plugin (Plugins tab > Ruinfall > Asset Viewer)

	Browse and inspect every RUINFALL asset.

	  Heroes      each class rig with its gear and weapons, built by the game's own CharacterFactory,
	              in any team colour, playing idle / run / attack / Q
	  Weapons     orbit view of every weapon mesh, alone or in its hero's hand
	  Props       orbit view of every map mesh
	  Monsters    creature templates playing idle / walk / attack / death
	  Animations  every AnimationLibrary slot played on the right rig: the uploaded animation, the
	              built-in one, or any stored VERSION of it (ServerStorage.RuinfallAnimationVersions:
	              KeyframeSequences such as Original / Improved) - one at a time or all side by side
	              (Compare). Select a KeyframeSequence and press "+ Add selected" to store a new one.
	  Images      gallery of item / class / shop icons and HUD art

	Every asset lists its ids, size and every script line / instance that uses it (click a line to
	open the script). Built-in animations are read from the game's own animation scripts
	(AttackAnimationController, MonsterAnimationController, MinionAnimationController) each time,
	so the preview always matches what the game plays.

	3D view: drag to rotate, mouse wheel to zoom.
	To replace an asset, use Asset Porter.
]]

--------------------------------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------------------------------
local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local StarterPlayer = game:GetService("StarterPlayer")
local StudioService = game:GetService("StudioService")
local TweenService = game:GetService("TweenService")

local plugin = plugin
local IS_TEST = type(plugin) == "table" and plugin.__test == true

--------------------------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------------------------
local VERSION = "1.1"
local VERSIONS_FOLDER = "RuinfallAnimationVersions" -- ServerStorage.<this>.<Slot key>.<Version KeyframeSequence>
local COMPARE_GAP = 4.6 -- studs between rigs in Compare
local COMPARE_COLORS = { Color3.fromRGB(150, 150, 165), Color3.fromRGB(255, 196, 60), Color3.fromRGB(80, 180, 255), Color3.fromRGB(240, 100, 100) }
local COMPARE_COLOR_NAMES = { "grey", "gold", "blue", "red" }
local TABS = { "Heroes", "Weapons", "Props", "Monsters", "Animations", "Images" }
local DEFAULT_IDLE = "rbxassetid://507766666" -- Roblox default R15 idle / run (what heroes use
local DEFAULT_RUN = "rbxassetid://507767714" -- when no <Class>_Idle / _Run is uploaded)
local WEAPON_CLASS = {
	W_Sword = "Fighter", W_Dagger = "Assassin", W_Staff = "Mage", W_StaffCrystal = "Mage",
	W_Bow = "Marksman", W_Quiver = "Marksman", W_Shield = "Tank", W_ShieldCrest = "Tank", W_Mace = "Tank",
}
local CREATURE_TEMPLATE = { Monster = "StoneWarden", Minion = "GoblinMinion" }
local TEMPLATE_KIND = { StoneWarden = "Monster", GoblinMinion = "Minion" }
local SEARCH_ROOTS = { "Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer", "StarterPack" }
local HISTORY_FOLDER = "AssetViewerHistory" -- ServerStorage.AssetViewerHistory.<slot>: every icon a slot had before
local MAX_HISTORY = 25
local SKIP_FOLDERS = { ScriptBackups = true, AssetPorterBackups = true, RuinfallOldDraft = true, RuinfallTools = true, [HISTORY_FOLDER] = true }
local EDIT_ROOTS = { "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer", "StarterPack", "ServerScriptService", "ServerStorage", "Lighting" }
local IMAGE_EDIT_PROPERTIES = { "Image", "HoverImage", "PressedImage", "Texture", "TextureID" }
local ID_PROPERTIES = { "Image", "HoverImage", "PressedImage", "Texture", "TextureID", "MeshId" }
local IMAGE_SOURCES = {
	{ { "ReplicatedStorage", "Shared", "ItemDefinitions" }, "Item icons" },
	{ { "ReplicatedStorage", "Shared", "ClassDefinitions" }, "Class emblems" },
	{ { "ReplicatedStorage", "Shared", "ShopDefinitions" }, "Shop icons" },
	{ { "StarterPlayer", "StarterPlayerScripts", "HUD", "Theme" }, "HUD art" },
}
local MAX_USAGES = 60
local ONE_SHOT_HOLD = 0.45 -- pause between repeats of attack / skill animations

--------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------
local function resolvePath(path)
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

-- loads a ModuleScript's CURRENT source (the plugin's require cache would keep old versions)
local function freshRequire(module)
	local fn, err = loadstring(module.Source, "=" .. module:GetFullName())
	if not fn then
		error(err, 0)
	end
	setfenv(fn, setmetatable({ script = module }, { __index = getfenv(0) }))
	return fn()
end

-- runs the definitions part of a game LocalScript (everything above `marker`) and returns the
-- locals named in `exports`, so previews use exactly the game's own animation data / poses
local function extractLocals(scriptInstance, marker, exports)
	if not scriptInstance then
		return nil, "script not found"
	end
	local source = scriptInstance.Source
	local cut = string.find(source, "\n" .. marker, 1, true)
	if not cut then
		return nil, "marker '" .. marker .. "' not found in " .. scriptInstance.Name
	end
	local fields = {}
	for _, name in ipairs(exports) do
		table.insert(fields, name .. " = " .. name)
	end
	local body = string.sub(source, 1, cut) .. "\nreturn { " .. table.concat(fields, ", ") .. " }\n"
	local fn, err = loadstring(body, "=" .. scriptInstance.Name)
	if not fn then
		return nil, err
	end
	setfenv(fn, setmetatable({ script = scriptInstance }, { __index = getfenv(0) }))
	local ok, result = pcall(fn)
	if not ok then
		return nil, result
	end
	for _, name in ipairs(exports) do
		if result[name] == nil then
			return nil, name .. " not found in " .. scriptInstance.Name
		end
	end
	return result
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

local function trim(text)
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- token found with no word character (or digit, for ids) glued to either side
local function hasToken(line, token, digits)
	local start = 1
	local boundary = digits and "%d" or "[%w_]"
	while true do
		local a, b = string.find(line, token, start, true)
		if not a then
			return false
		end
		local before = a > 1 and string.sub(line, a - 1, a - 1) or ""
		local after = string.sub(line, b + 1, b + 1)
		if not string.match(before, boundary) and not string.match(after, boundary) then
			return true
		end
		start = b + 1
	end
end

-- every script line and instance property that mentions one of the tokens
local function findUsages(tokens)
	local usages = {}
	local seen = {}
	for _, serviceName in ipairs(SEARCH_ROOTS) do
		local ok, service = pcall(function()
			return game:GetService(serviceName)
		end)
		if ok and service then
			for _, descendant in ipairs(service:GetDescendants()) do
				if #usages >= MAX_USAGES then
					return usages, true
				end
				if descendant:IsA("LuaSourceContainer") then
					if not isSkipped(descendant) then
						local source = descendant.Source
						local present = false
						for _, token in ipairs(tokens) do
							if string.find(source, token.Text, 1, true) then
								present = true
								break
							end
						end
						if present then
							for index, line in ipairs(string.split(source, "\n")) do
								for _, token in ipairs(tokens) do
									if hasToken(line, token.Text, token.Digits) then
										table.insert(usages, { Script = descendant, Line = index, Text = trim(line) })
										break
									end
								end
							end
						end
					end
				else
					for _, token in ipairs(tokens) do
						if token.Digits then
							for _, property in ipairs(ID_PROPERTIES) do
								local okRead, value = pcall(function()
									return descendant[property]
								end)
								if okRead and type(value) == "string" and hasToken(value, token.Text, true) and not seen[descendant] and not isSkipped(descendant) then
									seen[descendant] = true
									table.insert(usages, { Instance = descendant, Property = property })
								end
							end
						end
					end
				end
			end
		end
	end
	return usages, false
end

local function digitsOf(content)
	return type(content) == "string" and string.match(content, "%d%d%d%d+") or nil
end

local function vectorText(v)
	return string.format("%.2f x %.2f x %.2f", v.X, v.Y, v.Z)
end

local function escapeRich(text)
	return (string.gsub(string.gsub(string.gsub(tostring(text), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

--------------------------------------------------------------------------------------------------
-- Rig pose solver: places every part of a viewport model from its joints, so animations can be
-- previewed in edit mode (no physics / animator needed). Works for Motor6D and AnimationConstraint
-- rigs; welded gear follows the part it is welded to.
--------------------------------------------------------------------------------------------------
local function buildRig(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = model.PrimaryPart
	end
	if not root then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				root = descendant
				break
			end
		end
	end
	if not root then
		return nil
	end
	local edges, animated = {}, {}
	local function add(a, b, edge)
		if not a or not b or a == b or not a:IsA("BasePart") or not b:IsA("BasePart") then
			return
		end
		edges[a] = edges[a] or {}
		edges[b] = edges[b] or {}
		table.insert(edges[a], { Other = b, Edge = edge, Reverse = false })
		table.insert(edges[b], { Other = a, Edge = edge, Reverse = true })
		if edge.Animated then
			animated[b] = true
		end
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") then
			if descendant.Part0 and descendant.Part1 then
				add(descendant.Part0, descendant.Part1, { J0 = descendant.C0, J1inv = descendant.C1:Inverse(), Animated = descendant:IsA("Motor6D") })
			end
		elseif descendant:IsA("AnimationConstraint") then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				add(a0.Parent, a1.Parent, { J0 = a0.CFrame, J1inv = a1.CFrame:Inverse(), Animated = true })
			end
		elseif descendant:IsA("WeldConstraint") then
			if descendant.Part0 and descendant.Part1 then
				add(descendant.Part0, descendant.Part1, { Rel = descendant.Part0.CFrame:ToObjectSpace(descendant.Part1.CFrame) })
			end
		elseif descendant:IsA("RigidConstraint") then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
				add(a0.Parent, a1.Parent, { Rel = a0.Parent.CFrame:ToObjectSpace(a1.Parent.CFrame) })
			end
		end
	end
	local order, visited, queue, head = {}, { [root] = true }, { root }, 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		for _, link in ipairs(edges[part] or {}) do
			if not visited[link.Other] then
				visited[link.Other] = true
				table.insert(order, { Parent = part, Child = link.Other, Edge = link.Edge, Reverse = link.Reverse })
				table.insert(queue, link.Other)
			end
		end
	end
	local loose, parts = {}, {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			if not visited[descendant] then
				table.insert(loose, { Part = descendant, Rel = root.CFrame:ToObjectSpace(descendant.CFrame) })
			end
		end
	end
	return { Model = model, Root = root, RootCFrame = root.CFrame, Order = order, Loose = loose, Animated = animated, Parts = parts }
end

-- transforms: { [Part1 of an animated joint] = CFrame }
local function applyPose(rig, transforms)
	local placed = { [rig.Root] = rig.Root.CFrame }
	for _, step in ipairs(rig.Order) do
		local edge = step.Edge
		local relation
		if edge.Animated then
			local transform = transforms[step.Reverse and step.Parent or step.Child]
			relation = edge.J0 * (transform or CFrame.identity) * edge.J1inv
		else
			relation = edge.Rel
		end
		local parentCFrame = placed[step.Parent]
		local childCFrame = step.Reverse and parentCFrame * relation:Inverse() or parentCFrame * relation
		placed[step.Child] = childCFrame
		step.Child.CFrame = childCFrame
	end
	for _, entry in ipairs(rig.Loose) do
		entry.Part.CFrame = placed[rig.Root] * entry.Rel
	end
end

--------------------------------------------------------------------------------------------------
-- Animation drivers: Sample(time) -> transforms
--------------------------------------------------------------------------------------------------
local keyframeCache = {}
local readSequence -- defined below loadKeyframes

local function easeAlpha(alpha, style, direction)
	if style == "Constant" then
		return 0
	elseif style == "Linear" then
		return alpha
	end
	local ok, value = pcall(function()
		return TweenService:GetValue(alpha, Enum.EasingStyle[style == "CubicV2" and "Cubic" or style], Enum.EasingDirection[direction])
	end)
	return ok and value or alpha
end

local function loadKeyframes(id)
	local cached = keyframeCache[id]
	if cached ~= nil then
		return cached or nil, "could not load this animation"
	end
	local ok, sequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(id)
	end)
	if not ok or not sequence then
		keyframeCache[id] = false
		return nil, "could not load " .. tostring(id) .. " (not an animation you can access, or a curve animation)"
	end
	local data = readSequence(sequence)
	keyframeCache[id] = data
	return data
end

-- KeyframeSequence -> { Tracks = { [pose name] = { { Time, CFrame, Style, Direction } } }, Length, Loop, Keyframes, Priority }
readSequence = function(sequence)
	-- versions made from the game's procedural swings ease every segment like the game does (quad in/out)
	local quad = sequence:GetAttribute("GameEasing") == "Quad"
	local tracks, length, count = {}, 0, 0
	for _, keyframe in ipairs(sequence:GetKeyframes()) do
		count += 1
		length = math.max(length, keyframe.Time)
		for _, pose in ipairs(keyframe:GetDescendants()) do
			if pose:IsA("Pose") and pose.Weight > 0 then
				local list = tracks[pose.Name]
				if not list then
					list = {}
					tracks[pose.Name] = list
				end
				table.insert(list, { Time = keyframe.Time, CFrame = pose.CFrame, Style = quad and "Quad" or pose.EasingStyle.Name,
					Direction = quad and "InOut" or pose.EasingDirection.Name })
			end
		end
	end
	for _, list in pairs(tracks) do
		table.sort(list, function(a, b)
			return a.Time < b.Time
		end)
	end
	return { Tracks = tracks, Length = length, Loop = sequence.Loop, Keyframes = count, Priority = sequence.Priority.Name }
end

local function keyframeDriver(data, rig)
	local targets = {}
	for name in pairs(data.Tracks) do
		local part = rig.Model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") and rig.Animated[part] then
			targets[name] = part
		end
	end
	local length = math.max(data.Length, 0.05)
	local driver = { Kind = "Keyframes", Length = length, Period = data.Loop and length or length + ONE_SHOT_HOLD }
	function driver.Sample(time)
		local t = time % driver.Period
		local transforms = {}
		for name, part in pairs(targets) do
			local keys = data.Tracks[name]
			local value = keys[#keys].CFrame
			if t <= keys[1].Time then
				value = keys[1].CFrame
			else
				for index = 1, #keys - 1 do
					local a, b = keys[index], keys[index + 1]
					if t >= a.Time and t < b.Time then
						local alpha = (t - a.Time) / math.max(1e-4, b.Time - a.Time)
						value = a.CFrame:Lerp(b.CFrame, easeAlpha(alpha, a.Style, a.Direction))
						break
					end
				end
			end
			transforms[part] = value
		end
		return transforms
	end
	return driver
end

-- the game's procedural data, re-read from its scripts each time a preview is built
local function heroProcedural()
	return extractLocals(StarterPlayer.StarterPlayerScripts:FindFirstChild("AttackAnimationController"), "-- Init", { "ANIMATIONS", "ITEM_ANIMATIONS", "JOINTS", "poseAt", "mirrorPose" })
end

local function creatureProcedural(kind)
	if kind == "Monster" then
		return extractLocals(StarterPlayer.StarterPlayerScripts:FindFirstChild("MonsterAnimationController"), "-- Initialization",
			{ "walkPose", "attackPose", "deathPose", "findMotor", "LEGS", "ATTACK_TIME", "STRIDE", "DEATH_FADE_END" })
	end
	return extractLocals(StarterPlayer.StarterPlayerScripts:FindFirstChild("MinionAnimationController"), "-- Initialization",
		{ "basePose", "attackPose", "deathPose", "MOTORS", "ATTACK_TIME", "STRIDE", "DEATH_FADE_END" })
end

-- a class attack / Q / item-skill swing (keyframes on R15 joints, as AttackAnimationController)
local function heroSwingDriver(definition, rig, data)
	local keys = definition.Keys
	local mirrored = nil
	if definition.Alternate then
		mirrored = {}
		for index, key in ipairs(keys) do
			mirrored[index] = { T = key.T, Pose = data.mirrorPose(key.Pose) }
		end
	end
	local duration = math.max(0.12, definition.Duration)
	local driver = { Kind = "Procedural", Length = duration, Period = duration + ONE_SHOT_HOLD }
	local model = rig.Model
	function driver.Sample(time)
		local cycle = math.floor(time / driver.Period)
		local alpha = (time - cycle * driver.Period) / duration
		local transforms = {}
		if alpha >= 1 then
			return transforms
		end
		local useKeys = (mirrored and cycle % 2 == 1) and mirrored or keys
		local fromPose, toPose, t = data.poseAt(useKeys, alpha)
		for jointName, partName in pairs(data.JOINTS) do
			local part = model:FindFirstChild(partName)
			if part then
				local a = fromPose and fromPose[jointName] or CFrame.identity
				local b = toPose and toPose[jointName] or CFrame.identity
				transforms[part] = a:Lerp(b, t)
			end
		end
		return transforms
	end
	return driver
end

-- Stone Warden / goblin procedural states driven with the game's own pose functions
local function creatureDriver(kind, model, rig, data, state)
	local motors = {}
	if kind == "Monster" then
		local torso = model:FindFirstChild("Torso")
		motors.Root = torso and torso:FindFirstChild("RootJoint")
		motors.Neck = data.findMotor(model, "Head", "Neck")
		for _, leg in ipairs(data.LEGS) do
			motors[leg .. "_Hip"] = data.findMotor(model, leg .. "U", leg .. "_Hip")
			motors[leg .. "_Knee"] = data.findMotor(model, leg .. "L", leg .. "_Knee")
		end
		if not motors.Root then
			return nil, "this model is not the procedural Stone Warden rig (no Torso.RootJoint)"
		end
	else
		for motorName, partName in pairs(data.MOTORS) do
			local part = model:FindFirstChild(partName)
			motors[motorName] = part and part:FindFirstChild(motorName)
		end
		if not motors.Waist then
			return nil, "this model is not the procedural goblin rig"
		end
	end
	local eye = model:FindFirstChild("Head_Eye")
	local creature = {
		Model = model, Root = rig.Root, Scale = 1, Phase = 0, Move = 0, Alert = 0, Seed = 0, AttackStart = -10,
		AttackSide = kind == "Monster" and 1 or "R", DeathSide = 1, Eye = eye, EyeColor = eye and eye.Color,
		EyeLight = eye and eye:FindFirstChildOfClass("PointLight"), Parts = rig.Parts,
	}
	creature.EyeLightBrightness = creature.EyeLight and creature.EyeLight.Brightness
	local attackPeriod = data.ATTACK_TIME + 0.7
	local deathPeriod = data.DEATH_FADE_END + 0.8
	local driver = { Kind = "Procedural", State = state }
	driver.Length = state == "Death" and deathPeriod or (state == "Attack" and attackPeriod or 2)
	local lastTime, lastCycle, lastDeath = 0, -1, math.huge
	local function resetDeath()
		if creature.Eye and creature.EyeColor then
			creature.Eye.Color = creature.EyeColor
		end
		if creature.EyeLight then
			creature.EyeLight.Brightness = creature.EyeLightBrightness or 1
		end
		creature.DeathBase = nil
		rig.Root.CFrame = rig.RootCFrame
		for _, part in ipairs(rig.Parts) do
			part.LocalTransparencyModifier = 0
		end
	end
	function driver.Sample(time)
		local dt = math.clamp(time - lastTime, 0, 0.25)
		lastTime = time
		local pose = {}
		if driver.State == "Death" then
			local since = time % deathPeriod
			if since < lastDeath then
				resetDeath()
			end
			lastDeath = since
			data.deathPose(creature, since, pose)
		else
			local walking = driver.State == "Walk"
			creature.Move = walking and 1 or 0
			creature.Phase = (creature.Phase + (walking and 6 or 0) * dt / (data.STRIDE * creature.Scale)) % 1
			if kind == "Monster" then
				data.walkPose(creature, time, pose)
			else
				data.basePose(creature, time, pose)
			end
			if driver.State == "Attack" then
				local cycle = math.floor(time / attackPeriod)
				if cycle ~= lastCycle then
					lastCycle = cycle
					creature.AttackStart = cycle * attackPeriod
					if kind == "Monster" then
						creature.AttackSide = -creature.AttackSide
					else
						creature.AttackSide = creature.AttackSide == "R" and "L" or "R"
					end
				end
				data.attackPose(creature, time, pose)
			end
		end
		local transforms = {}
		for name, motor in pairs(motors) do
			if motor and pose[name] and motor.Part1 then
				transforms[motor.Part1] = pose[name]
			end
		end
		return transforms
	end
	function driver.Reset()
		resetDeath()
		lastDeath = math.huge
	end
	return driver
end

--------------------------------------------------------------------------------------------------
-- Building preview models
--------------------------------------------------------------------------------------------------
local function stripScripts(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
end

local function buildHero(classKey, teamColor)
	local factoryModule = ServerScriptService:FindFirstChild("CharacterFactory")
	if not factoryModule then
		return nil, "ServerScriptService.CharacterFactory not found"
	end
	local ok, factory = pcall(freshRequire, factoryModule)
	if not ok then
		return nil, "CharacterFactory: " .. tostring(factory)
	end
	local okModel, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(factory.BuildDescription(classKey), Enum.HumanoidRigType.R15)
	end)
	if not okModel or not model then
		return nil, "could not build the rig: " .. tostring(model)
	end
	factory.PrepareHumanoid(model)
	local okLook, lookError = pcall(factory.ApplyClassLook, model, classKey, teamColor, false)
	if not okLook then
		warn("[Asset Viewer] class look failed:", lookError)
	end
	model.Name = classKey
	model:SetAttribute("Class", classKey)
	stripScripts(model)
	return model
end

local function loadClassDefinitions()
	local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("ClassDefinitions")
	if not module then
		return nil
	end
	local ok, defs = pcall(freshRequire, module)
	return ok and defs or nil
end

local function loadTeams()
	local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Constants")
	local ok, constants = pcall(function()
		return freshRequire(module)
	end)
	if ok and constants and constants.Teams then
		return constants.Teams
	end
	return { { Name = "Crimson", Color = Color3.fromRGB(235, 70, 70) }, { Name = "Azure", Color = Color3.fromRGB(70, 150, 255) } }
end

local function animationSlotId(key)
	local folder = ReplicatedStorage:FindFirstChild("RuinfallAnimations")
	local slot = folder and folder:FindFirstChild(key)
	if slot and slot:IsA("Animation") and slot.AnimationId ~= "" then
		return slot.AnimationId
	end
	return nil
end

-- stored versions of an animation slot (KeyframeSequences in ServerStorage.RuinfallAnimationVersions.<Slot>),
-- e.g. the original and the Blender-improved Marksman attack, ordered by their Order attribute
local function animationVersions(key)
	local root = ServerStorage:FindFirstChild(VERSIONS_FOLDER)
	local folder = root and key and root:FindFirstChild(key)
	local list = {}
	for _, child in ipairs(folder and folder:GetChildren() or {}) do
		if child:IsA("KeyframeSequence") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = a:GetAttribute("Order") or 100, b:GetAttribute("Order") or 100
		if oa ~= ob then
			return oa < ob
		end
		return a.Name < b.Name
	end)
	return list
end

-- stores a copy of a KeyframeSequence as a new version of a slot
local function addAnimationVersion(key, sequence)
	local root = ServerStorage:FindFirstChild(VERSIONS_FOLDER)
	if not root then
		root = Instance.new("Folder")
		root.Name = VERSIONS_FOLDER
		root.Parent = ServerStorage
	end
	local folder = root:FindFirstChild(key)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = key
		folder.Parent = root
	end
	local base = (sequence.Name ~= "" and sequence.Name ~= "KeyframeSequence") and sequence.Name or "Version"
	local name, n = base, 1
	while folder:FindFirstChild(name) do
		n += 1
		name = base .. " " .. n
	end
	local copy = sequence:Clone()
	copy.Name = name
	copy:SetAttribute("Source", "added from " .. sequence:GetFullName())
	copy:SetAttribute("Order", #animationVersions(key) + 1)
	copy:SetAttribute("AddedAt", os.time())
	copy.Parent = folder
	ChangeHistoryService:SetWaypoint("Asset Viewer: add animation version " .. key .. "/" .. name)
	return copy
end

-- which class carries the item that grants a skill (for Skill_<Id> previews)
local function skillClass(abilityId)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("ItemDefinitions")
	local ok, defs = pcall(function()
		return require(module)
	end)
	if ok and defs and defs.Items then
		for _, item in pairs(defs.Items) do
			if item.Ability == abilityId and item.Class then
				return item.Class, item.Name
			end
		end
		for _, item in pairs(defs.Items) do
			if item.Ability == abilityId then
				return nil, item.Name
			end
		end
	end
	return nil, nil
end

--------------------------------------------------------------------------------------------------
-- Changing icons (a PNG from disk or an asset id) and keeping every previous icon
--------------------------------------------------------------------------------------------------
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

-- every script line, GUI and texture that shows `oldId` now shows `newId`
local function replaceImageEverywhere(oldId, newId)
	local scripts, instances = 0, 0
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
							local updated = replaceId(source, oldId, newId)
							if updated ~= source then
								writeSource(descendant, updated)
								scripts += 1
							end
						end
					else
						for _, property in ipairs(IMAGE_EDIT_PROPERTIES) do
							local okRead, value = pcall(function()
								return descendant[property]
							end)
							if okRead and type(value) == "string" then
								local updated = replaceId(value, oldId, newId)
								if updated ~= value and pcall(function()
									descendant[property] = updated
								end) then
									instances += 1
								end
							end
						end
					end
				end
			end
		end
	end
	return scripts, instances
end

-- history is saved in the place (ServerStorage.AssetViewerHistory), one folder per icon slot
local function historyKeyFor(entry)
	return (entry.Group or "Images") .. ": " .. tostring(entry.Label)
end

local function historyFolder(key, create)
	local root = ServerStorage:FindFirstChild(HISTORY_FOLDER)
	if not root then
		if not create then
			return nil
		end
		root = Instance.new("Folder")
		root.Name = HISTORY_FOLDER
		root.Parent = ServerStorage
	end
	local name = string.sub(string.gsub(key, "[^%w%-_ :%.]", "_"), 1, 90)
	local folder = root:FindFirstChild(name)
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = name
		folder:SetAttribute("Slot", key)
		folder.Parent = root
	end
	return folder
end

-- previous icons of a slot, newest first: { Id, At, By, Note, Instance }
local function getHistory(key)
	local folder = historyFolder(key, false)
	local list = {}
	for _, item in ipairs(folder and folder:GetChildren() or {}) do
		if item:IsA("StringValue") then
			table.insert(list, { Id = item.Value, At = item:GetAttribute("ReplacedAt") or 0, By = item:GetAttribute("ReplacedBy"), Note = item:GetAttribute("Note"), Instance = item })
		end
	end
	table.sort(list, function(a, b)
		return a.At > b.At
	end)
	return list
end

local function addHistory(key, oldId, newId, note)
	local folder = historyFolder(key, true)
	local item = Instance.new("StringValue")
	item.Name = "Previous"
	item.Value = oldId
	item:SetAttribute("ReplacedAt", DateTime.now().UnixTimestamp)
	item:SetAttribute("ReplacedBy", newId)
	item:SetAttribute("Note", note or "")
	item.Parent = folder
	local list = getHistory(key)
	for index = MAX_HISTORY + 1, #list do
		list[index].Instance:Destroy()
	end
end

-- the slot now shows `newId` (digits); the icon it had goes into its history (Ctrl+Z also works)
local function changeImage(entry, newId, note)
	local oldId = entry.Key
	if newId == oldId then
		return false, "That is already the current icon"
	end
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Asset Viewer: change icon " .. tostring(entry.Label))
	end)
	local ok, scripts, instances = pcall(function()
		local changedScripts, changedInstances = replaceImageEverywhere(oldId, newId)
		addHistory(historyKeyFor(entry), oldId, newId, note)
		return changedScripts, changedInstances
	end)
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
		end)
	end
	if not ok then
		return false, "Change failed: " .. tostring(scripts)
	end
	return true, string.format("%s now uses %s (%s). %d script(s) and %d GUI / texture(s) updated - the previous icon is kept in its history.",
		tostring(entry.Label), newId, note or "changed", scripts, instances)
end

-- a Creator Store "Decal" id is not the image id itself: open the decal to find its image
local function imageIdFromAsset(id)
	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if ok and type(objects) == "table" and objects[1] then
		local object = objects[1]
		local decal = object:IsA("Decal") and object or object:FindFirstChildWhichIsA("Decal", true)
		local imageId = decal and string.match(decal.Texture, "%d+")
		if imageId then
			return imageId
		end
	end
	return id
end

-- opens the Windows file picker, uploads the picture to Roblox as an Image asset, returns its id
local function uploadImageFromDisk(defaultName)
	local okPrompt, file = pcall(function()
		return StudioService:PromptImportFileAsync({ "png", "jpg", "jpeg" })
	end)
	if not okPrompt then
		return nil, "could not open the file picker: " .. tostring(file)
	end
	if not file then
		return nil, "cancelled"
	end
	local fileName = string.match(file.Name, "^(.-)%.%w+$") or file.Name
	local okImage, editable = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri(file:GetTemporaryId()))
	end)
	if not okImage or not editable then
		return nil, "could not read " .. file.Name .. " (" .. tostring(editable) .. ") - use a PNG or JPG up to 1024 x 1024"
	end
	local okUpload, result, assetId = pcall(function()
		return AssetService:CreateAssetAsync(editable, Enum.AssetType.Image, {
			Name = "RUINFALL " .. (fileName ~= "" and fileName or tostring(defaultName)),
			Description = "Icon uploaded with the Ruinfall Asset Viewer",
		})
	end)
	pcall(function()
		editable:Destroy()
	end)
	if not okUpload then
		return nil, "upload failed: " .. tostring(result)
	end
	if result ~= Enum.CreateAssetResult.Success or not assetId then
		return nil, "upload not completed (" .. (typeof(result) == "EnumItem" and result.Name or tostring(result)) .. ")"
	end
	return tostring(assetId), file.Name
end

--------------------------------------------------------------------------------------------------
-- Catalogs
--------------------------------------------------------------------------------------------------
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
		owner = nil
	end
	if owner and key and owner ~= key then
		return owner .. " - " .. key
	end
	return key or owner or ("line " .. index)
end

local function catalog(tab)
	local entries = {}
	if tab == "Heroes" then
		local defs = loadClassDefinitions()
		for _, classKey in ipairs(defs and defs.Order or {}) do
			local classDef = defs.Classes[classKey]
			table.insert(entries, { Key = classKey, Label = classDef.DisplayName or classKey, Sub = classDef.Role or "", Image = classDef.IconImage, IconId = digitsOf(classDef.IconImage) })
		end
	elseif tab == "Weapons" or tab == "Props" or tab == "Monsters" then
		local folderName = tab == "Weapons" and "RuinfallWeapons" or (tab == "Props" and "RuinfallAssets" or "MonsterAssets")
		local folder = ServerStorage:FindFirstChild(folderName)
		for _, child in ipairs(folder and folder:GetChildren() or {}) do
			if child:IsA("BasePart") or child:IsA("Model") then
				local group = nil
				local sub
				if tab == "Weapons" then
					sub = (WEAPON_CLASS[child.Name] or "unused") .. " weapon"
				elseif tab == "Props" then
					group = string.match(child.Name, "^([%a]+)_") or "Other"
					sub = child:IsA("BasePart") and vectorText(child.Size) or "model"
				else
					sub = TEMPLATE_KIND[child.Name] == "Monster" and "Jungle monster" or (TEMPLATE_KIND[child.Name] == "Minion" and "Lane minion" or "Creature")
				end
				table.insert(entries, { Key = child.Name, Label = (string.gsub(child.Name, "_", " ")), Sub = sub, Group = group, Instance = child })
			end
		end
		table.sort(entries, function(a, b)
			if (a.Group or "") ~= (b.Group or "") then
				return (a.Group or "") < (b.Group or "")
			end
			return a.Label < b.Label
		end)
	elseif tab == "Animations" then
		local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("AnimationLibrary")
		local ok, library = pcall(function()
			return freshRequire(module)
		end)
		local okSlots, slots = false, nil
		if ok and library then
			okSlots, slots = pcall(library.GetSlots)
		end
		local seen = {}
		local function versionText(key)
			local names = {}
			for _, version in ipairs(animationVersions(key)) do
				table.insert(names, version.Name)
			end
			return #names, table.concat(names, ", ")
		end
		for _, slot in ipairs(okSlots and slots or {}) do
			seen[slot.Key] = true
			local id = animationSlotId(slot.Key)
			local count, names = versionText(slot.Key)
			local sub = id and ("uploaded  " .. id) or "built-in"
			if count > 0 then
				sub ..= "  -  versions: " .. names
			end
			table.insert(entries, { Key = slot.Key, Label = slot.Label, Group = slot.Group, Sub = sub, Custom = id ~= nil, Versions = count > 0 and count or nil })
		end
		-- versions stored for a key that is not (yet) an AnimationLibrary slot
		local versionRoot = ServerStorage:FindFirstChild(VERSIONS_FOLDER)
		for _, folder in ipairs(versionRoot and versionRoot:GetChildren() or {}) do
			local count, names = versionText(folder.Name)
			if not seen[folder.Name] and count > 0 then
				table.insert(entries, { Key = folder.Name, Label = folder.Name, Group = "Stored versions", Sub = "versions: " .. names, Custom = false, Versions = count })
			end
		end
	elseif tab == "Images" then
		local byId = {}
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
						if not byId[id] then
							byId[id] = { Key = id, Label = imageLabel(lines, index, a), Group = spec[2], Image = "rbxassetid://" .. id, Sub = id }
							table.insert(entries, byId[id])
						end
					end
				end
			end
		end
		for _, entry in ipairs(entries) do
			local count = #getHistory(historyKeyFor(entry))
			entry.Sub = entry.Key .. (count > 0 and ("  -  " .. count .. " previous") or "")
		end
	end
	return entries
end

--------------------------------------------------------------------------------------------------
-- UI kit (Studio theme aware)
--------------------------------------------------------------------------------------------------
local Studio = settings().Studio
local FALLBACK_COLORS = {
	MainBackground = Color3.fromRGB(46, 46, 46), Titlebar = Color3.fromRGB(53, 53, 53), MainText = Color3.fromRGB(230, 230, 230),
	DimmedText = Color3.fromRGB(140, 140, 140), SubText = Color3.fromRGB(170, 170, 170), InputFieldBackground = Color3.fromRGB(37, 37, 37),
	InputFieldBorder = Color3.fromRGB(26, 26, 26), Button = Color3.fromRGB(60, 60, 60), ButtonText = Color3.fromRGB(230, 230, 230),
	ButtonBorder = Color3.fromRGB(26, 26, 26), Item = Color3.fromRGB(46, 46, 46), MainButton = Color3.fromRGB(0, 162, 255),
	DialogMainButtonText = Color3.fromRGB(255, 255, 255), ErrorText = Color3.fromRGB(255, 90, 90), LinkText = Color3.fromRGB(80, 160, 255),
	ViewPortBackground = Color3.fromRGB(37, 37, 37),
}

local function themeColor(name, modifier)
	local ok, color = pcall(function()
		return Studio.Theme:GetColor(Enum.StudioStyleGuideColor[name], Enum.StudioStyleGuideModifier[modifier or "Default"])
	end)
	return ok and color or FALLBACK_COLORS[name] or Color3.new(1, 0, 1)
end

local themed = setmetatable({}, { __mode = "k" })
local function paint(instance, property, name, modifier)
	themed[instance] = themed[instance] or {}
	themed[instance][property] = { name, modifier }
	instance[property] = themeColor(name, modifier)
end

local function new(className, properties)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
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
		Size = UDim2.new(0, 80, 0, 24),
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

--------------------------------------------------------------------------------------------------
-- Viewer
--------------------------------------------------------------------------------------------------
local Viewer = {
	Tab = "Heroes", Search = "", Selected = nil, Preview = nil, Clock = 0, Playing = true, Speed = 1,
	TeamIndex = 1, HeroAction = "Idle", CreatureState = "Idle", AnimationSource = "Uploaded", WeaponOnHero = false,
	Entries = {}, Token = 0, Loading = false, AutoRotate = false,
	Busy = false, HistoryPick = nil, IdBoxOpen = false, Message = nil,
}
local UI = {}
local view = { Yaw = math.rad(-30), Pitch = math.rad(-12), Distance = 12, Focus = Vector3.zero, MinDistance = 1, MaxDistance = 200 }

local function updateCamera()
	if not UI.Camera then
		return
	end
	local rotation = CFrame.Angles(0, view.Yaw, 0) * CFrame.Angles(view.Pitch, 0, 0)
	UI.Camera.CFrame = CFrame.new(view.Focus) * rotation * CFrame.new(0, 0, view.Distance)
	UI.Camera.Focus = CFrame.new(view.Focus)
end

local function frameBox(boxCFrame, boxSize)
	view.Focus = boxCFrame.Position
	local radius = math.max(0.5, boxSize.Magnitude / 2)
	view.Distance = radius / math.tan(math.rad(20)) * 1.15
	view.MinDistance = radius * 0.6
	view.MaxDistance = radius * 12
	view.Yaw, view.Pitch = math.rad(-30), math.rad(-12)
	if UI.Ground then
		UI.Ground.Size = Vector3.new(0.2, radius * 3, radius * 3)
		UI.Ground.CFrame = CFrame.new(boxCFrame.Position.X, boxCFrame.Position.Y - boxSize.Y / 2 - 0.12, boxCFrame.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	updateCamera()
end

local function frameModel(instance)
	if instance:IsA("Model") then
		frameBox(instance:GetBoundingBox())
	else
		frameBox(instance.CFrame, instance.Size)
	end
end

-- preview object: { Model, Rig, Driver, Title, Sub, Info = {{k, v}}, Usages, Controls, Image }
-- Compare: every stored version of a slot playing side by side (first version on the main rig)
local function clearCompare(preview)
	if not preview then
		return
	end
	for _, extra in ipairs(preview.Compare or {}) do
		if extra.Model then
			extra.Model:Destroy()
		end
		if extra.Ring then
			extra.Ring:Destroy()
		end
	end
	preview.Compare = nil
	if preview.CompareRing then
		preview.CompareRing:Destroy()
		preview.CompareRing = nil
	end
	if preview.CompareShifted and preview.Rig then
		preview.CompareShifted = nil
		preview.Rig.Root.CFrame = preview.Rig.RootCFrame
		if preview.Model then
			frameModel(preview.Model)
		end
	end
end

local function compareRing(position, color)
	local ring = Instance.new("Part")
	ring.Name = "CompareRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.1, 3.4, 3.4)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = UI.Viewport
	return ring
end

-- returns the main rig's driver and a note naming which rig is which
local function startCompare(preview, versions)
	local rig, model = preview.Rig, preview.Model
	local boxCFrame, boxSize = model:GetBoundingBox()
	local floorY = boxCFrame.Position.Y - boxSize.Y / 2 + 0.06
	local base = rig.RootCFrame
	local count = #versions
	-- left to right as the camera sees it (frameBox resets the view to its default angle)
	local right = CFrame.Angles(0, math.rad(-30), 0) * Vector3.new(1, 0, 0)
	local datas, period = {}, 0
	for index, version in ipairs(versions) do
		datas[index] = readSequence(version)
		period = math.max(period, datas[index].Length)
	end
	period += ONE_SHOT_HOLD
	preview.Compare = {}
	local legend, mainDriver = {}, nil
	for index, version in ipairs(versions) do
		local offset = right * ((index - (count + 1) / 2) * COMPARE_GAP)
		local color = COMPARE_COLORS[(index - 1) % #COMPARE_COLORS + 1]
		local ring = compareRing(Vector3.new(base.Position.X + offset.X, floorY, base.Position.Z + offset.Z), color)
		local targetRig
		if index == 1 then
			rig.Root.CFrame = base + offset
			preview.CompareShifted = true
			preview.CompareRing = ring
			targetRig = rig
		else
			local clone = model:Clone()
			clone.Parent = UI.Viewport
			local cloneRoot = clone:FindFirstChild(rig.Root.Name, true)
			if cloneRoot then
				cloneRoot.CFrame = base + offset
			end
			targetRig = buildRig(clone)
			targetRig.RootCFrame = base + offset
			table.insert(preview.Compare, { Model = clone, Rig = targetRig, Ring = ring })
		end
		local driver = keyframeDriver(datas[index], targetRig)
		driver.Period = period -- same cycle for every rig so they stay in sync
		if index == 1 then
			mainDriver = driver
		else
			preview.Compare[#preview.Compare].Driver = driver
		end
		table.insert(legend, string.format("%s = %s ring (%.2fs%s)", version.Name, COMPARE_COLOR_NAMES[(index - 1) % #COMPARE_COLOR_NAMES + 1],
			datas[index].Length, version:GetAttribute("InGame") and ", in game now" or ""))
	end
	frameBox(CFrame.new(base.Position.X, boxCFrame.Position.Y, base.Position.Z), boxSize + Vector3.new(COMPARE_GAP * (count - 1), 0, 0))
	return mainDriver, "compare, left to right: " .. table.concat(legend, "  |  ")
end

local function clearPreview()
	local preview = Viewer.Preview
	Viewer.Preview = nil
	clearCompare(preview)
	if preview and preview.Model then
		preview.Model:Destroy()
	end
end

local function setDriver(preview, driver, note)
	preview.Driver = driver
	preview.DriverNote = note
	Viewer.Clock = 0
	if preview.Rig then
		applyPose(preview.Rig, driver and driver.Sample(0) or {})
	end
end

-- hero animation for an action: uploaded slot, else the built-in (default keyframes / procedural)
local function heroDriverFor(preview, classKey, action, source)
	local rig = preview.Rig
	local key = classKey .. "_" .. action
	local uploaded = animationSlotId(key)
	if uploaded and source ~= "Built-in" then
		local data, err = loadKeyframes(uploaded)
		if data then
			return keyframeDriver(data, rig), string.format("uploaded %s  -  %.2fs, %d keyframes%s", uploaded, data.Length, data.Keyframes, data.Loop and ", looped" or "")
		end
		return nil, "uploaded " .. uploaded .. ": " .. tostring(err)
	end
	if action == "Idle" or action == "Run" then
		local id = action == "Idle" and DEFAULT_IDLE or DEFAULT_RUN
		local data, err = loadKeyframes(id)
		if data then
			return keyframeDriver(data, rig), "built-in: Roblox default " .. string.lower(action) .. " (" .. id .. ")"
		end
		return nil, tostring(err)
	end
	local procedural, err = heroProcedural()
	if not procedural then
		return nil, "built-in swing unavailable: " .. tostring(err)
	end
	local definition
	if action == "Skill" then
		definition = procedural.ITEM_ANIMATIONS[preview.SkillId or ""]
		if not definition then
			local classSet = procedural.ANIMATIONS[classKey]
			definition = classSet and classSet.Ability
		end
	else
		local classSet = procedural.ANIMATIONS[classKey]
		definition = classSet and classSet[action]
	end
	if not definition then
		return nil, "no built-in animation for " .. key
	end
	return heroSwingDriver(definition, rig, procedural), string.format("built-in procedural swing  -  %.2fs (AttackAnimationController)", definition.Duration)
end

local function creatureDriverFor(preview, kind, state, source)
	local key = kind .. "_" .. state
	local uploaded = animationSlotId(key)
	if uploaded and source ~= "Built-in" then
		local data, err = loadKeyframes(uploaded)
		if data then
			return keyframeDriver(data, preview.Rig), string.format("uploaded %s  -  %.2fs, %d keyframes", uploaded, data.Length, data.Keyframes)
		end
		return nil, "uploaded " .. uploaded .. ": " .. tostring(err)
	end
	local data, err = creatureProcedural(kind)
	if not data then
		return nil, "built-in animation unavailable: " .. tostring(err)
	end
	local driver, reason = creatureDriver(kind, preview.Model, preview.Rig, data, state)
	if not driver then
		return nil, reason
	end
	return driver, "built-in procedural " .. string.lower(state) .. " (" .. (kind == "Monster" and "MonsterAnimationController" or "MinionAnimationController") .. ")"
end

local function usageTokensFor(tab, entry)
	local tokens = {}
	if tab == "Images" then
		table.insert(tokens, { Text = entry.Key, Digits = true })
	elseif entry.Instance then
		table.insert(tokens, { Text = entry.Key })
		local mesh = entry.Instance:IsA("MeshPart") and digitsOf(entry.Instance.MeshId)
		if mesh then
			table.insert(tokens, { Text = mesh, Digits = true })
		end
	elseif tab == "Heroes" then
		table.insert(tokens, { Text = entry.Key })
	elseif tab == "Animations" then
		table.insert(tokens, { Text = entry.Key })
		local id = digitsOf(animationSlotId(entry.Key))
		if id then
			table.insert(tokens, { Text = id, Digits = true })
		end
	end
	return tokens
end

local function partInfo(part, info)
	table.insert(info, { "Class", part.ClassName })
	table.insert(info, { "Size", vectorText(part.Size) })
	if part:IsA("MeshPart") then
		table.insert(info, { "Mesh", part.MeshId ~= "" and part.MeshId or "-" })
		table.insert(info, { "Texture", part.TextureID ~= "" and part.TextureID or "-" })
	end
	local look = part:FindFirstChildOfClass("SurfaceAppearance")
	if look then
		table.insert(info, { "SurfaceAppearance", "yes (PBR textures)" })
	end
	table.insert(info, { "Material", part.Material.Name })
	for key, value in pairs(part:GetAttributes()) do
		table.insert(info, { "Attribute " .. key, tostring(value) })
	end
end

local function modelStats(model, info)
	local parts, motors, kinds = 0, 0, {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts += 1
			local kind = descendant:GetAttribute("Kind")
			if kind then
				kinds[kind] = (kinds[kind] or 0) + 1
			end
		elseif descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			motors += 1
		end
	end
	local _, size = model:GetBoundingBox()
	table.insert(info, { "Parts / joints", parts .. " / " .. motors })
	table.insert(info, { "Size", vectorText(size) })
	local kindText = {}
	for kind, count in pairs(kinds) do
		table.insert(kindText, kind .. " " .. count)
	end
	if #kindText > 0 then
		table.sort(kindText)
		table.insert(info, { "Recolour parts (Kind)", table.concat(kindText, ", ") })
	end
end

-- builds the preview for the selected entry (yields for rigs / animations)
local function buildPreview(tab, entry)
	local preview = { Tab = tab, Entry = entry, Title = entry.Label, Sub = entry.Sub or "", Info = {}, Controls = {} }
	local info = preview.Info
	if tab == "Images" then
		preview.Image = entry.Image
		preview.ImageSlot = entry
		preview.History = getHistory(historyKeyFor(entry))
		table.insert(info, { "Asset id", entry.Image })
		table.insert(info, { "Group", entry.Group or "-" })
		table.insert(info, { "First use", entry.Label })
	elseif tab == "Heroes" then
		local teams = loadTeams()
		local team = teams[Viewer.TeamIndex] or teams[1]
		local model, err = buildHero(entry.Key, team.Color)
		if not model then
			preview.Error = err
			return preview
		end
		preview.Model = model
		preview.ClassKey = entry.Key
		if entry.IconId then
			-- the class emblem (lobby, HUD portrait, hub) can be changed from here too
			for _, imageEntry in ipairs(catalog("Images")) do
				if imageEntry.Key == entry.IconId then
					preview.ImageSlot = imageEntry
					preview.History = getHistory(historyKeyFor(imageEntry))
					break
				end
			end
			table.insert(info, { "Icon", "rbxassetid://" .. entry.IconId })
		end
		local defs = loadClassDefinitions()
		local classDef = defs and defs.Classes[entry.Key]
		if classDef then
			table.insert(info, { "Role", classDef.Role or "-" })
			table.insert(info, { "Health / armor", tostring(classDef.MaxHealth) .. " / " .. tostring(classDef.Armor) })
			table.insert(info, { "Attack", string.format("%s %s dmg, range %s, every %ss", tostring(classDef.AttackType), tostring(classDef.AttackDamage), tostring(classDef.AttackRange), tostring(classDef.AttackCooldown)) })
			if classDef.MagicPower then
				table.insert(info, { "Magic Power", tostring(classDef.MagicPower) })
			end
			table.insert(info, { "Move speed", tostring(classDef.MoveSpeed) })
			if classDef.Ability then
				table.insert(info, { "Q", (classDef.Ability.Name or "-") .. " - " .. (classDef.Ability.Description or "") })
			end
		end
		local weapons = {}
		local gear = model:FindFirstChild("ClassGear")
		for _, part in ipairs(gear and gear:GetChildren() or {}) do
			if string.sub(part.Name, 1, 7) == "Weapon_" then
				table.insert(weapons, string.sub(part.Name, 8))
			end
		end
		table.insert(info, { "Weapons", #weapons > 0 and table.concat(weapons, ", ") or "primitive gear only" })
		for _, action in ipairs({ "Idle", "Run", "Attack", "Ability" }) do
			local id = animationSlotId(entry.Key .. "_" .. action)
			table.insert(info, { "Anim " .. entry.Key .. "_" .. action, id and ("uploaded " .. id) or "built-in" })
		end
		table.insert(info, { "Team colour", team.Name })
	elseif tab == "Weapons" then
		local source = entry.Instance
		partInfo(source, info)
		table.insert(info, 1, { "Carried by", WEAPON_CLASS[entry.Key] or "no class (not in CharacterFactory)" })
		local classKey = WEAPON_CLASS[entry.Key]
		if Viewer.WeaponOnHero and classKey then
			local teams = loadTeams()
			local model, err = buildHero(classKey, (teams[Viewer.TeamIndex] or teams[1]).Color)
			if not model then
				preview.Error = err
				return preview
			end
			preview.Model = model
			preview.ClassKey = classKey
		else
			local clone = source:Clone()
			clone.CFrame = CFrame.new()
			local holder = new("Model", { Name = entry.Key })
			clone.Parent = holder
			holder.PrimaryPart = clone
			preview.Model = holder
		end
	elseif tab == "Props" then
		local source = entry.Instance
		if source:IsA("BasePart") then
			partInfo(source, info)
			local clone = source:Clone()
			clone.CFrame = CFrame.new(0, source.Size.Y / 2, 0)
			local holder = new("Model", { Name = entry.Key })
			clone.Parent = holder
			holder.PrimaryPart = clone
			preview.Model = holder
		else
			local clone = source:Clone()
			stripScripts(clone)
			modelStats(clone, info)
			preview.Model = clone
		end
	elseif tab == "Monsters" then
		local clone = entry.Instance:Clone()
		stripScripts(clone)
		modelStats(clone, info)
		preview.Model = clone
		preview.CreatureKind = TEMPLATE_KIND[entry.Key] or "Monster"
		local torso = clone:FindFirstChild("Torso")
		local procedural = (preview.CreatureKind == "Monster" and torso and torso:FindFirstChild("RootJoint") ~= nil)
			or (preview.CreatureKind == "Minion" and clone:FindFirstChild("Torso") and clone.Torso:FindFirstChild("Waist") ~= nil)
		table.insert(info, 1, { "Used as", preview.CreatureKind == "Monster" and "jungle monster (MonsterService)" or "lane minion (CreepService)" })
		table.insert(info, { "Built-in animation", procedural and "yes - procedural rig" or "no - needs uploaded " .. preview.CreatureKind .. "_* animations" })
		for _, state in ipairs({ "Idle", "Walk", "Attack", "Death" }) do
			local id = animationSlotId(preview.CreatureKind .. "_" .. state)
			table.insert(info, { "Anim " .. preview.CreatureKind .. "_" .. state, id and ("uploaded " .. id) or "built-in" })
		end
	elseif tab == "Animations" then
		local prefix, rest = string.match(entry.Key, "^(%a+)_(.+)$")
		preview.SlotKey = entry.Key
		local uploaded = animationSlotId(entry.Key)
		table.insert(info, { "Slot", entry.Key })
		table.insert(info, { "Uploaded", uploaded or "none (built-in plays)" })
		for _, version in ipairs(animationVersions(entry.Key)) do
			local okData, data = pcall(readSequence, version)
			table.insert(info, { "Version " .. version.Name, string.format("%s%s  -  %s", okData and string.format("%.2fs, %d keyframes", data.Length, data.Keyframes) or "unreadable",
				version:GetAttribute("InGame") and ", IN GAME NOW" or "", tostring(version:GetAttribute("Source") or version:GetFullName())) })
		end
		local teams = loadTeams()
		local teamColor = (teams[Viewer.TeamIndex] or teams[1]).Color
		if prefix == "Monster" or prefix == "Minion" then
			local folder = ServerStorage:FindFirstChild("MonsterAssets")
			local template = folder and folder:FindFirstChild(CREATURE_TEMPLATE[prefix])
			if not template then
				preview.Error = "template " .. CREATURE_TEMPLATE[prefix] .. " not found in ServerStorage.MonsterAssets"
				return preview
			end
			preview.Model = template:Clone()
			stripScripts(preview.Model)
			preview.CreatureKind = prefix
			preview.CreatureStateFixed = rest
			table.insert(info, { "Played by", "CustomAnimationController (uploaded) / " .. (prefix == "Monster" and "MonsterAnimationController" or "MinionAnimationController") .. " (built-in)" })
		elseif prefix == "Skill" then
			local classKey, itemName = skillClass(rest)
			preview.SkillId = rest
			preview.ClassKey = classKey or "Fighter"
			local model, err = buildHero(preview.ClassKey, teamColor)
			if not model then
				preview.Error = err
				return preview
			end
			preview.Model = model
			preview.HeroActionFixed = "Skill"
			table.insert(info, { "Item", (itemName or "?") .. (classKey and (" (" .. classKey .. ")") or " (any class - shown on a Fighter)") })
			table.insert(info, { "Played by", "AttackAnimationController when the skill is cast" })
		else
			local model, err = buildHero(prefix, teamColor)
			if not model then
				preview.Error = err
				return preview
			end
			preview.Model = model
			preview.ClassKey = prefix
			preview.HeroActionFixed = rest
			local reader = (rest == "Idle" or rest == "Run") and "CustomAnimationController (your hero) and CharacterFactory (bots)" or "AttackAnimationController"
			table.insert(info, { "Played by", reader })
		end
	end
	return preview
end

--------------------------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------------------------
local function buildUI(container)
	local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = container })
	paint(root, "BackgroundColor3", "MainBackground")
	UI.Root = root

	-- top bar: title, tabs, search
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BorderSizePixel = 0, Parent = root })
	paint(top, "BackgroundColor3", "Titlebar")
	label({ Text = "RUINFALL ASSET VIEWER", Font = Enum.Font.SourceSansBold, TextSize = 15, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 170, 1, 0), Parent = top })
	local tabBar = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(182, 6), Size = UDim2.new(1, -372, 0, 24), Parent = top })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabBar })
	local tabButtons = {}
	for _, tab in ipairs(TABS) do
		tabButtons[tab] = button(tab, { Size = UDim2.new(1 / #TABS, -4, 1, 0), TextSize = 13, Parent = tabBar })
	end
	local search = new("TextBox", {
		Text = "", PlaceholderText = "Search...", ClearTextOnFocus = false, Font = Enum.Font.SourceSans, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(1, -182, 0, 6), Size = UDim2.new(0, 174, 0, 24), Parent = top,
	})
	paint(search, "BackgroundColor3", "InputFieldBackground")
	paint(search, "TextColor3", "MainText")
	paint(search, "PlaceholderColor3", "DimmedText")
	corner(search, 4)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = search })

	-- left: list
	local LIST_WIDTH = 270
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 42), Size = UDim2.new(0, LIST_WIDTH, 1, -48), BorderSizePixel = 0, ScrollBarThickness = 8,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = root,
	})
	paint(list, "BackgroundColor3", "InputFieldBackground")
	paint(list, "ScrollBarImageColor3", "DimmedText")
	UI.List = list

	-- right: title, viewport / image, controls, info
	local INFO_HEIGHT = 190
	local right = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(LIST_WIDTH + 14, 42), Size = UDim2.new(1, -(LIST_WIDTH + 20), 1, -48), Parent = root })
	local title = label({ Text = "Select an asset", Font = Enum.Font.SourceSansBold, TextSize = 17, Size = UDim2.new(1, 0, 0, 20), Parent = right })
	local subtitle = label({ Text = "", TextSize = 13, ColorName = "DimmedText", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16), Parent = right })
	local stage = new("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -(40 + 34 + INFO_HEIGHT + 6)), BorderSizePixel = 0, ClipsDescendants = true, Parent = right })
	paint(stage, "BackgroundColor3", "ViewPortBackground")
	corner(stage, 6)
	local viewport = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 150, 160), LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.5), Parent = stage,
	})
	local camera = new("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = camera
	local ground = new("Part", { Shape = Enum.PartType.Cylinder, Anchored = true, Color = Color3.fromRGB(70, 72, 80), Material = Enum.Material.SmoothPlastic, Transparency = 0.25, Size = Vector3.new(0.2, 8, 8), Parent = viewport })
	UI.Viewport, UI.Camera, UI.Ground = viewport, camera, ground
	local bigImage = new("ImageLabel", { Size = UDim2.new(1, -24, 1, -24), Position = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false, Parent = stage })
	UI.BigImage = bigImage
	local overlay = label({ Text = "", TextSize = 16, Font = Enum.Font.SourceSansSemibold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = stage })
	local hint = label({ Text = "Drag to rotate - wheel to zoom", TextSize = 12, ColorName = "DimmedText", Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16), Parent = stage })
	local status = label({ Text = "", TextSize = 12, ColorName = "SubText", TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16), Parent = stage })

	local controls = new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 1, -(34 + INFO_HEIGHT)), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, Parent = right,
	})
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center, Parent = controls })
	local infoFrame = new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 1, -INFO_HEIGHT), Size = UDim2.new(1, 0, 0, INFO_HEIGHT), BorderSizePixel = 0, ScrollBarThickness = 6,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = right,
	})
	paint(infoFrame, "BackgroundColor3", "Titlebar")
	corner(infoFrame, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = infoFrame })
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = infoFrame })

	-- orbit / zoom
	local dragging, lastPosition = false, nil
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging, lastPosition = true, input.Position
			Viewer.AutoRotate = false
		end
	end)
	viewport.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
		end
	end)
	viewport.MouseLeave:Connect(function()
		dragging = false
	end)
	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging and lastPosition then
			local delta = input.Position - lastPosition
			lastPosition = input.Position
			view.Yaw -= delta.X * 0.012
			view.Pitch = math.clamp(view.Pitch - delta.Y * 0.012, -1.35, 1.35)
			updateCamera()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			view.Distance = math.clamp(view.Distance * (1 - input.Position.Z * 0.12), view.MinDistance, view.MaxDistance)
			updateCamera()
		end
	end)

	-- rendering ----------------------------------------------------------------------------------
	local listItems = {}
	local refreshControls -- forward
	local renderInfo -- forward
	local showHistoryPick -- forward

	local function setStatus(text)
		status.Text = text or ""
	end
	UI.SetStatus = setStatus

	local function openUsage(usage)
		if usage.Script then
			local ok = pcall(function()
				plugin:OpenScript(usage.Script, usage.Line)
			end)
			if not ok then
				Selection:Set({ usage.Script })
			end
		elseif usage.Instance then
			Selection:Set({ usage.Instance })
		end
	end

	renderInfo = function(preview)
		for _, child in ipairs(infoFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if not preview then
			return
		end
		local order = 0
		local function line(key, value)
			order += 1
			local row = label({ Text = "<b>" .. escapeRich(key) .. ":</b>  " .. escapeRich(value), RichText = true, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order, Parent = infoFrame })
			row.TextTruncate = Enum.TextTruncate.AtEnd
		end
		if Viewer.Message then
			order += 1
			local message = label({ Text = Viewer.Message.Text, TextSize = 13, Font = Enum.Font.SourceSansSemibold, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
				AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = order, Parent = infoFrame })
			message.TextColor3 = Viewer.Message.Ok and Color3.fromRGB(80, 200, 120) or themeColor("ErrorText")
		end
		if preview.ImageSlot then
			local history = preview.History or {}
			order += 1
			label({ Text = #history > 0 and string.format("ICON HISTORY (%d)  -  click one to look at it, then Restore", #history) or "ICON HISTORY  -  every icon you replace is kept here",
				Font = Enum.Font.SourceSansBold, TextSize = 12, ColorName = "DimmedText", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, Parent = infoFrame })
			if #history > 0 then
				order += 1
				local strip = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 72), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, LayoutOrder = order, Parent = infoFrame })
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = strip })
				for _, item in ipairs(history) do
					local picked = Viewer.HistoryPick ~= nil and Viewer.HistoryPick.Instance == item.Instance
					local cell = new("ImageButton", { Image = "rbxassetid://" .. item.Id, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(52, 52), AutoButtonColor = true, Parent = strip })
					paint(cell, "BackgroundColor3", "Item", picked and "Selected" or "Default")
					corner(cell, 4)
					if picked then
						new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(0, 162, 255), Parent = cell })
					end
					local when = ""
					pcall(function()
						when = DateTime.fromUnixTimestamp(item.At):FormatLocalTime("MMM D HH:mm", "en-us")
					end)
					label({ Text = when, TextSize = 10, ColorName = "DimmedText", TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, -6, 1, 2), Size = UDim2.new(1, 12, 0, 12), Parent = cell })
					cell.MouseButton1Click:Connect(function()
						Viewer.HistoryPick = item
						showHistoryPick()
					end)
				end
			end
		end
		if preview.DriverNote then
			line("Playing", preview.DriverNote)
		end
		for _, pair in ipairs(preview.Info or {}) do
			line(pair[1], pair[2])
		end
		order += 1
		local header = label({ Text = preview.Usages and string.format("USED IN (%d%s)", #preview.Usages, preview.UsagesCapped and "+" or "") or "USED IN (searching...)",
			Font = Enum.Font.SourceSansBold, TextSize = 12, ColorName = "DimmedText", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, Parent = infoFrame })
		header.TextYAlignment = Enum.TextYAlignment.Bottom
		for _, usage in ipairs(preview.Usages or {}) do
			order += 1
			local text
			if usage.Script then
				text = string.format("%s:%d   %s", usage.Script:GetFullName(), usage.Line, usage.Text)
			else
				text = string.format("%s  (%s)", usage.Instance:GetFullName(), usage.Property)
			end
			local link = new("TextButton", { Text = text, Font = Enum.Font.Code, TextSize = 12, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order, AutoButtonColor = false, Parent = infoFrame })
			paint(link, "TextColor3", "LinkText")
			link.MouseButton1Click:Connect(function()
				openUsage(usage)
			end)
		end
		if preview.Usages and #preview.Usages == 0 then
			order += 1
			label({ Text = "not referenced by name or id in any script / GUI", TextSize = 12, ColorName = "DimmedText", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order, Parent = infoFrame })
		end
	end
	UI.RenderInfo = renderInfo

	-- looking at an earlier icon (before restoring it)
	showHistoryPick = function()
		local preview = Viewer.Preview
		local pick = Viewer.HistoryPick
		if not preview or not pick then
			return
		end
		local when = ""
		pcall(function()
			when = DateTime.fromUnixTimestamp(pick.At):FormatLocalTime("LLL", "en-us")
		end)
		if preview.Image then
			bigImage.Image = "rbxassetid://" .. pick.Id
		end
		subtitle.Text = "Earlier icon rbxassetid://" .. pick.Id .. "  -  replaced " .. when .. "  -  press Restore this version to use it again"
		renderInfo(preview)
		refreshControls()
	end

	local function backToCurrent()
		local preview = Viewer.Preview
		Viewer.HistoryPick = nil
		if preview then
			if preview.Image then
				bigImage.Image = preview.Image
			end
			subtitle.Text = preview.Sub or ""
			renderInfo(preview)
		end
		refreshControls()
	end

	local function showPreview(preview)
		clearPreview()
		Viewer.Preview = preview
		title.Text = preview.Title or ""
		subtitle.Text = preview.Sub or ""
		bigImage.Visible = preview.Image ~= nil
		viewport.Visible = preview.Image == nil
		hint.Visible = preview.Image == nil and preview.Model ~= nil
		overlay.Text = preview.Error and ("Could not preview: " .. preview.Error) or ""
		if preview.Image then
			bigImage.Image = preview.Image
		end
		if preview.Model then
			local model = preview.Model
			if model:IsA("Model") and (preview.ClassKey or preview.CreatureKind) then
				model:PivotTo(CFrame.Angles(0, math.pi, 0))
			end
			model.Parent = viewport
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true -- posed by the viewer, never simulated
				end
			end
			preview.Rig = buildRig(model)
			frameModel(model)
		end
		renderInfo(preview)
		refreshControls()
	end

	-- (re)picks the animation for the current preview
	local function applyAnimation()
		local preview = Viewer.Preview
		if not preview or not preview.Rig then
			return
		end
		local driver, note = nil, nil
		clearCompare(preview)
		-- a stored version (or all of them side by side)
		if preview.Tab == "Animations" and preview.SlotKey then
			local versions = animationVersions(preview.SlotKey)
			local wanted = string.match(Viewer.AnimationSource or "", "^Version:(.+)$")
			if Viewer.AnimationSource == "Compare" and #versions > 0 then
				local ok, a, b = pcall(startCompare, preview, versions)
				if ok then
					driver, note = a, b
				else
					clearCompare(preview)
					note = "compare failed: " .. tostring(a)
				end
			elseif wanted then
				for _, version in ipairs(versions) do
					if version.Name == wanted then
						local data = readSequence(version)
						driver = keyframeDriver(data, preview.Rig)
						note = string.format("version %s  -  %.2fs, %d keyframes%s", version.Name, data.Length, data.Keyframes,
							version:GetAttribute("InGame") and "  (this is what the game plays now)" or "")
					end
				end
			end
		end
		if driver then
			-- chosen above
		elseif preview.ClassKey and (preview.Tab == "Heroes" or preview.Tab == "Animations" or (preview.Tab == "Weapons" and Viewer.WeaponOnHero)) then
			local action = preview.HeroActionFixed or Viewer.HeroAction
			local source = preview.Tab == "Animations" and Viewer.AnimationSource or "Uploaded"
			driver, note = heroDriverFor(preview, preview.ClassKey, action, source)
		elseif preview.CreatureKind then
			local state = preview.CreatureStateFixed or Viewer.CreatureState
			local source = preview.Tab == "Animations" and Viewer.AnimationSource or "Uploaded"
			driver, note = creatureDriverFor(preview, preview.CreatureKind, state, source)
		end
		if preview.Driver and preview.Driver.Reset then
			preview.Driver.Reset()
		end
		setDriver(preview, driver, note)
		renderInfo(preview)
	end
	UI.ApplyAnimation = applyAnimation

	local function select(entry, keepMessage)
		Viewer.Selected = entry and entry.Key or nil
		Viewer.HistoryPick = nil
		if not keepMessage then
			Viewer.Message = nil
		end
		for _, item in ipairs(listItems) do
			if item.Button then
				paint(item.Button, "BackgroundColor3", "Item", item.Key == Viewer.Selected and "Selected" or "Default")
			end
		end
		if not entry then
			return
		end
		Viewer.Token += 1
		local token = Viewer.Token
		Viewer.Loading = true
		overlay.Text = "Loading..."
		local tab = Viewer.Tab
		task.spawn(function()
			local ok, preview = pcall(buildPreview, tab, entry)
			if token ~= Viewer.Token then
				if ok and preview and preview.Model then
					preview.Model:Destroy()
				end
				return
			end
			Viewer.Loading = false
			if not ok then
				preview = { Title = entry.Label, Sub = entry.Sub, Error = tostring(preview), Info = {} }
			end
			showPreview(preview)
			applyAnimation()
			-- where is it used (slow-ish: scans every script)
			local okUsage, usages, capped = pcall(findUsages, usageTokensFor(tab, entry))
			if token == Viewer.Token then
				preview.Usages = okUsage and usages or {}
				preview.UsagesCapped = okUsage and capped
				renderInfo(preview)
			end
		end)
	end
	UI.Select = select

	local function rebuildList()
		for _, item in ipairs(listItems) do
			item.Instance:Destroy()
		end
		table.clear(listItems)
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("UIGridLayout") or child:IsA("UIListLayout") or child:IsA("UIPadding") then
				child:Destroy()
			end
		end
		local ok, entries = pcall(catalog, Viewer.Tab)
		Viewer.Entries = ok and entries or {}
		if not ok then
			setStatus("list failed: " .. tostring(entries))
		end
		local query = string.lower(Viewer.Search)
		local grid = Viewer.Tab == "Images"
		if grid then
			new("UIGridLayout", { CellSize = UDim2.fromOffset(60, 60), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
			new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), Parent = list })
		else
			new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		end
		local layoutOrder, lastGroup = 0, nil
		for _, entry in ipairs(Viewer.Entries) do
			local haystack = string.lower(entry.Label .. " " .. (entry.Sub or "") .. " " .. entry.Key .. " " .. (entry.Group or ""))
			if query == "" or string.find(haystack, query, 1, true) then
				if not grid and entry.Group and entry.Group ~= lastGroup then
					lastGroup = entry.Group
					layoutOrder += 1
					local groupLabel = label({ Text = string.upper(entry.Group), Font = Enum.Font.SourceSansBold, TextSize = 12, ColorName = "DimmedText",
						Size = UDim2.new(1, -8, 0, 20), LayoutOrder = layoutOrder, Parent = list })
					new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = groupLabel })
					table.insert(listItems, { Instance = groupLabel })
				end
				layoutOrder += 1
				local rowButton
				if grid then
					rowButton = new("ImageButton", { Image = entry.Image, ScaleType = Enum.ScaleType.Fit, LayoutOrder = layoutOrder, AutoButtonColor = true, Parent = list })
					paint(rowButton, "BackgroundColor3", "Item", entry.Key == Viewer.Selected and "Selected" or "Default")
					corner(rowButton, 4)
				else
					rowButton = new("TextButton", { Text = "", AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 40), LayoutOrder = layoutOrder, Parent = list })
					paint(rowButton, "BackgroundColor3", "Item", entry.Key == Viewer.Selected and "Selected" or "Default")
					local textX = 10
					if entry.Image then
						new("ImageLabel", { Image = entry.Image, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(6, 4), Parent = rowButton })
						textX = 44
					elseif entry.Custom ~= nil then
						local badge = label({ Text = entry.Versions and (entry.Versions .. "V") or (entry.Custom and "UP" or "BI"), Font = Enum.Font.SourceSansBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center,
							BackgroundTransparency = 0, Size = UDim2.fromOffset(26, 18), Position = UDim2.fromOffset(8, 11), Parent = rowButton })
						badge.BackgroundColor3 = entry.Versions and Color3.fromRGB(190, 130, 20) or (entry.Custom and Color3.fromRGB(0, 120, 200) or themeColor("Button"))
						corner(badge, 3)
						textX = 42
					end
					label({ Text = entry.Label, Font = Enum.Font.SourceSansSemibold, TextSize = 14, Position = UDim2.fromOffset(textX, 3), Size = UDim2.new(1, -(textX + 6), 0, 18), Parent = rowButton })
					label({ Text = entry.Sub or "", TextSize = 12, ColorName = "DimmedText", Position = UDim2.fromOffset(textX, 21), Size = UDim2.new(1, -(textX + 6), 0, 15), Parent = rowButton })
				end
				rowButton.MouseButton1Click:Connect(function()
					select(entry)
				end)
				table.insert(listItems, { Instance = rowButton, Button = rowButton, Key = entry.Key })
			end
		end
		for tab, tabButton in pairs(tabButtons) do
			paint(tabButton, "BackgroundColor3", tab == Viewer.Tab and "MainButton" or "Button")
			paint(tabButton, "TextColor3", tab == Viewer.Tab and "DialogMainButtonText" or "ButtonText")
		end
		setStatus(#Viewer.Entries .. " " .. string.lower(Viewer.Tab))
	end
	UI.RebuildList = rebuildList

	-- icon change: "file" (Windows file picker -> upload), "id" (paste an id), "restore" (history)
	local function runImageChange(kind, value)
		local preview = Viewer.Preview
		local slot = preview and preview.ImageSlot
		if not slot or Viewer.Busy then
			return
		end
		local pick = Viewer.HistoryPick
		Viewer.Busy = true
		refreshControls()
		task.spawn(function()
			local newId, note, problem = nil, nil, nil
			if kind == "file" then
				local id, detail = uploadImageFromDisk(slot.Label)
				if id then
					newId, note = id, "uploaded " .. tostring(detail)
				else
					problem = detail
				end
			elseif kind == "id" then
				local digits = digitsOf(value)
				if digits then
					newId, note = imageIdFromAsset(digits), "asset id " .. digits
				else
					problem = "Enter an image or decal id (or its Creator Store link)"
				end
			elseif kind == "restore" and pick then
				newId, note = pick.Id, "restored an earlier icon"
			end
			local ok, message = false, problem
			if newId then
				ok, message = changeImage(slot, newId, note)
			end
			Viewer.Busy = false
			if problem == "cancelled" then
				refreshControls()
				return
			end
			Viewer.Message = { Text = message or "Nothing changed", Ok = ok }
			if not ok then
				renderInfo(preview)
				refreshControls()
				return
			end
			Viewer.HistoryPick = nil
			Viewer.IdBoxOpen = false
			local tab = Viewer.Tab
			rebuildList()
			local target = nil
			for _, candidate in ipairs(Viewer.Entries) do
				if (tab == "Images" and candidate.Group == slot.Group and candidate.Label == slot.Label) or (tab ~= "Images" and candidate.Key == Viewer.Selected) then
					target = candidate
					break
				end
			end
			if target then
				select(target, true)
			else
				renderInfo(preview)
				refreshControls()
			end
		end)
	end
	UI.RunImageChange = runImageChange

	-- controls row ---------------------------------------------------------------------------------
	local function controlButton(text, active, onClick, width)
		local instance = button(text, { Size = UDim2.new(0, width or (string.len(text) * 7 + 18), 0, 24), TextSize = 13, Parent = controls }, active)
		instance.MouseButton1Click:Connect(onClick)
		return instance
	end

	local function reselect()
		local entry
		for _, candidate in ipairs(Viewer.Entries) do
			if candidate.Key == Viewer.Selected then
				entry = candidate
			end
		end
		if entry then
			select(entry)
		end
	end

	refreshControls = function()
		for _, child in ipairs(controls:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local preview = Viewer.Preview
		if not preview then
			return
		end
		if preview.ImageSlot then
			controlButton(Viewer.Busy and "Working..." or "Change icon... (PNG)", true, function()
				runImageChange("file")
			end)
			controlButton("Use asset ID", Viewer.IdBoxOpen, function()
				Viewer.IdBoxOpen = not Viewer.IdBoxOpen
				refreshControls()
			end)
			if Viewer.IdBoxOpen then
				local idBox = new("TextBox", { Text = "", PlaceholderText = "image / decal id or link", ClearTextOnFocus = false, Font = Enum.Font.SourceSans, TextSize = 13,
					Size = UDim2.fromOffset(170, 24), Parent = controls })
				paint(idBox, "BackgroundColor3", "InputFieldBackground")
				paint(idBox, "TextColor3", "MainText")
				paint(idBox, "PlaceholderColor3", "DimmedText")
				corner(idBox, 4)
				controlButton("Apply", true, function()
					runImageChange("id", idBox.Text)
				end)
			end
			if Viewer.HistoryPick then
				controlButton("Restore this version", true, function()
					runImageChange("restore")
				end)
				controlButton("Back to current", false, function()
					backToCurrent()
				end)
			end
		end
		if preview.Image or not preview.Model then
			return
		end
		controlButton(Viewer.AutoRotate and "Auto-rotate: on" or "Auto-rotate: off", Viewer.AutoRotate, function()
			Viewer.AutoRotate = not Viewer.AutoRotate
			refreshControls()
		end)
		controlButton("Reset view", false, function()
			if Viewer.Preview and Viewer.Preview.Model then
				frameModel(Viewer.Preview.Model)
			end
		end)
		if preview.Entry and preview.Entry.Instance then
			controlButton("Select in Explorer", false, function()
				Selection:Set({ preview.Entry.Instance })
			end)
		end
		local animated = preview.ClassKey ~= nil or preview.CreatureKind ~= nil
		if preview.Tab == "Weapons" and WEAPON_CLASS[preview.Entry.Key] then
			controlButton(Viewer.WeaponOnHero and "On hero: yes" or "On hero: no", Viewer.WeaponOnHero, function()
				Viewer.WeaponOnHero = not Viewer.WeaponOnHero
				reselect()
			end)
		end
		if preview.ClassKey and (preview.Tab == "Heroes" or preview.Tab == "Animations" or preview.Tab == "Weapons") then
			local teams = loadTeams()
			for index, team in ipairs(teams) do
				local swatch = new("TextButton", { Text = index == Viewer.TeamIndex and "o" or "", Font = Enum.Font.SourceSansBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
					BackgroundColor3 = team.Color, Size = UDim2.fromOffset(22, 22), AutoButtonColor = true, Parent = controls })
				corner(swatch, 11)
				swatch.MouseButton1Click:Connect(function()
					Viewer.TeamIndex = index
					reselect()
				end)
			end
		end
		if preview.ClassKey and preview.Tab == "Heroes" then
			for _, action in ipairs({ "Idle", "Run", "Attack", "Ability" }) do
				controlButton(action == "Ability" and "Q" or action, Viewer.HeroAction == action, function()
					Viewer.HeroAction = action
					applyAnimation()
					refreshControls()
				end)
			end
		end
		if preview.CreatureKind and preview.Tab == "Monsters" then
			for _, state in ipairs({ "Idle", "Walk", "Attack", "Death" }) do
				controlButton(state, Viewer.CreatureState == state, function()
					Viewer.CreatureState = state
					applyAnimation()
					refreshControls()
				end)
			end
		end
		if preview.Tab == "Animations" then
			local hasUploaded = preview.SlotKey and animationSlotId(preview.SlotKey) ~= nil
			local versions = animationVersions(preview.SlotKey)
			local source = Viewer.AnimationSource
			local onVersion = source == "Compare" or string.match(source or "", "^Version:") ~= nil
			local versionFound = source == "Compare" and #versions > 0
			for _, version in ipairs(versions) do
				if source == "Version:" .. version.Name then
					versionFound = true
				end
			end
			local liveSelected = not (onVersion and versionFound)
			controlButton("Uploaded", liveSelected and source == "Uploaded" and hasUploaded, function()
				Viewer.AnimationSource = "Uploaded"
				applyAnimation()
				refreshControls()
			end)
			controlButton("Built-in", liveSelected and (source == "Built-in" or not hasUploaded), function()
				Viewer.AnimationSource = "Built-in"
				applyAnimation()
				refreshControls()
			end)
			for _, version in ipairs(versions) do
				controlButton(version.Name, source == "Version:" .. version.Name, function()
					Viewer.AnimationSource = "Version:" .. version.Name
					applyAnimation()
					refreshControls()
				end)
			end
			if #versions >= 2 then
				controlButton("Compare", source == "Compare", function()
					Viewer.AnimationSource = "Compare"
					applyAnimation()
					refreshControls()
				end)
			end
			local selected = Selection:Get()[1]
			if preview.SlotKey and selected and selected:IsA("KeyframeSequence") and not (preview.Model and selected:IsDescendantOf(preview.Model)) then
				controlButton("+ Add selected", false, function()
					local okAdd, added = pcall(addAnimationVersion, preview.SlotKey, selected)
					if okAdd then
						Viewer.AnimationSource = "Version:" .. added.Name
						reselect()
					end
				end)
			end
		end
		if animated then
			controlButton(Viewer.Playing and "Pause" or "Play", false, function()
				Viewer.Playing = not Viewer.Playing
				refreshControls()
			end)
			for _, speed in ipairs({ 0.25, 0.5, 1, 2 }) do
				controlButton(speed .. "x", Viewer.Speed == speed, function()
					Viewer.Speed = speed
					refreshControls()
				end, 38)
			end
		end
	end
	UI.RefreshControls = refreshControls
	-- "+ Add selected" follows the Studio selection
	UI.SelectionConnection = Selection.SelectionChanged:Connect(function()
		if Viewer.Preview and Viewer.Preview.Tab == "Animations" then
			refreshControls()
		end
	end)

	-- events -----------------------------------------------------------------------------------------
	for tab, tabButton in pairs(tabButtons) do
		tabButton.MouseButton1Click:Connect(function()
			if Viewer.Tab ~= tab then
				Viewer.Tab = tab
				Viewer.Selected = nil
				Viewer.Token += 1
				clearPreview()
				title.Text, subtitle.Text, overlay.Text = "Select an asset", "", ""
				bigImage.Visible = false
				renderInfo(nil)
				refreshControls()
				list.CanvasPosition = Vector2.zero
				rebuildList()
			end
		end)
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		Viewer.Search = search.Text
		rebuildList()
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

	rebuildList()
	updateCamera()
end

--------------------------------------------------------------------------------------------------
-- Plugin wiring
--------------------------------------------------------------------------------------------------
local container
if IS_TEST then
	container = new("ScreenGui", { Name = "RuinfallAssetViewerTest", Enabled = false, Parent = CoreGui })
	new("Frame", { Name = "Holder", Size = UDim2.fromOffset(920, 640), BackgroundTransparency = 1, Parent = container })
	buildUI(container.Holder)
else
	local toolbar = plugin:CreateToolbar("Ruinfall Viewer")
	local toolbarButton = toolbar:CreateButton("RuinfallAssetViewer", "Browse and inspect RUINFALL heroes, weapons, props, monsters, animations and images", "", "Asset Viewer")
	toolbarButton.ClickableWhenViewportHidden = true
	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 940, 660, 720, 480)
	container = plugin:CreateDockWidgetPluginGui("RuinfallAssetViewer", info)
	container.Name = "RuinfallAssetViewer"
	container.Title = "Ruinfall Asset Viewer"
	container.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	buildUI(container)
	toolbarButton.Click:Connect(function()
		container.Enabled = not container.Enabled
	end)
	container:GetPropertyChangedSignal("Enabled"):Connect(function()
		toolbarButton:SetActive(container.Enabled)
		if container.Enabled and UI.RebuildList then
			UI.RebuildList()
		end
	end)
	toolbarButton:SetActive(container.Enabled)
end

-- animation + camera loop (only while the viewer is open)
local heartbeat = RunService.Heartbeat:Connect(function(dt)
	if not IS_TEST and not container.Enabled then
		return
	end
	local preview = Viewer.Preview
	if not preview or not preview.Model then
		return
	end
	if Viewer.AutoRotate then
		view.Yaw += dt * 0.6
		updateCamera()
	end
	if preview.Driver and preview.Rig and Viewer.Playing then
		Viewer.Clock += math.min(dt, 0.1) * Viewer.Speed
		local ok, transforms = pcall(preview.Driver.Sample, Viewer.Clock)
		for _, extra in ipairs(preview.Compare or {}) do
			local okExtra, extraTransforms = pcall(extra.Driver.Sample, Viewer.Clock)
			if okExtra then
				applyPose(extra.Rig, extraTransforms)
			end
		end
		if ok then
			applyPose(preview.Rig, transforms)
		else
			preview.Driver = nil
			preview.DriverNote = "animation stopped: " .. tostring(transforms)
			if UI.RenderInfo then
				UI.RenderInfo(preview)
			end
		end
	end
end)

-- automation hook (used by tooling / tests)
local hook = CoreGui:FindFirstChild("RuinfallAssetViewerHook")
if hook then
	hook:Destroy()
end
hook = new("BindableFunction", { Name = "RuinfallAssetViewerHook", Archivable = false })
local function summary()
	local preview = Viewer.Preview
	if not preview then
		return { Loading = Viewer.Loading }
	end
	local parts = 0
	if preview.Model then
		for _, descendant in ipairs(preview.Model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				parts += 1
			end
		end
	end
	return {
		Title = preview.Title, Error = preview.Error, Parts = parts, Steps = preview.Rig and #preview.Rig.Order or 0,
		Driver = preview.Driver and preview.Driver.Kind or nil, Note = preview.DriverNote, Info = #(preview.Info or {}),
		Usages = preview.Usages and #preview.Usages or nil, Image = preview.Image, Loading = Viewer.Loading,
		Compare = preview.Compare and (#preview.Compare + 1) or nil,
	}
end
hook.OnInvoke = function(command, a, b)
	if command == "tab" then
		Viewer.Tab = a
		Viewer.Selected = nil
		UI.RebuildList()
		local keys = {}
		for _, entry in ipairs(Viewer.Entries) do
			table.insert(keys, entry.Key)
		end
		return keys
	elseif command == "select" then
		for _, entry in ipairs(Viewer.Entries) do
			if entry.Key == a then
				UI.Select(entry)
				local deadline = os.clock() + 20
				repeat
					task.wait(0.1)
				until (Viewer.Preview and Viewer.Preview.Entry == entry and Viewer.Preview.Usages ~= nil) or (Viewer.Preview and Viewer.Preview.Error) or os.clock() > deadline
				return summary()
			end
		end
		return { Error = "no entry " .. tostring(a) }
	elseif command == "set" then
		Viewer[a] = b
		if UI.ApplyAnimation then
			UI.ApplyAnimation()
			UI.RefreshControls()
		end
		return summary()
	elseif command == "motion" then
		-- how far the rig's parts move over `a` seconds of animation (proves it animates)
		local preview = Viewer.Preview
		if not (preview and preview.Rig and preview.Driver) then
			return -1
		end
		local start = {}
		for _, part in ipairs(preview.Rig.Parts) do
			start[part] = part.Position
		end
		local most = 0
		local t0 = Viewer.Clock
		for step = 1, 20 do
			applyPose(preview.Rig, preview.Driver.Sample(t0 + a * step / 20))
			for _, part in ipairs(preview.Rig.Parts) do
				most = math.max(most, (part.Position - start[part]).Magnitude)
			end
		end
		return most
	elseif command == "changeimage" then
		-- ("changeimage", "id", "<id>") / ("changeimage", "restore", historyIndex)
		if not UI.RunImageChange then
			return nil
		end
		if a == "restore" then
			local preview = Viewer.Preview
			Viewer.HistoryPick = preview and preview.History and preview.History[tonumber(b) or 1]
		end
		UI.RunImageChange(a, b)
		local deadline = os.clock() + 30
		repeat
			task.wait(0.1)
		until not Viewer.Busy or os.clock() > deadline
		task.wait(0.2)
		deadline = os.clock() + 20
		repeat
			task.wait(0.1)
		until (Viewer.Preview and Viewer.Preview.Usages ~= nil) or os.clock() > deadline
		return Viewer.Message
	elseif command == "history" then
		local ids = {}
		local preview = Viewer.Preview
		for _, item in ipairs(preview and preview.History or {}) do
			table.insert(ids, item.Id)
		end
		return ids, preview and preview.ImageSlot and preview.ImageSlot.Key
	elseif command == "uploadpng" then
		-- ("uploadpng", "<content uri of a png>", "<asset name>") -> assetId | nil, error
		local okImage, editable = pcall(function()
			return AssetService:CreateEditableImageAsync(Content.fromUri(a))
		end)
		if not okImage or not editable then
			return nil, "could not read " .. tostring(a) .. " (" .. tostring(editable) .. ")"
		end
		local okUpload, result, assetId = pcall(function()
			return AssetService:CreateAssetAsync(editable, Enum.AssetType.Image, {
				Name = "RUINFALL " .. tostring(b),
				Description = "RUINFALL item icon",
			})
		end)
		pcall(function()
			editable:Destroy()
		end)
		if not okUpload then
			return nil, "upload failed: " .. tostring(result)
		end
		if result ~= Enum.CreateAssetResult.Success or not assetId then
			return nil, "upload not completed (" .. tostring(result) .. ")"
		end
		return tostring(assetId)
	elseif command == "summary" then
		return summary()
	elseif command == "version" then
		return VERSION
	end
	return nil
end
hook.Parent = CoreGui

local function shutdown()
	heartbeat:Disconnect()
	if UI.SelectionConnection then
		UI.SelectionConnection:Disconnect()
	end
	clearPreview()
	if hook then
		hook:Destroy()
	end
	if IS_TEST and container then
		container:Destroy()
	end
end
if IS_TEST then
	return { Shutdown = shutdown, Viewer = Viewer, UI = UI }
else
	plugin.Unloading:Connect(shutdown)
end
