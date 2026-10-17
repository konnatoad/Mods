-- Chest Sort settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- The key that sorts the open container (only while the inventory
    -- screen is open: S is also walking backwards)
    key = "S",

    -- Time between moves in milliseconds (each move is done by the host's
    -- game). Lower is faster; raise it if moves get refused in co-op
    moveDelayMs = 120,

    -- Turn items to lie flat (wider than tall) so they line up in even rows;
    -- false: every item keeps the way it's turned now
    rotate = true,
}
