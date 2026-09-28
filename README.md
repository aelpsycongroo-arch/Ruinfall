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
