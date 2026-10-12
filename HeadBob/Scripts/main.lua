------------------------------------------------------------
-- Head Bob
------------------------------------------------------------
-- How much the view bobs while walking and running, in percent of the
-- game's own (100 = unchanged, 0 = none).
--
-- The bob is a camera shake the game starts while you move. This mod changes
-- the strength each walking or running shake starts with; other shakes (hits,
-- explosions) are left alone. Shakes are told apart by their names: names with
-- run / sprint / jog count as running, walk / bob / move / step as walking.
-- If the bob doesn't change, `.headbob scan` lists the shakes the game starts
-- while you move, and the bob-like settings of your character, for the log.
--
-- Only your own view changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.0.1"
local DEFAULTS = { walk = 100, run = 100 }   -- used when there is no settings.txt
local SETTINGS_PATH = "./ue4ss/Mods/HeadBob/settings.txt"
local MAX_PERCENT = 200

local RUN_WORDS = { "run", "sprint", "jog" }
local WALK_WORDS = { "walk", "bob", "move", "step", "locomot" }

local percent = { walk = DEFAULTS.walk, run = DEFAULTS.run }
local scan = nil          -- while scanning: { until_, seen = { [name] = count }, order = {} }
local changed = {}        -- shakes this mod has changed, logged once each

local function log(msg)
    print("[HeadBob] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    for line in file:lines() do
        local key, value = line:match("^%s*(%a+)%s*=%s*(%d+)")
        if (key == "walk" or key == "run") and tonumber(value) then
            percent[key] = math.min(MAX_PERCENT, tonumber(value))
        end
    end
    file:close()
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write("walk=" .. percent.walk .. "\nrun=" .. percent.run .. "\n")
    file:close()
end

------------------------------------------------------------
-- Which shakes are head bob
------------------------------------------------------------
local function ClassName(param)
    local name = nil
    pcall(function()
        local cls = param:get()
        if cls and cls:IsValid() then name = cls:GetFName():ToString() end
    end)
    return name
end

local function Has(name, words)
    local lower = name:lower()
    for _, w in ipairs(words) do
        if lower:find(w, 1, true) then return true end
    end
    return false
end

-- "run", "walk" or nil (not head bob)
local function Kind(name)
    if not name then return nil end
    if Has(name, RUN_WORDS) then return "run" end
    if Has(name, WALK_WORDS) then return "walk" end
    return nil
end

local function Note(name, kind, scale)
    if not scan then return end
    if not scan.seen[name] then
        scan.seen[name] = 0
        table.insert(scan.order, name)
        log(string.format("Scan: %s started (strength %.2f) - %s", name, scale or -1,
            kind and ("counted as " .. kind .. "ing") or "not head bob, left alone"))
    end
    scan.seen[name] = scan.seen[name] + 1
end

-- Pre-hook for the functions that start a camera shake: (self, ShakeClass, Scale, ...)
-- Whether a shake is for this game's own player. Hosting, the game also
-- starts shakes for players who joined (sent to their games); those keep
-- their strength, so each player's own Head Bob decides theirs.
local function ForMe(selfParam)
    local mine = true
    pcall(function()
        local obj = selfParam:get()
        local pc = obj
        if obj.PCOwner ~= nil then pc = obj.PCOwner end   -- a camera manager's player
        local isLocal = pc:IsLocalController()
        if isLocal == false then mine = false end
    end)
    return mine
end

local function OnShake(selfParam, classParam, scaleParam)
    if not ForMe(selfParam) then return end
    local name = ClassName(classParam)
    if not name then return end
    local kind = Kind(name)
    local scale = nil
    pcall(function() scale = scaleParam:get() end)
    Note(name, kind, scale)
    if not kind or type(scale) ~= "number" or percent[kind] == 100 then return end
    local new = scale * percent[kind] / 100
    if pcall(function() scaleParam:set(new) end) and not changed[name] then
        changed[name] = true
        log(string.format("%s: %s bob at %d%%", name, kind == "run" and "running" or "walking", percent[kind]))
    end
end

local hooked = 0
for _, path in ipairs({
    "/Script/Engine.PlayerCameraManager:StartCameraShake",
    "/Script/Engine.PlayerController:ClientStartCameraShake",
}) do
    if pcall(RegisterHook, path, OnShake) then
        hooked = hooked + 1
    else
        log("Couldn't hook " .. path)
    end
end

------------------------------------------------------------
-- Scan: what the game starts while you move
------------------------------------------------------------
local SCAN_SECONDS = 20
local CHARACTER_WORDS = { "bob", "shake", "sway", "head" }

local function CharacterSettings()
    local found = {}
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if ctrl:IsValid() and ctrl:IsLocalController() then
                local character = ctrl.Character
                if not (character and character:IsValid()) then return end
                -- the character class's own variables only: walking parent
                -- classes crashed this UE4SS build for the mod menu
                character:GetClass():ForEachProperty(function(prop)
                    local name = ""
                    pcall(function() name = prop:GetFName():ToString() end)
                    if Has(name, CHARACTER_WORDS) then
                        local value = nil
                        pcall(function() value = character[name] end)
                        local shown = type(value) == "number" or type(value) == "boolean"
                        table.insert(found, name .. (shown and (" = " .. tostring(value)) or ""))
                    end
                end)
                return
            end
        end
    end)
    return found
end

local function StartScan()
    if scan then log("Already scanning") return end
    scan = { seen = {}, order = {} }
    log("Scanning for " .. SCAN_SECONDS .. " s: walk, then run (and stand still a moment)")
    LoopAsync(SCAN_SECONDS * 1000, function()
        ExecuteInGameThread(function()
            local result = scan
            scan = nil
            if not result then return end
            if #result.order == 0 then
                log("Scan: the game started no camera shakes - the bob is done another way")
            else
                log("Scan summary (shake, times started, what this mod does with it):")
                for _, name in ipairs(result.order) do
                    local kind = Kind(name)
                    log(string.format("  %s x%d - %s", name, result.seen[name], kind and kind or "left alone"))
                end
            end
            local settings = CharacterSettings()
            log("Character settings with bob/shake/sway/head in the name: "
                .. (#settings > 0 and table.concat(settings, ", ") or "none"))
            log("Send these lines if walking or running doesn't change with .headbob")
        end)
        return true
    end)
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
local function Status()
    log(string.format("Walking %d%%, running %d%% of the game's head bob. "
        .. ".headbob <0-%d> | .headbob walk <n> | .headbob run <n> | .headbob off | .headbob reset | .headbob scan",
        percent.walk, percent.run, MAX_PERCENT))
end

local function Set(which, value)
    value = math.max(0, math.min(MAX_PERCENT, math.floor(value + 0.5)))
    if which == "walk" or which == "both" then percent.walk = value end
    if which == "run" or which == "both" then percent.run = value end
    changed = {}
    Save()
    log(string.format("Head bob: walking %d%%, running %d%% (from the next step)", percent.walk, percent.run))
end

RegisterConsoleCommandHandler(".headbob", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    local b = tonumber((Parameters and Parameters[2]) or "")
    if a == "" then
        Status()
    elseif tonumber(a) then
        Set("both", tonumber(a))
    elseif (a == "walk" or a == "run") and b then
        Set(a, b)
    elseif a == "off" then
        Set("both", 0)
    elseif a == "reset" then
        Set("both", 100)
    elseif a == "scan" then
        StartScan()
    else
        Status()
    end
    return true
end)

Load()
log(string.format("Loaded v%s: walking %d%%, running %d%% (%d/2 hooks). .headbob to change it",
    VERSION, percent.walk, percent.run, hooked))
