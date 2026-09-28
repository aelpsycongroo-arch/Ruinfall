-- ClientState: latest server snapshot + helpers shared by client controllers.
-- The client never decides gameplay; it only presents what the server sends.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))

-- Constants
local STATE = Constants.MatchState
local player = Players.LocalPlayer

-- State
local ClientState = {}
ClientState.Game = nil
ClientState.VisibleIds = {}
ClientState.RevealAll = true
ClientState.Changed = Util.Signal.new() -- (state, previous)
ClientState.StateChanged = Util.Signal.new() -- (matchState, previousMatchState)
ClientState.VisibilityChanged = Util.Signal.new()
ClientState.Notified = Util.Signal.new() -- (payload)
ClientState.LocalMessage = Util.Signal.new() -- (text, style) client-only hints

-- Public API
function ClientState.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("GameStateUpdate").OnClientEvent:Connect(function(state)
		local previous = ClientState.Game
		ClientState.Game = state
		if not previous or previous.State ~= state.State then
			ClientState.StateChanged:Fire(state.State, previous and previous.State)
		end
		ClientState.Changed:Fire(state, previous)
	end)
	remotes:WaitForChild("VisibilityUpdate").OnClientEvent:Connect(function(payload)
		local visible = {}
		for _, id in ipairs(payload.Ids or {}) do
			visible[id] = true
		end
		ClientState.VisibleIds = visible
		-- stealthed enemies my team can see anyway (True Sight passive): drawn and targetable
		local revealedIds = {}
		for _, id in ipairs(payload.Revealed or {}) do
			revealedIds[id] = true
		end
		ClientState.RevealedIds = revealedIds
		ClientState.RevealAll = payload.RevealAll == true
		ClientState.VisibilityChanged:Fire()
	end)
	remotes:WaitForChild("Notify").OnClientEvent:Connect(function(payload)
		ClientState.Notified:Fire(payload)
	end)
end

function ClientState.GetMatchState()
	return ClientState.Game and ClientState.Game.State or STATE.LOBBY
end

function ClientState.InMatch()
	local state = ClientState.GetMatchState()
	return state == STATE.STARTING or state == STATE.ACTIVE or state == STATE.ENDING
end

function ClientState.GetMe()
	local game = ClientState.Game
	if not game then
		return nil
	end
	for _, participant in ipairs(game.Participants) do
		if not participant.IsBot and participant.UserId == player.UserId then
			return participant
		end
	end
	return nil
end

function ClientState.GetMyTeam()
	local me = ClientState.GetMe()
	return (me and me.Team) or player:GetAttribute("Team") or 0
end

function ClientState.IsHost()
	return ClientState.Game ~= nil and ClientState.Game.HostUserId == player.UserId
end

function ClientState.GetTeamState(team)
	local game = ClientState.Game
	if not game or not game.Teams then
		return nil
	end
	for _, teamState in ipairs(game.Teams) do
		if teamState.Team == team then
			return teamState
		end
	end
	return nil
end

function ClientState.GetParticipant(participantId)
	local game = ClientState.Game
	if not game then
		return nil
	end
	for _, participant in ipairs(game.Participants) do
		if participant.Id == participantId then
			return participant
		end
	end
	return nil
end

-- Is this stealthed enemy revealed to my team (True Sight)?
function ClientState.IsRevealed(model)
	return ClientState.RevealedIds ~= nil and ClientState.RevealedIds[model:GetAttribute("EntityId")] == true
end

-- Should this hero model be drawn for the local player?
function ClientState.IsHeroVisible(model)
	if model:GetAttribute("Team") == ClientState.GetMyTeam() then
		return true
	end
	if ClientState.RevealAll then
		return model:GetAttribute("Stealthed") ~= true
	end
	return ClientState.VisibleIds[model:GetAttribute("EntityId")] == true
end

function ClientState.GetLocalCharacter()
	local character = player.Character
	if character and character.Parent and character:GetAttribute("EntityId") and character:GetAttribute("Dead") ~= true then
		return character
	end
	return nil
end

return ClientState
