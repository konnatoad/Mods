-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("MISERY_StructuralFreedom")

ModName, ModVersion = "MISERY Structural Freedom", "1.0.0"

-- MISERY Structural Freedom
-- Relaxes structural-support restrictions while preserving normal placement rules.
-- Does NOT provide arbitrary air placement, noclip building, free costs, or unlimited range.

local registered = {
    grid = false,
    sgk = false,
}

local calls = {
    grid = 0,
    sgk = 0,
}

local installAttempts = 0
local firstFailureLogged = {}

local PLAYER_BUILD_CLASS = "/Game/SurvivalGameKitV2/Components/BP_PlayerBuildingComponent.BP_PlayerBuildingComponent_C"
local MASTER_BUILD_CLASS = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/BP_MasterBuildPart.BP_MasterBuildPart_C"

local FN_SELECT_FLOOR_GRID = PLAYER_BUILD_CLASS .. ":SelectClosestFloorGrid"
local FN_SGK_SUPPORT      = MASTER_BUILD_CLASS .. ":SGK SupportCheck"

local function log(message)
    print(string.format("[%s v%s] %s\n", ModName, ModVersion, message))
end

local function safeGet(param)
    if not param then return nil, false end

    local ok, value = pcall(function()
        return param:get()
    end)

    if not ok then return nil, false end
    return value, true
end

local function safeSet(param, value)
    if not param then return false end

    local ok, err = pcall(function()
        param:set(value)
    end)

    if not ok then
        log("Could not set hook parameter: " .. tostring(err))
        return false
    end

    return true
end

local function allRegistered()
    return registered.grid and registered.sgk
end

local function tryRegister(key, path, callback)
    if registered[key] then return true end

    local ok, preId, postId = pcall(RegisterHook, path, callback)
    if ok and preId ~= nil then
        registered[key] = true
        log("Registered: " .. path)
        return true
    end

    if not firstFailureLogged[key] then
        firstFailureLogged[key] = true
        log("Hook not ready yet: " .. path)
    end

    return false
end

local function installHooks(source)
    if allRegistered() then return true end

    installAttempts = installAttempts + 1

    -- SelectClosestFloorGrid outputs begin with:
    -- ClosestGrid, SupportingGridFound, NonSuppored, Hide
    -- Only convert a real grid found by MISERY that was rejected specifically
    -- because it was considered unsupported. Never invent a placement grid.
    tryRegister("grid", FN_SELECT_FLOOR_GRID,
        function(self, ClosestGrid, SupportingGridFound, NonSuppored, Hide)
            calls.grid = calls.grid + 1

            local unsupportedValue, unsupportedRead = safeGet(NonSuppored)
            if not unsupportedRead or unsupportedValue ~= true then return end

            local grid, gridRead = safeGet(ClosestGrid)
            if not gridRead or not grid then return end

            local gridValid = false
            pcall(function()
                gridValid = grid:IsValid()
            end)

            if gridValid then
                safeSet(SupportingGridFound, true)
                safeSet(NonSuppored, false)
                safeSet(Hide, false)
            end
        end)

    -- BP_MasterBuildPart:SGK SupportCheck signature:
    -- DestroyOnFail, DirectSupportOnly, Supported, IndirectSupportOnly
    tryRegister("sgk", FN_SGK_SUPPORT,
        function(self, DestroyOnFail, DirectSupportOnly, Supported, IndirectSupportOnly)
            calls.sgk = calls.sgk + 1
            safeSet(Supported, true)
            safeSet(IndirectSupportOnly, false)
        end)

    if allRegistered() then
        log(string.format("All Structural Freedom hooks installed from %s. attempts=%d", tostring(source), installAttempts))
        return true
    end

    return false
end

local function statusString()
    return string.format(
        "grid=%s sgk=%s attempts=%d calls(grid=%d,sgk=%d)",
        tostring(registered.grid),
        tostring(registered.sgk),
        installAttempts,
        calls.grid,
        calls.sgk
    )
end

local function statusCommand(FullCommand, Parameters, OutputDevice)
    OutputDevice:Log(ModName .. " v" .. ModVersion .. " | " .. statusString())
    return true
end

local function installCommand(FullCommand, Parameters, OutputDevice)
    installHooks("console")
    OutputDevice:Log(ModName .. " v" .. ModVersion .. " | " .. statusString())
    return true
end

-- Public command names.
RegisterConsoleCommandHandler("structuralfreedomstatus", statusCommand)
RegisterConsoleCommandHandler("structuralfreedominstall", installCommand)

-- Legacy aliases retained for testers upgrading from pre-release FreeBuild builds.
RegisterConsoleCommandHandler("freebuildstatus", statusCommand)
RegisterConsoleCommandHandler("freebuildinstall", installCommand)

log("Starting lifecycle installer...")

-- Install only from UE4SS lifecycle callbacks. No async polling and no
-- temporary ClientRestart hook are used in the public build.
if RegisterLoadMapPostHook then
    RegisterLoadMapPostHook(function(...)
        installHooks("LoadMapPost")
    end)
else
    log("RegisterLoadMapPostHook unavailable; use structuralfreedominstall after loading a save.")
end

if RegisterInitGameStatePostHook then
    RegisterInitGameStatePostHook(function(GameState)
        installHooks("InitGameStatePost")
    end)
else
    log("RegisterInitGameStatePostHook unavailable; LoadMapPost/console fallback remains available.")
end
