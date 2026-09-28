--[[
	AudioController (LocalScript) - boots the client audio system and wires it to the game.

	AudioManager (ReplicatedStorage.Audio) plays sounds; the hook modules in
	StarterPlayerScripts.AudioHooks listen to EXISTING game signals and decide what to play:
	  EffectAudio     server EffectEvent batch (hits, projectiles, explosions, objectives...)
	  CharacterAudio  hero models: footsteps, jump/land, casts (Q / items), hurt, low health
	  CreatureAudio   monsters / goblin minions / golems: idle, alert, attack, death, steps
	  MusicDirector   dynamic music (lobby / exploration / combat / boss / victory / defeat)
	  AmbientDirector world ambience beds + randomised one-shots per zone
	  UIAudio         buttons, menus, notifications, shop results, match events
	  AudioSettingsUI player volume menu (saved on the server)
	  AudioDebugPanel Studio-only sound tester (F7)
	To add a NEW hook: create a ModuleScript in AudioHooks with Init(ctx) and add its name below.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local AudioFolder = ReplicatedStorage:WaitForChild("Audio")
local AudioConfig = require(AudioFolder:WaitForChild("AudioConfig"))
local AudioManager = require(AudioFolder:WaitForChild("AudioManager"))
local AnimationEvents = require(AudioFolder:WaitForChild("AnimationEvents"))

local scripts = script.Parent
local hooksFolder = scripts:WaitForChild("AudioHooks")
local player = Players.LocalPlayer

-- Constants
local HOOKS = { "EffectAudio", "CharacterAudio", "CreatureAudio", "MusicDirector", "AmbientDirector", "UIAudio", "AudioSettingsUI", "AudioDebugPanel" }

-- Initialization
AudioManager.Init()

local ClientState = require(scripts:WaitForChild("ClientState"))
local FogController = require(scripts:WaitForChild("FogController"))

-- Shared context handed to every hook ------------------------------------------------------
local ctx = {
	Manager = AudioManager,
	Config = AudioConfig,
	ClientState = ClientState,
	AnimationEvents = AnimationEvents,
	LastCombatAt = 0,
	SkillCasts = {}, -- recent casts: { Skill, Position, Time, EntityId }
}

-- Fog of war: never let sound reveal something the player cannot see
function ctx.Visible(position)
	if not position then
		return false
	end
	local ok, visible = pcall(FogController.IsVisible, position)
	return not ok or visible ~= false
end

function ctx.InMatch()
	local ok, inMatch = pcall(ClientState.InMatch)
	return ok and inMatch
end

function ctx.MyCharacter()
	local character = player.Character
	if character and character.Parent and character:GetAttribute("EntityId") then
		return character
	end
	return nil
end

function ctx.MyEntityId()
	local character = ctx.MyCharacter()
	return character and character:GetAttribute("EntityId")
end

function ctx.MyTeam()
	local ok, team = pcall(ClientState.GetMyTeam)
	return ok and team or player:GetAttribute("Team") or 0
end

-- Anything that means "the local player is fighting" (dealt / took damage, hostile nearby)
function ctx.NoteCombat()
	ctx.LastCombatAt = os.clock()
end

local entityCache = {}
function ctx.FindModel(entityId)
	if not entityId then
		return nil
	end
	local cached = entityCache[entityId]
	if cached and cached.Parent and cached:GetAttribute("EntityId") == entityId then
		return cached
	end
	for _, tag in ipairs({ "RF_Hero", "RF_Creep", "RF_Monster" }) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			if model:GetAttribute("EntityId") == entityId then
				entityCache[entityId] = model
				return model
			end
		end
	end
	return nil
end

-- Skill casts remember their caster so the next area effect gets the skill's own impact sound
function ctx.RegisterSkillCast(skillId, position, entityId)
	local skill = AudioConfig.Skills[skillId]
	if not skill or not skill.Impact then
		return
	end
	table.insert(ctx.SkillCasts, { Skill = skillId, Position = position, Time = os.clock(), EntityId = entityId, Window = skill.ImpactWindow or 1 })
	if #ctx.SkillCasts > 16 then
		table.remove(ctx.SkillCasts, 1)
	end
end

function ctx.ConsumeSkillImpact(position)
	local now = os.clock()
	for index = #ctx.SkillCasts, 1, -1 do
		local cast = ctx.SkillCasts[index]
		if now - cast.Time > cast.Window then
			table.remove(ctx.SkillCasts, index)
		elseif position and (cast.Position - position).Magnitude <= 70 then
			table.remove(ctx.SkillCasts, index)
			return AudioConfig.Skills[cast.Skill].Impact
		end
	end
	return nil
end

-- Start every hook (each is isolated: one failing hook never silences the others)
for _, name in ipairs(HOOKS) do
	local moduleScript = hooksFolder:FindFirstChild(name)
	if moduleScript then
		local ok, err = pcall(function()
			require(moduleScript).Init(ctx)
		end)
		if not ok then
			warn("[Audio] hook failed to start:", name, err)
		end
	end
end
