------------------------------------------------------------
-- Radiation Shield
------------------------------------------------------------
-- A toggle for 25% less radiation while it is on, for places (like parts of
-- the bunker) where radiation builds too fast even with the best gear. Turn
-- it on before walking in, off again afterwards.
--
-- Toggle: the key below, or type .radshield in the UE4SS console.
-- .radshield 75 changes the reduction to 75% until the game restarts.
-- .radmeter measures how hard a spot hits you and suggests a reduction.
------------------------------------------------------------
-- Config
------------------------------------------------------------
-- Any UE4SS key name: HOME, END, INS, DEL, PAGE_DOWN, F8 ...
local toggleKey = "HOME"
-- How much less radiation you get while the shield is on: 0.25 = 25% less
local reduction = 0.25
-- true = shield is already on when the game starts
local startOn = false
-- On-screen badge while the shield is on. Position: anchorX/anchorY are
-- 0..1 across/down the screen (0.5, 0 = top centre), offsetX/offsetY in pixels.
local showIndicator = true
local indicatorPosition = { anchorX = 0.5, anchorY = 0.0, offsetX = 0, offsetY = 24 }
----------------------------------

local INVENTORY_CLASS = "/Game/SurvivalGameKitV2/Components/BP_PlayerInventory.BP_PlayerInventory_C"
-- The player's radiation value (CurrentRadiation in this game version); only
-- used by the once-a-second check that the reduction is working.
local RADIATION_FIELDS = { "CurrentRadiation", "Radiation", "RadiationLevel", "PlayerRadiation" }

local isOn = startOn
local isHooked = false
local isLoopRunning = false
-- "shrink": make the amount smaller before the game adds it (exact, also near
-- the maximum). "takeback": remove 25% right after it was added - used if the
-- game turns out to ignore the smaller amount.
local mode = "shrink"
local radiationField = nil
local myInventory, myAddress = nil, nil
local intake, lastSample = 0, nil   -- radiation the game added since the last check
local MAX_FIELDS = { "MaxRadiation", "MaximumRadiation", "RadiationMax", "MaxRadiationLevel" }

-- Radiation meter (.radmeter): what the game sends, before the shield
local meterOn = false
local meterRaw, meterHits = 0, 0        -- this second
local meter = nil                        -- totals since the meter was switched on

local function log(msg)
    print("[RadiationShield] " .. tostring(msg) .. "\n")
end

local function AddressOf(obj)
    local ok, address = pcall(function() return obj:GetAddress() end)
    return ok and address or nil
end

-- The local player's stats live on their BP_PlayerInventory component
-- (same lookup as the mod menu: never another player's character).
-- FindAllOf walks every object in the game on this UE4SS build, so this runs
-- only when the remembered inventory is gone - never per radiation tick.
local function RefreshMyInventory()
    if myInventory and myInventory:IsValid() then return myInventory end
    myInventory, myAddress = nil, nil
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if ctrl:IsLocalController() then
                local candidate = ctrl.Character.PlayerInventory
                if candidate:IsValid() then myInventory = candidate end
                return
            end
        end
    end)
    myAddress = myInventory and AddressOf(myInventory) or nil
    return myInventory
end

local function ReadRadiation(inv)
    local function read(name)
        local ok, value = pcall(function() return inv[name] end)
        if ok and type(value) == "number" then return value end
        return nil
    end
    if radiationField then return read(radiationField) end
    for _, name in ipairs(RADIATION_FIELDS) do
        local value = read(name)
        if value then
            radiationField = name
            return value
        end
    end
    return nil
end

local maxField = false   -- false = not looked for yet, nil = none exists
local function ReadMax(inv)
    if maxField == false then
        maxField = nil
        for _, name in ipairs(MAX_FIELDS) do
            local ok, value = pcall(function() return inv[name] end)
            if ok and type(value) == "number" and value > 0 then maxField = name break end
        end
    end
    if not maxField then return nil end
    local ok, value = pcall(function() return inv[maxField] end)
    return ok and type(value) == "number" and value or nil
end

local function TakeBack(inv, amount)
    if amount > 0.0001 then pcall(function() inv:DecreaseRadiation(amount) end) end
end

-- Called for every bit of radiation the game adds (many times a second in a
-- radiation zone), before the game applies it - so this must stay cheap.
local reportedWorking = false   -- one log line per switch-on, so the log shows it's acting

local function OnIncreaseRadiation(selfParam, amountParam)
    if not (isOn or meterOn) or not myAddress then return end
    local inv = nil
    pcall(function() inv = selfParam:get() end)
    if not inv or AddressOf(inv) ~= myAddress then return end
    local amount = nil
    pcall(function() amount = amountParam:get() end)
    if type(amount) ~= "number" or amount <= 0 then return end
    if meterOn then meterRaw, meterHits = meterRaw + amount, meterHits + 1 end
    if not isOn then return end
    intake = intake + amount
    if mode == "shrink" then
        pcall(function() amountParam:set(amount * (1 - reduction)) end)
        if not reportedWorking then
            reportedWorking = true
            log(string.format("Working: radiation hit %.3f reduced to %.3f", amount, amount * (1 - reduction)))
        end
    else
        local take = amount * reduction
        -- queued: runs after the game's own function has added the radiation
        ExecuteInGameThread(function() TakeBack(inv, take) end)
    end
end

local function InstallHook()
    if isHooked then return end
    isHooked = pcall(RegisterHook, INVENTORY_CLASS .. ":IncreaseRadiation", OnIncreaseRadiation)
end

-- Once a second while on: re-find the inventory if a load replaced it, and
-- check the reduction is really happening. With "shrink" working, radiation
-- rises by at most ~75% of what the game asked for; if it rises by (nearly)
-- all of it, the game ignored the smaller amount, so switch to "takeback".
-- If IncreaseRadiation can't be hooked at all, take back 25% of each rise here.
local function StartLoop()
    if isLoopRunning then return end
    isLoopRunning = true
    intake, lastSample = 0, nil
    LoopAsync(1000, function()
        if not isOn then
            isLoopRunning = false
            return true
        end
        ExecuteInGameThread(function()
            local inv = RefreshMyInventory()
            if not inv then return end
            local now = ReadRadiation(inv)
            if now and lastSample then
                local rose = now - lastSample
                if not isHooked and rose > 0 then
                    TakeBack(inv, rose * reduction)
                    now = now - rose * reduction
                elseif mode == "shrink" and intake > 1 and rose >= intake * 0.85 then
                    mode = "takeback"
                    log("The game ignored the smaller radiation amount; taking back "
                        .. math.floor(reduction * 100 + 0.5) .. "% after it's added instead")
                end
            end
            intake, lastSample = 0, now
        end)
        return false
    end)
end

------------------------------------------------------------
-- Radiation meter
------------------------------------------------------------
-- Logs once a second while radiation is coming in: what the game sends
-- (before the shield), what the shield lets through, and your radiation.
-- The summary turns that into "how much reduction makes this spot usable".
local function Percent(x) return math.floor(x * 100 + 0.5) end

local function MeterSummary()
    local m = meter
    if not m or m.seconds == 0 then
        log("Meter: no radiation measured - stand in the hot spot with .radmeter on")
        return
    end
    local avg = m.total / m.seconds
    local maxRad, maxNote = m.max, ""
    if not maxRad then maxRad, maxNote = math.max(m.highest, 1), " (highest seen; real maximum unknown)" end
    log(string.format("Meter summary: %d s in radiation, game sent +%.2f/s on average, peak +%.2f/s; maximum radiation %.0f%s",
        m.seconds, avg, m.peak, maxRad, maxNote))
    if m.unhooked > 0.5 * (m.total + m.unhooked) then
        log(string.format("Meter: radiation rose +%.1f outside IncreaseRadiation (vs +%.1f through it) - "
            .. "the shield can only reduce the part that goes through it", m.unhooked, m.total))
    end
    log(string.format("  From 0 to maximum: %.0f s with no shield, %.0f s with the current %d%%",
        maxRad / avg, maxRad / (avg * math.max(0.001, 1 - reduction)), Percent(reduction)))
    for _, seconds in ipairs({ 30, 60, 120, 300 }) do
        local needed = 1 - (maxRad / seconds) / avg
        local text
        if needed <= 0 then text = "no shield needed"
        elseif needed >= 0.995 then text = "needs ~100%"
        else text = Percent(needed) .. "%" .. (needed <= reduction and " (current setting is enough)" or "") end
        log(string.format("  To last %3d s: %s", seconds, text))
    end
end

local function StartMeter()
    meterOn = true
    meterRaw, meterHits = 0, 0
    meter = { seconds = 0, total = 0, peak = 0, highest = 0, max = nil, unhooked = 0, last = nil }
    local session = meter
    LoopAsync(1000, function()
        if not meterOn or meter ~= session then return true end
        ExecuteInGameThread(function()
            local raw, hits = meterRaw, meterHits
            meterRaw, meterHits = 0, 0
            local inv = RefreshMyInventory()
            if not inv then return end
            local now = ReadRadiation(inv)
            local max = ReadMax(inv)
            local m = session
            if max then m.max = max end
            if now and now > m.highest then m.highest = now end
            local rose = (now and m.last) and (now - m.last) or 0
            m.last = now
            local through = isOn and raw * (1 - reduction) or raw
            if rose > through + 0.05 then m.unhooked = m.unhooked + (rose - through) end
            if raw > 0 then
                m.seconds = m.seconds + 1
                m.total = m.total + raw
                if raw > m.peak then m.peak = raw end
                log(string.format("Meter: game sends +%.2f/s (%d hits)%s | radiation %s%s (%+.2f)",
                    raw, hits,
                    isOn and string.format(", through shield +%.2f/s", through) or ", shield off",
                    now and string.format("%.1f", now) or "?",
                    max and string.format(" / %.0f", max) or "", rose))
            elseif rose > 0.05 then
                log(string.format("Meter: radiation rose %+.2f without IncreaseRadiation", rose))
            end
        end)
        return false
    end)
    log("Radiation meter ON - walk into the hot spot; .radmeter again for the summary")
end

------------------------------------------------------------
-- On-screen indicator
------------------------------------------------------------
--   | RADIATION SHIELD
--   | -25% RADIATION
-- A dark see-through badge with a softly pulsing green bar while the shield
-- is on; "SHIELD OFF" in grey for a moment when it is turned off.
-- Built at runtime from plain UMG widgets inside the game's own HUD
-- (BP_InventoryHUD, which also hosts the mod menu). A stand-alone UserWidget
-- is not used: that class is abstract and creating one can crash the game.
local UMG = "/Script/UMG."
local HIT_TEST_INVISIBLE = 3   -- ESlateVisibility: shown, never blocks the mouse
local COLLAPSED = 1
local GREEN, PALE_GREEN, WHITE = { R = 0.25, G = 1.0, B = 0.45, A = 1.0 }, { R = 0.55, G = 1.0, B = 0.62, A = 1.0 }, { R = 0.92, G = 1.0, B = 0.94, A = 1.0 }
local GREY, PALE_GREY = { R = 0.45, G = 0.47, B = 0.46, A = 1.0 }, { R = 0.7, G = 0.72, B = 0.71, A = 1.0 }

local badge = nil              -- { panel, accent, title, value, hud }
local indicatorWarned = false
local isAnimating = false
local animStop = false         -- set in the game thread, read by the timer
local animPhase, fade = 0, 0
local offUntil = nil

local function ClassName(obj)
    local name = ""
    pcall(function() name = obj:GetClass():GetFName():ToString() end)
    return name
end

local function Construct(className, outer)
    local cls = StaticFindObject(UMG .. className)
    if not cls or not cls:IsValid() then error(className .. " class not found", 0) end
    local obj = StaticConstructObject(cls, outer)
    if not obj or not obj:IsValid() then error("could not create " .. className, 0) end
    return obj
end

local function SetText(text, s)
    if not pcall(function() text:SetText(FText(s)) end) then pcall(function() text:SetText(s) end) end
end

local function SetTextColor(text, color)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

local function StyleText(text, size, color, letterSpacing)
    pcall(function() text.Font.Size = size end)
    if letterSpacing then pcall(function() text.Font.LetterSpacing = letterSpacing end) end
    SetTextColor(text, color)
    pcall(function() text:SetShadowOffset({ X = 1.0, Y = 1.0 }) end)
    pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 }) end)
end

local function BuildBadge(tree)
    local b = {}
    b.panel = Construct("Border", tree)
    b.panel:SetBrushColor({ R = 0.01, G = 0.04, B = 0.02, A = 0.72 })
    pcall(function() b.panel:SetPadding({ Left = 10, Top = 6, Right = 16, Bottom = 7 }) end)
    local row = Construct("HorizontalBox", tree)
    b.panel:SetContent(row)

    local bar = Construct("SizeBox", tree)
    bar:SetWidthOverride(4.0)
    bar:SetHeightOverride(34.0)
    b.accent = Construct("Border", tree)
    b.accent:SetBrushColor(GREEN)
    bar:SetContent(b.accent)
    local barSlot = row:AddChildToHorizontalBox(bar)
    pcall(function() barSlot:SetVerticalAlignment(2) end)   -- centre

    local column = Construct("VerticalBox", tree)
    local columnSlot = row:AddChildToHorizontalBox(column)
    pcall(function() columnSlot:SetPadding({ Left = 10, Top = 0, Right = 0, Bottom = 0 }) end)
    pcall(function() columnSlot:SetVerticalAlignment(2) end)

    b.title = Construct("TextBlock", tree)
    StyleText(b.title, 10, PALE_GREEN, 180)
    column:AddChildToVerticalBox(b.title)
    b.value = Construct("TextBlock", tree)
    StyleText(b.value, 17, WHITE)
    column:AddChildToVerticalBox(b.value)
    return b
end

-- The badge for the current HUD, building it the first time (and again
-- after a level load creates a new HUD).
local function EnsureBadge()
    if not showIndicator then return nil end
    local hud = nil
    pcall(function()
        local found = FindFirstOf("BP_InventoryHUD_C")
        if found and found:IsValid() then hud = found end
    end)
    if not hud then return nil end
    local hudName = ""
    pcall(function() hudName = hud:GetFullName() end)
    if badge and badge.hud == hudName and badge.panel:IsValid() then return badge end

    badge = nil
    local ok, err = pcall(function()
        local tree = hud.WidgetTree
        local root = tree.RootWidget
        local rootClass = ClassName(root)
        local b = BuildBadge(tree)
        local p = indicatorPosition
        if rootClass == "CanvasPanel" then
            local slot = root:AddChildToCanvas(b.panel)
            pcall(function() slot:SetAnchors({ Minimum = { X = p.anchorX, Y = p.anchorY }, Maximum = { X = p.anchorX, Y = p.anchorY } }) end)
            pcall(function() slot:SetAlignment({ X = p.anchorX, Y = p.anchorY }) end)
            pcall(function() slot:SetPosition({ X = p.offsetX, Y = p.offsetY }) end)
            pcall(function() slot:SetAutoSize(true) end)
            pcall(function() slot:SetZOrder(100) end)
        elseif rootClass == "Overlay" then
            local slot = root:AddChildToOverlay(b.panel)
            -- EHorizontalAlignment/EVerticalAlignment: 1 left/top, 2 centre, 3 right/bottom
            local h = p.anchorX < 0.34 and 1 or (p.anchorX > 0.66 and 3 or 2)
            local v = p.anchorY < 0.34 and 1 or (p.anchorY > 0.66 and 3 or 2)
            pcall(function() slot:SetHorizontalAlignment(h) end)
            pcall(function() slot:SetVerticalAlignment(v) end)
            pcall(function() slot:SetPadding({ Left = math.max(0, p.offsetX), Top = math.max(0, p.offsetY),
                Right = math.max(0, -p.offsetX), Bottom = math.max(0, -p.offsetY) }) end)
        else
            error("the HUD's root is a " .. rootClass .. ", not a canvas or overlay", 0)
        end
        pcall(function() b.panel:SetVisibility(COLLAPSED) end)
        b.hud = hudName
        badge = b
    end)
    if not ok and not indicatorWarned then
        indicatorWarned = true
        log("Indicator unavailable (" .. tostring(err) .. ") - the shield still works")
    end
    return badge
end

local function StartAnimation()
    animStop = false   -- also cancels a fade-out that was about to stop the loop
    if isAnimating then return end
    isAnimating = true
    LoopAsync(80, function()
        if animStop then
            isAnimating = false
            return true
        end
        ExecuteInGameThread(function()
            local b = badge
            if not b or not b.panel:IsValid() then
                if not isOn then animStop = true end
                return
            end
            animPhase = animPhase + 0.08
            if isOn then
                fade = math.min(1, fade + 0.25)
                local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(animPhase * 2 * math.pi / 1.6))
                pcall(function() b.accent:SetRenderOpacity(pulse) end)
                pcall(function() b.panel:SetRenderOpacity(fade) end)
            elseif offUntil and os.clock() < offUntil then
                pcall(function() b.panel:SetRenderOpacity(1) end)
            else
                fade = math.max(0, fade - 0.2)
                pcall(function() b.panel:SetRenderOpacity(fade) end)
                if fade <= 0 then
                    pcall(function() b.panel:SetVisibility(COLLAPSED) end)
                    animStop = true
                end
            end
        end)
        return false
    end)
end

-- Game thread only (widget calls)
local function ShowIndicator(on)
    local b = EnsureBadge()
    if not b then return end
    SetText(b.title, "RADIATION SHIELD")
    if on then
        SetText(b.value, "-" .. math.floor(reduction * 100 + 0.5) .. "% RADIATION")
        pcall(function() b.accent:SetBrushColor(GREEN) end)
        SetTextColor(b.title, PALE_GREEN)
        SetTextColor(b.value, WHITE)
        offUntil = nil
    else
        SetText(b.value, "SHIELD OFF")
        pcall(function() b.accent:SetBrushColor(GREY) end)
        pcall(function() b.accent:SetRenderOpacity(1) end)
        SetTextColor(b.title, GREY)
        SetTextColor(b.value, PALE_GREY)
        offUntil = os.clock() + 1.5
        fade = 1
    end
    pcall(function() b.panel:SetVisibility(HIT_TEST_INVISIBLE) end)
    StartAnimation()
end

local function SetShield(on)
    isOn = on
    reportedWorking = false
    InstallHook()
    if isOn then StartLoop() end
    ExecuteInGameThread(function()
        if on then
            local inv = RefreshMyInventory()
            -- start the once-a-second check from the radiation right now
            intake, lastSample = 0, inv and ReadRadiation(inv) or nil
        end
        ShowIndicator(on)
    end)
    local percent = math.floor(reduction * 100 + 0.5)
    log("Radiation shield " .. (isOn and ("ON - " .. percent .. "% less radiation") or "OFF"))
end

local okKey = pcall(function()
    RegisterKeyBind(Key[toggleKey], function() SetShield(not isOn) end)
end)
if not okKey then log("Key '" .. tostring(toggleKey) .. "' could not be bound; use .radshield instead") end

RegisterConsoleCommandHandler(".radshield", function(FullCommand, Parameters)
    local arg = string.lower((Parameters and Parameters[1]) or "")
    local percent = tonumber((arg:gsub("%%", "")))
    if percent then
        if percent < 1 or percent > 100 then
            log("Use a percentage from 1 to 100, e.g. .radshield 75")
            return true
        end
        reduction = percent / 100
        log("Reduction set to " .. Percent(reduction) .. "% until the game restarts "
            .. "(set reduction = " .. reduction .. " in main.lua to keep it)")
        SetShield(true)
        return true
    end
    if arg == "on" then SetShield(true)
    elseif arg == "off" then SetShield(false)
    else SetShield(not isOn) end
    return true
end)

RegisterConsoleCommandHandler(".radmeter", function()
    InstallHook()
    if meterOn then
        meterOn = false
        ExecuteInGameThread(function() MeterSummary() end)
        log("Radiation meter OFF")
    else
        StartMeter()
    end
    return true
end)

-- The inventory Blueprint is only loaded once you are in a world
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    InstallHook()
    -- a respawn or level load gives the player a new inventory and HUD
    LoopAsync(2000, function()
        ExecuteInGameThread(function()
            myInventory, myAddress = nil, nil
            if isOn or meterOn then RefreshMyInventory() end
            if isOn then ShowIndicator(true) end
        end)
        return true
    end)
    if isOn then StartLoop() end
end)

log("Loaded. Toggle with " .. toggleKey .. " or .radshield (" .. math.floor(reduction * 100 + 0.5)
    .. "% less radiation, currently " .. (isOn and "ON" or "OFF") .. ")")
