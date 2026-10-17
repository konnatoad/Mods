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
local VERSION = "1.1.0"

local function log(msg)
    print("[SoundFixes] " .. tostring(msg) .. "\n")
end

-- Hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local GameHook = require("GameHooks").ForMod("SoundFixes")

local MICROWAVE = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/Furniture/BP_MicrowavePower.BP_MicrowavePower_C"
local FALLOFF = "/Game/SurvivalGameKitV2/Sounds/Attenuation/SA_MediumSmallSound.SA_MediumSmallSound"
-- The microwave's door and start-cooking sounds: played at the microwave but
-- with no falloff of their own, so heard at full volume everywhere (the
-- host's .soundwatch, 17 Oct). They get the falloff on the sound itself.
local NO_FALLOFF_SOUNDS = {
    "/Game/Sounds/SFXrecorded/BuildParts/microwave/MicrowaveOpenSound_Cue.MicrowaveOpenSound_Cue",
    "/Game/Sounds/SFXrecorded/BuildParts/microwave/MicrowaveStartCookSound_Cue.MicrowaveStartCookSound_Cue",
}

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
    -- what it was, once (if it still sounds everywhere, this says why)
    if not logged.before then
        local function get(f) local v = nil pcall(function() v = f() end) return v end
        local att = get(function() return audio.AttenuationSettings end)
        local sound = get(function() return audio.Sound end)
        log(string.format("Microwave turned on: sound %s, falloff was %s, UI sound %s, positioned %s, override %s",
            Valid(sound) and get(function() return sound:GetFName():ToString() end) or "none",
            Valid(att) and get(function() return att:GetFName():ToString() end) or "none",
            tostring(get(function() return audio.bIsUISound end)), tostring(get(function() return audio.bAllowSpatialization end)),
            tostring(get(function() return audio.bOverrideAttenuation end))))
        logged.before = true
    end
    pcall(function() audio.bIsUISound = false end)
    pcall(function() audio.bAllowSpatialization = true end)
    pcall(function() audio.bOverrideAttenuation = false end)
    pcall(function() audio.AttenuationSettings = falloff end)
    LogOnce("fixed", "Microwave sound now comes from the microwave and fades with distance")
end

-- Gives each sound without a falloff the falloff, once it has loaded (a name
-- look-up). Returns true when all of them are done
local soundsFixed = {}
local function FixSounds()
    local falloff, all = nil, true
    for _, path in ipairs(NO_FALLOFF_SOUNDS) do
        if not soundsFixed[path] then
            local sound = Find(path)
            if not sound then
                all = false
            else
                falloff = falloff or Falloff()
                if not falloff then return false end
                local had, override = nil, nil
                pcall(function() had = sound.AttenuationSettings end)
                pcall(function() override = sound.bOverrideAttenuation end)
                if Valid(had) or override == true then
                    log(path:match("%.([%w_]+)$") .. " already has a falloff - left alone")
                elseif pcall(function() sound.AttenuationSettings = falloff end) then
                    log(path:match("%.([%w_]+)$") .. " now fades with distance (it was heard everywhere)")
                else
                    log("Couldn't give " .. path:match("%.([%w_]+)$") .. " a falloff")
                end
                soundsFixed[path] = true
            end
        end
    end
    return all
end

-- The microwave's class only exists once a microwave has loaded (later than
-- the world's start: 1.0.0 looked only then and never hooked). Looked for
-- every 5 s until it's there - a name look-up, not a search.
local hooked, tried = false, false
local function Hook()
    if hooked or tried or not Find(MICROWAVE) then return end
    tried = true   -- one try once the class is there (no retry spam if it fails)
    local any = false
    for _, fn in ipairs({ "MulticastTurnedOnEffect", "SGK TurnedOnEffect" }) do
        if pcall(GameHook, MICROWAVE .. ":" .. fn, FixMicrowave) then any = true end
    end
    hooked = any
    log(any and "Watching microwaves" or "Couldn't watch microwaves turning on - their sound is unchanged")
end

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteInGameThread(function() pcall(Hook) end)
    end)
end)
local soundsDone = false
ExecuteInGameThread(function() pcall(Hook) soundsDone = FixSounds() end)
LoopAsync(5000, function()
    if (hooked or tried) and soundsDone then return true end
    ExecuteInGameThread(function()
        pcall(Hook)
        local ok, done = pcall(FixSounds)
        soundsDone = ok and done
    end)
    return false
end)

------------------------------------------------------------
-- .soundwatch: for a minute, every sound the game starts through its
-- "play a sound" functions goes to the log with what started it, and whether
-- it's heard everywhere (2D) or from a place. For finding a sound heard where
-- it shouldn't be: run it, make the sound happen, read the log.
-- (1.0.1's microwave fix showed the microwave's own sound already fades
-- with distance: on the host something else is heard everywhere)
------------------------------------------------------------
local STATICS = "/Script/Engine.GameplayStatics:"
-- function = { where the sound is among the hook's values, where it comes from, how it's heard }
local SOUND_CALLS = {
    PlaySound2D = { sound = 2, from = 1, heard = "EVERYWHERE (2D)" },
    SpawnSound2D = { sound = 2, from = 1, heard = "EVERYWHERE (2D)" },
    PlaySoundAtLocation = { sound = 2, from = 1, heard = "from a place", att = 8 },
    SpawnSoundAtLocation = { sound = 2, from = 1, heard = "from a place", att = 8 },
    SpawnSoundAttached = { sound = 1, from = 2, heard = "attached", att = 11 },
}
local watch = { untilClock = 0, ids = {}, count = 0 }

local function NameOfParam(p)
    local obj = nil
    pcall(function() obj = p:get() end)
    if not Valid(obj) then return "none" end
    local name = "?"
    pcall(function() name = obj:GetFName():ToString() end)
    local owner = nil
    pcall(function() owner = obj:GetOwner() end)
    if Valid(owner) then
        pcall(function() name = name .. " of " .. owner:GetFName():ToString() end)
    end
    return name
end

local function StopWatch()
    for path, id in pairs(watch.ids) do pcall(UnregisterHook, path, id[1], id[2]) end
    watch.ids = {}
    log("Sound watch off (" .. watch.count .. " sounds logged)")
end

local function StartWatch()
    if next(watch.ids) then log("Sound watch is already on") return end
    watch.untilClock, watch.count = os.clock() + 60, 0
    for fn, how in pairs(SOUND_CALLS) do
        local path = STATICS .. fn
        local ok, pre, post = pcall(RegisterHook, path, function(_, ...)
            if os.clock() > watch.untilClock then return end
            local args = { ... }
            watch.count = watch.count + 1
            if watch.count > 200 then return end
            local att = how.att and args[how.att] and NameOfParam(args[how.att]) or "-"
            log(string.format("sound %s, %s, by %s, falloff %s (%s)", NameOfParam(args[how.sound]), how.heard,
                NameOfParam(args[how.from]), att, fn))
        end)
        if ok then watch.ids[path] = { pre, post } end
    end
    log("Sound watch on for 60 s: make the sound happen now (.soundwatch again stops it)")
    LoopAsync(61000, function()
        ExecuteInGameThread(function() if next(watch.ids) then StopWatch() end end)
        return true
    end)
end

RegisterConsoleCommandHandler(".soundwatch", function()
    ExecuteInGameThread(function()
        if next(watch.ids) then StopWatch() else StartWatch() end
    end)
    return true
end)

log("Loaded v" .. VERSION .. " (.soundwatch logs the sounds the game starts, for a minute)")
