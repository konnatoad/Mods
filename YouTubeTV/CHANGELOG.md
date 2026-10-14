# YouTube TV - Changelog

---

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
