# MISERY Mod Menu v4.5

A cheat/mod menu for MISERY using UE4SS. Includes god mode, stat manipulation, world control, teleportation, enemy spawning, and more.

## Installation

1. Make sure you have **UE4SS** installed in your MISERY game folder
2. Copy the `MISERYModMenu` folder to:
   ```
   MISERY\Binaries\Win64\ue4ss\Mods\
   ```
3. Enable the mod in `mods.txt` (add `MISERYModMenu : 1`)
4. Launch the game

## Quick Start

| Action | How |
|--------|-----|
| Open Dev Menu | Type `.menu` in console, or PageUp (Mod Hub) → Mod Menu → Open the spawn menu. Backspace closes it |
| Find an item | Type in the search box next to the amount field, or `.find <name>` in console |
| God Mode | Type `.instaheal` in console |
| Infinite Stamina | Type `.infstam` in console |
| Get Help | Type `.help` in console |

**To open the console:** Press `~` (tilde) key

## Hotkeys

| Key | Effect |
|-----|--------|
| `6` | Health +100 |
| `7` | Stamina +100 |
| `8` | Hunger +50 |
| `9` | Thirst +50 |
| `0` | Radiation -50 |
| `-` (minus) | Insanity -50 |
| `=` (equals) | Health -25 |

> Stat hotkeys use the **number row** (`6` `7` `8` `9` `0` `-` `=`). Earlier
> versions used `F1`-`F7`, which clashed with game/engine bindings on some setups.

## Console Commands

All commands start with `.` (period). Open the console with `~` and type the command.

### God Mode
| Command | Description |
|---------|-------------|
| `.instaheal` or `.ih` | Toggle auto-heal all stats every 0.5s |
| `.infstam` | Toggle infinite stamina |
| `.god` | Toggle god mode - no health damage, cannot die |
| `.ghost` / `.noclip` | Toggle noclip - fly through walls in the direction you look (W + look up = climb) |
| `.walk` | Return to normal walking |

### Stats
| Command | Description |
|---------|-------------|
| `.heal [amount]` | Restore health (default: 100) |
| `.stamina [amount]` | Restore stamina (default: 100) |
| `.feed [amount]` | Restore hunger (default: 50) |
| `.drink [amount]` | Restore thirst (default: 50) |
| `.radcure [amount]` | Reduce radiation (default: 50) |
| `.sanitycure [amount]` | Reduce insanity (default: 50) |
| `.damage [amount]` | Take damage (default: 25) |

### World Control
| Command | Description |
|---------|-------------|
| `.time <hour>` | Set time (0-24). Example: `.time 12` for noon. The menu's Time field also works: enter 1-24 and press Enter |
| `.weather <type>` | Change weather: `sunny`, `rain`, `thunder` |
| `.season <type>` | Change season: `spring`, `summer`, `autumn`, `winter` |
| `.slomo [speed]` | Slow motion (default: 0.5x) |
| `.freeze` | Freeze time |

### Teleportation
| Command | Description |
|---------|-------------|
| `.tp` | Teleport to crosshair |
| `.savepos` | Save current position |
| `.loadpos` | Teleport to saved position |
| `.debugcam` | Toggle free camera (run again to return to your character) |
| `.exitcam` | Exit debug camera (backup) |
| `.restartlevel` | Emergency restart (if stuck) |

### Spawning
| Command | Description |
|---------|-------------|
| `.enemy <type> [count]` | Spawn enemies. Example: `.enemy zombie 3` |
| `.summon <class>` | Spawn by exact class name |
| `.spawn <item> [amount]` | Spawn items (fuzzy search) |
| `.find <name>` | Filter the dev menu's item list (in-game names or IDs); `.find` alone clears it |
| `.spawnmode [game\|mod]` | Who adds items when you press the menu's Spawn button (default `game`) |

The dev menu's item list shows in-game item names. The search box next to the
amount field filters the list as you type and selects the best match.

The Spawn button lets only the game's own spawn code add the item (it is
handed the real item ID). If a game update ever stops that from working,
`.spawnmode mod` makes the mod spawn instead.

**Enemy Types:** `zombie`, `ghoul`, `bandit`, `screamer`, `swamper`, `plague`, `ratwolf`, `deer`, `dward`, `twins`, `izdushka`

### Custom Keybinds
| Command | Description |
|---------|-------------|
| `.bind <key> <command> [arg]` | Bind a key to a command |
| `.unbind <key>` | Remove a keybind |
| `.binds` | List all custom bindings |

**Example:**
```
.bind num1 instaheal
.bind num2 heal 500
.bind num3 time 12
```

**Available Keys:** `a-z`, `0-9`, `num0-num9`, `f1-f12`, `minus`, `equals`, `ins`, `del`, `home`, `end`, `pageup`, `pagedown`, `up`, `down`, `left`, `right`, `space`, `enter`, `tab`, `escape`

**Bindable Commands:** `heal`, `damage`, `stamina`, `feed`, `drink`, `radcure`, `sanitycure`, `maxstats`, `instaheal`, `infstam`, `god`, `ghost`, `walk`, `tp`, `slomo`, `freeze`, `debugcam`, `savepos`, `loadpos`, `time`, `destroypawns`

### Utility
| Command | Description |
|---------|-------------|
| `.help` | Show help |
| `.cheats` | Show all cheat commands |
| `.menu` | Open / close the dev menu |
| `.diag` | Show diagnostics (for troubleshooting) |

## Troubleshooting

### Where did PageUp go?
- PageUp now opens the Mod Hub. Open the dev menu with `.menu`, or from the Mod Menu's page in the Mod Hub

### Stat hotkeys (`6` `7` `8` `9` `0` `-` `=`) don't work
- Some keyboards/systems have different key codes
- Check `.diag` output to see which keys were bound
- Use console commands instead (`.heal`, `.stamina`, etc.)

### "Command not recognized"
- Make sure you're typing the command correctly with the `.` prefix
- Check spelling - the mod will suggest similar commands if you make a typo
- Type `.help` to see available commands

### Dev menu doesn't fit on screen
- The mod auto-scales for different resolutions
- If still not fitting, try a different resolution or use console commands

### Cheats aren't working
1. Make sure you're in-game (not in menu)
2. Type `.enablecheats` first
3. Run `.diag` to check API status

### Nothing works at all
1. Verify UE4SS is installed correctly
2. Check that the mod is enabled in `mods.txt`
3. Look for errors in the UE4SS console/log
4. Run `.diag` for a full diagnostic report

## Diagnostics

Type `.diag` in console to see:
- API Status (which UE4SS functions are available)
- Key Status (how many keys were successfully mapped)
- Screen Resolution and UI Scale
- Custom Bindings count
- Any initialization errors

Example output:
```
=== MISERY Mod Menu Diagnostics ===

API STATUS:
  RegisterKeyBindAsync: OK
  ExecuteInGameThread: OK
  ForEachUObject: OK
  ...

KEY STATUS:
  Key enum available: YES
  Keys mapped: 52
  Hotkeys bound: 7/7
  PageUp available: YES

SCREEN:
  Resolution: 1920x1080
  UI Scale: 1.00

INIT ERRORS: None
```

## Debug Commands

For advanced users and troubleshooting:

| Command | Description |
|---------|-------------|
| `.search <term>` | Search for game objects |
| `.classes <term>` | Search for classes |
| `.bp [term]` | List Blueprint classes |
| `.inspect <class>` | Inspect a class's properties/functions |
| `.items [filter]` | List spawnable items |
| `.invfuncs` | List inventory functions |
| `.cheatfuncs` | List cheat menu functions |
| `.exec <command>` | Execute raw console command |

## Custom Bindings File

Your custom keybinds are saved to:
```
Mods/MISERYModMenu/bindings.txt
```

Format:
```
keyname=command
keyname=command=argument
```

Example:
```
num1=instaheal
num2=heal=500
num3=time=12
```

## Version History

### v4.5
- Dev menu item list shows in-game item names, sorted A-Z
- Search box next to the amount field (`.find <name>` in console as a fallback)
- Spawn button no longer gives two of everything; `.spawnmode` to choose who spawns

### v4.4
- Spawn AI: Zombie works now (the menu pointed at a class that doesn't exist in shipped builds; the real one is force-loaded and spawned)
- Spawn AI: Izdushka no longer spawns half buried - it's placed with its legs on the ground (it doesn't walk after spawning; its movement is level-driven)
- `.enemy zombie` / `.enemy izd` fixed the same way; no more false "spawned" reports
- New diagnostics: `.findclass`, `.loadclass`, `.izdiag`, `.izsnap`, `.izlift`

### v4.3
- All menu buttons fixed: each does only its own job (previously every button also spawned the selected item)
- Time controls work: menu Time field accepts hours 1-24, `.time` formula fixed
- `.god` is real god mode now (no health damage, cannot die)
- `.ghost` / `.noclip` is real noclip with look-direction flight; FLY button toggles it
- `.debugcam` exits properly on second toggle
- Multiplayer: all cheats strictly target the local player only
- Fixed R-key log spam and cold-start reliability

### v4.2
- Stat hotkeys moved from `F1`-`F7` to the number row (`6` `7` `8` `9` `0` `-` `=`) to avoid conflicts with game/engine key bindings
- Added `minus` and `equals` as bindable keys for `.bind`
- Stat cheats now reliably target your own (local) character, not another actor in the scene

### v4.1
- Added screen resolution scaling for dev menu
- Added safe key binding with multiple naming convention fallbacks
- Added `.menu` command as backup for PageUp
- Added `.diag` diagnostic command
- Added command suggestions for typos
- Improved error reporting and initialization feedback
- Fixed file path compatibility issues
- Better support for different keyboard layouts

### v4.0
- Initial release with full feature set

## Credits

Built for MISERY using UE4SS modding framework.

## Support

If you encounter issues:
1. Run `.diag` and note any errors
2. Check the UE4SS log for errors
3. Try the troubleshooting steps above
