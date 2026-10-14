-- GameHooks: hooks on the game's Blueprint functions that are undone when the
-- mod is restarted.
--
-- Restarting a mod (Mod Hub's "Restart changed mods") removes its hooks on
-- engine functions (/Script/...), but its hooks on the game's own Blueprint
-- functions (/Game/...) stay, still pointing into the old copy of the mod: the
-- next time the game runs one, UE4SS crashes. With this, a mod writes the ids
-- of its Blueprint hooks to hooks.txt in its folder, and when it loads again in
-- the same game session it removes the previous copy's hooks first.
--
-- Use, at the top of a mod's main.lua (before any RegisterHook):
--   local RegisterHook = require("GameHooks").ForMod("MyMod")
-- It is called like UE4SS's RegisterHook and returns the same ids.
local M = {}

-- When this game was started, in seconds. os.clock() counts from the game's
-- start on Windows, so this stays the same for the whole session. A hooks.txt
-- from another session is ignored: its ids may belong to other mods' hooks now.
local function SessionStart()
    return os.time() - os.clock()
end

function M.ForMod(modName)
    local path = "./ue4ss/Mods/" .. modName .. "/hooks.txt"
    local session = SessionStart()

    -- undo the previous copy's hooks (same game session only)
    local file = io.open(path, "r")
    if file then
        local header = file:read("l")
        local written = tonumber(header and header:match("^session (%-?[%d%.]+)$"))
        if written and math.abs(written - session) < 5 then
            local removed = 0
            for line in file:lines() do
                local hookPath, pre, post = line:match("^(.-)|(%-?%d+)|(%-?%d+)%s*$")
                if hookPath and pcall(UnregisterHook, hookPath, tonumber(pre), tonumber(post)) then
                    removed = removed + 1
                end
            end
            if removed > 0 then
                print("[" .. modName .. "] Removed " .. removed .. " game hook(s) left by its previous copy\n")
            end
        end
        file:close()
    end
    local fresh = io.open(path, "w")
    if fresh then
        fresh:write(string.format("session %.0f\n", session))
        fresh:close()
    end

    -- RegisterHook that remembers Blueprint hooks; engine hooks pass straight through
    return function(hookPath, ...)
        local pre, post = RegisterHook(hookPath, ...)
        if type(hookPath) == "string" and hookPath:find("^/Game/") and pre ~= nil and post ~= nil then
            local out = io.open(path, "a")
            if out then
                out:write(string.format("%s|%s|%s\n", hookPath, tostring(pre), tostring(post)))
                out:close()
            end
        end
        return pre, post
    end
end

return M
