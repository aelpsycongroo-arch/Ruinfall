-- ShopService: handles shop purchase requests from players.
-- Players can buy permanent stat-boost items while near their base or dead.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local ShopDefinitions = require(Shared:WaitForChild("ShopDefinitions"))
local Net = require(script.Parent:WaitForChild("Net"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

-- Constants
local STATE = Constants.MatchState
local BASE_SHOP_RADIUS = Constants.Flag.HEAL_RADIUS

-- State
local ShopService = {}

-- Functions
local function isNearBase(participant)
	if not participant or not participant.Team then
		return false
	end
	local baseState = BaseService.GetState(participant.Team)
	if not baseState then
		return false
	end
	local entity = participant.Entity
	if not entity or not entity.Alive or not entity.Root or not entity.Root.Parent then
		return false
	end
	local heroPos = CombatService.GetPosition(entity)
	local basePos = baseState.Base.Position
	return Util.FlatDistance(heroPos, basePos) <= BASE_SHOP_RADIUS
end

-- Shared shop-access rule (also used by ItemService): match active, not spectating,
-- and either alive near the team's base or dead (waiting to respawn at base).
function ShopService.CanShop(participant)
	if MatchManager.State ~= STATE.ACTIVE then
		return false, "Shop is only available during a match"
	end
	if MatchManager.IsRoyale and MatchManager.IsRoyale() then
		return false, "No shop in Free For All - break ruins to find gear"
	end
	if not participant or participant.Spectator then
		return false, "Spectators cannot shop"
	end
	local entity = participant.Entity
	local isAlive = entity and entity.Alive
	if isAlive and not isNearBase(participant) then
		return false, "Return to your base to shop"
	end
	if not isAlive and participant.State ~= "Dead" then
		return false, "You can only shop while alive at base or while dead"
	end
	return true
end

function ShopService.HandleRequest(player, itemKey)
	if type(itemKey) ~= "string" then
		return
	end
	if MatchManager.State ~= STATE.ACTIVE then
		Net.Notify(player, "Shop is only available during a match", "Warning")
		return
	end
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or participant.Spectator then
		return
	end
	if MatchManager.IsRoyale and MatchManager.IsRoyale() then
		Net.Notify(player, "No shop in Free For All - break ruins to find gear", "Warning")
		return
	end
	-- Must be alive near base, or dead (respawn at base)
	local entity = participant.Entity
	local isAlive = entity and entity.Alive
	if isAlive and not isNearBase(participant) then
		Net.Notify(player, "Return to your base to shop", "Warning")
		return
	end
	if not isAlive and participant.State ~= "Dead" then
		Net.Notify(player, "You can only shop while alive at base or while dead", "Warning")
		return
	end
	-- Validate item
	local item = ShopDefinitions.Get(itemKey)
	if not item then
		Net.Notify(player, "Unknown item", "Warning")
		return
	end
	-- Check gold (price increases with each purchase of the same item)
	local currentCount = participant.Purchases and participant.Purchases[itemKey] or 0
	local buyPrice = ShopDefinitions.GetBuyPrice(item, currentCount)
	local gold = PlayerService.GetGold(participant)
	if gold < buyPrice then
		Net.Notify(player, string.format("Not enough gold (%d / %d)", gold, buyPrice), "Warning", { Sound = "UI.PurchaseFail" })
		return
	end
	-- Process purchase
	PlayerService.AddGold(participant, -buyPrice)
	PlayerService.AddPurchase(participant, itemKey)
	Net.Notify(player, "Purchased " .. item.DisplayName .. "!", "Success", { Sound = "UI.SupplyPurchase" })
	-- If alive, recompute stats on the existing entity
	if isAlive and entity then
		local bonuses = CombatService.ComputeShopBonuses(participant)
		local classDef = entity.Class
		entity.MaxHealth = classDef.MaxHealth + bonuses.MaxHealth
		entity.Armor = classDef.Armor + bonuses.Armor
		entity.BaseSpeed = classDef.MoveSpeed + bonuses.MoveSpeed
		entity.BonusAttackDamage = bonuses.AttackDamage
		entity.BonusHealthRegen = bonuses.HealthRegen
		-- Heal the health gained from Vitality
		if bonuses.MaxHealth > 0 then
			entity.Health = math.min(entity.MaxHealth, entity.Health + bonuses.MaxHealth)
		end
		CombatService.SyncHealth(entity)
		CombatService.RecomputeSpeed(entity)
	end
	MatchManager.Broadcast()
end

function ShopService.HandleSellRequest(player, itemKey)
	if type(itemKey) ~= "string" then
		return
	end
	if MatchManager.State ~= STATE.ACTIVE then
		Net.Notify(player, "Shop is only available during a match", "Warning")
		return
	end
	local participant = PlayerService.GetParticipantByPlayer(player)
	if not participant or participant.Spectator then
		return
	end
	-- Same location rules as buying
	local entity = participant.Entity
	local isAlive = entity and entity.Alive
	if isAlive and not isNearBase(participant) then
		Net.Notify(player, "Return to your base to use the shop", "Warning")
		return
	end
	if not isAlive and participant.State ~= "Dead" then
		Net.Notify(player, "You can only use the shop while alive at base or while dead", "Warning")
		return
	end
	-- Validate item exists
	local item = ShopDefinitions.Get(itemKey)
	if not item then
		Net.Notify(player, "Unknown item", "Warning")
		return
	end
	-- Check if player owns this item
	local purchases = PlayerService.GetPurchases(participant)
	if not purchases[itemKey] or purchases[itemKey] <= 0 then
		Net.Notify(player, "You don't own this item", "Warning")
		return
	end
	-- Get the oldest purchase timestamp and calculate refund
	local purchasedAt = PlayerService.GetOldestTimestamp(participant, itemKey) or os.time()
	local sellPrice = ShopDefinitions.GetSellPrice(item, purchasedAt)
	-- Remove the purchase (FIFO)
	PlayerService.RemovePurchase(participant, itemKey)
	-- Refund gold
	PlayerService.AddGold(participant, sellPrice)
	-- Recompute stats if alive
	if isAlive and entity then
		local bonuses = CombatService.ComputeShopBonuses(participant)
		local classDef = entity.Class
		entity.MaxHealth = classDef.MaxHealth + bonuses.MaxHealth
		entity.Armor = classDef.Armor + bonuses.Armor
		entity.BaseSpeed = classDef.MoveSpeed + bonuses.MoveSpeed
		entity.BonusAttackDamage = bonuses.AttackDamage
		entity.BonusHealthRegen = bonuses.HealthRegen
		-- Clamp health to new max
		if entity.Health > entity.MaxHealth then
			entity.Health = entity.MaxHealth
		end
		CombatService.SyncHealth(entity)
		CombatService.RecomputeSpeed(entity)
	end
	local refundMsg = string.format("Sold %s for %d gold!", item.DisplayName, sellPrice)
	if sellPrice >= item.Price then
		refundMsg = string.format("Refunded %s for %d gold (full refund)", item.DisplayName, sellPrice)
	end
	Net.Notify(player, refundMsg, "Success", { Sound = "UI.Sell" })
	MatchManager.Broadcast()
end

function ShopService.Init()
	Net.Get("ShopRequest").OnServerEvent:Connect(function(player, itemKey)
		ShopService.HandleRequest(player, itemKey)
	end)
	Net.Get("SellRequest").OnServerEvent:Connect(function(player, itemKey)
		ShopService.HandleSellRequest(player, itemKey)
	end)
end

return ShopService