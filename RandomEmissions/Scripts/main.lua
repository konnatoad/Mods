------------------------------------------------------------
-- Random Emissions Config
------------------------------------------------------------
-- Minimum random time in seconds until emission
-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("RandomEmissions")

local randomMin = 1800
-- Maximum random time in seconds until emission
local randomMax = 3600
-- Plays the siren warning sound before
local isSirenEnabled = true
-- Minimum random time in seconds left until siren
local sirenMin = 120
-- Maximum random time in seconds left until siren. The siren is 2 minutes
-- long: started up to 5 minutes before (1.2.6 and older), it ended long
-- before the emission and felt like a false alarm
local sirenMax = 150
-- Volume of siren
local sirenVolume = 3.0
----------------------------------

-- Co-op: the host's game runs the emissions, so only the host's copy picks
-- the random times. When the host's siren starts, players who joined are told
-- (a line in their console) and their copy plays the siren too. In someone
-- else's world this mod never changes the timer or plays the siren by itself.

local UEHelpers = require("UEHelpers")

-- Your own settings go in RandomEmissions\config.lua (start from config.example.lua),
-- not in this file, so `git pull` can always update the mod. config.lua
-- returns a table; anything it sets replaces the value here.
local function UserConfig()
    local path = "./ue4ss/Mods/RandomEmissions/config.lua"
    local file = io.open(path, "r")
    if not file then return {} end
    file:close()
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then return result end
    print("[RandomEmissions] config.lua ignored: " .. (ok and "it doesn't return a table" or tostring(result)) .. "\n")
    return {}
end

do
    local user = UserConfig()
    local function number(v, default) return type(v) == "number" and v or default end
    randomMin = number(user.randomMin, randomMin)
    randomMax = math.max(randomMin, number(user.randomMax, randomMax))
    if type(user.isSirenEnabled) == "boolean" then isSirenEnabled = user.isSirenEnabled end
    sirenMin = number(user.sirenMin, sirenMin)
    sirenMax = math.max(sirenMin, number(user.sirenMax, sirenMax))
    sirenVolume = number(user.sirenVolume, sirenVolume)
end

local function log(msg) print("[RandomEmissions] " .. tostring(msg) .. "\n") end

local sirenThreshold = math.random(sirenMin, sirenMax)
local sirenCue = nil
local siren = nil
local isSirenPlaying = false
local CHECK_EVERY_MS = 2000   -- how often the time until the emission is checked
local globalManager = nil     -- kept while valid: finding it walks every object
local localController = nil

local function GetSirenCue()
    if sirenCue ~= nil and sirenCue:IsValid() then
        return sirenCue
    end

    local path = "/Game/Sounds/S_2minSiren_Cue.S_2minSiren_Cue"
    sirenCue = StaticFindObject(path) or LoadObject(nil, path)

    return sirenCue
end

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

-- In someone else's world (the host's game has authority over our controller)
local function Joined()
    if not Valid(localController) then
        localController = nil
        pcall(function()
            for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
                if Valid(ctrl) and ctrl:IsLocalController() then localController = ctrl return end
            end
        end)
    end
    if not localController then return false end
    local ok, authority = pcall(function() return localController:HasAuthority() end)
    return ok and authority == false
end

local function GlobalManager()
    if Valid(globalManager) then return globalManager end
    globalManager = nil
    local gm = FindFirstOf("BP_GlobalManager_C")
    if Valid(gm) then globalManager = gm end
    return globalManager
end

-- Hosting: the siren starts for everyone who joined
local function TellPlayers()
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(ctrl) and not ctrl:IsLocalController() then
                pcall(function() ctrl:ClientMessage("[RandomEmissions] Emission coming #RE:siren", FName("None"), 0.0) end)
            end
        end
    end)
end

-- Is this mod's siren still sounding?
local function SirenSounding()
    if not (siren and Valid(siren)) then return false end
    local playing = false
    pcall(function() playing = siren:IsPlaying() end)
    return playing == true
end

local playingOwn = false   -- (our own SpawnSound2D call, so the watch below ignores it)
local function PlaySiren(why)
    if not isSirenEnabled or isSirenPlaying then
        return
    end
    -- never two of ours at once: two sirens on top of each other (17 Oct)
    if SirenSounding() then
        isSirenPlaying = true
        log("Siren (" .. why .. "): one is already sounding - not starting another")
        return
    end

    local gs = UEHelpers.GetGameplayStatics()
    local world = UEHelpers.GetWorld()
    local cue = GetSirenCue()

    playingOwn = true
    pcall(function()
        siren = gs:SpawnSound2D(world, cue, sirenVolume, 1.0, 0.0, nil, false, false)
		isSirenPlaying = true
    end)
    playingOwn = false
    log("Siren started (" .. why .. ")")
end

-- The game's own siren: if the game starts a siren itself while ours sounds,
-- ours stops (two on top of each other otherwise). Only 2D sounds are looked
-- at, and only their name
local function OnGame2DSound(_, worldContext, sound)
    if playingOwn then return end
    local name = ""
    pcall(function() name = sound:get():GetFName():ToString() end)
    if not name:lower():find("siren", 1, true) then return end
    if SirenSounding() then
        pcall(function() siren:Stop() end)
        log("The game itself started a siren (" .. name .. ") - this mod's stops so there's only one")
    else
        log("The game itself started a siren (" .. name .. ")")
    end
end
for _, fn in ipairs({ "SpawnSound2D", "PlaySound2D" }) do
    pcall(RegisterHook, "/Script/Engine.GameplayStatics:" .. fn, OnGame2DSound)
end

-- Every CHECK_EVERY_MS (it used to run Lua on every frame)
local function OnTick()
	local gm = GlobalManager()
	if not gm then return end
	if gm.TimeUntilEmmision > 1.0 and gm.TimeUntilEmmision < sirenThreshold and not isSirenPlaying
	   and not Joined() then
		PlaySiren(string.format("%.0f s before the emission", gm.TimeUntilEmmision))
		TellPlayers()
	end
end

local function OnUnloadPreviousLevels()
	if siren ~= nil and sirenCue ~= nil and sirenCue:IsValid() then
		siren:SetActive(false, true)
	end
	isSirenPlaying = false
	sirenThreshold = math.random(sirenMin, sirenMax)
	if Joined() then return end   -- the host's game picks the time
	local gm = GlobalManager()
	if not gm then return end
	gm.TimeUntilEmmision = math.random(randomMin, randomMax)
	log(string.format("Next emission in %.0f min, siren %d s before it", gm.TimeUntilEmmision / 60, sirenThreshold))
end

-- The host's siren, on a player who joined
local function OnClientMessage(selfParam, textParam)
	local text = textParam
	pcall(function() text = textParam:get() end)
	if type(text) ~= "string" then
		local ok, s = pcall(function() return text:ToString() end)
		text = ok and s or ""
	end
	if not text:find("#RE:siren", 1, true) or not Joined() then return end
	isSirenPlaying = false   -- each warning from the host plays once
	PlaySiren("the host's started")
end
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientMessage", OnClientMessage)

-- ClientRestart fires several times per load and again on every respawn, so
-- the hook and the tick loop are set up only once (they used to pile up).
local isUnloadHooked = false
local isTickLoopStarted = false

-- Repeats fn on the game thread every ms until it returns true: a 1 s
-- background tick that hands fn to the game thread. (Game-thread timers,
-- LoopInGameThreadWithDelay, in several mods at once froze the game.)
local function GameLoop(ms, fn)
	local stopped = false
	local function tick()
		if stopped then return true end
		local ok, stop = pcall(fn)
		if ok and stop == true then stopped = true end
		return stopped
	end
	LoopAsync(ms, function()
		if stopped then return true end
		ExecuteInGameThread(tick)
		return false
	end)
end

local function Setup()
	if not isUnloadHooked then
		isUnloadHooked = pcall(RegisterHook, "/Game/Blueprints/BP_GlobalManager.BP_GlobalManager_C:UnloadPreviousLevels", OnUnloadPreviousLevels)
	end

	if not isTickLoopStarted then
		isTickLoopStarted = true
		GameLoop(CHECK_EVERY_MS, function() pcall(OnTick) end)
	end
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", Setup)

-- Restarted in a world (.reloadmods, or the Mod Hub after a settings
-- change): start now, not only at the next load. At the game's start there's
-- no global manager yet, and the next load starts it as before.
ExecuteInGameThread(function()
	if GlobalManager() then Setup() end
end)