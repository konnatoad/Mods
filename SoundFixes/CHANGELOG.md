# Sound Fixes - Changelog

---

## 1.1.1 (2026-10-17)

- `.soundwatch` no longer removes its hooks after its minute, it only stops logging. Removing a hook (UnregisterHook) in this UE4SS can free its Lua function while the hook stays, and the game then aborts the next time it plays that kind of sound ("Ref was not function": very likely the host's crash mid game, 17 Oct)

## 1.1.0 (2026-10-17)

- Found with the host's `.soundwatch`: the microwave's door sound (`MicrowaveOpenSound_Cue`) and start-cooking sound (`MicrowaveStartCookSound_Cue`) are played at the microwave but have no falloff of their own, so they're heard at full volume everywhere. Each gets the game's falloff for small sounds once it has loaded (the log says so), so they fade with distance however the game plays them. (The microwave's hum already faded; 1.0.x changed only that)

## 1.0.2 (2026-10-17)

- 1.0.1's log showed the microwave's own sound already fades with distance (`SC_MicrowaveLoop`, `SA_MediumSound`), so the sound the host hears everywhere comes from somewhere else
- `.soundwatch`: for a minute, every sound the game starts through its play-a-sound functions goes to the log, with what started it and whether it's heard everywhere (2D) or from a place. The host runs it, a joined player turns the microwave on, and the log says which sound it is

## 1.0.1 (2026-10-17)

- 1.0.0 did nothing: it looked for the microwave only when the world started, before any microwave had loaded, and never again. It now looks every 5 s until one has loaded ("Watching microwaves" in the log)
- The first time a microwave turns on, the log says what its sound was set to before the fix

## 1.0.0 (2026-10-17)

- New mod for game sounds heard where they shouldn't be
- Microwave: when a joined player turned a microwave on, the host heard it at full volume wherever they were. Just before a microwave's on/off effect plays, its sound now gets the game's own falloff for small sounds, so it comes from the microwave and fades with distance. Each player's copy fixes what that player hears; in co-op the host needs it
