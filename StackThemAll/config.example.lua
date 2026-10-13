-- Stack Them All settings. Copy this file to config.lua (in this folder, next
-- to the scripts folder) and change what you like; `git pull` never touches it.
-- Or change them in game: .mods -> Stack Them All -> Settings.
-- Per-item values (e.g. Resource_Rubles = 250) go in scripts\stackConfig.lua,
-- which is yours too. In co-op everyone should use the same values.
return {
    -- Stack size for every item of a category (the start of its ID:
    -- Food_Apple -> Food). Weapons, equipment, magazines and the like keep
    -- the game's own stacks on purpose: stacking them can lose items.
    Ammo_StackSize = 1000,
    Food_StackSize = 100,
    Drink_StackSize = 100,
    Consumable_StackSize = 100,
    Resource_StackSize = 100,
    Plant_StackSize = 100,
    Object_StackSize = 100,
    BuildPart_StackSize = 100,
    Artifact_StackSize = 100,

    -- true: only stack sizes change; weight, size and the rest stay as the game has them
    onlyStacksChanges = false,

    -- true: items in scripts\stackConfig.lua are kept in alphabetical order
    aphapeticallySorted = true,
}
