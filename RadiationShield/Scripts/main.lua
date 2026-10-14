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
-- Engine always has (ServerNotifyLoadedWorld to the host, ClientMessage back), so this
-- works whichever game adds the radiation. Everyone needs this mod.
------------------------------------------------------------
-- Defaults. The menu saves your choices to settings.txt in this mod's
-- folder; that file overrides these.
------------------------------------------------------------
-- Any UE4SS key name: HOME, END, INS, DEL, PAGE_DOWN, F8 ...
-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("RadiationShield")

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

-- Your own strength (saved). `reduction` is the one in effect: the same,
-- except in someone else's world, where the host's strength applies.
local myReduction = nil

local function SaveSettings()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then return false end
    file:write("# Radiation Shield settings - written by the .radmenu menu\n")
    file:write("reduction = " .. (myReduction or reduction) .. "\n")
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
myReduction = reduction
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
-- others[controller address] = { pc = controller } (they get the host's strength)
local others = {}
local othersByInv = {}     -- [inventory address] = reduction, for the hook
local othersInvObj = {}    -- [inventory address] = that player's inventory
local othersRaw = {}       -- [inventory address] = radiation the game sent them this second
-- Hosting: each shielded player's radiation a second ago, to catch radiation
-- that reaches them without passing the shield's hook ([address] = value)
local lastRadiation = {}
local reportedBypass = false
local othersActive = false
local intake, lastSample = 0, nil   -- shield check: radiation the game added since the last second
local rawSecond, hitsSecond = 0, 0  -- what the game sent this second, before the shield
local live = { raw = 0, rose = 0, now = nil, max = nil }   -- smoothed, for the readout
local meterOn = false
local meter = nil
local reportedWorking = false   -- one log line per switch-on, so the log shows it's acting

local function Measuring() return meterOn or showDebug or menuOpen end
local function Joined() return myController ~= nil and not amHost end

-- Calling anything on an object that doesn't exist (a missing owner,
-- character or player state) crashes the game outright - pcall can't catch
-- it - so every link in a chain is checked first.
local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
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
            if Valid(ctrl) and ctrl:IsLocalController() then
                myController = ctrl
                local character = ctrl.Character   -- none while dead or loading
                if Valid(character) then
                    local candidate = character.PlayerInventory
                    if Valid(candidate) then myInventory = candidate end
                end
                return
            end
        end
    end)
    myAddress = myInventory and AddressOf(myInventory) or nil
    if myInventory then
        local ok, authority = pcall(function()
            local owner = myInventory:GetOwner()
            if Valid(owner) then return owner:HasAuthority() end
        end)
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
-- The game adds radiation in whole numbers (hits of exactly 3.0, radiation
-- always N.0): a shrunk hit like 0.75 isn't added as 0.75, and below 100%
-- radiation built up faster than with no shield at all. Whole hits are shrunk
-- to whole numbers, carrying the remainder to the next hit: 3 at 75% less ->
-- 1, 1, 1, 0, ... = 0.75 on average. [inventory address] = remainder
local carry = {}
-- what the shield let through this second, per inventory ([address] = sum)
local passed = {}
local function Shrunk(address, amount, cut)
    local want = amount * (1 - cut)
    if amount ~= math.floor(amount) then return want end   -- fractional hits stay exact
    want = want + (carry[address] or 0)
    local whole = math.floor(want + 1e-9)
    carry[address] = want - whole
    return whole
end

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
    if mine then rawSecond, hitsSecond = rawSecond + amount, hitsSecond + 1
    elseif cut then othersRaw[address] = (othersRaw[address] or 0) + amount end
    if not cut then return end
    if mine then intake = intake + amount end
    if mode == "shrink" or not amHost then
        local shrunk = Shrunk(address, amount, cut)
        pcall(function() amountParam:set(shrunk) end)
        passed[address] = (passed[address] or 0) + shrunk
        if mine and not reportedWorking then
            reportedWorking = true
            log(string.format("Working: radiation hit %.3f reduced to %.3f%s", amount, shrunk,
                amount == math.floor(amount) and string.format(" (whole numbers, %.2f on average)", amount * (1 - cut)) or ""))
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
--   badge:   | RADIATION SHIELD / -25% RADIATION, blue bar
--   readout: radiation now, what comes in, what the shield removes, time to max
--   menu:    settings, changed with the arrow keys
local UMG = "/Script/UMG."
local HIT_TEST_INVISIBLE = 3   -- ESlateVisibility: shown, never blocks the mouse
local COLLAPSED = 1
-- Steel blue on dark navy. Unreal takes linear colours; the comments are
-- the colours you see.
local ACCENT = { R = 0.212, G = 0.445, B = 0.783, A = 1 }   -- steel blue #7FB2E5
local ACCENT_SOFT = { R = 0.205, G = 0.275, B = 0.381, A = 1 }   -- grey-blue #7D8FA6
local WHITE = { R = 0.791, G = 0.831, B = 0.888, A = 1 }   -- cool white #E6EBF2
local GREY = { R = 0.168, G = 0.212, B = 0.275, A = 1 }   -- #727F8F
local PALE_GREY = { R = 0.491, G = 0.552, B = 0.637, A = 1 }   -- #BAC4D1
local WARN = { R = 0.784, G = 0.462, B = 0.136, A = 1 }   -- soft amber #E5B567
local RED = { R = 0.745, G = 0.195, B = 0.147, A = 1 }   -- #E07A6B

local ui = { hud = nil, hudObj = nil }   -- widgets of the current HUD
local lastText = setmetatable({}, { __mode = "k" })   -- text each widget shows now
local indicatorWarned = false

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
    pcall(function() text:SetShadowOffset({ X = 0.0, Y = 1.0 }) end)
    pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.45 }) end)
end

local function Bold(text)
    pcall(function() text.Font.TypefaceFontName = FName("Bold") end)
end

-- Rounded corners: UE5 brushes can draw as a rounded box. No radius = a pill
-- (half the height). Only looks: if the game refuses, corners stay square.
local function Round(border, radius, outline)
    radius = 0   -- square look; kept as a switch should rounded corners come back
    pcall(function()
        local brush = border.Background
        brush.DrawAs = 4                      -- ESlateBrushDrawType::RoundedBox (draws the outline)
        local o = brush.OutlineSettings
        o.RoundingType = 0                    -- fixed radius
        local c = o.CornerRadii
        c.X, c.Y, c.Z, c.W = radius, radius, radius, radius
        if outline then
            o.Width = 1.0
            local c = o.Color.SpecifiedColor
            c.R, c.G, c.B, c.A = outline.R, outline.G, outline.B, outline.A
            o.Color.ColorUseRule = 0
        end
    end)
    return border
end

-- Panels are named, so a restarted copy of this mod (.reloadmods) can find
-- and remove the badge, readout and menu the previous copy left on the HUD.
-- The tag keeps names unique between copies: reusing a name would replace
-- the old widget in place, which the game doesn't survive.
local PANEL_PREFIX = "RadiationShieldPanel_"
local panelTag = string.format("%x%x", os.time(), math.floor(os.clock() * 1000))
local panelCount = 0
local leftoversRemoved = false
local function RemoveLeftovers()
    if leftoversRemoved then return end
    leftoversRemoved = true
    pcall(function()
        for _, w in ipairs(FindAllOf("Border") or {}) do
            local name = ""
            pcall(function() name = w:GetFName():ToString() end)
            if name:find(PANEL_PREFIX, 1, true) == 1 and not name:find(panelTag, 1, true) then
                pcall(function() w:RemoveFromParent() end)
            end
        end
    end)
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
    RemoveLeftovers()
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
    panelCount = panelCount + 1
    local panel = nil
    pcall(function()
        panel = StaticConstructObject(StaticFindObject(UMG .. "Border"), tree,
            FName(PANEL_PREFIX .. panelTag .. "_" .. panelCount))
    end)
    if not (panel and panel:IsValid()) then panel = Construct("Border", tree) end
    panel:SetBrushColor({ R = 0.006, G = 0.009, B = 0.015, A = alpha })   -- dark navy #121821
    return Round(panel, 10)
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
    b.accent = Round(Construct("Border", tree))
    b.accent:SetBrushColor(ACCENT)
    bar:SetContent(b.accent)
    local barSlot = row:AddChildToHorizontalBox(bar)
    pcall(function() barSlot:SetVerticalAlignment(2) end)   -- centre

    local column = Construct("VerticalBox", tree)
    local columnSlot = row:AddChildToHorizontalBox(column)
    pcall(function() columnSlot:SetPadding({ Left = 10, Top = 0, Right = 0, Bottom = 0 }) end)
    pcall(function() columnSlot:SetVerticalAlignment(2) end)

    b.title = Construct("TextBlock", tree)
    StyleText(b.title, 10, ACCENT_SOFT, 120)
    column:AddChildToVerticalBox(b.title)
    b.value = Construct("TextBlock", tree)
    StyleText(b.value, 17, WHITE)
    Bold(b.value)
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
    StyleText(p.title, 10, GREY, 120)
    Bold(p.title)
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

-- No animation on purpose: a timer waking the game thread many times a
-- second crashed UE4SS (its game-thread queue races with the timer thread).
-- The badge just shows; "SHIELD OFF" hides itself with one delayed call.
local hideToken = 0
local function HideLater(seconds)
    hideToken = hideToken + 1
    local token = hideToken
    LoopAsync(math.floor(seconds * 1000), function()
        ExecuteInGameThread(function()
            if token ~= hideToken or isOn then return end
            if ui.badge then Show(ui.badge, false) end
        end)
        return true   -- once
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
        pcall(function() b.accent:SetBrushColor(ACCENT) end)
        SetTextColor(b.title, ACCENT_SOFT)
        SetTextColor(b.value, WHITE)
        hideToken = hideToken + 1   -- cancels a pending hide
    else
        SetText(b.value, notice or "SHIELD OFF")
        pcall(function() b.accent:SetBrushColor(notice and WARN or GREY) end)
        SetTextColor(b.title, notice and WARN or GREY)
        SetTextColor(b.value, notice and WHITE or PALE_GREY)
        HideLater(notice and 3 or 1.5)
    end
    pcall(function() b.panel:SetVisibility(HIT_TEST_INVISIBLE) end)
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
        if hostAnswer == "denied" then return "Disabled by host", WARN end
        if hostAnswer == "nomod" then return "Host doesn't have RadiationShield", WARN end
        if hostAnswer == "asking" then return "Asking the host...", PALE_GREY end
        if hostAnswer == "allowed" then return "Allowed by host: your shield covers only you", ACCENT_SOFT end
        return "Joined game: press " .. boundKey .. " to ask the host", PALE_GREY
    end
    if not isHooked then return "Backup mode: radiation taken back each second", WARN end
    if allowOthers then
        local n = CountOthers()
        return "Hosting: others may use shields (" .. n .. " on now)", ACCENT_SOFT
    end
    return mode == "shrink" and "Shield cuts radiation as it comes in"
        or "Shield takes radiation back as it comes in", ACCENT_SOFT
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
    if Joined() then
        -- the host adds (and shields) a joined player's radiation: this game never sees it come in
        SetText(p.lines[2], "Incoming:  counted by the host")
        SetText(p.lines[3], (isOn and hostAnswer == "allowed")
            and string.format("Shield:  on, the host applies it  (%d%%)", Percent(reduction)) or "Shield:  off")
    elseif isOn then
        SetText(p.lines[2], string.format("Incoming:  +%.2f /s", live.raw))
        SetText(p.lines[3], string.format("Shield removes:  -%.2f /s  (%d%%)", live.raw * reduction, Percent(reduction)))
    else
        SetText(p.lines[2], string.format("Incoming:  +%.2f /s", live.raw))
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
-- Player -> host: APlayerController:ServerNotifyLoadedWorld(FName "RSHIELD_ON_75").
--   Unreal sends it to the host in every build; the game only acts on it
--   during a seamless level change (and then only on a real level's name), so
--   our name is ignored - the host's mod reads it. (ServerCheat, the obvious
--   choice, doesn't exist in this game's shipping build.)
-- Host -> player: APlayerController:ClientMessage("... #RS:allowed"). Shows
--   as a line in that player's console; their mod reads the #RS: tag.
local SERVER_TAG = "RSHIELD"

local function SendToHost(command)
    return pcall(function() myController:ServerNotifyLoadedWorld(FName(SERVER_TAG .. "_" .. command)) end)
end

local function ParamString(param)
    local value = param
    pcall(function() value = param:get() end)
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    return ok and s or ""
end

local function PlayerName(pc)
    local name = "a player"
    pcall(function()
        local state = pc.PlayerState
        if Valid(state) then name = state:GetPlayerName():ToString() end
    end)
    return name
end

local function Tell(pc, tag, text)
    pcall(function() pc:ClientMessage("[RadiationShield] " .. text .. " #RS:" .. tag, FName("None"), 0.0) end)
end

-- Hosting: map each shielded player's current inventory to the host's strength
RebuildOthers = function()
    local byInv, objs, active = {}, {}, false
    for key, o in pairs(others) do
        local inv = nil
        local okPc = pcall(function()
            if not Valid(o.pc) then return end
            local character = o.pc.Character
            if Valid(character) then inv = character.PlayerInventory end
        end)
        if not okPc or not Valid(o.pc) then
            others[key] = nil   -- left the game
        elseif Valid(inv) then
            local address = AddressOf(inv)
            if address then byInv[address] = reduction; objs[address] = inv; active = true end
        end
    end
    othersByInv, othersInvObj, othersActive = byInv, objs, active
end

-- Hosting, shield hooked: some radiation reaches a player without passing the
-- hook the shield cuts (the readout showed 100% removed, yet +4.9 /s). Each
-- second, whatever rose beyond what the shield let through (raw * (1 - cut))
-- is cut by the same share, through the game's own DecreaseRadiation (like
-- the mod menu): writing the value directly (1.6.4) left the game's other
-- radiation bookkeeping behind, and below 100% radiation then built up faster
-- than with no shield. Returns the radiation and the rise after that.
local function CutBypass(inv, address, raw, cut, through)
    local now = ReadRadiation(inv)
    if not now then return nil, 0 end
    local last = lastRadiation[address]
    local rose = last and (now - last) or 0
    if last then
        local extra = rose - (through or raw * (1 - cut))
        if extra > 0.01 and cut > 0 then
            local take = extra * cut
            if pcall(function() inv:DecreaseRadiation(take) end) then
                local after = ReadRadiation(inv) or math.max(0, now - take)
                rose = rose - (now - after)
                now = after
                if not reportedBypass then
                    reportedBypass = true
                    log(string.format("Radiation also rises outside the shield's hook (+%.2f /s here): taking %d%% of that back too",
                        extra, Percent(cut)))
                end
            end
        end
    end
    lastRadiation[address] = now
    return now, rose
end

-- Hosting: tell every player who joined (permission changed)
local function TellEveryone(tag, text)
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if not ctrl:IsLocalController() then Tell(ctrl, tag, text) end
        end
    end)
end
-- Hosting: the strength changed - players with their shield on follow
local function TellStrength()
    if not next(others) then return end
    RebuildOthers()
    for _, o in pairs(others) do
        Tell(o.pc, "on:" .. Percent(reduction),
            "The host set radiation shields to " .. Percent(reduction) .. "% less radiation")
    end
end

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

local loopIdle = true
local function StartLoop()
    if not loopIdle then return end
    loopIdle = false
    intake, lastSample = 0, nil
    if isLoopRunning then return end   -- the game-thread loop runs for good once started
    isLoopRunning = true
    GameLoop(1000, function()
        if loopIdle then return end
        if not (isOn or Measuring() or next(others)) then
            loopIdle = true
            return
        end
        do
            local raw, hits = rawSecond, hitsSecond
            rawSecond, hitsSecond = 0, 0
            local rawOthers = othersRaw
            othersRaw = {}
            local through = passed
            passed = {}
            if next(others) then RebuildOthers() end   -- respawns give players new inventories
            -- hosting: joined players with their shield on get the same bypass check
            local seen = {}
            if amHost and isHooked then
                for address, inv in pairs(othersInvObj) do
                    if Valid(inv) then
                        seen[address] = true
                        CutBypass(inv, address, rawOthers[address] or 0, othersByInv[address] or 0,
                            mode == "shrink" and (through[address] or 0) or nil)
                    end
                end
            end
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
            local rose, switched = 0, false
            if now and lastSample then
                rose = now - lastSample
                if isOn and amHost then
                    if not isHooked and rose > 0 then
                        TakeBack(inv, rose * reduction)
                        now = now - rose * reduction
                        rose = rose * (1 - reduction)
                    elseif mode == "shrink" and intake > 1 and rose >= intake * 0.85 then
                        mode, switched = "takeback", true
                        log("The game ignored the smaller radiation amount; taking back "
                            .. Percent(reduction) .. "% after it's added instead")
                    end
                end
            end
            if isOn and amHost and isHooked and myAddress and not switched then
                lastRadiation[myAddress] = lastRadiation[myAddress] or lastSample
                local fixedNow, fixedRose = CutBypass(inv, myAddress, raw, reduction,
                    mode == "shrink" and (through[myAddress] or 0) or nil)
                if fixedNow and lastSample then now, rose = fixedNow, fixedRose end
                seen[myAddress] = true
            end
            for address in pairs(lastRadiation) do
                if not seen[address] then lastRadiation[address] = nil end   -- shield off, left, respawned
            end
            intake, lastSample = 0, now
            if meterOn and meter then MeterSecond(raw, hits, now, max, rose) end
            live.raw = live.raw * 0.4 + raw * 0.6
            live.rose = live.rose * 0.4 + rose * 0.6
            live.now, live.max = now, max
            UpdateReadout()
            if menuOpen then UpdateMenu() end
        end
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
        SendToHost("OFF")
        return
    end
    hostAnswer = "asking"
    askId = askId + 1
    local myAsk = askId
    local sent = SendToHost("ON")
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
        if Joined() then
            AskHost(on)
        else
            reduction = myReduction   -- in your own world: your own strength
            SetShield(on)
        end
    end)
end

-- Host's answers, on a player who joined
local function OnClientMessage(selfParam, textParam)
    if not Joined() then return end   -- the host's own copies of its messages
    local text = ParamString(textParam)
    local tag, percent = text:match("#RS:(%a+):?(%d*)%s*$")
    if not tag then return end
    if tag == "on" then
        hostAnswer = "allowed"
        local hostPercent = tonumber(percent)
        if hostPercent and hostPercent >= 1 and hostPercent <= 100 then
            -- the host decides how strong shields are in their world
            local changed = isOn and Percent(reduction) ~= hostPercent
            reduction = hostPercent / 100
            if changed then
                log("The host set radiation shields to " .. hostPercent .. "% less radiation")
                ShowIndicator(true)
            end
        end
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
local function OnHostMessage(selfParam, msgParam)
    if Joined() then return end       -- only the host answers
    local msg = ParamString(msgParam)
    local cmd, value = msg:match("^" .. SERVER_TAG .. "_(%u+)_?(%d*)$")
    if not cmd then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not pc then return end
    local key = AddressOf(pc)
    if key == AddressOf(myController) then return end
    if cmd == "ON" then
        if not allowOthers then
            Tell(pc, "denied", "Radiation shields are disabled by the host")
            log(PlayerName(pc) .. " asked for a radiation shield - disabled (Others can use it: NO)")
            return
        end
        -- the host's strength, whatever the player asked for
        others[key] = { pc = pc }
        RebuildOthers()
        StartLoop()
        Tell(pc, "on:" .. Percent(reduction), "Radiation shield ON for you (" .. Percent(reduction) .. "% less radiation)")
        log(PlayerName(pc) .. " turned their radiation shield on (" .. Percent(reduction) .. "% less)")
    elseif cmd == "OFF" then
        if others[key] then log(PlayerName(pc) .. " turned their radiation shield off") end
        others[key] = nil
        RebuildOthers()
    end
    if menuOpen then UpdateMenu() end
end

for path, fn in pairs({
    ["/Script/Engine.PlayerController:ServerNotifyLoadedWorld"] = OnHostMessage,
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
    { "Shield", function() return isOn and "On" or "Off" end,
      function() ToggleTo(not isOn) end },
    { "Less radiation", function() return Percent(reduction) .. "%" end,
      function(dir)
          if Joined() then return end   -- the host sets it (row hidden anyway)
          reduction = math.max(5, math.min(100, Percent(reduction) + 5 * dir)) / 100
          myReduction = reduction
          if isOn then ShowIndicator(true) end
          TellStrength()
          Changed("reduction " .. Percent(reduction) .. "%")
      end },
    { "Others can use it", function()
          if Joined() then
              return hostAnswer == "allowed" and "Allowed by host" or (hostAnswer == "denied" and "Disabled by host" or "Host decides")
          end
          return allowOthers and "Yes" or "No"
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
    { "Live readout", function() return showDebug and "On" or "Off" end,
      function()
          showDebug = not showDebug
          StartLoop()
          UpdateReadout()
          Changed("live readout " .. (showDebug and "on" or "off"))
      end },
    { "Badge", function() return showIndicator and "On" or "Off" end,
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
    { "Shield on at start", function() return startOn and "Yes" or "No" end,
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

-- Rounded dark panel, settings grouped into cards, one accent colour:
--
--   Radiation Shield                              On  (==o)
--   Settings
--   SHIELD
--   .--------------------------------------------------.
--   | Shield                                  On (==o) |  <- selected row lit
--   | Less radiation               ====o-------   75%  |
--   '--------------------------------------------------'
--   CO-OP / DISPLAY / STARTUP cards ...
--   (                     Close                        )
--   o status
--   [UP / DOWN] select   [LEFT / RIGHT] change   [.radmenu] close
local SECTION_OF = { Shield = "SHIELD", ["Less radiation"] = "SHIELD", ["Others can use it"] = "CO-OP",
    ["Live readout"] = "DISPLAY", Badge = "DISPLAY", ["Badge position"] = "DISPLAY",
    ["Shield on at start"] = "STARTUP", ["Toggle key"] = "STARTUP" }
-- In someone else's world the host decides strength and sharing: only these
local JOINED_ROWS = { Shield = true, ["Live readout"] = true, Badge = true, ["Badge position"] = true,
    ["Toggle key"] = true, Close = true }
local function VisibleRows()
    local order = {}
    for i, row in ipairs(ROWS) do
        if not Joined() or JOINED_ROWS[row[1]] then table.insert(order, i) end
    end
    return order
end
local KIND = { ["Less radiation"] = "slider", ["Badge position"] = "choice", ["Toggle key"] = "choice", Close = "button" }
local SWITCH_STATE = { On = true, Yes = true, Off = false, No = false }   -- other values: text only
local MENU_WIDTH, ROW_HEIGHT, SLIDER_WIDTH = 440, 38, 120
local CLEAR = { R = 0, G = 0, B = 0, A = 0 }
local CARD = { R = 1, G = 1, B = 1, A = 0 }   -- no box behind sections
local BAND = { R = 0.212, G = 0.445, B = 0.783, A = 0.07 }   -- faint blue behind the title
local ROW_LIT = { R = 0.212, G = 0.445, B = 0.783, A = 0.12 }   -- faint blue on the chosen row
local BUTTON = { R = 1, G = 1, B = 1, A = 0.05 }
local TRACK = { R = 1, G = 1, B = 1, A = 0.12 }
local HAIRLINE = { R = 0.6, G = 0.7, B = 0.85, A = 0.10 }   -- faint outline
local LABEL = PALE_GREY
local BRIGHT = { R = 1, G = 1, B = 1, A = 1 }
local INK = { R = 0.004, G = 0.006, B = 0.010, A = 1 }   -- dark text on blue
local NO_SHADOW = { R = 0, G = 0, B = 0, A = 0 }

local function Box(tree, w, h, child)
    local box = Construct("SizeBox", tree)
    if w then box:SetWidthOverride(w) end
    if h then box:SetHeightOverride(h) end
    if child then box:SetContent(child) end
    return box
end

local function Fill(tree, color)
    local b = Construct("Border", tree)
    b:SetBrushColor(color)
    return b
end

local function Text(tree, size, color, spacing)
    local t = Construct("TextBlock", tree)
    StyleText(t, size, color, spacing)
    pcall(function() t:SetShadowColorAndOpacity(NO_SHADOW) end)   -- flat on the panel
    return t
end

local function Pad(slot, l, t, r, b)
    pcall(function() slot:SetPadding({ Left = l, Top = t, Right = r, Bottom = b }) end)
    return slot
end

local function Middle(slot) pcall(function() slot:SetVerticalAlignment(2) end) return slot end
local function Grow(slot) pcall(function() slot:SetSize({ SizeRule = 1, Value = 1.0 }) end) return slot end

-- A toggle switch: rounded track, white knob that sits right when on
local function Switch(tree)
    local s = {}
    s.track = Round(Fill(tree, TRACK))
    pcall(function() s.track:SetPadding({ Left = 3, Top = 3, Right = 3, Bottom = 3 }) end)
    local row = Construct("HorizontalBox", tree)
    s.gap = Box(tree, 0, 14)
    row:AddChildToHorizontalBox(s.gap)
    row:AddChildToHorizontalBox(Box(tree, 14, 14, Round(Fill(tree, BRIGHT))))
    s.track:SetContent(Box(tree, 32, 14, row))
    return s
end

local function SetSwitch(s, on)
    pcall(function() s.track:SetBrushColor(on and ACCENT or TRACK) end)
    pcall(function() s.gap:SetWidthOverride(on and 18 or 0) end)
end

local function BuildMenu(hud)
    local tree = hud.WidgetTree
    local m = { rows = {}, order = VisibleRows(), joined = Joined() }
    m.panel = DarkPanel(tree, 0.88)
    Round(m.panel, 0, HAIRLINE)
    pcall(function() m.panel:SetPadding({ Left = 14, Top = 14, Right = 14, Bottom = 12 }) end)
    local width = Construct("SizeBox", tree)
    pcall(function() width:SetWidthOverride(MENU_WIDTH) end)
    m.panel:SetContent(width)
    local column = Construct("VerticalBox", tree)
    width:SetContent(column)

    -- header: tinted band with the accent bar, title, and the shield's own switch
    local band = Fill(tree, BAND)
    pcall(function() band:SetPadding({ Left = 0, Top = 10, Right = 12, Bottom = 10 }) end)
    column:AddChildToVerticalBox(band)
    local head = Construct("HorizontalBox", tree)
    band:SetContent(head)
    m.accent = Fill(tree, ACCENT)
    Middle(head:AddChildToHorizontalBox(Box(tree, 3, 34, m.accent)))
    local titles = Construct("VerticalBox", tree)
    Middle(Grow(Pad(head:AddChildToHorizontalBox(titles), 12, 0, 0, 0)))
    m.title = Text(tree, 17, BRIGHT, 120)
    Bold(m.title)
    SetText(m.title, "RADIATION SHIELD")
    titles:AddChildToVerticalBox(m.title)
    m.sub = Text(tree, 9, ACCENT_SOFT, 260)
    Bold(m.sub)
    SetText(m.sub, "SETTINGS")
    titles:AddChildToVerticalBox(m.sub)
    m.stateText = Text(tree, 12, PALE_GREY)
    Middle(Pad(head:AddChildToHorizontalBox(m.stateText), 0, 0, 10, 0))
    m.switch = Switch(tree)
    Middle(head:AddChildToHorizontalBox(m.switch.track))

    -- settings, one card per section
    local card, lastSection
    for _, i in ipairs(m.order) do
        local row = ROWS[i]
        local kind = KIND[row[1]] or "switch"
        local section = SECTION_OF[row[1]]
        if section and section ~= lastSection then
            lastSection = section
            local heading = Text(tree, 9, ACCENT_SOFT, 200)
            Bold(heading)
            SetText(heading, section)
            Pad(column:AddChildToVerticalBox(heading), 6, 14, 0, 6)
            local frame = Round(Fill(tree, CARD), 10)
            pcall(function() frame:SetPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 }) end)
            column:AddChildToVerticalBox(frame)
            card = Construct("VerticalBox", tree)
            frame:SetContent(card)
        end
        local r = { kind = kind }
        r.bg = Round(Fill(tree, CLEAR), 8)
        pcall(function() r.bg:SetPadding({ Left = 12, Top = 0, Right = 12, Bottom = 0 }) end)
        if kind == "button" then
            Pad(column:AddChildToVerticalBox(r.bg), 0, 16, 0, 0)
        else
            card:AddChildToVerticalBox(r.bg)
        end
        local line = Construct("HorizontalBox", tree)
        r.bg:SetContent(Box(tree, nil, ROW_HEIGHT, line))
        r.marker = Fill(tree, CLEAR)
        Middle(Pad(line:AddChildToHorizontalBox(Box(tree, 3, ROW_HEIGHT - 12, r.marker)), 0, 0, 10, 0))
        r.label = Text(tree, 13, LABEL)
        SetText(r.label, row[1])
        local labelSlot = Middle(Grow(line:AddChildToHorizontalBox(r.label)))
        if kind == "button" then
            Bold(r.label)
            pcall(function() labelSlot:SetHorizontalAlignment(2) end)   -- centred
        elseif kind == "switch" then
            r.value = Text(tree, 12, GREY)
            Middle(Pad(line:AddChildToHorizontalBox(r.value), 0, 0, 10, 0))
            r.switch = Switch(tree)
            Middle(line:AddChildToHorizontalBox(r.switch.track))
        elseif kind == "slider" then
            local slider = Construct("HorizontalBox", tree)
            Middle(line:AddChildToHorizontalBox(slider))
            r.barFill = Box(tree, 0, 4, Round(Fill(tree, ACCENT)))
            r.barRest = Box(tree, SLIDER_WIDTH, 4, Round(Fill(tree, TRACK)))
            Middle(slider:AddChildToHorizontalBox(r.barFill))
            Middle(slider:AddChildToHorizontalBox(Box(tree, 12, 12, Round(Fill(tree, BRIGHT)))))
            Middle(slider:AddChildToHorizontalBox(r.barRest))
            r.value = Text(tree, 13, BRIGHT)
            Bold(r.value)
            pcall(function() r.value:SetJustification(2) end)   -- right
            Middle(line:AddChildToHorizontalBox(Box(tree, 52, nil, r.value)))
        else   -- choice
            r.left = Text(tree, 17, GREY)
            SetText(r.left, "\u{2039}")
            Middle(Pad(line:AddChildToHorizontalBox(r.left), 0, 0, 10, 0))
            r.value = Text(tree, 13, LABEL)
            Middle(line:AddChildToHorizontalBox(r.value))
            r.right = Text(tree, 17, GREY)
            SetText(r.right, "\u{203A}")
            Middle(Pad(line:AddChildToHorizontalBox(r.right), 10, 0, 0, 0))
        end
        m.rows[i] = r
    end

    -- footer: status with a coloured dot, then the keys as key caps
    local statusRow = Construct("HorizontalBox", tree)
    Pad(column:AddChildToVerticalBox(statusRow), 4, 14, 4, 0)
    m.dot = Round(Fill(tree, ACCENT))
    Middle(statusRow:AddChildToHorizontalBox(Box(tree, 8, 8, m.dot)))
    m.status = Text(tree, 12, LABEL)
    Middle(Pad(statusRow:AddChildToHorizontalBox(m.status), 8, 0, 0, 0))
    local hints = Construct("HorizontalBox", tree)
    Pad(column:AddChildToVerticalBox(hints), 4, 10, 4, 0)
    for _, hint in ipairs({ { "UP / DOWN", "select" }, { "LEFT / RIGHT", "change" }, { "BACKSPACE", "close" } }) do
        local cap = Round(Fill(tree, BUTTON), 4, HAIRLINE)
        pcall(function() cap:SetPadding({ Left = 6, Top = 2, Right = 6, Bottom = 2 }) end)
        local capText = Text(tree, 9, PALE_GREY, 60)
        Bold(capText)
        SetText(capText, hint[1])
        cap:SetContent(capText)
        Middle(hints:AddChildToHorizontalBox(cap))
        local what = Text(tree, 10, GREY)
        SetText(what, hint[2])
        Middle(Pad(hints:AddChildToHorizontalBox(what), 6, 0, 14, 0))
    end

    Attach(hud, m.panel, 0.5, 0.5, 0, 0, 102)
    return m
end

local function ValueColor(value)
    if value == "Disabled by host" then return WARN end
    if value == "Allowed by host" then return ACCENT end
    return GREY
end

UpdateMenu = function()
    local hud = GetHud()
    if not hud then return end
    if ui.menu and ui.menu.panel:IsValid() and ui.menu.joined ~= Joined() then
        -- became host / joined someone since it was built: other rows
        pcall(function() ui.menu.panel:RemoveFromParent() end)
        ui.menu, selected = nil, 1
    end
    if not (ui.menu and ui.menu.panel:IsValid()) then
        ui.menu = nil
        local ok, err = pcall(function() ui.menu = BuildMenu(hud) end)
        if not ok then Warn(err) return end
    end
    local m = ui.menu
    if m.joined then
        SetText(m.sub, hostAnswer == "allowed" and ("STRENGTH SET BY HOST: " .. Percent(reduction) .. "%")
            or "STRENGTH SET BY HOST")
    end
    SetText(m.stateText, isOn and "On" or "Off")
    pcall(function() m.accent:SetBrushColor(isOn and ACCENT or GREY) end)
    SetSwitch(m.switch, isOn)
    for n, i in ipairs(m.order) do
        local row = ROWS[i]
        local r = m.rows[i]
        local lit = n == selected
        pcall(function() r.marker:SetBrushColor(lit and r.kind ~= "button" and ACCENT or CLEAR) end)
        if r.kind == "button" then
            pcall(function() r.bg:SetBrushColor(lit and ACCENT or BUTTON) end)
            SetTextColor(r.label, lit and INK or BRIGHT)
        else
            pcall(function() r.bg:SetBrushColor(lit and ROW_LIT or CLEAR) end)
            SetTextColor(r.label, lit and BRIGHT or LABEL)
            local value = row[2]()
            SetText(r.value, value)
            if r.kind == "switch" then
                local state = SWITCH_STATE[value]
                -- a joined player sees the host's answer as text, without a switch
                pcall(function() r.switch.track:SetVisibility(state == nil and COLLAPSED or HIT_TEST_INVISIBLE) end)
                if state ~= nil then SetSwitch(r.switch, state) end
                SetTextColor(r.value, ValueColor(value))
            elseif r.kind == "choice" then
                SetTextColor(r.value, lit and BRIGHT or LABEL)
                SetTextColor(r.left, lit and ACCENT or GREY)
                SetTextColor(r.right, lit and ACCENT or GREY)
            else   -- slider
                local filled = math.floor(SLIDER_WIDTH * reduction + 0.5)
                pcall(function() r.barFill:SetWidthOverride(filled) end)
                pcall(function() r.barRest:SetWidthOverride(SLIDER_WIDTH - filled) end)
            end
        end
    end
    local status, color = Status()
    SetText(m.status, status)
    pcall(function() m.dot:SetBrushColor(color) end)
    Show(m, true)
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
        if action == "backspace" then CloseMenu() return end   -- one level only: Backspace closes it
        local order = ui.menu and ui.menu.order or VisibleRows()
        if action == "up" then selected = (selected - 2) % #order + 1
        elseif action == "down" then selected = selected % #order + 1
        else ROWS[order[selected]][3](action == "right" and 1 or -1) end
        if menuOpen then UpdateMenu() end
    end)
end

------------------------------------------------------------
-- Keys and console commands
------------------------------------------------------------
local okKey = pcall(function()
    -- a held key repeats: one press is one toggle, however long it's held
    local lastKeyAt = -1
    RegisterKeyBind(Key[boundKey], function()
        local now = os.clock()
        local repeated = now - lastKeyAt < 0.4
        lastKeyAt = now
        if not repeated then ToggleTo(not isOn) end
    end)
end)
if not okKey then log("Key '" .. tostring(boundKey) .. "' could not be bound; use .radshield instead") end
-- Arrow keys only do something while the menu is open
for keyName, action in pairs({ UP_ARROW = "up", DOWN_ARROW = "down", LEFT_ARROW = "left", RIGHT_ARROW = "right",
                               BACKSPACE = "backspace" }) do
    pcall(function() RegisterKeyBind(Key[keyName], function() MenuKey(action) end) end)
end

-- .radshield scan: every radiation-like number and function on your stats
-- component, for the log. Only numbers and true/false are read: reading other
-- kinds of values (links to objects, event lists) crashes UE4SS.
local SCAN_SAFE = { FloatProperty = true, DoubleProperty = true, IntProperty = true, BoolProperty = true,
                    ByteProperty = true }
local SCAN_WORDS = { "rad", "dose", "contam", "expos", "rate", "absorb", "resist", "protect" }

local function ScanWanted(name)
    local lower = name:lower()
    for _, w in ipairs(SCAN_WORDS) do
        if lower:find(w, 1, true) then return true end
    end
    return false
end

local function Scan()
    local inv = RefreshMyInventory()
    if not inv then log("Scan: load into a world first") return end
    log("Scan of your stats (" .. tostring(radiationField or "?") .. " is the radiation the shield reads):")
    local shown = 0
    pcall(function()
        inv:GetClass():ForEachProperty(function(prop)
            local name, kind = "", nil
            pcall(function() name = prop:GetFName():ToString() end)
            pcall(function() kind = prop:GetClass():GetFName():ToString() end)
            if name ~= "" and kind and SCAN_SAFE[kind] and ScanWanted(name) then
                local value = nil
                pcall(function() value = inv[name] end)
                shown = shown + 1
                log("  " .. name .. " = " .. tostring(value))
            end
        end)
    end)
    if shown == 0 then log("  (no radiation-like numbers found)") end
    local functions = {}
    pcall(function()
        inv:GetClass():ForEachFunction(function(fn)
            local name = ""
            pcall(function() name = fn:GetFName():ToString() end)
            if name:lower():find("rad", 1, true) then table.insert(functions, name) end
        end)
    end)
    log("  Functions: " .. (#functions > 0 and table.concat(functions, ", ") or "(none found)"))
    for _, fnName in ipairs({ "IncreaseRadiation", "DecreaseRadiation" }) do
        local params = {}
        pcall(function()
            local fn = StaticFindObject(INVENTORY_CLASS .. ":" .. fnName)
            if not Valid(fn) then return end
            fn:ForEachProperty(function(prop)
                local name, kind = "?", "?"
                pcall(function() name = prop:GetFName():ToString() end)
                pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                table.insert(params, name .. " (" .. kind .. ")")
            end)
        end)
        log("  " .. fnName .. ": " .. (#params > 0 and table.concat(params, ", ") or "(couldn't list)"))
    end
    log("Done - send these lines")
end

RegisterConsoleCommandHandler(".radshield", function(FullCommand, Parameters)
    local arg = string.lower((Parameters and Parameters[1]) or "")
    if arg == "scan" then
        ExecuteInGameThread(Scan)
        return true
    end
    local percent = tonumber((arg:gsub("%%", "")))
    if percent then
        if percent < 1 or percent > 100 then
            log("Use a percentage from 1 to 100, e.g. .radshield 75")
            return true
        end
        if Joined() then
            log("In someone else's world the host sets the strength - .radshield on/off still works")
            return true
        end
        reduction = percent / 100
        myReduction = reduction
        TellStrength()
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
            -- back in your own world: your own strength again, not the last host's
            if not Joined() and reduction ~= myReduction then
                reduction = myReduction
                if isOn then log("In your own world: " .. Percent(reduction) .. "% less radiation") end
            end
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
