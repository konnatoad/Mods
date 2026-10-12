------------------------------------------------------------
-- Reticle Size
------------------------------------------------------------
-- `.reticle 50` makes the crosshair dot half its size (10-400% of the
-- game's own; `.dot` works too). Saved to settings.txt.
--
-- `.reticle color red` (or a hex colour like ff8800, with alpha ff880080)
-- colours it, `.reticle alpha 50` makes it half see-through, and
-- `.reticle color reset` gives back the game's colour.
--
-- The dot is found among the HUD's widgets by its name (crosshair, reticle,
-- dot) and scaled around its centre, so it stays in the middle. Its colour
-- goes on the images inside it. If it doesn't change, `.reticle scan` lists
-- the HUD widgets it could be, for the log.
--
-- Only your own screen changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.1.0"
local DEFAULT_PERCENT = 100   -- used when there is no settings.txt
local SETTINGS_PATH = "./ue4ss/Mods/ReticleSize/settings.txt"
local MIN_PERCENT, MAX_PERCENT = 10, 400

local WORDS = { "crosshair", "cross_hair", "reticle", "reticule", "dot" }
local WIDGET_CLASSES = { "UserWidget", "Image", "Border", "SizeBox", "Overlay", "CanvasPanel" }
local NAMED = {
    white = "ffffff", red = "ff2020", green = "20ff40", blue = "3080ff", yellow = "ffe020",
    cyan = "20f0ff", magenta = "ff30ff", pink = "ff80c0", orange = "ff8820", black = "000000",
}

local percent = DEFAULT_PERCENT
local rgb = nil               -- nil = the game's own colour; else { r, g, b } 0-255 as you see them
local alpha = nil             -- nil = the game's own; else 0-255 (255 = solid)
local applyRunning = false
local original = {}           -- each image's own colour (by path), to put back

local function log(msg)
    print("[ReticleSize] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Colours
------------------------------------------------------------
-- "ff8800" / "#ff880080" / a name -> { r, g, b }, alpha (nil when none is given)
local function ParseColor(text)
    text = tostring(text or ""):lower():gsub("^#", "")
    if NAMED[text] then text = NAMED[text] end
    if not (text:match("^%x%x%x%x%x%x$") or text:match("^%x%x%x%x%x%x%x%x$")) then return nil end
    local c = {}
    for i = 1, #text, 2 do table.insert(c, tonumber(text:sub(i, i + 1), 16)) end
    return { c[1], c[2], c[3] }, c[4]
end

-- "colour ff8800, 50% solid" for the log
local function Describe()
    local parts = {}
    table.insert(parts, rgb and string.format("colour %02x%02x%02x", rgb[1], rgb[2], rgb[3]) or "the game's colour")
    if alpha then table.insert(parts, string.format("%d%% solid", math.floor(alpha / 255 * 100 + 0.5))) end
    return table.concat(parts, ", ")
end

-- Unreal takes linear colours; hex colours are as you see them (sRGB)
local function Linear(v)
    v = v / 255
    if v <= 0.04045 then return v / 12.92 end
    return ((v + 0.055) / 1.055) ^ 2.4
end

-- Ours over the image's own colour (its own where we set nothing)
local function Wanted(own)
    return { R = rgb and Linear(rgb[1]) or own.R, G = rgb and Linear(rgb[2]) or own.G,
             B = rgb and Linear(rgb[3]) or own.B, A = alpha and alpha / 255 or own.A }
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local text = file:read("a") or ""
    file:close()
    local value = tonumber(text:match("size%s*=%s*(%d+)"))
    if value then percent = math.max(MIN_PERCENT, math.min(MAX_PERCENT, value)) end
    rgb = ParseColor(text:match("color%s*=%s*(%x+)"))
    local a = tonumber(text:match("alpha%s*=%s*(%d+)"))
    if a then alpha = math.max(0, math.min(255, a)) end
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write("size=" .. percent .. "\n")
    if rgb then file:write(string.format("color=%02x%02x%02x\n", rgb[1], rgb[2], rgb[3])) end
    if alpha then file:write("alpha=" .. alpha .. "\n") end
    file:close()
end

------------------------------------------------------------
-- Finding the dot
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

-- "Image /Engine/Transient...WD_Crosshair_C_1.WidgetTree.Dot" -> the path part
local function PathOf(obj)
    local full = ""
    pcall(function() full = obj:GetFullName() end)
    return full:match("^%S+%s+(.+)$") or full
end

local function ClassOf(obj)
    local full = ""
    pcall(function() full = obj:GetFullName() end)
    return full:match("^(%S+)") or ""
end

-- "dot" only as a word of its own (Dot, CenterDot, Aim_Dot), so that names
-- like "Antidote" don't count
local function Matches(name)
    local lower = name:lower()
    for _, w in ipairs(WORDS) do
        if w ~= "dot" and lower:find(w, 1, true) then return true end
    end
    return name:find("^[Dd][Oo][Tt]") ~= nil or name:find("[_%s%-][Dd][Oo][Tt]") ~= nil
        or name:find("[%l%d]Dot") ~= nil or name:find("DOT") ~= nil
end

-- Live widgets (not the game's templates) whose own name matches, outermost
-- only: a crosshair widget is scaled once, not again through its parts.
local function FindReticles()
    local found, seen = {}, {}
    for _, cls in ipairs(WIDGET_CLASSES) do
        pcall(function()
            for _, w in ipairs(FindAllOf(cls) or {}) do
                local path = PathOf(w)
                if Valid(w) and not seen[path] and path:find("^/Engine/Transient") and Matches(NameOf(w)) then
                    seen[path] = true
                    table.insert(found, { widget = w, path = path })
                end
            end
        end)
    end
    local outer = {}
    for _, a in ipairs(found) do
        local inside = false
        for _, b in ipairs(found) do
            if a ~= b and a.path:sub(1, #b.path + 1) == b.path .. "." then inside = true break end
        end
        if not inside then table.insert(outer, a) end
    end
    return outer
end

-- The images that draw the crosshair: the widget itself if it's an image,
-- otherwise the images inside it
local function Images(reticles)
    local list = {}
    local prefixes = {}
    for _, r in ipairs(reticles) do
        if ClassOf(r.widget) == "Image" then
            table.insert(list, { widget = r.widget, path = r.path })
        else
            table.insert(prefixes, r.path .. ".")
        end
    end
    if #prefixes > 0 then
        pcall(function()
            for _, img in ipairs(FindAllOf("Image") or {}) do
                local path = PathOf(img)
                for _, p in ipairs(prefixes) do
                    if Valid(img) and path:sub(1, #p) == p then table.insert(list, { widget = img, path = path }) break end
                end
            end
        end)
    end
    return list
end

local function ReadColor(img)
    local c = nil
    pcall(function()
        local v = img.ColorAndOpacity
        c = { R = v.R, G = v.G, B = v.B, A = v.A }
    end)
    return c
end

local function Paint(images)
    local done = 0
    for _, i in ipairs(images) do
        if not original[i.path] then original[i.path] = ReadColor(i.widget) or { R = 1, G = 1, B = 1, A = 1 } end
        local want = Wanted(original[i.path])
        if pcall(function() i.widget:SetColorAndOpacity(want) end) then done = done + 1 end
    end
    return done
end

-- Returns how many widgets were scaled
local function Apply(verbose)
    local scale = percent / 100
    local done = 0
    local reticles = FindReticles()
    for _, r in ipairs(reticles) do
        pcall(function() r.widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        if pcall(function() r.widget:SetRenderScale({ X = scale, Y = scale }) end) then
            done = done + 1
            if verbose then log("  scaled " .. NameOf(r.widget) .. " (" .. r.path .. ")") end
        end
    end
    -- colour only when there's one to set or put back (looking for the
    -- images walks every object again)
    if done > 0 and (rgb or alpha or next(original)) then
        local painted = Paint(Images(reticles))
        if verbose and (rgb or alpha) then log("  coloured " .. painted .. " image(s)") end
    end
    return done
end

-- After loading or respawning the HUD may not exist yet: try for up to 20 s
-- Each try walks every object in the game a few times (a short hitch), so
-- only at these seconds after the load, not every second.
local TRY_AT = { [1] = true, [3] = true, [6] = true, [10] = true, [20] = true }
local function ApplySoon()
    if applyRunning then return end
    applyRunning = true
    local seconds, done = 0, false
    LoopAsync(1000, function()
        if done or seconds >= 20 then
            applyRunning = false
            return true
        end
        seconds = seconds + 1
        if not TRY_AT[seconds] then return false end
        ExecuteInGameThread(function()
            if not done and Apply(false) > 0 then
                done = true
                if percent ~= 100 or rgb or alpha then log("Crosshair at " .. percent .. "%, " .. Describe()) end
            end
        end)
        return false
    end)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    original = {}   -- a new HUD: its images' own colours are read again
    ApplySoon()
end)

------------------------------------------------------------
-- Scan: what the dot could be
------------------------------------------------------------
local function Scan()
    local matches = FindReticles()
    log("Scan: " .. #matches .. " widget(s) named like a crosshair:")
    for _, r in ipairs(matches) do log("  " .. NameOf(r.widget) .. "  (" .. r.path .. ")") end
    for _, i in ipairs(Images(matches)) do
        local c = ReadColor(i.widget)
        log(string.format("  image %s colour %s", NameOf(i.widget),
            c and string.format("%.2f %.2f %.2f %.2f", c.R, c.G, c.B, c.A) or "?"))
    end
    -- every live image, for when the dot has another name
    local images = {}
    pcall(function()
        for _, w in ipairs(FindAllOf("Image") or {}) do
            local path = PathOf(w)
            if Valid(w) and path:find("^/Engine/Transient") then
                local visible = nil
                pcall(function() visible = w:IsVisible() end)
                if visible ~= false then table.insert(images, path) end
            end
        end
    end)
    table.sort(images)
    log("Scan: " .. #images .. " visible image(s) on screen" .. (#images > 80 and " (first 80)" or "") .. ":")
    for i = 1, math.min(#images, 80) do log("  " .. images[i]) end
    log("Send these lines if .reticle doesn't change the dot")
end

------------------------------------------------------------
-- Console
------------------------------------------------------------
local function Report(done)
    local what = "Crosshair at " .. percent .. "%, " .. Describe()
    if done > 0 then
        log(what)
    else
        log(what .. " (saved) - no crosshair found yet; load a world, or try .reticle scan")
    end
end

local function Help()
    log("Crosshair at " .. percent .. "% of the game's size, " .. Describe()
        .. ". .reticle <" .. MIN_PERCENT .. "-" .. MAX_PERCENT .. "> | .reticle reset | .reticle color <name or hex>"
        .. " | .reticle alpha <0-100> | .reticle color reset | .reticle scan")
end

local function Command(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    local b = tostring((Parameters and Parameters[2]) or "")
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        elseif a == "color" or a == "colour" then
            if b:lower() == "reset" then
                rgb, alpha = nil, nil
            else
                local c, a = ParseColor(b)
                if not c then
                    log("Not a colour: '" .. b .. "'. A name (white, red, green, blue, yellow, cyan, magenta, pink, orange,"
                        .. " black) or hex like ff8800, with alpha ff880080")
                    return
                end
                rgb = c
                if a then alpha = a end
            end
            Save()
            Report(Apply(true))
        elseif a == "alpha" or a == "opacity" then
            local n = tonumber(b)
            if not n then log(".reticle alpha <0-100>: how see-through (100 = solid)") return end
            alpha = math.floor(math.max(0, math.min(100, n)) / 100 * 255 + 0.5)
            Save()
            Report(Apply(true))
        elseif a == "reset" or tonumber(a) then
            percent = a == "reset" and 100 or math.max(MIN_PERCENT, math.min(MAX_PERCENT, math.floor(tonumber(a) + 0.5)))
            Save()
            Report(Apply(true))
        else
            Help()
        end
    end)
    return true
end
RegisterConsoleCommandHandler(".reticle", Command)
RegisterConsoleCommandHandler(".dot", Command)

Load()
log("Loaded v" .. VERSION .. ": crosshair at " .. percent .. "%, " .. Describe()
    .. ". .reticle <percent> / .reticle color <colour> to change it")
