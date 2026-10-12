------------------------------------------------------------
-- Field Of View
------------------------------------------------------------
-- `.fov 120` sets the field of view in degrees (60-130), past the game's own
-- slider (80-110). Saved to settings.txt; `.fov reset` gives the slider back.
--
-- The game keeps its field of view in its settings (the slider's value,
-- GameSettings.CameraFov of BP_SGKSettingsSaveData), and its normal view,
-- sprinting and aiming are all worked out from it. The mod sets that value,
-- so the game does everything itself from yours: nothing fights it.
-- Your character's BP_CharacterComponent keeps its own default from when it
-- spawned, and the sprint zoom ends back at it; the game updates it (with
-- SetDefaultCameraFOV) when you leave the Settings menu. The mod calls that
-- too, right after changing the setting, and number variables named like a
-- field of view on the character and that component which still hold an old
-- value follow as well.
-- The slider's own value is remembered (settings.txt) and put back by
-- `.fov reset`. While the mod is on, it keeps the setting at yours, also if
-- the options menu moves it.
--
-- Only your own game's setting changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.5.0"
local SETTINGS_PATH = "./ue4ss/Mods/FieldOfView/settings.txt"
local MIN_FOV, MAX_FOV = 60, 130
local SLIDER_MIN, SLIDER_MAX = 80, 110   -- the game's own slider
local CHECK_EVERY_MS = 1000
local SETTINGS_CLASS = "BP_SGKSettingsSaveData_C"
local FOV_FIELD = "CameraFov_17_5654B301488C06351C9D9C9FC76A7110"   -- in GameSettings

local fov = nil           -- nil = the game's own (the slider)
local slider = nil        -- the slider's value before the mod changed it
local controller = nil    -- kept while valid: finding it walks every object
local settings = nil      -- the game's settings object, kept while valid
local loopRunning = false
local reportedMissing = false
local written = nil       -- the last value the mod put in the setting
local old = {}            -- every normal field of view there has been (slider, ours): copies holding one follow
local fovNames = {}       -- per character class: its variables named like a field of view

local function log(msg)
    print("[FieldOfView] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Our settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local text = file:read("a") or ""
    file:close()
    local value = tonumber(text:match("fov%s*=%s*(%d+)"))
    if value then fov = math.max(MIN_FOV, math.min(MAX_FOV, value)) end
    local s = tonumber(text:match("slider%s*=%s*([%d%.]+)"))
    if s and s >= SLIDER_MIN and s <= SLIDER_MAX then slider = s end
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write(fov and ("fov=" .. fov .. "\n") or "fov=game\n")
    if slider then file:write(string.format("slider=%g\n", slider)) end
    file:close()
end

------------------------------------------------------------
-- The game
------------------------------------------------------------
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.05 end

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

-- Searching walks every object in the game, so each search below runs at
-- most every 10 s while there's nothing to find.
local lastSearch = { controller = -100, settings = -100 }

local function Controller()
    if Valid(controller) then return controller end
    controller = nil
    if os.time() - lastSearch.controller < 10 then return nil end
    lastSearch.controller = os.time()
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(ctrl) and ctrl:IsLocalController() then controller = ctrl return end
        end
    end)
    return controller
end

local function Settings()
    if Valid(settings) then return settings end
    settings = nil
    if os.time() - lastSearch.settings < 10 then return nil end
    lastSearch.settings = os.time()
    pcall(function()
        for _, obj in ipairs(FindAllOf(SETTINGS_CLASS) or {}) do
            if Valid(obj) and not NameOf(obj):find("^Default__") then settings = obj return end
        end
    end)
    return settings
end

local function ReadSetting(obj)
    local ok, value = pcall(function() return obj.GameSettings[FOV_FIELD] end)
    return ok and type(value) == "number" and value or nil
end

local function WriteSetting(obj, value)
    return pcall(function() obj.GameSettings[FOV_FIELD] = value end)
end

-- The camera on your character right now (to show the change at once,
-- rather than when the game next applies its settings)
local function Camera()
    local ctrl = Controller()
    local camera = nil
    pcall(function()
        local character = ctrl.Character
        if Valid(character) then
            local found = character:GetComponentByClass(StaticFindObject("/Script/Engine.CameraComponent"))
            if Valid(found) then camera = found end
        end
    end)
    return camera
end

-- The character's own variables with "fov" in the name (not aiming or
-- zoom ones). Only the class's own: walking parent classes crashed this UE4SS
-- build for the mod menu. Listed once per class.
local function FovNames(obj)
    if not obj then return {} end
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    local key = cls and NameOf(cls) or "?"
    if fovNames[key] then return fovNames[key] end
    local names = {}
    pcall(function()
        cls:ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            local lower = name:lower()
            if (lower:find("fov", 1, true) or lower:find("fieldofview", 1, true))
               and not (lower:find("aim", 1, true) or lower:find("ads", 1, true) or lower:find("zoom", 1, true)
                        or lower:find("sprint", 1, true) or lower:find("run", 1, true)) then
                table.insert(names, name)
            end
        end)
    end)
    fovNames[key] = names
    return names
end

local COMPONENT_CLASS = "/Game/SurvivalGameKitV2/Components/BP_CharacterComponent.BP_CharacterComponent_C"
local SET_DEFAULT = COMPONENT_CLASS .. ":SetDefaultCameraFOV"

local function Character()
    local character = nil
    pcall(function() character = Controller().Character end)
    return Valid(character) and character or nil
end

local function Component(character)
    local comp = nil
    pcall(function()
        local found = character:GetComponentByClass(StaticFindObject(COMPONENT_CLASS))
        if Valid(found) then comp = found end
    end)
    return comp
end

-- The game's SetDefaultCameraFOV: its parameters, so it's called the way it
-- expects (no guessing what a missing value would become). nil = not usable.
local setDefaultParams = false
local function SetDefaultParams()
    if setDefaultParams ~= false then return setDefaultParams end
    setDefaultParams = nil
    pcall(function()
        local fn = StaticFindObject(SET_DEFAULT)
        if not Valid(fn) then return end
        local params = {}
        fn:ForEachProperty(function(prop)
            local isParam = false
            pcall(function() isParam = prop:HasAnyPropertyFlags(0x80) end)   -- CPF_Parm
            if isParam then
                local kind = ""
                pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                table.insert(params, kind)
            end
        end)
        setDefaultParams = params
    end)
    return setDefaultParams
end

-- What the Settings menu does when you leave it: the character's default
-- field of view from the setting
local reportedDefault = false
local function ApplyToCharacter(want)
    local comp = Component(Character())
    local params = SetDefaultParams()
    if not comp or not params then return false end
    local ok, err = false, nil
    if #params == 0 then
        ok, err = pcall(function() comp:SetDefaultCameraFOV() end)
    elseif #params == 1 and (params[1] == "DoubleProperty" or params[1] == "FloatProperty") then
        ok, err = pcall(function() comp:SetDefaultCameraFOV(want) end)
    else
        err = "it takes " .. table.concat(params, ", ")
    end
    if not reportedDefault then
        reportedDefault = true
        log(ok and "Applied to your character (as leaving the Settings menu does)"
            or ("Couldn't apply it to your character (" .. tostring(err) .. "): open Settings and go back once"))
    end
    return ok
end

-- Copies of the setting on the character and its component that still hold
-- an old value (the slider's, or one the mod set before) -> the value we want
local reportedCopies = {}
local function FollowCopies(want)
    local character = Character()
    if not character then return end
    for _, obj in ipairs({ character, Component(character) }) do
        for _, name in ipairs(FovNames(obj)) do
            local value = nil
            pcall(function() value = obj[name] end)
            local stale = Near(value, slider)
            for v in pairs(old) do if Near(value, v) then stale = true end end
            -- only a copy of an old normal view: never one mid-sprint or mid-aim
            if type(value) == "number" and not Near(value, want) and stale then
                if pcall(function() obj[name] = want end) and not reportedCopies[name] then
                    reportedCopies[name] = true
                    log(string.format("  %s: %g -> %g", name, value, want))
                end
            end
        end
    end
end

-- Game thread. The setting at ours (and the slider's own value remembered).
local function Ensure()
    local obj = Settings()
    if not obj then return end
    local now = ReadSetting(obj)
    if not now then
        if not reportedMissing then
            reportedMissing = true
            log("The game's field-of-view setting wasn't found - a game update may have renamed it. Run .fov scan")
        end
        return
    end
    -- the slider's own value: anything the slider can be set to that the
    -- mod didn't put there
    -- (once the mod has set it this session, a change can only be the menu;
    -- before that, a value from an earlier session isn't taken for the slider)
    if now >= SLIDER_MIN and now <= SLIDER_MAX and not Near(now, fov) and not Near(now, slider)
       and not Near(now, written) and (slider == nil or written ~= nil) then
        slider = now
        Save()
    end
    local want = fov or slider
    if not want then return end
    old[now] = true
    if slider then old[slider] = true end
    FollowCopies(want)
    if Near(now, want) then return end
    if WriteSetting(obj, want) then
        written = want
        ApplyToCharacter(want)
        local cam = Camera()
        -- at the old normal view (not aiming): show the new one straight away
        if cam then
            local camFov = nil
            pcall(function() camFov = cam.FieldOfView end)
            if Near(camFov, now) then pcall(function() cam:SetFieldOfView(want) end) end
        end
        log(fov and string.format("Field of view %d (the game's slider: %s)", fov, slider and string.format("%g", slider) or "?")
            or string.format("The game's field of view: %g (the slider)", want))
    end
end

local function StartLoop()
    if loopRunning then return end
    loopRunning = true
    LoopAsync(CHECK_EVERY_MS, function()
        ExecuteInGameThread(function() pcall(Ensure) end)
        return false
    end)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(selfParam)
    pcall(function()
        local pc = selfParam:get()
        if Valid(pc) and pc:IsLocalController() then controller = pc end
    end)
end)

------------------------------------------------------------
-- Scan
------------------------------------------------------------
local WORDS = { "fov", "fieldofview", "zoom", "aim", "ads", "sprint" }

local function Matches(name)
    local lower = name:lower()
    for _, w in ipairs(WORDS) do if lower:find(w, 1, true) then return true end end
    return false
end

local function NumberSettings(obj)
    local found = {}
    pcall(function()
        obj:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            if Matches(name) then
                local value = nil
                pcall(function() value = obj[name] end)
                if type(value) == "number" or type(value) == "boolean" then
                    table.insert(found, name .. " = " .. tostring(value))
                end
            end
        end)
    end)
    return found
end

local function Scan()
    lastSearch.settings = -100
    local obj = Settings()
    log("Scan: settings object " .. (obj and NameOf(obj) or "not found")
        .. ", field of view setting " .. tostring(obj and ReadSetting(obj)))
    local cam = Camera()
    local camFov = nil
    pcall(function() camFov = cam.FieldOfView end)
    log("Scan: camera " .. (cam and NameOf(cam) or "none") .. " at " .. tostring(camFov))
    local character = nil
    pcall(function() character = Controller().Character end)
    if Valid(character) then
        for _, line in ipairs(NumberSettings(character)) do log("  character " .. line) end
    end
    local comp = Component(Character())
    local params = SetDefaultParams()
    log("Scan: character component " .. (comp and NameOf(comp) or "not found") .. ", SetDefaultCameraFOV "
        .. (params and ("takes (" .. table.concat(params, ", ") .. ")") or "not found"))
    if comp then for _, line in ipairs(NumberSettings(comp)) do log("  component " .. line) end end
    log("Send these lines if .fov doesn't work")
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
local function Status()
    log((fov and string.format("Field of view %d", fov) or "The game's field of view (the slider)")
        .. (slider and string.format("; the slider is at %g", slider) or "")
        .. ". .fov <" .. MIN_FOV .. "-" .. MAX_FOV .. "> | .fov reset | .fov scan")
end

RegisterConsoleCommandHandler(".fov", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        elseif a == "reset" or tonumber(a) then
            fov = a ~= "reset" and math.max(MIN_FOV, math.min(MAX_FOV, math.floor(tonumber(a) + 0.5))) or nil
            Save()
            lastSearch.settings = -100   -- look now if it wasn't found yet
            pcall(Ensure)
            if not Settings() then
                log((fov and string.format("Field of view %d", fov) or "The game's field of view")
                    .. " (saved) - it applies once the game's settings are loaded")
            elseif not fov and not slider then
                log("The game's field of view (the slider)")
            end
        else
            Status()
        end
    end)
    return true
end)

Load()
StartLoop()
log("Loaded v" .. VERSION .. ": " .. (fov and ("field of view " .. fov) or "the game's field of view")
    .. ". .fov <degrees> to change it")
