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
--   .tv on [n]       plays video n (default 1) on the TV you're looking at
--   .tv next         the next video
--   .tv turn / .tv mirror / .tv size 1.1   fix the picture on the TV's screen
--   .tv off          stops it (the HUD panel too)
--   E menu on a TV   TURN ON TV / TURN OFF TV (eMenu = false in config.lua: off)
--   .tv learn        look at a TV: how the game's E menu works on it (for turning it on with E)
--
-- Videos are downloaded with yt-dlp (+ ffmpeg) as H.264/AAC .mp4, which the
-- game's Windows video player (WMF) plays. Only the 11-character video ID is
-- taken from each link; the command is built from it, never from the link.
-- Co-op (the host's list for everyone, in sync) comes later.
------------------------------------------------------------
local VERSION = "0.4.6"
local MOD_DIR = "./ue4ss/Mods/YouTubeTV/"
local VIDEO_DIR = "ue4ss/Mods/YouTubeTV/videos/"   -- relative to the game's Win64 folder

local function log(msg)
    print("[YouTubeTV] " .. tostring(msg) .. "\n")
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
local VOLUME = math.max(0, math.min(1, tonumber(cfg.volume) or 0.8))
local MAX_HEIGHT = math.floor(tonumber(cfg.maxHeight) or 720)
local SCAN_METERS = tonumber(cfg.scanMeters) or 8
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

-- Writes download.cmd (one minimized window downloads every missing video in
-- turn, each with a log in videos\<id>.log) and starts it; the game keeps running
local function Download()
    if #videos == 0 then log("No videos in config.lua (videos = { \"https://www.youtube.com/watch?v=...\" })") return end
    local missing = {}
    for _, v in ipairs(videos) do
        if not Downloaded(v.id) then table.insert(missing, v.id) end
    end
    if #missing == 0 then log("All " .. #videos .. " videos are already downloaded") return end
    local format = string.format(
        "bv*[vcodec^=avc1][height<=%d]+ba[ext=m4a]/b[ext=mp4][height<=%d]/b[ext=mp4]/bv*[height<=%d]+ba/b",
        MAX_HEIGHT, MAX_HEIGHT, MAX_HEIGHT)
    -- quoted: a profile folder can have spaces ("xzqhbajk.Default (release)")
    local cookies = COOKIES ~= "" and (' --cookies-from-browser "' .. COOKIES .. '"') or ""
    local lines = { "@echo off", "cd /d \"%~dp0\"", "if not exist videos mkdir videos" }
    for _, id in ipairs(missing) do   -- ids are 11 checked characters: letters, digits, - and _
        table.insert(lines, string.format("echo Downloading %s ...", id))
        -- -P: the folder as a full path, so a download folder set in your own
        -- yt-dlp config (e.g. Downloads) doesn't move the videos there
        table.insert(lines, string.format(
            '%s -f "%s" --merge-output-format mp4 --recode-video mp4 --no-playlist%s -P "%%~dp0videos" -o "%s.%%%%(ext)s" "https://www.youtube.com/watch?v=%s" > "videos\\%s.log" 2>&1',
            YtDlp(), format, cookies, id, id, id))
    end
    local script = io.open(MOD_DIR .. "download.cmd", "wb")
    if not script then log("Couldn't write download.cmd in the mod's folder") return end
    script:write(table.concat(lines, "\r\n") .. "\r\n")
    script:close()
    local ok, result = pcall(os.execute, 'start "YouTubeTV download" /min "ue4ss\\Mods\\YouTubeTV\\download.cmd"')
    if not ok then log("Couldn't start the download: " .. tostring(result)) return end
    log("Downloading " .. #missing .. " video(s) in a minimized window" .. (cookies ~= "" and (" (with your " .. COOKIES:match("^%a+") .. " login)") or "")
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

-- A media player + texture on the actor: MediaComponent first, then Media Plate
local function MakePlayer(actor)
    local tried = {}
    for _, path in ipairs({ "/Script/MediaAssets.MediaComponent", "/Script/MediaPlate.MediaPlateComponent" }) do
        local comp, err = AddComponent(actor, path)
        if comp then
            local player, texture = nil, nil
            pcall(function() player = comp:GetMediaPlayer() end)
            pcall(function() texture = comp:GetMediaTexture() end)
            if Valid(player) and Valid(texture) then
                log("  player and texture from " .. path:match("%.(%w+)$"))
                return comp, player, texture
            end
            table.insert(tried, path:match("%.(%w+)$") .. ": no player/texture")
            pcall(function() comp:K2_DestroyComponent(comp) end)
        else
            table.insert(tried, err)
        end
    end
    return nil, table.concat(tried, "; ")
end

local function OpenVideo(player, index)
    local v = videos[index]
    if not v then return false, "no video " .. tostring(index) end
    if not Downloaded(v.id) then return false, v.id .. " isn't downloaded yet (.tv download, then .tv list)" end
    -- starts by itself once opened (a component's player may have it off)
    pcall(function() player.PlayOnOpen = true end)
    local ok, opened = pcall(function() return player:OpenFile(FileOf(v.id)) end)
    if not ok then return false, "OpenFile failed: " .. tostring(opened) end
    pcall(function() player:SetLooping(false) end)
    log(string.format("  opening video %d (%s): %s", index, v.id, tostring(opened)))
    return true
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
                for _, k in ipairs({ "X", "Y", "Ticks" }) do
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
    get("length", function() return p:GetDuration() end)
    get("time", function() return p:GetTime() end)
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
    pcall(function() tv.player:Close() end)
    if tv.hud and tv.hud.panel then pcall(function() tv.hud.panel:RemoveFromParent() end) end
    if Valid(tv.panel) then pcall(function() tv.panel:SetVisibility(false, false) end) end
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
    local media, player, texture = MakePlayer(pawn)
    if not media then log("  no player: " .. tostring(player)) return end
    tv = { actor = pawn, media = media, player = player, texture = texture, index = index or 1 }
    tv.sound = AttachSound(pawn, player, false)
    local hud, err = HudPanel(texture)
    if hud then tv.hud = hud log("  panel shown top right") else log("  no panel: " .. err) end
    local ok, why = OpenVideo(player, tv.index)
    if not ok then log("  " .. why) end
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
-- (you look at the screen when you turn it on). Returns location, rotation,
-- width and height in cm.
local function FrontOf(mesh)
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
    -- you, in the TV's own directions
    local here = PlayerLocation()
    if not here then return nil, "load into a world first" end
    local lx, ly = Turn(here.X - loc.X, here.Y - loc.Y, -rot.Yaw)
    -- the side facing you: along the TV's X or Y, whichever points at you more
    local faceYaw, out, across
    if math.abs(lx) >= math.abs(ly) then
        faceYaw = lx >= 0 and 0 or 180
        out, across = hx, hy
        cx = cx + (lx >= 0 and 1 or -1) * (hx + 0.5)
    else
        faceYaw = ly >= 0 and 90 or -90
        out, across = hy, hx
        cy = cy + (ly >= 0 and 1 or -1) * (hy + 0.5)
    end
    local wx, wy = Turn(cx, cy, rot.Yaw)
    return { X = loc.X + wx, Y = loc.Y + wy, Z = loc.Z + cz },
           { Pitch = 0, Yaw = rot.Yaw + faceYaw, Roll = 0 },
           across * 2 * SCREEN_WIDTH, hz * 2 * SCREEN_HEIGHT
end

-- Builds the panel on the actor showing texture through material's param.
-- Returns the panel or nil, why
local function MakePanel(actor, mesh, material, param, texture)
    local cube = LoadObject(CUBE)
    if not cube then return nil, "the engine's cube shape isn't in this game (" .. CUBE .. ")" end
    local where, rot, width, height = FrontOf(mesh)
    if not where then return nil, rot end
    local panel, err = AddComponent(actor, "/Script/Engine.StaticMeshComponent")
    if not panel then return nil, err end
    pcall(function() panel:SetCollisionEnabled(0) end)   -- you walk and shoot through it
    pcall(function() panel:SetStaticMesh(cube) end)
    local dmi = nil
    pcall(function() dmi = panel:CreateDynamicMaterialInstance(0, material, FName("YouTubeTVScreen")) end)
    if not Valid(dmi) then
        pcall(function() panel:K2_DestroyComponent(panel) end)
        return nil, "couldn't make the screen's material"
    end
    local ok, e = pcall(function() dmi:SetTextureParameterValue(FName(param), texture) end)
    if not ok then
        pcall(function() panel:K2_DestroyComponent(panel) end)
        return nil, "SetTextureParameterValue failed: " .. tostring(e)
    end
    local placed = { where = where, rot = rot, width = width, height = height, turn = 0, mirror = false }
    return panel, placed, dmi
end

-- Puts the panel where placed says (also after .tv turn / mirror / size)
local function PlacePanel(panel, placed)
    local rot = { Pitch = placed.rot.Pitch, Yaw = placed.rot.Yaw, Roll = placed.turn }
    pcall(function() panel:K2_SetWorldLocationAndRotation(placed.where, rot, false, {}, false) end)
    -- the cube is 100 cm: thin along X (towards you), the screen's size across
    local w, h = placed.width / 100, placed.height / 100
    if placed.turn % 180 ~= 0 then w, h = h, w end
    pcall(function() panel:SetWorldScale3D({ X = 0.004, Y = placed.mirror and -w or w, Z = h }) end)
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

-- Turns a TV on: actor is the TV, aimed the part you looked at (or nil)
local function OnActor(actor, aimed, index)
    if tv then Stop() end
    log("TV on: " .. NameOf(actor) .. " (" .. ClassName(actor) .. ")")
    local screen = PickScreen(actor, aimed)
    if not screen then log("  it has no mesh to show a picture on") return end
    local param = PickParam(screen.params)
    log(string.format("  TV mesh: %s, material %s, texture slot: %s", NameOf(screen.mesh), NameOf(screen.mat),
        param or "none"))
    if not param then log("  its material has no texture slot to show the video in") return end
    -- turned on before: the same player, sound and screen again
    local addr = AddressOf(actor)
    local old = addr and kept[addr]
    if old then
        kept[addr] = nil
        tv = old
        tv.index = index or 1
        if Valid(tv.panel) then
            pcall(function() tv.panel:SetVisibility(true, false) end)
            PlacePanel(tv.panel, tv.placed)
        end
        local ok, why = OpenVideo(tv.player, tv.index)
        if not ok then log("  " .. why) end
        log("  (the same player, sound and screen as before)")
        return
    end
    local media, player, texture = MakePlayer(actor)
    if not media then log("  no player: " .. tostring(player)) return end
    tv = { actor = actor, addr = AddressOf(actor), media = media, player = player, texture = texture, index = index or 1 }
    local panel, placed, dmi = MakePanel(actor, screen.mesh, screen.mat, param, texture)
    if panel then
        tv.panel, tv.placed, tv.dmi = panel, placed, dmi
        PlacePanel(panel, placed)
        log(string.format("  screen panel on the front, %.0f x %.0f cm (.tv turn / .tv mirror / .tv size if it's off)",
            placed.width, placed.height))
    else
        log("  no screen panel: " .. tostring(placed))
    end
    tv.sound = AttachSound(actor, player, true)
    local ok, why = OpenVideo(player, tv.index)
    if not ok then log("  " .. why) end
    log("Done - send these lines if the TV stays dark or silent (.tv off stops it)")
end

local function On(index)
    local target, err = LookedAt(false)
    if not target then log("TV on: " .. err .. " - look at the TV") return end
    OnActor(target.actor, target.comp, index)
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

local function Next()
    if not tv then log("Nothing playing - .tv on") return end
    if #videos == 0 then return end
    tv.index = tv.index % #videos + 1
    local ok, why = OpenVideo(tv.player, tv.index)
    if not ok then log(why) end
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
local eMenu = { hooked = false, logged = {}, menu = nil, entry = nil, index = nil, tvActor = nil }

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
local function HasOurEntry(box)
    local count = 0
    pcall(function() count = box:GetChildrenCount() end)
    for i = 0, count - 1 do
        local e, name = nil, nil
        pcall(function() e = box:GetChildAt(i) end)
        pcall(function() name = e.Action[E_ACTION_NAME]:ToString() end)
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
    local action = { [E_ACTION_TYPE] = E_TYPE, [E_ACTION_NAME] = FText(label) }
    -- Filled in directly, not with InitializeEntry: that starts the entry's
    -- UpdateText timer, which asks the TV for its actions again, finds none at
    -- our index and removes the entry about a second later (0.4.1)
    Step("filling it in")
    pcall(function() entry.Action = action end)
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
    eMenu.menu = menu
    if not IsTv(actor) then return end
    Step("the E menu is for a TV")
    local ok, err = pcall(AddEntry, menu, actor)
    if not ok then LogOnce("adderr", "E menu: " .. tostring(err)) end
end

-- E: if our entry is the selected one, the TV goes on / off
local lastToggle = -100
local function OnEKey()
    -- read fresh from the menu: the entry selected now and what you look at now
    -- (an entry or TV kept from earlier may have been deleted since)
    local menu = eMenu.menu
    if not menu then LogOnce("e-nomenu", "E menu: E pressed, but no menu seen yet") return end
    local selected, box = nil, nil
    pcall(function() selected = menu.SelectedEntryIndex end)
    pcall(function() box = menu.ContextVerticalBox end)
    if type(selected) ~= "number" or not Valid(box) then
        LogOnce("e-nobox", "E menu: E pressed, but couldn't read the menu's selection (" .. tostring(selected) .. ")")
        return
    end
    local entry, name = nil, nil
    pcall(function() entry = box:GetChildAt(selected) end)
    pcall(function() name = entry.Action[E_ACTION_NAME]:ToString() end)
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
        Stop()
    else
        local main = nil
        pcall(function() main = actor.StaticMesh end)   -- the TV body (not its lace)
        OnActor(actor, Valid(main) and main or nil, 1)
    end
    -- the entry's label follows
    local label = PlayingOn(actor) and LABEL_OFF or LABEL_ON
    pcall(function() entry.Action[E_ACTION_NAME] = FText(label) end)
    pcall(function() entry.TextBlock:SetText(FText(label)) end)
    pcall(function() entry.TextBlock_86:SetText(FText(label)) end)
end

-- A build part is being removed (a TV picked up, broken, or the level
-- unloading): forget everything kept for it, before the game deletes it
local function Forget(addr)
    if not addr then return end
    if tv and tv.addr == addr then
        pcall(function() tv.player:Close() end)
        tv = nil
        log("The TV that was on was picked up or removed - off")
    end
    kept[addr] = nil
end

local function ForgetAll()
    if tv then pcall(function() tv.player:Close() end) end
    tv, kept = nil, {}
    eMenu.menu = nil
end

local function HookEMenu()
    if not E_MENU or eMenu.hooked then return end
    if not Find(MENU_CLASS) then return end   -- loaded with the HUD
    eMenu.hooked = true
    local ok = pcall(RegisterHook, MENU_CLASS .. ":InitializeContextMenu", OnMenuBuilt)
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
    local ok = pcall(RegisterHook, path, function(self)
        local menu = nil
        if isMenu then
            pcall(function() menu = self:get() end)
            if Valid(menu) then learning.menu = menu end   -- the E key reads it (no object search)
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
                local menu = learning.menu
                if not Valid(menu) then log("learn: E pressed - no menu seen yet") return end
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
            elseif a == "next" then Next()
            elseif a == "status" then Status()
            elseif a == "learn" then Learn()
            elseif a == "turn" or a == "mirror" or a == "size" then Adjust(a, Parameters and Parameters[2])
            elseif a == "off" then Stop()
            else log(".tv probe | download | list | scan | hud [n] | on [n] | status | next | turn | mirror | size <x> | off | learn") end
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
    destroyHooked = pcall(RegisterHook, BUILD_PART .. ":ReceiveDestroyed", function(self)
        local addr = nil
        pcall(function() addr = self:get():GetAddress() end)
        if addr and (kept[addr] or (tv and tv.addr == addr)) then Forget(addr) end
    end)
end
pcall(HookDestroyed)

-- The TV's class exists once a level with TVs has loaded: hook its menu then
pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteInGameThread(function()
            ForgetAll()   -- a new level or a respawn: nothing from before is safe to touch
            pcall(HookEMenu)
            pcall(HookDestroyed)
        end)
    end)
end)
pcall(HookEMenu)

log("Loaded v" .. VERSION .. " (experimental): " .. #videos .. " video(s) in config.lua. .tv probe to start")
