--[[
	CharacterAudio - hero sounds (players AND bots).

	* Footsteps for every visible hero near the listener. Surface comes from the part under the
	  feet (name keywords, then material - see AudioConfig.Footsteps). Step rate follows the real
	  ground speed; nothing plays while airborne. Simulated at 10 Hz, never per frame.
	* Skill casts: the server already replicates LastAbilityAt (class Q) and ItemCastAbility /
	  ItemCastAt (item E / R / boots) on the hero model -> Cast / Charge / Release / Extra layers
	  from AudioConfig.Skills, and the cast is remembered for its impact sound (EffectAudio).
	* Local player only: jump / land / heavy landing, hurt / heavy hurt, low-health heartbeat,
	  stun, reveal, death + respawn cues. Roblox's default character sounds are muted so they do
	  not double up with ours.
]]

-- Services
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- Constants
local DEFAULT_SOUNDS = { Running = true, Jumping = true, Landing = true, FreeFalling = true, Died = true, GettingUp = true, Climbing = true }
local LOW_HEALTH = 0.3
local HEAVY_HIT = 0.15 -- share of max health lost in one hit that counts as a heavy hit
local player = Players.LocalPlayer

-- State
local CharacterAudio = {}
local ctx, Manager, Config = nil, nil, nil
local heroes = {} -- model -> { NextStep, WasStealthed }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local local_ = { Health = nil, Dead = false, LowHealth = false, FallSpeed = 0 }

-- Footstep surface ---------------------------------------------------------------------------
local function surfaceOf(part)
	local steps = Config.Footsteps
	local name = string.lower(part.Name .. " " .. (part.Parent and part.Parent.Name or ""))
	for _, pair in ipairs(steps.NameKeywords) do
		if string.find(name, pair[1], 1, true) then
			return pair[2]
		end
	end
	return steps.Materials[part.Material.Name] or steps.Default
end

local function groundUnder(model, root)
	rayParams.FilterDescendantsInstances = { model, workspace:FindFirstChild("LocalEffects") }
	return workspace:Raycast(root.Position, Vector3.new(0, -6, 0), rayParams)
end

-- Skill casts --------------------------------------------------------------------------------
local function playSkill(skillId, model)
	local skill = Config.Skills[skillId]
	local root = model:FindFirstChild("HumanoidRootPart")
	if not skill or not root then
		return
	end
	if model ~= ctx.MyCharacter() and not ctx.Visible(root.Position) then
		return
	end
	local source = "Skill " .. skillId
	-- every layer of a skill ends (with a fade) within SkillAudio.MaxDuration of the cast
	local cap = Config.SkillAudio.MaxDuration
	local fade = Config.SkillAudio.FadeOut
	local volume = skill.Volume or 1
	local function layer(cue, delay)
		Manager:Play(cue, { Follow = root, Delay = delay, Volume = volume, MaxDuration = cap, FadeOut = fade, Source = source })
	end
	if skill.Cast then
		layer(skill.Cast, nil)
	end
	if skill.Charge then
		layer(skill.Charge, 0.05)
	end
	if skill.Release then
		layer(skill.Release, skill.ReleaseDelay or 0.15)
	end
	if skill.Extra then
		layer(skill.Extra, 0.08)
	end
	if skill.Mythic then
		layer("Effects.MythicShimmer", 0.1)
	end
	ctx.RegisterSkillCast(skillId, root.Position, model:GetAttribute("EntityId"))
	if model == ctx.MyCharacter() then
		ctx.NoteCombat()
	end
end

local function trackHero(model)
	if heroes[model] then
		return
	end
	local state = { NextStep = 0 }
	heroes[model] = state
	model:GetAttributeChangedSignal("LastAbilityAt"):Connect(function()
		local class = model:GetAttribute("Class")
		local classAudio = class and Config.Classes[class]
		if classAudio and classAudio.Ability then
			playSkill(classAudio.Ability, model)
		end
	end)
	model:GetAttributeChangedSignal("ItemCastAt"):Connect(function()
		local abilityId = model:GetAttribute("ItemCastAbility")
		if abilityId then
			playSkill(abilityId, model)
		end
	end)
	model:GetAttributeChangedSignal("Stealthed"):Connect(function()
		if model:GetAttribute("Stealthed") == false and state.WasStealthed then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and ctx.Visible(root.Position) then
				Manager:Play("Effects.Reveal", { Position = root.Position })
			end
		end
		state.WasStealthed = model:GetAttribute("Stealthed") == true
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			heroes[model] = nil
		end
	end)
end

-- Footsteps: one 10 Hz pass over nearby heroes ------------------------------------------------
local function footstepPass()
	local listener = Manager:GetListenerPosition()
	local steps = Config.Footsteps
	local now = os.clock()
	local me = player.Character
	for model, state in pairs(heroes) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and model:GetAttribute("Dead") ~= true and (root.Position - listener).Magnitude <= steps.MaxHeroDistance then
			local velocity = root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if speed > 2.5 and math.abs(velocity.Y) < 12 then
				if now >= state.NextStep then
					local visible = model == me or (ctx.ClientState.IsHeroVisible(model) and ctx.Visible(root.Position))
					local ground = groundUnder(model, root)
					if visible and ground then
						local surface = surfaceOf(ground.Instance)
						local class = Config.Classes[model:GetAttribute("Class") or ""]
						local volume = (class and class.StepVolume or 0.8) * (model == me and 1 or 0.8)
						Manager:Play("Footsteps." .. surface, { Position = ground.Position, Volume = volume, Source = model.Name })
						if class and class.ArmorRattle and math.random() < 0.5 then
							Manager:Play("Footsteps.ArmorRattle", { Position = root.Position })
						end
					end
					local interval = steps.WalkInterval * steps.ReferenceSpeed / math.max(speed, 6)
					state.NextStep = now + math.clamp(interval, 0.22, 0.65) * (0.94 + math.random() * 0.12)
				end
			else
				state.NextStep = math.max(state.NextStep, now + 0.08) -- first step lands shortly after starting to move
			end
		end
	end
end

-- Local player -------------------------------------------------------------------------------
local function setLowHealth(isLow)
	if isLow == local_.LowHealth then
		return
	end
	local_.LowHealth = isLow
	if isLow then
		Manager:StartLoop("Heartbeat", "Player.Heartbeat", { Fade = 0.8 })
		Manager:SetMusicDuck("LowHealth", Config.MusicRules.LowHealthDuck)
	else
		Manager:StopLoop("Heartbeat", 1.2)
		Manager:SetMusicDuck("LowHealth", nil)
	end
end

local function hookMyCharacter(character)
	-- mute Roblox's default character sounds (RbxCharacterSounds); ours replace them
	local function mute(item)
		if item:IsA("Sound") and DEFAULT_SOUNDS[item.Name] then
			item.Volume = 0
		end
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		for _, item in ipairs(root:GetChildren()) do
			mute(item)
		end
		root.ChildAdded:Connect(mute)
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and root then
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				Manager:Play("Movement.Jump", { Position = root.Position })
			elseif new == Enum.HumanoidStateType.Landed then
				local fall = local_.FallSpeed
				if fall > 55 then
					Manager:Play("Movement.HeavyLand", { Position = root.Position })
				elseif fall > 12 then
					Manager:Play("Movement.Land", { Position = root.Position })
				end
				local_.FallSpeed = 0
			end
		end)
		humanoid.FreeFalling:Connect(function(active)
			if active then
				local_.FallSpeed = 0
				task.spawn(function()
					while humanoid.Parent and humanoid:GetState() == Enum.HumanoidStateType.Freefall do
						local_.FallSpeed = math.max(local_.FallSpeed, -root.AssemblyLinearVelocity.Y)
						task.wait(0.05)
					end
				end)
			end
		end)
	end
	-- health / death / stun come from the server-authoritative attributes
	local_.Health = character:GetAttribute("Health")
	character:GetAttributeChangedSignal("Health"):Connect(function()
		local health = character:GetAttribute("Health") or 0
		local maxHealth = math.max(1, character:GetAttribute("MaxHealth") or 1)
		local previous = local_.Health or health
		local_.Health = health
		if health < previous and character:GetAttribute("Dead") ~= true then
			local lost = previous - health
			ctx.NoteCombat()
			if lost >= maxHealth * HEAVY_HIT then
				Manager:Play("Player.HeavyHurt", { Source = "Me" })
			else
				Manager:Play("Player.Hurt", { Source = "Me" })
			end
		end
		setLowHealth(health > 0 and health / maxHealth < LOW_HEALTH and character:GetAttribute("Dead") ~= true)
	end)
	character:GetAttributeChangedSignal("Dead"):Connect(function()
		local dead = character:GetAttribute("Dead") == true
		if dead and not local_.Dead then
			setLowHealth(false)
			Manager:SetMusicDuck("Dead", Config.MusicRules.DeadDuck)
		elseif not dead and local_.Dead then
			Manager:SetMusicDuck("Dead", nil)
			Manager:Play("Player.Respawn")
		end
		local_.Dead = dead
	end)
	local lastStun = character:GetAttribute("StunnedUntil") or 0
	character:GetAttributeChangedSignal("StunnedUntil"):Connect(function()
		local untilTime = character:GetAttribute("StunnedUntil") or 0
		if untilTime > lastStun then
			Manager:Play("Player.Stunned") -- a new / extended stun on me
		end
		lastStun = untilTime
	end)
	local_.Dead = character:GetAttribute("Dead") == true
	if not local_.Dead then
		Manager:SetMusicDuck("Dead", nil)
	end
end

-- Public API -----------------------------------------------------------------------------------
function CharacterAudio.Init(context)
	ctx = context
	Manager = ctx.Manager
	Config = ctx.Config
	for _, model in ipairs(CollectionService:GetTagged("RF_Hero")) do
		trackHero(model)
	end
	CollectionService:GetInstanceAddedSignal("RF_Hero"):Connect(trackHero)
	-- the local player's character (hero model or hall avatar)
	if player.Character then
		trackHero(player.Character) -- footsteps also in the hub hall, where the avatar is not a tagged hero
		task.spawn(hookMyCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		setLowHealth(false)
		trackHero(character)
		hookMyCharacter(character)
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(footstepPass)
			if not ok then
				warn("[Audio] footsteps", err)
				task.wait(1)
			end
		end
	end)
	return CharacterAudio
end

return CharacterAudio
