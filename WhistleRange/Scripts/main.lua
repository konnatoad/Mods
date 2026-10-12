------------------------------------------------------------
-- Whistle Range
------------------------------------------------------------
-- In co-op the host hears and sees a player's whistle from much further away
-- than players who joined do. The likely reason: the host's game holds every
-- player's character at any distance, but only sends a character (and what it
-- does, like whistling) to a joined player while it's within Unreal's network
-- range of them - 150 m unless a game sets otherwise. Beyond that the joined
-- player's game doesn't have the whistling character at all.
--
-- This mod widens that range for the players' characters, so joined players
-- get each other's and the host's whistles from as far away as the host does.
-- Only the host's copy does anything: the host's game decides what is sent
-- to whom. It costs a little network traffic for the few player characters,
-- nothing for anything else.
--
--   .whistle          the range and the players it's applied to
--   .whistle scan     everything named like a whistle, for the log
--
-- Range: config.lua (see config.example.lua), rangeMeters; 0 = no limit.
------------------------------------------------------------
local VERSION = "1.0.0"

local rangeMeters = 0    -- 0 = no limit (like the host)

local function UserConfig()
    local path = "./ue4ss/Mods/WhistleRange/config.lua"
    local file = io.open(path, "r")
    if not file then return {} end
    file:close()
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then return result end
    print("[WhistleRange] config.lua ignored: " .. (ok and "it doesn't return a table" or tostring(result)) .. "\n")
    return {}
end

rangeMeters = math.max(0, tonumber(UserConfig().rangeMeters) or rangeMeters)
----------------------------------

local NO_LIMIT_METERS = 100000   -- 100 km: further than any map
local function RangeSquared()
    local cm = (rangeMeters > 0 and rangeMeters or NO_LIMIT_METERS) * 100
    return cm * cm
end

local function log(msg)
    print("[WhistleRange] " .. tostring(msg) .. "\n")
end

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function NameOf(obj)
    local name = ""
    pcall(function() name = obj:GetFName():ToString() end)
    return name
end

local function Meters(squared)
    if type(squared) ~= "number" or squared <= 0 then return "?" end
    local m = math.sqrt(squared) / 100
    return m >= NO_LIMIT_METERS and "no limit" or string.format("%d m", math.floor(m + 0.5))
end

-- Hosting (or alone): this game decides what is sent where
local function OwnsIt(actor)
    local ok, authority = pcall(function() return actor:HasAuthority() end)
    return ok and authority == true
end

local applied = setmetatable({}, { __mode = "k" })
local reportedJoin = false

-- A player's character: sent to everyone within the range
local function Widen(pawn)
    if not Valid(pawn) or not OwnsIt(pawn) then return end
    local want = RangeSquared()
    local now = nil
    pcall(function() now = pawn.NetCullDistanceSquared end)
    if type(now) == "number" and math.abs(now - want) < 1 then return end
    if pcall(function() pawn.NetCullDistanceSquared = want end) and not applied[pawn] then
        applied[pawn] = true
        log(string.format("%s: sent to players up to %s away (was %s)", NameOf(pawn),
            Meters(want), Meters(now)))
    end
end

-- Every character a player takes control of (joining, respawning), on the
-- host: the possession is confirmed to the host's game with this call
pcall(RegisterHook, "/Script/Engine.PlayerController:ServerAcknowledgePossession", function(selfParam, pawnParam)
    pcall(function() Widen(pawnParam:get()) end)
end)
-- The host's own character (and a backup for the others)
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(selfParam, pawnParam)
    pcall(function() Widen(pawnParam:get()) end)
    pcall(function() Widen(selfParam:get().Pawn) end)
end)

-- Every player's character right now (walks every object once: on load and
-- on .whistle only)
local function Players()
    local list = {}
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("PlayerController") or {}) do
            if Valid(ctrl) then
                local pawn = nil
                pcall(function() pawn = ctrl.Pawn end)
                table.insert(list, { ctrl = ctrl, pawn = Valid(pawn) and pawn or nil })
            end
        end
    end)
    return list
end

local function ApplyAll()
    for _, p in ipairs(Players()) do if p.pawn then Widen(p.pawn) end end
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
local function Status()
    local players = Players()
    local hosting = false
    log("Range for player characters: " .. (rangeMeters > 0 and (rangeMeters .. " m") or "no limit")
        .. " (rangeMeters in config.lua)")
    for _, p in ipairs(players) do
        local isLocal = false
        pcall(function() isLocal = p.ctrl:IsLocalController() end)
        if p.pawn then
            local now = nil
            pcall(function() now = p.pawn.NetCullDistanceSquared end)
            if OwnsIt(p.pawn) then hosting = true end
            log(string.format("  %s%s: %s", NameOf(p.pawn), isLocal and " (you)" or "", Meters(now)))
        end
    end
    if not hosting then
        log("You're not the host here: the host's Whistle Range decides (it only works in the host's game)")
    end
end

local function Scan()
    local found, count = {}, 0
    local ok = pcall(function()
        ForEachUObject(function(obj)
            if count >= 80 then return end
            local full = ""
            pcall(function() full = obj:GetFullName() end)
            if full:lower():find("whistle", 1, true) then
                count = count + 1
                table.insert(found, full)
            end
        end)
    end)
    if not ok then log("Scan: this UE4SS can't list objects") return end
    table.sort(found)
    log("Scan: " .. #found .. " thing(s) named like a whistle" .. (#found >= 80 and " (first 80)" or "") .. ":")
    for _, name in ipairs(found) do log("  " .. name) end
    log("Whistle once before scanning to include what a whistle creates. Send these lines")
end

RegisterConsoleCommandHandler(".whistle", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        else
            ApplyAll()
            Status()
        end
    end)
    return true
end)

-- After .reloadmods, the players already in the world
ExecuteInGameThread(function() ApplyAll() end)
log("Loaded v" .. VERSION .. ": player characters reach " .. (rangeMeters > 0 and (rangeMeters .. " m") or "any distance")
    .. " when you host. .whistle shows it")
