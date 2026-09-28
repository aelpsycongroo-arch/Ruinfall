--[[
	AudioService (server) - the server side of the audio system. Sounds themselves are always
	played by clients (ReplicatedStorage.Audio.AudioManager); the server only:
	  * Persists each player's audio settings (DataStore "RuinfallAudioSettings_v2"), validated
	    and rate-limited. Falls back to session-only when DataStores are unavailable (Studio).
	  * Offers helpers for FUTURE server-driven cues (boss abilities, scripted events):
	        AudioService.PlayAt("Monsters.Roar", position)        -- everyone near hears it
	        AudioService.PlayFor(player, "UI.Upgrade")             -- one player only (2D)
	    Both use existing channels: the batched EffectEvent (kind "Audio") and the AudioEvent
	    remote. Clients map the cue names through AudioConfig - never send raw asset ids.
	  * Notify(...) can carry a sound: Net.Notify(player, text, style, { Sound = "UI.Purchase" })
	Gameplay stays server-authoritative: clients cannot trigger sounds for other players.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Net = require(script.Parent:WaitForChild("Net"))

-- Constants
local STORE_NAME = "RuinfallAudioSettings_v2" -- v2: v1 could hold toggles wrongly saved as OFF
local SAVE_INTERVAL = 6 -- seconds between DataStore writes per player
local REQUEST_INTERVAL = 0.5 -- anti-spam for client requests

-- State
local AudioService = {}
local store = nil
local cache = {} -- player -> settings
local dirty = {} -- player -> true
local lastRequest = {}
local lastSave = {}
local initialized = false
local DEFAULTS = {}

local function sanitize(payload)
	local clean = {}
	for key, default in pairs(DEFAULTS) do
		-- NOTE: not `type(payload) == "table" and payload[key]` - that yields `false` for a missing
		-- payload, which turned the Music / SFX toggles OFF for players without saved settings
		local value = nil
		if type(payload) == "table" then
			value = payload[key]
		end
		if type(default) == "number" then
			clean[key] = (type(value) == "number" and value == value) and math.clamp(value, 0, 1) or default
		elseif type(default) == "boolean" then
			if type(value) == "boolean" then
				clean[key] = value
			else
				clean[key] = default
			end
		end
	end
	return clean
end

local function load(player)
	if cache[player] then
		return cache[player]
	end
	local settings = nil
	if store then
		local ok, data = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok and type(data) == "table" then
			settings = sanitize(data)
		end
	end
	settings = settings or sanitize(nil)
	cache[player] = settings
	return settings
end

local function save(player)
	if not store or not dirty[player] or not cache[player] then
		return
	end
	dirty[player] = nil
	lastSave[player] = os.clock()
	local data = cache[player]
	pcall(function()
		store:SetAsync("u" .. player.UserId, data)
	end)
end

-- Public API -------------------------------------------------------------------------------
function AudioService.PlayAt(cue, position, extra)
	local data = extra and table.clone(extra) or {}
	data.Cue = cue
	data.Position = position
	Net.Effect("Audio", data)
end

function AudioService.PlayFor(player, cue, position)
	Net.FireClient("AudioEvent", player, "Cue", { Cue = cue, Position = position })
end

function AudioService.GetSettings(player)
	return load(player)
end

function AudioService.Init()
	if initialized then
		return
	end
	initialized = true
	local okConfig, config = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Audio"):WaitForChild("AudioConfig"))
	end)
	DEFAULTS = okConfig and config.DefaultSettings or {}
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = ok and result or nil
	local remote = Net.Get("AudioEvent")
	remote.OnServerEvent:Connect(function(player, action, payload)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < REQUEST_INTERVAL then
			return
		end
		lastRequest[player] = now
		if action == "LoadSettings" then
			task.spawn(function()
				local settings = load(player)
				if player.Parent then
					remote:FireClient(player, "Settings", settings)
				end
			end)
		elseif action == "SaveSettings" then
			cache[player] = sanitize(payload)
			dirty[player] = true
			if not lastSave[player] or now - lastSave[player] >= SAVE_INTERVAL then
				task.spawn(save, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		cache[player], dirty[player], lastRequest[player], lastSave[player] = nil, nil, nil, nil
	end)
	-- flush pending saves periodically
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for player in pairs(dirty) do
				if player.Parent then
					task.spawn(save, player)
				end
			end
		end
	end)
	game:BindToClose(function()
		for player in pairs(dirty) do
			save(player)
		end
	end)
end

return AudioService
