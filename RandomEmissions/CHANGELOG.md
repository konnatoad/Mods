# Random Emissions - Changelog

---

## 1.2.8 (2026-10-24)

- The game could crash when picking things up (a fatal error in UE4SS's Lua): this mod hooked every 2D sound the game plays to catch the game's own siren, and read each sound's name there. That hook is gone. It never caught a siren anyway; this mod still never starts a second siren of its own while one sounds

## 1.2.7 (2026-10-17)

- The siren felt like a false alarm, with the real emission coming well after it: the siren is 2 minutes long but started up to 5 minutes before the emission, so it could end 3 minutes early. It now starts 2 to 2.5 minutes before (`sirenMax` 300 -> 150), so it ends at most 30 s before the emission. A `config.lua` with its own `sirenMax` still decides (only the host's counts in co-op)
- Hosting: the log says when the next emission is set and when its siren will sound

## 1.2.6 (2026-10-17)

- Two sirens could sound on top of each other. This mod never starts a second siren while its own still sounds, and if the game itself starts a siren while this mod's sounds, this mod's stops
- The log says each time a siren starts and why (the timer, so many seconds before the emission; or the host's), and when the game starts one itself - so the next emission shows where a second siren comes from

## 1.2.5 (2026-10-14)

- Restarting this mod from the Mod Hub ("Restart changed mods") could crash the game: UE4SS removes a restarted mod's hooks on engine functions, but its hooks on the game's own functions stayed, still pointing into the old copy of the mod, and the next time the game ran one UE4SS crashed. They're now written down (`hooks.txt` in the mod's folder) and removed when the mod loads again in the same game session (shared `GameHooks` module)

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
