-- AnimationLibrary: optional uploaded animations that REPLACE the game's built-in ones.
-- Slots live in ReplicatedStorage.RuinfallAnimations as Animation instances named by key;
-- a missing slot or an empty AnimationId means "use the built-in animation" (the procedural
-- class swings, the procedural monster / minion rigs, Roblox's default idle / run).
-- Edited with the Ruinfall Asset Porter Studio plugin. Changes made during a playtest apply
-- live, because every reader looks the id up at play time.
--
-- Keys:
--   <Class>_Idle, <Class>_Run          hero locomotion (players: Animate script, bots: CharacterFactory)
--   <Class>_Attack, <Class>_Ability    basic attack / Q            (AttackAnimationController)
--   Skill_<AbilityId>                  item skill on E / R / boots (AttackAnimationController)
--   Monster_Idle / _Walk / _Attack / _Death   jungle monsters      (CreatureAnimationController)
--   Minion_Idle  / _Walk / _Attack / _Death   lane minions         (CreatureAnimationController)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLibrary = {}
AnimationLibrary.FOLDER_NAME = "RuinfallAnimations"
AnimationLibrary.CREATURE_STATES = { "Idle", "Walk", "Attack", "Death" }
AnimationLibrary.HERO_STATES = { "Idle", "Run", "Attack", "Ability" }

function AnimationLibrary.GetFolder()
	return ReplicatedStorage:FindFirstChild(AnimationLibrary.FOLDER_NAME)
end

-- the uploaded animation id for a slot, or nil when the built-in animation is used
function AnimationLibrary.GetId(key)
	local folder = AnimationLibrary.GetFolder()
	local slot = folder and folder:FindFirstChild(key)
	if slot and slot:IsA("Animation") and slot.AnimationId ~= "" then
		return slot.AnimationId
	end
	return nil
end

-- per-animator track cache: [animator] = { [key] = { Id, Track } }
local cache = setmetatable({}, { __mode = "k" })

local function getAnimator(model)
	local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		return nil
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		-- server-built monsters have no Animator: a local one animates them on this machine
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	return animator
end

-- AnimationTrack for a slot on this model (reloaded when the slot's id changes), or nil
function AnimationLibrary.GetTrack(model, key)
	local id = AnimationLibrary.GetId(key)
	if not id or not model then
		return nil
	end
	local animator = getAnimator(model)
	if not animator then
		return nil
	end
	local entries = cache[animator]
	if not entries then
		entries = {}
		cache[animator] = entries
	end
	local entry = entries[key]
	if entry and entry.Id == id then
		return entry.Track
	end
	if entry and entry.Track then
		pcall(function()
			entry.Track:Stop(0)
			entry.Track:Destroy()
		end)
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[Ruinfall] Could not load animation " .. key .. " (" .. id .. "):", track)
		track = nil
	end
	entries[key] = { Id = id, Track = track }
	return track
end

-- Plays a slot once (or looped) and returns the track; nil = no uploaded animation (use built-in)
function AnimationLibrary.Play(model, key, fadeTime, speed, priority)
	local track = AnimationLibrary.GetTrack(model, key)
	if not track then
		return nil
	end
	if priority then
		track.Priority = priority
	end
	track:Play(fadeTime or 0.08, 1, speed or 1)
	return track
end

-- Every slot the game reads (for the Asset Porter plugin): { Key, Group, Label, Looped }
function AnimationLibrary.GetSlots()
	local Shared = script.Parent
	local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
	local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
	local slots = {}
	for _, classKey in ipairs(ClassDefinitions.Order) do
		local classDef = ClassDefinitions.Classes[classKey]
		table.insert(slots, { Key = classKey .. "_Idle", Group = "Heroes", Label = classKey .. " - idle", Looped = true })
		table.insert(slots, { Key = classKey .. "_Run", Group = "Heroes", Label = classKey .. " - run", Looped = true })
		table.insert(slots, { Key = classKey .. "_Attack", Group = "Heroes", Label = classKey .. " - basic attack" })
		table.insert(slots, { Key = classKey .. "_Ability", Group = "Heroes", Label = classKey .. " - Q: " .. (classDef.Ability and classDef.Ability.Name or "ability") })
	end
	local seen, skills = {}, {}
	for _, item in pairs(ItemDefinitions.Items) do
		local ability = item.Ability and ItemDefinitions.GetAbility(item.Ability)
		if ability and not seen[ability.Id] then
			seen[ability.Id] = true
			local slotName = ItemDefinitions.IsBoots(item) and "boots" or "E/R"
			table.insert(skills, { Key = "Skill_" .. ability.Id, Group = "Item skills",
				Label = string.format("%s - %s (%s, %s)", item.Class or "Any", ability.Name or ability.Id, item.Name or item.Id, slotName), Sort = (item.Class or "~") .. (ability.Name or "") })
		end
	end
	table.sort(skills, function(a, b)
		return a.Sort < b.Sort
	end)
	for _, slot in ipairs(skills) do
		slot.Sort = nil
		table.insert(slots, slot)
	end
	for _, prefix in ipairs({ "Monster", "Minion" }) do
		for _, state in ipairs(AnimationLibrary.CREATURE_STATES) do
			table.insert(slots, { Key = prefix .. "_" .. state, Group = "Creatures",
				Label = (prefix == "Monster" and "Jungle monster" or "Lane minion") .. " - " .. string.lower(state), Looped = state == "Idle" or state == "Walk" })
		end
	end
	return slots
end

return AnimationLibrary
