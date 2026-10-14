------------------------------------------------------------
-- Mod Hub
------------------------------------------------------------
-- One menu for all the mods: which ones are loaded, each mod's hotkeys and
-- console commands, a button for mods that have their own menu, and
-- restarting mods after you've changed them (no game restart needed).
--
--   .mods                  open / close the hub (in a world)
--                          Up/Down choose, Right/Enter open, Left back
--   .reloadmods            restart the mods whose main.lua changed
--   .reloadmods <Name>     restart one, e.g. .reloadmods RadiationShield
--
-- Each mod's page also shows its CHANGELOG.md, and Settings for the values
-- in its config.example.lua: changed there, they are saved to the mod's
-- config.lua (the player's own file, which git pull never touches).
-- New mods still need a game restart. A restarted mod starts fresh: a shield
-- that was on is off again, the PageUp menu is closed, and so on. The hub
-- restarts itself last when it has changed too.
------------------------------------------------------------

local MODS_DIR = "./ue4ss/Mods/"
local SELF = "ModHub"

-- What the hub knows about each mod. Mods not listed here still show up,
-- just without details.
local INFO = {
    { name = "MISERYModMenu", title = "Mod Menu",
      about = "Spawn items and enemies, set the time and weather, trigger events, and cheats. In co-op the host's menu gives you items and stats; time, weather and enemies are the host's.",
      menu = { "Open the spawn menu", ".menu" },
      keys = { { "6 / 7", "Health +100 / Stamina +100" },
               { "8 / 9", "Hunger +50 / Thirst +50" }, { "0", "Radiation -50" },
               { "- / =", "Insanity -50 / Health -25" } },
      commands = { { ".menu", "Spawn menu" }, { ".find <name>", "Search the item list" },
                   { ".time <hour>", "Set the time (0-24)" }, { ".weather <type>", "sunny, rain, thunder" },
                   { ".season <name>", "spring, summer, autumn, winter" }, { ".god / .ih", "God mode / auto-heal" },
                   { ".tp", "Teleport to the crosshair" }, { ".savepos / .loadpos", "Save / return to a position" },
                   { ".help", "Every command of this mod" } } },
    { name = "RadiationShield", title = "Radiation Shield",
      about = "Less radiation while it's on, for bunker hot spots. In co-op the host decides who may use it and how strong it is.",
      menu = { "Open shield settings", ".radmenu" },
      keys = { { "HOME", "Shield on / off" } },
      commands = { { ".radmenu", "Settings and live readout" }, { ".radshield", "Shield on / off" },
                   { ".radshield 75", "75% less radiation (host)" }, { ".radmeter", "Measure a hot spot (run twice)" },
                   { ".radshield scan", "Radiation numbers on your stats, for the log" } } },
    { name = "StackThemAll", title = "Stack Them All",
      about = "Bigger stacks. Items added by game updates get a stack size automatically. Money stacks to 250.",
      notes = "Your stack sizes: config.lua (see config.example.lua); per item: scripts\\stackConfig.lua" },
    { name = "Mi8CargoHold", title = "Mi-8 Cargo Hold",
      about = "The Mi-8 wreck becomes a 1,000-slot storage container. In co-op everyone uses the host's hold.",
      keys = { { "ENTER", "At the wreck: open the hold" } } },
    { name = "WorldTweaks", title = "World Tweaks",
      about = "Day and night length, season, and darker nights. In co-op the host's day length and season apply.",
      commands = { { ".worldinfo", "Show the day/night settings" }, { ".weatherdump", "Write the weather presets to a file" } } },
    { name = "BackpackWeightFix", title = "Backpack Weight Fix",
      about = "Empty containers stuck with weight (like 73/75 kg) go back to 0 every 30 s. In co-op the host's copy fixes everyone's.",
      commands = { { ".fixweight", "Fix it right now" }, { ".weightreport", "If the fix can't find the weight value" } } },
    { name = "RandomEmissions", title = "Random Emissions",
      about = "Emissions at random times, with a siren warning before each one. In co-op the host picks the times; everyone hears the siren." },
    { name = "MISERY_StructuralFreedom", title = "Structural Freedom",
      about = "Relaxed building support rules; normal placement rules still apply. In co-op everyone needs it.",
      commands = { { "structuralfreedomstatus", "Is it active?" }, { "structuralfreedominstall", "Apply it again" } } },
    { name = "HeadBob", title = "Head Bob",
      about = "How much the view bobs while walking and running, in percent of the game's own. Only your own view, so co-op is unaffected.",
      commands = { { ".headbob 50", "Walking and running bob at 50%" }, { ".headbob walk <n>", "Walking only (0-200)" },
                   { ".headbob run <n>", "Running only (0-200)" }, { ".headbob off / reset", "None / the game's own" },
                   { ".headbob", "Show the settings" }, { ".headbob scan", "If it doesn't work: list what the game uses" } } },
    { name = "ReticleSize", title = "Reticle Size",
      about = "The size, colour and see-through-ness of the crosshair dot. Only your own screen, so co-op is unaffected.",
      commands = { { ".reticle 50", "Crosshair at 50% (10-400)" }, { ".dot 50", "The same" },
                   { ".reticle reset", "The game's size" }, { ".reticle color red", "Colour: a name or hex like ff8800" },
                   { ".reticle alpha 50", "50% see-through" }, { ".reticle color reset", "The game's colour" },
                   { ".reticle", "Show the settings" },
                   { ".reticle scan", "If it doesn't work: list what the dot could be" } } },
    { name = "SurvivalStats", title = "Survival Stats",
      about = "A small panel with your exact survival numbers (health, stamina, hunger, thirst, radiation, ...), off until you switch it on. Only reads your own numbers, so it's safe in co-op.",
      commands = { { ".stats", "Panel on / off" }, { ".stats move", "Next position on the screen" },
                   { ".stats scan", "If a stat is missing: list the numbers" } } },
    { name = "WhistleRange", title = "Whistle Range",
      about = "Co-op: players who joined get whistles (and see players) from as far away as the host does. Only the host needs it.",
      commands = { { ".whistle", "The range and the players it's applied to" },
                   { ".whistle scan", "List everything named like a whistle" } } },
    { name = "YouTubeTV", title = "YouTube TV",
      about = "Experimental: TVs play YouTube videos from config.lua, with sound. This version tests each step and logs it.",
      notes = "Videos: config.lua (see config.example.lua); needs yt-dlp and ffmpeg for .tv download",
      commands = { { ".tv probe", "Which video pieces the game has" }, { ".tv download", "Download the videos (yt-dlp)" },
                   { ".tv list", "Which videos are downloaded" }, { ".tv scan", "TVs near you and their materials" },
                   { ".tv hud [n]", "Play a video in a panel on screen" }, { ".tv on [n]", "Play on the nearest TV" },
                   { ".tv next", "Next video" }, { ".tv off", "Stop" } } },
    { name = "ViewDebug", title = "View Debug",
      about = "Work in progress: for the weapon and arms getting stuck at an angle after slow mouse moves. Records your view's angles; changes nothing.",
      commands = { { ".view hud", "Show / hide the angles on screen, live" },
                   { ".view buffer", "Keep the last 25 s of angles (on / off)" },
                   { ".view dump", "Save the last 25 s now" },
                   { ".view dumps", "List the saved dumps" },
                   { ".view read [n]", "Show a dump on screen: where your aim got stuck" },
                   { ".view raw [seconds]", "The dump's recorded rows (left / right arrow: page)" },
                   { ".view close", "Close the dump on screen (or Backspace)" },
                   { ".view rec [seconds]", "Record the angles from now" },
                   { ".view stop", "Stop recording" }, { ".view mark [note]", "Mark this moment" },
                   { ".view", "Your view's angles now" }, { ".view watch", "Angles in the log, 4 a second" },
                   { ".view scan", "List everything on your character that turns" } } },
    { name = "NotSoShaky", title = "Not So Shaky",
      about = "Softer camera shake when you're hit." },
    { name = "ModHub", title = "Mod Hub",
      about = "This menu: the loaded mods, their keys, commands, settings and changelogs, and restarting mods you've changed.",
      keys = { { "PAGE UP", "Open / close this menu" }, { "BACKSPACE", "Back / close" } },
      commands = { { ".mods", "Open / close this menu" }, { ".reloadmods", "Restart the mods you've changed" },
                   { ".reloadmods <Name>", "Restart one mod" } } },
    -- UE4SS's own: shown, never restarted from here
    { name = "Keybinds", title = "Keybinds", builtin = true, about = "UE4SS: built-in key bindings." },
    { name = "ConsoleEnablerMod", title = "Console Enabler", builtin = true, about = "UE4SS: the ~ console." },
    { name = "ConsoleCommandsMod", title = "Console Commands", builtin = true, about = "UE4SS: extra console commands." },
    { name = "CheatManagerEnablerMod", title = "Cheat Manager Enabler", builtin = true, about = "UE4SS: turns on the game's cheat manager." },
    { name = "BPModLoaderMod", title = "Blueprint Mod Loader", builtin = true, about = "UE4SS: loads Blueprint mods from LogicMods." },
    { name = "BPML_GenericFunctions", title = "BPML Generic Functions", builtin = true, about = "UE4SS: helper for Blueprint mods." },
    { name = "LineTraceMod", title = "Line Trace", builtin = true, about = "UE4SS: debugging example." },
    { name = "SplitScreenMod", title = "Split Screen", builtin = true, about = "UE4SS: split-screen example." },
}
local INFO_BY_NAME, ORDER = {}, {}
for i, info in ipairs(INFO) do INFO_BY_NAME[info.name], ORDER[info.name] = info, i end

local function log(msg)
    print("[ModHub] " .. tostring(msg) .. "\n")
end

------------------------------------------------------------
-- Mods on disk
------------------------------------------------------------
local function ReadFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("a")
    file:close()
    return data
end

local function Script(name) return ReadFile(MODS_DIR .. name .. "/Scripts/main.lua") end

-- "Name : 1" lines of mods.txt (how UE4SS's own mods are switched on)
local function ModsTxt()
    local on = {}
    local text = ReadFile(MODS_DIR .. "mods.txt") or ""
    for line in text:gmatch("[^\r\n]+") do
        local name, flag = line:match("^%s*([%w_%-]+)%s*:%s*(%d)")
        if name and flag == "1" then on[name] = true end
    end
    return on
end

-- Folder names in Mods (UE4SS can list them; otherwise the known ones)
local function Folders()
    local names = {}
    pcall(function()
        local mods = IterateGameDirectories().Game.Binaries.Win64.ue4ss.Mods
        for key in pairs(mods) do
            if type(key) == "string" and key:sub(1, 2) ~= "__" then table.insert(names, key) end
        end
    end)
    if #names == 0 then
        for _, info in ipairs(INFO) do table.insert(names, info.name) end
    end
    return names
end

local function Loaded()
    local txt, seen, list = ModsTxt(), {}, {}
    local function add(name)
        if seen[name] or name == "shared" then return end
        seen[name] = true
        local enabled = io.open(MODS_DIR .. name .. "/enabled.txt", "r")
        if enabled then enabled:close() end
        if enabled or txt[name] then table.insert(list, name) end
    end
    for _, name in ipairs(Folders()) do add(name) end
    for name in pairs(txt) do add(name) end
    table.sort(list, function(a, b)
        local ia, ib = ORDER[a] or 1000, ORDER[b] or 1000
        if ia ~= ib then return ia < ib end
        return a:lower() < b:lower()
    end)
    return list
end

local function Builtin(name) return INFO_BY_NAME[name] ~= nil and INFO_BY_NAME[name].builtin == true end

------------------------------------------------------------
-- Changelogs
------------------------------------------------------------
-- A mod's CHANGELOG.md (or .txt), one entry per version, newest first:
-- { title = "1.2.0 (2026-10-12)", lines = { { kind = ..., text = ... } } }.
-- kind: "topic" (### or a **bold** line), "item" (- / * / 1. ...; level and
-- mark), "head" and "row" (table rows; cells), "code" or "text".
-- Only version sections are kept (not Installation and the like).
local CHANGELOG_FILES = { "CHANGELOG.md", "CHANGELOG.txt", "changelog.md", "changelog.txt" }

-- Markdown marks the menu can't show: bold, code, links
local function Plain(line)
    line = line:gsub("%[([^%]]+)%]%([^%)]*%)", "%1")
    line = line:gsub("%*%*", ""):gsub("__", ""):gsub("`", "")
    return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function IsVersion(heading)
    return heading:find("%d") ~= nil or heading:lower():find("original") ~= nil
end

local function Cells(line)
    local cells = {}
    local inner = line:gsub("^%s*|", ""):gsub("|%s*$", "")
    for cell in (inner .. "|"):gmatch("([^|]*)|") do table.insert(cells, Plain(cell)) end
    return cells
end

local function Changelog(name)
    local text = nil
    for _, file in ipairs(CHANGELOG_FILES) do
        text = ReadFile(MODS_DIR .. name .. "/" .. file)
        if text then break end
    end
    if not text then return nil end
    local raw = {}
    for line in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do table.insert(raw, line) end
    local versions, current, code, lastBlank = {}, nil, false, true
    local function add(entry)
        if current then table.insert(current.lines, entry) end
        return entry
    end
    local last = nil   -- the entry a wrapped line continues
    for i, line in ipairs(raw) do
        local nextLine = raw[i + 1] or ""
        local heading = nil
        if not code then
            if line:match("^##%s") then
                heading = Plain(line:gsub("^##%s*", ""))
            elseif line:match("%S") and not line:match("^%s*[%-|#>]") and nextLine:match("^%-%-%-+%s*$") then
                heading = Plain(line)   -- "1.0.0" underlined with dashes (.txt)
            end
        end
        if heading then
            current = nil
            if IsVersion(heading) then
                current = { title = (heading:gsub("^[Vv]ersion%s+", "")), lines = {} }
                table.insert(versions, current)
            end
            last = nil
        elseif current then
            if line:match("^%s*```") then
                code = not code
                last = nil
            elseif code then
                add({ kind = "code", text = line })
            elseif line:match("^%s*$") or line:match("^%-%-%-+%s*$") or line:match("^===+%s*$") then
                last = nil
            elseif line:match("^#+%s") then
                last = nil
                add({ kind = "topic", text = Plain(line:gsub("^#+%s*", "")) })
            elseif line:match("^%s*%*%*[^*]+%*%*:?%s*$") then
                last = nil
                add({ kind = "topic", text = Plain(line) })
            elseif line:match("^%s*|") then
                last = nil
                local cells = Cells(line)
                local separator = true
                for _, c in ipairs(cells) do
                    if not c:match("^:?%-+:?$") then separator = false end
                end
                local prev = current.lines[#current.lines]
                if separator then
                    if prev and prev.kind == "row" then prev.kind = "head" end
                else
                    add({ kind = "row", cells = cells })
                end
            else
                local indent, mark, rest = line:match("^(%s*)([%-%*%+])%s+(.+)$")
                if not mark then indent, mark, rest = line:match("^(%s*)(%d+[%.%)])%s+(.+)$") end
                if mark then
                    last = add({ kind = "item", text = Plain(rest), level = #indent >= 2 and 2 or 1,
                                 mark = mark:match("%d") and mark or nil })
                elseif last and not lastBlank then
                    last.text = last.text .. " " .. Plain(line)   -- the same paragraph, wrapped
                else
                    last = add({ kind = "text", text = Plain(line:gsub("^%s*>%s?", "")) })
                end
            end
        end
        lastBlank = not line:match("%S")
    end
    for i = #versions, 1, -1 do
        if #versions[i].lines == 0 and not versions[i].title:lower():find("original") then table.remove(versions, i) end
    end
    if #versions == 0 then return nil end
    return versions
end

-- "1.2.0 (2026-10-12)" -> "1.2.0"
local function LatestVersion(versions)
    local first = versions and versions[1]
    return first and (first.title:match("^(%S+)")) or nil
end

------------------------------------------------------------
-- Settings (a mod's config.example.lua and the player's config.lua)
------------------------------------------------------------
-- Every `key = value,` line of the example's table is a setting; the comment
-- lines just above it describe it. Values can be true / false, numbers or
-- "text". Choices for text are the "quoted" words in its description, and a
-- number whose description mentions false can also be switched off.
local function Literal(s)
    if s == "true" then return true end
    if s == "false" then return false end
    if tonumber(s) then return tonumber(s) end
    local str = s:match('^"(.*)"$') or s:match("^'(.*)'$")
    return str
end

local function Settings(name)
    local text = ReadFile(MODS_DIR .. name .. "/config.example.lua")
    if not text then return nil end
    local list, about, inTable = {}, {}, false
    for line in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        if not inTable then
            if line:match("^%s*return%s*{") then inTable = true end
        elseif line:match("^%s*%-%-") then
            table.insert(about, (line:gsub("^%s*%-%-%s?", "")))
        elseif line:match("^%s*$") then
            about = {}
        else
            local key, raw = line:match("^%s*([%a_][%w_]*)%s*=%s*([^,]-)%s*,?%s*$")
            if not key then key, raw = line:match("^%s*([%a_][%w_]*)%s*=%s*([^,]-)%s*,?%s*%-%-") end
            local value = raw and Literal(raw)
            if key and value ~= nil then
                local s = { key = key, default = value, about = #about > 0 and table.concat(about, " ") or nil }
                if type(value) == "boolean" then
                    s.kind = "bool"
                elseif type(value) == "number" then
                    s.kind = "number"
                    s.decimals = #(raw:match("%.(%d+)") or "")
                    s.allowFalse = s.about ~= nil and s.about:find("false", 1, true) ~= nil
                else
                    s.kind = "text"
                    s.choices, s.seen = {}, {}
                    for choice in ((s.about or "") .. ' "' .. value .. '"'):gmatch('"([^"]*)"') do
                        if not s.seen[choice] then s.seen[choice] = true table.insert(s.choices, choice) end
                    end
                end
                table.insert(list, s)
                about = {}
            end
        end
    end
    return #list > 0 and list or nil
end

local function ConfigPath(name) return MODS_DIR .. name .. "/config.lua" end

-- The player's own values (config.lua), or nil and the problem
local function UserValues(name)
    local path = ConfigPath(name)
    local file = io.open(path, "r")
    if not file then return {} end
    file:close()
    local ok, result = pcall(dofile, path)
    if ok and type(result) == "table" then return result end
    return nil, ok and "it doesn't return a table" or tostring(result)
end

local function LuaValue(s, value)
    if type(value) == "boolean" then return tostring(value) end
    if type(value) == "number" then
        if (s.decimals or 0) > 0 then return string.format("%." .. s.decimals .. "f", value) end
        return string.format("%d", math.floor(value + 0.5))
    end
    return string.format("%q", tostring(value))
end

-- Writes one value into config.lua: the line with that key gets the new
-- value (everything else in the file stays as it is); a missing line is
-- added. No config.lua yet: it starts as a copy of the example.
local function SaveSetting(name, s, value)
    local text = ReadFile(ConfigPath(name)) or ReadFile(MODS_DIR .. name .. "/config.example.lua")
    if not text then return false end
    local lit = LuaValue(s, value)
    local out, done = {}, false
    for line in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        if not done and not line:match("^%s*%-%-") then
            local before, after = line:match("^(%s*" .. s.key .. "%s*=%s*)[^,%-]-(%s*,.*)$")
            if not before then before, after = line:match("^(%s*" .. s.key .. "%s*=%s*)[^,%-]-(%s*)$") end
            if before then
                line, done = before .. lit .. after, true
            end
        end
        table.insert(out, line)
    end
    if out[#out] == "" then table.remove(out) end
    if not done then
        for i = #out, 1, -1 do
            if out[i]:match("^%s*}") then
                table.insert(out, i, "    " .. s.key .. " = " .. lit .. ",")
                done = true
                break
            end
        end
    end
    if not done then return false end
    local file = io.open(ConfigPath(name), "w")
    if not file then return false end
    file:write(table.concat(out, "\n") .. "\n")
    file:close()
    return true
end

-- checkEverySeconds -> "Check every seconds", Food_StackSize -> "Food stack size"
local function Humanize(key)
    local s = key:gsub("^is(%u)", "%1"):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    s = s:lower()
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function Shown(s, value)
    if type(value) == "boolean" then return value and "ON" or "OFF" end
    if type(value) == "number" then return LuaValue(s, value) end
    if value == "" then return "NONE" end
    return tostring(value):upper()
end

-- One step left (-1) or right (+1)
local function Step(s, value, dir)
    if s.kind == "bool" then return not value end
    if s.kind == "text" then
        local i = 1
        for n, c in ipairs(s.choices) do if c == value then i = n end end
        return s.choices[(i - 1 + dir) % #s.choices + 1]
    end
    if type(value) ~= "number" then return s.default end   -- switched off: back on
    local step
    if s.decimals > 0 then
        step = 0.5
    else
        local digits = #tostring(math.floor(math.abs(s.default)))
        step = digits <= 1 and 1 or (digits == 2 and 5 or 10 ^ (digits - 2))
    end
    local new = value + dir * step
    if s.default >= 0 and new < 0 then
        if s.allowFalse then return false end
        new = 0
    end
    return new
end

------------------------------------------------------------
-- Restarting mods
------------------------------------------------------------
-- Each mod's script as it was loaded, to tell which ones changed since
local loadedScript = {}
for _, name in ipairs(Loaded()) do loadedScript[name] = Script(name) end

local function Changed(name)
    if Builtin(name) then return false end
    local now = Script(name)
    return now ~= nil and now ~= loadedScript[name]
end

local function Restart(name)
    if name == SELF then
        -- the hub restarting itself: UE4SS does it once this call is over
        if type(RestartCurrentMod) ~= "function" or not pcall(RestartCurrentMod) then
            log("Couldn't restart the Mod Hub itself - restart the game to update it")
            return false
        end
        log("Restarting the Mod Hub")
        return true
    end
    if type(RestartMod) ~= "function" then
        log("This UE4SS version can't restart mods - restart the game instead")
        return false
    end
    local ok, err = pcall(RestartMod, name)
    if ok then
        loadedScript[name] = Script(name)
        log("Restarted " .. name)
    else
        log("Couldn't restart " .. name .. " (" .. tostring(err) .. ")")
    end
    return ok
end

-- which: "changed", "all", or a mod name. finished(summary, selfRestart) is
-- called on the game thread once done (selfRestart: the hub restarts itself,
-- its menu was closed first).
--
-- The other mods are restarted from a background task, not the game thread.
-- Stopping a mod waits for that mod; a mod with timers (the Mod Menu) can be
-- waiting at that moment to hand work to the game thread, which then never
-- comes back: restarting from the game thread hung the game now and then.
local reloading = false

-- Whether a mouse-driven screen is open (the inventory, the PageUp menu):
-- the game shows the cursor for those. Restarting mods while the inventory
-- was open froze the game (its screen calls hooked functions every frame
-- while hooks are being removed), so restarts wait until it's closed.
local cursorController = nil   -- kept while valid: finding it walks every object
local function CursorShown()
    local shown = false
    pcall(function()
        if not (cursorController and cursorController:IsValid()) then
            cursorController = nil
            for _, pc in ipairs(FindAllOf("BP_SGKController_C") or {}) do
                if pc:IsValid() and pc:IsLocalController() then cursorController = pc break end
            end
        end
        if cursorController then shown = cursorController.bShowMouseCursor == true end
    end)
    return shown
end

local WAIT_FOR_CLOSE_SECONDS = 60

-- notify(text): progress while waiting, for the menu
local function Reload(which, beforeSelf, finished, notify)
    finished = finished or function() end
    notify = notify or function() end
    local list = {}
    if which == "changed" or which == "all" then
        local includeSelf = false
        for _, name in ipairs(Loaded()) do
            if not Builtin(name) and (which == "all" or Changed(name)) then
                if name == SELF then includeSelf = true else table.insert(list, name) end
            end
        end
        if includeSelf then table.insert(list, SELF) end   -- itself last
        if #list == 0 then
            local msg = which == "changed" and "No mod has changed since it was loaded" or "No mods to restart"
            log(msg)
            finished(msg)
            return
        end
    else
        local name = which
        for _, info in ipairs(INFO) do
            if info.name:lower() == which:lower() then name = info.name end
        end
        if not Script(name) then
            log("No mod called '" .. which .. "' (looked for " .. MODS_DIR .. name .. "/Scripts/main.lua)")
            finished("No mod called " .. which)
            return
        end
        list = { name }
    end
    if reloading then
        log("Already restarting mods - wait a moment")
        finished("Already restarting mods")
        return
    end
    reloading = true
    local function Go()
        LoopAsync(10, function()
            -- background task: every mod but the hub itself
            local done = 0
            for _, name in ipairs(list) do
                if name ~= SELF and Restart(name) then done = done + 1 end
            end
            ExecuteInGameThread(function()
                reloading = false
                local selfRestart = false
                if list[#list] == SELF then
                    if beforeSelf then beforeSelf() end
                    if Restart(SELF) then
                        done = done + 1
                        selfRestart = true
                    end
                end
                local msg
                if #list == 1 then
                    msg = (done == 1 and "Restarted " or "Couldn't restart ") .. list[1]
                else
                    msg = done .. " of " .. #list .. " mods restarted"
                end
                log(msg)
                finished(msg, selfRestart)
            end)
            return true
        end)
    end

    if not CursorShown() then Go() return end
    local msg = "Close the inventory (or the menu using the mouse): the mods restart as soon as it's closed"
    log(msg)
    notify(msg)
    local waited, started = 0, false
    LoopAsync(500, function()
        if started then return true end
        waited = waited + 0.5
        ExecuteInGameThread(function()
            if started or not reloading then return end
            if not CursorShown() then
                started = true
                Go()
            elseif waited >= WAIT_FOR_CLOSE_SECONDS then
                started = true
                reloading = false
                log("Not restarted: the inventory stayed open")
                finished("Not restarted: the inventory stayed open")
            end
        end)
        return false
    end)
end

------------------------------------------------------------
-- Running another mod's console command (to open its menu)
------------------------------------------------------------
local function LocalController()
    local found = nil
    pcall(function()
        for _, pc in ipairs(FindAllOf("BP_SGKController_C") or FindAllOf("PlayerController") or {}) do
            if pc:IsValid() and pc:IsLocalController() then found = pc break end
        end
    end)
    return found
end

-- Mods' commands answer the in-game console (the game viewport), so the
-- command goes there, as if typed.
local function RunCommand(cmd)
    local pc = LocalController()
    local viewport = nil
    pcall(function()
        local vc = FindFirstOf("GameViewportClient")
        if vc and vc:IsValid() then viewport = vc end
    end)
    for _, target in ipairs({ viewport, pc }) do
        if pcall(function() target:ProcessConsoleExec(cmd, nil, pc or target) end) then return true end
    end
    log("Couldn't run " .. cmd .. " - type it in the console (~)")
    return false
end

------------------------------------------------------------
-- The menu
------------------------------------------------------------
local UMG = "/Script/UMG."
local VISIBLE, COLLAPSED = 3, 1   -- shown without blocking the mouse / hidden
-- Steel blue on dark navy, like the Radiation Shield menu. Unreal takes
-- linear colours; the comments are the colours you see.
local ACCENT = { R = 0.212, G = 0.445, B = 0.783, A = 1 }   -- steel blue #7FB2E5
local HEADING = { R = 0.205, G = 0.275, B = 0.381, A = 1 }   -- grey-blue #7D8FA6
local WARN = { R = 0.784, G = 0.462, B = 0.136, A = 1 }   -- soft amber #E5B567
local WHITE = { R = 0.791, G = 0.831, B = 0.888, A = 1 }   -- cool white #E6EBF2
local BRIGHT = { R = 1, G = 1, B = 1, A = 1 }
local LABEL = { R = 0.491, G = 0.552, B = 0.637, A = 1 }   -- #BAC4D1
local MUTED = { R = 0.168, G = 0.212, B = 0.275, A = 1 }   -- #727F8F
local INK = { R = 0.004, G = 0.006, B = 0.010, A = 1 }   -- dark text on blue
local PANEL = { R = 0.006, G = 0.009, B = 0.015, A = 0.86 }   -- dark navy #121821, see-through
local BAND = { R = 0.212, G = 0.445, B = 0.783, A = 0.07 }   -- faint blue behind the title
local CARD = { R = 1, G = 1, B = 1, A = 0 }   -- no box behind sections
local ROW_LIT = { R = 0.212, G = 0.445, B = 0.783, A = 0.12 }   -- faint blue on the chosen row
local CAP = { R = 1, G = 1, B = 1, A = 0.05 }
local BUTTON = { R = 1, G = 1, B = 1, A = 0.05 }
local LINE = { R = 0.6, G = 0.7, B = 0.85, A = 0.10 }   -- faint outline
local CLEAR = { R = 0, G = 0, B = 0, A = 0 }
local WIDTH = 480
local BODY_MAX = 470      -- taller than this, the menu's body scrolls
local SCROLLBAR = 12      -- room kept for the scroll bar
local SCROLL_STEP = 80

local hub = { open = false, view = "list", sel = 1, mod = nil, status = nil, openedAt = -1 }
local ui = {}
local lastText = setmetatable({}, { __mode = "k" })

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

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

local function Color(text, c)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
end

local function Text(tree, s, size, color, bold, spacing)
    local t = Construct("TextBlock", tree)
    pcall(function() t.Font.Size = size end)
    if bold then pcall(function() t.Font.TypefaceFontName = FName("Bold") end) end
    if spacing then pcall(function() t.Font.LetterSpacing = spacing end) end
    Color(t, color)
    pcall(function() t:SetShadowColorAndOpacity(CLEAR) end)
    SetText(t, s)
    return t
end

-- Line breaks for long text. Unreal's wrapping never breaks before a word
-- starting with "." (".summon"), so lines of commands ran off the panel; the
-- lines are broken here instead, from an estimate of the text's width, and
-- Unreal's own wrapping stays on as a backup.
local function Wrap(s, widthPx, size, bold, spacing)
    local charWidth = size * (bold and 0.7 or 0.66) + size * (spacing or 0) / 1000
    local perLine = math.max(8, math.floor(widthPx / charWidth))
    local function len(x) return utf8.len(x) or #x end
    local out = {}
    for paragraph in (tostring(s) .. "\n"):gmatch("([^\n]*)\n") do
        if len(paragraph) <= perLine then
            table.insert(out, paragraph)   -- fits: left as written
        else
            local line = ""
            for word in paragraph:gmatch("%S+") do
                if line == "" then
                    line = word
                elseif len(line) + 1 + len(word) <= perLine then
                    line = line .. " " .. word
                else
                    table.insert(out, line)
                    line = word
                end
            end
            table.insert(out, line)
        end
    end
    return table.concat(out, "\n")
end

local function WrappedText(tree, s, size, color, widthPx, bold, spacing)
    local t = Text(tree, Wrap(s, widthPx, size, bold, spacing), size, color, bold, spacing)
    pcall(function() t:SetAutoWrapText(true) end)
    return t
end

-- Square panels with a thin outline (UE5 rounded-box brushes at radius 0)
local function Round(border, radius, outline)
    radius = 0   -- square look; kept as a switch should rounded corners come back
    pcall(function()
        local brush = border.Background
        brush.DrawAs = 4   -- rounded-box drawing, which also draws the outline
        local o = brush.OutlineSettings
        o.RoundingType = 0
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

local function Fill(tree, color, name)
    local b = Construct("Border", tree, name)
    b:SetBrushColor(color)
    return b
end

local function Box(tree, w, h, child)
    local box = Construct("SizeBox", tree)
    if w then box:SetWidthOverride(w) end
    if h then box:SetHeightOverride(h) end
    if child then box:SetContent(child) end
    return box
end

local function Pad(slot, l, t, r, b)
    pcall(function() slot:SetPadding({ Left = l, Top = t, Right = r, Bottom = b }) end)
    return slot
end
local function Middle(slot) pcall(function() slot:SetVerticalAlignment(2) end) return slot end
local function Grow(slot) pcall(function() slot:SetSize({ SizeRule = 1, Value = 1.0 }) end) return slot end

local function GetHud()
    if Valid(ui.hudObj) then return ui.hudObj end
    local hud = nil
    pcall(function()
        local found = FindFirstOf("BP_InventoryHUD_C")
        if Valid(found) then hud = found end
    end)
    if not hud then return nil end
    local name = ""
    pcall(function() name = hud:GetFullName() end)
    if ui.hud ~= name then ui = { hud = name } end   -- new HUD (level load): build again
    ui.hudObj = hud
    return hud
end

-- The panel is named, so a restarted copy of this mod finds and removes the
-- one the previous copy left. The tag keeps the names of the copies apart:
-- reusing a name would replace the old widget in place, which the game
-- doesn't survive.
local PANEL_PREFIX = "ModHubPanel_"
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

local HINTS = {
    list = { { "UP / DOWN", "select" }, { "RIGHT / ENTER", "open" }, { "LEFT / BACKSPACE", "back" } },
    changelog = { { "UP / DOWN", "scroll" }, { "LEFT / RIGHT", "version" }, { "BACKSPACE", "back" } },
    settings = { { "UP / DOWN", "select" }, { "LEFT / RIGHT", "change" }, { "ENTER", "switch / default" }, { "BACKSPACE", "back" } },
}

local function SetHints(tree, p, which)
    pcall(function() p.hints:ClearChildren() end)
    for _, hint in ipairs(HINTS[which]) do
        local cap = Round(Fill(tree, CAP), 4, LINE)
        pcall(function() cap:SetPadding({ Left = 6, Top = 2, Right = 6, Bottom = 2 }) end)
        cap:SetContent(Text(tree, hint[1], 9, LABEL, true, 60))
        Middle(p.hints:AddChildToHorizontalBox(cap))
        Middle(Pad(p.hints:AddChildToHorizontalBox(Text(tree, hint[2], 10, MUTED)), 6, 0, 12, 0))
    end
    p.hintsFor = which
end

local function BuildPanel(hud)
    local tree = hud.WidgetTree
    panelCount = panelCount + 1
    local p = {}
    p.panel = Fill(tree, PANEL, PANEL_PREFIX .. panelTag .. "_" .. panelCount)
    Round(p.panel, 14, LINE)
    pcall(function() p.panel:SetPadding({ Left = 14, Top = 14, Right = 14, Bottom = 12 }) end)
    local width = Box(tree, WIDTH)
    p.panel:SetContent(width)
    local column = Construct("VerticalBox", tree)
    width:SetContent(column)

    -- header: tinted band with the accent bar, title in capitals
    local band = Fill(tree, BAND)
    pcall(function() band:SetPadding({ Left = 0, Top = 10, Right = 12, Bottom = 10 }) end)
    column:AddChildToVerticalBox(band)
    local head = Construct("HorizontalBox", tree)
    band:SetContent(head)
    Middle(head:AddChildToHorizontalBox(Box(tree, 3, 34, Fill(tree, ACCENT))))
    local titles = Construct("VerticalBox", tree)
    Middle(Grow(Pad(head:AddChildToHorizontalBox(titles), 12, 0, 0, 0)))
    p.title = Text(tree, "MODS", 17, BRIGHT, true, 120)
    titles:AddChildToVerticalBox(p.title)
    p.sub = Text(tree, "", 9, HEADING, true, 200)
    titles:AddChildToVerticalBox(p.sub)

    -- the body scrolls when it's taller than BODY_MAX
    p.body = Construct("VerticalBox", tree)
    local scrolls = pcall(function()
        local limit = Construct("SizeBox", tree)
        limit:SetMaxDesiredHeight(BODY_MAX)
        local scroll = Construct("ScrollBox", tree)
        pcall(function() scroll:SetScrollbarThickness({ X = 4, Y = 4 }) end)
        limit:SetContent(scroll)
        Pad(scroll:AddChild(p.body), 0, 0, SCROLLBAR, 0)
        column:AddChildToVerticalBox(limit)
        p.scroll = scroll
    end)
    if not scrolls then
        log("Scrolling unavailable - long pages may not fit the screen")
        pcall(function() p.body:RemoveFromParent() end)
        column:AddChildToVerticalBox(p.body)
    end

    local statusRow = Construct("HorizontalBox", tree)
    Pad(column:AddChildToVerticalBox(statusRow), 4, 14, 4, 0)
    p.dot = Round(Fill(tree, ACCENT))
    Middle(statusRow:AddChildToHorizontalBox(Box(tree, 8, 8, p.dot)))
    p.status = WrappedText(tree, "", 12, LABEL, WIDTH)
    Middle(Grow(Pad(statusRow:AddChildToHorizontalBox(p.status), 8, 0, 0, 0)))
    p.hints = Construct("HorizontalBox", tree)
    Pad(column:AddChildToVerticalBox(p.hints), 4, 10, 4, 0)
    SetHints(tree, p, "list")

    local root = hud.WidgetTree.RootWidget
    local cls = ""
    pcall(function() cls = root:GetClass():GetFName():ToString() end)
    if cls == "CanvasPanel" then
        local slot = root:AddChildToCanvas(p.panel)
        pcall(function() slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }) end)
        pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(103) end)
    elseif cls == "Overlay" then
        local slot = root:AddChildToOverlay(p.panel)
        pcall(function() slot:SetHorizontalAlignment(2) end)
        pcall(function() slot:SetVerticalAlignment(2) end)
    else
        error("the HUD's root is a " .. cls, 0)
    end
    return p
end

-- body helpers: a section heading and a card to put rows in
local function Section(tree, body, title)
    Pad(body:AddChildToVerticalBox(Text(tree, title, 9, HEADING, true, 200)), 6, 14, 0, 6)
    local frame = Round(Fill(tree, CARD), 10)
    pcall(function() frame:SetPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 }) end)
    body:AddChildToVerticalBox(frame)
    local card = Construct("VerticalBox", tree)
    frame:SetContent(card)
    return card
end

-- A row you can select: label, optional note on the right, chevron.
-- button = a centred button (Close / Back) instead of a list row.
local function ActionRow(tree, card, label, note, noteColor, action, button)
    local r = { action = action, button = button }
    r.bg = Round(Fill(tree, button and BUTTON or CLEAR), 8)
    pcall(function() r.bg:SetPadding({ Left = 12, Top = 0, Right = 12, Bottom = 0 }) end)
    local slot = card:AddChildToVerticalBox(r.bg)
    if button then Pad(slot, 0, 14, 0, 0) end
    local line = Construct("HorizontalBox", tree)
    r.bg:SetContent(Box(tree, nil, 36, line))
    if not button then
        r.marker = Fill(tree, CLEAR)
        Middle(Pad(line:AddChildToHorizontalBox(Box(tree, 3, 24, r.marker)), 0, 0, 10, 0))
    end
    r.label = Text(tree, label, 13, LABEL, button)
    local labelSlot = Middle(Grow(line:AddChildToHorizontalBox(r.label)))
    if button then pcall(function() labelSlot:SetHorizontalAlignment(2) end) end
    if note then
        Middle(Pad(line:AddChildToHorizontalBox(Text(tree, note, 11, noteColor or MUTED, true)), 8, 0, 0, 0))
    end
    if not button then
        r.chevron = Text(tree, "\u{203A}", 17, MUTED)
        Middle(Pad(line:AddChildToHorizontalBox(r.chevron), 10, 0, 0, 0))
    end
    table.insert(ui.rows, r)
    return r
end

-- A line of information: key cap (or command) and what it does
local function InfoRow(tree, card, key, what, width)
    local line = Construct("HorizontalBox", tree)
    Pad(card:AddChildToVerticalBox(line), 10, 5, 10, 5)
    local cap = Round(Fill(tree, CAP), 4, LINE)
    pcall(function() cap:SetPadding({ Left = 6, Top = 2, Right = 6, Bottom = 2 }) end)
    cap:SetContent(Text(tree, key, 10, WHITE, true))
    local capColumn = Construct("HorizontalBox", tree)
    Middle(capColumn:AddChildToHorizontalBox(cap))   -- the cap only as wide as its text
    Middle(line:AddChildToHorizontalBox(Box(tree, 170, nil, capColumn)))
    local t = WrappedText(tree, what, 12, LABEL, (width or (WIDTH - 8 - SCROLLBAR)) - 200)
    Middle(Grow(Pad(line:AddChildToHorizontalBox(t), 10, 0, 0, 0)))
end

local Close, Render

-- From the menu: show the result, unless the hub itself restarts (it closes first)
local function RunReload(which)
    hub.status = "Restarting..."
    Render()
    Reload(which, function() Close() end, function(msg, selfRestart)
        if selfRestart then return end
        hub.status = msg
        if hub.open then Render() end
    end, function(msg)
        hub.status = msg
        if hub.open then Render() end
    end)
end

local function ShowMod(name)
    return function() hub.view, hub.mod, hub.sel = "mod", name, 1; Render() end
end

local function ListView(tree, body)
    local mods = Loaded()
    SetText(ui.p.title, "MODS")
    SetText(ui.p.sub, #mods .. " LOADED")
    local card = Section(tree, body, "MODS")
    local changed, builtins = 0, {}
    for _, name in ipairs(mods) do
        if Builtin(name) then
            table.insert(builtins, name)
        else
            local info = INFO_BY_NAME[name]
            local isChanged = Changed(name)
            if isChanged then changed = changed + 1 end
            if isChanged then
                ActionRow(tree, card, info and info.title or name, "CHANGED", WARN, ShowMod(name))
            else
                -- mods whose page has a Settings button
                ActionRow(tree, card, info and info.title or name, Settings(name) and "SETTINGS" or nil, MUTED, ShowMod(name))
            end
        end
    end
    if #builtins > 0 then
        local ue = Section(tree, body, "UE4SS")
        for _, name in ipairs(builtins) do ActionRow(tree, ue, INFO_BY_NAME[name].title, nil, nil, ShowMod(name)) end
    end
    local tools = Section(tree, body, "RELOAD")
    ActionRow(tree, tools, "Restart changed mods", changed > 0 and tostring(changed) or "none",
        changed > 0 and WARN or MUTED, function() RunReload("changed") end)
    ActionRow(tree, body, "Close", nil, nil, function() Close() end, true)
end

local function ModView(tree, body)
    local name = hub.mod
    local info = INFO_BY_NAME[name] or { title = name, about = "No details for this mod." }
    SetText(ui.p.title, info.title:upper())
    SetText(ui.p.sub, name:upper() .. (Changed(name) and "  -  CHANGED SINCE IT LOADED" or ""))
    local about = WrappedText(tree, info.about or "", 12, LABEL, WIDTH - 8 - SCROLLBAR)
    Pad(body:AddChildToVerticalBox(about), 4, 10, 4, 0)
    if info.notes then
        local notes = WrappedText(tree, info.notes, 11, MUTED, WIDTH - 8 - SCROLLBAR)
        Pad(body:AddChildToVerticalBox(notes), 4, 4, 4, 0)
    end
    if info.keys then
        local card = Section(tree, body, "HOTKEYS")
        for _, k in ipairs(info.keys) do InfoRow(tree, card, k[1], k[2]) end
    end
    if info.commands then
        local card = Section(tree, body, "CONSOLE COMMANDS")
        for _, c in ipairs(info.commands) do InfoRow(tree, card, c[1], c[2]) end
    end
    local hasMenu, canRestart = info.menu ~= nil, not info.builtin
    local changes = Changelog(name)
    local settings = not info.builtin and Settings(name) or nil
    if hasMenu or canRestart or changes or settings then
        local actions = Section(tree, body, "ACTIONS")
        if hasMenu then
            ActionRow(tree, actions, info.menu[1], info.menu[2], MUTED, function()
                Close()
                -- a moment later, so the key that chose this doesn't also
                -- reach the other menu as it opens
                LoopAsync(300, function()
                    ExecuteInGameThread(function() RunCommand(info.menu[2]) end)
                    return true
                end)
            end)
        end
        if settings then
            ActionRow(tree, actions, "Settings", #settings .. (#settings == 1 and " SETTING" or " SETTINGS"), MUTED,
                function() hub.modSel, hub.view, hub.sel, hub.status = hub.sel, "settings", 1, nil; Render() end)
        end
        if changes then
            local latest = LatestVersion(changes)
            ActionRow(tree, actions, "Changelog", latest and ("v" .. latest:gsub("^[vV]", "")) or nil, MUTED,
                function() hub.modSel, hub.view, hub.page, hub.sel = hub.sel, "changelog", 1, 1; Render() end)
        end
        if canRestart then
            ActionRow(tree, actions, "Restart this mod", nil, nil, function() RunReload(name) end)
        end
    end
    ActionRow(tree, body, "Back", nil, nil, function() hub.view, hub.sel = "list", 1; Render() end, true)
end

-- A mod's changelog: one version per page, scrolled with Up/Down
local function ChangelogView(tree, body)
    local name = hub.mod
    local info = INFO_BY_NAME[name] or { title = name }
    local versions = Changelog(name) or { { title = "", lines = { { kind = "text", text = "This mod has no changelog." } } } }
    hub.page = math.max(1, math.min(hub.page or 1, #versions))
    local v = versions[hub.page]
    SetText(ui.p.title, info.title:upper())
    SetText(ui.p.sub, "CHANGELOG" .. (#versions > 1 and ("  -  " .. hub.page .. " OF " .. #versions) or ""))
    local column = Construct("VerticalBox", tree)
    Pad(body:AddChildToVerticalBox(column), 4, 4, 4, 0)
    local inner = WIDTH - 8 - SCROLLBAR

    if v.title ~= "" then
        local line = Construct("HorizontalBox", tree)
        Pad(column:AddChildToVerticalBox(line), 0, 6, 0, 2)
        Middle(line:AddChildToHorizontalBox(Box(tree, 3, 20, Fill(tree, ACCENT))))
        Middle(Pad(line:AddChildToHorizontalBox(Text(tree, v.title, 15, BRIGHT, true)), 10, 0, 0, 0))
    end
    for _, l in ipairs(v.lines) do
        if l.kind == "topic" then
            Pad(column:AddChildToVerticalBox(WrappedText(tree, l.text:upper(), 9, HEADING, inner - 13, true, 200)), 13, 12, 0, 4)
        elseif l.kind == "head" then
            Pad(column:AddChildToVerticalBox(WrappedText(tree, table.concat(l.cells, "  /  "):upper(), 9, MUTED, inner - 13, true, 120)),
                13, 6, 0, 2)
        elseif l.kind == "row" then
            if #l.cells >= 2 then
                local rest = {}
                for i = 2, #l.cells do if l.cells[i] ~= "" then table.insert(rest, l.cells[i]) end end
                InfoRow(tree, column, l.cells[1], table.concat(rest, "  -  "), inner)
            else
                Pad(column:AddChildToVerticalBox(WrappedText(tree, l.cells[1] or "", 11, LABEL, inner - 13)), 13, 2, 0, 2)
            end
        elseif l.kind == "code" then
            Pad(column:AddChildToVerticalBox(WrappedText(tree, l.text, 10, MUTED, inner - 26)), 26, 0, 0, 0)
        else
            local indent = l.kind == "item" and (l.level == 2 and 32 or 13) or 13
            local line = Construct("HorizontalBox", tree)
            Pad(column:AddChildToVerticalBox(line), indent, 2, 0, 2)
            local markWidth = 0
            if l.kind == "item" then
                markWidth = l.mark and 22 or 14
                local mark = Text(tree, l.mark or (l.level == 2 and "\u{2013}" or "\u{2022}"), 11, l.mark and HEADING or ACCENT, l.mark ~= nil)
                line:AddChildToHorizontalBox(Box(tree, markWidth, nil, mark))
            end
            Grow(line:AddChildToHorizontalBox(WrappedText(tree, l.text, 11, LABEL, inner - indent - markWidth)))
        end
    end
    local older, newer = versions[hub.page + 1], versions[hub.page - 1]
    local parts = {}
    if older then table.insert(parts, "RIGHT: " .. (older.title:match("^(%S+)") or "older")) end
    if newer then table.insert(parts, "LEFT: " .. (newer.title:match("^(%S+)") or "newer")) end
    return #parts > 0 and table.concat(parts, "   ") or "This is the only version"
end

-- A mod's config.lua settings: Left/Right change the chosen one (saved
-- straight away), Enter switches it or puts the default back
local function SettingsView(tree, body)
    local name = hub.mod
    local info = INFO_BY_NAME[name] or { title = name }
    local list = Settings(name) or {}
    local values, problem = UserValues(name)
    SetText(ui.p.title, info.title:upper())
    SetText(ui.p.sub, "SETTINGS")
    local inner = WIDTH - 8 - SCROLLBAR
    local card = Section(tree, body, "CONFIG.LUA")
    for _, s in ipairs(list) do
        if s.about then
            Pad(card:AddChildToVerticalBox(WrappedText(tree, s.about, 11, MUTED, inner - 30)), 15, 10, 4, 2)
        end
        local value = values and values[s.key]
        if value == nil then value = s.default end
        local isDefault = value == s.default
        local r = ActionRow(tree, card, Humanize(s.key), Shown(s, value), isDefault and LABEL or ACCENT, function()
            local new
            if s.kind == "bool" then
                new = not value
            elseif s.allowFalse and value ~= false then
                new = false
            else
                new = s.default
            end
            hub.change(s, new)
        end)
        r.setting, r.value = s, value
    end
    ActionRow(tree, body, "Restart " .. info.title .. " to use them", nil, nil, function() RunReload(name) end)
    ActionRow(tree, body, "Back", nil, nil, function() hub.view, hub.sel = "mod", hub.modSel or 1; Render() end, true)
    if problem then
        -- more important than what was just changed
        hub.status = "Your config.lua has a mistake (" .. problem .. "); the mod uses its defaults"
    end
    return "Saved to config.lua as you change them. Highlighted values differ from the default"
end

-- Saves one setting and shows the page again
hub.change = function(s, value)
    if SaveSetting(hub.mod, s, value) then
        hub.status = Humanize(s.key) .. ": " .. Shown(s, value) .. " - restart the mod to use it"
    else
        hub.status = "Couldn't write " .. ConfigPath(hub.mod)
    end
    Render()
end

local function Recolor()
    local chosen = ui.rows and ui.rows[hub.sel]
    if chosen and ui.p and ui.p.scroll then
        pcall(function() ui.p.scroll:ScrollWidgetIntoView(chosen.bg, false, 0, 0) end)
    end
    for i, r in ipairs(ui.rows or {}) do
        local lit = i == hub.sel
        if r.button then
            pcall(function() r.bg:SetBrushColor(lit and ACCENT or BUTTON) end)
            Color(r.label, lit and INK or WHITE)
        else
            pcall(function() r.bg:SetBrushColor(lit and ROW_LIT or CLEAR) end)
            pcall(function() r.marker:SetBrushColor(lit and ACCENT or CLEAR) end)
            Color(r.label, lit and BRIGHT or LABEL)
            if r.chevron then Color(r.chevron, lit and ACCENT or MUTED) end
        end
    end
end

-- Game thread. Builds the panel on the current HUD if needed and fills it.
Render = function()
    local hud = GetHud()
    if not hud then return false end
    RemoveLeftovers()
    if not (ui.p and Valid(ui.p.panel)) then
        local ok, p = pcall(BuildPanel, hud)
        if not ok then
            log("Menu unavailable (" .. tostring(p) .. ") - .reloadmods still works")
            return false
        end
        ui.p = p
    end
    local tree = hud.WidgetTree
    pcall(function() ui.p.body:ClearChildren() end)
    ui.rows = {}
    local hints = HINTS[hub.view] and hub.view or "list"
    if ui.p.hintsFor ~= hints then SetHints(tree, ui.p, hints) end
    local viewStatus = nil
    local ok, err = pcall(function()
        if hub.view == "changelog" then
            viewStatus = ChangelogView(tree, ui.p.body)
        elseif hub.view == "settings" then
            viewStatus = SettingsView(tree, ui.p.body)
        elseif hub.view == "mod" then
            ModView(tree, ui.p.body)
        else
            ListView(tree, ui.p.body)
        end
    end)
    if not ok then log("Menu problem: " .. tostring(err)) end
    hub.sel = math.max(1, math.min(hub.sel, #ui.rows))
    SetText(ui.p.status, Wrap(hub.status or viewStatus or "Mods with their own menu can be opened from their page", WIDTH - 24, 12))
    pcall(function() ui.p.dot:SetBrushColor(hub.status and ACCENT or MUTED) end)
    if ui.p.scroll then pcall(function() ui.p.scroll:SetScrollOffset(0) end) end
    Recolor()
    pcall(function() ui.p.panel:SetVisibility(VISIBLE) end)
    return true
end

Close = function()
    hub.open = false
    if ui.p then pcall(function() ui.p.panel:SetVisibility(COLLAPSED) end) end
end

local function Open()
    hub.open, hub.view, hub.sel, hub.status = true, "list", 1, nil
    hub.openedAt = os.clock()
    if not Render() then
        hub.open = false
        log("The mod menu needs the in-game HUD - load into a world first. Loaded mods: "
            .. table.concat(Loaded(), ", "))
    end
end

-- Changelog pages: Up/Down move the text
local function Scroll(dir)
    local scroll = ui.p and ui.p.scroll
    if not scroll then return end
    local offset, finish = 0, nil
    pcall(function() offset = scroll:GetScrollOffset() end)
    pcall(function() finish = scroll:GetScrollOffsetOfEnd() end)
    offset = math.max(0, (tonumber(offset) or 0) + dir * SCROLL_STEP)
    if type(finish) == "number" then offset = math.min(offset, finish) end
    pcall(function() scroll:SetScrollOffset(offset) end)
end

local function MenuKey(action)
    if not hub.open then return end
    -- the Enter that ran .mods in the console isn't a choice in the menu
    if os.clock() - hub.openedAt < 0.35 then return end
    ExecuteInGameThread(function()
        if not hub.open or not ui.rows then return end
        -- Backspace: one level back (changelog / settings -> mod page -> list), closes from the list
        if action == "backspace" then
            if hub.view == "changelog" or hub.view == "settings" then
                hub.view, hub.sel, hub.status = "mod", hub.modSel or 1, nil
                Render()
            elseif hub.view == "mod" then
                hub.view, hub.sel, hub.status = "list", 1, nil
                Render()
            else
                Close()
            end
            return
        end
        if hub.view == "changelog" then
            -- Up/Down scroll, Right older version, Left newer (or back), Enter back
            if action == "up" then
                Scroll(-1)
            elseif action == "down" then
                Scroll(1)
            elseif action == "right" then
                hub.page = (hub.page or 1) + 1   -- Render stops at the oldest
                Render()
            elseif action == "back" and (hub.page or 1) > 1 then
                hub.page = hub.page - 1
                Render()
            else
                hub.view, hub.sel = "mod", hub.modSel or 1
                Render()
            end
            return
        end
        local n = #ui.rows
        if n == 0 then return end
        local row = ui.rows[hub.sel]
        if hub.view == "settings" and row and row.setting and (action == "back" or action == "right") then
            -- from what config.lua says now (it may have been edited meanwhile)
            local s, value = row.setting, row.value
            local values = UserValues(hub.mod)
            if values then
                value = values[s.key]
                if value == nil then value = s.default end
            end
            hub.change(s, Step(s, value, action == "right" and 1 or -1))
            return
        end
        if action == "up" then
            hub.sel = (hub.sel - 2) % n + 1
            Recolor()
        elseif action == "down" then
            hub.sel = hub.sel % n + 1
            Recolor()
        elseif action == "back" then
            if hub.view == "mod" then
                hub.view, hub.sel = "list", 1
                Render()
            elseif hub.view == "settings" then
                hub.view, hub.sel, hub.status = "mod", hub.modSel or 1, nil
                Render()
            end
        elseif action == "right" and hub.view == "settings" then
            return   -- Right on Restart / Back: nothing to change
        else
            local row = ui.rows[hub.sel]
            if row and row.action then row.action() end
        end
    end)
end

for keyName, action in pairs({ UP_ARROW = "up", DOWN_ARROW = "down", RIGHT_ARROW = "right",
                               RETURN = "enter", LEFT_ARROW = "back", BACKSPACE = "backspace" }) do
    pcall(function() RegisterKeyBind(Key[keyName], function() MenuKey(action) end) end)
end

-- PageUp opens / closes the hub, like .mods (the Mod Menu used to bind it)
pcall(function()
    RegisterKeyBind(Key.PAGE_UP, function()
        ExecuteInGameThread(function()
            if hub.open then Close() else Open() end
        end)
    end)
end)

RegisterConsoleCommandHandler(".mods", function()
    ExecuteInGameThread(function()
        if hub.open then Close() else Open() end
    end)
    return true
end)

RegisterConsoleCommandHandler(".reloadmods", function(FullCommand, Parameters)
    local arg = (Parameters and Parameters[1]) or ""
    if arg:lower() == "all" then
        -- restarting every mod at once isn't offered: the changed ones, or one by one
        log("No 'all' any more: .reloadmods restarts the mods you've changed, .reloadmods <Name> one mod")
        return true
    end
    Reload(arg == "" and "changed" or arg, function() Close() end)
    return true
end)

log("Loaded. .mods opens the mod menu; .reloadmods restarts mods you've changed")
