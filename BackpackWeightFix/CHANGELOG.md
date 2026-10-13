# Backpack Weight Fix - Changelog

---

## 1.2.5 (2026-10-13)

- Its timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of the previous version, used by several mods at once, froze the game during normal play

## 1.2.4 (2026-10-13)

- Its timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

## 1.2.3 (2026-10-13)

- Restarting the mod (Mod Hub, `.reloadmods`) could freeze the game for up to 30 s: UE4SS can only stop a mod once its timer wakes up, and this one slept 30 s. It now ticks every second and checks every `checkEverySeconds` as before

## 1.2.1 (2026-10-12)

### Performance
- Finding the containers walks through every object in the game, a short hitch, and it happened every 30 s. The containers found are now kept and only looked for again every 5 minutes, after a level load, or on `.fixweight`
- Your player's controller is found once and kept

## 1.2.0 (2026-10-12)

### Updating with git pull
- Your own settings go in `config.lua` (copy `config.example.lua`), not in `main.lua`, so `git pull` can always update the mod
- `checkEverySeconds` is at least 5

## 1.1.0 (2026-10-12)

### Co-op
- The host's game keeps every container, the joined players' backpacks too, so the host's copy fixes them for everyone
- In someone else's world the mod changes nothing (a change there would only be undone); `.fixweight` says so

## 1.0.1 (2026-10-12)

### Crash Fix
- Asking a container without an owner for the owner's name crashed the game; every link is checked first now, and such containers are still fixed

## 1.0.0 (2026-10-11)

### First Release
- Empty containers stuck with weight (like an empty backpack at 73/75 kg) go back to 0 every 30 s
- `.fixweight` runs it right now
- `.weightreport` lists the containers' number variables, for when the weight value can't be found
- The game's global inventory manager is left alone
