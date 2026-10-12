# MISERY mods (a complete UE4SS `Mods` folder)

A ready-to-use [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) `Mods` folder for **MISERY**: bug fixes,
quality-of-life mods and updated versions of community mods, all switched on and all working in co-op.

This repository **is** the `Mods` folder. You clone it into place once, and `git pull` updates every mod.

Tested against MISERY Steam build 25711265 (UE 5.4) with UE4SS v3.0.1.

## Install

You need UE4SS installed in MISERY (the game has `MISERY\Binaries\Win64\ue4ss`) and
[Git for Windows](https://git-scm.com/download/win) (or `winget install Git.Git`).

1. Close MISERY.
2. Open PowerShell in the game's `ue4ss` folder:
   ```powershell
   cd "C:\Program Files (x86)\Steam\steamapps\common\MISERY\MISERY\Binaries\Win64\ue4ss"
   ```
   (use your own Steam library path).
3. Move the old `Mods` folder out of the way, then clone this repository (it makes the `Mods` folder):
   ```powershell
   Rename-Item Mods Mods.old; git clone https://github.com/konnatoad/Mods.git
   ```
4. Start the game. Every mod writes a "Loaded" line to `ue4ss\UE4SS.log`.

If you had other mods in `Mods.old`, copy their folders into `Mods`; git leaves folders it doesn't know about alone.
You don't need `Mods.old` after that. The repository already has UE4SS's own mods and `shared`.

## Update

```powershell
cd "<your ue4ss folder>\Mods"; git pull
```

Then restart the game. To update without restarting, type `.reloadmods` in the console: it restarts every mod whose
script changed (a mod that is new since you started the game still needs a restart).

`git pull` always works because none of your own files are in git:

- settings you saved in game (`settings.txt`, the Mod Menu's `bindings.txt`)
- your own `config.lua` files (see [Settings](#settings))
- StackThemAll's `scripts\stackConfig.lua`
- the log and the dump files the mods write

Don't edit the mods' `main.lua` files: your change would block the next `git pull` for that mod.
If `git pull` says your local changes would be overwritten, see [Troubleshooting](#troubleshooting).

## What's inside

Each mod is switched on by the `enabled.txt` in its folder (delete it to switch a mod off).
Every mod has a `CHANGELOG.md`; in game, `.mods` → pick a mod → **Changelog** shows it.

| Mod | What it does | In co-op |
|---|---|---|
| **ModHub** *(new)* | `.mods` opens a menu of the loaded mods: their hotkeys, console commands, settings and changelogs, a button for mods with their own menu, and restarting mods you've changed | Only your game |
| **MISERYModMenu** | The PageUp menu, restyled (dark navy, in sections), with in-game item names, a search box, single spawn and many console cheats | The host's menu gives joined players their items and stats; time, weather and enemies are the host's |
| **RadiationShield** *(new)* | HOME switches on less radiation (for bunker hot spots), with an on-screen badge; `.radmenu` for settings and a live radiation readout | Each player's own shield, if the host allows it, at the host's strength |
| **Mi8CargoHold** | The Mi-8 wreck becomes a 1,000-slot storage container | Everyone uses the host's hold; the host's save keeps it |
| **WorldTweaks** *(new)* | Day/night length (22 / 4), season and darker nights. Replaces DayLengthTweaks and the Darker Nights pak | The host's day length and season; your own darker nights |
| **StackThemAll** | Bigger stacks (money to 250); items from game updates get a stack size automatically | Everyone needs the same stack settings |
| **BackpackWeightFix** *(new)* | Empty containers stuck with weight (like 73/75 kg) go back to 0 every 30 s | The host's copy fixes everyone's |
| **RandomEmissions** | Emissions at random times, with a siren before each one | The host picks the times; everyone hears the siren |
| **HeadBob** *(new)* | `.headbob 50`: how much the view bobs while walking and running | Only your view |
| **ReticleSize** *(new)* | `.reticle 50` (or `.dot 50`): the crosshair dot's size | Only your screen |
| **FieldOfView** *(new)* | `.fov 95`: the field of view in degrees (60-120); aiming still zooms in | Only your view |
| **SurvivalStats** *(new)* | `.stats`: a small panel with your exact health, stamina, hunger, thirst, radiation, insanity... Off until you switch it on | Only reads your own numbers |
| **WhistleRange** *(new)* | Joined players get whistles (and see the other players) from as far away as the host does | Only the host needs it |
| **NotSoShaky** | Softer camera shake when you're hit | Only your view |
| **MISERY_StructuralFreedom** | Relaxed building support rules; normal placement rules still apply | Everyone needs it |

UE4SS's own mods are switched on or off in `mods.txt`; leave them as they are:

- On: CheatManagerEnablerMod, ConsoleCommandsMod, ConsoleEnablerMod, BPML_GenericFunctions, BPModLoaderMod, Keybinds.
- Off: LineTraceMod, SplitScreenMod.
- `shared` is a library the other mods need. It isn't a mod; never delete it.

### Replaces

- **Darker Nights** pak (`777_DarkerNights_P` in `MISERY\Content\Paks\~mods`): WorldTweaks does the same.
  Delete the pak's three files; if you keep both, the pak's older copy of the weather table wins.
- **DayLengthTweaks**: part of WorldTweaks.

## Co-op

Every player should have this folder, at the same version (everyone runs `git pull`). The host's game decides what
happens in the host's world; joined players' mods ask the host's mods, through two messages that are built into
Unreal Engine, and the host's answers show as lines in the joined player's console.

If the host doesn't have a mod, the joined player's copy says so after 3 seconds ("No answer from the host") and
changes nothing in the host's world.

| Mod | In someone else's world |
|---|---|
| RadiationShield | Your own shield, if the host allows it, at the host's strength (see [Radiation Shield menu](#radiation-shield-menu)) |
| MISERYModMenu | Spawn, `.heal`, `.feed` and the other stats, `.instaheal`, `.infstam` and `.god` are done for you by the host's menu. Time, weather, season, enemies, events, slow motion and the movement cheats (`.ghost`, `.tp`, ...) are the host's: they say so instead of doing anything |
| Mi8CargoHold | You use the host's hold |
| WorldTweaks | The host's day/night length and season; your own darker nights (it only changes your sky) |
| BackpackWeightFix | The host's copy fixes every container, yours too |
| RandomEmissions | The host's game picks the emission times; your siren plays when the host's does |
| StackThemAll, MISERY_StructuralFreedom | Everyone needs them, with the same settings |
| WhistleRange | The host's copy widens how far players' characters (and their whistles) are sent; yours does nothing in someone else's world |
| ModHub, HeadBob, ReticleSize, FieldOfView, SurvivalStats, NotSoShaky | Only change your own game |

## Settings

Most settings are changed in game and saved by the mod:

| Mod | How |
|---|---|
| RadiationShield | `.radmenu` (saved to `RadiationShield\settings.txt`) |
| HeadBob | `.headbob ...` (saved to `HeadBob\settings.txt`) |
| ReticleSize | `.reticle ...` (saved to `ReticleSize\settings.txt`) |
| FieldOfView | `.fov ...` (saved to `FieldOfView\settings.txt`) |
| SurvivalStats | `.stats`, `.stats move` (saved to `SurvivalStats\settings.txt`) |
| MISERYModMenu key bindings | `.bind <key> <command>` (saved to `MISERYModMenu\bindings.txt`) |

The rest go in a `config.lua` in the mod's folder. The easy way: `.mods` → pick the mod → **Settings**. Left/Right
change a value, Enter switches it or puts the default back, and it's saved to `config.lua` straight away; restart the
mod (the row below the settings) to use the new values.

By hand: copy the mod's `config.example.lua` to `config.lua` and change it; a line you leave out keeps its default.
`config.lua` is yours, and `git pull` never touches it.

| Mod | `config.lua` settings |
|---|---|
| WorldTweaks | `dayLength = 22.0`, `nightLength = 4.0`, `season = ""` (`"winter"` etc. to force one), `nightSkyLight = 7.5` (game default 20.0, lower is darker, `false` keeps the game's) |
| BackpackWeightFix | `checkEverySeconds = 30` (`.fixweight` runs it right now) |
| RandomEmissions | `randomMin = 1800`, `randomMax = 3600` (seconds), `isSirenEnabled = true`, `sirenMin = 120`, `sirenMax = 300`, `sirenVolume = 3.0` |
| MISERYModMenu | `allowJoined = true` (hosting: give items and stats to players who ask), `newLook = true` (false: the game's colours), `newLayout = true` (false: the game's layout) |
| WhistleRange | `rangeMeters = 0` (how far players' characters reach joined players; 0 = no limit, Unreal's own is 150) |
| StackThemAll | stack size per category, e.g. `Food_StackSize = 100`, and `onlyStacksChanges = false` (the defaults are in `scripts\stackThemAllConfig.lua`) |

StackThemAll's per-item values (e.g. `Resource_Rubles = 250`) are in `StackThemAll\scripts\stackConfig.lua`.
The first launch makes it from `stackConfig.default.lua`, and later launches add items from game updates to it.
It's yours to edit too.

## Console commands

Press `~` in game to open the console. `.mods` shows every mod's commands too.

| Command | Effect |
|---|---|
| `.mods` | Mod Hub: the loaded mods, their keys, commands and changelogs; opens their menus |
| `.reloadmods` | Restarts the mods whose `main.lua` changed since they loaded (`.reloadmods all`, or `.reloadmods <Name>`) |
| `.radshield [on\|off]` | Radiation Shield on / off (same as HOME) |
| `.radshield 75` | 75% less radiation, and switches it on (saved) |
| `.radmenu` | Radiation Shield settings menu (opens and closes it) |
| `.radmeter` | Measures a radiation hot spot; run it again for the suggested reduction |
| `.headbob 50` | Head bob at 50% while walking and running (`.headbob walk 40`, `.headbob run 0`, `off`, `reset`; `.headbob` shows it) |
| `.headbob scan` | If the bob doesn't change: lists the camera shakes the game starts while you move |
| `.reticle 50` / `.dot 50` | Crosshair dot at 50% of its size, 10-400 (`.reticle reset`; `.reticle` shows it) |
| `.reticle scan` | If the dot doesn't change: lists the widgets it could be |
| `.fov 95` | Field of view 95, 60-120 (`.fov reset`; `.fov` shows it; `.fov scan` if the view doesn't change) |
| `.stats` | Survival numbers panel on / off (`.stats move` puts it elsewhere; `.stats scan` if a stat is missing) |
| `.whistle` | Hosting: the range players' characters are sent to joined players (`.whistle scan` lists whistle things) |
| `.fixweight` | Fix stuck container weight right now |
| `.weightreport` | If the weight fix can't find the weight value: empty the backpack, then run it |
| `.worldinfo` | Shows the day/night settings |
| `.weatherdump` | Writes the weather presets to a file |
| `.find <name>` | Searches the PageUp menu's item list (`.find` alone clears it) |
| `.spawnmode game\|mod` | Who adds items when you press Spawn (not chosen: in co-op the host's menu adds them) |
| `.menudump` | Writes the PageUp menu's widgets to the log (for reporting layout problems) |
| `.help` | Every Mod Menu command |

## Radiation Shield menu

Type `.radmenu` in the console while in a world. Up/Down choose a row, Left/Right change it.
Close it with the Close row or `.radmenu` again. HOME (or your chosen key) still just turns the shield on and off.

| Setting | What it does |
|---|---|
| Shield | On / off (same as HOME) |
| Less radiation | 5–100% in 5% steps (`.radshield 73` for exact values) |
| Others can use it | Host only: whether players who joined your world may use their own shields |
| Live readout | Your radiation, what comes in per second, what the shield removes, the actual change and the time until maximum |
| Badge / Badge position | Shows the on-screen badge, and where it sits |
| Shield on at start | Switches the shield on as soon as the game starts |
| Toggle key | HOME, END, INS, DEL, PAGE_DOWN or F6–F9 (applies on the next start) |

**Co-op:** every player's shield is their own; HOME protects only you. The host decides whether players who join may
use shields (**Others can use it**) and how strong they are (the host's **Less radiation**).

- **YES:** a joined player's HOME asks the host's game; the shield turns on for that player at the host's percentage.
  If the host changes **Less radiation**, shields that are on follow straight away.
- **NO:** the joined player's badge shows **DISABLED BY HOST**. Switching it to NO later turns shields that are on off.
- **The host doesn't have the mod:** after 3 seconds the badge shows **HOST HAS NO SHIELD MOD**.

In someone else's world `.radmenu` only has **Shield**, **Live readout**, **Badge**, **Badge position** and
**Toggle key**, and shows the host's percentage under the title. Your own saved percentage is kept for when you host.

**Finding the right setting:** turn on **Live readout**, walk into the hot spot and watch **Maximum in**.
Raise **Less radiation** until it's long enough for what you need to do there.

## Troubleshooting

**`git pull` says your local changes would be overwritten:** a file that comes with the mods was changed in your
folder (most likely a `main.lua`, or `scripts\stackConfig.lua` from before it moved out of git). Put your changes in
the mod's `config.lua` instead, then:

```powershell
git stash; git pull
```

`git stash` keeps your changed files aside; `git stash pop` brings them back if you need something from them.

**A mod isn't working:** open `ue4ss\UE4SS.log` and look for the mod's lines:

- **[ModHub]** "Loaded": `.mods` works. "needs the in-game HUD": load into a world first.
- **[Mi8CargoHold]** "Cargo Hold ready automatically": working (host). "Joined the host's Cargo Hold": working
  (you joined someone). "no Cargo Hold from the host yet": the host doesn't have the mod.
- **[BackpackWeightFix]** "Couldn't find where containers keep their weight": run `.weightreport`.
- **[RadiationShield]** "Working: radiation hit X reduced to Y": the shield is cutting radiation. "ignored the
  smaller radiation amount": it switched to its backup method, that's fine. "Indicator unavailable": no badge, the
  shield still works.
- **[HeadBob]** / **[ReticleSize]** / **[FieldOfView]** / **[SurvivalStats]**: if nothing changes, run
  `.headbob scan` (walk, then run), `.reticle scan`, `.fov scan` or `.stats scan` and send the lines.
- **[WhistleRange]**: hosting, "sent to players up to no limit away" lines appear as players join. If joined players
  still don't hear far whistles, whistle once, then run `.whistle scan` and send the lines.
- **[WorldTweaks] / [ModMenu] ... config.lua ignored**: your `config.lua` has a mistake; the log says what.

If something is broken, please open an issue and include those lines.

## For contributors

Work happens on the `dev` branch and reaches `master` (what everyone clones) through pull requests. Every change to a
mod adds an entry to its `CHANGELOG.md` with a new version.

## Credits

- **UE4SS** and its built-in mods (`shared`, CheatManagerEnablerMod, ConsoleCommandsMod, ConsoleEnablerMod,
  BPML_GenericFunctions, BPModLoaderMod, Keybinds, LineTraceMod, SplitScreenMod): the
  [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) team, MIT licence.
- **StackThemAll, MISERYModMenu, Mi8CargoHold (originally Mi 8 Cargo Hold / ChopperStorage), RandomEmissions,
  MISERY_StructuralFreedom, NotSoShaky**: their original authors. This repository has modified versions; each
  mod's `CHANGELOG.md` says what changed.
- **ModHub, RadiationShield, WorldTweaks, BackpackWeightFix, HeadBob, ReticleSize, FieldOfView, SurvivalStats,
  WhistleRange**: made for this repository.

MISERY is a game by its developers. This project isn't affiliated with them.
