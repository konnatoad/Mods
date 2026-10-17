-- YouTube TV settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- YouTube links the TV plays, in order (.tv download fetches them)
    videos = {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    },

    -- Like a real TV: turning a TV on plays a random video (shuffle) from a
    -- random point in it (randomStart), as if it had been on all along.
    -- false: the list in order, from the start. .tv on 2 plays video 2 from the start
    shuffle = true,
    randomStart = true,

    -- TV volume, 0 to 1
    volume = 0.8,

    -- The TV's sound comes from the TV: full volume within fullVolumeDistance,
    -- fading out until hearDistance (metres)
    hearDistance = 15,
    fullVolumeDistance = 1.5,

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

    -- The screen's size, as a share of the TV's front (width, height)
    screenWidth = 0.8,
    screenHeight = 0.75,

    -- TURN ON TV / TURN OFF TV in the game's E menu on a TV (false = off;
    -- .tv on / .tv off still work)
    eMenu = true,

    -- The game action type the entry carries when you press E on it. The TV
    -- only reacts to PICK UP (2, never used); 0 does nothing on a TV
    eMenuActionType = 0,
}
