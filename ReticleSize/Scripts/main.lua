------------------------------------------------------------
-- Reticle Size
------------------------------------------------------------
-- `.reticle 50` makes the crosshair dot half its size (10-400% of the
-- game's own; `.dot` works too). Saved to settings.txt.
--
-- The dot is found among the HUD's widgets by its name (crosshair, reticle,
-- dot) and scaled around its centre, so it stays in the middle. If it doesn't
-- change, `.reticle scan` lists the HUD widgets it could be, for the log.
--
-- Only your own screen changes, so it works the same in co-op.
------------------------------------------------------------
local VERSION = "1.0.0"
local DEFAULT_PERCENT = 100   -- used when there is no settings.txt
local SETTINGS_PATH = "./ue4ss/Mods/ReticleSize/settings.txt"
local MIN_PERCENT, MAX_PERCENT = 10, 400

local WORDS = { "crosshair", "cross_hair", "reticle", "reticule", "dot" }
local WIDGET_CLASSES = { "UserWidget", "Image", "Border", "SizeBox", "Overlay", "CanvasPanel" }

local percent = DEFAULT_PERCENT
local applyRunning = false

local function log(msg)
    print("[ReticleSize] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local function Load()
    local file = io.open(SETTINGS_PATH, "r")
    if not file then return end
    local value = tonumber((file:read("a") or ""):match("size%s*=%s*(%d+)"))
    file:close()
    if value then percent = math.max(MIN_PERCENT, math.min(MAX_PERCENT, value)) end
end

local function Save()
    local file = io.open(SETTINGS_PATH, "w")
    if not file then log("Couldn't save " .. SETTINGS_PATH) return end
    file:write("size=" .. percent .. "\n")
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

local function Matches(name)
    local lower = name:lower()
    for _, w in ipairs(WORDS) do
        if lower:find(w, 1, true) then return true end
    end
    return false
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

-- Returns how many widgets were scaled
local function Apply(verbose)
    local scale = percent / 100
    local done = 0
    for _, r in ipairs(FindReticles()) do
        pcall(function() r.widget:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        if pcall(function() r.widget:SetRenderScale({ X = scale, Y = scale }) end) then
            done = done + 1
            if verbose then log("  scaled " .. NameOf(r.widget) .. " (" .. r.path .. ")") end
        end
    end
    return done
end

-- After loading or respawning the HUD may not exist yet: try for up to 20 s
local function ApplySoon()
    if applyRunning then return end
    applyRunning = true
    local tries, done = 0, false
    LoopAsync(1000, function()
        if done or tries >= 20 then
            applyRunning = false
            return true
        end
        tries = tries + 1
        ExecuteInGameThread(function()
            if not done and Apply(false) > 0 then
                done = true
                if percent ~= 100 then log("Crosshair at " .. percent .. "%") end
            end
        end)
        return false
    end)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ApplySoon()
end)

------------------------------------------------------------
-- Scan: what the dot could be
------------------------------------------------------------
local function Scan()
    local matches = FindReticles()
    log("Scan: " .. #matches .. " widget(s) named like a crosshair:")
    for _, r in ipairs(matches) do log("  " .. NameOf(r.widget) .. "  (" .. r.path .. ")") end
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
local function Command(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        if a == "scan" then
            Scan()
        elseif a == "reset" or tonumber(a) then
            percent = a == "reset" and 100 or math.max(MIN_PERCENT, math.min(MAX_PERCENT, math.floor(tonumber(a) + 0.5)))
            Save()
            local done = Apply(true)
            if done > 0 then
                log("Crosshair at " .. percent .. "%")
            else
                log("Crosshair at " .. percent .. "% (saved) - no crosshair found yet; load a world, or try .reticle scan")
            end
        else
            log("Crosshair at " .. percent .. "% of the game's size. .reticle <" .. MIN_PERCENT .. "-" .. MAX_PERCENT
                .. "> | .reticle reset | .reticle scan")
        end
    end)
    return true
end
RegisterConsoleCommandHandler(".reticle", Command)
RegisterConsoleCommandHandler(".dot", Command)

Load()
log("Loaded v" .. VERSION .. ": crosshair at " .. percent .. "%. .reticle <percent> to change it")
