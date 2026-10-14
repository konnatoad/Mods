# YouTube TV - Changelog

---

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
