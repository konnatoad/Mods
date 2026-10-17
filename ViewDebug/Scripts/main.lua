------------------------------------------------------------
-- View Debug
------------------------------------------------------------
-- For the game's bug where the weapon / arms (the viewmodel) get stuck at an
-- angle after moving the mouse slowly. Changes nothing: it only reads your
-- view's angles and writes them down, so a later mod can fix it.
--
--   .view                 your view's angles now, in the log
--   .view hud             show / hide the angles on screen, live (top right)
--   .view scan            everything on your character that turns: its parts
--                         and their angles, plus every number setting that
--                         looks like aim / sway / rotation (scan_<time>.txt)
--   .view buffer [s]      keep the last 25 s of angles (on / off)
--   .view dump            save them now to buffer_<time>.csv (or the hotkey,
--                         if set: saves 2 s later, so the stuck moment is in it)
--   .view dumps           list the saved dumps, newest first
--   .view read [n|name]   show a dump on screen: its walls (mouse moving, aim
--                         stuck), at what angle, for how long; again closes it
--   .view raw [seconds]   the dump's recorded rows on screen, a page at a
--                         time (left / right arrow, or .view next / .view prev);
--                         STUCK marks a wall
--   .view close           close the dump on screen (or press Backspace)
--   .view rec [seconds]   record the angles many times a second to
--                         recording_<time>.csv (stops by itself)
--   .view stop            stop recording / the buffer
--   .view mark [note]     mark this moment (markKey in config.lua adds a hotkey)
--   .view watch           print the main angles to the log 4 times a second
--   .view limits          the camera's angle limits now (yaw / pitch min and
--                         max); the buffer records them and logs each change
--
-- Settings: config.lua (see config.example.lua).
-- Only reads while recording, buffering, showing or watching, every frame
-- on the game thread (never from a background timer).
------------------------------------------------------------
-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("ViewDebug")

local VERSION = "0.6.6"
local MOD_DIR = "./ue4ss/Mods/ViewDebug/"

local function log(msg)
    print("[ViewDebug] " .. tostring(msg) .. "\n")
end

local function UserConfig()
    local path = MOD_DIR .. "config.lua"
    local file = io.open(path, "r")
    if not file then return {} end
    file:close()
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then return result end
    log("config.lua ignored: " .. (ok and "it doesn't return a table" or tostring(result)))
    return {}
end

local cfg = UserConfig()
local SAMPLE_MS = math.max(10, math.floor(tonumber(cfg.sampleMs) or 16))
local MAX_SECONDS = math.min(600, math.max(5, tonumber(cfg.maxSeconds) or 60))
local BUFFER_SECONDS = math.min(60, math.max(2, tonumber(cfg.bufferSeconds) or 25))
local MARK_KEY = tostring(cfg.markKey or "")   -- "" = no hotkey (the default)
-- "F12 or .view mark" when there's a hotkey, else ".view mark"
local MARK_HOW = MARK_KEY ~= "" and (MARK_KEY .. " or .view mark") or ".view mark"
local HUD_MS = math.max(30, math.floor(tonumber(cfg.hudMs) or 100))
local WATCH_SECONDS = 120
local MAX_COMPONENTS = 40
local MAX_PROPS_PER_OBJECT = 60

-- Names of settings worth recording (lower case parts of the name)
local KEYWORDS = { "sway", "lag", "rot", "aim", "look", "pitch", "yaw", "roll", "lean", "recoil",
                   "offset", "interp", "delta", "turn", "mouse", "input", "view", "camera", "cam",
                   "bob", "tilt", "angle", "ads", "weapon", "hand", "arm", "fov", "inertia", "speed" }

------------------------------------------------------------
-- Reading the game
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

local function ClassName(obj)
    local name = ""
    pcall(function() name = obj:GetClass():GetFName():ToString() end)
    return name
end

-- Arrays come back as Lua tables on this UE4SS (elements maybe wrapped)
local function Each(array, fn)
    if type(array) == "table" then
        for _, raw in pairs(array) do
            local v = raw
            pcall(function() if raw.get then v = raw:get() end end)
            fn(v)
        end
    elseif array then
        pcall(function() array:ForEach(function(_, e) fn(e:get()) end) end)
    end
end

local function LocalController()
    local found = nil
    pcall(function()
        for _, pc in ipairs(FindAllOf("BP_SGKController_C") or FindAllOf("PlayerController") or {}) do
            if pc:IsValid() and pc:IsLocalController() then found = pc return end
        end
    end)
    return found
end

-- Short name for a property name: drops the "_17_5654B3..." the editor adds
local function Short(name)
    return (name:gsub("_%d+_%x+$", ""))
end

local function Wanted(name)
    local lower = name:lower()
    for _, k in ipairs(KEYWORDS) do
        if lower:find(k, 1, true) then return true end
    end
    return false
end

-- What a value read from the game is: "number", "bool", "rot", "vec", "vec2" or nil
local function Kind(v)
    local t = type(v)
    if t == "number" then return "number" end
    if t == "boolean" then return "bool" end
    if t ~= "userdata" and t ~= "table" then return nil end
    local ok, p = pcall(function() return v.Pitch end)
    if ok and type(p) == "number" then return "rot" end
    local okx, x = pcall(function() return v.X end)
    if okx and type(x) == "number" then
        local okz, z = pcall(function() return v.Z end)
        if okz and type(z) == "number" then return "vec" end
        return "vec2"
    end
    return nil
end

-- Setting types that are safe to read. Reading some others (links to
-- objects, event lists, ...) crashes this UE4SS build, so a setting is only
-- read once its type is known to be one of these.
local SAFE_TYPES = { FloatProperty = "number", DoubleProperty = "number", IntProperty = "number",
                     BoolProperty = "bool" }
local SAFE_STRUCTS = { Rotator = "rot", Vector = "vec", Vector2D = "vec2" }
local typesUnknownWarned = false

local function KindOfProperty(prop)
    local t = nil
    pcall(function() t = prop:GetClass():GetFName():ToString() end)
    if not t then return nil, false end
    if SAFE_TYPES[t] then return SAFE_TYPES[t], true end
    if t == "StructProperty" then
        local st = nil
        pcall(function() st = prop:GetStruct():GetFName():ToString() end)
        return st and SAFE_STRUCTS[st] or nil, true
    end
    return nil, true
end

-- The object class's own settings (only its own class: walking parent
-- classes crashed this UE4SS build for the mod menu). fn(name, value, kind)
local function EachSetting(obj, fn)
    local unknown = 0
    pcall(function()
        obj:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            local kind, known = KindOfProperty(prop)
            if not known then unknown = unknown + 1 end
            if name ~= "" and kind then
                local value = nil
                pcall(function() value = obj[name] end)
                if Kind(value) == kind then fn(name, value, kind) end
            end
        end)
    end)
    if unknown > 0 and not typesUnknownWarned then
        typesUnknownWarned = true
        log("Couldn't tell the type of " .. unknown .. " settings, so they're skipped (reading the wrong type crashes)")
    end
end

-- The character's parts and everything attached to them (the held weapon's
-- parts too), following the attachment tree from the root
local function ComponentTree(pawn)
    local list, seen = {}, {}
    local function walk(comp, depth)
        if #list >= MAX_COMPONENTS or not Valid(comp) then return end
        local key = tostring(comp)
        pcall(function() key = tostring(comp:GetAddress()) end)
        if seen[key] then return end
        seen[key] = true
        table.insert(list, { comp = comp, depth = depth })
        local children = nil
        pcall(function() children = comp.AttachChildren end)
        Each(children, function(child) walk(child, depth + 1) end)
    end
    local root = nil
    pcall(function() root = pawn.RootComponent end)
    walk(root, 0)
    return list
end

local function OwnerOf(comp)
    local owner = nil
    pcall(function() owner = comp:GetOuter() end)
    return owner
end

------------------------------------------------------------
-- What gets recorded: a list of columns { name, get = fn -> number }
------------------------------------------------------------
local function Fmt(n)
    if n == nil then return "" end
    if n == math.floor(n) and math.abs(n) < 1e9 then return string.format("%d", n) end
    return string.format("%.4f", n)
end

-- The camera's angle limits: the camera keeps your view's yaw and pitch
-- between these. The yaw sometimes stuck at exactly 359 / 0 (14 Oct buffer)
-- though it normally passes 359.5: something may narrow them now and then.
local LIMITS = { "ViewYawMin", "ViewYawMax", "ViewPitchMin", "ViewPitchMax" }
local function LimitsText(pcm)
    local v = {}
    for _, f in ipairs(LIMITS) do
        local n = nil
        pcall(function() n = pcm[f] end)
        v[f] = type(n) == "number" and string.format("%.3f", n) or "?"
    end
    return string.format("yaw %s .. %s, pitch %s .. %s", v.ViewYawMin, v.ViewYawMax, v.ViewPitchMin, v.ViewPitchMax)
end

local traced = false
local function Build(pc)
    -- The first look-up logs each step: if the game crashes, the last line says where
    local trace = not traced
    traced = true
    local function step(what) if trace then log("  first look-up: " .. what) end end
    step("finding you")
    if not Valid(pc) then pc = LocalController() end
    if not pc then return nil, "no local player controller (load into a world first)" end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not Valid(pawn) then return nil, "you have no character right now" end

    local cols, names = {}, {}
    local objects, seenObj = {}, {}
    -- obj: what the value is read from; checked to still exist before every read
    local function add(name, get, obj)
        if names[name] then name = name .. "#" .. (#cols + 1) end
        names[name] = true
        table.insert(cols, { name = name, get = get, obj = obj })
        if obj and not seenObj[obj] then
            seenObj[obj] = true
            table.insert(objects, obj)
        end
    end
    local function addValue(prefix, obj, propName, kind)
        if kind == "number" then
            add(prefix, function() return obj[propName] end, obj)
        elseif kind == "bool" then
            add(prefix, function() return obj[propName] and 1 or 0 end, obj)
        elseif kind == "rot" then
            add(prefix .. ".P", function() return obj[propName].Pitch end, obj)
            add(prefix .. ".Y", function() return obj[propName].Yaw end, obj)
            add(prefix .. ".R", function() return obj[propName].Roll end, obj)
        elseif kind == "vec" then
            add(prefix .. ".X", function() return obj[propName].X end, obj)
            add(prefix .. ".Y", function() return obj[propName].Y end, obj)
            add(prefix .. ".Z", function() return obj[propName].Z end, obj)
        elseif kind == "vec2" then
            add(prefix .. ".X", function() return obj[propName].X end, obj)
            add(prefix .. ".Y", function() return obj[propName].Y end, obj)
        end
    end

    -- Where you look (the controller) and what the camera shows
    addValue("ctrl", pc, "ControlRotation", "rot")
    local pcm = nil
    pcall(function() pcm = pc.PlayerCameraManager end)
    if Valid(pcm) then
        add("cam.P", function() return pcm.CameraCachePrivate.POV.Rotation.Pitch end, pcm)
        add("cam.Y", function() return pcm.CameraCachePrivate.POV.Rotation.Yaw end, pcm)
        add("cam.R", function() return pcm.CameraCachePrivate.POV.Rotation.Roll end, pcm)
        add("cam.FOV", function() return pcm.CameraCachePrivate.POV.FOV end, pcm)
        for _, f in ipairs(LIMITS) do
            add("lim." .. f:gsub("^View", ""), function() return pcm[f] end, pcm)
        end
    end

    -- Every part's angle and position relative to what it hangs on: your
    -- character's own and those of what's attached to it (weapon, magazine,
    -- clothing). Attached things come and go; everything read is checked to
    -- still exist before every read (AllValid), which catches a removed one
    -- before the game frees it.
    step("your character's parts")
    local parts = ComponentTree(pawn)
    local animInstances, others, seenOwner = {}, {}, {}
    local own = 0
    for _, p in ipairs(parts) do
        local comp = p.comp
        local owner = OwnerOf(comp)
        if Valid(owner) then
            local label = NameOf(comp)
            if NameOf(owner) == NameOf(pawn) then
                own = own + 1
            else
                -- by class (BP_Saiga12_C), so a new copy of the weapon keeps its columns
                label = ClassName(owner) .. "/" .. label
                if not seenOwner[NameOf(owner)] then
                    seenOwner[NameOf(owner)] = true
                    table.insert(others, owner)
                end
            end
            addValue(label .. ".rel", comp, "RelativeRotation", "rot")
            addValue(label .. ".loc", comp, "RelativeLocation", "vec")
            local anim = nil
            pcall(function() anim = comp.AnimScriptInstance end)
            if Valid(anim) then table.insert(animInstances, { label = label, obj = anim }) end
        end
    end
    step(#parts .. " parts, " .. own .. " of them your character's own, " .. #others .. " attached things")

    -- Settings that sound like aim / sway / rotation on the character, its
    -- animation (arms sway usually lives there), what's attached (the weapon)
    local function addSettings(prefix, obj)
        step("settings of " .. NameOf(obj) .. " (" .. ClassName(obj) .. ")")
        local n = 0
        EachSetting(obj, function(name, _, kind)
            if n < MAX_PROPS_PER_OBJECT and Wanted(name) then
                n = n + 1
                addValue(prefix .. "." .. Short(name), obj, name, kind)
            end
        end)
    end
    addSettings("pawn", pawn)
    addSettings("ctrl", pc)
    for _, a in ipairs(animInstances) do addSettings("anim[" .. a.label .. "]", a.obj) end
    for _, obj in ipairs(others) do addSettings(ClassName(obj), obj) end

    step("done, " .. #cols .. " values")
    return { pc = pc, pawn = pawn, pcm = pcm, cols = cols, parts = parts, anims = animInstances, objects = objects }
end

local function Read(col)
    local ok, v = pcall(col.get)
    if ok and type(v) == "number" then return v end
    return nil
end

-- Everything the values are read from still exists (checked before each read)
local function AllValid(set)
    for _, obj in ipairs(set.objects) do
        if not Valid(obj) then return false end
    end
    return true
end

local function Wrap(d)
    if d == nil then return nil end
    if d > 180 then d = d - 360 elseif d < -180 then d = d + 360 end
    return d
end

------------------------------------------------------------
-- Mouse input: what the game hands Unreal each frame to turn the view
------------------------------------------------------------
-- Listens to Unreal's "add yaw / pitch input" functions only while a
-- recording or the readout needs it. Totals only grow; each user keeps the
-- totals it saw last and takes the difference.
local INPUT_FUNCTIONS = {
    { "/Script/Engine.Pawn:AddControllerYawInput", "yaw" },
    { "/Script/Engine.Pawn:AddControllerPitchInput", "pitch" },
    { "/Script/Engine.PlayerController:AddYawInput", "yaw" },
    { "/Script/Engine.PlayerController:AddPitchInput", "pitch" },
}
local mouse = { yaw = 0, pitch = 0, calls = 0, users = 0, hooks = {}, fired = {} }

-- The hooks stay once made (idle while nobody uses them): removing a hook
-- (UnregisterHook) in this UE4SS frees its Lua function but can leave the
-- hook in place, and the game aborts the next time the function runs ("Ref
-- was not function", 17 Oct)
local function MouseAcquire()
    mouse.users = mouse.users + 1
    if mouse.users > 1 or #mouse.hooks > 0 then return end
    for _, f in ipairs(INPUT_FUNCTIONS) do
        local path, axis = f[1], f[2]
        local ok, pre, post = pcall(RegisterHook, path, function(self, Val)
            if mouse.users <= 0 then return end
            local v = nil
            pcall(function() v = Val:get() end)
            if type(v) == "number" then
                mouse[axis] = mouse[axis] + v
                mouse.calls = mouse.calls + 1
                mouse.fired[path] = (mouse.fired[path] or 0) + 1
            end
        end)
        if ok and pre then
            table.insert(mouse.hooks, { path, pre, post })
        else
            log("Can't listen to " .. path .. ": " .. tostring(pre))
        end
    end
end

local function MouseRelease()
    if mouse.users == 0 then return end
    mouse.users = mouse.users - 1
end

------------------------------------------------------------
-- Every frame, on the game thread
------------------------------------------------------------
-- Recordings, the buffer, the readout and watch all run from one of the
-- game's own every-frame events (hooked while one of them is on), never
-- from a background timer: Lua code running on a background timer and on
-- the game thread at the same time crashed the game within seconds.
-- users[name] = { ms, fn, last }; fn runs at most every ms.
local ticker = { users = {}, hook = nil }

-- The class's path, e.g. "/Game/.../BP_SGKController.BP_SGKController_C"
local function ClassPath(obj)
    local full = ""
    pcall(function() full = obj:GetClass():GetFullName() end)
    return full:match("^%S+%s+(/.+)$")
end

-- Every-frame events a class can have, in the order they're tried: the
-- controller (lives through deaths), your character, its animations
local function FrameEvents(set)
    local list = {}
    local function try(obj, event)
        local path = ClassPath(obj)
        if path then table.insert(list, path .. ":" .. event) end
    end
    try(set.pc, "ReceiveTick")
    try(set.pawn, "ReceiveTick")
    for _, a in ipairs(set.anims) do try(a.obj, "BlueprintUpdateAnimation") end
    try(set.pcm, "BlueprintUpdateCamera")
    return list
end

local function OnFrame()
    local now = os.clock()
    for name, u in pairs(ticker.users) do
        if (now - u.last) * 1000 >= u.ms - 2 then   -- frames aren't exact: 16 ms ~ every frame at 60 fps
            u.last = now
            local ok, err = pcall(u.fn, now)
            if not ok and not u.warned then u.warned = true log(name .. ": " .. tostring(err)) end
        end
    end
end

local function TickerHook(set)
    if ticker.hook then return true end
    for _, path in ipairs(FrameEvents(set)) do
        local fn = nil
        pcall(function() fn = StaticFindObject(path) end)
        if Valid(fn) then
            local ok, pre, post = pcall(RegisterHook, path, function() OnFrame() end)
            if ok and pre then
                ticker.hook = { path, pre, post }
                log("Running every frame with " .. path:match("([^%.]+)$"))
                return true
            end
        end
    end
    log("Found no every-frame event to run from (tried the controller, your character, its animations and the camera)")
    return false
end

-- Start running fn every ms. set: a look-up, to find the event to hook
local function TickerAdd(name, ms, fn, set)
    if not TickerHook(set) then return false end
    ticker.users[name] = { ms = ms, fn = fn, last = -100 }
    return true
end

-- Stop running it. The hook stays (removing hooks can crash this UE4SS,
-- see MouseAcquire) and does nothing while nobody uses it
local function TickerRemove(name)
    ticker.users[name] = nil
end

------------------------------------------------------------
-- Recording: .view rec (from now on) and .view buffer (the last few
-- seconds, kept until the mark key saves them)
------------------------------------------------------------
-- rec = { mode = "rec" | "buffer", set, rows, start, until_, stop,
--         dumpAt, dumpFrom, dumpNote, ... }
local rec = nil
local pendingMark = nil
local watching = nil
local AFTER_MARK = 2      -- buffer: seconds kept after the mark key before saving

local stamps = 0
local function Stamp()
    stamps = stamps + 1
    return os.date("%Y%m%d_%H%M%S") .. "_" .. stamps
end

local function Csv(s)
    s = tostring(s)
    if s:find('[,"\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
    return s
end

-- Names of the character's parts (and their animations) in attachment
-- order: changes when you swap weapons or an animation is replaced. Only reads properties, so it's cheap enough once a second.
local function PartsSignature(pawn)
    local names = {}
    for _, p in ipairs(ComponentTree(pawn)) do
        local anim = nil
        pcall(function() anim = p.comp.AnimScriptInstance end)
        table.insert(names, NameOf(p.comp) .. (Valid(anim) and ("+" .. NameOf(anim)) or ""))
    end
    return table.concat(names, "|")
end

-- Walls: stretches where the mouse kept moving on an axis but your aim
-- didn't turn on it. rows: { t, dYaw, dPitch, mYaw, mPitch, P, Y } (P / Y:
-- where you aim). Frames without input on that axis don't end a wall; a
-- frame where the aim turns does, and its input is what broke through.
-- Returns { axis, from, to, frames, angle, pushed, smallest, breakInput, breakTurn }
local MIN_WALL_FRAMES = 2

local function Walls(rows)
    local walls = {}
    local function scan(axis, dKey, mKey, angleKey)
        local cur = nil
        for _, row in ipairs(rows) do
            local m, d = row[mKey] or 0, row[dKey]
            local atLimit = axis == "pitch" and row.P and math.abs(Wrap(row.P)) > 89.5
            if d ~= nil and not atLimit then
                if m ~= 0 and d == 0 then
                    if not cur then
                        cur = { axis = axis, from = row.t, frames = 0, angle = row[angleKey], pushed = 0 }
                    end
                    cur.to, cur.frames, cur.pushed = row.t, cur.frames + 1, cur.pushed + m
                    if not cur.smallest or math.abs(m) < cur.smallest then cur.smallest = math.abs(m) end
                elseif d ~= 0 and cur then
                    cur.breakInput, cur.breakTurn = m, d
                    if cur.frames >= MIN_WALL_FRAMES then table.insert(walls, cur) end
                    cur = nil
                end
            end
        end
        if cur and cur.frames >= MIN_WALL_FRAMES then table.insert(walls, cur) end
    end
    scan("yaw", "dYaw", "mYaw", "Y")
    scan("pitch", "dPitch", "mPitch", "P")
    table.sort(walls, function(a, b) return a.from < b.from end)
    return walls
end

local function WallText(w)
    local angle = w.angle and (w.axis == "pitch" and Wrap(w.angle) or w.angle)
    return string.format("%6.2f s  %-5s stuck at %s for %.2f s (%d frames), pushed %s (smallest %s)%s",
        w.from, w.axis, angle and string.format("%.3f", angle) or "?", (w.to or w.from) - w.from, w.frames,
        Fmt(w.pushed), Fmt(w.smallest),
        w.breakInput and string.format(", broke through with %s -> turned %s", Fmt(w.breakInput), Fmt(w.breakTurn))
            or ", never broke through")
end

-- Writes rows to <prefix>_<time>.csv and the summary to the log. Rows can
-- come from different look-ups (weapon swaps): columns are matched by name.
local function Write(r, rows, prefix, title)
    if #rows == 0 then log(title .. ": nothing recorded") return end

    local order, index = {}, {}      -- column names in order; [set][name] = i
    for _, row in ipairs(rows) do
        if not index[row.set] then
            index[row.set] = {}
            for i, col in ipairs(row.set.cols) do
                index[row.set][col.name] = i
                if not order[col.name] then
                    order[col.name] = true
                    table.insert(order, col.name)
                end
            end
        end
    end
    local function value(row, name)
        local i = index[row.set][name]
        return i and row.v[i] or nil
    end

    -- Keep only the columns that changed (plus where you look), so the file is readable
    local keep = {}
    for _, name in ipairs(order) do
        local first, changed, lo, hi = nil, false, math.huge, -math.huge
        for _, row in ipairs(rows) do
            local v = value(row, name)
            if v ~= nil then
                if first == nil then first = v elseif v ~= first then changed = true end
                if v < lo then lo = v end
                if v > hi then hi = v end
            end
        end
        if changed or name:find("^ctrl%.[PYR]$") or name:find("^cam%.") then
            table.insert(keep, { name = name, range = hi - lo, lo = lo, hi = hi })
        end
    end

    local t0 = rows[1].t
    local stamp = Stamp()
    local fileName = prefix .. "_" .. stamp .. ".csv"
    local file = io.open(MOD_DIR .. fileName, "w")
    if not file then log("Couldn't write " .. MOD_DIR .. fileName) return end
    local header = { "t", "dYaw", "dPitch", "mouseYaw", "mousePitch", "mouseCalls", "mark" }
    for _, k in ipairs(keep) do table.insert(header, Csv(k.name)) end
    file:write(table.concat(header, ",") .. "\n")
    for _, row in ipairs(rows) do
        local line = { Fmt(row.t - t0), Fmt(row.dYaw), Fmt(row.dPitch), Fmt(row.mYaw), Fmt(row.mPitch),
                       Fmt(row.mCalls), Csv(row.mark or "") }
        for _, k in ipairs(keep) do table.insert(line, Fmt(value(row, k.name))) end
        file:write(table.concat(line, ",") .. "\n")
    end
    file:close()
    local index = io.open(MOD_DIR .. "dumps.txt", "a")   -- for .view dumps / .view read
    if index then index:write(fileName .. "\n") index:close() end

    local seconds = rows[#rows].t - t0
    local slowTurns = 0
    for _, row in ipairs(rows) do
        local d = math.max(math.abs(row.dYaw or 0), math.abs(row.dPitch or 0))
        if d > 0 and d < 0.05 then slowTurns = slowTurns + 1 end
    end
    log(string.format("%s: %d samples over %.1f s (%.0f a second), %d of %d values saved (the ones that changed)",
        title, #rows, seconds, #rows / math.max(seconds, 0.001), #keep, #order))
    log("  Samples with a very slow turn (under 0.05 degrees): " .. slowTurns)

    -- Walls (mouse moving, aim stuck) and aim turning while the camera didn't
    local camStuck, prevCam, mouseCalls, view = 0, nil, 0, {}
    for _, row in ipairs(rows) do
        mouseCalls = mouseCalls + (row.mCalls or 0)
        local turned = (row.dYaw or 0) ~= 0 or (row.dPitch or 0) ~= 0
        local cam = value(row, "cam.Y")
        if turned and cam and prevCam and cam == prevCam then camStuck = camStuck + 1 end
        prevCam = cam
        table.insert(view, { t = row.t - t0, dYaw = row.dYaw, dPitch = row.dPitch, mYaw = row.mYaw,
                             mPitch = row.mPitch, P = value(row, "ctrl.P"), Y = value(row, "ctrl.Y") })
    end
    if mouseCalls == 0 then
        log("  Mouse: no input seen through Unreal's look functions (the game turns the view some other way)")
    else
        local fired = {}
        for path in pairs(mouse.fired) do table.insert(fired, (path:match(":(.+)$"))) end
        log("  Mouse: " .. mouseCalls .. " inputs (" .. table.concat(fired, ", ") .. ")")
        local walls = Walls(view)
        log("  Walls (mouse moving, aim stuck): " .. #walls)
        for _, w in ipairs(walls) do log("    " .. WallText(w)) end
    end
    log("  Samples where your aim turned but the camera didn't: " .. camStuck)
    table.sort(keep, function(a, b) return a.range > b.range end)
    local shown = 0
    for _, k in ipairs(keep) do
        if shown < 15 and k.range > 0 then
            shown = shown + 1
            log(string.format("  changed most: %s  %s .. %s", k.name, Fmt(k.lo), Fmt(k.hi)))
        end
    end
    for _, row in ipairs(rows) do
        if row.mark then log(string.format("  mark at %.2f s: %s", row.t - t0, row.mark)) end
    end
    log("  Saved: ue4ss\\Mods\\ViewDebug\\" .. fileName .. " - send this file")
end

local function Finish(reason)
    local r = rec
    if not r then return end
    rec = nil
    r.stop = true
    TickerRemove("Recording")
    MouseRelease()
    if r.mode == "rec" then
        Write(r, r.rows, "recording", "Recording stopped (" .. reason .. ")")
    else
        log("Buffer off (" .. reason .. ")" .. (r.dumpAt and ", the pending save is dropped" or ""))
    end
end

-- Buffer: save from dumpFrom up to now, keep going
local function Dump(r)
    local rows = {}
    for _, row in ipairs(r.rows) do
        if row.t >= r.dumpFrom then table.insert(rows, row) end
    end
    r.dumpAt = nil
    Write(r, rows, "buffer", "Saved the buffer (" .. r.dumpNote .. ")")
end

-- .view dump: save the buffer now
local function DumpNow()
    local r = rec
    if not r or r.mode ~= "buffer" then log("The buffer is off - .view buffer turns it on") return end
    local last = r.rows[#r.rows]
    if not last then log("The buffer is still empty") return end
    r.dumpFrom, r.dumpNote = last.t - r.window, "dump"
    Dump(r)
end

local function Sample()
    local r = rec
    if not r or r.stop then return end
    local now = os.clock()
    if r.mode == "rec" and now >= r.until_ then Finish("time's up") return end

    -- A new character (respawn, level) or weapon: look it up again
    local stale = not Valid(r.set.pawn) or not AllValid(r.set)
    if not stale and now - (r.checked or 0) > 1 then
        r.checked = now
        stale = PartsSignature(r.set.pawn) ~= r.signature
    end
    if stale then
        if now - (r.tried or -100) < 2 then return end
        r.tried = now
        local set = Build(r.set.pc)
        if not set then
            if r.mode == "rec" then Finish("your character is gone") end
            return   -- buffer: wait for the character to come back
        end
        r.set, r.signature, r.checked, r.lastV = set, PartsSignature(set.pawn), now, nil
    end

    local v = {}
    for i, col in ipairs(r.set.cols) do v[i] = Read(col) end
    local row = { t = now - r.start, set = r.set, v = v }
    -- the camera's limits: one log line each time they change
    if Valid(r.set.pcm) then
        local limits = LimitsText(r.set.pcm)
        if limits ~= r.lastLimits then
            log(string.format("Camera limits %s at %.2f s: %s", r.lastLimits and "changed" or "are", row.t, limits))
            r.lastLimits = limits
        end
    end
    -- columns 1-2 are ctrl.P / ctrl.Y in every look-up
    if r.lastV then
        row.dPitch = (v[1] and r.lastV[1]) and Wrap(v[1] - r.lastV[1]) or nil
        row.dYaw = (v[2] and r.lastV[2]) and Wrap(v[2] - r.lastV[2]) or nil
    end
    r.lastV = v
    row.mYaw, row.mPitch, row.mCalls = mouse.yaw - r.mouseYaw, mouse.pitch - r.mousePitch, mouse.calls - r.mouseCalls
    r.mouseYaw, r.mousePitch, r.mouseCalls = mouse.yaw, mouse.pitch, mouse.calls
    if pendingMark then
        row.mark = pendingMark
        if r.mode == "buffer" and not r.dumpAt then
            r.dumpAt, r.dumpFrom, r.dumpNote = now + AFTER_MARK, row.t - r.window, pendingMark
            log(string.format("Marked: %s - saving the last %d s in %d s (keep doing what you did)",
                pendingMark, math.floor(r.window), AFTER_MARK))
        else
            log(string.format("Marked at %.2f s: %s", row.t, pendingMark))
        end
        pendingMark = nil
    end
    table.insert(r.rows, row)

    if r.mode == "buffer" then
        if r.dumpAt and now >= r.dumpAt then Dump(r) end
        -- forget what's older than the buffer (plus room for a save after the mark key)
        local oldest = row.t - r.window - AFTER_MARK - 1
        local drop = 0
        while r.rows[drop + 1] and r.rows[drop + 1].t < oldest do drop = drop + 1 end
        if drop > 0 then
            local n = #r.rows
            table.move(r.rows, drop + 1, n, 1)
            for i = n - drop + 1, n do r.rows[i] = nil end
        end
    end
end

local function Start(mode, arg)
    if rec then
        log((rec.mode == "rec" and "Already recording" or "The buffer is on") .. " - .view stop first")
        return
    end
    local set, err = Build()
    if not set then log("Can't record: " .. err) return end
    local now = os.clock()
    rec = { mode = mode, set = set, rows = {}, start = now, signature = PartsSignature(set.pawn), checked = now }
    local mine = rec
    if not TickerAdd("Recording", SAMPLE_MS, function() Sample() end, set) then
        rec = nil
        return
    end
    if mode == "rec" then
        local seconds = math.min(MAX_SECONDS, math.max(1, tonumber(arg) or MAX_SECONDS))
        mine.until_ = now + seconds
        log(string.format("Recording %d values every %d ms for up to %d s. %s when the view sticks, .view stop to end",
            #set.cols, SAMPLE_MS, seconds, MARK_HOW))
    else
        mine.window = math.min(60, math.max(2, tonumber(arg) or BUFFER_SECONDS))
        log(string.format("Buffer on: keeping the last %d s. When the view sticks, .view dump saves them%s; .view buffer again turns it off",
            math.floor(mine.window), MARK_KEY ~= "" and (" (or press " .. MARK_KEY .. ")") or ""))
    end
    MouseAcquire()
    mine.mouseYaw, mine.mousePitch, mine.mouseCalls = mouse.yaw, mouse.pitch, mouse.calls
    mouse.fired = {}
end

------------------------------------------------------------
-- Snapshot, watch, scan
------------------------------------------------------------
local function Line(set, filter)
    local parts = {}
    for _, col in ipairs(set.cols) do
        if filter(col.name) then table.insert(parts, col.name .. "=" .. Fmt(Read(col))) end
    end
    return table.concat(parts, "  ")
end

local function IsMain(name)
    return name:find("^ctrl%.[PY]$") or name:find("^cam%.[PY]$")
end

-- The arms / weapon meshes: skeletal mesh parts' angles
local function MeshLabels(set)
    local wanted = {}
    for _, p in ipairs(set.parts) do
        if ClassName(p.comp):find("SkeletalMesh") then wanted[NameOf(p.comp)] = true end
    end
    return wanted
end

local function Snapshot(note)
    local set, err = Build()
    if not set then log("Can't read the view: " .. err) return end
    local meshes = MeshLabels(set)
    log((note and ("Mark (not recording): " .. note .. " - ") or "View now: ")
        .. Line(set, function(n) return n:find("^ctrl%.[PYR]$") or n:find("^cam%.") end))
    log("  Meshes: " .. Line(set, function(n)
        local comp = n:match("([^/]+)%.rel%.[PYR]$")
        return comp ~= nil and meshes[comp] == true
    end))
    log("  " .. #set.cols .. " values found (.view scan lists them)")
end

local function Watch()
    if watching then watching = nil TickerRemove("Watch") log("Watch off") return end
    local set, err = Build()
    if not set then log("Can't watch: " .. err) return end
    local meshes = MeshLabels(set)
    local mine = { until_ = os.clock() + WATCH_SECONDS }
    local ok = TickerAdd("Watch", 250, function(now)
        if watching ~= mine then return end
        if now >= mine.until_ or not Valid(set.pawn) or not AllValid(set) then
            watching = nil
            TickerRemove("Watch")
            log("Watch off")
            return
        end
        log("watch: " .. Line(set, function(n)
            if IsMain(n) then return true end
            local comp = n:match("([^/]+)%.rel%.[PY]$")
            return comp ~= nil and meshes[comp] == true
        end))
    end, set)
    if not ok then return end
    watching = mine
    log("Watch on for " .. WATCH_SECONDS .. " s (.view watch again to stop)")
end

local function Scan()
    local set, err = Build()
    if not set then log("Can't scan: " .. err) return end
    local out = {}
    local function w(s) table.insert(out, s) end
    w("View Debug " .. VERSION .. " scan, " .. os.date("%Y-%m-%d %H:%M:%S"))
    w("Character: " .. NameOf(set.pawn) .. " (" .. ClassName(set.pawn) .. ")")
    w("Controller: " .. NameOf(set.pc) .. " (" .. ClassName(set.pc) .. ")")
    if Valid(set.pcm) then w("Camera manager: " .. NameOf(set.pcm) .. " (" .. ClassName(set.pcm) .. ")") end
    w("")
    w("Parts (indented = attached to the one above):")
    for _, p in ipairs(set.parts) do
        local rot = ""
        pcall(function()
            local r = p.comp.RelativeRotation
            rot = string.format("  rel P=%s Y=%s R=%s", Fmt(r.Pitch), Fmt(r.Yaw), Fmt(r.Roll))
        end)
        local owner = OwnerOf(p.comp)
        w(string.rep("  ", p.depth + 1) .. NameOf(p.comp) .. " (" .. ClassName(p.comp) .. ") of "
            .. NameOf(owner) .. rot)
    end
    local function dump(title, obj)
        if not Valid(obj) then return end
        w("")
        w(title .. ": " .. NameOf(obj) .. " (" .. ClassName(obj) .. ")")
        EachSetting(obj, function(name, value, kind)
            local text
            if kind == "rot" then text = string.format("P=%s Y=%s R=%s", Fmt(value.Pitch), Fmt(value.Yaw), Fmt(value.Roll))
            elseif kind == "vec" then text = string.format("X=%s Y=%s Z=%s", Fmt(value.X), Fmt(value.Y), Fmt(value.Z))
            elseif kind == "vec2" then text = string.format("X=%s Y=%s", Fmt(value.X), Fmt(value.Y))
            elseif kind == "bool" then text = tostring(value)
            else text = Fmt(value) end
            w("  " .. (Wanted(name) and "* " or "  ") .. Short(name) .. " = " .. text)
        end)
    end
    dump("Character settings", set.pawn)
    dump("Controller settings", set.pc)
    dump("Camera manager settings", set.pcm)
    for _, a in ipairs(set.anims) do dump("Animation of " .. a.label, a.obj) end
    local done = {}
    for _, p in ipairs(set.parts) do
        local owner = OwnerOf(p.comp)
        if Valid(owner) and NameOf(owner) ~= NameOf(set.pawn) and not done[NameOf(owner)] then
            done[NameOf(owner)] = true
            dump("Attached", owner)
        end
    end
    w("")
    w("Recorded by .view rec (" .. #set.cols .. "):")
    for _, col in ipairs(set.cols) do w("  " .. col.name .. " = " .. Fmt(Read(col))) end

    local name = "scan_" .. Stamp() .. ".txt"
    local file = io.open(MOD_DIR .. name, "w")
    if file then
        file:write(table.concat(out, "\n") .. "\n")
        file:close()
    end
    log(string.format("Scan: %d parts, %d animations, %d values to record", #set.parts, #set.anims, #set.cols))
    for _, p in ipairs(set.parts) do
        if ClassName(p.comp):find("SkeletalMesh") or ClassName(p.comp):find("Camera") then
            log("  " .. NameOf(p.comp) .. " (" .. ClassName(p.comp) .. ")")
        end
    end
    log(file and ("  Saved: ue4ss\\Mods\\ViewDebug\\" .. name .. " - send this file") or "  Couldn't write the scan file")
end

------------------------------------------------------------
-- On-screen readout (.view hud)
------------------------------------------------------------
local UMG = "/Script/UMG."
local HUD_PREFIX = "ViewDebugPanel_"
local hudTag = string.format("%x%x", os.time(), math.floor(os.clock() * 1000))
local hudCount = 0
local hud = nil            -- { stop, set, rows, built, panel, text, hudObj, last, markUntil, markNote }
local COLLAPSED, HIT_TEST_INVISIBLE = 1, 3
local PANEL_COLOR = { R = 0.006, G = 0.009, B = 0.015, A = 0.78 }
local TEXT_COLOR = { R = 0.791, G = 0.831, B = 0.888, A = 1 }

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
    if not pcall(function() text:SetText(FText(s)) end) then pcall(function() text:SetText(s) end) end
end

-- Panels a previous copy of this mod (.reloadmods) left on the screen
local leftoversRemoved = false
local function RemoveLeftovers()
    if leftoversRemoved then return end
    leftoversRemoved = true
    pcall(function()
        for _, w in ipairs(FindAllOf("Border") or {}) do
            local name = NameOf(w)
            if name:find(HUD_PREFIX, 1, true) == 1 and not name:find(hudTag, 1, true) then
                pcall(function() w:RemoveFromParent() end)
            end
        end
    end)
end

-- Rows to show: { label, cols = { index, ... } }. Where you look, the camera,
-- every mesh's angle (arms, weapon) and rotations in the animations (sway)
local function HudRows(set)
    local byName = {}
    for i, col in ipairs(set.cols) do byName[col.name] = i end
    local meshes = MeshLabels(set)
    local rows = {}
    local function addRot(label, prefix, axes)
        local idx = {}
        for _, ax in ipairs(axes) do
            if byName[prefix .. "." .. ax] then table.insert(idx, { ax = ax, i = byName[prefix .. "." .. ax] }) end
        end
        if #idx > 0 then table.insert(rows, { label = label, cols = idx }) end
    end
    addRot("look", "ctrl", { "P", "Y" })
    addRot("camera", "cam", { "P", "Y" })
    for _, col in ipairs(set.cols) do
        local prefix = col.name:match("^(.+%.rel)%.P$")
        if prefix then
            local comp = prefix:match("([^/]+)%.rel$")
            if comp and meshes[comp] then addRot(comp, prefix, { "P", "Y", "R" }) end
        end
    end
    local anims = 0
    for _, col in ipairs(set.cols) do
        local prefix = col.name:match("^(anim%[.-%]%..+)%.P$")
        if prefix and anims < 8 then
            anims = anims + 1
            addRot(prefix:gsub("^anim%[.-%]%.", "anim "), prefix, { "P", "Y", "R" })
        end
    end
    return rows
end

local function HudBuildPanel(hudObj, side)
    local tree = hudObj.WidgetTree
    hudCount = hudCount + 1
    local panel = Construct("Border", tree, HUD_PREFIX .. hudTag .. "_" .. hudCount)
    panel:SetBrushColor(PANEL_COLOR)
    pcall(function() panel:SetPadding({ Left = 10, Top = 6, Right = 12, Bottom = 8 }) end)
    local text = Construct("TextBlock", tree)
    pcall(function() text.Font.Size = 11 end)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = TEXT_COLOR, ColorUseRule = 0 }) end)
    pcall(function() text:SetShadowOffset({ X = 0.0, Y = 1.0 }) end)
    panel:SetContent(text)
    local root = hudObj.WidgetTree.RootWidget
    local cls = ClassName(root)
    if cls == "CanvasPanel" then
        local slot = root:AddChildToCanvas(panel)
        local ax, ay, px, py = 1, 0, -24, 24          -- top right
        if side == "left" then ax, ay, px, py = 0, 0.5, 24, 0 end
        pcall(function() slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } }) end)
        pcall(function() slot:SetAlignment({ X = ax, Y = ay }) end)
        pcall(function() slot:SetPosition({ X = px, Y = py }) end)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(99) end)
    elseif cls == "Overlay" then
        local slot = root:AddChildToOverlay(panel)
        pcall(function() slot:SetHorizontalAlignment(side == "left" and 1 or 3) end)
        pcall(function() slot:SetVerticalAlignment(side == "left" and 2 or 1) end)
        pcall(function() slot:SetPadding(side == "left" and { Left = 24, Top = 0, Right = 0, Bottom = 0 }
            or { Left = 0, Top = 24, Right = 24, Bottom = 0 }) end)
    else
        error("the HUD's root is a " .. cls, 0)
    end
    return panel, text
end

local function HudRemove()
    if hud and hud.panel then pcall(function() hud.panel:RemoveFromParent() end) end
    if hud then hud.panel, hud.text = nil, nil end
end

local function Num(v)
    if v == nil then return "      -" end
    return string.format("%8.3f", v)
end

-- Game thread, every HUD_MS while shown
-- Each update only reads the angles shown and sets the text. Finding your
-- character's settings, the HUD and building the panel happen only when
-- something changed (respawn, weapon swap, level load), at most every 2 s.
local function HudTick(h)
    local now = os.clock()
    local stale = not h.set or not Valid(h.set.pawn) or not AllValid(h.set)
    if not stale and now - (h.checked or 0) > 1 then
        h.checked = now
        stale = PartsSignature(h.set.pawn) ~= h.signature
    end
    if stale then
        if now - (h.tried or -100) < 2 then return end
        h.tried = now
        local set = Build(h.set and h.set.pc)
        if not set then
            if h.panel then pcall(function() h.panel:SetVisibility(COLLAPSED) end) end
            return
        end
        h.set, h.rows, h.signature, h.checked = set, HudRows(set), PartsSignature(set.pawn), now
        if Valid(h.panel) then pcall(function() h.panel:SetVisibility(HIT_TEST_INVISIBLE) end) end
    end
    if not Valid(h.hudObj) then
        if now - (h.hudTried or -100) < 2 then return end
        h.hudTried = now
        pcall(function() h.hudObj = FindFirstOf("BP_InventoryHUD_C") end)
        if not Valid(h.hudObj) then return end
        h.panel = nil   -- a new HUD (level load): build the panel there
    end
    if not Valid(h.panel) then
        HudRemove()
        RemoveLeftovers()
        local ok, panel, text = pcall(HudBuildPanel, h.hudObj)
        if not ok then
            log("On-screen readout unavailable (" .. tostring(panel) .. ") - .view watch writes it to the log")
            h.stop = true
            if hud == h then hud = nil TickerRemove("Readout") MouseRelease() end
            return
        end
        h.panel, h.text, h.lastText = panel, text, nil
        pcall(function() h.panel:SetVisibility(HIT_TEST_INVISIBLE) end)
    end

    local lines = {}
    local title = "VIEW DEBUG"
    if rec and rec.mode == "rec" then title = title .. string.format("   REC %.1f s", now - rec.start)
    elseif rec then title = title .. (rec.dumpAt and "   SAVING..." or ("   BUFFER (.view dump saves)")) end
    if h.markUntil and now < h.markUntil then title = title .. "   MARKED: " .. h.markNote end
    table.insert(lines, title)
    local values = {}
    for _, row in ipairs(h.rows) do
        local parts = { string.format("%-14s", row.label:sub(1, 14)) }
        for _, c in ipairs(row.cols) do
            local v = Read(h.set.cols[c.i])
            values[c.i] = v
            table.insert(parts, c.ax .. Num(v))
        end
        table.insert(lines, table.concat(parts, "  "))
    end
    -- How far the view turned since the last update
    local p, y = Read(h.set.cols[1]), Read(h.set.cols[2])
    if h.lastP and p and y then
        table.insert(lines, string.format("%-14s  P%8.3f  Y%8.3f", "turn / update", Wrap(p - h.lastP), Wrap(y - h.lastY)))
    end
    h.lastP, h.lastY = p, y
    if h.mouseYaw then
        table.insert(lines, string.format("%-14s  P%8.3f  Y%8.3f  (%d inputs)", "mouse / update",
            mouse.pitch - h.mousePitch, mouse.yaw - h.mouseYaw, mouse.calls - h.mouseCalls))
    end
    h.mouseYaw, h.mousePitch, h.mouseCalls = mouse.yaw, mouse.pitch, mouse.calls
    local s = table.concat(lines, "\n")
    if s ~= h.lastText then
        SetText(h.text, s)
        h.lastText = s
    end
end

local function HudToggle()
    if hud then
        local h = hud
        hud = nil
        h.stop = true
        TickerRemove("Readout")
        MouseRelease()
        if h.panel then pcall(function() h.panel:RemoveFromParent() end) end
        log("On-screen readout off")
        return
    end
    local set, err = Build()
    if not set then log("Can't show the readout: " .. err) return end
    local now = os.clock()
    local mine = { stop = false, set = set, rows = HudRows(set), signature = PartsSignature(set.pawn), checked = now }
    if not TickerAdd("Readout", HUD_MS, function() if not mine.stop then HudTick(mine) end end, set) then return end
    MouseAcquire()
    hud = mine
    log("On-screen readout on (top right). .view hud again hides it")
end

------------------------------------------------------------
-- Reading dumps in game: .view dumps, .view read [n | name]
------------------------------------------------------------
local INDEX_PATH = MOD_DIR .. "dumps.txt"   -- every file written, oldest first
local reader = nil                           -- { panel, text } while a dump is shown

local function DumpList()
    local list = {}
    local file = io.open(INDEX_PATH, "r")
    if not file then return list end
    for raw in file:lines() do
        local line = raw:gsub("%s+$", "")
        if line ~= "" then
            local f = io.open(MOD_DIR .. line, "r")
            if f then f:close() table.insert(list, 1, line) end   -- newest first, existing only
        end
    end
    file:close()
    return list
end

local function SplitCsv(line)
    local out, i, n = {}, 1, #line
    while i <= n + 1 do
        if line:sub(i, i) == '"' then
            local j, buf = i + 1, {}
            while j <= n do
                local c = line:sub(j, j)
                if c == '"' then
                    if line:sub(j + 1, j + 1) == '"' then table.insert(buf, '"') j = j + 2
                    else j = j + 1 break end
                else table.insert(buf, c) j = j + 1 end
            end
            table.insert(out, table.concat(buf))
            i = j + 1
        else
            local j = line:find(",", i, true) or (n + 1)
            table.insert(out, line:sub(i, j - 1))
            i = j + 1
        end
    end
    return out
end

-- name: a number from .view dumps, a file name (with or without .csv), or nil (newest)
local function FindDump(name)
    local list = DumpList()
    local n = tonumber(name)
    if not name or name == "" then return list[1], list end
    if n then return list[n], list end
    if not name:find("%.csv$") then name = name .. ".csv" end
    local f = io.open(MOD_DIR .. name, "r")
    if f then f:close() return name, list end
    return nil, list
end

local function LoadDump(fileName)
    local file = io.open(MOD_DIR .. fileName, "r")
    if not file then return nil end
    local header, rows, marks = nil, {}, {}
    for raw in file:lines() do
        local line = raw:gsub("\r$", "")
        if not header then
            header = {}
            for i, h in ipairs(SplitCsv(line)) do header[h] = i end
        elseif line ~= "" then
            local c = SplitCsv(line)
            local function num(k) return header[k] and tonumber(c[header[k]]) or nil end
            local row = { t = num("t"), dYaw = num("dYaw"), dPitch = num("dPitch"), mYaw = num("mouseYaw"),
                          mPitch = num("mousePitch"), mCalls = num("mouseCalls"), P = num("ctrl.P"), Y = num("ctrl.Y"),
                          camP = num("cam.P"), camY = num("cam.Y") }
            local mark = header.mark and c[header.mark] or ""
            if mark ~= "" then row.mark = mark end
            if mark ~= "" then table.insert(marks, { t = row.t, note = mark }) end
            table.insert(rows, row)
        end
    end
    file:close()
    return rows, marks
end

local function ReaderClose()
    if reader and reader.panel then pcall(function() reader.panel:RemoveFromParent() end) end
    reader = nil
end

local function ReaderShow(lines)
    ReaderClose()
    local hudObj = nil
    pcall(function() hudObj = FindFirstOf("BP_InventoryHUD_C") end)
    if not Valid(hudObj) then log("  (no HUD to show it on: load into a world)") return end
    RemoveLeftovers()
    local ok, panel, text = pcall(HudBuildPanel, hudObj, "left")
    if not ok then log("  (couldn't show it on screen: " .. tostring(panel) .. ")") return end
    SetText(text, table.concat(lines, "\n"))
    pcall(function() panel:SetVisibility(HIT_TEST_INVISIBLE) end)
    reader = { panel = panel, text = text }
end

local MAX_SHOWN_WALLS = 10

local opened = nil   -- { fileName, rows, marks, walls, page } of the dump last read

-- Loads a dump (see FindDump for name) into opened; false if there's none
local function OpenDump(name)
    local fileName, list = FindDump(name)
    if not fileName then
        if #list == 0 and (not name or name == "") then log("No dumps yet: .view buffer, then .view dump")
        else log("No dump '" .. tostring(name) .. "' - .view dumps lists them") end
        return false
    end
    local rows, marks = LoadDump(fileName)
    if not rows or #rows == 0 then log("Couldn't read " .. fileName) return false end
    opened = { fileName = fileName, rows = rows, marks = marks, walls = Walls(rows), first = 1 }
    return true
end

local RAW_ROWS = 30

local function Num3(v) return v and string.format("%8.3f", v) or "       -" end

-- One page of the raw rows: time, mouse input, how far the aim turned, where
-- the aim and camera point. STUCK: the mouse moved on an axis, the aim didn't
local function RawPage()
    local o = opened
    local rows, t0 = o.rows, o.rows[1].t or 0
    o.first = math.min(math.max(1, o.first), math.max(1, #rows - RAW_ROWS + 1))
    local first = o.first
    local lines = { string.format("RAW  %s   rows %d-%d of %d   (left / right arrow: page, Backspace: close, .view raw <s>: jump)",
                        o.fileName:gsub("%.csv$", ""), first, math.min(#rows, first + RAW_ROWS - 1), #rows),
                    "       t   mouseY   mouseP     turnY    turnP      aimP      aimY      camP      camY" }
    for i = first, math.min(#rows, first + RAW_ROWS - 1) do
        local r = rows[i]
        local stuck = ((r.mYaw or 0) ~= 0 and r.dYaw == 0)
            or ((r.mPitch or 0) ~= 0 and r.dPitch == 0 and not (r.P and math.abs(Wrap(r.P)) > 89.5))
        table.insert(lines, string.format("%8.3f %s %s  %s %s  %s %s  %s %s%s%s",
            (r.t or 0) - t0, Num3(r.mYaw), Num3(r.mPitch), Num3(r.dYaw), Num3(r.dPitch),
            Num3(r.P and Wrap(r.P)), Num3(r.Y), Num3(r.camP and Wrap(r.camP)), Num3(r.camY),
            stuck and "  STUCK" or "", r.mark and ("  mark: " .. r.mark) or ""))
    end
    return lines
end

local function ShowRaw()
    local lines = RawPage()
    ReaderShow(lines)
    if reader then reader.raw = true end   -- the arrow keys page while it's shown
    if not reader then for _, l in ipairs(lines) do log(l) end end   -- no HUD: the log
end

-- .view raw [seconds]: page at that time (default: the first wall, or the start)
local function Raw(at)
    if not opened and not OpenDump(nil) then return end
    local rows, t0 = opened.rows, opened.rows[1].t or 0
    local target = tonumber(at)
    if not target and #opened.walls > 0 then target = opened.walls[1].from end
    local index = 1
    if target then
        for i, r in ipairs(rows) do
            if (r.t or 0) - t0 >= target then index = i break end
            index = i
        end
        index = math.max(1, index - 3)   -- a few rows before it
    end
    opened.first = index
    ShowRaw()
end

local function Page(delta)
    if not opened then log("No dump open - .view read or .view raw first") return end
    opened.first = opened.first + delta * RAW_ROWS
    ShowRaw()
end

local function ReadDump(name)
    if reader and (not name or name == "") then ReaderClose() log("Dump closed") return end
    if not OpenDump(name) then return end
    local fileName, rows, marks = opened.fileName, opened.rows, opened.marks
    local seconds = (rows[#rows].t or 0) - (rows[1].t or 0)
    local inputs = 0
    for _, row in ipairs(rows) do inputs = inputs + (row.mCalls or 0) end
    local walls = opened.walls

    local lines = { string.format("DUMP  %s", fileName:gsub("%.csv$", "")),
                    string.format("%.1f s, %d samples, %d mouse inputs", seconds, #rows, inputs), "" }
    if inputs == 0 then
        table.insert(lines, "No mouse input recorded")
    elseif #walls == 0 then
        table.insert(lines, "No walls: your aim followed every mouse movement")
    else
        table.insert(lines, #walls .. " WALL(S): mouse moving, aim stuck")
        for i, w in ipairs(walls) do
            if i <= MAX_SHOWN_WALLS then table.insert(lines, WallText(w)) end
        end
        if #walls > MAX_SHOWN_WALLS then table.insert(lines, "... " .. (#walls - MAX_SHOWN_WALLS) .. " more in the log") end
    end
    for _, m in ipairs(marks) do table.insert(lines, string.format("mark at %.2f s: %s", m.t - (rows[1].t or 0), m.note)) end
    table.insert(lines, "")
    table.insert(lines, ".view raw: the recorded rows   Backspace or .view close: close")

    log("Read " .. fileName .. string.format(": %.1f s, %d samples, %d mouse inputs, %d wall(s)", seconds, #rows, inputs, #walls))
    for _, w in ipairs(walls) do log("  wall: " .. WallText(w)) end
    ReaderShow(lines)
end

local function ListDumps()
    local list = DumpList()
    if #list == 0 then log("No dumps yet: .view buffer, then .view dump (older ones: .view read <file name>)") return end
    log("Dumps, newest first (.view read <number>):")
    for i, name in ipairs(list) do
        if i <= 20 then log(string.format("  %d  %s", i, name)) end
    end
end

------------------------------------------------------------
-- Commands and the mark key
------------------------------------------------------------
local function Mark(note)
    note = (note and note ~= "") and note or "stuck"
    if hud then hud.markNote, hud.markUntil = note, os.clock() + 2 end
    if rec then
        pendingMark = note
    else
        ExecuteInGameThread(function() Snapshot(note) end)
    end
end

RegisterConsoleCommandHandler(".view", function(FullCommand, Parameters)
    local args = {}
    for _, p in ipairs(Parameters or {}) do table.insert(args, tostring(p)) end
    local a = string.lower(args[1] or "")
    if a == "mark" then
        Mark(table.concat(args, " ", 2))
        return true
    end
    ExecuteInGameThread(function()
        if a == "" then Snapshot()
        elseif a == "scan" then Scan()
        elseif a == "rec" or a == "record" then Start("rec", args[2])
        elseif a == "buffer" or a == "buf" then
            if rec and rec.mode == "buffer" then Finish("turned off") else Start("buffer", args[2]) end
        elseif a == "dump" then DumpNow()
        elseif a == "dumps" or a == "list" then ListDumps()
        elseif a == "read" or a == "open" then ReadDump(args[2])
        elseif a == "raw" then Raw(args[2])
        elseif a == "close" then
            if reader then ReaderClose() log("Dump closed") else log("Nothing open") end
        elseif a == "next" then Page(1)
        elseif a == "prev" or a == "back" then Page(-1)
        elseif a == "stop" then
            if rec then Finish("stopped") else log("Not recording") end
        elseif a == "watch" then Watch()
        elseif a == "hud" or a == "show" then HudToggle()
        elseif a == "limits" or a == "limit" then
            local pc, pcm = LocalController(), nil
            pcall(function() pcm = pc.PlayerCameraManager end)
            if Valid(pcm) then log("Camera limits now: " .. LimitsText(pcm))
            else log("No camera - load into a world first") end
        else
            log(".view | .view hud | .view buffer [seconds] | .view dump | .view dumps | .view read [n] | .view raw [s] | .view next / prev | .view close | .view rec [seconds] | .view stop | .view mark [note] | .view watch | .view limits | .view scan")
        end
    end)
    return true
end)

-- Backspace closes a dump on screen (summary or raw rows), only while one is
if Key.BACKSPACE then
    pcall(function()
        RegisterKeyBind(Key.BACKSPACE, function()
            if reader then ExecuteInGameThread(function() ReaderClose() end) end
        end)
    end)
end

-- Left / right arrow page the raw view, only while it's on screen
for keyName, delta in pairs({ LEFT_ARROW = -1, RIGHT_ARROW = 1 }) do
    if Key[keyName] then
        pcall(function()
            RegisterKeyBind(Key[keyName], function()
                if reader and reader.raw and opened then
                    ExecuteInGameThread(function() Page(delta) end)
                end
            end)
        end)
    end
end

if MARK_KEY == "" then
    -- no hotkey: .view mark / .view dump
elseif Key[MARK_KEY] then
    pcall(function() RegisterKeyBind(Key[MARK_KEY], function() Mark("key") end) end)
else
    log("markKey '" .. MARK_KEY .. "' isn't a key name; use .view mark")
end

log("Loaded v" .. VERSION .. ": .view buffer keeps the last " .. BUFFER_SECONDS .. " s of your view's angles, .view dump saves them"
    .. (MARK_KEY ~= "" and (" (or " .. MARK_KEY .. ")") or ""))
