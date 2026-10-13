------------------------------------------------------------
-- View Debug
------------------------------------------------------------
-- For the game's bug where the weapon / arms (the viewmodel) get stuck at an
-- angle after moving the mouse slowly. Changes nothing: it only reads your
-- view's angles and writes them down, so a later mod can fix it.
--
--   .view                 your view's angles now, in the log
--   .view scan            everything on your character that turns: its parts
--                         and their angles, plus every number setting that
--                         looks like aim / sway / rotation (scan_<time>.txt)
--   .view rec [seconds]   record the angles many times a second to
--                         recording_<time>.csv (stops by itself)
--   .view stop            stop recording now
--   .view mark [note]     mark this moment (or press the mark key, F11)
--   .view watch           print the main angles to the log 4 times a second
--
-- Settings: config.lua (see config.example.lua).
-- Only reads while recording or watching; it stops itself after a while.
------------------------------------------------------------
local VERSION = "0.1.0"
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
local MARK_KEY = tostring(cfg.markKey or "F11")
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

-- The object class's own settings (only its own class: walking parent
-- classes crashed this UE4SS build for the mod menu). fn(name, value, kind)
local function EachSetting(obj, fn)
    pcall(function()
        obj:GetClass():ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            if name ~= "" then
                local value = nil
                pcall(function() value = obj[name] end)
                local kind = Kind(value)
                if kind then fn(name, value, kind) end
            end
        end)
    end)
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

local function Build()
    local pc = LocalController()
    if not pc then return nil, "no local player controller (load into a world first)" end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not Valid(pawn) then return nil, "you have no character right now" end

    local cols, names = {}, {}
    local function add(name, get)
        if names[name] then name = name .. "#" .. (#cols + 1) end
        names[name] = true
        table.insert(cols, { name = name, get = get })
    end
    local function addValue(prefix, obj, propName, kind)
        if kind == "number" then
            add(prefix, function() return obj[propName] end)
        elseif kind == "bool" then
            add(prefix, function() return obj[propName] and 1 or 0 end)
        elseif kind == "rot" then
            add(prefix .. ".P", function() return obj[propName].Pitch end)
            add(prefix .. ".Y", function() return obj[propName].Yaw end)
            add(prefix .. ".R", function() return obj[propName].Roll end)
        elseif kind == "vec" then
            add(prefix .. ".X", function() return obj[propName].X end)
            add(prefix .. ".Y", function() return obj[propName].Y end)
            add(prefix .. ".Z", function() return obj[propName].Z end)
        elseif kind == "vec2" then
            add(prefix .. ".X", function() return obj[propName].X end)
            add(prefix .. ".Y", function() return obj[propName].Y end)
        end
    end

    -- Where you look (the controller) and what the camera shows
    addValue("ctrl", pc, "ControlRotation", "rot")
    local pcm = nil
    pcall(function() pcm = pc.PlayerCameraManager end)
    if Valid(pcm) then
        add("cam.P", function() return pcm.CameraCachePrivate.POV.Rotation.Pitch end)
        add("cam.Y", function() return pcm.CameraCachePrivate.POV.Rotation.Yaw end)
        add("cam.R", function() return pcm.CameraCachePrivate.POV.Rotation.Roll end)
        add("cam.FOV", function() return pcm.CameraCachePrivate.POV.FOV end)
    end

    -- Every part's angle and position relative to what it hangs on
    local parts = ComponentTree(pawn)
    local others, animInstances = {}, {}
    for _, p in ipairs(parts) do
        local comp = p.comp
        local owner = OwnerOf(comp)
        local label = NameOf(comp)
        if Valid(owner) and owner ~= pawn and NameOf(owner) ~= NameOf(pawn) then
            label = Short(NameOf(owner)) .. "/" .. label
            others[NameOf(owner)] = owner
        end
        addValue(label .. ".rel", comp, "RelativeRotation", "rot")
        addValue(label .. ".loc", comp, "RelativeLocation", "vec")
        local anim = nil
        pcall(function() anim = comp.AnimScriptInstance end)
        if Valid(anim) then table.insert(animInstances, { label = label, obj = anim }) end
    end

    -- Settings that sound like aim / sway / rotation on the character, its
    -- animation (arms sway usually lives there), the held items, the camera
    local function addSettings(prefix, obj)
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
    for name, obj in pairs(others) do addSettings(Short(name), obj) end

    return { pc = pc, pawn = pawn, pcm = pcm, cols = cols, parts = parts, anims = animInstances }
end

local function Read(col)
    local ok, v = pcall(col.get)
    if ok and type(v) == "number" then return v end
    return nil
end

local function Wrap(d)
    if d == nil then return nil end
    if d > 180 then d = d - 360 elseif d < -180 then d = d + 360 end
    return d
end

------------------------------------------------------------
-- Recording
------------------------------------------------------------
local rec = nil       -- { set, rows, start, until_, marks, stop }
local pendingMark = nil
local watching = nil

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

local function Finish(reason)
    local r = rec
    if not r then return end
    rec = nil
    r.stop = true
    local rows, cols = r.rows, r.set.cols
    if #rows == 0 then log("Recording stopped (" .. reason .. "): nothing recorded") return end

    -- Keep only the columns that changed (plus where you look), so the file is readable
    local keep = {}
    for i, col in ipairs(cols) do
        local first, changed, lo, hi = nil, false, math.huge, -math.huge
        for _, row in ipairs(rows) do
            local v = row.v[i]
            if v ~= nil then
                if first == nil then first = v elseif v ~= first then changed = true end
                if v < lo then lo = v end
                if v > hi then hi = v end
            end
        end
        if changed or col.name:find("^ctrl%.[PYR]$") or col.name:find("^cam%.") then
            table.insert(keep, { i = i, name = col.name, range = hi - lo, lo = lo, hi = hi })
        end
    end

    local path = MOD_DIR .. "recording_" .. r.stamp .. ".csv"
    local file = io.open(path, "w")
    if not file then log("Couldn't write " .. path) return end
    local header = { "t", "dYaw", "dPitch", "mark" }
    for _, k in ipairs(keep) do table.insert(header, Csv(k.name)) end
    file:write(table.concat(header, ",") .. "\n")
    for _, row in ipairs(rows) do
        local line = { Fmt(row.t), Fmt(row.dYaw), Fmt(row.dPitch), Csv(row.mark or "") }
        for _, k in ipairs(keep) do table.insert(line, Fmt(row.v[k.i])) end
        file:write(table.concat(line, ",") .. "\n")
    end
    file:close()

    local seconds = rows[#rows].t
    local slowTurns = 0
    for _, row in ipairs(rows) do
        local d = math.max(math.abs(row.dYaw or 0), math.abs(row.dPitch or 0))
        if d > 0 and d < 0.05 then slowTurns = slowTurns + 1 end
    end
    log(string.format("Recording stopped (%s): %d samples over %.1f s (%.0f a second), %d of %d values saved (the ones that changed)",
        reason, #rows, seconds, #rows / math.max(seconds, 0.001), #keep, #cols))
    log("  Samples with a very slow turn (under 0.05 degrees): " .. slowTurns)
    table.sort(keep, function(a, b) return a.range > b.range end)
    local shown = 0
    for _, k in ipairs(keep) do
        if shown < 15 and k.range > 0 then
            shown = shown + 1
            log(string.format("  changed most: %s  %s .. %s", k.name, Fmt(k.lo), Fmt(k.hi)))
        end
    end
    for _, m in ipairs(r.marks) do log(string.format("  mark at %.2f s: %s", m.t, m.note)) end
    log("  Saved: ue4ss\\Mods\\ViewDebug\\recording_" .. r.stamp .. ".csv - send this file")
end

local function Sample()
    local r = rec
    if not r or r.stop then return end
    local now = os.clock()
    if not Valid(r.set.pawn) then Finish("your character is gone") return end
    if now >= r.until_ then Finish("time's up") return end
    local v = {}
    for i, col in ipairs(r.set.cols) do v[i] = Read(col) end
    local row = { t = now - r.start, v = v }
    -- columns 1-2 are ctrl.P / ctrl.Y
    if r.last then
        row.dPitch = (v[1] and r.last[1]) and Wrap(v[1] - r.last[1]) or nil
        row.dYaw = (v[2] and r.last[2]) and Wrap(v[2] - r.last[2]) or nil
    end
    r.last = v
    if pendingMark then
        row.mark = pendingMark
        table.insert(r.marks, { t = row.t, note = pendingMark })
        log(string.format("Marked at %.2f s: %s", row.t, pendingMark))
        pendingMark = nil
    end
    table.insert(r.rows, row)
end

local function Start(seconds)
    if rec then log("Already recording - .view stop first") return end
    local set, err = Build()
    if not set then log("Can't record: " .. err) return end
    seconds = math.min(MAX_SECONDS, math.max(1, tonumber(seconds) or MAX_SECONDS))
    local now = os.clock()
    rec = { set = set, rows = {}, marks = {}, start = now, until_ = now + seconds, stamp = Stamp() }
    local mine = rec
    log(string.format("Recording %d values every %d ms for up to %d s. Press %s (or .view mark) when the view sticks, .view stop to end",
        #set.cols, SAMPLE_MS, seconds, MARK_KEY))
    local busy = false
    LoopAsync(SAMPLE_MS, function()
        if mine.stop or rec ~= mine then return true end
        if not busy then
            busy = true
            ExecuteInGameThread(function()
                pcall(Sample)
                busy = false
            end)
        end
        return false
    end)
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
    if watching then watching.stop = true watching = nil log("Watch off") return end
    local set, err = Build()
    if not set then log("Can't watch: " .. err) return end
    local meshes = MeshLabels(set)
    local mine = { stop = false, until_ = os.clock() + WATCH_SECONDS }
    watching = mine
    log("Watch on for " .. WATCH_SECONDS .. " s (.view watch again to stop)")
    local busy = false
    LoopAsync(250, function()
        if mine.stop then return true end
        if not busy then
            busy = true
            ExecuteInGameThread(function()
                pcall(function()
                    if os.clock() >= mine.until_ or not Valid(set.pawn) then
                        mine.stop = true
                        if watching == mine then watching = nil end
                        log("Watch off")
                        return
                    end
                    log("watch: " .. Line(set, function(n)
                        if IsMain(n) then return true end
                        local comp = n:match("([^/]+)%.rel%.[PY]$")
                        return comp ~= nil and meshes[comp] == true
                    end))
                end)
                busy = false
            end)
        end
        return false
    end)
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
-- Commands and the mark key
------------------------------------------------------------
local function Mark(note)
    note = (note and note ~= "") and note or "stuck"
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
        elseif a == "rec" or a == "record" then Start(args[2])
        elseif a == "stop" then
            if rec then Finish("stopped") else log("Not recording") end
        elseif a == "watch" then Watch()
        else
            log(".view | .view scan | .view rec [seconds] | .view stop | .view mark [note] | .view watch")
        end
    end)
    return true
end)

if Key[MARK_KEY] then
    pcall(function() RegisterKeyBind(Key[MARK_KEY], function() Mark("key") end) end)
else
    log("markKey '" .. MARK_KEY .. "' isn't a key name; use .view mark")
end

log("Loaded v" .. VERSION .. ": .view rec records your view's angles, " .. MARK_KEY .. " marks when it sticks")
