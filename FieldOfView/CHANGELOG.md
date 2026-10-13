# Field Of View - Changelog

---

## 1.5.2 (2026-10-13)

- Its timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of the previous version, used by several mods at once, froze the game during normal play

## 1.5.1 (2026-10-13)

- Its timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

## 1.5.0 (2026-10-13)

### Applies by Itself
- No more opening Settings and going back: right after changing the setting, the mod calls the game's own `SetDefaultCameraFOV` on your character, which is what leaving the Settings menu does. Sprinting ends at your field of view straight away
- It's called the way the game expects (its parameters are checked first); if they're ever different, it isn't called and the log says to open Settings and go back once
- The character component's own field-of-view values that still hold an old value follow too
- `.fov scan` crashed the game: it watched 71 of the game's functions at once, some of them run every frame. The watching is gone; the scan now only lists what it finds

## 1.4.3 (2026-10-13)

- `.fov scan` stopped at "can't list functions": this UE4SS wants the object search to be told to keep going. If it still fails, the log now says why

## 1.4.2 (2026-10-13)

- The game only uses a new field of view everywhere (sprinting too) once its settings are applied, which happens when you leave its Settings menu; that also saves it, so the game keeps it on the next start. After `.fov`, the log now says to open Settings and go back once
- `.fov scan` watches the game's settings functions for 30 s while you open Settings and go back, to find the one that applies them (so a later version can do it for you)

## 1.4.1 (2026-10-13)

- Sprinting ended back at the slider's field of view: your character keeps its own copy of the setting from when it spawned. The character's field-of-view variables that still hold an old normal value now follow yours too (values mid-sprint or mid-aim, and sprint and aim settings, are left alone)
- Going from one `.fov` value to another inside the slider's range (like 90 to 110) took the mod's own earlier value for the slider's

## 1.4.0 (2026-10-13)

### Uses the Game's Own Setting
- MISERY keeps its field of view in its settings (the options slider, 80-110), and works out the normal view, sprinting and aiming from it. The mod now sets that value itself, so the game does all of it from yours: no flicker, no jump when aiming, nothing fighting the camera
- `.fov` goes up to 130 (and down to 60)
- The slider's own value is remembered and `.fov reset` puts it back; while the mod is on it keeps the setting at yours, also if the options menu moves it
- The camera tricks of 1.1.0-1.3.1 are gone

## 1.3.1 (2026-10-13)

- 1.3.0 changed nothing in game: MISERY's camera doesn't let mods call its offset functions. Now the camera's offset variables are tried too, and if neither is there it says so once instead of every second
- `.fov scan` now records for 15 s every field of view the game gives the camera (and the value just before), while you sprint and aim, and lists the character's and camera manager's zoom, aim and sprint settings: what's needed to make a version that works

## 1.3.0 (2026-10-13)

### Works Again, Without Flicker
- 1.2.0 changed nothing: this UE4SS can't watch the engine's own camera-modifier code, so the view was never scaled
- Now uses the camera's additive offset, which Unreal adds on top of the field of view without changing it: the offset is your field of view minus the game's normal one. The game's sprint and aim zooms change only the game's own value and never see the offset, so nothing fights it and nothing jumps
- Set once per camera, not every frame; put back if the game ever clears it
- Aiming zooms in by the same number of degrees as before (game 110 aiming at 70, with your 120: 80)
- The game's normal field of view only changes once another value has been seen for 10 s longer, so aiming for a while just after spawning doesn't count

## 1.2.0 (2026-10-13)

### No More Flicker
- Sprinting (spamming Shift) and aiming flickered for a few frames with a wide field of view: the game's zooms read the camera's current field of view, which the mod had already changed, and the mod then changed the result again, so the two fought each other
- The game's camera is now left alone. The mod adds a camera modifier, the part of Unreal's camera that adjusts the final view every frame after the game is done, and scales the field of view only there. The game's sprint and aim zooms run exactly as before, just from your field of view
- The game's normal field of view is the camera's value seen most often, so a moment of sprinting or aiming can't be mistaken for it; it isn't kept in `settings.txt` any more

## 1.1.0 (2026-10-13)

### Smooth Aiming
- Aiming with a wider field of view jumped back to the game's own view first and then zoomed in. Every field of view the game gives your camera is now scaled by yours / the game's: the normal view is yours, and aiming zooms in smoothly from it and back
- Aiming zooms in by the same proportion as before (aiming at 55 with the game's 90 becomes 67 with your 110)
- Character settings are no longer changed (their scaled values would have been scaled twice)
- Changing `.fov` mid-aim keeps the zoom; `.fov scan` says how many of the game's view changes were scaled

## 1.0.0 (2026-10-12)

### First Release
- `.fov 95` sets the field of view in degrees (60-120); `.fov reset` goes back to the game's own, `.fov` shows it
- Saved to `settings.txt`
- Aiming still zooms in: the view is only changed while it's at the game's normal field of view
- Character settings that hold the normal field of view follow yours, so the view comes back from aiming at your value
- `.fov scan` lists your character's cameras and field-of-view settings, if the view doesn't change
- Only your own view changes, so it works the same in co-op
