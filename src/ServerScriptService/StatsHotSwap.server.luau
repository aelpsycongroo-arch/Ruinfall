-- StatsHotSwap: applies edits made with the Ruinfall Stats Editor plugin during a playtest to the
-- server's loaded ItemDefinitions / ClassDefinitions (see Shared.StatPatch), then re-applies item +
-- class stats to every living hero. Idle in a published game (the patch folder never exists there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatPatch = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatPatch"))

local refreshQueued = false
local function refreshHeroes()
	refreshQueued = false
	-- required lazily: only once an edit arrives, long after the game's services have started
	local ok, CombatService = pcall(require, ServerScriptService:WaitForChild("CombatService"))
	if not ok then
		return
	end
	local count = 0
	for _, entity in pairs(CombatService.Entities or {}) do
		if type(entity) == "table" and entity.Kind == "Hero" and entity.Participant then
			if pcall(CombatService.RefreshParticipantBonuses, entity.Participant) then
				count += 1
			end
		end
	end
	print(string.format("[Ruinfall] Stats edit applied live - %d hero(es) refreshed", count))
end

StatPatch.Listen(function(patch)
	print(string.format("[Ruinfall] Stats edit: %s %s.%s = %s", patch.Kind, patch.Key, table.concat(patch.Path, "."),
		patch.Remove and "(removed)" or tostring(patch.Value)))
	if not refreshQueued then
		refreshQueued = true
		task.delay(0.1, refreshHeroes)
	end
end)
