-- Stack Them All settings. Copy this file to config.lua (in this folder, next
-- to the scripts folder) and change what you like; `git pull` never touches it.
-- Anything here replaces the value in scripts\stackThemAllConfig.lua.
-- Per-item values (e.g. Resource_Rubles = 250) go in scripts\stackConfig.lua,
-- which is yours too. In co-op everyone should use the same values.
return {
    -- Stack size for every item of a category (the start of its ID: Food_Apple -> Food)
    Food_StackSize = 100,
    Ammo_StackSize = 1000,

    -- true: only stack sizes change; weight, size and the rest stay as the game has them
    onlyStacksChanges = false,
}
