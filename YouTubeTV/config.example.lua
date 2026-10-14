-- YouTube TV settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- YouTube links the TV plays, in order (.tv download fetches them)
    videos = {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    },

    -- TV volume, 0 to 1
    volume = 0.8,

    -- Highest video quality downloaded (480, 720, 1080)
    maxHeight = 720,

    -- How far .tv scan and .tv on look for a TV, in metres
    scanMeters = 8,
}
