# Random Emissions - Changelog

---

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
