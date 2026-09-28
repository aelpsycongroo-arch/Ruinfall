# Ruinfall

A Roblox game.

## What's in this repo

- **`rainfall.rbxl`**: the full place file (map, models, UI, and all scripts). Open it in Roblox Studio.
- **`src/`**: every live script from the place, saved as plain `.luau` text so it can be read and diffed on GitHub.

`src/` mirrors the Studio Explorer:

| Folder                                     | Studio location                            |
|--------------------------------------------|--------------------------------------------|
| `src/ServerScriptService`                  | ServerScriptService (game server logic)    |
| `src/ReplicatedStorage`                    | ReplicatedStorage (shared config/modules)  |
| `src/StarterPlayer/StarterPlayerScripts`   | StarterPlayerScripts (client code and UI)  |
| `src/StarterPlayer/StarterCharacterScripts`| StarterCharacterScripts                    |
| `src/ServerStorage`                        | ServerStorage (Studio tools, HUD builders) |

File naming: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.
A folder containing `init.luau` is a ModuleScript that has child scripts.

The old copies in `ServerStorage/ScriptBackups` and `ServerStorage/RuinfallOldDraft` are still inside
`rainfall.rbxl` but aren't exported to `src/`, because Git history now keeps old versions.

## Syncing with Studio (optional)

This repo is set up for [Rojo](https://rojo.space). Run `rojo serve`, then click **Connect** in the
Rojo Studio plugin. Rojo only manages the scripts in `src/`; parts, models, UI and other objects in
the place are left alone.

## Game modes

The Ruinfall Hall has one gate per game mode:

| Gate | Mode | What it is |
|------|------|-----------|
| **Crater Arena** | 2 / 4 / 6 Team | The classic team battle: classes, shop, flags, minion waves. The arena sits in an impact crater (cosmetic rim and scorch marks; the layout is unchanged). |
| **Shattered Expanse** | Free For All (`Royale`) | 18 players, each on their own (you see yourself green, everyone else red). Pick a landing spot on the map (a pick blocks the area around it for others). Everyone starts as a Fighter; weapon caches (one per two players) turn you into another class. Broken ruins and fallen heroes leave supply chests: press F, drag gear onto your gear panel. Plant your Revive Cross to rise once after dying. Stay inside the shrinking zone - last one standing wins. |

Natural monsters drop **health potions** in both modes (walk over to collect, press **H** to drink).

Main code: `ServerScriptService/RoyaleService` (deploy, zone, loot ruins), `ServerScriptService/LootService`
(potions, loot pickups, dropping gear), `MatchManager.RunRoyaleMatch`, `MapGenerator.GenerateRoyale`,
and `StarterPlayerScripts/RoyaleUI` (landing map, zone HUD, gear/potion panel). Settings live in
`Constants.Royale` and `Constants.Loot`.

## Updating the place file from `src/`

After editing scripts in `src/`, write them into the place file:

```
python3 tools/rbxl_build.py rainfall.rbxl src rainfall.rbxl
```

Existing scripts get their new source; new `.luau` files become new scripts (their parent must already exist).
Needs `pip install lz4 zstandard`.
