------------------------------------------------------------
-- World Tweaks
------------------------------------------------------------
-- Day/night length, season and darker nights in one place.
-- Replaces DayLengthTweaks and the Darker Nights pak (777_DarkerNights_P).
--
-- Co-op: day/night length and season belong to the host's world. In someone
-- else's world this mod asks the host's World Tweaks for its numbers and uses
-- those, so both games' clocks run at the same speed (a host without World
-- Tweaks: nothing is changed). Darker nights is only how your own sky looks,
-- so it always uses your own setting.
------------------------------------------------------------
-- Config
------------------------------------------------------------
local Config = {
    -- Speed of time passing (same numbers as DayLengthTweaks; game default 11 / 4)
    dayLength = 22.0,
    nightLength = 4.0,

    -- Season to switch to after a world loads: "" leaves the game's season alone,
    -- or "spring", "summer", "autumn", "winter".
    season = "",

    -- Darker nights: how bright the night sky is in spring, summer and autumn,
    -- in every weather. Game default 20.0; the Darker Nights pak used 7.5;
    -- lower is darker. Winter nights are already 0.4 and are left alone.
    -- nil = keep the game's value.
    nightSkyLight = 7.5,
}
----------------------------------

local WEATHER_MANAGER = "BP_MultiplayerDynamicWeatherManager_C"
local WEATHER_TABLE = "/Game/MultiplayerDynamicWeatherSystem/Blueprints/DT_Weather.DT_Weather"
local DUMP_PATH = "./ue4ss/Mods/WorldTweaks/weather_dump.txt"
-- E_Seasons enum (from the mod menu's .season command)
local SEASONS = { spring = 0, summer = 1, autumn = 2, fall = 2, winter = 3 }

local applyRunning = false
local askedFor = nil          -- joined: the weather manager we asked the host about
local hostAnswered = false
local seasonAppliedTo = nil   -- address of the weather manager the season was set on

local function log(msg)
    print("[WorldTweaks] " .. tostring(msg) .. "\n")
end

local function FindWeatherManager()
    local wm = nil
    pcall(function()
        local found = FindFirstOf(WEATHER_MANAGER)
        if found and found:IsValid() then wm = found end
    end)
    return wm
end

local function AddressOf(obj)
    local ok, address = pcall(function() return obj:GetAddress() end)
    return ok and address or nil
end

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

-- The player controller of this game's own player
local function LocalController()
    local found = nil
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(ctrl) and ctrl:IsLocalController() then found = ctrl return end
        end
    end)
    return found
end

-- In someone else's world (the host's game has authority over our controller)
local function Joined(ctrl)
    ctrl = ctrl or LocalController()
    if not ctrl then return false end
    local ok, authority = pcall(function() return ctrl:HasAuthority() end)
    return ok and authority == false
end

------------------------------------------------------------
-- Darker nights
------------------------------------------------------------
-- DT_Weather row -> Season -> Spring/Summer/Autumn -> Skylight ->
-- SkylightNightIntensity is the only value the Darker Nights pak changed.
-- Blueprint struct fields are named Field_<n>_<GUID>; they are matched by
-- their readable part, so a game update that changes the GUIDs still works.
local nightSkyPaths = nil
local nightSkyAppliedTo = nil
local nightSkyWarned = false

local function BaseName(name)
    return name:match("^(.-)_%d+_%x+$") or name
end

-- Full name of the field with this readable name, and its struct type if it is one
local function FindField(structType, base)
    local fullName, nested = nil, nil
    pcall(function()
        structType:ForEachProperty(function(prop)
            if fullName then return end
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            if BaseName(name) == base then
                fullName = name
                pcall(function() nested = prop:GetStruct() end)
            end
        end)
    end)
    return fullName, nested
end

local function ResolveNightSkyPaths(dt)
    local paths = {}
    local rowStruct = nil
    pcall(function() rowStruct = dt.RowStruct end)
    if not rowStruct then return paths end
    local season, seasonType = FindField(rowStruct, "Season")
    if not season or not seasonType then return paths end
    for _, seasonName in ipairs({ "Spring", "Summer", "Autumn" }) do
        local field, fieldType = FindField(seasonType, seasonName)
        if field and fieldType then
            local skylight, skylightType = FindField(fieldType, "Skylight")
            if skylight and skylightType then
                local night = FindField(skylightType, "SkylightNightIntensity")
                if night then paths[#paths + 1] = { season, field, skylight, night } end
            end
        end
    end
    return paths
end

-- Writes nightSkyLight into the weather table; the weather system picks it up
-- from there (at the latest on the next weather change).
local function ApplyNightSky()
    if Config.nightSkyLight == nil then return end
    local dt = nil
    pcall(function()
        local found = StaticFindObject(WEATHER_TABLE)
        if found and found:IsValid() then dt = found end
    end)
    if not dt then return end
    if not nightSkyPaths or #nightSkyPaths == 0 then nightSkyPaths = ResolveNightSkyPaths(dt) end
    if #nightSkyPaths == 0 then
        if not nightSkyWarned then
            nightSkyWarned = true
            log("Darker nights: couldn't find SkylightNightIntensity in DT_Weather - run .weatherdump and send it")
        end
        return
    end
    local written, rows = 0, 0
    pcall(function()
        dt:ForEachRow(function(rowName, row)
            rows = rows + 1
            for _, p in ipairs(nightSkyPaths) do
                if pcall(function() row[p[1]][p[2]][p[3]][p[4]] = Config.nightSkyLight end) then
                    written = written + 1
                end
            end
        end)
    end)
    local address = AddressOf(dt)
    if written > 0 and address ~= nightSkyAppliedTo then
        nightSkyAppliedTo = address
        log(string.format("Darker nights: night sky light %.1f in %d weathers x %d seasons (game default 20.0)",
            Config.nightSkyLight, rows, #nightSkyPaths))
    end
end

-- Returns true once the settings are on the weather manager.
local AskHost   -- co-op, below

local function Apply()
    ApplyNightSky()
    local wm = FindWeatherManager()
    if not wm then return false end

    local ctrl = LocalController()
    if Joined(ctrl) then
        AskHost(ctrl, wm)
        if Config.nightSkyLight ~= nil then pcall(function() wm["Set Elements"](wm) end) end
        return true
    end

    local okLength = pcall(function()
        wm["Day Length"] = Config.dayLength
        wm["Night Length"] = Config.nightLength
    end)

    local seasonIndex = SEASONS[string.lower(Config.season or "")]
    local address = AddressOf(wm)
    if seasonIndex and address ~= seasonAppliedTo then
        -- once per loaded world, so respawning doesn't restart the transition
        if pcall(function() wm["Toggle Season"](wm, seasonIndex, 1.0, 0) end) then
            seasonAppliedTo = address
            log("Season set to " .. Config.season)
        end
    end

    if okLength then
        log(string.format("Day length %.1f, night length %.1f", Config.dayLength, Config.nightLength))
    end
    if Config.nightSkyLight ~= nil then
        -- same refresh the mod menu uses after changing the time
        pcall(function() wm["Set Elements"](wm) end)
    end
    return okLength
end

-- ClientRestart fires before the weather manager exists on a fresh load, so
-- keep trying for up to 30s instead of failing on the first try.
local function ApplySoon()
    if applyRunning then return end
    applyRunning = true
    local tries, applied = 0, false
    LoopAsync(1000, function()
        -- ExecuteInGameThread only queues the work, so the result of the
        -- previous try is checked here, on the next tick
        if applied or tries >= 30 then
            applyRunning = false
            return true
        end
        tries = tries + 1
        ExecuteInGameThread(function()
            if not applied and Apply() then applied = true end
        end)
        return false
    end)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ApplySoon()
end)

------------------------------------------------------------
-- Co-op
------------------------------------------------------------
-- Same two messages Unreal always has as the Radiation Shield uses:
-- player -> host: ServerNotifyLoadedWorld(FName "WTWEAKS_ASK") (the game
--   ignores the name; the host's mod reads it)
-- host -> player: ClientMessage("... #WT:<day>:<night>:<season>"), season -1
--   when the host doesn't force one. Shows as a line in the player's console.
local SERVER_TAG = "WTWEAKS_ASK"

local function ParamString(param)
    local value = param
    pcall(function() value = param:get() end)
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    return ok and s or ""
end

AskHost = function(ctrl, wm)
    local address = AddressOf(wm)
    if address == askedFor then return end
    askedFor, hostAnswered = address, false
    local sent = pcall(function() ctrl:ServerNotifyLoadedWorld(FName(SERVER_TAG)) end)
    log("In someone else's world: asking the host for their day length and season")
    LoopAsync(3000, function()
        if askedFor == address and not hostAnswered then
            log("No answer from the host" .. (sent and "" or " (couldn't send)")
                .. " - their game keeps its own day length (the host doesn't have World Tweaks)")
        end
        return true
    end)
end

-- The host's numbers, on a player who joined
local function OnClientMessage(selfParam, textParam)
    local text = ParamString(textParam)
    local day, night, season = text:match("#WT:([%d%.]+):([%d%.]+):(%-?%d+)%s*$")
    if not day or not Joined() then return end
    day, night, season = tonumber(day), tonumber(night), tonumber(season)
    if not day or not night or day <= 0 or night <= 0 then return end
    hostAnswered = true
    local wm = FindWeatherManager()
    if not wm then return end
    pcall(function()
        wm["Day Length"] = day
        wm["Night Length"] = night
    end)
    local address = AddressOf(wm)
    if season and season >= 0 and address ~= seasonAppliedTo then
        if pcall(function() wm["Toggle Season"](wm, season, 1.0, 0) end) then seasonAppliedTo = address end
    end
    log(string.format("Using the host's day length %.1f, night length %.1f", day, night))
end

-- A joined player asking, on the host
local function OnHostMessage(selfParam, msgParam)
    if ParamString(msgParam) ~= SERVER_TAG then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not Valid(pc) or Joined() then return end
    local isLocal = true
    pcall(function() isLocal = pc:IsLocalController() end)
    if isLocal then return end
    local season = SEASONS[string.lower(Config.season or "")] or -1
    local text = string.format("[WorldTweaks] Host's day length %.1f, night length %.1f #WT:%.1f:%.1f:%d",
        Config.dayLength, Config.nightLength, Config.dayLength, Config.nightLength, season)
    pcall(function() pc:ClientMessage(text, FName("None"), 0.0) end)
end

for path, fn in pairs({
    ["/Script/Engine.PlayerController:ServerNotifyLoadedWorld"] = OnHostMessage,
    ["/Script/Engine.PlayerController:ClientMessage"] = OnClientMessage,
}) do
    if not pcall(RegisterHook, path, fn) then log("Co-op messages unavailable (" .. path .. ")") end
end

------------------------------------------------------------
-- Diagnostics
------------------------------------------------------------

-- Reads a few likely weather-manager settings by name (no property walking:
-- listing this actor's properties crashed this UE4SS build for the mod menu).
local INFO_FIELDS = {
    "Day Length", "Night Length", "Current Time",
    "Season", "Current Season", "Season Length", "Days Per Season", "Season Duration",
    "Day", "Month", "Year", "Current Day", "Current Month", "Days In Month", "Month Length",
}
RegisterConsoleCommandHandler(".worldinfo", function()
    ExecuteInGameThread(function()
        local wm = FindWeatherManager()
        if not wm then log("Weather manager not found - load a world first") return end
        for _, name in ipairs(INFO_FIELDS) do
            local ok, value = pcall(function() return wm[name] end)
            if ok and (type(value) == "number" or type(value) == "boolean") then
                log("  " .. name .. " = " .. tostring(value))
            end
        end
    end)
    return true
end)

-- Writes every setting of every weather preset in DT_Weather, following
-- nested settings groups and lists, to a timestamped weather_dump_*.txt.
-- A dump with Darker Nights installed and one without show exactly which
-- values that pak changes, for building a Lua version of it.
local function PropInfo(prop)
    local name, kind = "?", "?"
    pcall(function() name = prop:GetFName():ToString() end)
    pcall(function() kind = prop:GetClass():GetFName():ToString() end)
    return name, kind
end

local DumpValue
local function DumpStruct(lines, path, structType, value, depth)
    if depth > 6 then lines[#lines + 1] = path .. " = (too deep)" return end
    local ok = pcall(function()
        structType:ForEachProperty(function(prop)
            local name, kind = PropInfo(prop)
            local fieldValue = nil
            pcall(function() fieldValue = value[name] end)
            DumpValue(lines, path .. "." .. name, prop, kind, fieldValue, depth + 1)
        end)
    end)
    if not ok then lines[#lines + 1] = path .. " = (struct, unreadable)" end
end

DumpValue = function(lines, path, prop, kind, value, depth)
    if kind == "FloatProperty" or kind == "DoubleProperty" or kind == "IntProperty"
       or kind == "ByteProperty" or kind == "BoolProperty" or kind == "EnumProperty" then
        lines[#lines + 1] = path .. " = " .. tostring(value)
    elseif kind == "NameProperty" or kind == "StrProperty" or kind == "TextProperty" then
        local s = nil
        pcall(function() s = value:ToString() end)
        lines[#lines + 1] = path .. ' = "' .. tostring(s) .. '"'
    elseif kind == "ObjectProperty" or kind == "SoftObjectProperty" or kind == "ClassProperty" then
        local s = nil
        pcall(function() s = value:GetFullName() end)
        lines[#lines + 1] = path .. " = " .. tostring(s or "None")
    elseif kind == "StructProperty" then
        local structType = nil
        pcall(function() structType = prop:GetStruct() end)
        if structType then
            DumpStruct(lines, path, structType, value, depth)
        else
            lines[#lines + 1] = path .. " = (struct)"
        end
    elseif kind == "ArrayProperty" then
        local inner, innerKind = nil, "?"
        pcall(function() inner = prop:GetInner(); _, innerKind = PropInfo(inner) end)
        local count = 0
        pcall(function()
            value:ForEach(function(index, element)
                count = count + 1
                local item = element
                pcall(function() item = element:get() end)
                DumpValue(lines, path .. "[" .. tostring(index) .. "]", inner, innerKind, item, depth + 1)
            end)
        end)
        lines[#lines + 1] = path .. " (" .. count .. " entries)"
    else
        lines[#lines + 1] = path .. " = (" .. kind .. ")"
    end
end

RegisterConsoleCommandHandler(".weatherdump", function()
    ExecuteInGameThread(function()
        local dt = StaticFindObject(WEATHER_TABLE)
        if not dt or not dt:IsValid() then log("DT_Weather not loaded - load a world first") return end
        local rowStruct = nil
        pcall(function() rowStruct = dt.RowStruct end)
        if not rowStruct then log("DT_Weather has no readable row layout") return end
        local lines = { "# DT_Weather dump by World Tweaks, " .. os.date("%Y-%m-%d %H:%M:%S") }
        local rows = 0
        pcall(function()
            dt:ForEachRow(function(rowName, rowData)
                rows = rows + 1
                DumpStruct(lines, tostring(rowName), rowStruct, rowData, 0)
            end)
        end)
        local path = DUMP_PATH:gsub("%.txt$", "_" .. os.date("%Y%m%d_%H%M%S") .. ".txt")
        local file = io.open(path, "w")
        if not file then log("Could not write " .. path) return end
        file:write(table.concat(lines, "\n") .. "\n")
        file:close()
        log("Wrote " .. rows .. " weather presets (" .. (#lines - 1) .. " values) to " .. path)
    end)
    return true
end)

log("Loaded: day " .. Config.dayLength .. ", night " .. Config.nightLength
    .. (Config.season ~= "" and (", season " .. Config.season) or "")
    .. (Config.nightSkyLight ~= nil and (", night sky " .. Config.nightSkyLight) or ""))
