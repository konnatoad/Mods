------------------------------------------------------------
-- Field Of View
------------------------------------------------------------
-- `.fov 95` sets the field of view in degrees (60-120). Saved to
-- settings.txt; `.fov reset` goes back to the game's own.
--
-- The game's camera is left alone. The mod adds a camera modifier, a part of
-- Unreal's camera that adjusts the final view every frame after the game has
-- set it, and scales the field of view there by yours / the game's normal
-- one. Sprinting, aiming and anything else the game does to the view still
-- happen exactly as the game does them, just from your field of view: the
-- game's zooms never see the change, so nothing fights it and nothing jumps.
-- The game's normal field of view is read from your character's camera when
-- you spawn.
-- If it doesn't change, `.fov scan` lists the cameras and field-of-view
-- settings it found, for the log.
--
-- Only your own view changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.2.0"
local SETTINGS_PATH = "./ue4ss/Mods/FieldOfView/settings.txt"
local MIN_FOV, MAX_FOV = 60, 120
local CHECK_EVERY_MS = 1000

local fov = nil           -- nil = the game's own
local base = nil          -- the game's normal field of view (read from the camera)
local baseOf = nil        -- the character it was read from
local seen = {}           -- how often each of the camera's values was seen
local controller = nil    -- kept while valid: finding it walks every object
local modifier, modifierAddress, modifierOf = nil, nil, nil
local frames = 0          -- frames whose view was scaled
local pending = nil       -- this frame's field of view, from the hook's start to its end
local loopRunning = false
local warned = false

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
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write(fov and ("fov=" .. fov .. "\n") or "fov=game\n")
    file:close()
end

------------------------------------------------------------
-- The player
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

local function AddressOf(obj)
    local ok, address = pcall(function() return obj:GetAddress() end)
    return ok and address or nil
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

local function Camera(character)
    local camera = nil
    pcall(function()
        local found = character:GetComponentByClass(StaticFindObject("/Script/Engine.CameraComponent"))
        if Valid(found) then camera = found end
    end)
    return camera
end

local function ReadFov(cam)
    local ok, value = pcall(function() return cam.FieldOfView end)
    return ok and type(value) == "number" and value > 0 and value or nil
end

-- The character's own number settings with "fov" or "fieldofview" in the
-- name (for .fov scan). Only the character class's own variables: walking
-- parent classes crashed this UE4SS build for the mod menu.
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

------------------------------------------------------------
-- The camera modifier
------------------------------------------------------------
local function Ratio()
    if not fov or not base then return nil end
    return fov / base
end

-- Every frame, after the game has set the view: our field of view instead.
-- Both the incoming and the outgoing value are set, so it works whether or
-- not the engine copies one to the other.
local function OnModify(selfParam, deltaParam, locParam, rotParam, fovParam, newLocParam, newRotParam, newFovParam)
    local ratio = Ratio()
    if not ratio or not modifierAddress then return end
    local mine = false
    pcall(function() mine = AddressOf(selfParam:get()) == modifierAddress end)
    if not mine then return end
    pending = nil
    pcall(function()
        local value = fovParam:get()
        if type(value) ~= "number" then return end
        pending = value * ratio
        fovParam:set(pending)
        newFovParam:set(pending)
        frames = frames + 1
    end)
end

local hooked = pcall(RegisterHook, "/Script/Engine.CameraModifier:BlueprintModifyCamera", OnModify,
    function(selfParam, deltaParam, locParam, rotParam, fovParam, newLocParam, newRotParam, newFovParam)
        -- after: in case the engine's own copy wrote the game's value back
        if not pending then return end
        local value = pending
        pending = nil
        pcall(function() newFovParam:set(value) end)
    end)
if not hooked then log("Couldn't watch the camera - .fov can't change the view in this game version") end

-- Game thread. The modifier on our camera manager, and the game's normal
-- field of view for the current character.
local function Ensure()
    local ctrl = Controller()
    local character = Character()
    if not ctrl or not character then return end
    -- The game's normal field of view: the camera's own value seen most often
    -- (sprinting and aiming change it only for a moment). Counted per character.
    if baseOf ~= AddressOf(character) then
        baseOf, seen = AddressOf(character), {}
    end
    local value = ReadFov(Camera(character))
    if value then
        local key = math.floor(value * 10 + 0.5) / 10
        seen[key] = (seen[key] or 0) + 1
        if not base or (seen[key] > (seen[base] or 0) and key ~= base) then
            local first = base == nil
            base = key
            if first or seen[key] > 3 then log(string.format("The game's field of view: %.0f", base)) end
        end
    end
    if not fov then return end
    local manager = nil
    pcall(function() manager = ctrl.PlayerCameraManager end)
    if not Valid(manager) then return end
    if Valid(modifier) and modifierOf == AddressOf(manager) then return end
    modifier, modifierAddress = nil, nil
    pcall(function()
        local added = manager:AddNewCameraModifier(StaticFindObject("/Script/Engine.CameraModifier"))
        if Valid(added) then modifier, modifierAddress, modifierOf = added, AddressOf(added), AddressOf(manager) end
    end)
    if modifier then
        log(string.format("Field of view %d", fov))
    elseif not warned then
        warned = true
        log("Couldn't add to the camera - send .fov scan's lines")
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
local function Scan()
    local character = Character()
    if not character then log("Scan: no character yet - load into a world first") return end
    log("Scan: character " .. NameOf(character:GetClass()))
    pcall(function()
        character:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.CameraComponent")):ForEach(function(_, element)
            local comp = element:get()
            log(string.format("  camera %s: field of view %s", NameOf(comp), tostring(ReadFov(comp))))
        end)
    end)
    log(string.format("Scan: watching the camera %s, modifier %s, %d frame(s) scaled so far",
        hooked and "yes" or "NO", Valid(modifier) and "added" or "none", frames))
    for _, s in ipairs(FovSettings(character)) do log("  " .. s.name .. " = " .. tostring(s.value)) end
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
            fov = a ~= "reset" and math.max(MIN_FOV, math.min(MAX_FOV, math.floor(tonumber(a) + 0.5))) or nil
            Save()
            pcall(Ensure)
            if not fov then
                log("The game's field of view" .. (base and string.format(" (%.0f)", base) or ""))
            elseif not modifier then
                log(string.format("Field of view %d (saved) - it applies once you're in a world", fov))
            elseif base then
                log(string.format("Field of view %d", fov))
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
