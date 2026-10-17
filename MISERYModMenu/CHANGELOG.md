# MISERY Mod Menu - Changelog

---

## Version 4.6.21

- `.movecheck watch` also logs where you look up/down (the controller's and the camera's pitch) and how strong the movement input is. The slow sprint moved at exactly 0.707 of normal (424 instead of 600, jogging 176 instead of 250): moving along a view tilted 45 degrees keeps exactly that much, so this shows whether the slow moments are a tilted view

---

## Version 4.6.20

- `.movecheck watch`: logs how you move (state, sprint key, speed limit, real speed, stamina, crouched) twice a second for 30 s, so it catches the slow sprint while it happens. Typing `.movecheck` alone stops your character, so it only ever showed standing still

---

## Version 4.6.19

- `.movecheck` shows what decides how fast you move right now: your state, sprint key, stamina, the speed limit and how fast you really move, the game's speed for each state, and the item in your hands with its own speeds. For the bug where sprinting is sometimes very slow: run it while it happens

---

## Version 4.6.18

- In someone else's world, a player who got into fly / ghost couldn't get out: turning it off was refused like turning it on ("the host's game moves your character"). `.noclip` and keybinds didn't check at all, so that's how one got in. Now every way (`.ghost`, `.noclip`, the FLY button, keybinds) goes through one switch that goes by whether the character really flies (the game's own FLY button can start it too): in someone else's world it still won't turn on, but it always turns off. `.walk` works as before

---

## Version 4.6.17

- `.invcheck` found no open container in 4.6.16 (it looked for a visible container window). It now reads what you're using straight from the game (the workbench, a box...) and lists each of its containers' rules

---

## Version 4.6.16

- `.invcheck` also lists the open containers' own rules: items and weight in them, cells, weight limit, item count limit, restriction type and restricted items. For finding out why Shift+click moves nothing into a workbench or box and a drag moves only part of a stack

---

## Version 4.6.15

- `.invcheck` shows what the game thinks about the inventory's keys: whether its split key is held (`IsSplitKeyDown`) and which of Shift / Ctrl / Alt are down right now. For the bug where a dragged stack moves only half and Shift+click quick move does nothing; `.invcheck fix` turns the split key off

---

## Version 4.6.14

- Restarting this mod from the Mod Hub ("Restart changed mods") could crash the game: UE4SS removes a restarted mod's hooks on engine functions, but its hooks on the game's own functions stayed, still pointing into the old copy of the mod, and the next time the game ran one UE4SS crashed. They're now written down (`hooks.txt` in the mod's folder) and removed when the mod loads again in the same game session (shared `GameHooks` module)

---

## Version 4.6.13

- PageUp no longer opens the cheat menu: it opens the Mod Hub now. Open the cheat menu with `.menu`, or from the Mod Menu's page in the Mod Hub ("Open the spawn menu"). Backspace closes it, and its header says so
- Help texts, `.diag` and the README no longer mention PageUp for the cheat menu

---

## Version 4.6.12

- Backspace closes the cheat menu (PageUp still opens and closes it). It has no levels to go back through. Backspace does nothing while you're typing in one of the menu's text boxes, where it deletes as usual

---

## Version 4.6.11

- `.season` back to 4.6.9's defaults (speed 1.0, duration 0): the game's own values (4.6.10) froze the game. Those defaults make the seasons cycle, so don't use `.season` for now

---

## Version 4.6.10

- `.season winter` made the seasons cycle nonstop: its default speed 1.0 and duration 0 made each season last no time at all. Without your own numbers it now uses the game's own transition speed and season duration (60 and 180)

---

## Version 4.6.9

The code of 4.6.2, the last version with real fixes in it:
- Opening the PageUp menu no longer walks through every object in the game (the HUD is kept until the next level)
- No cheats check at the main menu, where there is no player to find
- The cheats check and building the item list run on the game thread (from a timer thread they could crash)

The changes of 4.6.3 to 4.6.7 are not in it. They were attempts at fixing a freeze when restarting mods, and the
freeze turned out to come from the Field Of View mod (now removed), not the Mod Menu.

---

## Version 4.6.8

- The code of 4.6.1, to find what made restarting mods freeze the game (it turned out to be the Field Of View mod)

---

## Version 4.6.7 (undone in 4.6.8)

- The cheats check's timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of 4.6.5, used by several mods at once, froze the game during normal play. The normal keybinds of 4.6.6 stay

---

## Version 4.6.6 (undone in 4.6.8)

- Restarting the Mod Menu froze the game right after UE4SS removed its hooks: the next step removes its keys (PageUp, 6-0, `.bind` keys), and it was the only restarted mod using UE4SS's async keybinds. It now uses the normal keybinds like every other mod; the keys work the same

---

## Version 4.6.5 (undone in 4.6.8)

- The cheats check's timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

---

## Version 4.6.4 (undone in 4.6.8)

- Restarting the Mod Menu could freeze the game for a few seconds: UE4SS can only stop a mod once its timers wake up, and the check that switches cheats on slept 5 s. It now ticks every second (still checking every 5 s)

---

## Version 4.6.3 (undone in 4.6.8)

### Restarting No Longer Hangs the Game
- Restarting the Mod Menu (Mod Hub's Restart, `.reloadmods`) could hang the game, mostly after using the PageUp menu: UE4SS froze while removing the Mod Menu's NotifyOnNewObject watches (for new controllers, inventories and characters). No other mod used those
- The watches are gone: switching the game's cheats on and building the item list now happen when the player spawns (`ClientRestart`, like the other mods), and right away when the Mod Menu is restarted in a world

---

## Version 4.6.2

### Performance
- Opening the PageUp menu walked through every object in the game to find the HUD, a small hitch on every press. The HUD is now found once and kept until the next level
- At the main menu, the check that switches the game's cheats on looked for a player every 5 s by walking every object, though there is none until a world loads. It now waits for the player to appear

### Stability
- That check, and building the item list, ran on a timer thread beside the game; touching game objects from there can crash. Both now run on the game thread

---

## Version 4.6.1

### Performance
- Infinite stamina and instaheal looked for your player by walking through every object in the game on every tick: about 20 times a second with infinite stamina on, which can cost frames. The player is now found once and kept until the next level

---

## Version 4.6

### Updating with git pull
- Your own settings go in `config.lua` (copy `config.example.lua`), not in `main.lua`, so `git pull` can always update the mod
- `config.lua` settings: `allowJoined` (co-op), `newLook = false` for the game's colours, `newLayout = false` for the game's layout

---

## Version 4.5.1

### Co-op
- Hosting: a player who turns instaheal, infinite stamina and god mode all off is forgotten, so the health hook no longer checks them on every hit

---


## Version 4.5

### Co-op
- In someone else's world the host's game owns the world and everyone's inventory, so the menu no longer changes things only in your own game (where they were undone or seen by nobody else)
- Spawn, `.heal`, `.damage`, `.stamina`, `.feed`, `.drink`, `.radcure`, `.sanitycure`, `.instaheal`, `.infstam` and `.god` ask the host's Mod Menu, which does them for you; its answer shows in your console, and after 3 s without one the log says the host needs this mod
- Time (also the time field), weather, season, enemies, `.summon`, `.slomo`, `.freeze`, `.destroyall`, `.destroypawns`, `.restartlevel`, the movement cheats (Fly, `.ghost`, `.noclip`, `.tp`, `.loadpos`, `.size`) and the old item commands (`.spawn`, `.give`, ...) are the host's: they say so instead
- Hosting: the host's log shows what each player asked for. `allowJoined = false` in the `Coop` table turns it off
- `.spawnmode game` still makes the game's own spawn add the item in co-op

### New Look
- The PageUp menu is restyled when it opens: the stone frame becomes a square, see-through dark navy panel with soft steel-blue highlights, the grey stock buttons become dark buttons with light text, Spawn is blue, and the item list has light text with a blue selection (it was black on black)
- Labels, buttons and the amount, search and time fields share one smaller, consistent style
- Rearranged into sections in one panel: Spawn item (list, then amount, search and Spawn on one row), Spawn enemy (list and Spawn), Time and weather (Time, Day, Month side by side, then Sunny, Rain, Thunder), Events (Summon plane, Summon Grad, Skip 1 or 5 emissions), Movement (Fly and its hint)
- These are the game's own widgets, moved rather than copied, so every button works as before; anything the game won't let the mod recolour keeps its old look, and if the menu isn't laid out as expected the game's layout is kept (`[MenuLayout]` in the log says why)
- `.menudump` writes the menu's widgets to the log, for reporting layout problems

### Items Show Their In-Game Names
- The dev menu's item list now shows the names you see in game (`Rubles`, `Vodka`) instead of the internal IDs (`Resource_Rubles`), sorted A-Z
- Items that share a name get their number or category added (`Poster 3`, `Bandage (Resource)`); items without a name get one made from their ID
- The UE4SS log says how many names came from the game: `[ItemMenu] Item names: ...`
- The list includes every item in the game's item table, read when the game starts, so items added by game updates appear even if the game's own cheat-menu list wasn't updated

### Search
- A search box shares the amount field's row (under SPAWN): type part of a name and the item list shows only matches, with the best match already selected. Several words narrow it down (`poster 2`); internal IDs also match (`resource_`)
- Console fallback: `.find <name>` does the same (and lists the matches); `.find` on its own clears the search

### Spawn Button No Longer Doubles Items
- The game's own Spawn code now works, and the mod was adding a second copy on top of it. Now only the game spawns: the Spawn button hands it the real item ID (the list shows in-game names) and the mod adds nothing
- A click that reaches the mod twice is handled once
- New `.spawnmode game|mod` to pick who spawns if a game update changes this again: `game` (default) or `mod` (the mod's own spawn; the game's code is handed no selection)
- Each spawn is logged: `[Spawn] Rubles x5 (game spawn)`
- No game functions are called with guessed parameters: an early 4.5 build counted the inventory with one and crashed the game on Spawn

---

## Version 4.4

### Spawn AI Fixes
- **Zombie spawns now.** The menu's Zombie entry pointed at a class that doesn't exist in shipped game builds (a dev typo - the real asset is named `BP_ZombieSoilder`), so clicking Spawn AI silently did nothing. The mod now force-loads the real class and spawns it
- **Izdushka spawns on the ground now.** It used to appear half buried and stuck. The creature is a special actor with no physics settling, so the game dropped it at the wrong height and left it there - the mod now places it so its legs sit on the ground
- Note: the Izdushka does not walk around after spawning - its movement is driven by the game's own level logic that a manual spawn can't trigger. Consider it scenery for now
- `.enemy zombie` / `.enemy izd` get the same fixes; `.enemy` also no longer reports "spawned" when nothing actually spawned

### New Diagnostic Commands
| Command | Description |
|---------|-------------|
| `.findclass <text>` | List loaded objects whose name contains the text |
| `.loadclass <path>` | Probe / force-load a blueprint class by asset path |
| `.izdiag [fix]` | Inspect spawned Izdushka actors (components, controller) |
| `.izsnap <offset>` | Place all Izdushkas at your ground level + offset |
| `.izlift <dz>` | Nudge all Izdushkas up/down by dz units |

---

## Version 4.3

### Menu Fixes
- Every menu button used to ALSO spawn the currently selected item (Spawn AI, Fly, Summon Plane, Summon Grad, weather buttons - all of them). Each button now does only its own job
- The SPAWN button still spawns items through the game's own factory - items arrive non-glitched, no save/reload needed
- Spawn AI no longer resets the time to 0:00 when clicked
- The FLY button now works - it toggles the new noclip mode

### Time Controls Fixed
- The Time field in the menu works: type an hour (1-24) and press Enter; raw values (0000-2400) work too. Previously any input reset time to midnight
- `.time <hour>` fixed with the correct time formula (was broken since the first release)
- Time changes need the menu to have been opened once after game start

### God Mode Works Now
- `.god` hooks the game's own health system: while enabled you cannot take health damage or die. Previously it did nothing (the game ignores the engine cheat)
- Hunger/thirst/radiation still tick - combine with `.instaheal` for full immunity

### Real Noclip
- `.ghost` / `.noclip` (or the FLY button): fly through walls in the direction you look - look up + hold W to climb. Toggle again or `.walk` to land

### Debug Camera Fixed
- `.debugcam` properly returns you to your character on the second toggle. Previously you could get permanently stuck in the free camera

### Multiplayer Safety
- All cheats (god mode, ghost, stat hotkeys, item spawns) strictly target YOUR character only. Previously some cheats could grab another player's character on a hosted server
- Time/weather changes still affect the whole world (game architecture)

### Misc
- Fixed log spam when pressing R in-game
- Cheats now work reliably on a fresh game start (some previously only worked after a mod reload)
- Item dump diagnostic commands write to a relative path (worked only on the dev machine before)

---

## Version 4.2

### Changes

**Stat Hotkeys Moved to the Number Row**
- Quick stat keys are now `6` `7` `8` `9` `0` `-` `=` (were `F1`-`F7`)
- The F-keys clashed with existing game/engine bindings on some setups; the number row is free
- Mapping: `6` Health +100, `7` Stamina +100, `8` Hunger +50, `9` Thirst +50, `0` Radiation -50, `-` Insanity -50, `=` Health -25

**More Reliable Cheat Targeting**
- Stat cheats now resolve your own LOCAL character first (local controller -> character inventory), with fallbacks to the master/MISERY character and the original lookup
- Fixes cases where a cheat could affect the wrong actor in a scene

### New Bindable Keys
- `minus` and `equals` can now be used with `.bind`

---

## Version 4.1

### Compatibility Update

This update focuses on fixing compatibility issues reported by users with different PC setups, screen resolutions, and keyboard configurations.

---

### New Features

**Backup Menu Command**
- Added `.menu` console command as an alternative to PageUp
- If your PageUp key doesn't work, just type `.menu` in console to toggle the dev menu

**Diagnostics Command**
- Added `.diag` command for troubleshooting
- Shows API status, key bindings, screen resolution, and any errors
- Helps identify exactly what's working and what isn't on your system

**Command Suggestions**
- If you mistype a command, the mod now suggests similar commands
- Example: typing `.heall` will suggest `.heal`

---

### Bug Fixes

**Screen Resolution / Aspect Ratio Issues**
- Dev menu now auto-scales based on your screen resolution
- Reference resolution is 1920x1080 - menu scales up or down accordingly
- Tries multiple scaling methods for maximum compatibility

**PageUp Key Not Working**
- Added support for multiple key naming conventions (PAGE_UP, PAGEUP, PRIOR)
- Keys are now validated before binding - no more silent failures
- Use `.menu` command as a backup if PageUp still doesn't work

**Hotkeys (F1-F7) Not Working**
- All hotkeys now use safe registration with error reporting
- If a key fails to bind, you'll see a warning at startup
- Startup message shows how many hotkeys were successfully bound (e.g., "7/7")

**"Command Not Recognized" Errors**
- Improved command parsing
- Added suggestions for common typos
- Better error messages tell you what went wrong

**Keybind File Issues**
- Fixed file path format for better cross-system compatibility
- Now tries multiple path formats when loading saved bindings
- Bindings file supports comments (lines starting with #)

---

### Improvements

**Better Startup Messages**
- Shows keybind status at startup
- Warns you immediately if PageUp or other keys failed to bind
- Displays first 3 initialization errors with option to see more via `.diag`

**Error Tracking**
- All initialization errors are now collected and can be viewed with `.diag`
- Easier to troubleshoot issues on different systems

**Updated Help**
- `.help` command now includes troubleshooting section
- Points users to `.diag` and `.menu` commands

---

### Technical Changes

- Added API validation layer - checks if UE4SS functions exist before using them
- Safe wrappers for keybind and command registration
- Multiple fallback methods for key enum values
- Screen size detection with multiple methods (GameViewportClient, PlayerController)
- Widget scaling tries 5 different UE4 methods for compatibility

---

### New Commands

| Command | Description |
|---------|-------------|
| `.menu` | Toggle dev menu (backup for PageUp) |
| `.diag` | Show full diagnostics report |

---

### For Users Experiencing Issues

1. **PageUp doesn't work?** Use `.menu` instead
2. **Hotkeys don't work?** Use console commands (`.heal`, `.stamina`, etc.)
3. **Menu doesn't fit screen?** Should be auto-fixed, report if still broken
4. **Something else broken?** Run `.diag` and include output in bug report

---

## Version 4.0

### Initial Release

**God Mode**
- `.instaheal` / `.ih` - Auto-heal all stats every 0.5 seconds
- `.infstam` - Infinite stamina
- `.god`, `.ghost`, `.walk` - Movement modes

**World Control**
- `.time <hour>` - Set time of day (0-24)
- `.weather <type>` - Change weather (sunny/rain/thunder)
- `.season <type>` - Change season (spring/summer/autumn/winter)
- `.slomo [speed]` - Slow motion
- `.freeze` - Freeze time

**Teleportation**
- `.tp` - Teleport to crosshair
- `.savepos` / `.loadpos` - Save and load positions
- `.debugcam` - Free camera mode

**Spawning**
- `.enemy <type> [count]` - Spawn enemies with fuzzy matching
- `.spawn <item> [amount]` - Spawn items with fuzzy matching
- `.summon <class>` - Spawn by exact class name
- PageUp - Built-in dev cheat menu for item spawning

**Stats**
- `.heal`, `.stamina`, `.feed`, `.drink`, `.radcure`, `.sanitycure`
- All support custom amounts

**Custom Keybinds**
- `.bind <key> <command> [arg]` - Create custom hotkeys
- `.unbind <key>` - Remove hotkeys
- `.binds` - List all bindings
- Bindings persist between sessions

**Hotkeys**
- PageUp - Toggle dev menu
- F1-F7 - Quick stat adjustments

**Debug Tools**
- `.search`, `.classes`, `.bp`, `.inspect`
- `.items`, `.invfuncs`, `.cheatfuncs`
- And more for exploring game internals

---

## Installation

1. Install UE4SS for MISERY
2. Copy `MISERYModMenu` folder to `MISERY\Binaries\Win64\ue4ss\Mods\`
3. Enable in `mods.txt`: `MISERYModMenu : 1`
4. Launch game and press `~` for console, `PageUp` for dev menu

---

## Reporting Issues

When reporting bugs, please include:
1. Your screen resolution
2. Output from `.diag` command
3. Any errors shown at startup
4. What you expected vs what happened
