------------------------------------------------------------
-- Random Emissions Config
------------------------------------------------------------
-- Minimum random time in seconds until emission
local randomMin = 1800
-- Maximum random time in seconds until emission
local randomMax = 3600
-- Plays the siren warning sound before
local isSirenEnabled = true
-- Minimum random time in seconds left until siren
local sirenMin = 120
-- Maximum random time in seconds left until siren
local sirenMax = 300
-- Volume of siren
local sirenVolume = 3.0
----------------------------------

local UEHelpers = require("UEHelpers")

local sirenThreshold = math.random(sirenMin, sirenMax)
local sirenCue = nil
local siren = nil
local isSirenPlaying = false
local updateCount = 0
local updateInterval = 1000

local function GetSirenCue()
    if sirenCue ~= nil and sirenCue:IsValid() then
        return sirenCue
    end

    local path = "/Game/Sounds/S_2minSiren_Cue.S_2minSiren_Cue"
    sirenCue = StaticFindObject(path) or LoadObject(nil, path)

    return sirenCue
end

local function PlaySiren()
    if not isSirenEnabled or isSirenPlaying then
        return
    end

    local gs = UEHelpers.GetGameplayStatics()
    local world = UEHelpers.GetWorld()
    local cue = GetSirenCue()

    pcall(function()
        siren = gs:SpawnSound2D(world, cue, sirenVolume, 1.0, 0.0, nil, false, false)
		isSirenPlaying = true
    end)
end

local function OnTick(selfParam, deltaParam)
	updateCount = updateCount + 1
    if updateCount % updateInterval == 0 then
		local gm = FindFirstOf("BP_GlobalManager_C")
		if gm.TimeUntilEmmision > 1.0 and gm.TimeUntilEmmision < sirenThreshold then
			PlaySiren()
		end
		
		updateCount = 0
	end
end

local function OnUnloadPreviousLevels()
	local gm = FindFirstOf("BP_GlobalManager_C")
	if gm == nil or not gm:IsValid() then return end
	gm.TimeUntilEmmision = math.random(randomMin, randomMax)
	if siren ~= nil and sirenCue ~= nil and sirenCue:IsValid() then
		isSirenPlaying = false
		siren:SetActive(false, true)
	end
	sirenThreshold = math.random(sirenMin, sirenMax)
end

-- ClientRestart fires several times per load and again on every respawn, so
-- the hook and the tick loop are set up only once (they used to pile up).
local isUnloadHooked = false
local isTickLoopStarted = false

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
	if not isUnloadHooked then
		isUnloadHooked = pcall(RegisterHook, "/Game/Blueprints/BP_GlobalManager.BP_GlobalManager_C:UnloadPreviousLevels", OnUnloadPreviousLevels)
	end

	if not isTickLoopStarted then
		isTickLoopStarted = true
		LoopInGameThreadAfterFrames(1, function()
	        pcall(OnTick, nil, 1/60)
	    end)
	end
end)