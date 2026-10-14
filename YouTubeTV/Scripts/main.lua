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
--   .tv scan         TVs and screens near you, their materials and texture slots
--   .tv hud          plays the first video in a panel on your screen (tests playback)
--   .tv on [n]       plays video n (default 1) on the nearest TV
--   .tv next         the next video
--   .tv off          stops it (the HUD panel too)
--
-- Videos are downloaded with yt-dlp (+ ffmpeg) as H.264/AAC .mp4, which the
-- game's Windows video player (WMF) plays. Only the 11-character video ID is
-- taken from each link; the command is built from it, never from the link.
-- Co-op (the host's list for everyone, in sync) comes later.
------------------------------------------------------------
local VERSION = "0.1.4"
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
-- .tv scan: TVs and screens near you
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
local function Meshes(actor)
    local list = {}
    pcall(function()
        Each(actor:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent")), function(c)
            if Valid(c) then table.insert(list, c) end
        end)
    end)
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

-- Actors within SCAN_METERS whose class, name or mesh looks like a TV, nearest first
local function NearbyTvs()
    local here = PlayerLocation()
    if not here then return nil, "load into a world first" end
    local found = {}
    local actorClass = StaticFindObject("/Script/Engine.Actor")
    pcall(function()
        ForEachUObject(function(obj)
            local isActor = false
            pcall(function() isActor = obj:IsA(actorClass) end)
            if isActor and not NameOf(obj):find("^Default__") then
                local ok, l = pcall(function() return obj:K2_GetActorLocation() end)
                if ok and l then
                    local d = Distance(here, l)
                    if d <= SCAN_METERS then
                        local tv = LooksLikeTv(ClassName(obj)) or LooksLikeTv(NameOf(obj))
                        if not tv then
                            for _, m in ipairs(Meshes(obj)) do
                                if LooksLikeTv(MeshAssetName(m)) then tv = true break end
                            end
                        end
                        if tv then table.insert(found, { actor = obj, dist = d }) end
                    end
                end
            end
            return false
        end)
    end)
    table.sort(found, function(a, b) return a.dist < b.dist end)
    return found
end

local function Scan()
    local tvs, err = NearbyTvs()
    if not tvs then log("Scan: " .. err) return end
    log(string.format("Scan: %d TV-like thing(s) within %d m", #tvs, SCAN_METERS))
    for i, t in ipairs(tvs) do
        if i > 8 then break end
        log(string.format("  %s (%s) %.1f m", NameOf(t.actor), ClassName(t.actor), t.dist))
        for _, m in ipairs(Meshes(t.actor)) do
            log("    mesh " .. NameOf(m) .. " = " .. MeshAssetName(m))
            for _, s in ipairs(Materials(m)) do
                local params = TextureParams(s.mat)
                log(string.format("      slot %d: %s (%s)  textures: %s", s.slot, NameOf(s.mat), ClassName(s.mat),
                    #params > 0 and table.concat(params, ", ") or "-"))
            end
        end
    end
    if #tvs == 0 then log("  Stand next to a TV and run it again (or raise scanMeters in config.lua)") end
    log("Done - send these lines")
end

------------------------------------------------------------
-- Playback: a player and its texture, made by an engine component
------------------------------------------------------------
-- tv = { actor, media, player, texture, sound, dmi, index, hud = { panel } }
local tv = nil

-- Adds a component of the given class to an actor, registered (so it gets
-- set up like one made in the editor)
local function AddComponent(actor, classPath)
    local cls = Find(classPath)
    if not cls then return nil, classPath .. " isn't in this game" end
    local comp = nil
    local ok, err = pcall(function()
        comp = actor:AddComponentByClass(cls, false, {
            Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
            Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    end)
    if not ok or not Valid(comp) then return nil, "AddComponentByClass failed: " .. tostring(err) end
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
            for _, k in ipairs({ "X", "Y", "Ticks" }) do
                local okk, kv = pcall(function() return v[k] end)
                if okk and kv ~= nil then table.insert(parts, k .. "=" .. tostring(kv)) end
            end
            if #parts == 0 then pcall(function() table.insert(parts, v:ToString()) end) end
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
    get("video tracks", function() return p:GetNumTracks(1) end)   -- 1 = video
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

local function AttachSound(actor, player)
    local sound, err = AddComponent(actor, "/Script/MediaAssets.MediaSoundComponent")
    if not sound then log("  no sound: " .. err) return nil end
    pcall(function() sound:SetMediaPlayer(player) end)
    pcall(function() sound:SetVolumeMultiplier(VOLUME) end)
    log("  sound attached")
    return sound
end

local function Stop()
    if not tv then log("Nothing playing") return end
    pcall(function() tv.player:Close() end)
    if tv.hud and tv.hud.panel then pcall(function() tv.hud.panel:RemoveFromParent() end) end
    for _, c in ipairs({ tv.sound, tv.media }) do
        if Valid(c) then pcall(function() c:K2_DestroyComponent(c) end) end
    end
    if tv.mesh and tv.oldMaterial then pcall(function() tv.mesh:SetMaterial(tv.slot, tv.oldMaterial) end) end
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
    tv.sound = AttachSound(pawn, player)
    local hud, err = HudPanel(texture)
    if hud then tv.hud = hud log("  panel shown top right") else log("  no panel: " .. err) end
    local ok, why = OpenVideo(player, tv.index)
    if not ok then log("  " .. why) end
    log("Done - if the panel stays black or silent, send these lines (.tv off stops it)")
end

------------------------------------------------------------
-- .tv on: the picture on the nearest TV's screen
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

local function PickScreen(actor)
    local best = nil
    for _, m in ipairs(Meshes(actor)) do
        for _, s in ipairs(Materials(m)) do
            local params = TextureParams(s.mat)
            local name = NameOf(s.mat):lower()
            local score = (#params > 0 and 1 or 0)
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

local function On(index)
    if tv then Stop() end
    local tvs, err = NearbyTvs()
    if not tvs then log(err) return end
    if #tvs == 0 then log("No TV within " .. SCAN_METERS .. " m (.tv scan lists what's near)") return end
    local actor = tvs[1].actor
    log("TV on: " .. NameOf(actor) .. " (" .. ClassName(actor) .. ")")
    local screen = PickScreen(actor)
    if not screen then log("  it has no mesh to show a picture on") return end
    log(string.format("  screen: %s slot %d, %s (%s), texture slots: %s", NameOf(screen.mesh), screen.slot,
        NameOf(screen.mat), ClassName(screen.mat), #screen.params > 0 and table.concat(screen.params, ", ") or "none"))
    local media, player, texture = MakePlayer(actor)
    if not media then log("  no player: " .. tostring(player)) return end
    tv = { actor = actor, media = media, player = player, texture = texture, index = index or 1,
           mesh = screen.mesh, slot = screen.slot, oldMaterial = screen.mat }
    local param = PickParam(screen.params)
    if param then
        local dmi = nil
        pcall(function() dmi = screen.mesh:CreateDynamicMaterialInstance(screen.slot, screen.mat, FName("YouTubeTV")) end)
        if Valid(dmi) then
            local ok, e = pcall(function() dmi:SetTextureParameterValue(FName(param), texture) end)
            log(ok and ("  video shown through texture slot '" .. param .. "'") or ("  SetTextureParameterValue failed: " .. tostring(e)))
            tv.dmi = dmi
        else
            log("  couldn't copy the screen material")
        end
    else
        log("  the screen material has no texture slot to show the video in (sound only for now)")
    end
    tv.sound = AttachSound(actor, player)
    local ok, why = OpenVideo(player, tv.index)
    if not ok then log("  " .. why) end
    log("Done - send these lines if the TV stays dark or silent (.tv off stops it)")
end

local function Next()
    if not tv then log("Nothing playing - .tv on") return end
    if #videos == 0 then return end
    tv.index = tv.index % #videos + 1
    local ok, why = OpenVideo(tv.player, tv.index)
    if not ok then log(why) end
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
            elseif a == "off" then Stop()
            else log(".tv probe | download | list | scan | hud [n] | on [n] | status | next | off") end
        end)
        if not ok then log("Error: " .. tostring(err)) end
    end)
    return true
end)

log("Loaded v" .. VERSION .. " (experimental): " .. #videos .. " video(s) in config.lua. .tv probe to start")
