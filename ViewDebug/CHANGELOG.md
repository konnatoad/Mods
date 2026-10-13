# View Debug - Changelog

---

## 0.6.0 (2026-10-13)

### Reading Dumps In Game
- `.view dumps` lists the dumps and recordings you've saved, newest first, numbered
- `.view read` shows the newest one on screen (left side); `.view read 2` or `.view read <file name>` shows another. `.view read` again closes it. Dumps from before this version aren't numbered: open them by name (`.view read buffer_20261013_200919_1`)
- It shows the dump's length and every **wall**: a stretch where you kept moving the mouse on one axis but your aim didn't turn on it. For each: when, left/right or up/down, the angle it stuck at, how long, how much you pushed (and the smallest push), and the movement that broke through. The full list also goes to the log
- The files stay CSV: the game reads them, and they still open in a spreadsheet

### Walls Instead of Stuck Samples
- The summary after a dump or recording now lists the walls (same as `.view read`) instead of counting single "the mouse moved but your aim didn't turn" samples. Each axis is checked on its own, a frame without mouse input doesn't end a wall, and looking straight up or down isn't one

## 0.5.1 (2026-10-13)

- The weapon is back in recordings, the buffer and the readout: its parts' angles and its aim / sway settings, and the same for other things attached to your character (magazine, clothing). The first dump showed the arms never turn relative to the camera, so the stuck angle is most likely on the weapon. (0.4.2 dropped it while chasing the crash, which turned out to be the background timer.) Everything is checked to still exist before every read, and a new weapon is picked up after a swap
- Attached things are named by their kind (`BP_Saiga12_C/...`), so a new copy of the same weapon keeps the same columns
- "The mouse moved but your aim didn't turn" no longer counts looking straight up or down: pushing further there is ignored on purpose

## 0.5.0 (2026-10-13)

- The buffer still crashed the game after 15-25 seconds. The cause wasn't what it read but how: it took its readings on a background timer 60 times a second, while the mouse listener ran on the game thread every frame. The mod's Lua code running on two threads at once breaks Lua within seconds
- Now recordings, the buffer, the readout and `.view watch` all run from one of the game's own every-frame events (the controller's, your character's or its animation's), on the game thread, and nothing runs on a background timer. The log says which event it uses ("Running every frame with ..."); it's only hooked while one of them is on
- If the game has no such event to hook, the log says so and nothing starts

## 0.4.2 (2026-10-13)

- The buffer crashed the game after a while. Recordings, the buffer and the readout also read things attached to your character that come and go (the weapon, its magazine, clothing): reading one just after the game removes it (reloading, swapping) crashes, and the mod only noticed a removal once a second
- Now they read only what lives as long as your character: where you aim, the camera, your character's own parts and their animations (where arms sway lives). Each of those is checked to still exist before every read, and a replaced animation is picked up again
- The weapon's parts and settings are still listed by `.view scan`, which reads them once

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
