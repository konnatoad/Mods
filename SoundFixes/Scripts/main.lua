------------------------------------------------------------
-- Sound Fixes
------------------------------------------------------------
-- Game sounds that are heard where they shouldn't be.
--
-- Microwave: in co-op, when a joined player turns a microwave on, the host
-- hears it at full volume wherever they are. The microwave's on/off effect
-- (MulticastTurnedOnEffect) runs on every player's game and plays the
-- microwave's Audio component, and on the host that sound has no distance
-- falloff. Just before the effect runs, the Audio component gets the game's
-- own falloff for small sounds (SA_MediumSmallSound) and is made a sound in
-- the world (not a UI sound), so it comes from the microwave and fades with
-- distance. Only an object setting is written, nothing else.
--
-- Each player's copy fixes what that player hears: the host needs it for the
-- host's ears.
------------------------------------------------------------
local VERSION = "1.0.0"

local function log(msg)
    print("[SoundFixes] " .. tostring(msg) .. "\n")
end

-- Hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local GameHook = require("GameHooks").ForMod("SoundFixes")

local MICROWAVE = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/Furniture/BP_MicrowavePower.BP_MicrowavePower_C"
local FALLOFF = "/Game/SurvivalGameKitV2/Sounds/Attenuation/SA_MediumSmallSound.SA_MediumSmallSound"

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function Find(path)
    local obj = nil
    pcall(function() obj = StaticFindObject(path) end)
    return Valid(obj) and obj or nil
end

local function Falloff()
    local found = Find(FALLOFF)
    if found then return found end
    pcall(function() LoadAsset(FALLOFF) end)
    return Find(FALLOFF)
end

local logged = {}
local function LogOnce(key, msg)
    if logged[key] then return end
    logged[key] = true
    log(msg)
end

-- Gives a microwave's sound the falloff, before it plays
local function FixMicrowave(selfParam)
    local microwave, audio = nil, nil
    pcall(function() microwave = selfParam:get() end)
    if not Valid(microwave) then return end
    pcall(function() audio = microwave.Audio end)
    if not Valid(audio) then LogOnce("noaudio", "Microwave: no sound component found - not changed") return end
    local falloff = Falloff()
    if not falloff then LogOnce("nofalloff", "Microwave: the game's falloff (" .. FALLOFF .. ") isn't there - not changed") return end
    pcall(function() audio.bIsUISound = false end)
    pcall(function() audio.bAllowSpatialization = true end)
    pcall(function() audio.bOverrideAttenuation = false end)
    pcall(function() audio.AttenuationSettings = falloff end)
    LogOnce("fixed", "Microwave sound now comes from the microwave and fades with distance")
end

-- The microwave's class is there once a level with one has loaded: hooked then
local hooked = false
local function Hook()
    if hooked or not Find(MICROWAVE) then return end
    local any = false
    for _, fn in ipairs({ "MulticastTurnedOnEffect", "SGK TurnedOnEffect" }) do
        if pcall(GameHook, MICROWAVE .. ":" .. fn, FixMicrowave) then any = true end
    end
    hooked = any
    if not any then log("Couldn't watch microwaves turning on - their sound is unchanged") end
end

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteInGameThread(function() pcall(Hook) end)
    end)
end)
ExecuteInGameThread(function() pcall(Hook) end)

log("Loaded v" .. VERSION)
