------------------------------------------------------------
-- YouTube TV (experimental)
------------------------------------------------------------
-- Turn on a TV in the world and it plays YouTube videos listed in config.lua,
-- with sound coming from the TV.
--
-- This first version finds out what works in this game, one step at a time,
-- and logs every step ([YouTubeTV] in UE4SS.log):
--
--   .tv probe        which video / sound pieces the game has
--   .tv download     downloads the videos in config.lua (yt-dlp, a minimized
--                    window; the game keeps running) into the videos folder
--   .tv list         the configured videos and which are downloaded
--   .tv scan         what you're looking at (a TV): its parts, materials, texture slots
--   .tv hud          plays the first video in a panel on your screen (tests playback)
--   .tv on [n]       turns on the TV you're looking at: a random video from a
--                    random point, like a real TV (n: video n from the start)
--   .tv next         another video
--   .tv turn / .tv mirror / .tv size 1.1   fix the picture on the TV's screen
--   .tv light 300    the light the screen gives off, brighter or dimmer (0 = off)
--   .tv off          stops it (the HUD panel too)
--   E menu on a TV   TURN ON TV / TURN OFF TV (eMenu = false in config.lua: off)
--   .tv learn        look at a TV: how the game's E menu works on it (for turning it on with E)
--   .tv seek <s>     jumps to s seconds into the video (tests what co-op needs)
--   .tv sync         joined someone: asks the host what's playing
--
-- Videos are downloaded with yt-dlp (+ ffmpeg) as H.264/AAC .mp4, which the
-- game's Windows video player (WMF) plays. Only the 11-character video ID is
-- taken from each link; the command is built from it, never from the link.
--
-- Co-op: the host's game decides. A joined player turning a TV on or off
-- asks the host; the host plays the video and tells every player which TV,
-- which video (its ID) and how far in. Each player's game plays its own copy
-- of the file (nothing is streamed through the game), jumping to the host's
-- point; a player who doesn't have the file gets it downloaded first.
------------------------------------------------------------
local VERSION = "0.5.14"
local MOD_DIR = "./ue4ss/Mods/YouTubeTV/"
local VIDEO_DIR = "ue4ss/Mods/YouTubeTV/videos/"   -- relative to the game's Win64 folder

local function log(msg)
    print("[YouTubeTV] " .. tostring(msg) .. "\n")
end

-- Hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local GameHook = require("GameHooks").ForMod("YouTubeTV")

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
local VOLUME = math.max(0, math.min(1, tonumber(cfg.volume) or 0.8))
local MAX_HEIGHT = math.floor(tonumber(cfg.maxHeight) or 720)
local SCAN_METERS = tonumber(cfg.scanMeters) or 8
-- Like a real TV: a random video, already somewhere in the middle
local SHUFFLE = cfg.shuffle ~= false
local RANDOM_START = cfg.randomStart ~= false
local HEAR_M = math.max(2, tonumber(cfg.hearDistance) or 15)              -- the TV is heard this far
local FULL_VOLUME_M = math.max(0, math.min(HEAR_M - 1, tonumber(cfg.fullVolumeDistance) or 1.5))
-- YouTube often refuses anonymous downloads ("confirm you're not a bot", age
-- checks). yt-dlp can use your browser's YouTube login instead:
-- "firefox", or "firefox:<profile folder>" for a Firefox-based browser like
-- Zen. Only known browser names and plain path characters are accepted, so
-- nothing else can get into the command.
local BROWSERS = { firefox = true, chrome = true, edge = true, brave = true, opera = true, vivaldi = true,
                   chromium = true, whale = true, safari = true }
local function CookiesArg(value)
    value = tostring(value or "")
    if value == "" then return "" end
    local browser, profile = value:match("^(%a+):(.+)$")
    browser = (browser or value):lower()
    if not BROWSERS[browser] then
        print("[YouTubeTV] cookiesFromBrowser: '" .. browser .. "' isn't a browser yt-dlp knows; ignored\n")
        return ""
    end
    if profile then
        if not profile:match("^[%w%s:\\/%._%-%(%)]+$") then
            print("[YouTubeTV] cookiesFromBrowser: the profile folder has characters that aren't allowed; ignored\n")
            return ""
        end
        return browser .. ":" .. profile
    end
    return browser
end
local COOKIES = CookiesArg(cfg.cookiesFromBrowser)

------------------------------------------------------------
-- Videos
------------------------------------------------------------
-- The 11-character ID from a YouTube link (watch?v=, youtu.be/, shorts/, embed/)
local function VideoId(link)
    link = tostring(link or "")
    local id = link:match("[?&]v=([%w_%-]+)") or link:match("youtu%.be/([%w_%-]+)")
        or link:match("/shorts/([%w_%-]+)") or link:match("/embed/([%w_%-]+)")
        or link:match("^([%w_%-]+)$")
    if id and #id == 11 and id:match("^[%w_%-]+$") then return id end
    return nil
end

local videos = {}   -- { { id, link } }
for _, link in ipairs(type(cfg.videos) == "table" and cfg.videos or {}) do
    local id = VideoId(link)
    if id then table.insert(videos, { id = id, link = link })
    else log("Not a YouTube video link, skipped: " .. tostring(link)) end
end

local function FileOf(id) return VIDEO_DIR .. id .. ".mp4" end

local function Downloaded(id)
    local f = io.open("./" .. FileOf(id), "rb")
    if not f then return false end
    local size = f:seek("end")
    f:close()
    return size and size > 0
end

-- yt-dlp: the WinGet install if it's there (the game may not see your PATH), else PATH
local function YtDlp()
    local localAppData = os.getenv("LOCALAPPDATA")
    if localAppData then
        local path = localAppData .. "\\Microsoft\\WinGet\\Links\\yt-dlp.exe"
        local f = io.open(path, "rb")
        if f then f:close() return '"' .. path .. '"' end
    end
    return "yt-dlp"
end

-- The yt-dlp command for one video (id: 11 checked characters: letters,
-- digits, - and _), run from the mod's folder
local function DownloadLine(id)
    local format = string.format(
        "bv*[vcodec^=avc1][height<=%d]+ba[ext=m4a]/b[ext=mp4][height<=%d]/b[ext=mp4]/bv*[height<=%d]+ba/b",
        MAX_HEIGHT, MAX_HEIGHT, MAX_HEIGHT)
    -- quoted: a profile folder can have spaces ("xzqhbajk.Default (release)")
    local cookies = COOKIES ~= "" and (' --cookies-from-browser "' .. COOKIES .. '"') or ""
    -- -P: the folder as a full path, so a download folder set in your own
    -- yt-dlp config (e.g. Downloads) doesn't move the videos there
    return string.format(
        '%s -f "%s" --merge-output-format mp4 --recode-video mp4 --no-playlist%s -P "%%~dp0videos" -o "%s.%%%%(ext)s" "https://www.youtube.com/watch?v=%s" > "videos\\%s.log" 2>&1',
        YtDlp(), format, cookies, id, id, id)
end

-- Writes a .cmd in the mod's folder and starts it in a minimized window (the
-- game keeps running). Returns true or nil, why
local function RunScript(name, lines)
    local all = { "@echo off", "cd /d \"%~dp0\"", "if not exist videos mkdir videos" }
    for _, l in ipairs(lines) do table.insert(all, l) end
    local script = io.open(MOD_DIR .. name, "wb")
    if not script then return nil, "couldn't write " .. name .. " in the mod's folder" end
    script:write(table.concat(all, "\r\n") .. "\r\n")
    script:close()
    local ok, result = pcall(os.execute, 'start "YouTubeTV download" /min "ue4ss\\Mods\\YouTubeTV\\' .. name .. '"')
    if not ok then return nil, "couldn't start it: " .. tostring(result) end
    return true
end

-- Writes download.cmd (one minimized window downloads every missing video in
-- turn, each with a log in videos\<id>.log) and starts it; the game keeps running
local function Download()
    if #videos == 0 then log("No videos in config.lua (videos = { \"https://www.youtube.com/watch?v=...\" })") return end
    local missing = {}
    for _, v in ipairs(videos) do
        if not Downloaded(v.id) then table.insert(missing, v.id) end
    end
    if #missing == 0 then log("All " .. #videos .. " videos are already downloaded") return end
    local lines = {}
    for _, id in ipairs(missing) do
        table.insert(lines, string.format("echo Downloading %s ...", id))
        table.insert(lines, DownloadLine(id))
    end
    local ok, why = RunScript("download.cmd", lines)
    if not ok then log("Couldn't start the download: " .. why) return end
    log("Downloading " .. #missing .. " video(s) in a minimized window" .. (COOKIES ~= "" and (" (with your " .. COOKIES:match("^%a+") .. " login)") or "")
        .. ". .tv list shows which are done, or why one failed")
end

-- Why a download failed: the last ERROR line yt-dlp wrote to videos\<id>.log
local function FailReason(id)
    local f = io.open("./" .. VIDEO_DIR .. id .. ".log", "r")
    if not f then return nil end
    local reason = nil
    for line in f:lines() do
        local e = line:match("ERROR:%s*(.+)")
        if e then reason = e end
    end
    f:close()
    if reason then
        -- (the log is in the Windows codepage: "you're" has a curly apostrophe)
        reason = reason:gsub("[\128-\255]+", "'"):gsub("%[youtube%]%s*[%w_%-]+:%s*", ""):gsub("%. Use %-%-cookies.*$", "")
        if reason:lower():find("sign in", 1, true) and COOKIES == "" then
            reason = reason .. " (set cookiesFromBrowser in config.lua)"
        end
    end
    return reason
end

local function List()
    if #videos == 0 then log("No videos in config.lua") return end
    for i, v in ipairs(videos) do
        local state = "downloaded"
        if not Downloaded(v.id) then
            local why = FailReason(v.id)
            state = why and ("failed: " .. why) or "not downloaded (.tv download)"
        end
        log(string.format("  %d  %s  %s", i, v.id, state))
    end
end

------------------------------------------------------------
-- Reading the game
------------------------------------------------------------
local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

-- An object's address, taken while it exists: compared later instead of
-- touching an old object, which crashes once the game has deleted it
local function AddressOf(obj)
    local a = nil
    pcall(function() a = obj:GetAddress() end)
    return a
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
        for _, pc in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if pc:IsValid() and pc:IsLocalController() then found = pc return end
        end
    end)
    return found
end

local function PlayerLocation()
    local loc = nil
    pcall(function()
        local l = LocalController().Pawn:K2_GetActorLocation()
        loc = { X = l.X, Y = l.Y, Z = l.Z }
    end)
    return loc
end

local function Distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100
end

local function Find(path)
    local obj = nil
    pcall(function() obj = StaticFindObject(path) end)
    return Valid(obj) and obj or nil
end

------------------------------------------------------------
-- .tv probe
------------------------------------------------------------
local PIECES = {
    { "/Script/MediaAssets.MediaPlayer", "plays video" },
    { "/Script/MediaAssets.MediaTexture", "the picture as a texture" },
    { "/Script/MediaAssets.MediaSoundComponent", "the sound, from a place in the world" },
    { "/Script/MediaAssets.FileMediaSource", "a video file" },
    { "/Script/MediaAssets.MediaComponent", "player + texture, made ready by the engine" },
    { "/Script/MediaPlate.MediaPlateComponent", "player + texture (Media Plate)" },
    { "/Script/MediaPlate.MediaPlate", "Media Plate actor" },
    { "/MediaPlate/M_MediaPlate.M_MediaPlate", "Media Plate's screen material (only if cooked)" },
    { "/Script/UMG.WidgetComponent", "a screen widget in the world" },
}

local function Probe()
    log("Probe (v" .. VERSION .. "):")
    for _, p in ipairs(PIECES) do
        log(string.format("  %-4s %s - %s", Find(p[1]) and "yes" or "NO", p[1], p[2]))
    end
    log("  videos in config.lua: " .. #videos)
    log("Done - send these lines")
end

------------------------------------------------------------
-- .tv scan: what you're looking at
------------------------------------------------------------
local TV_WORDS = { "tv", "telev", "monitor", "screen", "display", "telly" }

local function LooksLikeTv(text)
    text = text:lower()
    for _, w in ipairs(TV_WORDS) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

-- Static / skeletal mesh components of an actor
-- extra: a part that must be in the list (the one you aimed at)
local function Meshes(actor, extra)
    local list, seen = {}, {}
    pcall(function()
        Each(actor:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent")), function(c)
            if Valid(c) then table.insert(list, c) seen[NameOf(c)] = true end
        end)
    end)
    if extra and Valid(extra) and not seen[NameOf(extra)] then table.insert(list, 1, extra) end
    return list
end

local function MeshAssetName(comp)
    local name = ""
    pcall(function() name = NameOf(comp.StaticMesh) end)
    if name == "" then pcall(function() name = NameOf(comp.SkeletalMesh) end) end
    return name
end

-- Texture parameter names of a material (instances keep them; plain
-- materials in a cooked game usually don't)
local function TextureParams(mat)
    local names = {}
    local current = mat
    for _ = 1, 4 do   -- an instance's parents can add more
        if not Valid(current) then break end
        pcall(function()
            Each(current.TextureParameterValues, function(p)
                local n = ""
                pcall(function() n = p.ParameterInfo.Name:ToString() end)
                if n ~= "" then names[n] = true end
            end)
        end)
        local parent = nil
        pcall(function() parent = current.Parent end)
        current = parent
    end
    local list = {}
    for n in pairs(names) do table.insert(list, n) end
    table.sort(list)
    return list
end

local function Materials(comp)
    local list = {}
    local count = 0
    pcall(function() count = comp:GetNumMaterials() end)
    for i = 0, count - 1 do
        local mat = nil
        pcall(function() mat = comp:GetMaterial(i) end)
        table.insert(list, { slot = i, mat = mat })
    end
    return list
end

-- What you're looking at, up to SCAN_METERS away: a line traced from the
-- camera, like a shot. Only the one thing it hits is read - the engine just
-- found it, so it exists. (Going through every actor in the game crashed it
-- twice, 0.1.4 and 0.1.5: some listed actors are already being removed.)
-- Returns { actor, comp (the part hit), dist } or nil, why
local function LookedAt(verbose)
    local function step(what) if verbose then log("  " .. what) end end
    local pc = LocalController()
    if not pc then return nil, "load into a world first" end
    local pawn, cam = nil, nil
    pcall(function() pawn = pc.Pawn end)
    pcall(function() cam = pc.PlayerCameraManager end)
    if not Valid(pawn) or not Valid(cam) then return nil, "load into a world first" end
    local from, rot = nil, nil
    pcall(function() from = cam:GetCameraLocation() end)
    pcall(function() rot = cam:GetCameraRotation() end)
    if not from or not rot then return nil, "couldn't read the camera" end
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    local reach = SCAN_METERS * 100
    local to = { X = from.X + math.cos(p) * math.cos(y) * reach, Y = from.Y + math.cos(p) * math.sin(y) * reach,
                 Z = from.Z + math.sin(p) * reach }
    local kismet = Find("/Script/Engine.Default__KismetSystemLibrary")
    if not kismet then return nil, "KismetSystemLibrary not found" end
    step("tracing from the camera")
    local hit, result = false, {}
    local ok, err = pcall(function()
        local color = { R = 0, G = 0, B = 0, A = 0 }
        -- channel 0 = Visibility, no debug lines, ignore yourself
        hit = kismet:LineTraceSingle(pawn, { X = from.X, Y = from.Y, Z = from.Z }, to, 0, false, {}, 0, result,
                                     true, color, color, 0.0)
    end)
    if not ok then return nil, "the trace failed: " .. tostring(err) end
    if not hit then return nil, "nothing within " .. SCAN_METERS .. " m where you're looking" end
    step("hit something")
    local hitObj, comp = nil, nil
    pcall(function() hitObj = result.HitObjectHandle.ReferenceObject:Get() end)
    pcall(function() comp = result.Component:Get() end)
    if not Valid(comp) then comp = nil end
    -- The engine may name the part hit (a mesh component) instead of the thing
    -- it belongs to: go up to its owner, the TV
    local actor = nil
    local function ownerOf(c)
        local o = nil
        pcall(function() o = c:GetOwner() end)
        return Valid(o) and o or nil
    end
    if Valid(hitObj) and ClassName(hitObj):find("Component$") then
        comp = comp or hitObj
        actor = ownerOf(hitObj)
    elseif Valid(hitObj) then
        actor = hitObj
    end
    if not actor and comp then actor = ownerOf(comp) end
    if not actor then return nil, "hit something that isn't an object the mod can read" end
    step("hit " .. NameOf(actor) .. (comp and (", part " .. NameOf(comp)) or ""))
    local dist = 0
    pcall(function() dist = result.Distance / 100 end)
    return { actor = actor, comp = comp, dist = dist }
end

local function Scan()
    local target, err = LookedAt(true)
    if not target then log("Scan: " .. err) return end
    local tvLike = LooksLikeTv(ClassName(target.actor)) or LooksLikeTv(NameOf(target.actor))
    log(string.format("Scan: looking at %s (%s), %.1f m%s", NameOf(target.actor), ClassName(target.actor), target.dist,
        tvLike and " - looks like a TV" or ""))
    if target.comp then log("  the part you're looking at: " .. NameOf(target.comp) .. " (" .. ClassName(target.comp) .. ")") end
    for _, m in ipairs(Meshes(target.actor, target.comp)) do
        log("    mesh " .. NameOf(m) .. " = " .. MeshAssetName(m))
        for _, sl in ipairs(Materials(m)) do
            local params = TextureParams(sl.mat)
            log(string.format("      slot %d: %s (%s)  textures: %s", sl.slot, NameOf(sl.mat), ClassName(sl.mat),
                #params > 0 and table.concat(params, ", ") or "-"))
        end
    end
    log("Done - send these lines")
end

------------------------------------------------------------
-- Playback: a player and its texture, made by an engine component
------------------------------------------------------------
-- tv = { actor, media, player, texture, sound, dmi, index, hud = { panel } }
local tv = nil

-- Adds a component of the given class to an actor, registered (so it gets
-- set up like one made in the editor)
local IDENTITY = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
                   Scale3D = { X = 1, Y = 1, Z = 1 } }

-- setup(comp): runs before the component starts (deferred), for settings it
-- only reads when it starts, like a sound's
local function AddComponent(actor, classPath, setup)
    local cls = Find(classPath)
    if not cls then return nil, classPath .. " isn't in this game" end
    local comp = nil
    local ok, err = pcall(function()
        comp = actor:AddComponentByClass(cls, false, IDENTITY, setup ~= nil)
    end)
    if not ok or not Valid(comp) then return nil, "AddComponentByClass failed: " .. tostring(err) end
    if setup then
        pcall(setup, comp)
        local okFinish, e = pcall(function() actor:FinishAddComponent(comp, false, IDENTITY) end)
        if not okFinish then log("  FinishAddComponent failed: " .. tostring(e)) end
    end
    return comp
end

-- A media player + texture on the actor. The engine's Media Plate first: it
-- opens a video at a start time given in plain seconds (StartTime), which is
-- how a TV starts in the middle of a video. The player's own Seek takes a
-- Timespan, which this UE4SS can't build or read (0.5.1 tried; it may also
-- have broken memory the garbage collector then crashed on). MediaComponent
-- (from the start only) if Media Plate doesn't work.
-- Returns comp, player, texture, isPlate or nil, why
local PLATE = "/Script/MediaPlate.MediaPlateComponent"
local function MakePlayer(actor)
    local tried = {}
    for _, path in ipairs({ PLATE, "/Script/MediaAssets.MediaComponent" }) do
        local isPlate = path == PLATE
        local setup = nil
        if isPlate then
            setup = function(plate)   -- before it starts
                pcall(function() plate.bAutoPlay = false end)
                pcall(function() plate.bPlayOnOpen = true end)
                pcall(function() plate.bEnableAudio = false end)          -- the TV's own sound comes from AttachSound
                pcall(function() plate.bPlayOnlyWhenVisible = false end)  -- it has no mesh of its own to be seen on
                pcall(function() plate.bLoop = false end)
            end
        end
        local comp, err = AddComponent(actor, path, setup)
        if comp then
            local player, texture = nil, nil
            pcall(function() player = comp:GetMediaPlayer() end)
            pcall(function() texture = isPlate and comp:GetMediaTexture(0) or comp:GetMediaTexture() end)
            if Valid(player) and Valid(texture) then
                log("  player and texture from " .. path:match("%.(%w+)$")
                    .. (isPlate and " (starts anywhere in a video)" or " (videos start from the beginning)"))
                return comp, player, texture, isPlate
            end
            table.insert(tried, path:match("%.(%w+)$") .. ": no player/texture")
            pcall(function() comp:K2_DestroyComponent(comp) end)
        else
            table.insert(tried, err)
        end
    end
    return nil, table.concat(tried, "; ")
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- A video's length in seconds, from its .mp4 header (the moov box's mvhd):
-- read from the file, so the game's player isn't asked
local function Mp4Length(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local function u32(s, i)
        local a, b, c, d = s:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    -- the box of type want between from and to: where its content starts and ends
    local function find(from, to, want)
        local pos = from
        for _ = 1, 10000 do
            if pos + 8 > to then return nil end
            f:seek("set", pos)
            local h = f:read(16)
            if not h or #h < 8 then return nil end
            local size, kind, header = u32(h, 1), h:sub(5, 8), 8
            if size == 1 and #h >= 16 then size, header = u32(h, 9) * 4294967296 + u32(h, 13), 16
            elseif size == 0 then size = to - pos end
            if size < header then return nil end
            if kind == want then return pos + header, pos + size end
            pos = pos + size
        end
    end
    local length = nil
    pcall(function()
        local moov, moovEnd = find(0, f:seek("end"), "moov")
        local mvhd = moov and find(moov, moovEnd, "mvhd")
        if not mvhd then return end
        f:seek("set", mvhd)
        local d = f:read(32)
        local scale, duration
        if d:byte(1) == 1 then scale, duration = u32(d, 21), u32(d, 25) * 4294967296 + u32(d, 29)
        else scale, duration = u32(d, 13), u32(d, 17) end
        if scale > 0 then length = duration / scale end
    end)
    f:close()
    return length
end

local function LengthOfId(id) return Mp4Length("./" .. FileOf(id)) end

-- The video file for Media Plate, as a full path (a relative one would be
-- taken from the game's Content folder)
local function FullPath(id)
    local full = nil
    pcall(function()
        full = Find("/Script/Engine.Default__KismetSystemLibrary"):ConvertToAbsolutePath(FileOf(id))
    end)
    if type(full) ~= "string" then pcall(function() full = full:ToString() end) end
    return type(full) == "string" and full ~= "" and full or FileOf(id)
end

-- Media Plate opened nothing in 0.5.2 (dark TV). Until it's seen playing,
-- each open is checked after 2 s; if it isn't playing, the log says what the
-- player reports and that TV (and later ones) use the player directly, from
-- the start. plateWorks: nil = not known yet, true, false
local plateWorks = nil
local CheckPlate   -- (below OpenAt)
local Broadcast    -- (co-op, below)
local PlacePanel   -- (the screen, below)
local LightOf      -- (its light, below)

-- Opens a downloaded video on a TV (entry = tv: its media component, player
-- and whether it's a Media Plate) at seconds in. Returns the point it starts
-- at (0 without Media Plate), or nil, why. label says which it is in the log.
local function OpenAt(entry, id, at, label)
    if not Downloaded(id) then return nil, id .. " isn't downloaded yet (.tv download, then .tv list)" end
    at = math.max(0, at or 0)
    local length = LengthOfId(id)
    if length and at > length - 2 then at = math.max(0, length - 2) end   -- (it ended: the last moments)
    if entry.plate and plateWorks ~= false then
        local ok, err = pcall(function()
            local plate = entry.media
            local list = plate.MediaPlaylist
            if not Valid(list) then error("the Media Plate has no playlist", 0) end
            entry.platePath = FullPath(id)
            if list:AddFile(entry.platePath) == false then error("its playlist refused the file", 0) end
            -- only this video in it: at its end Media Plate would go on to the
            -- older ones by itself (from the start point still set)
            for _ = 2, list:Num() do list:RemoveAt(0) end
            plate.PlaylistIndex = list:Num() - 1
            -- it only opens media while its mesh is visible (0.5.3 stayed dark): the
            -- screen panel is its mesh. It mustn't reshape it: by default it
            -- stretches its mesh to the video's shape (0.5.4 made the screen a block)
            pcall(function() plate:SetIsAspectRatioAuto(false) end)
            pcall(function() plate:SetLetterboxAspectRatio(0) end)
            if Valid(entry.panel) then pcall(function() plate.StaticMeshComponent = entry.panel end) end
            plate.StartTime = at
            plate:Open()
        end)
        if not ok then return nil, "Media Plate couldn't open it: " .. tostring(err) end
        CheckPlate(entry, id, label)
    else
        at = 0
        -- starts by itself once opened (a component's player may have it off)
        pcall(function() entry.player.PlayOnOpen = true end)
        local ok, opened = pcall(function() return entry.player:OpenFile(FileOf(id)) end)
        if not ok then return nil, "OpenFile failed: " .. tostring(opened) end
        pcall(function() entry.player:SetLooping(false) end)
    end
    entry.openedAt = os.clock()
    log(string.format("  opening %s (%s)%s%s", label or "video", id, at >= 1 and (" at " .. Clock(at)) or " from the start",
        length and (" of " .. Clock(length)) or ""))
    return at
end

local function PlayerState(p)
    local parts = {}
    for _, f in ipairs({ "IsPreparing", "IsReady", "IsPlaying", "IsClosed", "HasError" }) do
        local v = nil
        pcall(function() v = p[f](p) end)
        table.insert(parts, f:gsub("^Is", ""):gsub("^Has", ""):lower() .. "=" .. tostring(v))
    end
    local url = nil
    pcall(function() url = p:GetUrl():ToString() end)
    if url == nil then pcall(function() url = tostring(p:GetUrl()) end) end
    table.insert(parts, "url=" .. tostring(url))
    return table.concat(parts, " ")
end

CheckPlate = function(entry, id, label)
    local done = false
    LoopAsync(2000, function()
        ExecuteInGameThread(function()
            if done then return end
            done = true
            if tv ~= entry or entry.id ~= id then return end
            -- the screen's own size and place again, in case Media Plate changed them
            if Valid(entry.panel) and entry.placed then PlacePanel(entry.panel, entry.placed) end
            if plateWorks ~= nil then return end
            local playing = false
            pcall(function() playing = entry.player:IsPlaying() or entry.player:IsPreparing() end)
            if playing then
                plateWorks = true
                log("  Media Plate plays (" .. PlayerState(entry.player) .. ")")
                return
            end
            local plateState = "?"
            pcall(function() plateState = "playing=" .. tostring(entry.media.bIsMediaPlatePlaying) .. " index=" .. tostring(entry.media.PlaylistIndex) end)
            -- what it was given: the file, as Media Plate's source sees it
            local source, url, valid = nil, "?", "?"
            pcall(function() source = entry.media.MediaPlaylist:Get(entry.media.PlaylistIndex) end)
            if Valid(source) then
                pcall(function() url = source:GetUrl():ToString() end)
                if url == "?" then pcall(function() url = tostring(source:GetUrl()) end) end
                pcall(function() valid = tostring(source:Validate()) end)
            end
            local exists = false
            if entry.platePath then
                local f = io.open(entry.platePath, "rb")
                if f then exists = true f:close() end
            end
            plateState = plateState .. "; path " .. tostring(entry.platePath) .. " (file there: " .. tostring(exists)
                .. "), source " .. (Valid(source) and ("url=" .. url .. " valid=" .. valid) or "missing")
            log("  Media Plate didn't start the video (player: " .. PlayerState(entry.player) .. "; plate: " .. plateState
                .. ") - TVs now play from the start instead. Send these lines")
            plateWorks = false
            pcall(function() entry.media:Close() end)
            local at = OpenAt(entry, id, 0, label)
            if at then
                entry.startClock = os.clock() - at
                if Broadcast then Broadcast() end
            end
        end)
        return true
    end)
end

-- .tv status: what the player says about itself now. If it's ready but not
-- playing, it's told to play.
local function Status()
    if not tv then log("Nothing playing - .tv hud or .tv on first") return end
    local p, t = tv.player, tv.texture
    local function get(label, fn)
        local ok, v = pcall(fn)
        local text
        if not ok then text = "(error: " .. tostring(v) .. ")"
        elseif type(v) == "userdata" or type(v) == "table" then
            local parts = {}
            -- names and strings first (an FName answers X / Y with itself)
            local okS, s = pcall(function() return v:ToString() end)
            if okS and type(s) == "string" then
                table.insert(parts, s)
            else
                for _, k in ipairs({ "X", "Y" }) do
                    local okk, kv = pcall(function() return v[k] end)
                    if okk and (type(kv) == "number" or type(kv) == "string") then
                        table.insert(parts, k .. "=" .. tostring(kv))
                    end
                end
            end
            text = #parts > 0 and table.concat(parts, " ") or tostring(v)
        else text = tostring(v) end
        log(string.format("  %-22s %s", label, text))
        return ok and v or nil
    end
    log("Status of video " .. tostring(tv.index) .. ":")
    get("decoder", function() return p:GetPlayerName() end)
    get("url", function() return p:GetUrl() end)
    get("play on open", function() return p.PlayOnOpen end)
    local ready = get("ready", function() return p:IsReady() end)
    get("preparing", function() return p:IsPreparing() end)
    local playing = get("playing", function() return p:IsPlaying() end)
    get("paused", function() return p:IsPaused() end)
    get("closed", function() return p:IsClosed() end)
    get("player", function() return tv.plate and "Media Plate" or "MediaComponent (from the start only)" end)
    get("length", function() local l = tv.id and LengthOfId(tv.id) return l and Clock(l) or "?" end)
    get("time (about)", function() return tv.startClock and Clock(os.clock() - tv.startClock) or "?" end)
    get("rate", function() return p:GetRate() end)
    get("video tracks", function() return p:GetNumTracks(6) end)   -- 6 = video
    get("audio tracks", function() return p:GetNumTracks(0) end)   -- 0 = audio
    get("video size", function() return p:GetVideoTrackDimensions(-1, -1) end)
    get("texture size", function() return string.format("%sx%s", tostring(t:GetWidth()), tostring(t:GetHeight())) end)
    get("sound active", function() return tv.sound and tv.sound:IsActive() end)
    if ready == true and playing ~= true then
        local ok, played = pcall(function() return p:Play() end)
        log("  ready but not playing - told it to play: " .. tostring(ok and played))
    end
    log("Done - send these lines")
end

-- inWorld: the sound comes from the actor (positioned, fading with distance);
-- otherwise it plays straight to you (the .tv hud test)
local function AttachSound(actor, player, inWorld)
    local function setup(sound)
        if not inWorld then return end
        -- one channel: a stereo sound can't come from one point
        pcall(function() sound.Channels = 0 end)                       -- EMediaSoundChannels::Mono
        pcall(function() sound.bAllowSpatialization = true end)
        pcall(function() sound.bOverrideAttenuation = true end)
        pcall(function()
            local a = sound.AttenuationOverrides
            a.bAttenuate = true
            a.bSpatialize = true
            a.AttenuationShape = 0                                   -- sphere
            a.AttenuationShapeExtents = { X = FULL_VOLUME_M * 100, Y = 0, Z = 0 }
            a.FalloffDistance = math.max(100, (HEAR_M - FULL_VOLUME_M) * 100)
            a.DistanceAlgorithm = 1                                  -- logarithmic: like a real speaker
        end)
    end
    local sound, err = AddComponent(actor, "/Script/MediaAssets.MediaSoundComponent", setup)
    if not sound then log("  no sound: " .. err) return nil end
    pcall(function() sound:SetMediaPlayer(player) end)
    pcall(function() sound:SetVolumeMultiplier(VOLUME) end)
    if inWorld then
        local spatial, mono = nil, nil
        pcall(function() spatial = sound.bAllowSpatialization and sound.AttenuationOverrides.bSpatialize end)
        pcall(function() mono = sound.Channels end)
        log(string.format("  sound from the TV: heard up to %d m (positioned: %s, channels: %s)", HEAR_M,
            tostring(spatial), tostring(mono)))
    else
        log("  sound attached (straight to you)")
    end
    return sound
end

-- A TV's player, sound and screen, kept after it's turned off and used again
-- when it's turned back on: [actor name] = { actor, media, player, texture,
-- sound, panel, placed, dmi }. Deleting them while the engine's video and
-- audio threads still used them (off right after on) crashed the game (0.4.3).
local kept = {}

local function Stop()
    if not tv then log("Nothing playing") return end
    if tv.plate then pcall(function() tv.media:Close() end) end
    pcall(function() tv.player:Close() end)
    if tv.hud and tv.hud.panel then pcall(function() tv.hud.panel:RemoveFromParent() end) end
    if Valid(tv.panel) then pcall(function() tv.panel:SetVisibility(false, false) end) end
    local light = LightOf(tv)
    if light then pcall(function() light:SetVisibility(false, false) end) end
    if tv.mesh and tv.oldMaterial then pcall(function() tv.mesh:SetMaterial(tv.slot, tv.oldMaterial) end) end
    if tv.addr and not tv.hud then kept[tv.addr] = tv end   -- the HUD test's are left alone too
    tv = nil
    log("TV off")
end

------------------------------------------------------------
-- .tv hud: the picture in a panel on the HUD (tests playback by itself)
------------------------------------------------------------
local UMG = "/Script/UMG."
local function Construct(className, outer)
    local cls = StaticFindObject(UMG .. className)
    if not Valid(cls) then error(className .. " class not found", 0) end
    local obj = StaticConstructObject(cls, outer)
    if not Valid(obj) then error("could not create " .. className, 0) end
    return obj
end

local function HudPanel(texture)
    local hudObj = nil
    pcall(function() hudObj = FindFirstOf("BP_InventoryHUD_C") end)
    if not Valid(hudObj) then return nil, "no HUD" end
    local tree = hudObj.WidgetTree
    local panel = Construct("Border", tree)
    pcall(function() panel:SetBrushColor({ R = 0, G = 0, B = 0, A = 1 }) end)
    pcall(function() panel:SetPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 }) end)
    local image = Construct("Image", tree)
    pcall(function() image:SetBrushResourceObject(texture) end)
    pcall(function() image:SetDesiredSizeOverride({ X = 640, Y = 360 }) end)
    panel:SetContent(image)
    local root = hudObj.WidgetTree.RootWidget
    if ClassName(root) == "CanvasPanel" then
        local slot = root:AddChildToCanvas(panel)
        pcall(function() slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } }) end)
        pcall(function() slot:SetAlignment({ X = 1, Y = 0 }) end)
        pcall(function() slot:SetPosition({ X = -24, Y = 24 }) end)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(98) end)
    else
        local slot = root:AddChildToOverlay(panel)
        pcall(function() slot:SetHorizontalAlignment(3) end)
        pcall(function() slot:SetVerticalAlignment(1) end)
    end
    pcall(function() panel:SetVisibility(3) end)
    return { panel = panel, image = image }
end

local function Hud(index)
    if tv then Stop() end
    local pc = LocalController()
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not Valid(pawn) then log("Load into a world first") return end
    log("HUD test:")
    local media, player, texture, isPlate = MakePlayer(pawn)
    if not media then log("  no player: " .. tostring(player)) return end
    tv = { actor = pawn, media = media, player = player, texture = texture, plate = isPlate, index = index or 1 }
    tv.sound = AttachSound(pawn, player, false)
    local hud, err = HudPanel(texture)
    if hud then tv.hud = hud log("  panel shown top right") else log("  no panel: " .. err) end
    local v = videos[tv.index]
    local at, why = nil, "no video " .. tv.index .. " in config.lua"
    if v then at, why = OpenAt(tv, v.id, 0, "video " .. tv.index) end
    if not at then log("  " .. why) end
    log("Done - if the panel stays black or silent, send these lines (.tv off stops it)")
end

------------------------------------------------------------
-- The TV's own screen: a thin panel on the TV's front
------------------------------------------------------------
-- A TV like MISERY's (one mesh, one texture for the casing and the screen
-- together) can't have just its screen swapped: the video would cover the
-- whole TV. So the TV is left alone and gets a thin panel (the engine's cube,
-- flattened) on the side facing you, showing the video.
local CUBE = "/Engine/BasicShapes/Cube.Cube"
local SCREEN_WIDTH = math.max(0.2, math.min(1.2, tonumber(cfg.screenWidth) or 0.8))     -- of the TV's front
local SCREEN_HEIGHT = math.max(0.2, math.min(1.2, tonumber(cfg.screenHeight) or 0.75))
-- A real TV glows: the picture shows in a dark room (an unlit material, the
-- engine's own one for 3D widgets), and it lights the room in front of it
local GLOW = cfg.glowScreen ~= false
local GLOW_MATERIAL = "/Engine/EngineMaterials/Widget3DPassThrough_Opaque.Widget3DPassThrough_Opaque"
local GLOW_PARAM = "SlateUI"
local LIGHT_CD = math.max(0, tonumber(cfg.lightBrightness) or 60)      -- candelas at its brightest (0 = no light)
local LIGHT_M = math.max(1, tonumber(cfg.lightDistance) or 4)          -- it reaches this far
-- Like a real screen the light changes with the picture: a new scene every
-- few seconds (brighter or darker, a bit warmer or cooler) and a slight
-- flicker in between. Off unless lightFlicker = true: a steady light
local FLICKER = cfg.lightFlicker == true   -- off by default: it cost FPS for little

local function LoadObject(path)
    local obj = Find(path)
    if obj then return obj end
    pcall(function() LoadAsset(path) end)
    return Find(path)
end

-- Turns a local offset (x, y, z) by a yaw in degrees
local function Turn(x, y, yawDeg)
    local a = math.rad(yawDeg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
end

-- Where the panel goes: the face of the TV mesh's box that points at you
-- (you look at the screen when you turn it on), or the given face (co-op: the
-- side the player who turned it on chose: 0 +X, 1 -X, 2 +Y, 3 -Y, in the TV's
-- own directions). Returns location, rotation, width and height in cm, face.
local function FrontOf(mesh, face)
    local box, loc, rot, scale = nil, nil, nil, nil
    pcall(function() box = mesh.StaticMesh:GetBoundingBox() end)
    pcall(function() loc = mesh:K2_GetComponentLocation() end)
    pcall(function() rot = mesh:K2_GetComponentRotation() end)
    pcall(function() scale = mesh:K2_GetComponentScale() end)
    if not (box and loc and rot and scale) then return nil, "couldn't read the TV's size" end
    local min, max = box.Min, box.Max
    local sx, sy, sz = scale.X, scale.Y, scale.Z
    local cx, cy, cz = (min.X + max.X) / 2 * sx, (min.Y + max.Y) / 2 * sy, (min.Z + max.Z) / 2 * sz
    local hx, hy, hz = (max.X - min.X) / 2 * math.abs(sx), (max.Y - min.Y) / 2 * math.abs(sy), (max.Z - min.Z) / 2 * math.abs(sz)
    if face == nil then
        -- you, in the TV's own directions
        local here = PlayerLocation()
        if not here then return nil, "load into a world first" end
        local lx, ly = Turn(here.X - loc.X, here.Y - loc.Y, -rot.Yaw)
        -- the side facing you: along the TV's X or Y, whichever points at you more
        if math.abs(lx) >= math.abs(ly) then face = lx >= 0 and 0 or 1
        else face = ly >= 0 and 2 or 3 end
    end
    local faceYaw, across
    if face == 0 or face == 1 then
        faceYaw = face == 0 and 0 or 180
        across = hy
        cx = cx + (face == 0 and 1 or -1) * (hx + 0.5)
    else
        faceYaw = face == 2 and 90 or -90
        across = hx
        cy = cy + (face == 2 and 1 or -1) * (hy + 0.5)
    end
    local wx, wy = Turn(cx, cy, rot.Yaw)
    return { X = loc.X + wx, Y = loc.Y + wy, Z = loc.Z + cz },
           { Pitch = 0, Yaw = rot.Yaw + faceYaw, Roll = 0 },
           across * 2 * SCREEN_WIDTH, hz * 2 * SCREEN_HEIGHT, face
end

-- Builds the panel on the actor showing texture through material's param.
-- Returns the panel or nil, why
local function MakePanel(actor, mesh, material, param, texture, face)
    local cube = LoadObject(CUBE)
    if not cube then return nil, "the engine's cube shape isn't in this game (" .. CUBE .. ")" end
    local where, rot, width, height
    where, rot, width, height, face = FrontOf(mesh, face)
    if not where then return nil, rot end
    local panel, err = AddComponent(actor, "/Script/Engine.StaticMeshComponent")
    if not panel then return nil, err end
    pcall(function() panel:SetCollisionEnabled(0) end)   -- you walk and shoot through it
    pcall(function() panel:SetCastShadow(false) end)
    pcall(function() panel:SetStaticMesh(cube) end)
    -- the glowing material if it's there and has its texture slot (it then
    -- has a default texture in it); else the TV's own (lit: dark in a dark room)
    local dmi = nil
    if GLOW then
        local glow = LoadObject(GLOW_MATERIAL)
        if glow then
            pcall(function() dmi = panel:CreateDynamicMaterialInstance(0, glow, FName("YouTubeTVScreen")) end)
            local has = false
            pcall(function() has = Valid(dmi:K2_GetTextureParameterValue(FName(GLOW_PARAM))) end)
            if has then param = GLOW_PARAM else dmi = nil end
        end
        if dmi then log("  the screen glows (unlit material)")
        else log("  the glowing screen material isn't in this game - the picture is lit like the TV") end
    end
    if not dmi then
        pcall(function() dmi = panel:CreateDynamicMaterialInstance(0, material, FName("YouTubeTVScreen")) end)
    end
    if not Valid(dmi) then
        pcall(function() panel:K2_DestroyComponent(panel) end)
        return nil, "couldn't make the screen's material"
    end
    local ok, e = pcall(function() dmi:SetTextureParameterValue(FName(param), texture) end)
    if not ok then
        pcall(function() panel:K2_DestroyComponent(panel) end)
        return nil, "SetTextureParameterValue failed: " .. tostring(e)
    end
    local placed = { where = where, rot = rot, width = width, height = height, turn = 0, mirror = false, face = face }
    return panel, placed, dmi
end

-- The light the screen gives off: a soft rectangle of light the screen's
-- size, just in front of it, casting no shadows (cheap). Returns it or nil
local function MakeLight(actor)
    if LIGHT_CD <= 0 then return nil end
    -- Cheap: a spot light (0.5.9-0.5.12's rectangle light, the most
    -- expensive kind, cost a lot of FPS), set before it starts so the engine
    -- never prepares what it doesn't need: no shadows, no bounce light
    -- (Lumen), no fog or see-through lighting, no specular
    local light, err = AddComponent(actor, "/Script/Engine.SpotLightComponent", function(l)
        pcall(function() l.Mobility = 2 end)   -- movable: it's added while the game runs
        pcall(function() l.CastShadows = false end)
        pcall(function() l.CastStaticShadows = false end)
        pcall(function() l.CastDynamicShadows = false end)
        pcall(function() l.bAffectTranslucentLighting = false end)
        pcall(function() l.bAffectGlobalIllumination = false end)
        pcall(function() l.IndirectLightingIntensity = 0 end)
        pcall(function() l.VolumetricScatteringIntensity = 0 end)
        pcall(function() l.SpecularScale = 0 end)
        pcall(function() l.bUseInverseSquaredFalloff = true end)
        pcall(function() l.AttenuationRadius = LIGHT_M * 100 end)
        pcall(function() l.OuterConeAngle = 70 end)
        pcall(function() l.InnerConeAngle = 25 end)
        pcall(function() l.SourceRadius = 20 end)
    end)
    if not light then log("  no light from the screen: " .. tostring(err)) return nil end
    pcall(function() light:SetCastShadows(false) end)
    pcall(function() light:SetIntensityUnits(1) end)   -- candelas
    pcall(function() light:SetIntensity(LIGHT_CD) end)
    pcall(function() light:SetAttenuationRadius(LIGHT_M * 100) end)
    pcall(function() light:SetLightColor({ R = 0.75, G = 0.85, B = 1.0, A = 1.0 }, true) end)   -- a screen's cool white
    local units, intensity = "?", "?"
    pcall(function() units = tostring(light.IntensityUnits) end)
    pcall(function() intensity = tostring(light.Intensity) end)
    log(string.format("  light from the screen: %s, %s (units %s, 1 = candelas), reaching %g m", ClassName(light), intensity, units, LIGHT_M))
    return light
end

-- An entry's light, looked up by its name (a hash lookup): a light deleted
-- with its world is never touched, only not found (touching a deleted object
-- crashes UE4SS)
LightOf = function(entry)
    if not (entry and entry.lightPath) then return nil end
    local light = nil
    pcall(function() light = StaticFindObject(entry.lightPath) end)
    if not Valid(light) then return nil end
    local same = false
    pcall(function() same = light:GetAddress() == entry.lightAddr end)
    return same and light or nil
end

-- The flicker: one loop while a TV is on, 4 times a second. level is how
-- bright the picture is now (0-1), heading for target; at a scene cut the
-- target (and the colour) changes, quickly, like a cut on a real TV
local flicker = { running = false, level = 0.7, target = 0.7, cutAt = 0,
                  color = { R = 0.75, G = 0.85, B = 1.0 }, aim = { R = 0.75, G = 0.85, B = 1.0 } }
local function FlickerTick()
    local light = tv and LightOf(tv)
    if not light then return end
    local now = os.clock()
    if now >= flicker.cutAt then
        flicker.cutAt = now + 1.5 + math.random() * 5
        flicker.target = 0.35 + math.random() * 0.65
        local warm = math.random() * 0.3                -- 0: cool blue-white, 0.3: warmer
        flicker.aim = { R = 0.72 + warm, G = 0.82 + warm * 0.3, B = 1.0 - warm }
    end
    flicker.level = flicker.level + (flicker.target - flicker.level) * 0.6
    local wobble = 1 + (math.random() - 0.5) * 0.1     -- the picture moving within a scene
    pcall(function() light:SetIntensity(LIGHT_CD * flicker.level * wobble) end)
    -- the colour only at a cut (each change costs the renderer a little)
    if flicker.color ~= flicker.aim then
        flicker.color = flicker.aim
        pcall(function() light:SetLightColor({ R = flicker.color.R, G = flicker.color.G, B = flicker.color.B, A = 1 }, true) end)
    end
end

local function StartFlicker()
    if not FLICKER or flicker.running then return end
    flicker.running = true
    LoopAsync(250, function()
        if not (tv and tv.lightPath) then flicker.running = false return true end
        ExecuteInGameThread(function() pcall(FlickerTick) end)
        return false
    end)
end

-- .tv light <candelas>: the screen's light brighter or dimmer, now (put the
-- number you like in config.lua as lightBrightness)
local function SetLight(value)
    local cd = tonumber(value)
    if not cd or cd < 0 then log(".tv light 300 = brighter, .tv light 50 = dimmer, .tv light 0 = off (now " .. LIGHT_CD .. ")") return end
    LIGHT_CD = cd
    local n = 0
    local function apply(entry)
        local light = LightOf(entry)
        if light then
            pcall(function() light:SetIntensity(cd) end)
            pcall(function() light:SetVisibility(cd > 0, false) end)   -- 0: not drawn at all
            n = n + 1
        end
    end
    apply(tv)
    for _, entry in pairs(kept) do apply(entry) end
    log(string.format("Screen light %g cd (%d TV%s) - lightBrightness = %g in config.lua keeps it", cd, n, n == 1 and "" or "s", cd))
end

-- Puts the panel where placed says (also after .tv turn / mirror / size)
PlacePanel = function(panel, placed)
    local rot = { Pitch = placed.rot.Pitch, Yaw = placed.rot.Yaw, Roll = placed.turn }
    pcall(function() panel:K2_SetWorldLocationAndRotation(placed.where, rot, false, {}, false) end)
    -- the cube is 100 cm: thin along X (towards you), the screen's size across
    local w, h = placed.width / 100, placed.height / 100
    if placed.turn % 180 ~= 0 then w, h = h, w end
    pcall(function() panel:SetWorldScale3D({ X = 0.004, Y = placed.mirror and -w or w, Z = h }) end)
    -- its light, 3 cm in front of it, shining out
    local light = LightOf(placed)
    if light then
        local fx, fy = Turn(3, 0, placed.rot.Yaw)
        local at = { X = placed.where.X + fx, Y = placed.where.Y + fy, Z = placed.where.Z }
        pcall(function() light:K2_SetWorldLocationAndRotation(at, { Pitch = 0, Yaw = placed.rot.Yaw, Roll = 0 }, false, {}, false) end)
        pcall(function() light:SetSourceWidth(w * 100) end)
        pcall(function() light:SetSourceHeight(h * 100) end)
    end
end

------------------------------------------------------------
-- .tv on: the picture on the screen of the TV you're looking at
------------------------------------------------------------
-- The screen: the material slot whose name or texture slots look like a
-- screen, else the TV's first slot. The video goes into a texture slot of a
-- copy of that material (emissive first, so it glows like a screen).
local SCREEN_WORDS = { "screen", "display", "monitor", "glass", "tv" }
local PARAM_ORDER = { "emiss", "screen", "base", "diffuse", "albedo", "color", "tex" }

local function PickParam(params)
    for _, word in ipairs(PARAM_ORDER) do
        for _, p in ipairs(params) do
            if p:lower():find(word, 1, true) then return p end
        end
    end
    return params[1]
end

-- aimed: the part you were looking at (from the trace), preferred
local function PickScreen(actor, aimed)
    local best = nil
    for _, m in ipairs(Meshes(actor, aimed)) do
        local isAimed = aimed ~= nil and NameOf(m) == NameOf(aimed)
        for _, s in ipairs(Materials(m)) do
            local params = TextureParams(s.mat)
            local name = NameOf(s.mat):lower()
            local score = (#params > 0 and 1 or 0) + (isAimed and 1 or 0)
            for _, w in ipairs(SCREEN_WORDS) do
                if name:find(w, 1, true) then score = score + 2 break end
            end
            if not best or score > best.score then
                best = { mesh = m, slot = s.slot, mat = s.mat, params = params, score = score }
            end
        end
    end
    return best
end

-- Where a TV is, rounded to whole cm: how every player's game finds the same
-- TV (an object's address is different on each PC)
local function TvPos(actor)
    local pos = nil
    pcall(function()
        local l = actor:K2_GetActorLocation()
        pos = { X = math.floor(l.X + 0.5), Y = math.floor(l.Y + 0.5), Z = math.floor(l.Z + 0.5) }
    end)
    return pos
end

local function SamePos(a, b)
    return a ~= nil and b ~= nil and math.abs(a.X - b.X) + math.abs(a.Y - b.Y) + math.abs(a.Z - b.Z) < 60
end

-- Where a video starts: the host's point (startClock: os.clock() when the
-- host's was at 0:00), or like a real TV a random point in its first 85%
local function StartPoint(id, startClock, random)
    if startClock then return math.max(0, os.clock() - startClock) end
    if random and RANDOM_START then
        local length = LengthOfId(id)
        if length and length >= 30 then return math.random() * length * 0.85 end
    end
    return 0
end

-- Which of config.lua's videos plays next: a random one (shuffle), preferring
-- downloaded ones and not the one on now; else the next in the list
local function PickIndex(current)
    if #videos == 0 then return nil end
    if not SHUFFLE then return (current or 0) % #videos + 1 end
    local ready, any = {}, {}
    for i, v in ipairs(videos) do
        if i ~= current or #videos == 1 then
            table.insert(any, i)
            if Downloaded(v.id) then table.insert(ready, i) end
        end
    end
    local from = #ready > 0 and ready or any
    return from[math.random(#from)]
end

-- Turns a TV on: actor is the TV, aimed the part you looked at (or nil).
-- play: index = which of config.lua's videos, or id = a video's ID (the
-- host's), or neither: a random one from a random point (shuffle,
-- randomStart); face = the screen's side (nil: the one facing you);
-- startClock = jump to where the host's video is. Returns true, or false, why
local function OnActor(actor, aimed, play)
    play = play or {}
    if tv then Stop() end
    local random = play.index == nil and play.id == nil
    local index = play.index or (random and PickIndex(nil) or nil)
    local id = play.id or (videos[index] and videos[index].id)
    if not id then log("TV on: no video " .. tostring(index) .. " in config.lua") return false, "no video " .. tostring(index) end
    log("TV on: " .. NameOf(actor) .. " (" .. ClassName(actor) .. ")")
    local screen = PickScreen(actor, aimed)
    if not screen then log("  it has no mesh to show a picture on") return false, "the TV has no mesh" end
    local param = PickParam(screen.params)
    log(string.format("  TV mesh: %s, material %s, texture slot: %s", NameOf(screen.mesh), NameOf(screen.mat),
        param or "none"))
    if not param then log("  its material has no texture slot to show the video in") return false, "no texture slot" end
    local label = index and ("video " .. index) or "the host's video"
    local function Open()
        tv.index, tv.id, tv.pos = index, id, TvPos(actor)
        local at, why = OpenAt(tv, id, StartPoint(id, play.startClock, random), label)
        if not at then
            log("  " .. why)
            Stop()
            return false, why
        end
        tv.startClock = os.clock() - at
        StartFlicker()
        return true
    end
    -- turned on before: the same player, sound and screen again
    local addr = AddressOf(actor)
    local old = addr and kept[addr]
    if old then
        kept[addr] = nil
        tv = old
        if Valid(tv.panel) then
            local p = tv.placed
            if play.face ~= nil and p and play.face ~= p.face then   -- co-op: another side this time
                local where, rot, width, height, face = FrontOf(screen.mesh, play.face)
                if where then p.where, p.rot, p.width, p.height, p.face = where, rot, width, height, face end
            end
            pcall(function() tv.panel:SetVisibility(true, false) end)
            local light = LightOf(tv)
            if light then pcall(function() light:SetVisibility(true, false) end) end
            PlacePanel(tv.panel, tv.placed)
        end
        log("  (the same player, sound and screen as before)")
        return Open()
    end
    local media, player, texture, isPlate = MakePlayer(actor)
    if not media then log("  no player: " .. tostring(player)) return false, "no video player" end
    tv = { actor = actor, addr = AddressOf(actor), name = NameOf(actor), media = media, mediaAddr = AddressOf(media), player = player,
           texture = texture, plate = isPlate }
    local panel, placed, dmi = MakePanel(actor, screen.mesh, screen.mat, param, texture, play.face)
    if panel then
        tv.panel, tv.placed, tv.dmi = panel, placed, dmi
        tv.light = MakeLight(actor)
        if tv.light then
            pcall(function()
                tv.lightPath = tv.light:GetFullName():match("^%S+%s+(.+)$")
                tv.lightAddr = tv.light:GetAddress()
            end)
            placed.lightPath, placed.lightAddr = tv.lightPath, tv.lightAddr
        end
        tv.light = nil   -- (only its name is kept)
        PlacePanel(panel, placed)
        log(string.format("  screen panel on the front, %.0f x %.0f cm (.tv turn / .tv mirror / .tv size if it's off)",
            placed.width, placed.height))
    else
        log("  no screen panel: " .. tostring(placed))
    end
    tv.sound = AttachSound(actor, player, true)
    local ok, why = Open()
    log("Done - send these lines if the TV stays dark or silent (.tv off stops it)")
    return ok, why
end

-- The side of the TV facing you (0-3, see FrontOf), for the host to use
local function FaceToward(actor, aimed)
    local screen = PickScreen(actor, aimed)
    if not screen then return 0 end
    local _, _, _, _, face = FrontOf(screen.mesh)
    return face or 0
end

-- .tv turn / .tv mirror / .tv size <factor>: fix the picture if it's sideways,
-- mirrored, or the wrong size for the TV
local function Adjust(what, value)
    if not (tv and tv.panel and tv.placed) then log("No TV screen on - .tv on first") return end
    local p = tv.placed
    if what == "turn" then
        p.turn = (p.turn + 90) % 360
        log("Picture turned to " .. p.turn .. " degrees")
    elseif what == "mirror" then
        p.mirror = not p.mirror
        log("Picture " .. (p.mirror and "mirrored" or "not mirrored"))
    elseif what == "size" then
        local f = tonumber(value)
        if not f or f < 0.2 or f > 3 then log(".tv size 1.1 = 10% bigger, .tv size 0.9 = 10% smaller") return end
        p.width, p.height = p.width * f, p.height * f
        log(string.format("Screen now %.0f x %.0f cm", p.width, p.height))
    end
    PlacePanel(tv.panel, p)
end

-- Another video on the TV that's on (a random one, or the next in the list:
-- shuffle). Changing the channel starts it at a random point (randomStart);
-- fromStart: when the one before ended. Returns true when it opened
local function Next(fromStart)
    if not tv then log("Nothing playing - .tv on") return false end
    if #videos == 0 then log("No videos in config.lua") return false end
    tv.index = PickIndex(tv.index)
    tv.id = videos[tv.index].id
    local at, why = OpenAt(tv, tv.id, StartPoint(tv.id, nil, not fromStart), "video " .. tv.index)
    if not at then log(why) return false end
    tv.startClock = os.clock() - at
    return true
end

------------------------------------------------------------
-- Co-op
------------------------------------------------------------
-- The host's game decides what plays, like the other mods in this folder
-- (Radiation Shield, Mod Menu), through two messages Unreal always has:
-- Player -> host: PlayerController:ServerNotifyLoadedWorld(FName "YTTV_ON_x_y_z_face_n")
--   (also YTTV_OFF, YTTV_NEXT, YTTV_SYNC). The game ignores the name; the
--   host's mod reads it.
-- Host -> player: PlayerController:ClientMessage("... #TV:play:<id>:x:y:z:face:<seconds in>")
--   (or #TV:off, #TV:none, #TV:err). A line in the player's console; their
--   mod reads the tag.
-- A TV is named by where it stands (whole cm), the same on every PC. Each
-- player's game plays its own copy of the video and jumps to the host's
-- point; a missing video is downloaded first. Nothing goes through the game.
local SERVER_TAG = "YTTV"
local remote = nil    -- joined: what the host says plays { id, pos, face, startClock }
local fetching = {}   -- [video ID] = true while a host's video downloads here
local answered = 0    -- host answers so far (the no-answer check counts them)

-- Joined someone else's world: our own controller isn't the authority
local function Joined()
    local joined = false
    pcall(function()
        local pc = LocalController()
        if Valid(pc) then joined = pc:HasAuthority() == false end
    end)
    return joined
end

local function ParamString(param)
    local value = param
    pcall(function() value = param:get() end)
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    return ok and type(s) == "string" and s or ""
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
    pcall(function() pc:ClientMessage("[YouTubeTV] " .. text .. " #TV:" .. tag, FName("None"), 0.0) end)
end

-- Hosting: every player who joined
local function TellEveryone(tag, text)
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(ctrl) and not ctrl:IsLocalController() then Tell(ctrl, tag, text) end
        end
    end)
end

local function SendToHost(command)
    local pc = LocalController()
    if not pc then return false end
    return pcall(function() pc:ServerNotifyLoadedWorld(FName(SERVER_TAG .. "_" .. command)) end)
end

-- The TV standing at pos (whole cm), found among the game's TVs only
local function FindTvAt(pos)
    local best, bestD = nil, nil
    pcall(function()
        for _, a in ipairs(FindAllOf("BP_TV_C") or {}) do
            if Valid(a) then
                local p = TvPos(a)
                if SamePos(p, pos) then
                    local d = math.abs(p.X - pos.X) + math.abs(p.Y - pos.Y) + math.abs(p.Z - pos.Z)
                    if not bestD or d < bestD then best, bestD = a, d end
                end
            end
        end
    end)
    return best
end

local function MainMesh(actor)
    local main = nil
    pcall(function() main = actor.StaticMesh end)   -- the TV body (not its lace)
    return Valid(main) and main or nil
end

-- Hosting: what plays now, as the message players get
local function PlayMessage()
    if not (tv and tv.id and tv.pos) then return "none", "Nothing is playing on the host's TV" end
    local face = tv.placed and tv.placed.face or 0
    return string.format("play:%s:%d:%d:%d:%d:%.1f", tv.id, tv.pos.X, tv.pos.Y, tv.pos.Z, face,
        os.clock() - (tv.startClock or os.clock())), "The host's TV plays " .. tv.id
end

-- Hosting: tell every player who joined what plays (or that it's off)
Broadcast = function()
    if Joined() then return end
    local tag, text = PlayMessage()
    if tag == "none" then tag, text = "off", "The host's TV is off" end
    TellEveryone(tag, text)
end

-- Joined: ask the host; fallback runs if no answer comes in 3 s (the host
-- doesn't have this mod)
local function AskHost(command, fallback)
    local before = answered
    local sent = SendToHost(command)
    LoopAsync(3000, function()
        ExecuteInGameThread(function()
            if answered ~= before then return end
            log("No answer from the host" .. (sent and "" or " (couldn't send)") .. " - the host needs YouTube TV "
                .. VERSION .. " for TVs in their world" .. (fallback and "; playing it just for you" or ""))
            if fallback then pcall(fallback) end
        end)
        return true
    end)
end

local StartRemote

-- Joined: download the host's video, then start it if it still plays
local function FetchThen(id)
    if fetching[id] then return end
    fetching[id] = true
    local doneFile = "./" .. VIDEO_DIR .. id .. ".done"
    os.remove(doneFile)
    local ok, why = RunScript("download_" .. id .. ".cmd", {
        string.format("echo Downloading the host's video %s ...", id),
        DownloadLine(id),
        string.format('echo done> "videos\\%s.done"', id),
    })
    if not ok then
        fetching[id] = nil
        log("Couldn't download the host's video: " .. why)
        return
    end
    log("Downloading the host's video " .. id .. " in a minimized window - it starts here when it's done")
    local waited = 0
    LoopAsync(2000, function()   -- only looks for a file; nothing in the game until it's there
        waited = waited + 2
        local f = io.open(doneFile, "r")
        if not f then
            if waited < 1800 then return false end
            fetching[id] = nil
            return true
        end
        f:close()
        ExecuteInGameThread(function()
            fetching[id] = nil
            os.remove(doneFile)
            if not Downloaded(id) then
                log("Couldn't download the host's video " .. id .. ": " .. (FailReason(id) or ("see videos\\" .. id .. ".log")))
            elseif remote and remote.id == id then
                StartRemote()
            end
        end)
        return true
    end)
end

-- Joined: play what the host says plays, from the host's point
StartRemote = function()
    local r = remote
    if not r then return end
    if tv and tv.id == r.id and SamePos(tv.pos, r.pos) then
        -- already on: only a restart (the host's next, same video) jumps
        if math.abs((tv.startClock or 0) - r.startClock) > 3 then   -- moved: open it again at the host's point
            local at = OpenAt(tv, r.id, os.clock() - r.startClock, "the host's video")
            if at then tv.startClock = os.clock() - at end
        end
        return
    end
    if not Downloaded(r.id) then FetchThen(r.id) return end
    local actor = FindTvAt(r.pos)
    if not actor then
        log("The host's TV isn't loaded in your game yet - it starts when you look at it, or .tv sync")
        return
    end
    OnActor(actor, MainMesh(actor), { id = r.id, face = r.face, startClock = r.startClock })
end

-- A joined player's request, on the host
local function OnHostMessage(selfParam, msgParam)
    if Joined() then return end   -- only the host answers
    local msg = ParamString(msgParam)
    local cmd, rest = msg:match("^" .. SERVER_TAG .. "_(%u+)_?(.*)$")
    if not cmd then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not Valid(pc) then return end
    local isLocal = true
    pcall(function() isLocal = pc:IsLocalController() end)
    if isLocal then return end
    local who = PlayerName(pc)
    if cmd == "ON" then
        local x, y, z, face, n = rest:match("^(%-?%d+)_(%-?%d+)_(%-?%d+)_(%d)_?(%d*)$")
        if not x then return end
        local actor = FindTvAt({ X = tonumber(x), Y = tonumber(y), Z = tonumber(z) })
        if not actor then Tell(pc, "err", "The host's game couldn't find that TV") return end
        local index = tonumber(n)   -- 0: a random one
        if index and (index < 1 or index > #videos) then index = nil end
        log(who .. " turned a TV on")
        local ok, why = OnActor(actor, MainMesh(actor), { index = index, face = tonumber(face) })
        if ok then Broadcast() else Tell(pc, "err", "The host's TV couldn't play: " .. tostring(why)) end
    elseif cmd == "OFF" then
        if tv then log(who .. " turned the TV off") Stop() end
        Broadcast()
    elseif cmd == "NEXT" then
        if tv and Next() then Broadcast() else Tell(pc, "err", "Nothing is playing on the host's TV") end
    elseif cmd == "SYNC" then
        Tell(pc, PlayMessage())
    end
end

-- The host's answers, on a player who joined
local function OnClientMessage(selfParam, textParam)
    local text = ParamString(textParam)
    local tag, rest = text:match("#TV:(%a+):?(%S*)%s*$")
    if not tag or not Joined() then return end   -- (the host's own copies of its messages)
    answered = answered + 1
    if tag == "play" then
        local id, x, y, z, face, secs = rest:match("^([%w_%-]+):(%-?%d+):(%-?%d+):(%-?%d+):(%d):([%d%.]+)$")
        if not id or #id ~= 11 then return end
        remote = { id = id, pos = { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, face = tonumber(face),
                   startClock = os.clock() - (tonumber(secs) or 0) }
        log("The host's TV plays " .. id .. " (" .. Clock(tonumber(secs) or 0) .. " in)")
        ExecuteInGameThread(function() pcall(StartRemote) end)
    elseif tag == "off" or tag == "none" then
        remote = nil
        ExecuteInGameThread(function() if tv then Stop() end end)
    elseif tag == "err" then
        log((text:gsub("^%[YouTubeTV%]%s*", ""):gsub("%s*#TV:.*$", "")))
    end
end

for path, fn in pairs({
    ["/Script/Engine.PlayerController:ServerNotifyLoadedWorld"] = OnHostMessage,
    ["/Script/Engine.PlayerController:ClientMessage"] = OnClientMessage,
}) do
    if not pcall(RegisterHook, path, fn) then log("Co-op messages unavailable (" .. path .. ")") end
end

-- Turning a TV on, off, to the next video: by yourself or hosting, here and
-- for every player who joined; joined, the host does it for everyone
local function TurnOn(actor, aimed, index)
    if not Joined() then
        if OnActor(actor, aimed, { index = index }) then Broadcast() end
        return
    end
    local pos = TvPos(actor)
    if not pos then log("TV on: couldn't read where the TV is") return end
    local face = FaceToward(actor, aimed)
    log("Asking the host to turn the TV on (the host's videos play)")
    AskHost(string.format("ON_%d_%d_%d_%d_%d", pos.X, pos.Y, pos.Z, face, index or 0), function()
        local a = FindTvAt(pos)
        if a then OnActor(a, MainMesh(a), { index = index, face = face }) end
    end)
end

local function TurnOff()
    if not Joined() then
        local was = tv ~= nil
        Stop()
        if was then Broadcast() end
        return
    end
    remote = nil
    if tv then Stop() end   -- yours now; the host turns it off for everyone
    AskHost("OFF")
end

-- A TV's video ended: the next one, from the start. Hosting, every player
-- follows; joined, the host's TV decides (its end comes the same moment)
local function OnPlateEnd(selfParam)
    local addr = nil
    pcall(function() addr = selfParam:get():GetAddress() end)
    if not (addr and tv and tv.mediaAddr == addr) then return end
    ExecuteInGameThread(function()
        if not (tv and tv.mediaAddr == addr) then return end
        if os.clock() - (tv.openedAt or 0) < 3 then return end   -- (not the video just opened)
        if Joined() then return end
        log("Video ended - the next one, from the start")
        if Next(true) then Broadcast() end
    end)
end
if not pcall(RegisterHook, "/Script/MediaPlate.MediaPlateComponent:OnMediaEnd", OnPlateEnd) then
    log("Couldn't watch for videos ending: a TV stops at the end of its video")
end

local function NextVideo()
    if not Joined() then
        if Next() then Broadcast() end
        return
    end
    AskHost("NEXT")
end

local function Sync()
    if not Joined() then log("You're the host: players who join get what plays by themselves") return end
    log("Asking the host what plays")
    AskHost("SYNC")
end

local function On(index)
    local target, err = LookedAt(false)
    if not target then log("TV on: " .. err .. " - look at the TV") return end
    TurnOn(target.actor, target.comp, index)
end

-- .tv seek <seconds>: the video that plays, from that point (tests what
-- random starts and co-op need). Hosting: every player follows
local function Seek(value)
    local seconds = tonumber(value)
    if not seconds or seconds < 0 then log(".tv seek 90 = 1:30 into the video") return end
    if not (tv and tv.id) then log("Nothing playing - .tv on") return end
    if Joined() then log("In someone else's world the host decides where the video is") return end
    local at, why = OpenAt(tv, tv.id, seconds, tv.index and ("video " .. tv.index) or "the video")
    if not at then log(why) return end
    tv.startClock = os.clock() - at
    Broadcast()
end

------------------------------------------------------------
-- E menu: "TURN ON TV" / "TURN OFF TV" on the game's own TV
------------------------------------------------------------
-- The game's E menu (BP_InteractionContextMenu) is built by its
-- InitializeContextMenu: one entry widget per action the object offers (a TV
-- without power: only PICK UP). After it runs on a TV, one more entry is added
-- the game's way (WidgetBlueprintLibrary.Create + InitializeEntry). Scrolling
-- picks entries by the widgets in the menu's box, so it can be selected.
-- Pressing E sends the selected action's type to the TV, whose Interact only
-- reacts to PICK UP (type 2); ours carries type 0, which it ignores. The mod
-- watches E itself and turns the video on or off.
-- (Hooking the TV's own "SGK PossibleActions" crashed UE4SS in 0.3.0: it
-- returns a list. The menu's own functions are safe: Mi-8 Cargo Hold hooks them.)
local WIDGETS = "/Game/SurvivalGameKitV2/Blueprints/Widgets/"
local MENU_CLASS = WIDGETS .. "BP_InteractionContextMenu.BP_InteractionContextMenu_C"
local ENTRY_CLASS = WIDGETS .. "BP_InteractContextMenuEntry.BP_InteractContextMenuEntry_C"
local ACTION_ENUM = "/Game/SurvivalGameKitV2/Blueprints/Other/Enum/E_WorldActions.E_WorldActions"
local E_ACTION_NAME = "ActionName_15_19BA14C540FCFDAA9B8F29A403079514"
local E_ACTION_TYPE = "WorldActions_14_09EA4A134331DF405C8B59A59F4D242C"
local E_MENU = cfg.eMenu ~= false   -- eMenu = false in config.lua: no E menu entry
local E_TYPE = math.floor(tonumber(cfg.eMenuActionType) or 0)
if E_TYPE == 2 then E_TYPE = 0 end   -- never PICK UP
local LABEL_ON, LABEL_OFF = "TURN ON TV", "TURN OFF TV"
local eMenu = { hooked = false, logged = {}, menuAddr = nil }

local function LogOnce(key, msg)
    if eMenu.logged[key] then return end
    eMenu.logged[key] = true
    log(msg)
end

local function IsTv(actor)
    return Valid(actor) and ClassName(actor) == "BP_TV_C"
end

local function PlayingOn(actor)
    local addr = AddressOf(actor)
    return tv ~= nil and tv.addr ~= nil and tv.addr == addr
end

-- The readable names of the game's action types, once (so the log shows what 0 is)
local function LogActionTypes()
    local enum, lib = Find(ACTION_ENUM), Find("/Script/Engine.Default__KismetNodeHelperLibrary")
    if not (enum and lib) then LogOnce("types", "E menu: couldn't read the action types' names") return end
    local names = {}
    for i = 0, 10 do
        local n = "?"
        pcall(function() n = tostring(lib:GetEnumeratorUserFriendlyName(enum, i):ToString()) end)
        table.insert(names, i .. "=" .. n)
    end
    LogOnce("types", "E menu: action types " .. table.concat(names, ", ") .. " - TURN ON TV uses " .. E_TYPE)
end

-- Is one of the menu's entries already ours?
-- An entry's label, as shown. Ours are recognised by it: their Action has no
-- name (writing one broke the game's memory, see AddEntry)
local function EntryLabel(e)
    local name = nil
    pcall(function() name = e.TextBlock:GetText():ToString() end)
    return name
end

local function HasOurEntry(box)
    local count = 0
    pcall(function() count = box:GetChildrenCount() end)
    for i = 0, count - 1 do
        local e = nil
        pcall(function() e = box:GetChildAt(i) end)
        local name = EntryLabel(e)
        if name == LABEL_ON or name == LABEL_OFF then return true, i, e end
    end
    return false, count
end

-- The first TV menu logs each step before doing it: if the game crashes,
-- the last line says where (0.4.0 crashed with no line at all)
local traceSteps = true
local function Step(what) if traceSteps then log("E menu step: " .. what) end end

local function AddEntry(menu, actor)
    Step("reading the menu's entry box")
    local box = nil
    pcall(function() box = menu.ContextVerticalBox end)
    if not Valid(box) then return end
    local label = PlayingOn(actor) and LABEL_OFF or LABEL_ON
    Step("looking for our entry")
    local has, index, existing = HasOurEntry(box)
    if has then
        return
    end
    local lib, cls, pc = Find("/Script/UMG.Default__WidgetBlueprintLibrary"), Find(ENTRY_CLASS), LocalController()
    if not (lib and cls and pc) then LogOnce("noparts", "E menu: couldn't find what's needed to add the entry") return end
    local entry = nil
    Step("creating the entry widget")
    local ok, err = pcall(function() entry = lib:Create(menu, cls, pc) end)
    if not ok or not Valid(entry) then LogOnce("create", "E menu: couldn't create the entry: " .. tostring(err)) return end
    -- Filled in directly, not with InitializeEntry: that starts the entry's
    -- UpdateText timer, which asks the TV for its actions again, finds none at
    -- our index and removes the entry about a second later (0.4.1).
    -- No name is written into its Action: this UE4SS writes a text 8 bytes too
    -- long, over the PlayerInventory pointer right after it, and the engine's
    -- memory clean-up crashed on that pointer about a minute later (0.4.3 to
    -- 0.5.5). A new entry's action type is already 0; only another is written.
    Step("filling it in")
    if E_TYPE ~= 0 then pcall(function() entry.Action[E_ACTION_TYPE] = E_TYPE end) end
    pcall(function() entry.Actor = actor end)
    pcall(function() entry.Index = index end)
    pcall(function() entry.PlayerInventory = menu.PlayerInventory end)
    ok, err = pcall(function() entry.TextBlock:SetText(FText(label)) end)
    pcall(function() entry.TextBlock_86:SetText(FText(label)) end)   -- the other label (shown unselected)
    if not ok then LogOnce("init", "E menu: couldn't set the entry's text: " .. tostring(err)) return end
    Step("adding it to the menu")
    ok, err = pcall(function() box:AddChildToVerticalBox(entry) end)
    if not ok then LogOnce("add", "E menu: couldn't add the entry: " .. tostring(err)) return end
    pcall(function() entry:EntrySelected(false) end)
    LogOnce("added", "E menu: added '" .. label .. "' to the TV's menu (entry " .. index .. ")")
    traceSteps = false
end

local function OnMenuBuilt(self, lookAtActor)
    LogOnce("hookran", "E menu step: the menu hook ran (first time, any object)")
    local menu, actor = nil, nil
    pcall(function() menu = self:get() end)
    if not Valid(menu) then return end
    pcall(function() actor = lookAtActor:get() end)
    if traceSteps and Valid(actor) then LogOnce("first:" .. NameOf(actor), "E menu step: menu for " .. NameOf(actor)) end
    eMenu.menuAddr = AddressOf(menu)   -- only its address: the game may delete the menu later
    if not IsTv(actor) then return end
    -- joined: the host's TV plays, but it wasn't loaded here when the host said so
    if remote and not (tv and tv.id == remote.id) and not fetching[remote.id] and SamePos(TvPos(actor), remote.pos) then
        ExecuteInGameThread(function() pcall(StartRemote) end)
    end
    Step("the E menu is for a TV")
    local ok, err = pcall(AddEntry, menu, actor)
    if not ok then LogOnce("adderr", "E menu: " .. tostring(err)) end
end

-- E: if our entry is the selected one, the TV goes on / off
local lastToggle = -100
-- The E menu last built, found fresh among the game's menus by its address.
-- The menu object itself isn't kept: when the game deletes a menu, touching
-- it crashes UE4SS (0.5.7: an E press anywhere, a while after the menu was
-- deleted, read the freed menu)
local function CurrentMenu()
    if not eMenu.menuAddr then return nil end
    local found = nil
    pcall(function()
        for _, m in ipairs(FindAllOf("BP_InteractionContextMenu_C") or {}) do
            if m:GetAddress() == eMenu.menuAddr then found = m return end
        end
    end)
    return Valid(found) and found or nil
end

local function OnEKey()
    -- everything read fresh: the menu, the entry selected now and what you
    -- look at now (anything kept from earlier may have been deleted since)
    if not eMenu.menuAddr then LogOnce("e-nomenu", "E menu: E pressed, but no menu seen yet") return end
    local menu = CurrentMenu()
    if not menu then eMenu.menuAddr = nil return end   -- deleted since
    local selected, box = nil, nil
    pcall(function() selected = menu.SelectedEntryIndex end)
    pcall(function() box = menu.ContextVerticalBox end)
    if type(selected) ~= "number" or not Valid(box) then
        LogOnce("e-nobox", "E menu: E pressed, but couldn't read the menu's selection (" .. tostring(selected) .. ")")
        return
    end
    local entry = nil
    pcall(function() entry = box:GetChildAt(selected) end)
    local name = EntryLabel(entry)
    if name ~= LABEL_ON and name ~= LABEL_OFF then return end   -- another entry: not ours
    -- the TV: the one our entry was made for (the entry is in the menu now, so
    -- it exists), else what the menu says you look at
    local actor = nil
    for _, field in ipairs({ "Actor", "LastLookAtActor", "LastActor" }) do
        local obj = nil
        pcall(function() obj = (field == "Actor" and entry or menu)[field] end)
        if IsTv(obj) then actor = obj break end
    end
    if not actor then LogOnce("e-notv", "E menu: E on " .. name .. ", but couldn't tell which TV") return end
    local now = os.clock()
    if now - lastToggle < 1.0 then return end   -- one toggle a second at most
    lastToggle = now
    if PlayingOn(actor) then
        TurnOff()
    else
        TurnOn(actor, MainMesh(actor), nil)
    end
    -- the entry's label follows
    local label = PlayingOn(actor) and LABEL_OFF or LABEL_ON
    pcall(function() entry.TextBlock:SetText(FText(label)) end)
    pcall(function() entry.TextBlock_86:SetText(FText(label)) end)
end

-- A build part is being removed (a TV picked up, broken, or the level
-- unloading): forget everything kept for it, before the game deletes it
local function Forget(addr)
    if not addr then return end
    if tv and tv.addr == addr then
        if tv.plate then pcall(function() tv.media:Close() end) end
        pcall(function() tv.player:Close() end)
        tv = nil
        log("The TV that was on was picked up or removed - off")
        Broadcast()   -- hosting: off for everyone
    end
    kept[addr] = nil
end

-- Is the TV that's on still in the world? Found among the game's TVs by its
-- address and name, without touching the old object itself
local function StillThere(entry)
    if not (entry and entry.addr) then return false end
    local found = false
    pcall(function()
        for _, a in ipairs(FindAllOf("BP_TV_C") or {}) do
            if Valid(a) and a:GetAddress() == entry.addr and NameOf(a) == entry.name then found = true return end
        end
    end)
    return found
end

-- A respawn or a new world (ClientRestart). A respawn keeps the world: the TV
-- plays on. A new world (leaving or joining a game, loading) has already
-- deleted the old TVs with their players: nothing from before is touched,
-- only let go of. (0.5.6 closed the old players: disconnecting crashed UE4SS.)
-- Returns true when a TV that was on is gone
local function ForgetAll()
    eMenu.menuAddr = nil
    if tv and StillThere(tv) then return false end
    local was = tv ~= nil
    tv, kept = nil, {}
    return was
end

local function HookEMenu()
    if not E_MENU or eMenu.hooked then return end
    if not Find(MENU_CLASS) then return end   -- loaded with the HUD
    eMenu.hooked = true
    local ok = pcall(GameHook, MENU_CLASS .. ":InitializeContextMenu", OnMenuBuilt)
    if Key and Key.E then
        pcall(function()
            RegisterKeyBind(Key.E, function() ExecuteInGameThread(function() pcall(OnEKey) end) end)
        end)
    end
    log("E menu: " .. (ok and "TURN ON TV will be in TVs' E menu" or "couldn't hook the E menu"))
end

------------------------------------------------------------
-- .tv learn: how the game's E menu works on a TV (for turning it on with E)
------------------------------------------------------------
-- Look at a TV and run it. It logs the functions and settings (names and
-- types only, nothing is read) of the TV's class and its parent classes and of
-- the E menu, then watches those functions: open the E menu on the TV, scroll
-- through it, press E on an entry (or close it), and the log shows what ran
-- and what the menu held.
local SKIP_WATCH = { Tick = true, ReceiveTick = true, PreConstruct = true, Construct = true, OnPaint = true,
                     UserConstructionScript = true, ExecuteUbergraph = true }
local learning = { watched = {}, calls = {} }

local function ClassPathOf(cls)
    local full = ""
    pcall(function() full = cls:GetFullName() end)
    return full:match("^%S+%s+(/.+)$") or ""
end

-- fn(name) for each function the class itself declares
local function EachFunction(cls, fn)
    pcall(function()
        cls:ForEachFunction(function(f)
            local name = ""
            pcall(function() name = f:GetFName():ToString() end)
            if name ~= "" then fn(name) end
        end)
    end)
end

local function PropertyList(cls)
    local list = {}
    pcall(function()
        cls:ForEachProperty(function(prop)
            local name, kind = "?", "?"
            pcall(function() name = prop:GetFName():ToString() end)
            pcall(function() kind = prop:GetClass():GetFName():ToString() end)
            table.insert(list, name .. ":" .. kind:gsub("Property$", ""))
        end)
    end)
    return list
end

-- What the E menu holds (entries in its vertical box)
local function MenuEntries(menu)
    local out = {}
    local box = nil
    pcall(function() box = menu.ContextVerticalBox end)
    if not Valid(box) then return "no entry box" end
    local count = 0
    pcall(function() count = box:GetChildrenCount() end)
    for i = 0, count - 1 do
        local e = nil
        pcall(function() e = box:GetChildAt(i) end)
        if Valid(e) then
            local name, kind, text = "?", "?", ""
            pcall(function() name = e.Action[E_ACTION_NAME]:ToString() end)
            pcall(function() kind = tostring(e.Action[E_ACTION_TYPE]) end)
            pcall(function() text = e.TextBlock:GetText():ToString() end)
            table.insert(out, string.format("[%d] %s (type %s) '%s'", i, name, kind, text))
        end
    end
    local sel = "?"
    pcall(function() sel = tostring(menu.SelectedEntryIndex) end)
    return table.concat(out, ", ") .. "  selected " .. sel
end

local function Watch(path, label, isMenu)
    if learning.watched[path] then return end
    learning.watched[path] = true
    local ok = pcall(GameHook, path, function(self)
        local menu = nil
        if isMenu then
            pcall(function() menu = self:get() end)
            if Valid(menu) then eMenu.menuAddr = AddressOf(menu) end   -- the E key finds it by this
        end
        local n = (learning.calls[path] or 0) + 1
        learning.calls[path] = n
        if n > 4 then return end   -- the first few calls are enough
        local extra = ""
        if Valid(menu) then extra = "  menu: " .. MenuEntries(menu) end
        log("learn: " .. label .. extra)
    end)
    if not ok then log("  couldn't watch " .. label) end
end

-- The game's action types (PICK UP is 2): the enum on the entry's Action.
-- Tries the few ways this UE4SS might expose it; logs which one worked.
local function LearnActionTypes()
    local entryClass = Find(ENTRY_CLASS)
    if not entryClass then return end
    local found = false
    pcall(function()
        entryClass:ForEachProperty(function(prop)
            local name = ""
            pcall(function() name = prop:GetFName():ToString() end)
            if name ~= "Action" then return end
            local struct = nil
            for _, getter in ipairs({ "GetStruct", "GetScriptStruct" }) do
                if not struct then pcall(function() struct = prop[getter](prop) end) end
            end
            if not struct then log("  action types: couldn't reach the Action struct") return end
            struct:ForEachProperty(function(field)
                local enum = nil
                for _, getter in ipairs({ "GetEnum", "GetEnumProperty" }) do
                    if not enum then pcall(function() enum = field[getter](field) end) end
                end
                if enum then
                    local names = {}
                    local ok = pcall(function()
                        enum:ForEachName(function(n, v) table.insert(names, tostring(n:ToString()) .. "=" .. tostring(v)) end)
                    end)
                    log("  action types (" .. NameOf(enum) .. "): " .. (ok and table.concat(names, ", ") or "couldn't list them"))
                    found = true
                end
            end)
        end)
    end)
    if not found then log("  action types: no enum found on the entry's Action") end
end

-- E pressed: what the open menu holds and which entry is selected (only logged)
local eKeyWatched = false
local function LearnEKey()
    if eKeyWatched or not (Key and Key.E) then return end
    eKeyWatched = true
    pcall(function()
        RegisterKeyBind(Key.E, function()
            ExecuteInGameThread(function()
                local menu = CurrentMenu()
                if not menu then log("learn: E pressed - no menu seen yet") return end
                local vis = "?"
                pcall(function() vis = tostring(menu:GetVisibility()) end)
                log("learn: E pressed - menu visibility " .. vis .. ", " .. MenuEntries(menu))
            end)
        end)
    end)
end

local function Learn()
    local target, err = LookedAt(false)
    if not target then log("Learn: " .. err .. " - look at the TV") return end
    log("Learn: " .. NameOf(target.actor) .. " (" .. ClassName(target.actor) .. ")")
    -- the TV's class and its parents (game classes only)
    local cls = nil
    pcall(function() cls = target.actor:GetClass() end)
    local depth = 0
    while Valid(cls) and depth < 6 do
        local path = ClassPathOf(cls)
        if not path:find("^/Game/") then break end
        log("  class " .. path)
        local fns = {}
        EachFunction(cls, function(name)
            table.insert(fns, name)
            -- not watched: some of these return lists, and hooking those crashes UE4SS (0.3.0)
        end)
        log("    functions: " .. (#fns > 0 and table.concat(fns, ", ") or "-"))
        local props = PropertyList(cls)
        log("    settings: " .. (#props > 0 and table.concat(props, ", ") or "-"))
        local super = nil
        pcall(function() super = cls:GetSuperStruct() end)
        cls = super
        depth = depth + 1
    end
    -- the E menu and its entries
    for _, path in ipairs({ MENU_CLASS, ENTRY_CLASS }) do
        local c = Find(path)
        if c then
            local fns = {}
            EachFunction(c, function(name)
                table.insert(fns, name)
                if not SKIP_WATCH[name] and not name:find("^Get") and not name:find("^Is") then
                    Watch(path .. ":" .. name, path:match("%.([%w_]+)$") .. ":" .. name, path == MENU_CLASS)
                end
            end)
            log("  " .. path:match("%.([%w_]+)$") .. " functions: " .. table.concat(fns, ", "))
            log("    settings: " .. table.concat(PropertyList(c), ", "))
            -- what the functions that build entries take (names and types)
            for _, fname in ipairs({ "PopulateMenu", "InitializeContextMenu", "InitializeEntry", "EntrySelected" }) do
                local fn = Find(path .. ":" .. fname)
                if fn then log("    " .. fname .. "(" .. table.concat(PropertyList(fn), ", ") .. ")") end
            end
        else
            log("  " .. path .. " not loaded yet - open the E menu once, then run .tv learn again")
        end
    end
    LearnActionTypes()
    LearnEKey()
    log("Now: look away and back at the TV, open its E menu and scroll it (don't press E on PICK UP).")
    log("Then open the E menu on something harmless (a cabinet's OPEN) and press E there. Then send the log")
end

------------------------------------------------------------
-- Commands
------------------------------------------------------------
RegisterConsoleCommandHandler(".tv", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    local n = tonumber(Parameters and Parameters[2])
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if a == "probe" then Probe()
            elseif a == "download" then Download()
            elseif a == "list" then List()
            elseif a == "scan" then Scan()
            elseif a == "hud" then Hud(n)
            elseif a == "on" then On(n)
            elseif a == "next" then NextVideo()
            elseif a == "seek" then Seek(Parameters and Parameters[2])
            elseif a == "sync" then Sync()
            elseif a == "status" then Status()
            elseif a == "learn" then Learn()
            elseif a == "turn" or a == "mirror" or a == "size" then Adjust(a, Parameters and Parameters[2])
            elseif a == "light" then SetLight(Parameters and Parameters[2])
            elseif a == "off" then TurnOff()
            else log(".tv probe | download | list | scan | hud [n] | on [n] | status | next | seek <s> | sync | turn | mirror | size <x> | light <cd> | off | learn") end
        end)
        if not ok then log("Error: " .. tostring(err)) end
    end)
    return true
end)

-- Build parts being removed (a TV picked up): forget what's kept for them
local BUILD_PART = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/BP_MasterBuildPart.BP_MasterBuildPart_C"
local destroyHooked = false
local function HookDestroyed()
    if destroyHooked or not Find(BUILD_PART) then return end
    destroyHooked = pcall(GameHook, BUILD_PART .. ":ReceiveDestroyed", function(self)
        local addr = nil
        pcall(function() addr = self:get():GetAddress() end)
        if addr and (kept[addr] or (tv and tv.addr == addr)) then Forget(addr) end
    end)
end
pcall(HookDestroyed)

-- The TV's class exists once a level with TVs has loaded: hook its menu then
pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self)
        local isLocal = false
        pcall(function() isLocal = self:get():IsLocalController() end)
        if not isLocal then return end   -- (hosting: a joined player's respawn)
        ExecuteInGameThread(function()
            -- a new level or a respawn: nothing from before is safe to touch
            if ForgetAll() then Broadcast() end   -- hosting: the TV went off for everyone
            pcall(HookEMenu)
            pcall(HookDestroyed)
        end)
        -- joined: ask the host what plays once the world is there
        LoopAsync(3000, function()
            ExecuteInGameThread(function()
                if Joined() then remote = nil SendToHost("SYNC") end
            end)
            return true
        end)
    end)
end)
pcall(HookEMenu)

log("Loaded v" .. VERSION .. " (experimental): " .. #videos .. " video(s) in config.lua. .tv probe to start")
