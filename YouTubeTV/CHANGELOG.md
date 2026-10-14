# YouTube TV - Changelog

---

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
