-- Constants: tunable game-wide values shared by server and client

local Constants = {}

-- Debug -------------------------------------------------------------------
-- Server-side debug mode: bot state labels, monster aggro rings, spawn/ruin
-- markers, seed + state overlay, faster first ruin. Toggle here.
Constants.DEBUG_MODE = false
Constants.FORCED_SEED = nil -- set to a number to reproduce a specific map

-- Participants --------------------------------------------------------------
Constants.MAX_PARTICIPANTS = 18 -- players + bots per match (2 teams x 9, 4 x 4-5, 6 x 3)
Constants.MIN_PARTICIPANTS = 2

-- Match state machine ---------------------------------------------------------
Constants.MatchState = {
	LOBBY = "Lobby",
	PREPARING = "Preparing",
	GENERATING = "Generating",
	DEPLOYING = "Deploying", -- Royale only: players pick their landing spot on the map
	STARTING = "Starting",
	ACTIVE = "Active",
	ENDING = "Ending",
	RESULTS = "Results",
}

-- Team modes ----------------------------------------------------------------
-- TeamModeOrder = the CraterArena team modes (lobby buttons). "Royale" is the separate
-- 18-player free-for-all battle royale (its own hall gate, never shown as a team mode).
Constants.TeamModes = { TWO = "2Team", FOUR = "4Team", SIX = "6Team", ROYALE = "Royale" }
Constants.TeamModeOrder = { "2Team", "4Team", "6Team" }
Constants.TeamModeSlots = { ["2Team"] = 2, ["4Team"] = 4, ["6Team"] = 6, Royale = 18 }
Constants.TeamModeLabels = { ["2Team"] = "2 TEAM", ["4Team"] = "4 TEAM", ["6Team"] = "6 TEAM", Royale = "FREE FOR ALL" }

function Constants.IsRoyale(mode)
	return mode == "Royale"
end

Constants.Teams = {
	{ Name = "Crimson", Color = Color3.fromRGB(235, 70, 70) },
	{ Name = "Azure", Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Verdant", Color = Color3.fromRGB(70, 210, 120) },
	{ Name = "Gilded", Color = Color3.fromRGB(245, 200, 60) },
	{ Name = "Violet", Color = Color3.fromRGB(175, 110, 255) },
	{ Name = "Ember", Color = Color3.fromRGB(255, 140, 50) },
	-- 7..18: Royale free-for-all (every hero is its own team)
	{ Name = "Frost", Color = Color3.fromRGB(150, 230, 255) },
	{ Name = "Rose", Color = Color3.fromRGB(255, 120, 190) },
	{ Name = "Moss", Color = Color3.fromRGB(150, 190, 70) },
	{ Name = "Copper", Color = Color3.fromRGB(200, 120, 80) },
	{ Name = "Indigo", Color = Color3.fromRGB(100, 100, 230) },
	{ Name = "Jade", Color = Color3.fromRGB(60, 190, 160) },
	{ Name = "Ivory", Color = Color3.fromRGB(235, 225, 200) },
	{ Name = "Scarlet", Color = Color3.fromRGB(200, 30, 60) },
	{ Name = "Amber", Color = Color3.fromRGB(255, 175, 0) },
	{ Name = "Lilac", Color = Color3.fromRGB(200, 160, 255) },
	{ Name = "Teal", Color = Color3.fromRGB(0, 150, 170) },
	{ Name = "Ash", Color = Color3.fromRGB(140, 140, 150) },
}
Constants.NEUTRAL_TEAM = 0

-- Bots ------------------------------------------------------------------------
Constants.BotDifficultyOrder = { "Easy", "Normal", "Hard" }
Constants.BotDifficulty = {
	Easy = { ReactionDelay = 0.7, AimError = 7, Aggression = 0.55, RetreatHealth = 0.2, AbilityChance = 0.35, ThinkInterval = 0.4, FocusWeakest = false, LeadTargets = false },
	Normal = { ReactionDelay = 0.4, AimError = 3.5, Aggression = 0.8, RetreatHealth = 0.3, AbilityChance = 0.65, ThinkInterval = 0.25, FocusWeakest = false, LeadTargets = true },
	Hard = { ReactionDelay = 0.18, AimError = 1.5, Aggression = 1.0, RetreatHealth = 0.35, AbilityChance = 0.9, ThinkInterval = 0.15, FocusWeakest = true, LeadTargets = true },
}
Constants.DEFAULT_BOT_DIFFICULTY = "Normal"

-- Match flow -------------------------------------------------------------------
Constants.Match = {
	START_COUNTDOWN = 3,
	RESPAWN_TIME = 6,
	ENDING_DURATION = 3,
	RESULTS_DURATION = 20,
	BROADCAST_INTERVAL = 0.5,
}

-- Bases / flags / Last Stand --------------------------------------------------------
Constants.Flag = {
	MAX_HEALTH = 2500,
	ARMOR = 15,
	TURRET_RANGE = 30,
	SIEGE_RANGE = 32, -- flags only take damage from attackers standing this close (no safe long-range sieging)
	TURRET_DAMAGE = 100,
	FRAGILE_DAMAGE_PER_STACK = 20,
	TURRET_INTERVAL = 1.2,
	HEAL_RADIUS = 18,
	BASE_REGEN_PERCENT = 0.06, -- of max health per second while inside own base
	RESTORE_HEALTH_PERCENT = 0.5,
	REPAIR_PERCENT = 0.3, -- depositing a fragment at an intact flag
	REANCHOR_RADIUS = 9,
	REANCHOR_TIME = 2,
	VISION_RADIUS = 40,
}
Constants.LAST_STAND_DURATION = 15

-- Ruins ---------------------------------------------------------------------------
Constants.Ruin = {
	INTERVAL = 60,
	FIRST_SPAWN_DELAY = 60,
	DEBUG_FIRST_SPAWN_DELAY = 10,
	HEALTH = 1000,
	MAX_ACTIVE = 4,
	PLAYERS_PER_RUIN = 2,
}

-- Monsters / fragments ------------------------------------------------------------------
Constants.Monster = {
	CAMP_RESPAWN_TIME = 45,
	AGGRO_RANGE = 18,
	LEASH_RANGE = 38,
	FRAGMENT_DROP_CHANCE = 1.0,
	THINK_INTERVAL = 0.25,
}
Constants.Fragment = {
	PICKUP_RADIUS = 4.5,
	MAX_ON_GROUND = 8,
}

-- Combat ---------------------------------------------------------------------------
Constants.Combat = {
	COOLDOWN_TOLERANCE = 0.9, -- accept requests slightly early (latency)
	MAX_AIM_DISTANCE = 140,
	OUT_OF_COMBAT_TIME = 5,
	REQUESTS_PER_SECOND = 25,
	TICK_INTERVAL = 0.1,
	MOVEMENT_CHECK_INTERVAL = 0.5,
	MOVEMENT_TOLERANCE = 1.6,
}

-- Visibility -----------------------------------------------------------------------
Constants.Vision = {
	RADIUS = 58,
	BRUSH_REVEAL_RANGE = 9,
	UPDATE_INTERVAL = 0.2,
}

-- Royale (18-player free-for-all battle royale) ------------------------------------------
-- No class pick, no shop: everyone lands as a Fighter, finds weapons (= classes) and items
-- in supply chests, can be revived once by a planted cross, and the play zone shrinks
-- until one hero is left.
Constants.Royale = {
	MAP_RADIUS = 420,
	DEPLOY_TIME = 25, -- seconds to pick a landing spot on the map
	SPAWN_EXCLUSION = 60, -- a picked spot blocks this radius for everyone else
	SPAWN_EDGE_MARGIN = 30, -- keep landing spots this far inside the map edge
	START_RUINS = 34, -- loot ruins placed at match start
	RUIN_HEALTH = 450,
	RUIN_RESPAWN_INTERVAL = 50, -- a fresh ruin appears inside the zone this often
	LOOT_PER_RUIN = 2, -- items in the supply chest a ruin leaves behind
	RUIN_WEAPON_CHANCE = 0.2, -- extra chance that chest also holds a weapon
	PLAYERS_PER_START_WEAPON = 2, -- 18 players -> 9 weapon caches on the map at the start
	REVIVE_DELAY = 6, -- seconds from death to rising again at your planted cross
	CROSS_HEALTH = 450, -- enemies can smash a planted cross
	ZONE_START_DELAY = 70, -- seconds before the first shrink starts
	-- each phase: wait, then shrink over Shrink seconds to Radius (fraction of the map radius)
	ZONE_PHASES = {
		-- storm damage (% of max HP per second) doubles every phase
		{ Wait = 0, Shrink = 50, Radius = 0.62, DamagePercent = 0.02 },
		{ Wait = 45, Shrink = 40, Radius = 0.38, DamagePercent = 0.04 },
		{ Wait = 40, Shrink = 35, Radius = 0.2, DamagePercent = 0.08 },
		{ Wait = 35, Shrink = 30, Radius = 0.08, DamagePercent = 0.16 },
		{ Wait = 30, Shrink = 30, Radius = 0.0, DamagePercent = 0.32 },
	},
	ZONE_TICK = 0.5,
}

-- Loot: health potions (monsters, both modes) + dropped / looted items (Royale) ------------
Constants.Loot = {
	PICKUP_RADIUS = 6,
	POTION_HEAL_PERCENT = 0.35, -- of max health, restored over POTION_HEAL_TIME
	POTION_MANA_PERCENT = 0.35, -- of max mana, restored over the same time
	POTION_HEAL_TIME = 3,
	POTION_COOLDOWN = 8,
	MAX_POTIONS = 5,
	POTION_DROP_CHANCE = 0.45, -- per natural monster killed
	LOOT_LIFETIME = 180, -- seconds before a loose potion fades
	CHEST_LIFETIME = 300, -- seconds before a supply chest crumbles
	CHEST_MERGE_RADIUS = 12, -- gear dropped this close to a chest goes into that chest
	CHEST_REACH = 11, -- how close you must stay to use an open chest
}

-- Map --------------------------------------------------------------------------------
Constants.Map = {
	RADIUS = 150,
	GROUND_Y = 0,
	WALL_HEIGHT = 10,
	FOG_CELL = 12,
	FOG_HEIGHT = 11.5,
}

-- Camera -------------------------------------------------------------------------------
Constants.Camera = {
	HEIGHT = 62,
	MIN_HEIGHT = 34,
	MAX_HEIGHT = 95,
	ANGLE = 60, -- degrees down from horizontal
	FIELD_OF_VIEW = 50,
	SMOOTHNESS = 9,
	PEEK_FACTOR = 0.12,
	MAX_PEEK = 9,
}

-- UI palette ---------------------------------------------------------------------------
Constants.Colors = {
	Background = Color3.fromRGB(12, 13, 20),
	Panel = Color3.fromRGB(22, 24, 36),
	PanelLight = Color3.fromRGB(34, 37, 54),
	Stroke = Color3.fromRGB(70, 74, 104),
	Text = Color3.fromRGB(235, 236, 245),
	Subtext = Color3.fromRGB(150, 155, 180),
	Accent = Color3.fromRGB(140, 110, 255),
	Gold = Color3.fromRGB(255, 205, 90),
	Danger = Color3.fromRGB(240, 70, 70),
	Success = Color3.fromRGB(80, 220, 130),
	Warning = Color3.fromRGB(255, 180, 60),
	Shield = Color3.fromRGB(150, 210, 255),
	Fragment = Color3.fromRGB(120, 255, 240),
	Neutral = Color3.fromRGB(170, 170, 170),
}

function Constants.GetTeamColor(team)
	local info = Constants.Teams[team]
	return info and info.Color or Constants.Colors.Neutral
end

function Constants.GetTeamName(team)
	local info = Constants.Teams[team]
	return info and info.Name or "Neutral"
end

return Constants
