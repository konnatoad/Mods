# Mi-8 Cargo Hold - Changelog

---

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
