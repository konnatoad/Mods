# YouTube TV - Changelog

---

## 0.5.4 (2026-10-15)

- Media Plate marked itself as playing but its player never got the video (no URL). Two changes to find out why and maybe fix it: Media Plate gets the TV's screen panel as its mesh (it may only open media while its mesh is visible), and if it still doesn't start, the log line also shows the file path it was given, whether that file is there, and what its media source says (URL, valid). TVs still fall back to playing from the start

## 0.5.3 (2026-10-15)

- 0.5.2's TVs stayed dark: Media Plate took the video but never started it. Now the first video a Media Plate opens is checked 2 s later; if it isn't playing, the log says what the player reports ("Media Plate didn't start the video ...") and TVs play from the start with the plain player again, as before 0.5.2
- The crash about a minute into the game is still open. It isn't from 0.5.1's time values (0.5.2 had none and crashed the same way); it's the engine's memory clean-up meeting a bad pointer, and which mod leaves it isn't known yet

## 0.5.2 (2026-10-15)

- 0.5.1's TVs always started from the beginning, and the game crashed about a minute after it started. Jumping in a video used the engine's time values, which this UE4SS can't read or make: the length came back as nothing ("a short video"), and the jump went to 0:00. The crash came from the engine's memory clean-up (it runs about once a minute) tripping over a bad pointer; 0.4.3's crash had the same signature
- Those time values are gone. A video's length is read from the video file itself, and the TV's player is now the engine's Media Plate, which opens a video at a start time in plain seconds. So a TV turned on starts somewhere in the middle, and co-op players start where the host's video is
- If Media Plate doesn't work in this game, the TV falls back to the old player (the log says "videos start from the beginning")
- `.tv seek <seconds>` opens the video that plays again from that point (hosting: for every player too)
- `.tv status` shows which player the TV uses, the video's length and about how far in it is

## 0.5.1 (2026-10-15)

### Like a Real TV
- Turning a TV on plays a random video from `config.lua` (downloaded ones first), from a random point in it, as if the TV had been on all along. `.tv next` (another channel) does the same and never repeats the video that's on
- In co-op every player sees the same random video at the same point: joined players are told once the host's TV has picked it
- `shuffle = false` / `randomStart = false` in `config.lua` bring back the list in order, from the start. `.tv on 2` still plays video 2 from the start

## 0.5.0 (2026-10-15)

### Co-op
- The host's game decides what TVs play in the host's world, and every player sees and hears the same video at the same point. Everyone needs this version
- A joined player turning a TV on or off (E menu, `.tv on`, `.tv off`, `.tv next`) asks the host; the host plays a video from the host's `config.lua` list and tells every player which TV, which video and how far in
- Each player's game plays its own copy of the video file and jumps to the host's point; nothing is sent through the game. A joined player who doesn't have the video gets it downloaded in a minimized window (yt-dlp needed on every PC), and it starts at the host's point when it's done
- Joining while a TV plays, or respawning, catches up by itself (3 s after you're in the world); `.tv sync` asks again
- A TV the host turns on that isn't loaded in your game yet starts when you look at it
- If the host doesn't have this version, a joined player's TV says "No answer from the host" after 3 s and plays only for them
- The screen goes on the side of the TV the player who turned it on was facing, on every PC
- `.tv seek <seconds>` jumps in the video that plays: test it on your own first; if it doesn't jump, co-op players start from the beginning instead of the host's point
- `.tv status` shows how far into the video the player is

## 0.4.8 (2026-10-14)

- The hook clean-up from 0.4.7 now comes from the shared `GameHooks` module (the other mods use it too), which also fixes a flaw in it: `hooks.txt` survives closing the game, and on the next game start its old ids could belong to other mods' hooks, which would have been removed. A `hooks.txt` from an earlier game session is now ignored

## 0.4.7 (2026-10-14)

- Restarting this mod from the Mod Hub ("Restart changed mods") could crash the game: UE4SS removes a restarted mod's hooks on engine functions, but its hooks on the game's own functions (the E menu, TVs being removed, `.tv learn`'s) stayed, pointing into the old copy of the mod, and the next time the game ran one, UE4SS crashed. Every such hook is now written to `hooks.txt`, and on load the previous copy's hooks are removed first
- Restart the game once after updating: hooks made by older versions aren't in that list

## 0.4.6 (2026-10-14)

- 0.4.5's E did nothing: it took the TV from the menu's "last looked at" field, which doesn't hold it when E is pressed. It now takes the TV from the entry itself (made for that TV, and in the menu at that moment), then the menu's fields. If E on TURN ON TV still does nothing, the log says why once ("E menu: E pressed, but ...")

## 0.4.5 (2026-10-14)

- Picking up a TV that was on, placing it elsewhere and looking at it crashed the game. Picking a TV up deletes it (placing makes a new one), but the mod still held the old TV, its player and the old menu entry, and checking a deleted object crashes UE4SS
- Now nothing that can be deleted is held on to: TVs are recognised by their address (taken while they exist), E reads the selected entry and the TV you look at fresh from the menu each time, and when the game removes a build part (a TV picked up, broken) the mod lets go of it first, turning it off. A level load or respawn forgets everything

## 0.4.4 (2026-10-14)

- TURN ON TV works from the E menu. But turning it off 0.3 s after turning it on crashed the game, in one of its own background threads: turning off deleted the TV's player, sound and screen while the engine's video and audio threads were still opening the video
- Turning off now only stops the video and hides the screen; the player, sound and screen stay on the TV and are used again next time it's turned on. Nothing is deleted while the engine may still be using it
- E toggles a TV at most once a second (a double press, or a held key, toggled it twice in 0.3 s)

## 0.4.3 (2026-10-14)

- The entry read "Text Block" until you scrolled to it: an entry has two labels, one shown while it's selected and one while it isn't, and only the first was set. Both say TURN ON TV / TURN OFF TV now

## 0.4.2 (2026-10-14)

- TURN ON TV showed for about a second, then disappeared. The game's InitializeEntry starts a timer on each entry (UpdateText) that asks the TV for its actions again and drops the entry if there's none at its place in the list; ours is past the end. The entry is now filled in directly (action, TV, place, text), without that timer, so it stays

## 0.4.1 (2026-10-14)

- 0.4.0 crashed the game the moment you looked at a TV, without a log line or a crash report. The first thing it did for a TV's menu was ask the engine for the action types' readable names; that's gone (not needed)
- Until the entry has been added once, every step is logged before it's done ("E menu step: ..."), starting with the menu hook's first call for anything you look at, so a crash shows exactly where

## 0.4.0 (2026-10-14)

### TURN ON TV in the E Menu
- Look at a TV: its E menu has **TURN ON TV** under PICK UP (**TURN OFF TV** while it plays). Scroll to it and press E
- Built into the menu widget itself, the way the game builds its entries, after the game's own InitializeContextMenu (which Mi-8 Cargo Hold hooks safely); the TV's own functions aren't hooked (that crashed in 0.3.0). Learned from `.tv learn` and UE4SS's object dump (Ctrl+J): the menu scrolls through its entry widgets, pressing E sends the selected action's type to the TV, and the TV only reacts to PICK UP (type 2)
- The entry carries type 0, which the TV ignores, and the mod catches E on it itself. `eMenuActionType` in `config.lua` changes it (2 is never used). The log lists the action types' names once
- `eMenu = false` leaves the E menu alone

## 0.3.2 (2026-10-14)

- Toward a TURN ON TV entry built into the E menu widget itself (the way Mi-8 Cargo Hold edits that menu, without the TV's own functions): `.tv learn` also logs the menu's and its entries' settings, what PopulateMenu, InitializeContextMenu, InitializeEntry and EntrySelected take, the game's action types (PICK UP is 2), and what the menu holds and has selected when you press E. Names and types only, and it finds the menu through its own functions, not by searching the game's objects

## 0.3.1 (2026-10-14)

- 0.3.0 crashed the game as soon as you looked at a TV: the game asks the TV for its E menu entries ("SGK PossibleActions") every time you look at it, and that function returns a list. This UE4SS crashes handling a hooked Blueprint function's returned list, before any of the mod's code runs. Those hooks are switched off, so there's no TURN ON TV entry for now; `.tv on` / `.tv off` work as before
- `.tv learn` no longer watches the TV's own functions (same reason), only the E menu's

## 0.3.0 (2026-10-14)

### Turn It On With E
- Walk up to a TV and press E: the game's own E menu has **TURN ON TV** (and **TURN OFF TV** while it plays), next to PICK UP. Choosing it starts the first video on that TV, with its screen and sound; no `.tv on` needed
- How: `.tv learn` showed the TV answers the game's "SGK PossibleActions" (the menu's entries) and "SGK Interact" (the one chosen). The mod adds its entry to that list and catches it when it's chosen. The entry uses the game's own "use / turn on" action type, read from the game (the log lists them all); if there's none, no entry is added rather than risk one like PICK UP
- `eMenu = false` in `config.lua` leaves the E menu alone

## 0.2.2 (2026-10-14)

- Toward turning the TV on with E from the game's own menu: `.tv learn` (look at a TV) logs the functions and settings of the TV's class, its parent classes and the E menu (names and types only, nothing is read), and watches them: open the E menu on the TV, scroll, press E on an entry, and the log shows what ran and what the menu held. That shows where a "Turn on" entry can go and how to catch it

## 0.2.1 (2026-10-14)

- The TV's sound comes from the TV instead of straight into your headphones: it's positioned (left / right as you turn) and fades with distance, full volume within `fullVolumeDistance` (1.5 m) and silent past `hearDistance` (15 m). It's mixed to one channel, since a stereo sound can't come from one point, and set up before the sound starts (it reads these settings only then)
- `.tv hud` still plays straight to you (its panel isn't anywhere in the world)

## 0.2.0 (2026-10-14)

### A Screen on the TV
- First picture on a TV: the video played and was heard, but covered the whole TV. MISERY's TV is one mesh with one texture for the casing and the screen together, so swapping that texture paints everything
- The TV is now left alone and gets its own screen: a thin panel on the side facing you (you look at the screen when you turn it on), 80% of the front's width and 75% of its height (`screenWidth` / `screenHeight` in `config.lua`). It shows the video through a copy of the TV's material, so it's lit like the TV; you walk and shoot through it
- If the picture is sideways, mirrored or the wrong size: `.tv turn` (90 degrees), `.tv mirror`, `.tv size 1.1` (10% bigger; 0.9 smaller)
- `.tv off` removes the panel

## 0.1.7 (2026-10-14)

- `.tv on` did nothing ("it has no mesh to show a picture on") and `.tv scan` listed no materials: the game reports the part you hit (a mesh) instead of the TV it belongs to. They now go up to the part's owner, the TV, and the part you aimed at is always one of the screens tried

## 0.1.6 (2026-10-14)

- `.tv scan` still crashed the game: going through the game's actor list also reaches actors that are already being removed, and even checking one of those crashes (inside UE4SS's object check). So it doesn't look around any more: **look at the TV**. `.tv scan` and `.tv on` trace a line from your view, like a shot, up to `scanMeters` away, and read only what it hits (the engine just found it, so it exists)
- `.tv scan` also says which part of it you're looking at, and `.tv on` prefers that part as the screen

## 0.1.5 (2026-10-14)

- `.tv scan` (and `.tv on`) crashed the game: looking for TVs walked through every object in the game, including ones the engine was still building or removing. They now go through the game's list of actors, check each one before reading it, and log how many they looked at
- `.tv status` shows the decoder's name and the file instead of object addresses, and counts video tracks (it counted caption tracks)
- Found with `.tv status`: the video does play (ready, playing, 640x360, sound on), so what's left is getting it seen and heard

## 0.1.4 (2026-10-14)

- `.tv hud` opened the video (the game said yes) but nothing showed or played. `.tv status` asks the player what it's doing: which decoder it picked, ready / preparing / playing, the video's length and time, its tracks and size, the picture's size, and whether the sound is on. If it's ready but not playing, it tells it to play
- "Play once opened" is switched on before a video opens, in case the engine component's player has it off

## 0.1.3 (2026-10-14)

- Downloads went to the download folder set in your own yt-dlp config (e.g. `Downloads\videos`) instead of the mod's `videos` folder. The mod's folder is now given to yt-dlp as a full path (`-P`), which overrides that; the rest of your yt-dlp config still applies

## 0.1.2 (2026-10-14)

- `cookiesFromBrowser` takes a profile folder too, for Firefox-based browsers like Zen: `[[firefox:C:\...\Profiles\xzqhbajk.Default (release)]]`, like yt-dlp's own `--cookies-from-browser "firefox:<folder>"`. The folder may only have letters, digits, spaces and `: \ / . _ - ( )`
- `--recode-video mp4` as a last resort, for a video with no MP4 format at all (H.264 + AAC is still asked for first, which needs no re-encoding)

## 0.1.1 (2026-10-14)

- `.tv download` failed silently: YouTube refused the videos ("Sign in to confirm you're not a bot", and an age check), in a window that closed at once. `.tv list` now shows why each failed, from a log yt-dlp writes for each video (`videos\<id>.log`)
- New `cookiesFromBrowser` setting (off by default): yt-dlp uses your YouTube login from that browser (firefox, edge, chrome, ...), which gets past those checks. Only real browser names are accepted
- Downloads run from a small `download.cmd` the mod writes (one minimized window, the videos one after another) and use yt-dlp's full path, in case the game doesn't see your PATH

## 0.1.0 (2026-10-14)

### First Version: Finding Out What Works (experimental)
- Turn on a TV and it plays YouTube videos from `config.lua`, with sound from the TV. This version tests each piece and logs every step (`[YouTubeTV]` in UE4SS.log)
- `.tv probe` checks which video, sound and material pieces the game has
- `.tv download` downloads the videos in `config.lua` with yt-dlp (needs yt-dlp and ffmpeg) into the `videos` folder, in minimized windows while the game keeps running. Only the 11-character video ID is taken from each link
- `.tv list` shows which videos are downloaded
- `.tv scan` lists TVs and screens near you with their materials and texture slots
- `.tv hud` plays the first video in a panel on your screen, to test playback by itself
- `.tv on [n]` plays video n on the nearest TV, `.tv next` the next one, `.tv off` stops it
- Not yet: co-op (the host's list for everyone, in sync)
