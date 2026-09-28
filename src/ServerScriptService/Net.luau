-- Net: creates remotes and batches server -> client messages

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Constants
local REMOTE_NAMES = {
	"LobbyRequest",
	"SelectClass",
	"MatchRequest",
	"AttackRequest",
	"AbilityRequest",
	"PlayerInput",
	"ShopRequest",
	"SellRequest",
	"ItemRequest", -- mythic items: Buy / Sell / Swap / BuyCreeps (server validates everything)
	"GameStateUpdate",
	"Notify",
	"VisibilityUpdate",
	"EffectEvent",
	"HubRequest", -- hub hall: Join / Leave / SetMode / Start / Sync (+ ReturnToHall on match servers)
	"HubState", -- hub hall: ("State", snapshot) / ("Notice", { Text, Style })
	"AudioEvent", -- audio: client Load/SaveSettings; server ("Settings", t) / ("Cue", { Cue, Position }) - see AudioService
	"LootRequest", -- ("UsePotion") both modes; Royale: Drop / OpenChest / CloseChest / Take / PlantCross; server -> client ("Chest" / "ChestClosed", payload)
	"RoyaleRequest", -- Royale deploy: ("Pick", Vector3 landing spot) - see RoyaleService
}

-- State
local Net = {}
local remotesFolder = nil
local effectQueue = {}
local flushConnection = nil

-- Public API
function Net.Init()
	if remotesFolder then
		return
	end
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(REMOTE_NAMES) do
		if not remotesFolder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotesFolder
		end
	end

	-- Effects are batched and flushed once per frame (one remote call per frame)
	flushConnection = RunService.Heartbeat:Connect(function()
		if #effectQueue > 0 then
			local batch = effectQueue
			effectQueue = {}
			remotesFolder.EffectEvent:FireAllClients(batch)
		end
	end)
end

function Net.Get(name)
	if not remotesFolder then
		Net.Init()
	end
	return remotesFolder:WaitForChild(name)
end

-- Queue a visual effect for every client (clients filter by fog of war)
function Net.Effect(kind, data)
	table.insert(effectQueue, { kind, data })
end

-- Send a notification. target: Player, array of Players, or nil for everyone.
-- style: "Info" | "Success" | "Warning" | "Danger" | "Ruin" | "Buff" | "Fragment"
-- options: { Banner = bool, Sub = string, Duration = number }
function Net.Notify(target, message, style, options)
	local remote = Net.Get("Notify")
	local payload = { Text = message, Style = style or "Info", Options = options or {} }
	if target == nil then
		remote:FireAllClients(payload)
	elseif typeof(target) == "Instance" then
		if target:IsA("Player") and target.Parent then
			remote:FireClient(target, payload)
		end
	elseif type(target) == "table" then
		for _, player in ipairs(target) do
			if typeof(player) == "Instance" and player.Parent then
				remote:FireClient(player, payload)
			end
		end
	end
end

function Net.FireAll(name, ...)
	Net.Get(name):FireAllClients(...)
end

function Net.FireClient(name, player, ...)
	if player and player.Parent == Players then
		Net.Get(name):FireClient(player, ...)
	end
end

return Net
