local Players = game:GetService("Players")

-- Disable automatic character loading so we can manually spawn R6 characters
Players.CharacterAutoLoads = false

local function spawnR6Character(player)
	local success, humanoidDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)

	if not success or not humanoidDescription then
		warn("[ForceR6] Failed to get HumanoidDescription for " .. player.Name .. ", falling back to default LoadCharacter")
		player:LoadCharacter()
		return
	end

	local modelSuccess, characterModel = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(humanoidDescription, Enum.HumanoidRigType.R6)
	end)

	if not modelSuccess or not characterModel then
		warn("[ForceR6] Failed to create R6 model for " .. player.Name .. ", falling back to default LoadCharacter")
		player:LoadCharacter()
		return
	end

	characterModel.Name = player.Name
	player.Character = characterModel
	characterModel.Parent = workspace
end

local function onPlayerAdded(player)
	spawnR6Character(player)

	-- When the character dies, respawn as R6 after a delay
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				task.wait(Players.RespawnTime)
				spawnR6Character(player)
			end)
		end
	end)
end

-- Handle players already in the game
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Handle players who join later
Players.PlayerAdded:Connect(onPlayerAdded)