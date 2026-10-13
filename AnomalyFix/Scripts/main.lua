------------------------------------------------------------
-- Anomaly Fix
------------------------------------------------------------
-- MISERY bug: electric anomalies drone with a constant, piercing bass sound
-- and only ever show one frame of their effect.
--
-- This version only looks: stand near an electric anomaly and run
--   .anomaly scan
-- It writes the anomalies around you to the log, the nearest one in detail
-- (its parts: sounds, effects and whether they're playing, its settings).
-- That shows what's stuck, so the next version can fix it.
------------------------------------------------------------
local VERSION = "0.1.0"
local MAX_LISTED = 40

local function log(msg)
    print("[AnomalyFix] " .. tostring(msg) .. "\n")
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

local function ClassName(obj)
    local name = ""
    pcall(function() name = obj:GetClass():GetFName():ToString() end)
    return name
end

-- Arrays come back as Lua tables on this UE4SS (elements maybe wrapped)
local function Each(array, fn)
    if type(array) == "table" then
        for _, raw in pairs(array) do
            local v = raw
            pcall(function() if raw.get then v = raw:get() end end)
            fn(v)
        end
    elseif array then
        pcall(function() array:ForEach(function(_, e) fn(e:get()) end) end)
    end
end

local function Distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100   -- metres
end

local function PlayerLocation()
    local loc = nil
    pcall(function()
        for _, pc in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if pc:IsValid() and pc:IsLocalController() then
                local l = pc.Pawn:K2_GetActorLocation()
                loc = { X = l.X, Y = l.Y, Z = l.Z }
                return
            end
        end
    end)
    return loc
end

-- Every live actor whose class is named like an anomaly (one walk through
-- every object, on the command only)
local function FindAnomalies()
    local found = {}
    pcall(function()
        ForEachUObject(function(obj)
            local cls = ClassName(obj)
            local lower = cls:lower()
            if (lower:find("anomal", 1, true) or lower:find("electr", 1, true))
               and not NameOf(obj):find("^Default__") then
                local isActor = false
                pcall(function() isActor = obj:IsA(StaticFindObject("/Script/Engine.Actor")) end)
                if isActor then table.insert(found, obj) end
            end
            return false
        end)
    end)
    return found
end

local function Describe(comp)
    local cls = ClassName(comp)
    local parts = { NameOf(comp) .. " (" .. cls .. ")" }
    local function add(label, fn)
        local ok, v = pcall(fn)
        if ok and v ~= nil then table.insert(parts, label .. "=" .. tostring(v)) end
    end
    add("active", function() return comp:IsActive() end)
    add("visible", function() return comp:IsVisible() end)
    if cls:find("Audio") then
        add("playing", function() return comp:IsPlaying() end)
        add("sound", function() return NameOf(comp.Sound) end)
        add("volume", function() return comp.VolumeMultiplier end)
        add("pitch", function() return comp.PitchMultiplier end)
    end
    if cls:find("Niagara") then
        add("asset", function() return NameOf(comp:GetAsset()) end)
        add("paused", function() return comp:IsPaused() end)
        add("age", function() return comp:GetDesiredAge() end)
    end
    if cls:find("Particle") then
        add("template", function() return NameOf(comp.Template) end)
    end
    if cls:find("Light") then
        add("intensity", function() return comp.Intensity end)
    end
    add("timeDilation", function() return comp.CustomTimeDilation end)
    return table.concat(parts, "  ")
end

-- The actor class's own number / true-false settings (only its own class:
-- walking parent classes crashed this UE4SS build for the mod menu)
local function Settings(actor)
    local list = {}
    pcall(function()
        actor:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            local value = nil
            pcall(function() value = actor[name] end)
            if type(value) == "number" or type(value) == "boolean" then
                table.insert(list, name .. "=" .. tostring(value))
            end
        end)
    end)
    return list
end

local function Scan()
    local here = PlayerLocation()
    local anomalies = FindAnomalies()
    log("Scan: " .. #anomalies .. " anomaly actor(s)")
    local byClass = {}
    local nearest, nearestDist = nil, math.huge
    for _, a in ipairs(anomalies) do
        local cls = ClassName(a)
        byClass[cls] = (byClass[cls] or 0) + 1
        if here then
            local ok, l = pcall(function() return a:K2_GetActorLocation() end)
            if ok and l then
                local d = Distance(here, l)
                if d < nearestDist then nearest, nearestDist = a, d end
            end
        end
    end
    local listed = 0
    for cls, n in pairs(byClass) do
        listed = listed + 1
        if listed <= MAX_LISTED then log("  " .. n .. " x " .. cls) end
    end
    if not nearest and here then
        -- named differently: everything within 10 m, to find it by hand
        log("Nothing named like an anomaly - everything within 10 m of you:")
        local shown = 0
        pcall(function()
            ForEachUObject(function(obj)
                if shown >= MAX_LISTED then return false end
                local isActor = false
                pcall(function() isActor = obj:IsA(StaticFindObject("/Script/Engine.Actor")) end)
                if isActor and not NameOf(obj):find("^Default__") then
                    local ok, l = pcall(function() return obj:K2_GetActorLocation() end)
                    if ok and l and Distance(here, l) < 10 then
                        shown = shown + 1
                        log(string.format("  %s (%s) %.1f m", NameOf(obj), ClassName(obj), Distance(here, l)))
                    end
                end
                return false
            end)
        end)
        log("Done - send these lines")
        return
    end
    if not nearest then log("No anomaly near you found - stand next to an electric anomaly and run it again") return end
    log(string.format("Nearest: %s (%s), %.1f m away", NameOf(nearest), ClassName(nearest), nearestDist))
    pcall(function() log("  actor timeDilation=" .. tostring(nearest.CustomTimeDilation)
        .. " hidden=" .. tostring(nearest.bHidden)) end)
    local count = 0
    pcall(function()
        Each(nearest:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent")), function(comp)
            if Valid(comp) then
                count = count + 1
                log("  part: " .. Describe(comp))
            end
        end)
    end)
    if count == 0 then log("  (couldn't list its parts)") end
    local settings = Settings(nearest)
    log("  settings: " .. (#settings > 0 and table.concat(settings, ", ") or "none readable"))
    log("Done - send these lines")
end

RegisterConsoleCommandHandler(".anomaly", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        else
            log(".anomaly scan - stand next to an electric anomaly and run it")
        end
    end)
    return true
end)

log("Loaded v" .. VERSION .. ": .anomaly scan near an electric anomaly lists what it's made of")
