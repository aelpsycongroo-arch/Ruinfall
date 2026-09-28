# Ruinfall

A Roblox game.

## Project layout

This repo uses [Rojo](https://rojo.space) to sync code between the filesystem and Roblox Studio.

| Folder        | Roblox location                                  |
|---------------|--------------------------------------------------|
| `src/server`  | `ServerScriptService.Server`                     |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`      |
| `src/shared`  | `ReplicatedStorage.Shared`                       |

File naming: `Name.server.luau` → Script, `Name.client.luau` → LocalScript, `Name.luau` → ModuleScript.

## Getting started

1. Install Rojo (e.g. via [Aftman](https://github.com/LPGhatguy/aftman) or the Rojo Studio plugin).
2. Run `rojo serve` in this folder.
3. In Roblox Studio, open the Rojo plugin and click **Connect**.

To build a place file: `rojo build -o Ruinfall.rbxlx`
