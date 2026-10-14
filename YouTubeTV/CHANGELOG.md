# YouTube TV - Changelog

---

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
