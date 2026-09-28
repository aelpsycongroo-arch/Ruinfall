--[[
	HUD.Theme - visual configuration for the in-match HUD (colours, fonts, art, layout).
	Gameplay code never reads this; the HUD builder and the HUD components do.
	Layout numbers are authored on a 1500 x 900 reference screen (the reference screenshot) and
	converted to Scale by the builder, so the HUD keeps its proportions on any resolution.
]]

local Theme = {}

Theme.Reference = Vector2.new(1500, 900)

Theme.Colors = {
	Black = Color3.fromHex("15120F"),
	Panel = Color3.fromHex("211A15"),
	Gold = Color3.fromHex("B88A3B"),
	GoldBright = Color3.fromHex("E2B85A"),
	Crimson = Color3.fromHex("9E2028"),
	Red = Color3.fromHex("D73535"),
	Azure = Color3.fromHex("2868B8"),
	Cyan = Color3.fromHex("24D6E8"),
	Text = Color3.fromRGB(240, 232, 216),
	Muted = Color3.fromRGB(176, 162, 138),
	Cream = Color3.fromRGB(236, 214, 170),
	Track = Color3.fromRGB(24, 12, 12),
	Mana = Color3.fromRGB(64, 132, 235),
	ManaTrack = Color3.fromRGB(10, 14, 28),
}

Theme.Fonts = {
	Title = Font.new("rbxasset://fonts/families/Guru.json", Enum.FontWeight.Bold),
	Body = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular),
	BodyBold = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
	Number = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
}

-- Frame art rendered in Blender (dark iron / bronze thorns / crimson) + icons
Theme.Art = {
	TeamPanel = "rbxassetid://73699275466398", -- 340 x 160
	FlagPanel = "rbxassetid://121812067840818", -- 340 x 84
	Scoreboard = "rbxassetid://113069396572952", -- 690 x 112 (crossed swords baked in)
	Minimap = "rbxassetid://129296856025947", -- old ring (330 x 330, N + zoom tiles), unused
	-- minimap border, 440 x 454, round hole centred at (224, 222) r ~174. Base / Tint split like
	-- the bottom HUD: the red accents live in the white Tint image and follow the team colour.
	MinimapBorder = "rbxassetid://72195903279319",
	MinimapBorderTint = "rbxassetid://127811036651993",
	Portrait = "rbxassetid://94756892705174", -- 250 x 250 ring
	PlayerPanel = "rbxassetid://125824664699380", -- 640 x 200
	AbilityBar = "rbxassetid://79014549386216", -- 740 x 180 (5 slots + key tabs baked in)
	LevelBadge = "rbxassetid://98910988582833", -- 60 x 60
	BannerCloth = "rbxassetid://138878499514238", -- 64 x 112, white (tinted per team)
	BannerTrim = "rbxassetid://128197857921082", -- rod, gold piping, lion
	FlagCloth = "rbxassetid://83396569194706", -- 44 x 70, white (tinted)
	FlagTrim = "rbxassetid://78708682523734",
	Hourglass = "rbxassetid://90785903800615",
	IconMelee = "rbxassetid://133347552670459",
	IconBloodRush = "rbxassetid://137770348514002",
	IconItem = "rbxassetid://88414600504840",
	IconBoots = "rbxassetid://113608455735429",
	-- bottom HUD (portrait + player panel + LM/Q/E/R/MR bar), 1627 x 353 split into two tiles.
	-- Base = the art with its red accents turned grey; Tint = those accents in white, coloured
	-- with the team colour at runtime (ImageColor3).
	BottomBaseL = "rbxassetid://137934457452754", -- x 0..815
	-- right tile: the old MR compartment is a 2 x 2 grid of small framed cells (boots top-left with
	-- a small MR tab, PASSIVE 1 / 2 / 3 in the other cells). Previous right tiles (one big MR slot):
	-- base rbxassetid://106270520333201, tint rbxassetid://93894953857257
	BottomBaseR = "rbxassetid://80834850570664", -- x 812..1627
	BottomTintL = "rbxassetid://99713454817856",
	BottomTintR = "rbxassetid://102347943199616",
	-- top plaques (team / your flag / scoreboard), cut from one painted sheet. Live values (team
	-- name, alive counts, flag bars and numbers, the hourglass) are erased from the art and drawn
	-- by the HUD. Tint images = the red (or, on the scoreboard's right half, blue) parts in white.
	TopTeamBase = "rbxassetid://71418011554350", -- 431 x 221
	TopTeamTint = "rbxassetid://120538943175928",
	TopFlagBase = "rbxassetid://71886626119023", -- 443 x 149
	TopFlagTint = "rbxassetid://115888007548823",
	ScoreBase = "rbxassetid://112576979049987", -- 764 x 202
	ScoreTintL = "rbxassetid://105903961216569", -- left team (red in the art)
	ScoreTintR = "rbxassetid://111268031177158", -- right team (blue in the art)
	TopHourglass = "rbxassetid://88394646402141", -- 34 x 41
	-- Ruinfall Hall menu (same painted plaques, text removed; tints reuse TopTeamTint/TopFlagTint)
	HallTitleBase = "rbxassetid://87106019747038", -- 431 x 221 lion-banner plaque
	HallRowBase = "rbxassetid://92180349397960", -- 443 x 149 plaque with the small flag
	HallTallBase = "rbxassetid://102374370870687", -- 443 x 580 tall plaque (war party)
	HallTallTint = "rbxassetid://132860965852279",
}

-- Colour used for TeamTint images: the team colour scaled so its brightest channel is 1, with
-- its saturation pushed a little (keeps the art's brightness and deep colour: the red team looks
-- like the original art, the blue team turns the same deep blue as the scoreboard's right half)
local TINT_SATURATION = 1.35
function Theme.TintColor(teamColor)
	local m = math.max(teamColor.R, teamColor.G, teamColor.B, 1e-3)
	local function ch(v)
		return math.clamp(1 - (1 - v / m) * TINT_SATURATION, 0, 1)
	end
	return Color3.new(ch(teamColor.R), ch(teamColor.G), ch(teamColor.B))
end

-- Team-name text on the scoreboard plaques: a pale version of the team colour; red teams use
-- gold instead (red text on the red half would not read - same as the painted original)
function Theme.TeamNameColor(teamColor)
	if teamColor.R > 0.8 and teamColor.G < 0.4 and teamColor.B < 0.4 then
		return Theme.Colors.GoldBright
	end
	return teamColor:Lerp(Color3.new(1, 1, 1), 0.6)
end

-- Button looks for the painted menus (Ruinfall Hall): rounded, gold-rimmed, bar-like sheen
Theme.ButtonStyles = {
	Primary = { Fill = Color3.fromRGB(196, 22, 32), Stroke = Theme.Colors.Gold, Text = Color3.fromRGB(255, 240, 222) },
	Gold = { Fill = Theme.Colors.GoldBright, Stroke = Color3.fromRGB(120, 84, 30), Text = Color3.fromRGB(40, 26, 12) },
	Dark = { Fill = Theme.Colors.Panel, Stroke = Theme.Colors.Gold, Text = Theme.Colors.Cream },
	Danger = { Fill = Color3.fromRGB(72, 14, 18), Stroke = Theme.Colors.Crimson, Text = Theme.Colors.Cream },
	Disabled = { Fill = Color3.fromRGB(44, 39, 35), Stroke = Color3.fromRGB(92, 80, 62), Text = Color3.fromRGB(132, 122, 106) },
}

-- Ability icons by ability name (falls back to the class emblem)
Theme.AbilityIcons = {
	["Blood Rush"] = Theme.Art.IconBloodRush,
}

-- Input mapping shown on the ability bar (DO NOT CHANGE: LM melee, Q class ability,
-- E / R item slots, MR boots). The 3 passive slots next to the boots have no key.
Theme.Slots = {
	{ Key = "LM", Name = "MELEE", Kind = "Attack" },
	{ Key = "Q", Name = "BLOOD RUSH", Kind = "Ability" },
	{ Key = "E", Name = "ITEM", Kind = "Item", Index = 1 },
	{ Key = "R", Name = "ITEM", Kind = "Item", Index = 2 },
	{ Key = "MR", Name = "BOOTS", Kind = "Boots" },
}

return Theme
