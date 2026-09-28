-- ForceR6Avatar: players walk around the Ruinfall Hall (hub servers) as R6 versions of
-- their own avatar. Match servers spawn every hero through PlayerService / CombatService,
-- so this script must stay out of their way: spawning an extra avatar there (e.g. after a
-- death) left a stray body in the arena that nothing could interact with.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- GameServer sets ServerRole ("Hub" / "Match") right after it starts
local function role()
	local waited = 0
	while ReplicatedStorage:GetAttribute("ServerRole") == nil and waited < 10 do
		waited += task.wait(0.1)
	end
	return ReplicatedStorage:GetAttribute("ServerRole")
end

local function isHub()
	return ReplicatedStorage:GetAttribute("ServerRole") == "Hub"
end

if role() ~= "Hub" then
	return -- match server: PlayerService owns all characters
end

-- Disable automatic character loading so we can manually spawn R6 characters
Players.CharacterAutoLoads = false

local function spawnR6Character(player)
	if not isHub() or player.Parent ~= Players then
		return -- the hub turned into a match server (Studio) or the player left
	end
	local success, humanoidDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)

	if not success or not humanoidDescription then
		warn("[ForceR6] Failed to get HumanoidDescription for " .. player.Name .. ", falling back to default LoadCharacter")
		if isHub() then
			player:LoadCharacter()
		end
		return
	end

	local modelSuccess, characterModel = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(humanoidDescription, Enum.HumanoidRigType.R6)
	end)

	if not modelSuccess or not characterModel then
		warn("[ForceR6] Failed to create R6 model for " .. player.Name .. ", falling back to default LoadCharacter")
		if isHub() then
			player:LoadCharacter()
		end
		return
	end

	if not isHub() or player.Parent ~= Players then
		characterModel:Destroy() -- the role changed while the avatar was being built
		return
	end
	characterModel.Name = player.Name
	player.Character = characterModel
	characterModel.Parent = workspace
end

local function onPlayerAdded(player)
	spawnR6Character(player)

	-- When the character dies in the hall, respawn as R6 after a delay
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				task.wait(Players.RespawnTime)
				-- only if this is still the hall and nothing else gave the player a new body
				if isHub() and player.Character == character then
					spawnR6Character(player)
				end
			end)
		end
	end)
end

-- Handle players already in the game
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Handle players who join later
Players.PlayerAdded:Connect(onPlayerAdded)
