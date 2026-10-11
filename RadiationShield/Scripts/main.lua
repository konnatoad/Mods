------------------------------------------------------------
-- Radiation Shield
------------------------------------------------------------
-- Less radiation while it is on, for places (like parts of the bunker) where
-- radiation builds too fast even with the best gear.
--
--   HOME (or .radshield)   turn the shield on/off
--   .radmenu               settings menu: arrow keys to choose and change,
--                          .radmenu again (or "Close") to close it
--   .radshield 75          set 75% less radiation and switch the shield on
--   .radmeter              measure a hot spot, then .radmeter for a summary
--
-- Co-op: everyone's shield is their own - HOME protects only the player who
-- pressed it. The host decides whether players who joined may use theirs
-- ("Others can use it" in the host's menu); if not, they see "Disabled by
-- host". The host's and the players' mods talk through two messages Unreal
-- Engine always has (ServerCheat to the host, ClientMessage back), so this
-- works whichever game adds the radiation. Everyone needs this mod.
------------------------------------------------------------
-- Defaults. The menu saves your choices to settings.txt in this mod's
-- folder; that file overrides these.
------------------------------------------------------------
-- Any UE4SS key name: HOME, END, INS, DEL, PAGE_DOWN, F8 ...
local toggleKey = "HOME"
-- How much less radiation you get while the shield is on: 0.25 = 25% less
local reduction = 0.25
-- true = shield is already on when the game starts
local startOn = false
-- On-screen badge while the shield is on, and where
local showIndicator = true
local badgePosition = "Top centre"
-- Live readout of incoming radiation (also switchable in the menu)
local showDebug = false
-- When you host: players who joined may use their own shields
local allowOthers = false
----------------------------------

local SETTINGS_PATH = "./ue4ss/Mods/RadiationShield/settings.txt"
local INVENTORY_CLASS = "/Game/SurvivalGameKitV2/Components/BP_PlayerInventory.BP_PlayerInventory_C"
-- The player's radiation value (CurrentRadiation in this game version)
local RADIATION_FIELDS = { "CurrentRadiation", "Radiation", "RadiationLevel", "PlayerRadiation" }
local MAX_FIELDS = { "MaxRadiation", "MaximumRadiation", "RadiationMax", "MaxRadiationLevel" }
local KEY_CHOICES = { "HOME", "END", "INS", "DEL", "PAGE_DOWN", "F6", "F7", "F8", "F9" }
-- name, anchorX, anchorY (0..1 across/down the screen), offsetX, offsetY (px)
local POSITIONS = {
    { "Top centre", 0.5, 0.0, 0, 24 },
    { "Top left", 0.0, 0.0, 24, 24 },
    { "Top right", 1.0, 0.0, -24, 24 },
    { "Bottom centre", 0.5, 1.0, 0, -140 },
    { "Left middle", 0.0, 0.5, 24, 0 },
    { "Right middle", 1.0, 0.5, -24, 0 },
}

local function log(msg)
    print("[RadiationShield] " .. tostring(msg) .. "\n")
end

local function Percent(x) return math.floor(x * 100 + 0.5) end

------------------------------------------------------------
-- Settings file
------------------------------------------------------------
local function LoadSettings()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local values = {}
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key then values[key] = value end
    end
    file:close()
    local function bool(v, default) if v == "true" then return true elseif v == "false" then return false end return default end
    local r = tonumber(values.reduction)
    if r and r > 0 and r <= 1 then reduction = r end
    startOn = bool(values.startOn, startOn)
    showIndicator = bool(values.showIndicator, showIndicator)
    showDebug = bool(values.showDebug, showDebug)
    allowOthers = bool(values.allowOthers, allowOthers)
    for _, p in ipairs(POSITIONS) do if p[1] == values.badgePosition then badgePosition = p[1] end end
    if values.toggleKey and values.toggleKey:match("^[%w_]+$") then toggleKey = values.toggleKey end
end

local function SaveSettings()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then return false end
    file:write("# Radiation Shield settings - written by the .radmenu menu\n")
    file:write("reduction = " .. reduction .. "\n")
    file:write("startOn = " .. tostring(startOn) .. "\n")
    file:write("showIndicator = " .. tostring(showIndicator) .. "\n")
    file:write("badgePosition = " .. badgePosition .. "\n")
    file:write("showDebug = " .. tostring(showDebug) .. "\n")
    file:write("allowOthers = " .. tostring(allowOthers) .. "\n")
    file:write("toggleKey = " .. toggleKey .. "\n")
    file:close()
    return true
end

LoadSettings()
local boundKey = toggleKey   -- the key actually bound this session

------------------------------------------------------------
-- State
------------------------------------------------------------
local isOn = startOn
local isHooked = false
local isLoopRunning = false
local RebuildOthers
local menuOpen = false
-- "shrink": make the amount smaller before the game adds it (exact, also near
-- the maximum). "takeback": remove it right after it was added - used if the
-- game turns out to ignore the smaller amount.
local mode = "shrink"
local radiationField = nil
local maxField = false   -- false = not looked for yet, nil = none exists
local myInventory, myAddress = nil, nil
local myController = nil
local amHost = true      -- false when we joined someone else's world
-- Joined someone: what the host's mod said. nil = not asked yet,
-- "asking", "allowed", "denied", "nomod" (no answer: host lacks the mod)
local hostAnswer = nil
-- Hosting: players who joined and have their shield on.
-- others[controller address] = { pc = controller, reduction = 0.25, name = "..." }
local others = {}
local othersByInv = {}     -- [inventory address] = reduction, for the hook
local othersActive = false
local intake, lastSample = 0, nil   -- shield check: radiation the game added since the last second
local rawSecond, hitsSecond = 0, 0  -- what the game sent this second, before the shield
local live = { raw = 0, rose = 0, now = nil, max = nil }   -- smoothed, for the readout
local meterOn = false
local meter = nil
local reportedWorking = false   -- one log line per switch-on, so the log shows it's acting

local function Measuring() return meterOn or showDebug or menuOpen end
local function Joined() return myController ~= nil and not amHost end

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
                myController = ctrl
                local candidate = ctrl.Character.PlayerInventory
                if candidate:IsValid() then myInventory = candidate end
                return
            end
        end
    end)
    myAddress = myInventory and AddressOf(myInventory) or nil
    if myInventory then
        local ok, authority = pcall(function() return myInventory:GetOwner():HasAuthority() end)
        amHost = not (ok and authority == false)
    end
    return myInventory
end

local function ReadNumber(obj, name)
    local ok, value = pcall(function() return obj[name] end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function ReadRadiation(inv)
    if radiationField then return ReadNumber(inv, radiationField) end
    for _, name in ipairs(RADIATION_FIELDS) do
        local value = ReadNumber(inv, name)
        if value then
            radiationField = name
            return value
        end
    end
    return nil
end

local function ReadMax(inv)
    if maxField == false then
        maxField = nil
        for _, name in ipairs(MAX_FIELDS) do
            local value = ReadNumber(inv, name)
            if value and value > 0 then maxField = name break end
        end
    end
    return maxField and ReadNumber(inv, maxField) or nil
end

local function TakeBack(inv, amount)
    if amount > 0.0001 then pcall(function() inv:DecreaseRadiation(amount) end) end
end

------------------------------------------------------------
-- The shield
------------------------------------------------------------
-- Called for every bit of radiation the game adds (many times a second in a
-- radiation zone, for every player on the host), before the game applies it
-- - so this must stay cheap: no object searches, no widgets.
local function OnIncreaseRadiation(selfParam, amountParam)
    if not (isOn or othersActive or Measuring()) then return end
    local inv = nil
    pcall(function() inv = selfParam:get() end)
    if not inv then return end
    local address = AddressOf(inv)
    local mine = myAddress ~= nil and address == myAddress
    local cut = nil
    if mine then
        if isOn then cut = reduction end
    else
        -- hosting: another player whose own shield is on
        cut = othersByInv[address]
        if not cut then return end
    end
    local amount = nil
    pcall(function() amount = amountParam:get() end)
    if type(amount) ~= "number" or amount <= 0 then return end
    if mine then rawSecond, hitsSecond = rawSecond + amount, hitsSecond + 1 end
    if not cut then return end
    if mine then intake = intake + amount end
    if mode == "shrink" or not amHost then
        pcall(function() amountParam:set(amount * (1 - cut)) end)
        if mine and not reportedWorking then
            reportedWorking = true
            log(string.format("Working: radiation hit %.3f reduced to %.3f", amount, amount * (1 - cut)))
        end
    else
        local take = amount * cut
        -- queued: runs after the game's own function has added the radiation
        ExecuteInGameThread(function() TakeBack(inv, take) end)
    end
end

local function InstallHook()
    if isHooked then return end
    isHooked = pcall(RegisterHook, INVENTORY_CLASS .. ":IncreaseRadiation", OnIncreaseRadiation)
end

------------------------------------------------------------
-- Radiation meter (.radmeter)
------------------------------------------------------------
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

local function MeterSecond(raw, hits, now, max, rose)
    local m = meter
    if max then m.max = max end
    if now and now > m.highest then m.highest = now end
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
end

------------------------------------------------------------
-- Widgets: badge, live readout, menu
------------------------------------------------------------
-- Built at runtime from plain UMG widgets inside the game's own HUD
-- (BP_InventoryHUD, which also hosts the mod menu). A stand-alone UserWidget
-- is not used: that class is abstract and creating one can crash the game.
--   badge:   | RADIATION SHIELD / -25% RADIATION, softly pulsing green bar
--   readout: radiation now, what comes in, what the shield removes, time to max
--   menu:    settings, changed with the arrow keys
local UMG = "/Script/UMG."
local HIT_TEST_INVISIBLE = 3   -- ESlateVisibility: shown, never blocks the mouse
local COLLAPSED = 1
local GREEN, PALE_GREEN, WHITE = { R = 0.25, G = 1.0, B = 0.45, A = 1.0 }, { R = 0.55, G = 1.0, B = 0.62, A = 1.0 }, { R = 0.92, G = 1.0, B = 0.94, A = 1.0 }
local GREY, PALE_GREY = { R = 0.45, G = 0.47, B = 0.46, A = 1.0 }, { R = 0.7, G = 0.72, B = 0.71, A = 1.0 }
local AMBER = { R = 1.0, G = 0.75, B = 0.25, A = 1.0 }
local RED = { R = 1.0, G = 0.35, B = 0.3, A = 1.0 }

local ui = { hud = nil, hudObj = nil }   -- widgets of the current HUD
local lastText = setmetatable({}, { __mode = "k" })   -- text each widget shows now
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

-- Only touches the widget when the text changes (the readout updates every second)
local function SetText(text, s)
    if not text or lastText[text] == s then return end
    if not pcall(function() text:SetText(FText(s)) end) then pcall(function() text:SetText(s) end) end
    lastText[text] = s
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

-- The HUD, remembered between calls: FindFirstOf searches every object, so
-- it runs only after a level load or when the remembered HUD is gone.
local function GetHud()
    if ui.hudObj then
        local ok, valid = pcall(function() return ui.hudObj:IsValid() end)
        if ok and valid then return ui.hudObj end
    end
    local hud = nil
    pcall(function()
        local found = FindFirstOf("BP_InventoryHUD_C")
        if found and found:IsValid() then hud = found end
    end)
    if not hud then return nil end
    local hudName = ""
    pcall(function() hudName = hud:GetFullName() end)
    if ui.hud ~= hudName then ui = { hud = hudName } end   -- new HUD: build everything again there
    ui.hudObj = hud
    return hud
end

-- Puts a panel on the HUD's root at a screen anchor
local function Attach(hud, panel, ax, ay, ox, oy, z)
    local root = hud.WidgetTree.RootWidget
    local rootClass = ClassName(root)
    if rootClass == "CanvasPanel" then
        local slot = root:AddChildToCanvas(panel)
        pcall(function() slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } }) end)
        pcall(function() slot:SetAlignment({ X = ax, Y = ay }) end)
        pcall(function() slot:SetPosition({ X = ox, Y = oy }) end)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(z) end)
    elseif rootClass == "Overlay" then
        local slot = root:AddChildToOverlay(panel)
        -- EHorizontalAlignment/EVerticalAlignment: 1 left/top, 2 centre, 3 right/bottom
        local h = ax < 0.34 and 1 or (ax > 0.66 and 3 or 2)
        local v = ay < 0.34 and 1 or (ay > 0.66 and 3 or 2)
        pcall(function() slot:SetHorizontalAlignment(h) end)
        pcall(function() slot:SetVerticalAlignment(v) end)
        pcall(function() slot:SetPadding({ Left = math.max(0, ox), Top = math.max(0, oy),
            Right = math.max(0, -ox), Bottom = math.max(0, -oy) }) end)
    else
        error("the HUD's root is a " .. rootClass .. ", not a canvas or overlay", 0)
    end
    pcall(function() panel:SetVisibility(COLLAPSED) end)
end

local function Warn(err)
    if not indicatorWarned then
        indicatorWarned = true
        log("Indicator unavailable (" .. tostring(err) .. ") - the shield still works")
    end
end

local function DarkPanel(tree, alpha)
    local panel = Construct("Border", tree)
    panel:SetBrushColor({ R = 0.01, G = 0.04, B = 0.02, A = alpha })
    return panel
end

local function BuildBadge(tree)
    local b = {}
    b.panel = DarkPanel(tree, 0.72)
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

local function PositionOf(name)
    for _, p in ipairs(POSITIONS) do if p[1] == name then return p end end
    return POSITIONS[1]
end

-- The badge for the current HUD, building it the first time (and again
-- after a level load creates a new HUD, or the position changes).
local function EnsureBadge()
    if not showIndicator then return nil end
    local hud = GetHud()
    if not hud then return nil end
    if ui.badge and ui.badge.panel:IsValid() then return ui.badge end
    ui.badge = nil
    local ok, err = pcall(function()
        local b = BuildBadge(hud.WidgetTree)
        local p = PositionOf(badgePosition)
        Attach(hud, b.panel, p[2], p[3], p[4], p[5], 100)
        ui.badge = b
    end)
    if not ok then Warn(err) end
    return ui.badge
end

-- Simple panel: a small title and a column of text lines
local function BuildTextPanel(hud, lineCount, ax, ay, ox, oy, titleText)
    local tree = hud.WidgetTree
    local p = { lines = {} }
    p.panel = DarkPanel(tree, 0.8)
    pcall(function() p.panel:SetPadding({ Left = 14, Top = 10, Right = 18, Bottom = 12 }) end)
    local column = Construct("VerticalBox", tree)
    p.panel:SetContent(column)
    p.title = Construct("TextBlock", tree)
    StyleText(p.title, 10, PALE_GREEN, 180)
    SetText(p.title, titleText)
    column:AddChildToVerticalBox(p.title)
    for i = 1, lineCount do
        local line = Construct("TextBlock", tree)
        StyleText(line, 13, WHITE)
        local slot = column:AddChildToVerticalBox(line)
        pcall(function() slot:SetPadding({ Left = 0, Top = i == 1 and 6 or 2, Right = 0, Bottom = 0 }) end)
        p.lines[i] = line
    end
    Attach(hud, p.panel, ax, ay, ox, oy, 101)
    return p
end

local function EnsurePanel(key, lineCount, ax, ay, ox, oy, titleText)
    local hud = GetHud()
    if not hud then return nil end
    local p = ui[key]
    if p and p.panel:IsValid() then return p end
    ui[key] = nil
    local ok, err = pcall(function() ui[key] = BuildTextPanel(hud, lineCount, ax, ay, ox, oy, titleText) end)
    if not ok then Warn(err) end
    return ui[key]
end

local function Show(p, on)
    if p then pcall(function() p.panel:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED) end) end
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
            local b = ui.badge
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

local function BadgeValue()
    return "-" .. Percent(reduction) .. "% RADIATION"
end

-- Game thread only (widget calls). on = true/false, or a short notice
-- ("DISABLED BY HOST") shown like "SHIELD OFF" in amber.
local function ShowIndicator(on, notice)
    if not showIndicator then
        if ui.badge then Show(ui.badge, false) end
        return
    end
    local b = EnsureBadge()
    if not b then return end
    SetText(b.title, "RADIATION SHIELD")
    if on then
        SetText(b.value, BadgeValue())
        pcall(function() b.accent:SetBrushColor(GREEN) end)
        SetTextColor(b.title, PALE_GREEN)
        SetTextColor(b.value, WHITE)
        offUntil = nil
    else
        SetText(b.value, notice or "SHIELD OFF")
        pcall(function() b.accent:SetBrushColor(notice and AMBER or GREY) end)
        pcall(function() b.accent:SetRenderOpacity(1) end)
        SetTextColor(b.title, notice and AMBER or GREY)
        SetTextColor(b.value, notice and WHITE or PALE_GREY)
        offUntil = os.clock() + (notice and 3 or 1.5)
        fade = 1
    end
    pcall(function() b.panel:SetVisibility(HIT_TEST_INVISIBLE) end)
    StartAnimation()
end

------------------------------------------------------------
-- Live readout
------------------------------------------------------------
local function CountOthers()
    local n = 0
    for _ in pairs(others) do n = n + 1 end
    return n
end

local function Status()
    if not myAddress then return "Not in a world yet", GREY end
    if Joined() then
        if hostAnswer == "denied" then return "Disabled by host", AMBER end
        if hostAnswer == "nomod" then return "Host doesn't have RadiationShield", AMBER end
        if hostAnswer == "asking" then return "Asking the host...", PALE_GREY end
        if hostAnswer == "allowed" then return "Allowed by host: your shield covers only you", PALE_GREEN end
        return "Joined game: press " .. boundKey .. " to ask the host", PALE_GREY
    end
    if not isHooked then return "Backup mode: radiation taken back each second", AMBER end
    if allowOthers then
        local n = CountOthers()
        return "Hosting: others may use shields (" .. n .. " on now)", PALE_GREEN
    end
    return mode == "shrink" and "Shield cuts radiation as it comes in"
        or "Shield takes radiation back as it comes in", PALE_GREEN
end

local function UpdateReadout()
    local p = ui.readout
    if not showDebug then
        if p then Show(p, false) end
        return
    end
    p = EnsurePanel("readout", 6, 0.0, 0.35, 24, 0, "RADIATION READOUT")
    if not p then return end
    local now, max = live.now, live.max
    SetText(p.lines[1], "Radiation:  " .. (now and string.format("%.1f", now) or "?")
        .. (max and string.format(" / %.0f", max) or ""))
    SetText(p.lines[2], string.format("Incoming:  +%.2f /s", live.raw))
    if isOn then
        SetText(p.lines[3], string.format("Shield removes:  -%.2f /s  (%d%%)", live.raw * reduction, Percent(reduction)))
    else
        SetText(p.lines[3], "Shield:  off")
    end
    SetText(p.lines[4], string.format("Actual change:  %+.2f /s", live.rose))
    local full = "-"
    if now and max and now >= max - 0.01 and live.rose >= -0.01 and live.raw > 0 then
        full = "AT MAXIMUM"
    elseif now and max and live.rose > 0.01 then
        full = string.format("%.0f s", (max - now) / live.rose)
    elseif now and live.rose > 0.01 then
        full = "rising"
    end
    SetText(p.lines[5], "Maximum in:  " .. full)
    SetTextColor(p.lines[5], full == "AT MAXIMUM" and RED or WHITE)
    local status, color = Status()
    SetText(p.lines[6], status)
    SetTextColor(p.lines[6], color)
    Show(p, true)
end

------------------------------------------------------------
-- The once-a-second check
------------------------------------------------------------
-- Runs while the shield, meter, readout or menu is on: re-finds the inventory
-- after a load, checks the reduction really happens (switching to take-back
-- if the game ignores the smaller amount), feeds the meter and the readout.
local UpdateMenu   -- defined with the menu below
local searchWait = 0

------------------------------------------------------------
-- Co-op messages
------------------------------------------------------------
-- Player -> host: APlayerController:ServerCheat("RSHIELD on 0.75"). Unreal
--   sends it to the host in every build; a shipping game ignores its text, the
--   host's mod reads it.
-- Host -> player: APlayerController:ClientMessage("... #RS:allowed"). Shows
--   as a line in that player's console; their mod reads the #RS: tag.
local SERVER_TAG = "RSHIELD"

local function ParamString(param)
    local value = param
    pcall(function() value = param:get() end)
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    return ok and s or ""
end

local function PlayerName(pc)
    local name = "a player"
    pcall(function() name = pc.PlayerState:GetPlayerName():ToString() end)
    return name
end

local function Tell(pc, tag, text)
    pcall(function() pc:ClientMessage("[RadiationShield] " .. text .. " #RS:" .. tag, FName("None"), 0.0) end)
end

-- Hosting: map each shielded player's current inventory to their reduction
RebuildOthers = function()
    local byInv, active = {}, false
    for key, o in pairs(others) do
        local inv = nil
        local okPc = pcall(function() if o.pc:IsValid() then inv = o.pc.Character.PlayerInventory end end)
        if not okPc or not o.pc:IsValid() then
            others[key] = nil   -- left the game
        elseif inv and inv:IsValid() then
            local address = AddressOf(inv)
            if address then byInv[address] = o.reduction; active = true end
        end
    end
    othersByInv, othersActive = byInv, active
end

-- Hosting: tell every player who joined (permission changed)
local function TellEveryone(tag, text)
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if not ctrl:IsLocalController() then Tell(ctrl, tag, text) end
        end
    end)
end
local function StartLoop()
    if isLoopRunning then return end
    isLoopRunning = true
    intake, lastSample = 0, nil
    LoopAsync(1000, function()
        if not (isOn or Measuring() or next(others)) then
            isLoopRunning = false
            return true
        end
        ExecuteInGameThread(function()
            local raw, hits = rawSecond, hitsSecond
            rawSecond, hitsSecond = 0, 0
            if next(others) then RebuildOthers() end   -- respawns give players new inventories
            -- not in a world (main menu, loading): search only every 5 s,
            -- each search walks every object in the game
            local inv = nil
            if myInventory or searchWait <= 0 then
                inv = RefreshMyInventory()
                searchWait = inv and 0 or 4
            else
                searchWait = searchWait - 1
            end
            if not inv then
                if menuOpen then UpdateMenu() end
                return
            end
            local now = ReadRadiation(inv)
            local max = ReadMax(inv)
            local rose = 0
            if now and lastSample then
                rose = now - lastSample
                if isOn and amHost then
                    if not isHooked and rose > 0 then
                        TakeBack(inv, rose * reduction)
                        now = now - rose * reduction
                        rose = rose * (1 - reduction)
                    elseif mode == "shrink" and intake > 1 and rose >= intake * 0.85 then
                        mode = "takeback"
                        log("The game ignored the smaller radiation amount; taking back "
                            .. Percent(reduction) .. "% after it's added instead")
                    end
                end
            end
            intake, lastSample = 0, now
            if meterOn and meter then MeterSecond(raw, hits, now, max, rose) end
            live.raw = live.raw * 0.4 + raw * 0.6
            live.rose = live.rose * 0.4 + rose * 0.6
            live.now, live.max = now, max
            UpdateReadout()
            if menuOpen then UpdateMenu() end
        end)
        return false
    end)
end

local function SetShield(on)
    isOn = on
    reportedWorking = false
    InstallHook()
    StartLoop()
    ExecuteInGameThread(function()
        local inv = RefreshMyInventory()
        if on then
            -- start the once-a-second check from the radiation right now
            intake, lastSample = 0, inv and ReadRadiation(inv) or nil
        end
        ShowIndicator(on)
        if menuOpen then UpdateMenu() end
    end)
    log("Radiation shield " .. (isOn and ("ON - " .. Percent(reduction) .. "% less radiation") or "OFF"))
end

-- Joined someone: the host's mod decides. Ask, and wait for the answer.
local askId = 0
local function AskHost(on)
    if not on then
        SetShield(false)
        pcall(function() myController:ServerCheat(SERVER_TAG .. " off") end)
        return
    end
    hostAnswer = "asking"
    askId = askId + 1
    local myAsk = askId
    local sent = pcall(function() myController:ServerCheat(SERVER_TAG .. " on " .. reduction) end)
    log("Asking the host to allow your radiation shield")
    -- no answer in 3 s: the host doesn't run this mod
    LoopAsync(3000, function()
        ExecuteInGameThread(function()
            if askId == myAsk and hostAnswer == "asking" then
                hostAnswer = "nomod"
                log("No answer from the host" .. (sent and "" or " (couldn't send)")
                    .. " - the host needs RadiationShield for shields in their world")
                ShowIndicator(false, "HOST HAS NO SHIELD MOD")
                if menuOpen then UpdateMenu() end
            end
        end)
        return true
    end)
end

-- HOME, .radshield and the menu all come here
local function ToggleTo(on)
    ExecuteInGameThread(function()
        RefreshMyInventory()
        if Joined() then AskHost(on) else SetShield(on) end
    end)
end

-- Host's answers, on a player who joined
local function OnClientMessage(selfParam, textParam)
    if not Joined() then return end   -- the host's own copies of its messages
    local text = ParamString(textParam)
    local tag = text:match("#RS:(%a+)%s*$")
    if not tag then return end
    if tag == "on" then
        hostAnswer = "allowed"
        if not isOn then SetShield(true) end
    elseif tag == "denied" then
        hostAnswer = "denied"
        if isOn then
            isOn = false
            log("Radiation shield OFF - disabled by the host")
        end
        ShowIndicator(false, "DISABLED BY HOST")
        log("The host has radiation shields disabled")
    elseif tag == "allowed" then
        hostAnswer = "allowed"
        log("The host allows radiation shields - press " .. boundKey .. " to use yours")
    end
    if menuOpen then UpdateMenu() end
end

-- A joined player's request, on the host
local function OnServerCheat(selfParam, msgParam)
    if Joined() then return end       -- only the host answers
    local msg = ParamString(msgParam)
    local cmd, value = msg:match("^" .. SERVER_TAG .. " (%a+)%s*([%d%.]*)")
    if not cmd then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not pc then return end
    local key = AddressOf(pc)
    if key == AddressOf(myController) then return end
    if cmd == "on" then
        if not allowOthers then
            Tell(pc, "denied", "Radiation shields are disabled by the host")
            log(PlayerName(pc) .. " asked for a radiation shield - disabled (Others can use it: NO)")
            return
        end
        local r = math.max(0.01, math.min(1, tonumber(value) or 0.25))
        others[key] = { pc = pc, reduction = r }
        RebuildOthers()
        StartLoop()
        Tell(pc, "on", "Radiation shield ON for you (" .. Percent(r) .. "% less radiation)")
        log(PlayerName(pc) .. " turned their radiation shield on (" .. Percent(r) .. "% less)")
    elseif cmd == "off" then
        if others[key] then log(PlayerName(pc) .. " turned their radiation shield off") end
        others[key] = nil
        RebuildOthers()
    end
    if menuOpen then UpdateMenu() end
end

for path, fn in pairs({
    ["/Script/Engine.PlayerController:ServerCheat"] = OnServerCheat,
    ["/Script/Engine.PlayerController:ClientMessage"] = OnClientMessage,
}) do
    if not pcall(RegisterHook, path, fn) then log("Co-op messages unavailable (" .. path .. ")") end
end

------------------------------------------------------------
-- Settings menu (.radmenu)
------------------------------------------------------------
local selected = 1
local function Cycle(list, current, dir)
    local index = 1
    for i, v in ipairs(list) do if v == current then index = i end end
    return list[(index - 1 + dir) % #list + 1]
end
local function PositionNames()
    local names = {}
    for i, p in ipairs(POSITIONS) do names[i] = p[1] end
    return names
end

local function Changed(what)
    if not SaveSettings() then log("Couldn't save " .. SETTINGS_PATH .. "; the change lasts until the game closes") end
    log("Setting changed: " .. what)
end

local CloseMenu
-- label, current value, change(direction: -1 left, 1 right)
local ROWS = {
    { "Shield", function() return isOn and "ON" or "OFF" end,
      function() ToggleTo(not isOn) end },
    { "Less radiation", function() return Percent(reduction) .. "%" end,
      function(dir)
          reduction = math.max(5, math.min(100, Percent(reduction) + 5 * dir)) / 100
          if isOn then ShowIndicator(true) end
          if isOn and Joined() then
              pcall(function() myController:ServerCheat(SERVER_TAG .. " on " .. reduction) end)
          end
          Changed("reduction " .. Percent(reduction) .. "%")
      end },
    { "Others can use it", function()
          if Joined() then
              return hostAnswer == "allowed" and "ALLOWED BY HOST" or (hostAnswer == "denied" and "DISABLED BY HOST" or "host decides")
          end
          return allowOthers and "YES" or "NO"
      end,
      function()
          if Joined() then
              log("Only the host can change this")
              return
          end
          allowOthers = not allowOthers
          if allowOthers then
              TellEveryone("allowed", "The host allows radiation shields - press your shield key to use yours")
          else
              others = {}
              RebuildOthers()
              TellEveryone("denied", "The host disabled radiation shields")
          end
          Changed("others can use it " .. (allowOthers and "yes" or "no"))
      end },
    { "Live readout", function() return showDebug and "ON" or "OFF" end,
      function()
          showDebug = not showDebug
          StartLoop()
          UpdateReadout()
          Changed("live readout " .. (showDebug and "on" or "off"))
      end },
    { "Badge", function() return showIndicator and "ON" or "OFF" end,
      function()
          showIndicator = not showIndicator
          if showIndicator then
              if isOn then ShowIndicator(true) end
          elseif ui.badge then
              Show(ui.badge, false)
          end
          Changed("badge " .. (showIndicator and "on" or "off"))
      end },
    { "Badge position", function() return badgePosition end,
      function(dir)
          badgePosition = Cycle(PositionNames(), badgePosition, dir)
          if ui.badge then
              pcall(function() ui.badge.panel:RemoveFromParent() end)
              ui.badge = nil
          end
          if isOn then ShowIndicator(true) end
          Changed("badge position " .. badgePosition)
      end },
    { "Shield on at start", function() return startOn and "YES" or "NO" end,
      function()
          startOn = not startOn
          Changed("shield on at start " .. (startOn and "yes" or "no"))
      end },
    { "Toggle key", function() return toggleKey .. (toggleKey ~= boundKey and " (after restart)" or "") end,
      function(dir)
          toggleKey = Cycle(KEY_CHOICES, toggleKey, dir)
          Changed("toggle key " .. toggleKey .. " from the next start")
      end },
    { "Close", function() return "" end, function() CloseMenu() end },
}

UpdateMenu = function()
    local p = EnsurePanel("menu", #ROWS + 3, 0.5, 0.5, 0, 0, "RADIATION SHIELD SETTINGS")
    if not p then return end
    for i, row in ipairs(ROWS) do
        local value = row[2]()
        local label = (i == selected and ">  " or "    ") .. row[1]
        if value ~= "" then label = label .. ":   < " .. value .. " >" end
        SetText(p.lines[i], label)
        SetTextColor(p.lines[i], i == selected and GREEN or WHITE)
    end
    local status, color = Status()
    SetText(p.lines[#ROWS + 1], " ")
    SetText(p.lines[#ROWS + 2], status)
    SetTextColor(p.lines[#ROWS + 2], color)
    SetText(p.lines[#ROWS + 3], "Up/Down: choose    Left/Right: change    .radmenu: close")
    SetTextColor(p.lines[#ROWS + 3], PALE_GREY)
    Show(p, true)
end

CloseMenu = function()
    menuOpen = false
    ExecuteInGameThread(function() if ui.menu then Show(ui.menu, false) end end)
    log("Menu closed")
end

local function OpenMenu()
    menuOpen = true
    InstallHook()
    StartLoop()
    ExecuteInGameThread(function()
        RefreshMyInventory()
        UpdateMenu()
        if not ui.menu then log("The menu needs the in-game HUD - load into a world first") end
    end)
    log("Menu open: arrow keys change settings, .radmenu closes it")
end

local function MenuKey(action)
    if not menuOpen then return end
    ExecuteInGameThread(function()
        if not menuOpen then return end
        if action == "up" then selected = (selected - 2) % #ROWS + 1
        elseif action == "down" then selected = selected % #ROWS + 1
        else ROWS[selected][3](action == "right" and 1 or -1) end
        if menuOpen then UpdateMenu() end
    end)
end

------------------------------------------------------------
-- Keys and console commands
------------------------------------------------------------
local okKey = pcall(function()
    RegisterKeyBind(Key[boundKey], function() ToggleTo(not isOn) end)
end)
if not okKey then log("Key '" .. tostring(boundKey) .. "' could not be bound; use .radshield instead") end
-- Arrow keys only do something while the menu is open
for keyName, action in pairs({ UP_ARROW = "up", DOWN_ARROW = "down", LEFT_ARROW = "left", RIGHT_ARROW = "right" }) do
    pcall(function() RegisterKeyBind(Key[keyName], function() MenuKey(action) end) end)
end

RegisterConsoleCommandHandler(".radshield", function(FullCommand, Parameters)
    local arg = string.lower((Parameters and Parameters[1]) or "")
    local percent = tonumber((arg:gsub("%%", "")))
    if percent then
        if percent < 1 or percent > 100 then
            log("Use a percentage from 1 to 100, e.g. .radshield 75")
            return true
        end
        reduction = percent / 100
        Changed("reduction " .. Percent(reduction) .. "%")
        ToggleTo(true)
        return true
    end
    if arg == "on" then ToggleTo(true)
    elseif arg == "off" then ToggleTo(false)
    else ToggleTo(not isOn) end
    return true
end)

RegisterConsoleCommandHandler(".radmenu", function()
    if menuOpen then CloseMenu() else OpenMenu() end
    return true
end)

RegisterConsoleCommandHandler(".radmeter", function()
    InstallHook()
    if meterOn then
        meterOn = false
        ExecuteInGameThread(function() MeterSummary() end)
        log("Radiation meter OFF")
    else
        meterOn = true
        meter = { seconds = 0, total = 0, peak = 0, highest = 0, max = nil, unhooked = 0 }
        StartLoop()
        log("Radiation meter ON - walk into the hot spot; .radmeter again for the summary")
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
            ui.hudObj = nil
            -- joined a world (or respawned) with the shield on: check with this host
            RefreshMyInventory()
            if isOn and Joined() then AskHost(true) end
            if isOn or Measuring() then RefreshMyInventory() end
            if isOn then ShowIndicator(true) end
            UpdateReadout()
            if menuOpen then UpdateMenu() end
        end)
        return true
    end)
    if isOn or Measuring() then StartLoop() end
end)

if isOn or showDebug then StartLoop() end
log("Loaded. Toggle with " .. boundKey .. " or .radshield (" .. Percent(reduction)
    .. "% less radiation, currently " .. (isOn and "ON" or "OFF") .. "); .radmenu for settings")
