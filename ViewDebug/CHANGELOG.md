# View Debug - Changelog

---

## 0.2.0 (2026-10-13)

- `.view hud` shows the angles on screen, live (top right, 10 times a second): where you look, the camera, the arms and weapon meshes, rotations in the arms animation (like sway), and how far the view turned since the last update. `.view hud` again hides it
- While it's shown, F11 / `.view mark` flashes MARKED on it, and a recording shows REC with its time
- `hudMs` in `config.lua` sets how often it updates

## 0.1.0 (2026-10-13)

### First Version: Recording Only
- For the game's bug where the weapon and arms get stuck at an angle after moving the mouse slowly
- `.view rec [seconds]` records many times a second where you look, what the camera shows, the angle and position of every part of your character and held weapon, and every setting that sounds like aim, sway or rotation (on the character, its animation and the weapon). It saves a `recording_<time>.csv` in the mod's folder, keeping only the values that changed
- Press F11 (or `.view mark <note>`) the moment the view sticks: the recording marks it
- `.view stop` ends it early; it also stops by itself after 60 s (`maxSeconds`)
- `.view` writes your view's angles to the log now; `.view watch` writes the main ones 4 times a second
- `.view scan` saves a list of everything on your character that turns, with its values, to `scan_<time>.txt`
- Changes nothing in the game. Settings in `config.lua`: `sampleMs`, `maxSeconds`, `markKey`
