--[[
	AudioManager - the one playback engine for every sound in RUINFALL (CLIENT ONLY).

	Everything is referenced by logical cue names defined in AudioConfig ("Section.Name"):
		AudioManager:Play("Combat.SwordSwing", { Position = hitPosition })
		AudioManager:PlaySFX("Explosion", { Position = p })   -- section optional for SFX
		AudioManager:PlayUI("Click")
		AudioManager:PlaySkill("Fireball", "Cast", { Position = casterPosition })
		AudioManager:PlayMusic("Combat")                        -- crossfades, never restarts the same track
		AudioManager:PlayStinger("Stingers.BossSpawn")          -- ducks the music while it plays
		AudioManager:StartLoop("Heartbeat", "Player.Heartbeat") / :StopLoop("Heartbeat")

	Performance / multiplayer rules implemented here:
	  * Sounds are POOLED: a fixed set of 3D emitters + 2D channels is created once and reused.
	    Nothing is cloned per shot, nothing is created per frame. Loops own one Sound per key.
	  * Per-cue Cooldown + MaxInstances, global voice budget with Priority based dropping /
	    stealing, and 3D distance culling keep busy fights from turning into noise.
	  * All sounds are client-local. Gameplay events reach every client through the existing
	    replicated channels (EffectEvent batch, model attributes, Notify), so every player hears
	    the same world events from their own position without extra network traffic.
	  * Placeholders / missing ids are skipped silently (logged once in debug mode).

	Server scripts must not require this module - use ServerScriptService.AudioService instead.
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local AudioConfig = require(script.Parent:WaitForChild("AudioConfig"))

-- Constants
local PRIORITY = AudioConfig.Priority
local VOICES = AudioConfig.Voices
local SPATIAL = AudioConfig.Spatial
local PLACEHOLDER = AudioConfig.PLACEHOLDER
-- Section -> designer override folder (a Sound named like the entry inside it overrides the ids)
local OVERRIDE_FOLDERS = {
	Music = "Music", Stingers = "Music", Ambient = "Environment", Footsteps = "SFX", Movement = "SFX",
	Player = "SFX", Effects = "SFX", Objectives = "SFX", Combat = "Combat", Skills = "Skills",
	Monsters = "Monsters", UI = "UI",
}
local SFX_SEARCH_ORDER = { "Combat", "Effects", "Skills", "Movement", "Player", "Objectives", "Monsters", "Footsteps", "Stingers", "Ambient", "UI" }

-- State
local AudioManager = {}
AudioManager.Settings = table.clone(AudioConfig.DefaultSettings)
AudioManager.SettingsChanged = Instance.new("BindableEvent") -- :Fire(settings)
AudioManager.CuePlayed = Instance.new("BindableEvent") -- :Fire(cue, info) (debug panel / tests)

local initialized = false
local debugEnabled = false
local rng = Random.new()
local groups = {} -- name -> SoundGroup
local resolvedCache = {} -- cue -> entry
local lastPlayedAt = {} -- cue -> os.clock()
local lastIdIndex = {} -- cue -> index of last id used
local failedIds = {} -- "rbxassetid://.." -> true
local loggedMissing = {}
local voices3D, voices2D = {}, {}
local anchorPart = nil
local root2D = nil
local listenerCFrame = CFrame.new()
local loops = {} -- key -> { Sound, Cue, Base }
local music = { Channels = {}, Active = nil, Name = nil, Entry = nil, Ducks = {} }
local stats = { Played = 0, Dropped = 0, Stolen = 0 }

-- Helpers ------------------------------------------------------------------------------------
local function log(...)
	if debugEnabled then
		print("[Audio]", ...)
	end
end

local function toContentId(id)
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end
	if type(id) == "string" and id ~= PLACEHOLDER and id ~= "" then
		return id:find("://") and id or ("rbxassetid://" .. id)
	end
	return nil
end

local function randomRange(value, default)
	if type(value) == "table" then
		return rng:NextNumber(value[1], value[2] or value[1])
	end
	return value or default
end

local function shallowMerge(base, overrides)
	local result = table.clone(base)
	for key, value in pairs(overrides) do
		if key ~= "Alias" then
			result[key] = value
		end
	end
	return result
end

-- Resolve "Section.Name" into a config entry (follows Alias, applies Studio overrides) -------
function AudioManager:Resolve(cue)
	if resolvedCache[cue] ~= nil then
		return resolvedCache[cue] or nil
	end
	local section, name = string.match(cue, "^(%w+)%.(%w+)$")
	local sectionTable = section and AudioConfig.Sounds[section]
	local entry = sectionTable and sectionTable[name]
	if not entry then
		resolvedCache[cue] = false
		return nil
	end
	if entry.Alias then
		local base = self:Resolve(entry.Alias)
		entry = base and shallowMerge(base, entry) or nil
	else
		entry = table.clone(entry)
	end
	if entry then
		-- Designer override: ReplicatedStorage.Audio.<Folder>.<Name> (a Sound) replaces the ids
		local folder = script.Parent:FindFirstChild(OVERRIDE_FOLDERS[section] or "")
		local override = folder and folder:FindFirstChild(name)
		if override and override:IsA("Sound") and override.SoundId ~= "" then
			entry.Ids = { override.SoundId }
			entry.Volume = override.Volume
		end
		entry.Cue = cue
		entry.Section = section
		-- skill / spell sounds are short: capped length with a smooth fade (AudioConfig.SkillAudio)
		local skillAudio = AudioConfig.SkillAudio
		if skillAudio and skillAudio.Sections[section] and entry.MaxDuration == nil then
			entry.MaxDuration = skillAudio.MaxDuration
			entry.FadeOut = entry.FadeOut or skillAudio.FadeOut
		end
	end
	resolvedCache[cue] = entry or false
	return entry
end

local function pickId(cue, entry)
	local ids = entry.Ids
	if not ids or #ids == 0 then
		return nil
	end
	local valid = {}
	for index, id in ipairs(ids) do
		local content = toContentId(id)
		if content and not failedIds[content] then
			table.insert(valid, { Index = index, Content = content })
		end
	end
	if #valid == 0 then
		if AudioConfig.Debug.LogMissing and not loggedMissing[cue] then
			loggedMissing[cue] = true
			log("MISSING ASSET (placeholder) for", cue, "- add an id in AudioConfig")
		end
		return nil
	end
	local choice = valid[rng:NextInteger(1, #valid)]
	if #valid > 1 and choice.Index == lastIdIndex[cue] then
		-- avoid the same variation twice in a row
		for _, candidate in ipairs(valid) do
			if candidate.Index ~= lastIdIndex[cue] then
				choice = candidate
				break
			end
		end
	end
	lastIdIndex[cue] = choice.Index
	return choice.Content
end

-- Voices -------------------------------------------------------------------------------------
local function busyCount()
	local count = 0
	for _, voice in ipairs(voices3D) do
		if voice.Busy then
			count += 1
		end
	end
	for _, voice in ipairs(voices2D) do
		if voice.Busy then
			count += 1
		end
	end
	return count
end

local function releaseVoice(voice)
	if not voice.Busy then
		return
	end
	voice.Busy = false
	voice.Cue = nil
	voice.Follow = nil
	if voice.Tween then
		voice.Tween:Cancel()
		voice.Tween = nil
	end
	voice.Sound:Stop()
end

local function makeVoice(is3D, index)
	local sound = Instance.new("Sound")
	sound.Name = (is3D and "Emitter" or "Channel") .. index
	local voice = { Sound = sound, Busy = false, Priority = 0, StartedAt = 0, EndsAt = 0 }
	if is3D then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Emitter" .. index
		attachment.Parent = anchorPart
		sound.Parent = attachment
		voice.Attachment = attachment
	else
		sound.Parent = root2D
	end
	sound.Ended:Connect(function()
		if voice.Busy and not sound.Looped then
			releaseVoice(voice)
		end
	end)
	return voice
end

local function acquireVoice(pool, cue, entry, priority)
	-- 1) per-cue instance limit: reuse the oldest copy of the same cue
	local maxInstances = entry.MaxInstances or 4
	local sameCue, oldestSame = 0, nil
	for _, voice in ipairs(pool) do
		if voice.Busy and voice.Cue == cue then
			sameCue += 1
			if not oldestSame or voice.StartedAt < oldestSame.StartedAt then
				oldestSame = voice
			end
		end
	end
	if sameCue >= maxInstances then
		if priority >= PRIORITY.High and oldestSame then
			releaseVoice(oldestSame)
			stats.Stolen += 1
			return oldestSame
		end
		return nil
	end
	-- 2) a free voice
	for _, voice in ipairs(pool) do
		if not voice.Busy then
			return voice
		end
	end
	-- 3) steal the lowest-priority, oldest voice that is less important than this one
	local victim = nil
	for _, voice in ipairs(pool) do
		if not voice.Sound.Looped and voice.Priority < priority then
			if not victim or voice.Priority < victim.Priority or (voice.Priority == victim.Priority and voice.StartedAt < victim.StartedAt) then
				victim = voice
			end
		end
	end
	if victim then
		releaseVoice(victim)
		stats.Stolen += 1
	end
	return victim
end

-- Core play -----------------------------------------------------------------------------------
local function playEntry(cue, entry, options)
	options = options or {}
	local now = os.clock()
	-- composite cues
	if entry.Layers then
		local handles = {}
		for _, layer in ipairs(entry.Layers) do
			local layerCue = type(layer) == "string" and layer or layer.Cue
			local layerOptions = table.clone(options)
			if type(layer) == "table" then
				layerOptions.Volume = (options.Volume or 1) * (layer.Volume or 1)
				if layer.Spatial == false then
					layerOptions.Force2D = true
				end
				if layer.Delay then
					layerOptions.Delay = (options.Delay or 0) + layer.Delay
				end
			end
			local handle = AudioManager:Play(layerCue, layerOptions)
			if handle then
				table.insert(handles, handle)
			end
		end
		return handles[1]
	end
	-- anti-spam
	if entry.Cooldown and not options.IgnoreCooldown and lastPlayedAt[cue] and now - lastPlayedAt[cue] < entry.Cooldown then
		return nil
	end
	local priority = PRIORITY[entry.Priority or "Medium"] or PRIORITY.Medium
	local busy = busyCount()
	if (priority <= PRIORITY.Low and busy >= VOICES.DropLowAbove) or (priority <= PRIORITY.Medium and busy >= VOICES.DropMediumAbove) then
		stats.Dropped += 1
		return nil
	end
	-- Follow: a BasePart or a function returning a Vector3 (moving sources: projectiles, units)
	local follow = options.Follow
	local position = options.Position
	if not position and follow then
		if typeof(follow) == "Instance" then
			position = follow:IsA("BasePart") and follow.Position or nil
		elseif type(follow) == "function" then
			local ok, value = pcall(follow)
			position = ok and value or nil
		end
	end
	local spatial = entry.Spatial and not options.Force2D and position ~= nil
	local maxDistance = entry.MaxDistance or SPATIAL.MaxDistance
	if spatial then
		if (position - listenerCFrame.Position).Magnitude > maxDistance then
			return nil -- too far to be heard: do not waste a voice
		end
	end
	local contentId = pickId(cue, entry)
	if not contentId then
		return nil
	end
	local voice = acquireVoice(spatial and voices3D or voices2D, cue, entry, priority)
	if not voice then
		stats.Dropped += 1
		return nil
	end
	lastPlayedAt[cue] = now
	local sound = voice.Sound
	voice.Busy = true
	voice.Cue = cue
	voice.Priority = priority
	voice.StartedAt = now
	sound.SoundId = contentId
	sound.Looped = entry.Looped == true and options.Looped ~= false
	local jitter = entry.VolumeJitter or 0
	sound.Volume = math.clamp((entry.Volume or 0.5) * (1 + rng:NextNumber(-jitter, jitter)) * (options.Volume or 1), 0, 3)
	sound.PlaybackSpeed = randomRange(entry.Pitch, 1) * (options.Pitch or 1)
	sound.SoundGroup = groups[entry.Group or "SFX"] or groups.SFX
	sound.TimePosition = 0
	if spatial then
		sound.RollOffMode = SPATIAL.RollOffMode
		sound.RollOffMinDistance = entry.MinDistance or SPATIAL.MinDistance
		sound.RollOffMaxDistance = maxDistance
		voice.Attachment.WorldPosition = position
		voice.Follow = follow
	end
	local length = sound.TimeLength > 0 and sound.TimeLength or 6
	voice.EndsAt = now + (options.Delay or 0) + length / math.max(0.05, sound.PlaybackSpeed) + 0.5
	local delay = (options.Delay or 0) + randomRange(entry.Delay, 0)
	-- Length cap with a natural fade-out (never an abrupt cut). MaxDuration counts from the
	-- moment the cue was triggered, so delayed layers of a skill still end inside the cap.
	local maxDuration = options.MaxDuration or entry.MaxDuration
	if maxDuration and maxDuration > 0 then
		local audible = math.max(0.2, maxDuration - (options.Delay or 0))
		local fade = math.min(options.FadeOut or entry.FadeOut or 0.3, audible * 0.6)
		voice.EndsAt = math.min(voice.EndsAt, now + delay + audible + 0.3)
		task.delay(delay + audible - fade, function()
			if voice.Busy and voice.Cue == cue and voice.StartedAt == now then
				local tween = TweenService:Create(sound, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
				voice.Tween = tween
				tween.Completed:Connect(function(state)
					if state == Enum.PlaybackState.Completed and voice.Busy and voice.StartedAt == now then
						releaseVoice(voice)
					end
				end)
				tween:Play()
			end
		end)
	end
	if delay > 0 then
		task.delay(delay, function()
			if voice.Busy and voice.Cue == cue and voice.StartedAt == now then
				sound:Play()
			end
		end)
	else
		sound:Play()
	end
	stats.Played += 1
	if debugEnabled then
		log(string.format("Playing: %s | Category: %s | Volume: %.2f | Position: %s | Priority: %s | Source: %s",
			cue, entry.Group or "SFX", sound.Volume,
			spatial and string.format("(%.0f, %.0f, %.0f)", position.X, position.Y, position.Z) or "2D",
			entry.Priority or "Medium", options.Source or "-"))
	end
	AudioManager.CuePlayed:Fire(cue, { Position = spatial and position or nil, Volume = sound.Volume })
	return sound
end

-- Public API ---------------------------------------------------------------------------------
-- options: Position (Vector3) | Follow (BasePart or function -> Vector3) | Volume / Pitch (multipliers) |
--          Delay (s) | Force2D | Looped=false | IgnoreCooldown | Source (debug label) |
--          MaxDuration / FadeOut (s): cap the length with a smooth fade (skill sounds)
function AudioManager:Play(cue, options)
	if not initialized or type(cue) ~= "string" then
		return nil
	end
	local entry = self:Resolve(cue)
	if not entry then
		if AudioConfig.Debug.LogMissing and not loggedMissing[cue] then
			loggedMissing[cue] = true
			log("Unknown cue", cue)
		end
		return nil
	end
	local ok, result = pcall(playEntry, cue, entry, options)
	if not ok then
		warn("[Audio] play failed", cue, result)
		return nil
	end
	return result
end

-- Plays "Name" from the first SFX section that has it (or a full "Section.Name")
function AudioManager:PlaySFX(name, options)
	if string.find(name, "%.") then
		return self:Play(name, options)
	end
	for _, section in ipairs(SFX_SEARCH_ORDER) do
		local sectionTable = AudioConfig.Sounds[section]
		if sectionTable and sectionTable[name] then
			return self:Play(section .. "." .. name, options)
		end
	end
	return nil
end

function AudioManager:PlayUI(name, options)
	return self:Play("UI." .. name, options)
end

-- phase: "Cast" | "Charge" | "Release" | "Impact" | "Extra"
function AudioManager:PlaySkill(skillId, phase, options)
	local skill = AudioConfig.Skills[skillId]
	local cue = skill and skill[phase or "Cast"]
	if not cue then
		return nil
	end
	return self:Play(cue, options)
end

function AudioManager:PlayStinger(cue, options)
	local sound = self:Play(cue, options)
	if sound then
		local duration = sound.TimeLength > 0 and sound.TimeLength / sound.PlaybackSpeed or 3
		self:SetMusicDuck("Stinger_" .. cue, AudioConfig.MusicRules.StingerDuck, math.min(duration, 8))
	end
	return sound
end

-- Loops: one persistent Sound per key (ambience beds, heartbeat...). Changing the cue fades. ---
function AudioManager:StartLoop(key, cue, options)
	options = options or {}
	local existing = loops[key]
	if existing and existing.Cue == cue then
		local target = existing.Base * (options.Volume or 1)
		TweenService:Create(existing.Sound, TweenInfo.new(options.Fade or 1), { Volume = target }):Play()
		return existing.Sound
	end
	if existing then
		self:StopLoop(key, options.Fade or 1.5)
	end
	local entry = self:Resolve(cue)
	local contentId = entry and pickId(cue, entry)
	if not contentId then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Loop_" .. key
	sound.SoundId = contentId
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = randomRange(entry.Pitch, 1)
	sound.SoundGroup = groups[entry.Group or "Ambient"] or groups.SFX
	sound.Parent = root2D
	sound:Play()
	local base = entry.Volume or 0.3
	TweenService:Create(sound, TweenInfo.new(options.Fade or 1.5), { Volume = base * (options.Volume or 1) }):Play()
	loops[key] = { Sound = sound, Cue = cue, Base = base }
	log("Loop start", key, cue)
	return sound
end

function AudioManager:StopLoop(key, fade)
	local loop = loops[key]
	if not loop then
		return
	end
	loops[key] = nil
	local sound = loop.Sound
	local tween = TweenService:Create(sound, TweenInfo.new(fade or 1), { Volume = 0 })
	tween.Completed:Connect(function()
		sound:Destroy()
	end)
	tween:Play()
	log("Loop stop", key)
end

function AudioManager:IsLoopPlaying(key)
	return loops[key] ~= nil
end

-- Music: two crossfading channels, one track at a time --------------------------------------
local function musicDuck()
	local multiplier = 1
	local now = os.clock()
	for key, duck in pairs(music.Ducks) do
		if duck.Until and now > duck.Until then
			music.Ducks[key] = nil
		else
			multiplier = math.min(multiplier, duck.Value)
		end
	end
	return multiplier
end

local function applyMusicVolume(fadeTime)
	local channel = music.Active
	if channel and music.Entry then
		TweenService:Create(channel, TweenInfo.new(fadeTime or 0.6), { Volume = (music.Entry.Volume or 0.5) * musicDuck() }):Play()
	end
end

-- Keeps the music under important moments (stingers, death, low health). value 0..1
function AudioManager:SetMusicDuck(key, value, duration)
	if value == nil or value >= 1 then
		music.Ducks[key] = nil
	else
		music.Ducks[key] = { Value = value, Until = duration and (os.clock() + duration) or nil }
	end
	applyMusicVolume(0.6)
	if duration then
		task.delay(duration + 0.05, function()
			applyMusicVolume(1.2)
		end)
	end
end

-- options: Once = true (do not loop), Then = "TrackName" to crossfade to when it ends
function AudioManager:PlayMusic(name, options)
	options = options or {}
	if not initialized then
		return
	end
	if music.Name == name and music.Active and music.Active.IsPlaying then
		return -- never restart the track that is already playing
	end
	local cue = "Music." .. name
	local entry = self:Resolve(cue)
	local contentId = entry and pickId(cue, entry)
	if not contentId then
		return
	end
	local fade = options.Fade or AudioConfig.MusicRules.Crossfade
	local old = music.Active
	local new = (old == music.Channels[1]) and music.Channels[2] or music.Channels[1]
	music.Name = name
	music.Entry = entry
	music.Token = (music.Token or 0) + 1
	local token = music.Token
	new:Stop()
	new.SoundId = contentId
	new.Looped = not options.Once and entry.Looped ~= false
	new.Volume = 0
	new.TimePosition = 0
	new:Play()
	music.Active = new
	TweenService:Create(new, TweenInfo.new(fade), { Volume = (entry.Volume or 0.5) * musicDuck() }):Play()
	if old and old ~= new then
		local tween = TweenService:Create(old, TweenInfo.new(fade), { Volume = 0 })
		tween.Completed:Connect(function()
			if music.Active ~= old then
				old:Stop()
			end
		end)
		tween:Play()
	end
	if options.Once and options.Then then
		task.spawn(function()
			local waited = 0
			while waited < 3 and new.TimeLength <= 0 do
				waited += task.wait(0.1)
			end
			local duration = new.TimeLength > 0 and new.TimeLength or 10
			task.wait(math.max(0.5, duration - fade * 0.5))
			if music.Token == token then
				AudioManager:PlayMusic(options.Then)
			end
		end)
	end
	log("Music ->", name)
end

function AudioManager:StopMusic(fade)
	local channel = music.Active
	music.Name = nil
	music.Active = nil
	music.Token = (music.Token or 0) + 1
	if channel then
		local tween = TweenService:Create(channel, TweenInfo.new(fade or 2), { Volume = 0 })
		tween.Completed:Connect(function()
			channel:Stop()
		end)
		tween:Play()
	end
end

function AudioManager:GetMusicName()
	return music.Name
end

-- Settings -------------------------------------------------------------------------------------
local function applySettings()
	local s = AudioManager.Settings
	if not groups.Master then
		return
	end
	groups.Master.Volume = s.Master
	groups.Music.Volume = s.MusicEnabled and s.Music or 0
	groups.SFX.Volume = s.SFXEnabled and s.SFX or 0
	groups.Combat.Volume = s.Combat
	groups.Ambient.Volume = s.Ambient
	groups.UI.Volume = s.UI
end

function AudioManager:ApplySettings(settings, silent)
	for key, default in pairs(AudioConfig.DefaultSettings) do
		local value = settings and settings[key]
		if type(default) == "number" and type(value) == "number" then
			self.Settings[key] = math.clamp(value, 0, 1)
		elseif type(default) == "boolean" and type(value) == "boolean" then
			self.Settings[key] = value
		end
	end
	applySettings()
	if not silent then
		self.SettingsChanged:Fire(self.Settings)
	end
end

function AudioManager:SetSetting(key, value)
	self:ApplySettings({ [key] = value })
end

function AudioManager:GetSettings()
	return table.clone(self.Settings)
end

-- Debug ----------------------------------------------------------------------------------------
function AudioManager:SetDebug(enabled)
	debugEnabled = enabled == true and RunService:IsStudio()
end

function AudioManager:IsDebug()
	return debugEnabled
end

function AudioManager:GetStats()
	local copy = table.clone(stats)
	copy.Busy = busyCount()
	copy.Loops = 0
	for _ in pairs(loops) do
		copy.Loops += 1
	end
	copy.Music = music.Name
	return copy
end

-- Every "Section.Name" in the config (debug test panel)
function AudioManager:GetCueNames()
	local names = {}
	for section, entries in pairs(AudioConfig.Sounds) do
		for name in pairs(entries) do
			table.insert(names, section .. "." .. name)
		end
	end
	table.sort(names)
	return names
end

function AudioManager:GetListenerPosition()
	return listenerCFrame.Position
end

-- Init -----------------------------------------------------------------------------------------
local function buildGroups()
	for _, definition in ipairs(AudioConfig.Groups) do
		local group = SoundService:FindFirstChild("RF_" .. definition.Name)
		if not group then
			group = Instance.new("SoundGroup")
			group.Name = "RF_" .. definition.Name
		end
		group.Parent = definition.Parent and groups[definition.Parent] or SoundService
		groups[definition.Name] = group
	end
end

local function updateListener()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then
		flatLook = Vector3.new(0, 0, -1)
	end
	local position
	if root then
		position = root.Position + Vector3.new(0, 3, 0) -- top-down camera: hear from the hero, not the sky
	else
		position = camera.Focus.Position
	end
	listenerCFrame = CFrame.lookAt(position, position + flatLook.Unit)
	SoundService:SetListener(Enum.ListenerType.CFrame, listenerCFrame)
	-- move emitters that follow a moving source (only the few busy ones with Follow set)
	for _, voice in ipairs(voices3D) do
		local follow = voice.Follow
		if voice.Busy and follow then
			local at = nil
			if typeof(follow) == "Instance" then
				at = follow.Parent and follow.Position or nil
			else
				local ok, value = pcall(follow)
				at = ok and value or nil
			end
			if at then
				voice.Attachment.WorldPosition = at
			else
				voice.Follow = nil -- source gone: the sound finishes where it was
			end
		end
	end
end

local function maintenance()
	-- release voices whose sound finished but never fired Ended (e.g. asset failed to load)
	local now = os.clock()
	for _, pool in ipairs({ voices3D, voices2D }) do
		for _, voice in ipairs(pool) do
			if voice.Busy and not voice.Sound.Looped and now > voice.EndsAt then
				local sound = voice.Sound
				if sound.TimeLength <= 0 and sound.SoundId ~= "" and now - voice.StartedAt > 5 then
					failedIds[sound.SoundId] = true
					log("Asset failed to load, disabled:", sound.SoundId, voice.Cue)
				end
				if not sound.IsPlaying or now - voice.StartedAt > 30 then
					releaseVoice(voice)
				end
			end
		end
	end
end

local function preload()
	-- warm the most frequent short sounds so the first hit is not silent
	local list = {}
	for _, section in ipairs({ "UI", "Combat", "Footsteps", "Player", "Movement" }) do
		for name in pairs(AudioConfig.Sounds[section] or {}) do
			local entry = AudioManager:Resolve(section .. "." .. name)
			for _, id in ipairs(entry and entry.Ids or {}) do
				local content = toContentId(id)
				if content then
					local sound = Instance.new("Sound")
					sound.SoundId = content
					table.insert(list, sound)
				end
			end
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list, function(content, status)
			if status == Enum.AssetFetchStatus.Failure then
				failedIds[content] = true
				log("Preload failed:", content)
			end
		end)
	end)
	for _, sound in ipairs(list) do
		sound:Destroy()
	end
end

function AudioManager.Init()
	if initialized then
		return AudioManager
	end
	assert(RunService:IsClient(), "AudioManager is client-only; use AudioService on the server")
	initialized = true
	debugEnabled = AudioConfig.Debug.Enabled and RunService:IsStudio()
	buildGroups()
	root2D = Instance.new("Folder")
	root2D.Name = "RF_Audio2D"
	root2D.Parent = SoundService
	anchorPart = Instance.new("Part")
	anchorPart.Name = "RF_AudioEmitters"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.CFrame = CFrame.new()
	anchorPart.Parent = workspace
	for index = 1, VOICES.Emitters3D do
		table.insert(voices3D, makeVoice(true, index))
	end
	for index = 1, VOICES.Channels2D do
		table.insert(voices2D, makeVoice(false, index))
	end
	for index = 1, 2 do
		local channel = Instance.new("Sound")
		channel.Name = "MusicChannel" .. index
		channel.SoundGroup = groups.Music
		channel.Volume = 0
		channel.Parent = root2D
		music.Channels[index] = channel
	end
	applySettings()
	RunService.Heartbeat:Connect(updateListener)
	task.spawn(function()
		while true do
			task.wait(0.5)
			maintenance()
		end
	end)
	task.spawn(preload)
	return AudioManager
end

return AudioManager
