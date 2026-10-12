# MISERY mods (complete UE4SS `Mods` folder)

A ready-to-use [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) `Mods` folder for **MISERY**.
It holds bug fixes, quality-of-life mods and updated versions of community mods, all switched on.

Tested against MISERY Steam build 25711265 (UE 5.4) with UE4SS v3.0.1.

## Install

UE4SS must already be installed (the game has `MISERY\Binaries\Win64\ue4ss`).

1. Close MISERY.
2. Download this repository (**Code → Download ZIP**) and extract it.
3. Delete `<Steam library>\steamapps\common\MISERY\MISERY\Binaries\Win64\ue4ss\Mods`.
4. Copy the extracted folder there and rename it to `Mods`.
   Afterwards the game has `...\ue4ss\Mods\StackThemAll`, `...\Mods\shared`, `...\Mods\mods.txt` and so on.
5. Start the game. Every mod writes a "Loaded" line to `...\Win64\ue4ss\UE4SS.log`.

To install only some mods, copy just those folders into your existing `Mods` folder.
Each one has an `enabled.txt` that switches it on, and every mod needs `shared`.

Keep a copy of your folder. StackThemAll writes new items into its `stackConfig.lua`.

## What's inside

Each of these mods is switched on by the `enabled.txt` in its folder:

| Mod | What it does |
|---|---|
| **StackThemAll** | Bigger stacks. Adds items from game updates automatically. Money stacks to 250. In co-op everyone needs the same stack settings. |
| **MISERYModMenu** | PageUp menu with a modern dark look, in-game item names, a search box, single spawn and console commands. In co-op the host's menu gives joined players their items and stats; time, weather and enemies are the host's. |
| **Mi8CargoHold** | The Mi-8 wreck becomes a 1,000-slot storage container. In co-op the host's hold is shared: everyone who has this mod can open it, and the host's save keeps it. |
| **WorldTweaks** *(new)* | Day/night length (22 / 4), season and darker nights in one config. Replaces DayLengthTweaks and the Darker Nights pak. In co-op the host's day length and season apply to everyone. |
| **RadiationShield** *(new)* | HOME toggles less radiation (for bunker hot spots), with an on-screen badge. `.radmenu` opens a settings menu with a live radiation readout. In co-op each player has their own shield, if the host allows it. |
| **BackpackWeightFix** *(new)* | Resets empty containers stuck with weight (e.g. 73/75 kg) to 0 every 30 s. In co-op the host's copy fixes everyone's. |
| **ModHub** *(new)* | `.mods` opens a menu of the loaded mods: each one's hotkeys and console commands, a button for mods with their own menu, and restarting mods you've changed (no game restart). |
| **RandomEmissions** | Random emission times and a warning siren. Fixed so it no longer piles up. In co-op the host's game picks the times and everyone hears the siren. |
| **MISERY_StructuralFreedom** | Relaxed building support rules (unchanged). In co-op everyone needs it. |
| **NotSoShaky** | Softer camera shake when hit (unchanged). |

UE4SS's own mods are switched on or off in `mods.txt`; leave them as they are:

- On: CheatManagerEnablerMod, ConsoleCommandsMod, ConsoleEnablerMod, BPML_GenericFunctions, BPModLoaderMod, Keybinds.
- Off: LineTraceMod, SplitScreenMod.
- `shared` is a library the other mods need. It isn't a mod; never delete it.

### Replaces

- **Darker Nights** pak (`777_DarkerNights_P` in `MISERY\Content\Paks\~mods`): WorldTweaks does the same thing.
  The pak only lowered the night sky brightness from 20 to 7.5 in spring, summer and autumn; winter is already 0.4.
  Delete its three files. If you keep both, the pak's older copy of the weather table wins.
- **DayLengthTweaks**: also part of WorldTweaks.

## Co-op

Every mod works in co-op. Install the same mods (and settings) on every player's game; the host's game decides what
happens in the host's world. The mods talk to each other through two messages that are built into Unreal Engine.
The host's answers show as lines in the joined player's console.

| Mod | In someone else's world |
|---|---|
| RadiationShield | Your own shield, if the host allows it, at the host's strength (see [Radiation Shield menu](#radiation-shield-menu)) |
| MISERYModMenu | Spawn, `.heal`, `.feed` and the other stats, `.instaheal`, `.infstam` and `.god` are done for you by the host's menu. Time, weather, season, enemies, events, slow motion and the movement cheats (`.ghost`, `.tp`, ...) are the host's: they say so instead of doing anything |
| Mi8CargoHold | You use the host's hold; the host's save keeps it |
| WorldTweaks | The host's day/night length and season; your own darker nights setting (it only changes your sky) |
| BackpackWeightFix | The host's copy fixes every container, yours too |
| RandomEmissions | The host's game picks the emission times; your siren plays when the host's does |
| StackThemAll, MISERY_StructuralFreedom | Everyone needs them, with the same settings |
| NotSoShaky, ModHub | Only affect your own game |

If the host doesn't have a mod, the joined player's copy says so after 3 seconds (e.g. "No answer from the host")
and changes nothing in the host's world.

In the Mod Menu the host can stop giving items and stats to other players with `allowJoined = false` in the `Coop`
table near the top of `MISERYModMenu\Scripts\main.lua`.

## Settings

The settings are at the top of each mod's `Scripts\main.lua`.

| Mod | Settings |
|---|---|
| WorldTweaks | `dayLength = 22.0`, `nightLength = 4.0`, `season = ""` (`"winter"` etc. to force one), `nightSkyLight = 7.5` (game default 20.0; lower is darker; `nil` turns it off) |
| RadiationShield | Use the in-game menu (`.radmenu`); it saves to `RadiationShield\settings.txt`. The defaults at the top of `main.lua` apply only when there is no settings file. |
| BackpackWeightFix | `checkEverySeconds = 30` (`.fixweight` runs it instantly) |
| RandomEmissions | emission every 1800–3600 s, siren 120–300 s before |
| StackThemAll | per category in `scripts\stackThemAllConfig.lua`, per item in `scripts\stackConfig.lua` (e.g. `Resource_Rubles = 250`) |

## Console commands

Press `~` in game to open the console.

| Command | Effect |
|---|---|
| `.radshield [on\|off]` | Radiation Shield toggle (same as HOME) |
| `.radmenu` | Radiation Shield settings menu (opens and closes it) |
| `.radshield 75` | Sets the shield to 75% less radiation and switches it on (saved) |
| `.radmeter` | Measures a radiation hot spot; run it again to get the suggested reduction |
| `.mods` | Mod Hub: the loaded mods, their keys and commands, opening their menus, restarting them |
| `.reloadmods` | Restarts the mods whose `main.lua` changed since they loaded (`.reloadmods all`, or `.reloadmods <Name>` for one) |
| `.fixweight` | Fix stuck container weight right now |
| `.weightreport` | Use if the weight fix can't find the weight value: empty the backpack, then run it |
| `.worldinfo` | Shows the day/night settings |
| `.weatherdump` | Writes the weather presets to a file |
| `.find <name>` | Searches the mod menu's item list (`.find` alone clears it) |
| `.spawnmode game\|mod` | Chooses who adds items when you press Spawn (not chosen: in co-op the host's menu adds it) |
| `.menudump` | Writes the PageUp menu's widgets to the log (for reporting layout problems) |
| `.help` | Lists all mod menu commands |

## Radiation Shield menu

Type `.radmenu` in the console while in a world. Use Up/Down to choose a row and Left/Right to change it.
Close it with the Close row or `.radmenu` again. HOME (or your chosen key) still just turns the shield on and off.

| Setting | What it does |
|---|---|
| Shield | On / off (same as HOME) |
| Less radiation | 5–100% in 5% steps (`.radshield 73` for exact values) |
| Others can use it | Host only: whether players who joined your world may use their own shields |
| Live readout | A panel with your radiation, what comes in per second, what the shield removes, the actual change and the time until maximum |
| Badge / Badge position | Shows the on-screen badge, and where it sits |
| Shield on at start | Switches the shield on as soon as the game starts |
| Toggle key | HOME, END, INS, DEL, PAGE_DOWN or F6–F9 (applies on the next start) |

Every change is saved immediately to `RadiationShield\settings.txt`.

**Co-op:** every player's shield is their own. Pressing HOME protects only you. The host decides the rest:
whether players who join may use shields (**Others can use it**) and how strong they are (the host's **Less radiation**).

- **YES:** when a joined player presses HOME, their game asks the host's game, the shield turns on for that player only
  at the host's percentage, and their badge shows it. If the host changes **Less radiation** later, shields that are on
  follow straight away.
- **NO:** the joined player's badge shows **DISABLED BY HOST** and the shield stays off. If the host switches it to NO
  later, shields that are already on turn off.
- **The host doesn't have the mod:** after 3 seconds the badge shows **HOST HAS NO SHIELD MOD**.

In someone else's world, `.radmenu` only has **Shield**, **Live readout**, **Badge**, **Badge position** and **Toggle key**, and shows the host's
percentage under the title. `.radshield 75` is refused there (`.radshield on/off` works). Your own saved percentage is
kept for when you host.

Everyone needs this mod. The two games talk through two messages that are built into Unreal Engine, so it works
whichever game works out the radiation. The host's answers also show as a line in the joined player's console.

**Finding the right setting:** turn on **Live readout**, walk into the hot spot and watch **Maximum in**.
Raise **Less radiation** until it's long enough to do what you need there.

## Troubleshooting

Open `...\Win64\ue4ss\UE4SS.log` and look for the mod's lines:

- **[Mi8CargoHold]**
  - "Cargo Hold ready automatically": working (host).
  - "Joined the host's Cargo Hold": working (you joined someone).
  - "no Cargo Hold from the host yet": the host doesn't have the mod.
- **[BackpackWeightFix]** "Couldn't find where containers keep their weight": run `.weightreport`.
- **[RadiationShield]**
  - "Working: radiation hit X reduced to Y": the shield is cutting radiation.
  - "ignored the smaller radiation amount": it switched to its backup method. That's fine.
  - "Indicator unavailable (...)": there's no badge, but the shield still works.
  - "Meter summary": from `.radmeter`. It shows how fast radiation comes in, how long until the maximum,
    and the reduction needed to last 30, 60, 120 or 300 s.
- **[ItemMenu] / [Spawn]**: lines about the mod menu's item list and spawning.

If something is broken, please open an issue and include those lines.

## Changes to the included community mods

**StackThemAll 1.2.0** (was 1.1.0)
- At launch, items added by game updates are appended to `stackConfig.lua` with their category's stack size. Your entries are never touched.
- Values missing from an entry keep the game's value. `onlyStacksChanges` and `aphapeticallySorted` work.
- Sets itself up once instead of retrying constantly. It used to write about 1,400 log lines in 12 minutes at the main menu.

**MISERYModMenu 4.5** (was 4.4)
- The item list shows in-game names sorted A–Z, including items from newer patches.
- Search box next to the amount field, and `.find` in the console.
- Spawn gives one copy instead of two (`.spawnmode`), and no longer crashes the game.
- New look: the stone frame and grey stock buttons become a square, see-through dark navy panel with soft steel-blue
  highlights (like the Radiation Shield menu and the Mod Hub), dark buttons, a blue Spawn and a readable item list. Everything is arranged in sections: Spawn item, Spawn enemy, Time and weather, Events, Movement.
  To keep the game's layout, set `MenuLayout = { enabled = false ...` in `Scripts\main.lua`; for the old colours too, `MenuStyle = { enabled = false ...`.

**Mi8CargoHold** (was the "Mi 8 Cargo Hold 1.0.1" download, folder `ChopperStorage`)
- Renamed, and given an `enabled.txt`.
- Keeps working when a game update renames the save-system hook it needs.
- In co-op, joining players use the host's hold.

**RandomEmissions**
- Sets up its hook and per-frame loop once instead of on every load or respawn.

## Credits

- **UE4SS** and its built-in mods (`shared`, CheatManagerEnablerMod, ConsoleCommandsMod, ConsoleEnablerMod,
  BPML_GenericFunctions, BPModLoaderMod, Keybinds, LineTraceMod, SplitScreenMod): the
  [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) team, MIT licence.
- **StackThemAll, MISERYModMenu, Mi8CargoHold (originally Mi 8 Cargo Hold / ChopperStorage), RandomEmissions,
  MISERY_StructuralFreedom, NotSoShaky**: their original authors. This repo contains modified versions, as described above.
- **WorldTweaks, RadiationShield, BackpackWeightFix, ModHub**: new in this repo.

MISERY is a game by its developers. This project isn't affiliated with them.
