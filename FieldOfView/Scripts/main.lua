------------------------------------------------------------
-- Field Of View
------------------------------------------------------------
-- `.fov 95` sets the field of view in degrees (60-120). Saved to
-- settings.txt; `.fov reset` goes back to the game's own.
--
-- The view comes from the camera on your character. The game's normal field
-- of view is remembered the first time it's seen. Every field of view the
-- game then gives that camera is scaled by yours / the game's: the normal
-- view becomes yours, and aiming zooms in smoothly from yours (by the same
-- proportion as before) instead of jumping back to the game's view first.
-- A 1 s check puts the view back if the game sets it some other way.
-- If it doesn't change, `.fov scan` lists the cameras and field-of-view
-- settings it found, for the log.
--
-- Only your own view changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.1.0"
local SETTINGS_PATH = "./ue4ss/Mods/FieldOfView/settings.txt"
local MIN_FOV, MAX_FOV = 60, 120
local CHECK_EVERY_MS = 1000

local fov = nil           -- nil = the game's own
local base = nil          -- the game's normal field of view (seen on the camera)
local controller = nil    -- kept while valid: finding it walks every object
local camera, cameraOf = nil, nil
local loopRunning = false
local reported = false
local ownCall = false     -- this mod setting the view: not scaled again
local scaledCalls = 0     -- the game's field-of-view changes scaled so far

local function log(msg)
    print("[FieldOfView] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local text = file:read("a") or ""
    file:close()
    local value = tonumber(text:match("fov%s*=%s*(%d+)"))
    if value then fov = math.max(MIN_FOV, math.min(MAX_FOV, value)) end
    -- the game's own, as first seen: after .reloadmods the camera already
    -- shows ours, so it can't be read from there again
    base = tonumber(text:match("game%s*=%s*([%d%.]+)"))
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write(fov and ("fov=" .. fov .. "\n") or "fov=game\n")
    if base then file:write(string.format("game=%.2f\n", base)) end
    file:close()
end

------------------------------------------------------------
-- The camera
------------------------------------------------------------
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

-- Normally handed over by the ClientRestart hook. Searching walks every
-- object in the game, so the search (after .reloadmods, or at the main
-- menu where there is none) runs at most every 10 s.
local lastSearch = -100
local function Controller()
    if Valid(controller) then return controller end
    controller = nil
    if os.time() - lastSearch < 10 then return nil end
    lastSearch = os.time()
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(ctrl) and ctrl:IsLocalController() then controller = ctrl return end
        end
    end)
    return controller
end

local function Character()
    local ctrl = Controller()
    if not ctrl then return nil end
    local character = nil
    pcall(function() character = ctrl.Character end)   -- none while dead or loading
    return Valid(character) and character or nil
end

-- The character's camera, kept until the character changes
local function Camera()
    local character = Character()
    if not character then return nil, nil end
    if Valid(camera) and cameraOf == character then return camera, character end
    camera, cameraOf = nil, character
    pcall(function()
        local cls = StaticFindObject("/Script/Engine.CameraComponent")
        local found = character:GetComponentByClass(cls)
        if Valid(found) then camera = found end
    end)
    return camera, character
end

local function ReadFov(cam)
    local ok, value = pcall(function() return cam.FieldOfView end)
    return ok and type(value) == "number" and value or nil
end

local function SetFov(cam, value)
    ownCall = true
    if not pcall(function() cam:SetFieldOfView(value) end) then
        pcall(function() cam.FieldOfView = value end)
    end
    ownCall = false
end

local function AddressOf(obj)
    local ok, address = pcall(function() return obj:GetAddress() end)
    return ok and address or nil
end

-- The character's own number settings with "fov" or "fieldofview" in the
-- name. Only the character class's own variables: walking parent classes
-- crashed this UE4SS build for the mod menu.
local function FovSettings(character)
    local found = {}
    pcall(function()
        character:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            local lower = name:lower()
            if lower:find("fov", 1, true) or lower:find("fieldofview", 1, true) then
                local value = nil
                pcall(function() value = character[name] end)
                table.insert(found, { name = name, value = value })
            end
        end)
    end)
    return found
end

local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.05 end

-- Game thread. Puts the view at our field of view when it's at the normal one.
local function Apply()
    local cam, character = Camera()
    if not cam then return false end
    local now = ReadFov(cam)
    if not now then return false end
    if not base then
        base = now
        log(string.format("The game's field of view: %.0f", base))
        Save()
    end
    if fov == nil or Near(now, fov) then return true end
    -- back at the game's normal view: ours instead. Anything else is aiming
    -- (or the like) and left alone.
    if Near(now, base) then
        SetFov(cam, fov)
        if not reported then
            reported = true
            log(string.format("Field of view %d", fov))
        end
    end
    return true
end

local function StartLoop()
    if loopRunning then return end
    loopRunning = true
    LoopAsync(CHECK_EVERY_MS, function()
        ExecuteInGameThread(function() pcall(Apply) end)
        return false
    end)
end

-- Every field of view the game gives our camera (the normal one, each step
-- of the aiming zoom), scaled by ours / the game's before it's applied
local hooked = pcall(RegisterHook, "/Script/Engine.CameraComponent:SetFieldOfView", function(selfParam, fovParam)
    if ownCall or not fov or not base then return end
    pcall(function()
        local cam = selfParam:get()
        local mine = Camera()
        if not mine or AddressOf(mine) ~= AddressOf(cam) then return end   -- another camera
        local value = fovParam:get()
        if type(value) ~= "number" then return end
        fovParam:set(value * fov / base)
        scaledCalls = scaledCalls + 1
        if scaledCalls == 1 then log("The game changed the view: scaled to yours, aiming follows it") end
    end)
end)

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(selfParam)
    camera, cameraOf, reported = nil, nil, false   -- a new character (respawn, level)
    pcall(function()
        local pc = selfParam:get()
        if Valid(pc) and pc:IsLocalController() then controller = pc end
    end)
end)

------------------------------------------------------------
-- Scan: what the camera is
------------------------------------------------------------
local function Scan()
    local cam, character = Camera()
    if not character then log("Scan: no character yet - load into a world first") return end
    log("Scan: character " .. NameOf(character:GetClass()))
    pcall(function()
        local cls = StaticFindObject("/Script/Engine.CameraComponent")
        character:K2_GetComponentsByClass(cls):ForEach(function(_, element)
            local comp = element:get()
            log(string.format("  camera %s: field of view %s", NameOf(comp), tostring(ReadFov(comp))))
        end)
    end)
    if not cam then log("  no camera found on the character") end
    log(string.format("Scan: the game changed the view %d time(s) since loading, all scaled%s", scaledCalls,
        hooked and "" or " (couldn't watch it: aiming may jump)"))
    local settings = FovSettings(character)
    log("Scan: " .. #settings .. " character setting(s) named like a field of view:")
    for _, s in ipairs(settings) do log("  " .. s.name .. " = " .. tostring(s.value)) end
    local manager = nil
    pcall(function() manager = Controller().PlayerCameraManager end)
    if Valid(manager) then
        pcall(function() log("  camera manager: default " .. tostring(manager.DefaultFOV)
            .. ", locked " .. tostring(manager.LockedFOV)) end)
    end
    log("Send these lines if .fov doesn't change the view")
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
local function Status()
    log((fov and string.format("Field of view %d", fov) or "The game's field of view")
        .. (base and string.format(" (the game's: %.0f)", base) or "")
        .. ". .fov <" .. MIN_FOV .. "-" .. MAX_FOV .. "> | .fov reset | .fov scan")
end

RegisterConsoleCommandHandler(".fov", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        elseif a == "reset" or tonumber(a) then
            local old = fov or base
            fov = a ~= "reset" and math.max(MIN_FOV, math.min(MAX_FOV, math.floor(tonumber(a) + 0.5))) or nil
            Save()
            local cam = Camera()
            local now = cam and ReadFov(cam)
            if now and base then
                -- straight away, in proportion (mid-aim stays zoomed)
                SetFov(cam, now * (fov or base) / old)
                log(fov and string.format("Field of view %d", fov) or string.format("The game's field of view (%.0f)", base))
            else
                log((fov and string.format("Field of view %d", fov) or "The game's field of view")
                    .. " (saved) - it applies once you're in a world")
            end
            reported = true
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
