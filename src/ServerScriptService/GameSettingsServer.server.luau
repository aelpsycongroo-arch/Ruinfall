-- GameSettingsServer: saves each player's game settings (hotkeys + HUD size) to a DataStore so
-- they follow the player between the Ruinfall Hall and match servers. Values are validated by
-- Shared.SettingsSchema. Without DataStores (Studio without API access) they last the session.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Net = require(script.Parent:WaitForChild("Net"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsSchema"))

local STORE_NAME = "RuinfallGameSettings_v1"
local SAVE_INTERVAL = 6
local REQUEST_INTERVAL = 0.3

local okStore, store = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
store = okStore and store or nil
local cache, dirty, lastSave, lastRequest = {}, {}, {}, {}

local function load(player)
	if cache[player] then
		return cache[player]
	end
	local data = nil
	if store then
		local ok, result = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		data = ok and result or nil
	end
	cache[player] = SettingsSchema.Sanitize(data)
	return cache[player]
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

local remote = Net.Get("SettingsEvent")
remote.OnServerEvent:Connect(function(player, action, payload)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < REQUEST_INTERVAL then
		return
	end
	lastRequest[player] = now
	if action == "Load" then
		task.spawn(function()
			local settings = load(player)
			if player.Parent then
				remote:FireClient(player, "Settings", settings)
			end
		end)
	elseif action == "Save" then
		cache[player] = SettingsSchema.Sanitize(payload)
		dirty[player] = true
		if not lastSave[player] or now - lastSave[player] >= SAVE_INTERVAL then
			task.spawn(save, player)
		else
			task.delay(SAVE_INTERVAL, save, player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	cache[player], dirty[player], lastSave[player], lastRequest[player] = nil, nil, nil, nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		save(player)
	end
end)
