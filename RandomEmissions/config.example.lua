-- Random Emissions settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
-- In co-op only the host's settings count.
return {
    -- Time until the next emission: random between these, in seconds
    randomMin = 1800,
    randomMax = 3600,
    -- Siren warning before it, between these many seconds before
    isSirenEnabled = true,
    sirenMin = 120,
    sirenMax = 300,
    sirenVolume = 3.0,
}
