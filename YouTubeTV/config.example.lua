-- YouTube TV settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- YouTube links the TV plays, in order (.tv download fetches them)
    videos = {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    },

    -- TV volume, 0 to 1
    volume = 0.8,

    -- YouTube often refuses anonymous downloads ("Sign in to confirm you're not
    -- a bot", age checks). Set your browser here and yt-dlp uses your YouTube
    -- login from it: "firefox", "edge", "chrome", "brave", ... ("" = off).
    -- Firefox works best; Chrome and Edge may need to be closed while it runs.
    -- A Firefox-based browser (Zen, LibreWolf...): "firefox:" and its profile
    -- folder, between [[ ]] so the backslashes stay as they are, e.g.
    --   cookiesFromBrowser = [[firefox:C:\Users\you\AppData\Roaming\zen\Profiles\abcd1234.Default (release)]],
    cookiesFromBrowser = "",

    -- Highest video quality downloaded (480, 720, 1080)
    maxHeight = 720,

    -- How far .tv scan and .tv on look for a TV, in metres
    scanMeters = 8,
}
