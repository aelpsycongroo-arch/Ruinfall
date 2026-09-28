--[[
	EffectAudio - sounds for the server's replicated effect stream.

	Hooks the EXISTING RemoteEvent "EffectEvent" (one batched call per server frame, already
	sent to every client for visuals). No new network traffic: each client turns the same
	events into 3D sounds at the event position, so every player hears every fight correctly.
	Effects hidden by fog of war stay silent (same rule as the visuals).

	To give a new server effect a sound: add a handler below named after the effect kind.
	Server scripts can also send an explicit cue with AudioService.PlayAt -> kind "Audio".
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local GLOBAL = { RuinSpawn = true, RuinDestroyed = true, FlagDestroyed = true, FlagRestored = true, FragmentSpawn = true, Audio = true }
-- Effects produced by skills: their sounds are capped to AudioConfig.SkillAudio.MaxDuration
-- and fade out smoothly instead of ringing on
local SKILL_KINDS = {
	Projectile = true, ProjectileEnd = true, Melee = true, Explosion = true, Shockwave = true, Telegraph = true,
	Dash = true, Stealth = true, Lightning = true, Heal = true, Shield = true, Stun = true, HeavyKick = true,
	PointStrike = true, WindPull = true, SmokeCloud = true, BloodRush = true,
}

-- State
local EffectAudio = {}
local ctx, Manager, Config = nil, nil, nil
local handlers = {}
local projectiles = {} -- id -> { Origin, Direction, Speed, Range, Start }
local currentCap = nil -- MaxDuration applied while handling a skill effect

-- Helpers
local function play(cue, position, options)
	options = options or {}
	options.Position = position
	if currentCap and options.MaxDuration == nil then
		options.MaxDuration = currentCap
		options.FadeOut = Config.SkillAudio.FadeOut
	end
	return Manager:Play(cue, options)
end

local function classOf(entityId)
	local model = ctx.FindModel(entityId)
	return model and model:GetAttribute("Class"), model
end

local function involvesMe(data)
	local me = ctx.MyEntityId()
	return me ~= nil and (data.TargetId == me or data.SourceId == me)
end

-- Handlers -----------------------------------------------------------------------------------
handlers.Projectile = function(data)
	local style = Config.Projectiles[data.Style] or Config.Projectiles.Default
	if style.Launch then
		play(style.Launch, data.Origin, { Source = "Projectile " .. tostring(data.Style) })
	end
	if style.Travel and data.Direction and data.Speed then
		local projectile = { Origin = data.Origin, Direction = data.Direction, Speed = data.Speed, Range = data.Range or 60, Start = os.clock() }
		projectiles[data.Id] = projectile
		-- the travel sound follows the (predicted) projectile position so it whooshes past you
		Manager:Play(style.Travel, {
			MaxDuration = currentCap,
			FadeOut = Config.SkillAudio.FadeOut,
			Follow = function()
				if projectiles[data.Id] ~= projectile then
					return nil
				end
				local traveled = math.min(projectile.Speed * (os.clock() - projectile.Start), projectile.Range)
				return projectile.Origin + projectile.Direction * traveled
			end,
			Source = "Projectile travel",
		})
	end
end

handlers.ProjectileEnd = function(data)
	projectiles[data.Id] = nil
	local impact = ctx.ConsumeSkillImpact(data.Position)
	local style = Config.Projectiles[data.Style] or Config.Projectiles.Default
	play(impact or style.Impact, data.Position, { Source = "Projectile impact" })
end

handlers.Melee = function(data)
	local origin = data.Origin
	if data.EntityId then
		local class, model = classOf(data.EntityId)
		if model and model:GetAttribute("Rig") == "Goblin" then
			return -- CreatureAudio voices goblin attacks (synced to their animation)
		end
		local classAudio = class and Config.Classes[class]
		local cue = classAudio and classAudio.Swing or "Combat.SwordSwing"
		play(data.Empowered and "Combat.HeavySwing" or cue, origin, { Source = tostring(class) .. " swing" })
		if data.Empowered then
			play("Combat.CriticalHit", origin, { Volume = 0.5, Delay = 0.06 })
		end
	elseif data.Empowered then
		play("Combat.HeavySwing", origin, { Source = "Item melee" }) -- item skill arcs (Cleaving Arc, Whirlwind...)
	end
	-- no EntityId and not empowered = camp monster swing: CreatureAudio handles it
end

handlers.Damage = function(data)
	local position = data.Position
	if involvesMe(data) then
		ctx.NoteCombat()
	end
	local kind = data.Kind
	if kind == "Miss" then
		play("Combat.Miss", position)
		return
	elseif kind == "Shield" then
		play("Combat.ShieldBlock", position, { Volume = 0.8 })
		return
	end
	if (data.Amount or 0) <= 0 then
		return
	end
	local me = ctx.MyEntityId()
	if kind == "Crit" then
		if me and data.TargetId == me then
			Manager:Play("Player.CritHurt", { Source = "Crit on me" })
		else
			play("Combat.CriticalHit", position, { Source = "Crit" })
		end
		return
	end
	local targetKind = data.TargetKind
	local cue
	if targetKind == "Flag" or targetKind == "Ruin" then
		cue = "Objectives.FlagHit"
	elseif targetKind == "Monster" then
		cue = "Combat.StoneHit" -- the jungle monsters are living stone
	else
		local classAudio = data.SourceClass and Config.Classes[data.SourceClass]
		if data.Basic and classAudio and classAudio.Hit then
			cue = classAudio.Hit
		elseif data.SourceKind == "Monster" then
			cue = "Combat.BluntHit"
		else
			cue = "Combat.FleshHit"
		end
	end
	play(cue, position, { Volume = data.Reflected and 0.5 or 1, Source = tostring(data.SourceKind) .. "->" .. tostring(targetKind) })
	if data.Heavy and targetKind == "Hero" and data.TargetId ~= me then
		play("Combat.Stagger", position, { Volume = 0.8, Delay = 0.05 })
	end
	if targetKind == "Hero" and (data.TargetArmor or 0) >= 40 and math.random() < 0.35 then
		play("Combat.ArmorHit", position, { Volume = 0.7 })
	end
end

handlers.Explosion = function(data)
	local impact = ctx.ConsumeSkillImpact(data.Position)
	play(impact or "Combat.Explosion", data.Position, { Source = "Explosion" })
end

handlers.Shockwave = function(data)
	local impact = ctx.ConsumeSkillImpact(data.Position)
	if impact then
		play(impact, data.Position, { Source = "Skill shockwave" })
	elseif (data.Radius or 0) <= 3.5 then
		play("Monsters.GolemAttack", data.Position, { Volume = 0.8 })
	else
		play("Effects.GroundSlam", data.Position)
	end
end

handlers.Telegraph = function(data)
	play("Effects.MagicCharge", data.Position, { Source = "Telegraph" })
end

handlers.Dash = function(data)
	play("Movement.Dash", data.From)
end

handlers.Stealth = function(data)
	play("Effects.Stealth", data.Position)
end

handlers.Lightning = function(data)
	play("Effects.Lightning", data.To or data.From)
end

handlers.Heal = function(data)
	play("Effects.Heal", data.Position)
end

handlers.Shield = function(data)
	play("Effects.Shield", data.Position)
end

handlers.Stun = function(data)
	play("Effects.Stun", data.Position)
end

handlers.HeavyKick = function(data)
	play("Combat.Kick", data.Position)
end

handlers.PointStrike = function(data)
	play("Combat.CriticalHit", data.Position)
end

handlers.WindPull = function(data)
	play("Effects.Wind", data.Position)
end

handlers.SmokeCloud = function(data)
	play("Effects.Smoke", data.Position)
end

handlers.Death = function(data)
	if data.Kind == "Hero" then
		play("Player.Death", data.Position, { Source = "Hero death" })
	end
	-- Monster / Creep deaths are voiced by CreatureAudio; flags and ruins by their own effects
end

handlers.RuinSpawn = function(data)
	Manager:PlayStinger("Objectives.RuinSpawn", { Position = data.Position, Source = "Ruin spawn" })
end

handlers.RuinDestroyed = function(data)
	play("Objectives.RuinDestroyed", data.Position)
	local character = ctx.MyCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - data.Position).Magnitude < 70 then
		Manager:PlayStinger("Music.Victory", { Volume = 0.6 }) -- you were part of the fight
	end
end

handlers.FlagDestroyed = function()
	Manager:PlayStinger("Objectives.FlagDestroyed")
end

handlers.FlagRestored = function()
	Manager:Play("Objectives.FlagRestored")
end

handlers.FragmentSpawn = function(data)
	play("Objectives.FragmentSpawn", data.Position)
end

handlers.Pickup = function(data)
	play("Objectives.FragmentPickup", data.Position)
end

-- Explicit server cue (AudioService.PlayAt)
handlers.Audio = function(data)
	if type(data.Cue) == "string" then
		play(data.Cue, data.Position, { Source = "Server cue" })
	end
end

-- Public API ---------------------------------------------------------------------------------
function EffectAudio.Handle(kind, data)
	local handler = handlers[kind]
	if not handler or type(data) ~= "table" then
		return
	end
	if not GLOBAL[kind] then
		if not ctx.InMatch() then
			return
		end
		local position = data.Position or data.Origin or data.From or data.To
		if position and not ctx.Visible(position) then
			return
		end
	end
	currentCap = SKILL_KINDS[kind] and Config.SkillAudio.MaxDuration or nil
	local ok, err = pcall(handler, data)
	currentCap = nil
	if not ok then
		warn("[Audio] effect sound error", kind, err)
	end
end

function EffectAudio.Init(context)
	ctx = context
	Manager = ctx.Manager
	Config = ctx.Config
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("EffectEvent").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then
			return
		end
		for _, item in ipairs(batch) do
			EffectAudio.Handle(item[1], item[2])
		end
	end)
	-- forget projectiles that never reported an end (cheap cleanup, 1 Hz)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for id, projectile in pairs(projectiles) do
				if now - projectile.Start > 6 then
					projectiles[id] = nil
				end
			end
		end
	end)
	return EffectAudio
end

return EffectAudio
