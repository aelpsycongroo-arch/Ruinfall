-- ShopDefinitions: items, prices and gold rewards for the base shop.
-- Items are permanent stat boosts for the current match (lost on match end).

local ShopDefinitions = {}

ShopDefinitions.Order = { "Vitality", "Iron", "Swift", "Power", "Regen" }

ShopDefinitions.Items = {
	Vitality = {
		Key = "Vitality",
		Icon = "rbxassetid://119124627704951",
		DisplayName = "Vitality Crystal",
		Description = "+150 Max Health",
		Price = 250,
		Effect = { MaxHealth = 150 },
	},
	Iron = {
		Key = "Iron",
		Icon = "rbxassetid://125773215001141",
		DisplayName = "Iron Plating",
		Description = "+12 Armor",
		Price = 200,
		Effect = { Armor = 12 },
	},
	Swift = {
		Key = "Swift",
		Icon = "rbxassetid://126171007804464",
		DisplayName = "Swift Boots",
		Description = "+3 Move Speed",
		Price = 200,
		Effect = { MoveSpeed = 3 },
	},
	Power = {
		Key = "Power",
		Icon = "rbxassetid://106274881011204",
		DisplayName = "Power Blade",
		Description = "+12 Attack Damage",
		Price = 300,
		Effect = { AttackDamage = 12 },
	},
	Regen = {
		Key = "Regen",
		Icon = "rbxassetid://100682407147140",
		DisplayName = "Regen Charm",
		Description = "+0.4% Health Regen/s",
		Price = 150,
		Effect = { HealthRegen = 0.004 },
	},
}

-- Resale pricing: full refund within FULL_REFUND_WINDOW seconds, then SELL_RATIO after
ShopDefinitions.FULL_REFUND_WINDOW = 30
ShopDefinitions.SELL_RATIO = 0.75
ShopDefinitions.PRICE_INCREMENT = 50

ShopDefinitions.GoldRewards = {
	HeroKill = 150,
	MinionKill = 30,
	BruteKill = 50,
	RuinKill = 150,
	FlagKill = 60,
	PassivePerSecond = 2,
	-- Assists: anyone who damaged or crowd-controlled (stun / taunt) an enemy hero in the
	-- last AssistWindow seconds before it died earns AssistShare of the hero kill gold
	AssistShare = 0.6,
	AssistWindow = 5,
}

function ShopDefinitions.Get(key)
	return ShopDefinitions.Items[key]
end

function ShopDefinitions.IsValid(key)
	return type(key) == "string" and ShopDefinitions.Items[key] ~= nil
end

-- Calculate the sell price for an item given when it was purchased (os.time epoch)
function ShopDefinitions.GetSellPrice(item, purchasedAt, now)
	now = now or os.time()
	local elapsed = now - purchasedAt
	if elapsed < ShopDefinitions.FULL_REFUND_WINDOW then
		return item.Price -- full refund
	end
	return math.floor(item.Price * ShopDefinitions.SELL_RATIO + 0.5)
end

-- Calculate the buy price for a stat item given how many the player already owns.
-- Each purchase increases the next price by PRICE_INCREMENT gold.
function ShopDefinitions.GetBuyPrice(item, purchaseCount)
	return item.Price + ShopDefinitions.PRICE_INCREMENT * (purchaseCount or 0)
end

-- Uploaded painted icons (Shared.IconIds) override the shop icons above
do
	local module = script.Parent:FindFirstChild("IconIds")
	local ok, ids = pcall(function()
		return module and require(module)
	end)
	if ok and type(ids) == "table" then
		for key, icon in pairs(ids.Shop or {}) do
			if ShopDefinitions.Items[key] and icon ~= "" then
				ShopDefinitions.Items[key].Icon = icon
			end
		end
	end
end

return ShopDefinitions