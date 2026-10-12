------------------------------------------------------------
-- Survival Stats
------------------------------------------------------------
-- `.stats` shows or hides a small panel with your exact survival numbers
-- (health, stamina, hunger, thirst, radiation, insanity, ...), updated every
-- second. Off until you switch it on; the choice is saved to settings.txt.
--
--   .stats            on / off
--   .stats move       next position on the screen
--   .stats scan       every number your stats component has, for the log
--
-- It only reads your own numbers, nothing is changed, so it's safe in co-op.
------------------------------------------------------------
local VERSION = "1.0.0"
local SETTINGS_PATH = "./ue4ss/Mods/SurvivalStats/settings.txt"
local UPDATE_MS = 1000

-- Stats in the order shown. Each is looked for under a few likely names; the
-- first one that exists is used. Others named Current<Something> on the
-- stats component are shown after these.
local STATS = { "Health", "Stamina", "Hunger", "Thirst", "Radiation", "Insanity",
                "Fatigue", "Sleep", "Temperature", "BodyTemperature", "Energy", "Bleeding" }
local VALUE_NAMES = { "Current%s", "%s", "%sLevel", "Current%sLevel" }
local MAX_NAMES = { "Max%s", "Maximum%s", "%sMax", "Max%sLevel" }

-- name, anchorX, anchorY (0..1 across/down the screen), offsetX, offsetY (px)
local POSITIONS = {
    { "Left middle", 0.0, 0.5, 24, 0 },
    { "Top left", 0.0, 0.0, 24, 24 },
    { "Top right", 1.0, 0.0, -24, 24 },
    { "Right middle", 1.0, 0.5, -24, 0 },
    { "Bottom left", 0.0, 1.0, 24, -160 },
}

local show = false
local position = POSITIONS[1][1]
local loopRunning = false

local controller, inventory = nil, nil   -- kept while valid: finding them walks every object
local lastSearch = -100
local fields = nil                       -- { { label, value = name, max = name|nil } }, per inventory
local ui = {}
local lastText = setmetatable({}, { __mode = "k" })

local function log(msg)
    print("[SurvivalStats] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local text = file:read("a") or ""
    file:close()
    show = text:match("show%s*=%s*1") ~= nil
    local pos = text:match("position%s*=%s*([^\r\n]+)")
    for _, p in ipairs(POSITIONS) do if p[1] == pos then position = pos end end
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write("show=" .. (show and 1 or 0) .. "\nposition=" .. position .. "\n")
    file:close()
end

------------------------------------------------------------
-- Reading the numbers
------------------------------------------------------------
local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function Inventory()
    if Valid(inventory) then return inventory end
    inventory, fields = nil, nil
    -- The controller normally comes from the ClientRestart hook. Searching
    -- walks every object in the game, so it runs at most every 10 s.
    if not Valid(controller) and os.time() - lastSearch >= 10 then
        controller = nil
        lastSearch = os.time()
        pcall(function()
            for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
                if Valid(ctrl) and ctrl:IsLocalController() then controller = ctrl return end
            end
        end)
    end
    if not Valid(controller) then return nil end
    pcall(function()
        local character = controller.Character   -- none while dead or loading
        if Valid(character) and Valid(character.PlayerInventory) then inventory = character.PlayerInventory end
    end)
    return inventory
end

local function Number(obj, name)
    local ok, value = pcall(function() return obj[name] end)
    if ok and type(value) == "number" then return value end
    return nil
end

-- The stats component class's own number variables (walking parent classes
-- crashed this UE4SS build for the mod menu)
local function OwnNumbers(inv)
    local list = {}
    pcall(function()
        inv:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            if name ~= "" and Number(inv, name) then table.insert(list, name) end
        end)
    end)
    return list
end

local function Label(word)
    return (word:gsub("(%l)(%u)", "%1 %2"))   -- BodyTemperature -> Body Temperature
end

local function FindFields(inv)
    local list, used = {}, {}
    local function try(word)
        for _, pattern in ipairs(VALUE_NAMES) do
            local name = pattern:format(word)
            if not used[name] and Number(inv, name) then
                local max = nil
                for _, mp in ipairs(MAX_NAMES) do
                    local m = mp:format(word)
                    local v = Number(inv, m)
                    if v and v > 0 then max = m break end
                end
                used[name] = true
                if max then used[max] = true end
                table.insert(list, { label = Label(word), value = name, max = max })
                return
            end
        end
    end
    for _, word in ipairs(STATS) do try(word) end
    for _, name in ipairs(OwnNumbers(inv)) do
        local word = name:match("^Current(%u%w*)$")
        if word and not used[name] then try(word) end
    end
    return list
end

local function Format(value, max)
    local function n(x)
        if math.abs(x - math.floor(x + 0.5)) < 0.05 or math.abs(x) >= 100 then return string.format("%d", math.floor(x + 0.5)) end
        return string.format("%.1f", x)
    end
    if max and max > 0 then
        if max <= 1.0001 then return string.format("%d%%", math.floor(value / max * 100 + 0.5)) end
        return n(value) .. " / " .. n(max)
    end
    return n(value)
end

------------------------------------------------------------
-- The panel
------------------------------------------------------------
local UMG = "/Script/UMG."
local HIT_TEST_INVISIBLE, COLLAPSED = 3, 1
-- Steel blue on dark navy, like the Radiation Shield and the Mod Hub
local HEADING = { R = 0.205, G = 0.275, B = 0.381, A = 1 }   -- grey-blue #7D8FA6
local LABEL = { R = 0.491, G = 0.552, B = 0.637, A = 1 }     -- #BAC4D1
local WHITE = { R = 0.791, G = 0.831, B = 0.888, A = 1 }     -- cool white #E6EBF2
local PANEL = { R = 0.006, G = 0.009, B = 0.015, A = 0.72 }  -- dark navy #121821, see-through

local function Construct(className, outer, name)
    local cls = StaticFindObject(UMG .. className)
    if not Valid(cls) then error(className .. " class not found", 0) end
    local obj = nil
    if name then pcall(function() obj = StaticConstructObject(cls, outer, FName(name)) end) end
    if not Valid(obj) then obj = StaticConstructObject(cls, outer) end
    if not Valid(obj) then error("could not create " .. className, 0) end
    return obj
end

local function SetText(text, s)
    if lastText[text] == s then return end
    if not pcall(function() text:SetText(FText(s)) end) then pcall(function() text:SetText(s) end) end
    lastText[text] = s
end

local function Text(tree, s, size, color, bold, spacing)
    local t = Construct("TextBlock", tree)
    pcall(function() t.Font.Size = size end)
    if bold then pcall(function() t.Font.TypefaceFontName = FName("Bold") end) end
    if spacing then pcall(function() t.Font.LetterSpacing = spacing end) end
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    pcall(function() t:SetShadowOffset({ X = 0.0, Y = 1.0 }) end)
    pcall(function() t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.45 }) end)
    SetText(t, s)
    return t
end

local function GetHud()
    if Valid(ui.hudObj) then return ui.hudObj end
    local hud = nil
    pcall(function()
        local found = FindFirstOf("BP_InventoryHUD_C")
        if Valid(found) then hud = found end
    end)
    if not hud then return nil end
    ui = { hudObj = hud }   -- a new HUD (level load): build again there
    return hud
end

-- The panel is named, so a restarted copy of this mod (.reloadmods) finds
-- and removes the one the previous copy left. The tag keeps the copies'
-- names apart: reusing a name would replace the old widget in place, which
-- the game doesn't survive.
local PANEL_PREFIX = "SurvivalStatsPanel_"
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

local function PositionOf(name)
    for _, p in ipairs(POSITIONS) do if p[1] == name then return p end end
    return POSITIONS[1]
end

local function Build(hud, list)
    local tree = hud.WidgetTree
    panelCount = panelCount + 1
    local p = { values = {} }
    p.panel = Construct("Border", tree, PANEL_PREFIX .. panelTag .. "_" .. panelCount)
    p.panel:SetBrushColor(PANEL)
    pcall(function() p.panel:SetPadding({ Left = 12, Top = 8, Right = 14, Bottom = 10 }) end)
    local column = Construct("VerticalBox", tree)
    p.panel:SetContent(column)
    column:AddChildToVerticalBox(Text(tree, "SURVIVAL", 9, HEADING, true, 160))
    for i, f in ipairs(list) do
        local row = Construct("HorizontalBox", tree)
        local slot = column:AddChildToVerticalBox(row)
        pcall(function() slot:SetPadding({ Left = 0, Top = i == 1 and 5 or 1, Right = 0, Bottom = 0 }) end)
        local labelBox = Construct("SizeBox", tree)
        labelBox:SetWidthOverride(110)
        labelBox:SetContent(Text(tree, f.label, 12, LABEL))
        row:AddChildToHorizontalBox(labelBox)
        p.values[i] = Text(tree, "", 12, WHITE, true)
        row:AddChildToHorizontalBox(p.values[i])
    end

    local pos = PositionOf(position)
    local root = hud.WidgetTree.RootWidget
    local cls = ""
    pcall(function() cls = root:GetClass():GetFName():ToString() end)
    if cls == "CanvasPanel" then
        local slot = root:AddChildToCanvas(p.panel)
        pcall(function() slot:SetAnchors({ Minimum = { X = pos[2], Y = pos[3] }, Maximum = { X = pos[2], Y = pos[3] } }) end)
        pcall(function() slot:SetAlignment({ X = pos[2], Y = pos[3] }) end)
        pcall(function() slot:SetPosition({ X = pos[4], Y = pos[5] }) end)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(99) end)
    elseif cls == "Overlay" then
        local slot = root:AddChildToOverlay(p.panel)
        local h = pos[2] < 0.34 and 1 or (pos[2] > 0.66 and 3 or 2)
        local v = pos[3] < 0.34 and 1 or (pos[3] > 0.66 and 3 or 2)
        pcall(function() slot:SetHorizontalAlignment(h) end)
        pcall(function() slot:SetVerticalAlignment(v) end)
        pcall(function() slot:SetPadding({ Left = math.max(0, pos[4]), Top = math.max(0, pos[5]),
            Right = math.max(0, -pos[4]), Bottom = math.max(0, -pos[5]) }) end)
    else
        error("the HUD's root is a " .. cls, 0)
    end
    p.position, p.count = position, #list
    return p
end

local function Remove()
    if ui.p then pcall(function() ui.p.panel:RemoveFromParent() end) end
    ui.p = nil
end

local warned = false
-- Game thread: the panel shows the numbers now (built when needed)
local function Update()
    if not show then
        if ui.p then pcall(function() ui.p.panel:SetVisibility(COLLAPSED) end) end
        return
    end
    local inv = Inventory()
    local hud = GetHud()
    if not inv or not hud then
        if ui.p then pcall(function() ui.p.panel:SetVisibility(COLLAPSED) end) end
        return
    end
    RemoveLeftovers()
    if not fields then
        fields = FindFields(inv)
        local names = {}
        for _, f in ipairs(fields) do table.insert(names, f.label) end
        log(#fields > 0 and ("Showing " .. table.concat(names, ", "))
            or "Found no stats on your character - .stats scan lists what there is")
    end
    if #fields == 0 then return end
    if ui.p and (not Valid(ui.p.panel) or ui.p.position ~= position or ui.p.count ~= #fields) then Remove() end
    if not ui.p then
        local ok, p = pcall(Build, hud, fields)
        if not ok then
            if not warned then warned = true log("Panel unavailable (" .. tostring(p) .. ")") end
            return
        end
        ui.p = p
    end
    for i, f in ipairs(fields) do
        local value = Number(inv, f.value)
        local max = f.max and Number(inv, f.max) or nil
        SetText(ui.p.values[i], value and Format(value, max) or "-")
    end
    pcall(function() ui.p.panel:SetVisibility(HIT_TEST_INVISIBLE) end)
end

-- Every second while it's shown; stops when it's hidden
local function StartLoop()
    if loopRunning then return end
    loopRunning = true
    LoopAsync(UPDATE_MS, function()
        if not show then
            loopRunning = false
            ExecuteInGameThread(function() pcall(Update) end)   -- hides it
            return true
        end
        ExecuteInGameThread(function() pcall(Update) end)
        return false
    end)
end

------------------------------------------------------------
-- Scan
------------------------------------------------------------
local function Scan()
    local inv = Inventory()
    if not inv then log("Scan: no character yet - load into a world first") return end
    local names = OwnNumbers(inv)
    table.sort(names)
    log("Scan: " .. #names .. " number(s) on your stats component:")
    for _, name in ipairs(names) do log(string.format("  %s = %s", name, tostring(Number(inv, name)))) end
    local shown = FindFields(inv)
    log("Scan: shown in the panel:")
    for _, f in ipairs(shown) do log("  " .. f.label .. " (" .. f.value .. (f.max and (" of " .. f.max) or "") .. ")") end
    log("Send these lines if a stat is missing or wrong")
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
RegisterConsoleCommandHandler(".stats", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
            return
        elseif a == "move" then
            for i, p in ipairs(POSITIONS) do
                if p[1] == position then position = POSITIONS[i % #POSITIONS + 1][1] break end
            end
            show = true
            log("Stats panel: " .. position)
        elseif a == "on" then
            show = true
        elseif a == "off" then
            show = false
        elseif a == "" then
            show = not show
        else
            log(".stats (on / off) | .stats move | .stats scan")
            return
        end
        Save()
        if a ~= "move" then log("Stats panel " .. (show and "on" or "off")) end
        pcall(Update)
        if show then StartLoop() end
    end)
    return true
end)

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(selfParam)
    inventory, fields = nil, nil   -- a new character (respawn, level)
    pcall(function()
        local pc = selfParam:get()
        if Valid(pc) and pc:IsLocalController() then controller = pc end
    end)
end)

Load()
if show then StartLoop() end
log("Loaded v" .. VERSION .. ": panel " .. (show and "on" or "off") .. ". .stats shows / hides it")
