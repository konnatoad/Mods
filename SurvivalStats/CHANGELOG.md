# Survival Stats - Changelog

---

## 1.0.2 (2026-10-13)

- Its timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of the previous version, used by several mods at once, froze the game during normal play

## 1.0.1 (2026-10-13)

- Its timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

## 1.0.0 (2026-10-12)

### First Release
- `.stats` shows or hides a small panel with your exact survival numbers: health, stamina, hunger, thirst, radiation, insanity and any other stat it finds, updated every second
- Off until you switch it on; on / off and the position are saved to `settings.txt`
- `.stats move` puts it somewhere else on the screen (left middle, top left, top right, right middle, bottom left)
- `.stats scan` lists every number on your stats component, if a stat is missing or wrong
- Only reads your own numbers and changes nothing, so it's safe in co-op
