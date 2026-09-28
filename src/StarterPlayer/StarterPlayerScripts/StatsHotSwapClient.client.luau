-- StatsHotSwapClient: applies edits made with the Ruinfall Stats Editor plugin during a playtest to
-- this client's loaded ItemDefinitions / ClassDefinitions, so shop prices, tooltips and ability
-- numbers match the server right away (see Shared.StatPatch). Idle in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatPatch = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatPatch"))
StatPatch.Listen()
