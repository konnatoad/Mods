-- Chest Sort settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- The key that sorts the open container (only while the inventory
    -- screen is open: S is also walking backwards)
    key = "S",

    -- Time between moves in milliseconds (each move is done by the host's
    -- game). Lower is faster; raise it if moves get refused in co-op
    moveDelayMs = 120,

    -- Items keep the way they're turned; when the container is too full to
    -- sort them like that, tall items are turned flat to fit. false: never turn
    rotate = true,

    -- Shift+click on a stack in your inventory with a container open: when the
    -- game doesn't move it (its own bug), the mod moves the whole stack
    quickMoveFix = true,

    -- Dragging moves only half a stack when the game's split key gets stuck
    -- on: clicking an item with no Ctrl/Alt/Shift held turns it off
    splitFix = true,
}
