# Mi-8 Cargo Hold (Mi8CargoHold)

Repackaged from the download "Mi 8 Cargo Hold 1.0.1" (UE4SS mod `ChopperStorage`,
made for MISERY build 25144234). Updated for build 25711265 (the 5 October 2026 patch).

Turns the decorative Mi-8 helicopter wreck into a large storage container: walk up
to the wreck, the prompt reads "Mi-8 Cargo Hold", press E on "Enter". It has
1,000 slots in six columns with a scroll bar, no weight limit, and can't be picked
up or destroyed. It does not touch your build menu.

## Install

1. Close MISERY.
2. Copy the `Mi8CargoHold` folder into
   `MISERY\Binaries\Win64\ue4ss\Mods\` (the `enabled.txt` inside switches it on).
3. Start MISERY, load your world and wait about five seconds.

## Using it

- Single-player, or co-op where you are the host: the hold is created and saved
  by your game.
- Joining someone else's world: if the host also has this mod, you use the
  host's hold (same prompt and window); the host's game keeps the items. If the
  host doesn't have it, the log says so and nothing changes.
- The hold appears by itself after the world finishes loading. If you are far
  from the wreck it waits until the wreck streams in.
- Save the game normally to save the cargo. Cargo belongs to that save slot,
  not shared between saves. Unsaved changes are lost on reload, like the rest
  of your inventory.

## Where the cargo is saved

Next to the game's own saves (`%LOCALAPPDATA%\MISERY\Saved\SaveGames`) as
`ChopperCargo_v1_<slot>_<level>.sav`, plus `_pending` and `_backup` copies.
Back them up together with your game saves; restoring a game save without its
matching cargo files is not handled. Don't delete the `_pending`/`_backup`
files to get past a lock - the log explains what is wrong.

## If it doesn't appear

Look for `[Mi8CargoHold]` lines in `ue4ss\UE4SS.log`:

| Log line | Meaning |
|---|---|
| `Cargo Hold ready automatically` | Working - go to the wreck |
| `You are in someone else's world` | Only works in a world you host |
| `Mi-8 wreck not found` | Not near the wreck yet; it retries |
| `native save hooks are unavailable (...)` | A game update changed the save system; send the line |
| `BP_SaveSystem_C still not found` | A game update renamed the save system; send the line |
| `no save slot for this world` | The game hasn't given this world a save slot yet |

The mod stays off rather than risking your items whenever something it relies
on is missing ("fails closed").

## Changes from 1.0.1

- Normal folder name and an `enabled.txt`, so UE4SS loads it without editing
  `mods.txt`. Log lines now start with `[Mi8CargoHold]`.
- 1.0.1 hooked the save system's async-save completion by one hard-coded,
  compiler-generated name (`Completed_A03379DA...`). That name can change
  whenever the game rebuilds its save system, and without the hook the whole
  mod pauses. It still uses that name while it exists; if it's gone, it hooks
  the save system's `Completed_<id>` events instead (each one only acts on the
  game's own save while a cargo save is pending).
- One-time log messages for the silent waits (joining someone else's world, no
  save slot yet, save system not found), and the pause message says which save
  hook is missing.
- Cargo save files keep their 1.0.1 names, so nothing is lost if 1.0.1 ran before.
