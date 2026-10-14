# Mi-8 Cargo Hold - Changelog

---

## 1.1.1 (2026-10-14)

- Restarting this mod from the Mod Hub ("Restart changed mods") could crash the game: UE4SS removes a restarted mod's hooks on engine functions, but its hooks on the game's own functions stayed, still pointing into the old copy of the mod, and the next time the game ran one UE4SS crashed. They're now written down (`hooks.txt` in the mod's folder) and removed when the mod loads again in the same game session (shared `GameHooks` module)

## 1.1.0 (2026-10-11)

### Updated for the 5 October 2026 Patch
- Renamed from `ChopperStorage` to `Mi8CargoHold`, with an `enabled.txt`, so UE4SS loads it without editing `mods.txt`; log lines start with `[Mi8CargoHold]`
- Keeps working when a game update renames the save-system hook it needs: if the old hard-coded name is gone it hooks the save system's `Completed_<id>` events instead
- One-time log messages for the silent waits, and the pause message says which save hook is missing
- Cargo save files keep their 1.0.1 names, so nothing is lost

### Co-op
- Joining players use the host's hold (same prompt and window); the host's save keeps the items
- If the host doesn't have the mod, the log says so and nothing changes

## 1.0.1

- The "Mi 8 Cargo Hold" download (`ChopperStorage`) by its original author, made for MISERY build 25144234
