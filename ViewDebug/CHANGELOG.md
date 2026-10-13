# View Debug - Changelog

---

## 0.4.1 (2026-10-13)

- No hotkey by default: `.view dump` saves the buffer and `.view mark` marks a recording. To use a key as well, set `markKey = "F12"` (or another key) in `config.lua` or in the Mod Hub's settings page

## 0.4.0 (2026-10-13)

### Buffer: Save It After It Happens
- `.view buffer` keeps the last 25 seconds of everything `.view rec` records (aim, camera, weapon, mouse input), forgetting older seconds. `.view buffer` again (or `.view stop`) turns it off
- When the view sticks, `.view dump` saves those 25 seconds to `buffer_<time>.csv` and the buffer keeps going
- Or press F12 (or `.view mark`) without opening the console: 2 seconds later it saves the 25 seconds before the press and the 2 after
- `.view buffer 40` keeps 40 seconds (up to 60); `bufferSeconds` in `config.lua` sets the default
- The mark key is now F12: F11 switches the game to fullscreen. Change it with `markKey`
- Recordings and the buffer look your character up again after a respawn or weapon swap and keep going, instead of stopping
- The readout shows BUFFER while it's on, and SAVING... between the press and the save

## 0.3.0 (2026-10-13)

### Mouse Input
- Recordings and the on-screen readout now also capture your mouse input separately from where you aim and what the camera shows. That's the movement the game hands Unreal each frame to turn the view (`mouseYaw`, `mousePitch` and `mouseCalls` columns; "mouse / update" on the readout)
- So it can tell "the mouse moved but nothing turned" apart from holding the mouse still
- After a recording, the log says how many times the mouse moved but your aim didn't turn (and the smallest such movement, next to the smallest one that did turn), and how many times your aim turned but the camera didn't
- It only listens while recording or while the readout is shown, and stops listening right after
- If the log says "no input seen", the game turns the view without Unreal's look functions; aim, camera and weapon are still recorded

## 0.2.2 (2026-10-13)

- `.view hud` no longer drops your FPS. Each of its 10 updates a second searched the whole game for the HUD, then rebuilt the panel (and searched every widget for leftovers), and every 5 s it re-read all your character's settings. Now an update only reads the angles shown and sets the text
- It looks your character up again only when something changed: a respawn, a level load or a weapon swap (checked once a second by reading the names of your character's parts)

## 0.2.1 (2026-10-13)

- `.view hud` crashed the game (and `.view`, `.view scan` and `.view rec` would have too). Looking for aim and sway settings, the mod read every setting on your character, its animation and weapon, and reading some kinds (links to other objects, event lists) crashes UE4SS. It now checks each setting's type first and reads only numbers, true/false, angles and positions
- The first look-up after loading writes each step to the log (`first look-up: ...`), so if the game still crashes, the last line shows where

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
