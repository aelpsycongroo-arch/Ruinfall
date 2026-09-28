-- LeaderboardService: lifetime totals (hero kills, ruins destroyed) kept in OrderedDataStores.
-- Match servers add each real player's match stats when a match ends (both game modes);
-- the Ruinfall Hall reads the top entries for its leaderboard boards.
-- DataStores only work in a published game (in Studio: Game Settings -> Security ->
-- "Enable Studio Access to API Services"); every call is pcall'd so the game keeps running
-- without them and the boards just say the leaderboard is offline.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local LeaderboardService = {}

LeaderboardService.Boards = {
	{ Key = "Kills", Title = "TOTAL KILLS", Store = "RuinfallTotalKills_v1", Stat = "Kills" },
	{ Key = "Ruins", Title = "RUINS DESTROYED", Store = "RuinfallTotalRuins_v1", Stat = "Ruins" },
}
LeaderboardService.TOP_COUNT = 10

local stores = {}
local nameCache = {}

local function store(board)
	if stores[board.Key] == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.Store)
		end)
		stores[board.Key] = ok and result or false
	end
	return stores[board.Key] or nil
end

local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Player " .. tostring(userId)
end

-- participants: PlayerService participants at the end of a match (bots are skipped)
function LeaderboardService.RecordMatch(participants)
	for _, participant in ipairs(participants) do
		local userId = participant.UserId
		if not participant.IsBot and userId and userId > 0 and participant.Stats then
			for _, board in ipairs(LeaderboardService.Boards) do
				local amount = participant.Stats[board.Stat] or 0
				local target = store(board)
				if amount > 0 and target then
					task.spawn(function()
						local ok, err = pcall(function()
							target:IncrementAsync(tostring(userId), amount)
						end)
						if not ok then
							warn("[Leaderboard] could not save " .. board.Key .. " for " .. tostring(userId) .. ": " .. tostring(err))
						end
					end)
				end
			end
		end
	end
end

-- returns { { Name, Value }, ... } (best first), or nil + reason when DataStores are unavailable
function LeaderboardService.GetTop(board, count)
	local target = store(board)
	if not target then
		return nil, "unavailable"
	end
	local ok, pages = pcall(function()
		return target:GetSortedAsync(false, count or LeaderboardService.TOP_COUNT, 1)
	end)
	if not ok or not pages then
		return nil, tostring(pages)
	end
	local rows = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(rows, { Name = nameOf(tonumber(entry.key) or 0), Value = entry.value })
	end
	return rows
end

return LeaderboardService
