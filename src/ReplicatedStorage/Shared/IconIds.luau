-- IconIds: uploaded icon images (the painted icons in tools/icons/out). Filled in by
-- tools/icons/apply_icons.py from tools/icons/icon_ids.json - edit that json, not this file.
-- An empty table keeps the existing icons. Values are "rbxassetid://<id>".
return {
	Items = {}, -- [ItemDefinitions item id] = icon (mythics, boots, passives)
	Shop = {}, -- [ShopDefinitions key] = icon (Vitality, Iron, Swift, Power, Regen)
	Special = {}, -- WarBand, MinionUpgrade
	Skills = {}, -- [class Q ability name] = icon (Shadow Step, Arcane Burst, ...)
}
