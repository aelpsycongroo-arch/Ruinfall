-- AssetHotSwapClient: applies image swaps made with the Ruinfall Asset Porter plugin during a
-- playtest on this client: patches the already-loaded config tables (item / class / shop icons,
-- HUD Theme art) and every GUI that shows the old image, including GUIs built later.
-- (Weapons, props and monsters are swapped by the server; animations are read live.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetSwap = require(Shared:WaitForChild("AssetSwap"))

local player = Players.LocalPlayer
local swaps = {} -- { { Old, New } } in order
local listening = false

local function patchModules(old, new)
	for _, name in ipairs({ "ItemDefinitions", "ClassDefinitions", "ShopDefinitions", "Constants" }) do
		local module = Shared:FindFirstChild(name)
		if module then
			local ok, data = pcall(require, module)
			if ok then
				AssetSwap.PatchTable(data, old, new)
			end
		end
	end
	local hud = script.Parent:FindFirstChild("HUD")
	local theme = hud and hud:FindFirstChild("Theme")
	if theme then
		local ok, data = pcall(require, theme)
		if ok then
			AssetSwap.PatchTable(data, old, new)
		end
	end
end

AssetSwap.Watch(function(old, new)
	table.insert(swaps, { Old = old, New = new })
	patchModules(old, new)
	local playerGui = player:WaitForChild("PlayerGui")
	AssetSwap.PatchInstances(playerGui, old, new)
	if not listening then
		listening = true
		-- GUIs cloned later from templates that still carry an old id
		playerGui.DescendantAdded:Connect(function(descendant)
			for _, swap in ipairs(swaps) do
				AssetSwap.PatchInstance(descendant, swap.Old, swap.New)
			end
		end)
	end
end)
