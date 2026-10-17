# Sound Fixes - Changelog

---

## 1.0.1 (2026-10-17)

- 1.0.0 did nothing: it looked for the microwave only when the world started, before any microwave had loaded, and never again. It now looks every 5 s until one has loaded ("Watching microwaves" in the log)
- The first time a microwave turns on, the log says what its sound was set to before the fix

## 1.0.0 (2026-10-17)

- New mod for game sounds heard where they shouldn't be
- Microwave: when a joined player turned a microwave on, the host heard it at full volume wherever they were. Just before a microwave's on/off effect plays, its sound now gets the game's own falloff for small sounds, so it comes from the microwave and fades with distance. Each player's copy fixes what that player hears; in co-op the host needs it
