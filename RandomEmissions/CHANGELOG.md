# Random Emissions - Changelog

---

## 1.2.4 (2026-10-13)

- Its timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of the previous version, used by several mods at once, froze the game during normal play

## 1.2.3 (2026-10-13)

- Its timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

## 1.2.2 (2026-10-13)

- Restarting the mod in a world (`.reloadmods`, or the Mod Hub after a settings change) left emissions and the siren off until the next load; it starts straight away now, with the new settings

## 1.2.1 (2026-10-12)

### Performance
- No more Lua on every frame: the time until the emission is checked every 2 s
- The game's emission manager and your controller are found once and kept, instead of walking through every object in the game each check

## 1.2.0 (2026-10-12)

### Updating with git pull
- Your own settings go in `config.lua` (copy `config.example.lua`), not in `main.lua`, so `git pull` can always update the mod
- A `randomMax` or `sirenMax` smaller than its minimum is raised to it

## 1.1.0 (2026-10-12)

### Co-op
- Only the host's copy picks the random emission times (the host's game runs the emissions)
- When the host's siren starts, players who joined are told and their siren plays too
- In someone else's world the mod never changes the timer or plays the siren by itself

## 1.0.1 (2026-10-11)

### No More Piling Up
- The level-change hook and the per-frame loop are set up once instead of on every load and respawn, where they piled up

## Original

- Emissions at random times (every 1800-3600 s) with a siren 120-300 s before, by the original author
