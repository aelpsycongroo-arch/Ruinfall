-- AudioServer: starts AudioService (audio settings persistence + server cue helpers).
-- Runs on hub and match servers alike; independent of GameServer so audio never blocks gameplay.
local AudioService = require(script.Parent:WaitForChild("AudioService"))
local ok, err = pcall(AudioService.Init)
if not ok then
	warn("[Audio] AudioService failed to start:", err)
end
