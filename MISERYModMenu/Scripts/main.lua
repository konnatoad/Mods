--[[
    MISERY Mod Menu v4.6.23 (patched for current game version)

    Cheats auto-enable on game start!

    GOD MODE:
      .instaheal (.ih) - auto-heal all stats every 0.5s
      .infstam         - infinite stamina

    WORLD CONTROL:
      .time <hour>     - set time (0-24)
      .weather <type>  - sunny/rain/thunder
      .season <type>   - spring/summer/autumn/winter
      .slomo [x]       - slow motion
      .freeze          - freeze time

    TELEPORT:
      .tp              - teleport to crosshair
      .savepos         - save current position
      .loadpos         - teleport to saved position

    SPAWN:
      .spawn <item>    - fuzzy item spawn
      .enemy <type>    - fuzzy enemy spawn
      .summon <class>  - exact class spawn

    STATS:
      .heal .stamina .feed .drink .radcure .sanitycure

    KEYBINDS:
      .bind <key> <cmd> [amt]
      .unbind <key>
      .binds

    HOTKEYS: F1-F7 (quick stats); .menu opens the cheat menu

    Type .help or .cheats for full command list
]]

-- ============================================================
-- COMPATIBILITY LAYER - Validates APIs before use
-- ============================================================

-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("MISERYModMenu")

local function Log(msg)
    local ok = pcall(function()
        print("[ModMenu] " .. tostring(msg) .. "\n")
    end)
    if not ok then
        -- Fallback if print fails
        pcall(function() io.write("[ModMenu] " .. tostring(msg) .. "\n") end)
    end
end

-- Track initialization errors for user feedback
local InitErrors = {}

-- Validate that a global function exists
local function ValidateAPI(name)
    local exists = type(_G[name]) == "function"
    if not exists then
        table.insert(InitErrors, "Missing API: " .. name)
    end
    return exists
end

-- Check critical UE4SS APIs
local HAS_RegisterKeyBindAsync = ValidateAPI("RegisterKeyBindAsync")
local HAS_RegisterConsoleCommandHandler = ValidateAPI("RegisterConsoleCommandHandler")
local HAS_ExecuteInGameThread = ValidateAPI("ExecuteInGameThread")
local HAS_ForEachUObject = ValidateAPI("ForEachUObject")
local HAS_FindAllOf = ValidateAPI("FindAllOf")
local HAS_LoopAsync = ValidateAPI("LoopAsync")
local HAS_NotifyOnNewObject = ValidateAPI("NotifyOnNewObject")
local HAS_ExecuteConsoleCommand = ValidateAPI("ExecuteConsoleCommand")

-- Wrapper for keybind registration with error handling
local function SafeRegisterKeyBind(keyEnum, modifiers, callback, keyName)
    if not HAS_RegisterKeyBindAsync then
        table.insert(InitErrors, "Cannot bind " .. (keyName or "key") .. ": RegisterKeyBindAsync not available")
        return false
    end

    if keyEnum == nil then
        table.insert(InitErrors, "Cannot bind " .. (keyName or "key") .. ": Key enum value is nil")
        return false
    end

    local ok, err = pcall(function()
        RegisterKeyBindAsync(keyEnum, modifiers or {}, callback)
    end)

    if not ok then
        table.insert(InitErrors, "Failed to bind " .. (keyName or "key") .. ": " .. tostring(err))
        return false
    end

    return true
end

-- Wrapper for console command registration with error handling
local function SafeRegisterCommand(cmdName, callback)
    if not HAS_RegisterConsoleCommandHandler then
        table.insert(InitErrors, "Cannot register command " .. cmdName .. ": API not available")
        return false
    end

    local ok, err = pcall(function()
        RegisterConsoleCommandHandler(cmdName, callback)
    end)

    if not ok then
        table.insert(InitErrors, "Failed to register " .. cmdName .. ": " .. tostring(err))
        return false
    end

    return true
end

-- ============================================================
-- CO-OP
-- ============================================================
-- In someone else's world the host's game owns the world and every player's
-- inventory and stats: a change made only in a joined player's game is undone
-- or never reaches anyone. So in someone else's world:
--   * world commands (time, weather, season, enemies, slow motion, ...) and
--     movement cheats are the host's: they're refused with a message
--   * items and stats (Spawn, .heal, .instaheal, .infstam, .god, ...) are asked
--     of the host's Mod Menu, which gives them to you (the host needs it too)
-- The same two messages Unreal always has as the Radiation Shield uses:
-- ServerNotifyLoadedWorld(FName "MMENU_...") to the host, ClientMessage
-- ("... #MM:ok") back, shown as a line in the player's console.
-- One table: the main chunk is close to Lua's 200-local limit.
local Coop = {
    allowJoined = true,   -- hosting: give items and stats to players who ask for them
    TAG = "MMENU",
    HOST_ONLY = {},       -- command -> why it's refused in someone else's world
    -- the inventory functions players may ask for, and how many numbers each takes
    STATS = { IncreaseHealth = 1, DecreaseHealth = 2, IncreaseStamina = 1, IncreaseHunger = 1,
              IncreaseThirst = 1, DecreaseRadiation = 1, DecreaseInsanity = 1 },
    MODES = { INSTAHEAL = "instaheal", INFSTAM = "infinite stamina", GOD = "god mode" },
    HEAL_ALL = { "IncreaseHealth", "IncreaseStamina", "IncreaseHunger", "IncreaseThirst",
                 "DecreaseRadiation", "DecreaseInsanity" },
    guests = {},          -- hosting: [controller] = { pc, INSTAHEAL, INFSTAM, GOD }
    told = {},            -- joined: [mode] = the controller the host was told it's on for
    askId = 0,
    answered = true,
    looping = false,
}
-- Your own settings go in MISERYModMenu\config.lua (start from
-- config.example.lua), not in this file, so `git pull` can always update it.
do
    local path = "./ue4ss/Mods/MISERYModMenu/config.lua"
    local file = io.open(path, "r")
    if file then
        file:close()
        local ok, user = pcall(dofile, path)
        if ok and type(user) == "table" then
            if type(user.allowJoined) == "boolean" then Coop.allowJoined = user.allowJoined end
            Coop.user = user   -- newLook / newLayout are read where the menu look is set up
        else
            Log("config.lua ignored: " .. (ok and "it doesn't return a table" or tostring(user)))
        end
    end
end
do
    local WORLD = "it changes the host's world, ask the host"
    local MOVE = "the host's game moves your character"
    local ITEMS = "use the .menu cheat menu's Spawn (the host's Mod Menu adds the item)"
    for _, c in ipairs({ ".time", ".ctset", ".weather", ".season", ".slomo", ".freeze", ".enemy", ".summon",
                         ".forcespawn", ".destroyall", ".destroypawns", ".damage_target", ".restartlevel" }) do
        Coop.HOST_ONLY[c] = WORLD
    end
    for _, c in ipairs({ ".ghost", ".noclip", ".tp", ".loadpos", ".size" }) do Coop.HOST_ONLY[c] = MOVE end
    for _, c in ipairs({ ".spawn", ".give", ".give2", ".giveme", ".givealt", ".addraw", ".inject",
                         ".fetchitem", ".pickup", ".dropitem", ".testcreate" }) do
        Coop.HOST_ONLY[c] = ITEMS
    end
end

function Coop.Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

function Coop.Key(obj)
    local ok, address = pcall(function() return obj:GetAddress() end)
    if ok and address then return address end
    return tostring(obj)
end

-- This game's own player controller
-- Kept once found: FindAllOf walks every object in the game, which the 10-a-
-- second stamina loop did on every tick. A new level makes it invalid, and
-- the next call looks again.
function Coop.Controller()
    if Coop.Valid(Coop.ctrl) then return Coop.ctrl end
    Coop.ctrl = nil
    pcall(function()
        for _, ctrl in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Coop.Valid(ctrl) and ctrl:IsLocalController() then Coop.ctrl = ctrl return end
        end
    end)
    return Coop.ctrl
end

-- In someone else's world (the host's game has authority over our controller)
function Coop.Joined()
    local ctrl = Coop.Controller()
    if not ctrl then return false end
    local ok, authority = pcall(function() return ctrl:HasAuthority() end)
    return ok and authority == false
end

-- Commands (and key bindings) that only the host may use. True = refused.
function Coop.Refuse(cmd)
    local why = Coop.HOST_ONLY[string.lower(tostring(cmd))]
    if not why or not Coop.Joined() then return false end
    Log(tostring(cmd) .. " doesn't work in someone else's world: " .. why)
    return true
end

function Coop.Text(param)
    local value = param
    pcall(function() value = param:get() end)
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    return ok and s or ""
end

-- Joined: ask the host's Mod Menu
function Coop.Send(command, what)
    local ctrl = Coop.Controller()
    local sent = ctrl ~= nil and pcall(function() ctrl:ServerNotifyLoadedWorld(FName(Coop.TAG .. "_" .. command)) end)
    Coop.askId = Coop.askId + 1
    local id = Coop.askId
    Coop.answered = false
    Log("Asking the host for " .. what)
    LoopAsync(3000, function()
        if Coop.askId == id and not Coop.answered then
            Log("No answer from the host" .. (sent and "" or " (couldn't send)")
                .. " - the host needs MISERYModMenu for items and stats in their world")
        end
        return true
    end)
    return sent
end

-- Joined: a mode (instaheal, ...) is on or off. Tells the host once per world.
function Coop.Mode(mode, on)
    local ctrl = Coop.Controller()
    local key = ctrl and Coop.Key(ctrl)
    if on then
        if Coop.told[mode] == key then return end
        Coop.told[mode] = key
    else
        if Coop.told[mode] == nil then return end
        Coop.told[mode] = nil
        if not Coop.Joined() then return end
    end
    Coop.Send(mode .. (on and "_ON" or "_OFF"), Coop.MODES[mode] .. (on and " on" or " off"))
end

-- ---------- hosting ----------

function Coop.Tell(pc, text, tag)
    pcall(function() pc:ClientMessage("[ModMenu] " .. text .. " #MM:" .. tag, FName("None"), 0.0) end)
end

function Coop.Name(pc)
    local name = "a player"
    pcall(function()
        local state = pc.PlayerState
        if Coop.Valid(state) then name = state:GetPlayerName():ToString() end
    end)
    return name
end

function Coop.Inventory(pc)
    local inv = nil
    pcall(function()
        local character = pc.Character
        if Coop.Valid(character) and Coop.Valid(character.PlayerInventory) then inv = character.PlayerInventory end
    end)
    return inv
end

function Coop.FullName(obj)
    local name = nil
    pcall(function() name = obj:GetFullName() end)
    return name
end

-- Instaheal and infinite stamina for players who asked, every 0.5 s while any is on
function Coop.StartGuestLoop()
    if Coop.looping then return end
    Coop.looping = true
    LoopAsync(500, function()
        local any = false
        for _, guest in pairs(Coop.guests) do
            if guest.INSTAHEAL or guest.INFSTAM then any = true end
        end
        if not any then
            Coop.looping = false
            return true
        end
        ExecuteInGameThread(function()
            for key, guest in pairs(Coop.guests) do
                if not Coop.Valid(guest.pc) then
                    Coop.guests[key] = nil   -- left the game
                else
                    local inv = Coop.Inventory(guest.pc)
                    if inv and guest.INSTAHEAL then
                        for _, fn in ipairs(Coop.HEAL_ALL) do pcall(function() inv[fn](inv, 9999) end) end
                    elseif inv and guest.INFSTAM then
                        pcall(function() inv["IncreaseStamina"](inv, 9999) end)
                    end
                end
            end
        end)
        return false
    end)
end

-- God mode for players who asked: called from the health hook for every
-- inventory that takes damage. True when it was such a player's.
function Coop.HealGuest(inv)
    local name = nil
    for key, guest in pairs(Coop.guests) do
        if guest.GOD then
            if not Coop.Valid(guest.pc) then
                Coop.guests[key] = nil   -- left the game
            else
                name = name or Coop.FullName(inv)
                local mine = Coop.Inventory(guest.pc)
                if name and mine and Coop.FullName(mine) == name then
                    pcall(function() inv["IncreaseHealth"](inv, 9999) end)
                    return true
                end
            end
        end
    end
    return false
end

-- A joined player's request, on the host
function Coop.OnHostMessage(selfParam, msgParam)
    local cmd, rest = Coop.Text(msgParam):match("^" .. Coop.TAG .. "_(%u+)_?(.*)$")
    if not cmd then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not Coop.Valid(pc) or Coop.Joined() then return end
    local isLocal = true
    pcall(function() isLocal = pc:IsLocalController() end)
    if isLocal then return end
    local who = Coop.Name(pc)
    -- out of the game's fly camera, back into their character: always allowed
    -- (a player stuck in it can't do anything else)
    if cmd == "UNFLY" then
        local ok = Coop.EndFlyCamera and Coop.EndFlyCamera(pc)
        Coop.Tell(pc, ok and "Back in your character" or "Couldn't find your character", ok and "ok" or "failed")
        Log("[Co-op] " .. who .. ": out of the fly camera" .. (ok and "" or " - failed (character not found)"))
        return
    end
    if not Coop.allowJoined then
        Coop.Tell(pc, "The host doesn't give items or stats to other players", "denied")
        Log("[Co-op] " .. who .. " asked for " .. cmd:lower() .. " - turned off (Coop.allowJoined)")
        return
    end
    local inv = Coop.Inventory(pc)
    if cmd == "GIVE" then
        local amount, row = rest:match("^(%d+)_([%w_]+)$")
        amount = math.min(tonumber(amount) or 0, 9999)
        local ok = row ~= nil and amount >= 1 and inv ~= nil and Coop.AddItem ~= nil and Coop.AddItem(row, amount, inv)
        if ok then
            Coop.Tell(pc, "Added " .. row .. " x" .. amount, "ok")
            Log("[Co-op] " .. who .. ": " .. row .. " x" .. amount)
        else
            Coop.Tell(pc, "Couldn't add " .. tostring(row), "failed")
            Log("[Co-op] " .. who .. ": couldn't add " .. tostring(row))
        end
    elseif cmd == "STAT" then
        local fn, amount = rest:match("^(%a+)_(%d+)$")
        local params = fn and Coop.STATS[fn]
        amount = tonumber(amount)
        local ok = params ~= nil and amount ~= nil and inv ~= nil and pcall(function()
            if params == 2 then inv[fn](inv, amount, 0) else inv[fn](inv, amount) end
        end)
        Coop.Tell(pc, ok and (fn .. " " .. amount) or "Couldn't change that", ok and "ok" or "failed")
        if ok then Log("[Co-op] " .. who .. ": " .. fn .. " " .. amount) end
    elseif Coop.MODES[cmd] then
        local on = rest == "ON"
        local key = Coop.Key(pc)
        local guest = Coop.guests[key] or {}
        guest.pc, guest[cmd] = pc, on
        -- nothing on any more: forgotten, so the health hook has nobody to check
        Coop.guests[key] = (guest.INSTAHEAL or guest.INFSTAM or guest.GOD) and guest or nil
        if cmd == "GOD" and on and Coop.InstallGodHooks then Coop.InstallGodHooks() end
        if on then Coop.StartGuestLoop() end
        Coop.Tell(pc, Coop.MODES[cmd]:upper() .. (on and ": ON" or ": OFF") .. " for you", "ok")
        Log("[Co-op] " .. who .. ": " .. Coop.MODES[cmd] .. (on and " on" or " off"))
    end
end

-- The host's answer, on a player who joined (the game shows the line itself)
function Coop.OnClientMessage(selfParam, textParam)
    if not Coop.Text(textParam):find("#MM:%a+%s*$") or not Coop.Joined() then return end
    Coop.answered = true
end

for path, fn in pairs({
    ["/Script/Engine.PlayerController:ServerNotifyLoadedWorld"] = function(...) Coop.OnHostMessage(...) end,
    ["/Script/Engine.PlayerController:ClientMessage"] = function(...) Coop.OnClientMessage(...) end,
}) do
    if not pcall(RegisterHook, path, fn) then Log("Co-op messages unavailable (" .. path .. ")") end
end

-- Wrap all RegisterConsoleCommandHandler callbacks to always return true
-- (and refuse the host's commands in someone else's world)
if RegisterConsoleCommandHandler then
    local _realRCCH = RegisterConsoleCommandHandler
    RegisterConsoleCommandHandler = function(cmd, callback)
        return _realRCCH(cmd, function(FullCommand, Parameters)
            if Coop.Refuse(cmd) then return true end
            local ok, err = pcall(callback, FullCommand, Parameters)
            if not ok then Log("CMD ERR [" .. tostring(cmd) .. "]: " .. tostring(err)) end
            return true
        end)
    end
end

-- Safe ExecuteInGameThread wrapper
local function SafeExecuteInGameThread(callback)
    if HAS_ExecuteInGameThread then
        local ok, err = pcall(function()
            ExecuteInGameThread(callback)
        end)
        if not ok then
            Log("ExecuteInGameThread error: " .. tostring(err))
        end
    else
        -- Fallback: try to execute directly
        local ok, err = pcall(callback)
        if not ok then
            Log("Direct execution error: " .. tostring(err))
        end
    end
end

local function GetPlayerController()
    local mine = Coop.Controller()   -- kept once found (no object walk per call)
    if mine then return mine end
    local ok, result = pcall(function()
        local ctrls = FindAllOf("BP_SGKController_C")
        if ctrls and #ctrls > 0 then
            -- Prefer the LOCAL controller (the one we actually play)
            for _, ctrl in ipairs(ctrls) do
                if ctrl:IsLocalController() then
                    return ctrl
                end
            end
            return ctrls[1]
        end
        return nil
    end)
    if ok and result then return result end
    return nil
end

local function GetInventory()
    local ok, result = pcall(function()
        -- 1. Pull inventory from our own local controller's character
        local ctrl = GetPlayerController()
        if ctrl and ctrl.Character and ctrl.Character.PlayerInventory then
            return ctrl.Character.PlayerInventory
        end

        -- 2. Fall back to a character possessed by a LOCAL controller
        -- (MULTIPLAYER: [1] of a blind FindAllOf can be a friend's character)
        for _, cls in ipairs({"BP_SGKMasterCharacter_C", "BP_MISERYCharacter_C"}) do
            local chars = FindAllOf(cls)
            if chars then
                for _, ch in ipairs(chars) do
                    local isLocal = false
                    pcall(function() isLocal = ch.Controller and ch.Controller:IsLocalController() end)
                    if isLocal and ch.PlayerInventory then return ch.PlayerInventory end
                end
                if #chars == 1 and chars[1].PlayerInventory then return chars[1].PlayerInventory end
            end
        end

        -- 3. Final fallback: only safe when exactly one inventory exists
        local invs = FindAllOf("BP_PlayerInventory_C")
        if invs and #invs == 1 then
            return invs[1]
        end
        return nil
    end)
    if ok and result then return result end
    return nil
end

local function ModifyStat(name, func, amount, paramCount)
    Log("--- " .. name .. " ---")
    if Coop.Joined() then
        return Coop.Send("STAT_" .. func .. "_" .. math.max(0, math.floor(tonumber(amount) or 0)), name)
    end
    local Inv = GetInventory()
    if not Inv then
        Log("No inventory!")
        return false
    end
    local ok = pcall(function()
        if paramCount == 2 then
            Inv[func](Inv, amount, 0)
        else
            Inv[func](Inv, amount)
        end
    end)
    Log(ok and "Done!" or "Failed!")
    return ok
end

-- Cheat menu toggle state
local cheatMenuVisible = false
-- Called (in the game thread) after the menu is shown; set in the ITEM MENU section
local OnCheatMenuShown = function() end

-- Custom keybind system
local customBindings = {}

-- Use forward slashes and relative path for cross-platform compatibility
local bindingsFile = "Mods/MISERYModMenu/bindings.txt"

-- Safe key getter - returns nil if key doesn't exist
local function SafeGetKey(keyTable, keyName)
    if type(keyTable) ~= "table" then return nil end
    local ok, val = pcall(function() return keyTable[keyName] end)
    if ok and val ~= nil then return val end
    return nil
end

-- Build KeyMap safely, handling missing Key enum values
local KeyMap = {}
local KeysAvailable = type(Key) == "table"

if KeysAvailable then
    -- Letters
    local letters = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
    for _, letter in ipairs(letters) do
        local val = SafeGetKey(Key, letter)
        if val then KeyMap[string.lower(letter)] = val end
    end

    -- Numbers - try multiple naming conventions
    local numNames = {
        ["0"] = {"ZERO", "NUM_0", "KEY_0"},
        ["1"] = {"ONE", "NUM_1", "KEY_1"},
        ["2"] = {"TWO", "NUM_2", "KEY_2"},
        ["3"] = {"THREE", "NUM_3", "KEY_3"},
        ["4"] = {"FOUR", "NUM_4", "KEY_4"},
        ["5"] = {"FIVE", "NUM_5", "KEY_5"},
        ["6"] = {"SIX", "NUM_6", "KEY_6"},
        ["7"] = {"SEVEN", "NUM_7", "KEY_7"},
        ["8"] = {"EIGHT", "NUM_8", "KEY_8"},
        ["9"] = {"NINE", "NUM_9", "KEY_9"},
    }
    for num, names in pairs(numNames) do
        for _, name in ipairs(names) do
            local val = SafeGetKey(Key, name)
            if val then
                KeyMap[num] = val
                break
            end
        end
    end

    -- Numpad - try multiple naming conventions
    local numpadNames = {
        ["num0"] = {"NUM_ZERO", "NUMPAD0", "NUMPAD_0"},
        ["num1"] = {"NUM_ONE", "NUMPAD1", "NUMPAD_1"},
        ["num2"] = {"NUM_TWO", "NUMPAD2", "NUMPAD_2"},
        ["num3"] = {"NUM_THREE", "NUMPAD3", "NUMPAD_3"},
        ["num4"] = {"NUM_FOUR", "NUMPAD4", "NUMPAD_4"},
        ["num5"] = {"NUM_FIVE", "NUMPAD5", "NUMPAD_5"},
        ["num6"] = {"NUM_SIX", "NUMPAD6", "NUMPAD_6"},
        ["num7"] = {"NUM_SEVEN", "NUMPAD7", "NUMPAD_7"},
        ["num8"] = {"NUM_EIGHT", "NUMPAD8", "NUMPAD_8"},
        ["num9"] = {"NUM_NINE", "NUMPAD9", "NUMPAD_9"},
    }
    for keyName, names in pairs(numpadNames) do
        for _, name in ipairs(names) do
            local val = SafeGetKey(Key, name)
            if val then
                KeyMap[keyName] = val
                break
            end
        end
    end

    -- Function keys
    for i = 1, 12 do
        local val = SafeGetKey(Key, "F" .. i)
        if val then KeyMap["f" .. i] = val end
    end

    -- Special keys - try multiple naming conventions
    local specialKeys = {
        ["ins"] = {"INS", "INSERT"},
        ["del"] = {"DEL", "DELETE"},
        ["home"] = {"HOME"},
        ["end"] = {"END"},
        ["pageup"] = {"PAGE_UP", "PAGEUP", "PRIOR"},
        ["pagedown"] = {"PAGE_DOWN", "PAGEDOWN", "NEXT"},
        ["up"] = {"UP", "ARROW_UP"},
        ["down"] = {"DOWN", "ARROW_DOWN"},
        ["left"] = {"LEFT", "ARROW_LEFT"},
        ["right"] = {"RIGHT", "ARROW_RIGHT"},
        ["space"] = {"SPACE", "SPACEBAR"},
        ["enter"] = {"ENTER", "RETURN"},
        ["tab"] = {"TAB"},
        ["escape"] = {"ESCAPE", "ESC"},
        ["backspace"] = {"BACKSPACE", "BACK"},
        ["minus"] = {"MINUS", "OEM_MINUS", "HYPHEN"},
        ["equals"] = {"EQUALS", "OEM_PLUS", "PLUS"},
    }
    for keyName, names in pairs(specialKeys) do
        for _, name in ipairs(names) do
            local val = SafeGetKey(Key, name)
            if val then
                KeyMap[keyName] = val
                break
            end
        end
    end
else
    table.insert(InitErrors, "Key enum table not found - keybinds will not work")
end

-- Count available keys for diagnostics
local keyCount = 0
for _ in pairs(KeyMap) do keyCount = keyCount + 1 end

-- ============================================================
-- COMMAND LIST - For better error messages
-- ============================================================

-- All valid commands (for "command not recognized" feedback)
local ValidCommands = {
    -- Stats
    ".heal", ".damage", ".stamina", ".feed", ".drink", ".radcure", ".sanitycure",
    -- God modes
    ".instaheal", ".ih", ".infstam", ".god", ".ghost", ".walk",
    -- World
    ".time", ".weather", ".season", ".slomo", ".freeze",
    -- Teleport
    ".tp", ".savepos", ".loadpos", ".debugcam", ".exitcam", ".restartlevel",
    -- Spawn
    ".enemy", ".spawn", ".summon", ".give", ".find", ".spawnmode",
    -- Combat
    ".damage_target", ".destroyall", ".destroypawns", ".size",
    -- Keybinds
    ".bind", ".unbind", ".binds",
    -- UI
    ".menu", ".cheat",
    -- Debug/Search
    ".search", ".classes", ".bp", ".player", ".inspect", ".invfuncs",
    ".items", ".itemids", ".finditem", ".findwi", ".findspawn",
    ".cheatfuncs", ".findfuncs", ".itemfuncs", ".debug", ".scanworld", ".dtrows",
    -- Utility
    ".help", ".cheats", ".diag", ".exec", ".enablecheats", ".cmfuncs", ".cacheitems", ".noclip",
}

-- Find similar commands for typo suggestions
local function FindSimilarCommands(input)
    input = string.lower(input)
    local suggestions = {}

    for _, cmd in ipairs(ValidCommands) do
        local cmdLower = string.lower(cmd)
        -- Check if input is substring of command or vice versa
        if string.find(cmdLower, input, 1, true) or string.find(input, string.sub(cmdLower, 2), 1, true) then
            table.insert(suggestions, cmd)
        -- Check first few characters match
        elseif string.sub(cmdLower, 1, #input) == input then
            table.insert(suggestions, cmd)
        -- Check Levenshtein-like similarity (simple version)
        elseif #input > 2 then
            local matches = 0
            for i = 1, math.min(#input, #cmdLower) do
                if string.sub(input, i, i) == string.sub(cmdLower, i, i) then
                    matches = matches + 1
                end
            end
            if matches >= #input * 0.5 then
                table.insert(suggestions, cmd)
            end
        end
    end

    -- Remove duplicates and limit to 5
    local seen = {}
    local unique = {}
    for _, cmd in ipairs(suggestions) do
        if not seen[cmd] then
            seen[cmd] = true
            table.insert(unique, cmd)
            if #unique >= 5 then break end
        end
    end

    return unique
end

-- Command handlers for custom binds
local CommandHandlers = {
    ["heal"] = function(amount)
        amount = tonumber(amount) or 100
        ModifyStat("Health +" .. amount, "IncreaseHealth", amount, 1)
    end,
    ["damage"] = function(amount)
        amount = tonumber(amount) or 25
        ModifyStat("Health -" .. amount, "DecreaseHealth", amount, 2)
    end,
    ["stamina"] = function(amount)
        amount = tonumber(amount) or 100
        ModifyStat("Stamina +" .. amount, "IncreaseStamina", amount, 1)
    end,
    ["feed"] = function(amount)
        amount = tonumber(amount) or 50
        ModifyStat("Hunger +" .. amount, "IncreaseHunger", amount, 1)
    end,
    ["drink"] = function(amount)
        amount = tonumber(amount) or 50
        ModifyStat("Thirst +" .. amount, "IncreaseThirst", amount, 1)
    end,
    ["radcure"] = function(amount)
        amount = tonumber(amount) or 50
        ModifyStat("Radiation -" .. amount, "DecreaseRadiation", amount, 1)
    end,
    ["sanitycure"] = function(amount)
        amount = tonumber(amount) or 50
        ModifyStat("Insanity -" .. amount, "DecreaseInsanity", amount, 1)
    end,
    ["maxstats"] = function()
        ModifyStat("Health +1000", "IncreaseHealth", 1000, 1)
        ModifyStat("Stamina +1000", "IncreaseStamina", 1000, 1)
        ModifyStat("Hunger +100", "IncreaseHunger", 100, 1)
        ModifyStat("Thirst +100", "IncreaseThirst", 100, 1)
        ModifyStat("Radiation -100", "DecreaseRadiation", 100, 1)
        ModifyStat("Insanity -100", "DecreaseInsanity", 100, 1)
    end,
}

-- Save bindings to file
local function SaveBindings()
    local file = io.open(bindingsFile, "w")
    if file then
        for keyName, binding in pairs(customBindings) do
            local line = keyName .. "=" .. binding.command
            if binding.arg then
                line = line .. "=" .. binding.arg
            end
            file:write(line .. "\n")
        end
        file:close()
        Log("Bindings saved!")
    else
        Log("Could not save bindings file")
    end
end

-- Load bindings from file
local function LoadBindings()
    -- Try multiple path formats for compatibility
    local paths = {
        bindingsFile,
        "Mods\\MISERYModMenu\\bindings.txt",
        "./Mods/MISERYModMenu/bindings.txt",
    }

    local file = nil
    for _, path in ipairs(paths) do
        file = io.open(path, "r")
        if file then break end
    end

    if not file then
        return -- No saved bindings
    end

    local count = 0
    local failed = 0
    for line in file:lines() do
        -- Skip empty lines and comments
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local parts = {}
            for part in string.gmatch(line, "[^=]+") do
                table.insert(parts, part)
            end

            local keyName = string.lower(parts[1] or "")
            local command = string.lower(parts[2] or "")
            local arg = parts[3]

            if keyName ~= "" and command ~= "" then
                local keyEnum = KeyMap[keyName]
                if keyEnum and CommandHandlers[command] then
                    customBindings[keyName] = { command = command, arg = arg }

                    -- Register the keybind using safe wrapper
                    local success = SafeRegisterKeyBind(keyEnum, {}, function()
                        SafeExecuteInGameThread(function()
                            local binding = customBindings[keyName]
                            if binding and CommandHandlers[binding.command] and (binding.command == "ghost" or not Coop.Refuse("." .. binding.command)) then
                                CommandHandlers[binding.command](binding.arg)
                            end
                        end)
                    end, keyName)

                    if success then
                        count = count + 1
                    else
                        failed = failed + 1
                    end
                elseif not keyEnum then
                    Log("Unknown key in bindings: " .. keyName)
                    failed = failed + 1
                elseif not CommandHandlers[command] then
                    Log("Unknown command in bindings: " .. command)
                    failed = failed + 1
                end
            end
        end
    end
    file:close()

    if count > 0 then
        Log("Loaded " .. count .. " custom binding(s)")
    end
    if failed > 0 then
        Log("Failed to load " .. failed .. " binding(s)")
    end
end

-- Helper to toggle cursor
local function SetCursorVisible(visible)
    -- Try to find and use the game controller
    local success = false
    pcall(function()
        local controllers = FindAllOf("BP_SGKController_C")
        if controllers and #controllers > 0 then
            local pc = controllers[1]
            if visible then
                -- Try calling SetShowMouseCursor function
                pcall(function() pc:SetShowMouseCursor(true) end)
                -- Try direct property
                pcall(function() pc.bShowMouseCursor = true end)
            else
                pcall(function() pc:SetShowMouseCursor(false) end)
                pcall(function() pc.bShowMouseCursor = false end)
            end
            success = true
        end
    end)
    return success
end

-- ============================================================
-- SCREEN SCALING HELPER - Fixes menu on different resolutions
-- ============================================================

-- Get current viewport/screen size
local function GetViewportSize()
    local width, height = 1920, 1080 -- Default fallback

    pcall(function()
        -- Try to get viewport size from game viewport client
        local gvpc = FindFirstOf("GameViewportClient")
        if gvpc then
            local size = nil
            pcall(function() size = gvpc:GetViewportSize() end)
            if size then
                width = size.X or width
                height = size.Y or height
            end
        end
    end)

    -- Fallback: try getting from player controller
    pcall(function()
        local pc = GetPlayerController()
        if pc then
            local sizeX, sizeY = nil, nil
            pcall(function()
                sizeX, sizeY = pc:GetViewportSize()
            end)
            if sizeX and sizeY then
                width = sizeX
                height = sizeY
            end
        end
    end)

    return width, height
end

-- Calculate scale factor for UI widgets based on screen resolution
local function GetUIScaleFactor()
    local width, height = GetViewportSize()

    -- Reference resolution (what the menu was designed for)
    local refWidth, refHeight = 1920, 1080

    -- Calculate scale factor (use smaller of width/height ratios)
    local scaleX = width / refWidth
    local scaleY = height / refHeight
    local scale = math.min(scaleX, scaleY)

    -- Clamp to reasonable values
    scale = math.max(0.5, math.min(scale, 2.0))

    return scale, width, height
end

-- Apply scaling and positioning to a widget for screen compatibility
local function ScaleWidgetForScreen(widget)
    if not widget then return false end

    local scale, screenW, screenH = GetUIScaleFactor()
    local success = false

    -- Method 1: Try SetRenderScale (UMG widgets)
    pcall(function()
        widget:SetRenderScale({X = scale, Y = scale})
        success = true
    end)

    -- Method 2: Try SetRenderTransform with scale
    pcall(function()
        local transform = {
            Translation = {X = 0, Y = 0},
            Scale = {X = scale, Y = scale},
            Shear = {X = 0, Y = 0},
            Angle = 0
        }
        widget:SetRenderTransform(transform)
        success = true
    end)

    -- Method 3: Try setting desired size in viewport (if available)
    pcall(function()
        -- For widgets that support anchoring
        widget:SetAnchorsInViewport({Minimum = {X = 0, Y = 0}, Maximum = {X = 1, Y = 1}})
    end)

    -- Method 4: Try to access the widget's slot and set anchors
    pcall(function()
        local slot = widget:GetSlot()
        if slot then
            slot:SetAnchors({Minimum = {X = 0.5, Y = 0.5}, Maximum = {X = 0.5, Y = 0.5}})
            slot:SetAlignment({X = 0.5, Y = 0.5})
        end
    end)

    -- Method 5: Force layout update
    pcall(function()
        widget:ForceLayoutPrepass()
    end)

    return success, scale
end

-- Get cheat menu widget via InventoryHUD property (WD_CheatMenu_C no longer standalone)
-- The HUD is kept while valid: finding it walks every object in the game,
-- which every opening did. A level load makes a new HUD; the next call looks again.
local function GetCheatMenuWidget()
    local cheatMenu = nil
    pcall(function()
        if not Coop.Valid(Coop.hud) then
            Coop.hud = nil
            local huds = FindAllOf("BP_InventoryHUD_C")
            if huds and #huds > 0 then Coop.hud = huds[1] end
        end
        if Coop.hud then cheatMenu = Coop.hud.CheatMenu end
    end)
    return cheatMenu
end

-- The cheat menu opens with .menu, or from the Mod Menu's page in the Mod Hub
-- (PageUp opens the Mod Hub now; the Mod Menu no longer binds it).

-- Backspace closes the cheat menu (it has one level, nothing to go back to).
-- Not while you're typing in one of its text boxes: there Backspace deletes.
-- The text boxes are looked up only when Backspace is pressed with the menu
-- open (FindAllOf walks every object in the game).
local function TypingInTextBox()
    local typing = false
    pcall(function()
        for _, className in ipairs({ "EditableTextBox", "EditableText", "MultiLineEditableTextBox" }) do
            for _, box in ipairs(FindAllOf(className) or {}) do
                if Coop.Valid(box) and box:HasKeyboardFocus() then typing = true return end
            end
        end
    end)
    return typing
end

local backspaceKey = KeyMap["backspace"]
if backspaceKey then
    SafeRegisterKeyBind(backspaceKey, {}, function()
        if not cheatMenuVisible then return end
        SafeExecuteInGameThread(function()
            if not cheatMenuVisible or TypingInTextBox() then return end
            local cheatMenu = GetCheatMenuWidget()
            cheatMenuVisible = false
            if cheatMenu then pcall(function() cheatMenu["SetVisibility"](cheatMenu, 1) end) end -- Collapsed
            SetCursorVisible(false)
            Log("Cheat Menu: HIDDEN (Backspace)")
        end)
    end, "Backspace")
end

-- Hotkeys - using safe registration with fallback
local hotkeys = {
    {key = "6", name = "6", func = function() ModifyStat("Health +100", "IncreaseHealth", 100, 1) end},
    {key = "7", name = "7", func = function() ModifyStat("Stamina +100", "IncreaseStamina", 100, 1) end},
    {key = "8", name = "8", func = function() ModifyStat("Hunger +50", "IncreaseHunger", 50, 1) end},
    {key = "9", name = "9", func = function() ModifyStat("Thirst +50", "IncreaseThirst", 50, 1) end},
    {key = "0", name = "0", func = function() ModifyStat("Radiation -50", "DecreaseRadiation", 50, 1) end},
    {key = "minus", name = "-", func = function() ModifyStat("Insanity -50", "DecreaseInsanity", 50, 1) end},
    {key = "equals", name = "=", func = function() ModifyStat("Health -25", "DecreaseHealth", 25, 2) end},
}

local boundHotkeys = 0
for _, hk in ipairs(hotkeys) do
    local keyEnum = KeyMap[hk.key]
    if keyEnum then
        local success = SafeRegisterKeyBind(keyEnum, {}, function()
            SafeExecuteInGameThread(hk.func)
        end, hk.name)
        if success then boundHotkeys = boundHotkeys + 1 end
    else
        table.insert(InitErrors, "Key " .. hk.name .. " not available")
    end
end

-- Ctrl+R hot reload
local rKey = KeyMap["r"]
local ctrlMod = nil
pcall(function()
    if ModifierKeys and ModifierKeys.Control then
        ctrlMod = ModifierKeys.Control
    end
end)

-- Only bind when the Ctrl modifier is actually available. Binding plain R
-- fires the (unavailable) reload on every R press in game — log spam, no use.
if rKey and ctrlMod then
    SafeRegisterKeyBind(rKey, {ctrlMod}, function()
        SafeExecuteInGameThread(function()
            Log("Hot reloading MISERYModMenu...")
            local ok = false
            pcall(function()
                if UE4SS and UE4SS.ReloadAllMods then
                    UE4SS.ReloadAllMods()
                    ok = true
                end
            end)
            if not ok then
                pcall(function()
                    if UE4SS and UE4SS.ReloadMod then
                        UE4SS.ReloadMod("MISERYModMenu")
                        ok = true
                    end
                end)
            end
            if not ok then
                Log("Reload API unavailable in this UE4SS build.")
                Log("Use UE4SS GUI > Mods tab to reload manually.")
            end
        end)
    end, "Ctrl+R")
elseif rKey then
    Log("Ctrl modifier unavailable - hot-reload hotkey disabled (use UE4SS GUI > Mods tab).")
end

-- Console commands with custom amounts (prefix: .)
-- Discovery/debug commands
RegisterConsoleCommandHandler(".search", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "item")
    Log("Searching for objects containing: " .. search)
    local found = {}
    local count = 0

    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(string.lower(name), search) then
            count = count + 1
            if count <= 20 then
                table.insert(found, name)
            end
        end
        return false -- continue iteration
    end)

    Log("Found " .. count .. " matching objects")
    for i, name in ipairs(found) do
        Log("  " .. name)
    end
    if count > 20 then
        Log("  ... and " .. (count - 20) .. " more")
    end
    return true
end)

RegisterConsoleCommandHandler(".classes", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "item")
    Log("Searching for CLASSES containing: " .. search)
    local classes = {}

    ForEachUObject(function(obj)
        local ok, className = pcall(function()
            return obj:GetClass():GetFullName()
        end)
        if ok and className and string.find(string.lower(className), search) then
            classes[className] = true
        end
        return false
    end)

    local count = 0
    for className, _ in pairs(classes) do
        count = count + 1
        if count <= 30 then
            Log("  " .. className)
        end
    end
    Log("Found " .. count .. " unique classes")
    return true
end)

-- Search for game blueprints only (filters out engine noise)
RegisterConsoleCommandHandler(".bp", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "")
    Log("Searching for BP_ classes" .. (search ~= "" and " containing: " .. search or ""))
    local classes = {}

    ForEachUObject(function(obj)
        local ok, className = pcall(function()
            return obj:GetClass():GetName()
        end)
        if ok and className and string.sub(className, 1, 3) == "BP_" then
            if search == "" or string.find(string.lower(className), search) then
                classes[className] = true
            end
        end
        return false
    end)

    local sorted = {}
    for className, _ in pairs(classes) do
        table.insert(sorted, className)
    end
    table.sort(sorted)

    for i, className in ipairs(sorted) do
        if i <= 50 then
            Log("  " .. className)
        end
    end
    Log("Found " .. #sorted .. " BP_ classes")
    return true
end)

-- Dump player component info
RegisterConsoleCommandHandler(".player", function(FullCommand, Parameters)
    Log("Searching for player-related objects...")
    ExecuteInGameThread(function()
        local classes = {}
        ForEachUObject(function(obj)
            local ok, className = pcall(function()
                return obj:GetClass():GetName()
            end)
            if ok and className then
                local lower = string.lower(className)
                if string.find(lower, "player") or string.find(lower, "character") then
                    classes[className] = true
                end
            end
            return false
        end)

        local sorted = {}
        for className, _ in pairs(classes) do
            table.insert(sorted, className)
        end
        table.sort(sorted)

        for i, className in ipairs(sorted) do
            if i <= 40 then
                Log("  " .. className)
            end
        end
        Log("Found " .. #sorted .. " player/character classes")
    end)
    return true
end)

-- Inspect a specific class's functions
RegisterConsoleCommandHandler(".inspect", function(FullCommand, Parameters)
    local className = Parameters[1]
    if not className then
        Log("Usage: .inspect ClassName")
        Log("Example: .inspect BP_PlayerInventory_C")
        return true
    end
    Log("Inspecting class: " .. className)
    ExecuteInGameThread(function()
        local objs = FindAllOf(className)
        if not objs or #objs == 0 then
            Log("No instances of " .. className .. " found!")
            return
        end
        local obj = objs[1]
        Log("Found " .. #objs .. " instance(s)")

        local ok, err = pcall(function()
            Log("--- Properties ---")
            local propCount = 0
            for prop in obj:GetClass():Properties() do
                propCount = propCount + 1
                if propCount <= 50 then
                    Log("  " .. prop:GetName())
                end
            end
            if propCount > 50 then
                Log("  ... and " .. (propCount - 50) .. " more properties")
            end

            Log("--- Functions ---")
            local funcCount = 0
            for func in obj:GetClass():Functions() do
                funcCount = funcCount + 1
                if funcCount <= 50 then
                    Log("  " .. func:GetName())
                end
            end
            if funcCount > 50 then
                Log("  ... and " .. (funcCount - 50) .. " more functions")
            end
        end)

        if not ok then
            Log("Error: " .. tostring(err))
        end
    end)
    return true
end)

RegisterConsoleCommandHandler(".invfuncs", function(FullCommand, Parameters)
    local filter = Parameters[1] or "PlayerInventory"
    Log("UFunctions matching: " .. filter)
    local count = 0
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(name, "^Function") and string.find(name, filter, 1, true) then
            Log("  " .. name)
            count = count + 1
        end
        return false
    end)
    Log("Total: " .. count)
    return true
end)

SafeRegisterCommand(".help", function(FullCommand, Parameters)
    Log("=== MISERY Mod Menu v4.6.23 ===")
    Log("")
    Log("Cheats auto-enable on game start!")
    Log("")
    Log("GOD MODE:")
    Log("  .instaheal (.ih) - auto-heal all stats")
    Log("  .infstam         - infinite stamina")
    Log("")
    Log("WORLD CONTROL:")
    Log("  .time <hour>     - set time (0-24)")
    Log("  .weather <type>  - sunny/rain/thunder")
    Log("  .season <type>   - spring/summer/autumn/winter")
    Log("  .slomo [x]       - slow motion")
    Log("  .freeze          - freeze time")
    Log("")
    Log("TELEPORT:")
    Log("  .tp              - teleport to crosshair")
    Log("  .savepos         - save current position")
    Log("  .loadpos         - teleport to saved pos")
    Log("  .debugcam        - free camera")
    Log("")
    Log("SPAWN:")
    Log("  .enemy <type>    - spawn enemies")
    Log("  .summon <class>  - spawn by class")
    Log("  .menu            - DEV MENU (items)")
    Log("  .find <name>     - search the menu's item list")
    Log("  .spawnmode       - how the Spawn button adds items")
    Log("")
    Log("STATS: .heal .stamina .feed .drink")
    Log("       .radcure .sanitycure")
    Log("")
    Log("KEYBINDS: .bind .unbind .binds")
    Log("HOTKEYS: F1-F7 (quick stats)")
    Log("")
    Log("TROUBLESHOOTING:")
    Log("  .diag  - Show diagnostics")
    Log("")
    Log("More: .cheats .enemy")
    return true
end)

RegisterConsoleCommandHandler(".heal", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 100
    ExecuteInGameThread(function() ModifyStat("Health +" .. amount, "IncreaseHealth", amount, 1) end)
    return true
end)
RegisterConsoleCommandHandler(".damage", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 25
    ExecuteInGameThread(function() ModifyStat("Health -" .. amount, "DecreaseHealth", amount, 2) end)
    return true
end)
RegisterConsoleCommandHandler(".stamina", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 100
    ExecuteInGameThread(function() ModifyStat("Stamina +" .. amount, "IncreaseStamina", amount, 1) end)
    return true
end)
RegisterConsoleCommandHandler(".feed", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 50
    ExecuteInGameThread(function() ModifyStat("Hunger +" .. amount, "IncreaseHunger", amount, 1) end)
    return true
end)
RegisterConsoleCommandHandler(".drink", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 50
    ExecuteInGameThread(function() ModifyStat("Thirst +" .. amount, "IncreaseThirst", amount, 1) end)
    return true
end)
RegisterConsoleCommandHandler(".radcure", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 50
    ExecuteInGameThread(function() ModifyStat("Radiation -" .. amount, "DecreaseRadiation", amount, 1) end)
    return true
end)
RegisterConsoleCommandHandler(".sanitycure", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 50
    ExecuteInGameThread(function() ModifyStat("Insanity -" .. amount, "DecreaseInsanity", amount, 1) end)
    return true
end)

-- Custom keybind commands
RegisterConsoleCommandHandler(".bind", function(FullCommand, Parameters)
    local keyName = string.lower(Parameters[1] or "")
    local command = string.lower(Parameters[2] or "")
    local arg = Parameters[3]

    if keyName == "" or command == "" then
        Log("Usage: .bind <key> <command> [arg]")
        Log("Example: .bind num1 instaheal")
        Log("Example: .bind num2 heal 500")
        Log("Example: .bind num3 time 12")
        Log("")
        Log("Keys: a-z, 0-9, num0-num9, f1-f12")
        Log("      ins, del, home, end, pageup, pagedown")
        Log("")
        Log("STATS: heal, damage, stamina, feed,")
        Log("  drink, radcure, sanitycure, maxstats")
        Log("")
        Log("CHEATS: instaheal, infstam, god, ghost,")
        Log("  walk, tp, slomo, freeze, debugcam")
        Log("")
        Log("WORLD: time, destroypawns")
        Log("TELEPORT: savepos, loadpos")
        return true
    end

    local keyEnum = KeyMap[keyName]
    if not keyEnum then
        Log("Unknown key: " .. keyName)
        Log("Use: a-z, 0-9, num0-num9, f1-f12, etc.")
        return true
    end

    if not CommandHandlers[command] then
        Log("Unknown command: " .. command)
        Log("Use .bind to see all available commands")
        return true
    end

    -- Store the binding
    customBindings[keyName] = { command = command, arg = arg }

    -- Register the keybind
    RegisterKeyBindAsync(keyEnum, {}, function()
        ExecuteInGameThread(function()
            local binding = customBindings[keyName]
            if binding and CommandHandlers[binding.command] and (binding.command == "ghost" or not Coop.Refuse("." .. binding.command)) then
                CommandHandlers[binding.command](binding.arg)
            end
        end)
    end)

    if arg then
        Log("Bound " .. string.upper(keyName) .. " to " .. command .. " " .. arg)
    else
        Log("Bound " .. string.upper(keyName) .. " to " .. command)
    end
    SaveBindings()
    return true
end)

RegisterConsoleCommandHandler(".unbind", function(FullCommand, Parameters)
    local keyName = string.lower(Parameters[1] or "")

    if keyName == "" then
        Log("Usage: .unbind <key>")
        Log("Example: .unbind e")
        return true
    end

    if customBindings[keyName] then
        customBindings[keyName] = nil
        Log("Unbound " .. string.upper(keyName))
        SaveBindings()
    else
        Log("No custom binding for " .. string.upper(keyName))
    end
    return true
end)

RegisterConsoleCommandHandler(".binds", function(FullCommand, Parameters)
    Log("=== Custom Keybindings ===")
    local count = 0
    for keyName, binding in pairs(customBindings) do
        count = count + 1
        if binding.arg then
            Log("  " .. string.upper(keyName) .. " = " .. binding.command .. " " .. binding.arg)
        else
            Log("  " .. string.upper(keyName) .. " = " .. binding.command)
        end
    end
    if count == 0 then
        Log("  No custom bindings set")
        Log("  Use: .bind <key> <command> [amount]")
    end
    Log("==========================")
    return true
end)

-- Search for item-related functions
RegisterConsoleCommandHandler(".itemfuncs", function(FullCommand, Parameters)
    Log("Searching for item-related functions...")
    local funcs = {}
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            local lower = string.lower(name)
            if string.find(name, "^Function") and
               (string.find(lower, "item") or string.find(lower, "inventory") or string.find(lower, "pickup")) and
               string.find(lower, "survivalgamekit") then
                funcs[name] = true
            end
        end
        return false
    end)

    local sorted = {}
    for name, _ in pairs(funcs) do
        table.insert(sorted, name)
    end
    table.sort(sorted)

    for i, name in ipairs(sorted) do
        if i <= 50 then
            Log("  " .. name)
        end
    end
    Log("Found " .. #sorted .. " item/inventory functions")
    return true
end)

-- List available items
RegisterConsoleCommandHandler(".items", function(FullCommand, Parameters)
    local filter = string.lower(Parameters[1] or "")
    Log("Searching for item classes...")
    local items = {}

    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            -- Look for BlueprintGeneratedClass in the Items folder
            if string.find(name, "BlueprintGeneratedClass") and
               string.find(name, "/Items/") and
               string.find(name, "BP_") then
                -- Extract just the class name
                local className = string.match(name, "(BP_[%w_]+)_C$")
                if className and (filter == "" or string.find(string.lower(className), filter)) then
                    items[className] = true
                end
            end
        end
        return false
    end)

    local sorted = {}
    for name, _ in pairs(items) do
        table.insert(sorted, name)
    end
    table.sort(sorted)

    for i, name in ipairs(sorted) do
        if i <= 60 then
            Log("  " .. name)
        end
    end
    if #sorted > 60 then
        Log("  ... and " .. (#sorted - 60) .. " more")
    end
    Log("Found " .. #sorted .. " items (use: .give ItemName)")
    return true
end)

-- MULTIPLAYER: always resolve the LOCAL player. On a host, FindAllOf returns
-- every connected player's controller/character — [1] can be a friend.
local function GetPlayerController()
    local mine = Coop.Controller()   -- kept once found (no object walk per call)
    if mine then return mine end
    local ok, result = pcall(function()
        local ctrls = FindAllOf("BP_SGKController_C")
        if ctrls and #ctrls > 0 then
            for _, ctrl in ipairs(ctrls) do
                if ctrl:IsLocalController() then
                    return ctrl
                end
            end
            return ctrls[1]
        end
        return nil
    end)
    if ok and result then return result end
    return nil
end

local function GetPlayerCharacter()
    local ok, result = pcall(function()
        -- 1. The local controller's own character
        local ctrl = GetPlayerController()
        if ctrl and ctrl.Character and ctrl.Character:IsValid() then
            return ctrl.Character
        end

        -- 2. Scan characters, keep only one possessed by a local controller
        for _, cls in ipairs({"BP_SGKMasterCharacter_C", "BP_MISERYCharacter_C"}) do
            local chars = FindAllOf(cls)
            if chars then
                for _, ch in ipairs(chars) do
                    local isLocal = false
                    pcall(function() isLocal = ch.Controller and ch.Controller:IsLocalController() end)
                    if isLocal then return ch end
                end
                -- Single-player style fallback: only safe when exactly one exists
                if #chars == 1 then return chars[1] end
            end
        end
        return nil
    end)
    if ok and result then return result end
    return nil
end

-- Search for item data tables and row names
RegisterConsoleCommandHandler(".itemids", function(FullCommand, Parameters)
    local filter = string.lower(Parameters[1] or "")
    Log("Searching for item data tables and IDs...")
    local tables = {}
    local rows = {}

    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            local lower = string.lower(name)
            -- Look for DataTable objects with item-related names
            if string.find(name, "DataTable") and
               (string.find(lower, "item") or string.find(lower, "inventory") or string.find(lower, "loot")) then
                tables[name] = true
            end
            -- Look for row struct instances
            if string.find(lower, "itemdata") or string.find(lower, "itemrow") then
                if filter == "" or string.find(lower, filter) then
                    rows[name] = true
                end
            end
        end
        return false
    end)

    Log("--- Data Tables ---")
    for name, _ in pairs(tables) do
        Log("  " .. name)
    end

    if next(rows) then
        Log("--- Item Rows ---")
        local count = 0
        for name, _ in pairs(rows) do
            count = count + 1
            if count <= 30 then
                Log("  " .. name)
            end
        end
    end

    return true
end)

-- Debug: find all spawn/give/add related functions in the game
RegisterConsoleCommandHandler(".findfuncs", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "spawn")
    Log("Searching for functions containing: " .. search)
    ExecuteInGameThread(function()
        local funcs = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name and string.find(name, "^Function") then
                if string.find(string.lower(name), search) then
                    funcs[name] = true
                end
            end
            return false
        end)

        local sorted = {}
        for name, _ in pairs(funcs) do
            table.insert(sorted, name)
        end
        table.sort(sorted)

        for i, name in ipairs(sorted) do
            if i <= 30 then
                Log("  " .. name)
            end
        end
        Log("Found " .. #sorted .. " functions")
    end)
    return true
end)

-- Try UE4 console commands
RegisterConsoleCommandHandler(".exec", function(FullCommand, Parameters)
    local cmd = table.concat(Parameters, " ")
    if cmd == "" then
        Log("Usage: .exec <console command>")
        Log("Try: .exec SGK.SpawnItem Drink_Vodka")
        return true
    end
    Log("Executing: " .. cmd)
    ExecuteInGameThread(function()
        pcall(function()
            ExecuteConsoleCommand(cmd)
            Log("Command sent")
        end)
    end)
    return true
end)

-- Look for CheatManager or debug objects
RegisterConsoleCommandHandler(".debug", function(FullCommand, Parameters)
    Log("Searching for debug/cheat objects...")
    ExecuteInGameThread(function()
        local found = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                local lower = string.lower(name)
                if string.find(lower, "cheat") or string.find(lower, "debug") or string.find(lower, "admin") then
                    if not string.find(name, "Function") then
                        found[name] = true
                    end
                end
            end
            return false
        end)

        for name, _ in pairs(found) do
            Log("  " .. name)
        end
        Log("Found " .. (next(found) and "objects above" or "nothing"))
    end)
    return true
end)

-- Cached DataTable reference
local MasterItemList = nil

-- Known enemy types (from dev menu)
local EnemyTypes = {
    { id = "BP_AIDwardWild_C", name = "Dward", aliases = {"dward", "wild"} },
    { id = "BP_DeerAgro_C", name = "Deer (Aggressive)", aliases = {"deer", "deeragro", "aggressive"} },
    { id = "BP_DeerNeutral_C", name = "Deer (Neutral)", aliases = {"deerneutral", "neutral"} },
    { id = "BP_Ghoul_C", name = "Ghoul", aliases = {"ghoul"} },
    -- Asset is BP_Izbushka (the "Izdushka" spelling used by the menu/skeletal
    -- mesh folder does not exist as an AI class). Confirmed in AssetRegistry.
    -- Plain Actor, no gravity: zOffset places the root exactly 390 above the
    -- ground so the legs touch (calibrated in-game with .izsnap).
    { id = "BP_Izbushka_C", name = "Izdushka", aliases = {"izdushka", "izbushka", "izd"}, zOffset = 390 },
    { id = "BP_NormalBandit_C", name = "Bandit", aliases = {"bandit", "normalbandit"} },
    { id = "BP_NormalBanditUniform_C", name = "Bandit (Uniform)", aliases = {"bandituniform", "uniform"} },
    { id = "BP_PlagueDoctor_C", name = "Plague Doctor", aliases = {"plague", "doctor", "plaguedoctor"} },
    { id = "BP_RatWolf_C", name = "Rat Wolf", aliases = {"rat", "wolf", "ratwolf"} },
    { id = "BP_Screamer_C", name = "Screamer", aliases = {"screamer", "scream"} },
    { id = "BP_Swamper_C", name = "Swamper", aliases = {"swamper", "swamp"} },
    -- NOTE: not "BP_Zombie" — that asset doesn't exist in shipped builds; the
    -- real class is BP_ZombieSoilder (sic, dev typo). Confirmed in AssetRegistry.
    { id = "BP_ZombieSoilder_C", name = "Zombie", aliases = {"zombie", "zomb"} },
    { id = "BP_Twins_C", name = "Twins", aliases = {"twins", "twin"} },
}

-- Cached item list for fuzzy search
local CachedItems = nil

-- Fuzzy search: check if search term is contained in target
local function FuzzyMatch(search, target)
    search = string.lower(search)
    target = string.lower(target)
    -- Direct contains match
    if string.find(target, search, 1, true) then
        return true, 1  -- priority 1 = contains
    end
    -- Check if all chars of search appear in order in target
    local si = 1
    for i = 1, #target do
        if string.sub(target, i, i) == string.sub(search, si, si) then
            si = si + 1
            if si > #search then
                return true, 2  -- priority 2 = fuzzy
            end
        end
    end
    return false, 0
end

-- Build item cache (called separately to avoid callback issues)
local function BuildItemCache()
    if CachedItems then return end
    CachedItems = {}
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            if string.find(name, "BlueprintGeneratedClass") and
               string.find(name, "/Items/") and
               string.find(name, "BP_") then
                local className = string.match(name, "(BP_[%w_]+)_C$")
                if className then
                    -- Create simplified name (remove BP_ prefix and underscores)
                    local simpleName = string.gsub(className, "^BP_", "")
                    simpleName = string.gsub(simpleName, "_", "")
                    CachedItems[className] = {
                        id = className,
                        simple = string.lower(simpleName)
                    }
                end
            end
        end
        return false
    end)
end

-- Find best matching items for a search term
local function FindMatchingItems(search, maxResults)
    maxResults = maxResults or 5

    -- Ensure cache exists
    if not CachedItems then
        return {}
    end

    local matches = {}
    for id, item in pairs(CachedItems) do
        local isMatch, priority = FuzzyMatch(search, item.simple)
        if not isMatch then
            isMatch, priority = FuzzyMatch(search, id)
        end
        if isMatch then
            table.insert(matches, { id = id, priority = priority })
        end
    end

    -- Sort by priority (lower = better)
    table.sort(matches, function(a, b) return a.priority < b.priority end)

    -- Return top results
    local results = {}
    for i = 1, math.min(maxResults, #matches) do
        table.insert(results, matches[i].id)
    end
    return results
end

-- Find matching enemy for search term
local function FindMatchingEnemy(search)
    search = string.lower(search)
    local bestMatch = nil
    local bestPriority = 999

    for _, enemy in ipairs(EnemyTypes) do
        -- Check aliases first
        for _, alias in ipairs(enemy.aliases) do
            local isMatch, priority = FuzzyMatch(search, alias)
            if isMatch and priority < bestPriority then
                bestMatch = enemy
                bestPriority = priority
            end
        end
        -- Check full name
        local isMatch, priority = FuzzyMatch(search, enemy.name)
        if isMatch and priority < bestPriority then
            bestMatch = enemy
            bestPriority = priority
        end
    end

    return bestMatch
end

-- Noclip/fly state
local isFlying = false
local isGodMode = false

-- Enable cheats on PlayerController (required for CheatManager to work!)
local cheatsEnabled = false
local function EnableCheats()
    if cheatsEnabled then return true end

    local pc = GetPlayerController()
    if not pc then return false end

    local success = false

    -- Try EnableCheats function
    pcall(function()
        pc:EnableCheats()
        success = true
    end)

    -- Try setting property directly
    if not success then
        pcall(function()
            pc.bCheatsEnabled = true
            success = true
        end)
    end

    -- Try console command
    if not success then
        pcall(function()
            ExecuteConsoleCommand("EnableCheats")
            success = true
        end)
    end

    if success then
        cheatsEnabled = true
    end
    return success
end

-- Get CheatManager from PlayerController
local function GetCheatManager()
    local pc = GetPlayerController()
    if not pc then return nil end

    -- Enable cheats first!
    EnableCheats()

    local cm = nil

    -- Try property access
    pcall(function()
        cm = pc.CheatManager
    end)
    if cm then return cm end

    -- Try getter function
    pcall(function()
        cm = pc:GetCheatManager()
    end)
    if cm then return cm end

    -- Try to create/spawn CheatManager if it doesn't exist
    pcall(function()
        pc:AddCheats(true)
        cm = pc.CheatManager
    end)

    return cm
end

-- Execute a cheat command via CheatManager (tries multiple methods)
local function ExecuteCheat(cheatName, ...)
    local args = {...}
    local method = nil

    -- Build command string
    local cmdStr = cheatName
    if #args > 0 then
        for _, arg in ipairs(args) do
            cmdStr = cmdStr .. " " .. tostring(arg)
        end
    end

    -- Method 1: Try as console command first (most reliable)
    pcall(function()
        ExecuteConsoleCommand(cmdStr)
        method = "Console"
    end)

    -- Method 2: Call directly on CheatManager object
    if not method then
        pcall(function()
            local cm = GetCheatManager()
            if cm then
                if #args == 0 then
                    cm[cheatName](cm)
                elseif #args == 1 then
                    cm[cheatName](cm, args[1])
                elseif #args == 2 then
                    cm[cheatName](cm, args[1], args[2])
                end
                method = "CheatManager"
            end
        end)
    end

    -- Method 3: Try with PlayerController directly
    if not method then
        pcall(function()
            local pc = GetPlayerController()
            if pc then
                if #args == 0 then
                    pc[cheatName](pc)
                elseif #args == 1 then
                    pc[cheatName](pc, args[1])
                end
                method = "PlayerController"
            end
        end)
    end

    return method
end

-- Force-load a Blueprint class by content path and return its
-- BlueprintGeneratedClass UObject (or nil). Needed for AI/actors that are not
-- referenced by the loaded level (e.g. BP_ZombieSoilder), so their class is not
-- resident and the game's name-lookup spawners silently no-op.
--
-- Build-specific quirks (confirmed in-game on this UE4SS install):
--   * The ONLY LoadAsset form that loads is the full asset object path
--     "<pkg>.<asset>" — package-only and the "<pkg>.<asset>_C" class path both
--     no-op silently.
--   * LoadAsset's return value wraps a NULL object here; calling any method on it
--     (GetClass/GetFullName) access-violates and crashes the game. Never touch it.
--   * StaticFindObject cannot find the loaded class by path; the class must be
--     located by walking the UObject array (ForEachUObject) by exact FName.
--     FindAllOf is the wrong tool — it returns INSTANCES of a class, not the
--     class object.
-- pkgPath example: "/Game/Blueprints/AI/BP_ZombieSoilder"
local function LoadBPClass(pkgPath)
    local asset = pkgPath:match("([%w_]+)$")
    if not asset then return nil end
    local clsFName = asset .. "_C"
    local function findClass()
        local cls = nil
        pcall(function()
            ForEachUObject(function(o)
                local n = ""
                pcall(function() n = o:GetFName():ToString() end)
                if n == clsFName then
                    local fn = ""
                    pcall(function() fn = o:GetFullName() end)
                    if fn:find("^BlueprintGeneratedClass") then cls = o; return false end
                    if not cls then cls = o end
                end
                return false
            end)
        end)
        return cls
    end
    local cls = findClass()
    if cls then return cls end
    pcall(function() LoadAsset(pkgPath .. "." .. asset) end)
    return findClass()
end

local function GetMasterItemList()
    -- Try StaticFindObject first (avoids GC'd pointer issue)
    local dt = nil
    pcall(function()
        dt = StaticFindObject("/Game/SurvivalGameKitV2/Blueprints/Items/MasterLists/MasterItemList.MasterItemList")
    end)
    if dt then
        local ok, valid = pcall(function() return dt:IsValid() end)
        if ok and valid then MasterItemList = dt; return dt end
    end
    -- Fallback: search UObjects fresh each time (no stale-cache problem)
    local found = nil
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(name, "MasterItemList") then
            local okV, valid = pcall(function() return obj:IsValid() end)
            if okV and valid then found = obj; return true end
        end
        return false
    end)
    MasterItemList = found
    return MasterItemList
end

-- Dump DataTable row names to find correct item IDs
RegisterConsoleCommandHandler(".dtrows", function(FullCommand, Parameters)
    local filter = Parameters[1] and Parameters[1]:lower() or nil
    Log("Dumping MasterItemList row names" .. (filter and (" (filter: " .. filter .. ")") or "") .. "...")
    ExecuteInGameThread(function()
        local dt = GetMasterItemList()
        if not dt then Log("DataTable not found!") return end
        local count = 0
        local shown = 0
        local ok, result = pcall(function() return dt:GetAllTableRowNames() end)
        if ok and result then
            for i = 1, #result do
                local rn = result[i]:ToString()
                count = count + 1
                if not filter or rn:lower():find(filter, 1, true) then
                    shown = shown + 1
                    if shown <= 50 then Log("Row[" .. i .. "]: " .. rn) end
                end
            end
        else
            Log("GetAllTableRowNames failed: " .. tostring(result))
        end
        Log("Total rows: " .. count .. ", shown: " .. shown)
    end)
    return true
end)

-- Give item command - tries multiple methods to add item to inventory
RegisterConsoleCommandHandler(".give", function(FullCommand, Parameters)
    local itemID = Parameters[1]
    if not itemID or itemID == "" then
        Log("Usage: .give RowName [amount]")
        Log("Get row names from .scanworld")
        Log("  .give Weapon_SmallAxe")
        Log("  .give vodka 3   (partial match OK)")
        return true
    end
    local amount = tonumber(Parameters[2]) or 1
    local filterLower = itemID:lower()

    ExecuteInGameThread(function()
        local inv = GetInventory()
        if not inv then Log("No inventory") return end

        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items or #items == 0 then
            Log("No world items loaded — walk around to stream them in, then retry.")
            return
        end

        local matches = {}
        for _, item in ipairs(items) do
            local rn = "?"
            pcall(function() rn = item["Item"]["RowName"]:ToString() end)
            if rn:lower():find(filterLower, 1, true) then
                table.insert(matches, {item = item, rn = rn})
            end
        end

        if #matches == 0 then
            local player = GetPlayerCharacter()
            if not player then Log("No player") return end

            Log("'" .. itemID .. "' not in this area. Walk near where it spawns, then retry.")
            Log("Run .scanworld to see what items are available here.")
            return
        end

        local matchName = matches[1].rn
        Log("Giving: " .. matchName .. " x" .. amount)

        local given = 0
        local idx = 1
        while given < amount do
            if idx > #matches then
                Log("Only " .. given .. " of " .. matchName .. " available in world right now.")
                break
            end
            local entry = matches[idx]
            idx = idx + 1
            local ok, err = pcall(function() entry.item:Pickup(inv) end)
            if ok then
                given = given + 1
            else
                Log("Pickup ERR: " .. tostring(err):sub(1, 80))
                break
            end
        end

        if given > 0 then
            Log("Done — " .. given .. " x " .. matchName .. " added. Check inventory!")
        end
    end)
    return true
end)

-- Probe spawner properties for diagnosis
RegisterConsoleCommandHandler(".scanspawners", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local spawners = FindAllOf("BP_MasterItemSpawner_C")
        if not spawners or #spawners == 0 then Log("No spawners found.") return end
        Log("Total spawners in area: " .. #spawners)
        -- Probe first spawner for readable properties
        local s = spawners[1]
        local candidates = {
            "Item", "SpawnList", "ItemData", "ItemToSpawn", "DefaultItem",
            "Items", "SpawnItem", "SpawnItems", "ItemList", "LootTable",
            "SpawnEntry", "ItemRowName", "RowName", "InvItem", "SGK InvItem",
            "SpawnedItem", "ItemClass", "WorldItem", "SpawnChance",
        }
        Log("Probing first spawner properties:")
        for _, k in ipairs(candidates) do
            local ok, v = pcall(function() return s[k] end)
            if ok and v ~= nil then
                local ts = tostring(v)
                Log("  [" .. k .. "] = " .. ts:sub(1, 60))
                -- Try sub-fields
                local ok2, rn = pcall(function() return v["RowName"]:ToString() end)
                if ok2 and rn then Log("    .RowName = " .. rn) end
                local ok3, rn2 = pcall(function() return v[1]["Item"]["RowName"]:ToString() end)
                if ok3 and rn2 then Log("    [1].Item.RowName = " .. rn2) end
            end
        end
        -- Try SpawnNewItem on first spawner and see if items appear
        Log("Calling SpawnNewItem on first spawner...")
        local before = #(FindAllOf("BP_StaticMasterItem_C") or {})
        local ok, err = pcall(function() s:SpawnNewItem() end)
        if ok then
            local after = #(FindAllOf("BP_StaticMasterItem_C") or {})
            Log("SpawnNewItem OK. World items: " .. before .. " → " .. after)
        else
            Log("SpawnNewItem ERR: " .. tostring(err):sub(1, 80))
        end
    end)
    return true
end)

-- Force ALL spawners to spawn, then pickup matching items
RegisterConsoleCommandHandler(".forcespawn", function(FullCommand, Parameters)
    local itemID = Parameters[1]
    if not itemID or itemID == "" then
        Log("Usage: .forcespawn <filter>")
        Log("Triggers ALL item spawners, then picks up items matching filter.")
        return true
    end
    local filterLower = itemID:lower()
    ExecuteInGameThread(function()
        local inv = GetInventory()
        if not inv then Log("No inventory") return end

        local spawners = FindAllOf("BP_MasterItemSpawner_C")
        if not spawners or #spawners == 0 then
            Log("No item spawners in this area.")
            return
        end

        local before = #(FindAllOf("BP_StaticMasterItem_C") or {})
        Log("Triggering " .. #spawners .. " spawners (world items before: " .. before .. ")...")

        local ok_count, err_count = 0, 0
        for _, s in ipairs(spawners) do
            local ok = pcall(function() s:SpawnNewItem() end)
            if ok then ok_count = ok_count + 1 else err_count = err_count + 1 end
        end
        Log("SpawnNewItem: " .. ok_count .. " OK, " .. err_count .. " errors.")

        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        local after = #worldItems
        Log("World items after: " .. after .. " (+" .. (after - before) .. " new)")

        local picked, matchName = 0, itemID
        for _, item in ipairs(worldItems) do
            local rn = "?"
            pcall(function() rn = item["Item"]["RowName"]:ToString() end)
            if rn:lower():find(filterLower, 1, true) then
                matchName = rn
                local ok2 = pcall(function() item:Pickup(inv) end)
                if ok2 then picked = picked + 1 end
            end
        end

        if picked > 0 then
            Log("Done — picked up " .. picked .. " x " .. matchName .. ". Check inventory!")
        else
            Log("0 items matched '" .. itemID .. "' after spawning.")
            Log("Run .scanworld to see what items exist, or .scanspawners to debug spawner layout.")
        end
    end)
    return true
end)

-- Test BP_GlobalInventoryManager_C:CreateNewItem
RegisterConsoleCommandHandler(".testcreate", function(FullCommand, Parameters)
    local itemID = Parameters[1]
    if not itemID or itemID == "" then itemID = "Drink_Vodka" end
    ExecuteInGameThread(function()
        -- Find GlobalInventoryManager
        local mgrs = FindAllOf("BP_GlobalInventoryManager_C")
        if not mgrs or #mgrs == 0 then
            Log("BP_GlobalInventoryManager_C: not found in scene.")
            return
        end
        local mgr = mgrs[1]
        Log("Found GlobalInventoryManager: " .. tostring(mgr))

        -- Find player inventory for reference
        local inv = GetInventory()
        if not inv then Log("No player inventory") return end

        -- Attempt 1: no args
        Log("--- Attempt 1: CreateNewItem() no args ---")
        local ok1, r1 = pcall(function() return mgr:CreateNewItem() end)
        Log("Result: ok=" .. tostring(ok1) .. " val=" .. tostring(r1))

        -- Attempt 2: pass the inventory component as arg
        Log("--- Attempt 2: CreateNewItem(inv) ---")
        local ok2, r2 = pcall(function() return mgr:CreateNewItem(inv) end)
        Log("Result: ok=" .. tostring(ok2) .. " val=" .. tostring(r2))

        -- Attempt 3: pass row name string
        Log("--- Attempt 3: CreateNewItem('" .. itemID .. "') ---")
        local ok3, r3 = pcall(function() return mgr:CreateNewItem(itemID) end)
        Log("Result: ok=" .. tostring(ok3) .. " val=" .. tostring(r3))

        -- Attempt 4: pass amount integer
        Log("--- Attempt 4: CreateNewItem(1) ---")
        local ok4, r4 = pcall(function() return mgr:CreateNewItem(1) end)
        Log("Result: ok=" .. tostring(ok4) .. " val=" .. tostring(r4))

        -- Attempt 5: CreateNewInventory (no args)
        Log("--- Attempt 5: CreateNewInventory() ---")
        local ok5, r5 = pcall(function() return mgr:CreateNewInventory() end)
        Log("Result: ok=" .. tostring(ok5) .. " val=" .. tostring(r5))

        -- Check if any new world items appeared
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        Log("World items after attempts: " .. #worldItems)

        -- If CreateNewItem returned something, inspect it
        for i, result in ipairs({r1, r2, r3, r4}) do
            if result ~= nil and result ~= false and type(result) ~= "string" then
                Log("Return value from attempt " .. i .. " is UObject — trying Pickup...")
                local okp, errp = pcall(function() result:Pickup(inv) end)
                Log("Pickup: ok=" .. tostring(okp) .. " " .. tostring(errp or ""))
            end
        end
    end)
    return true
end)

-- Diagnose FName raw value for a world item
RegisterConsoleCommandHandler(".fnameraw", function(FullCommand, Parameters)
    local filter = ((Parameters[1] or "")):lower()
    ExecuteInGameThread(function()
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        for _, item in ipairs(worldItems) do
            local ok, rn = pcall(function() return item["Item"]["RowName"]:ToString() end)
            if ok and rn and rn:lower():find(filter, 1, true) then
                local fname = item["Item"]["RowName"]
                Log("=== FName raw for " .. rn .. " ===")
                Log("  tostring: " .. tostring(fname))
                Log("  type: " .. type(fname))
                pcall(function() Log("  GetValue: " .. tostring(fname:GetValue())) end)
                pcall(function() Log("  GetComparisonIndex: " .. tostring(fname:GetComparisonIndex())) end)
                pcall(function() Log("  GetNumber: " .. tostring(fname:GetNumber())) end)
                pcall(function() Log("  GetDisplayIndex: " .. tostring(fname:GetDisplayIndex())) end)
                pcall(function() Log("  IsValid: " .. tostring(fname:IsValid())) end)
                return
            end
        end
        Log("No world item matching '" .. filter .. "'")
    end)
    return true
end)

-- Inject any item into an inventory slot by FName-to-FName assignment
-- Usage: .inject <TargetRowName> [SlotIndex|SourceRowName]
-- Example: .inject Weapon_SapperShovel 9mm
-- Requires the target item to exist as a world actor (BP_StaticMasterItem_C)
RegisterConsoleCommandHandler(".inject", function(FullCommand, Parameters)
    local targetName = Parameters[1] or ""
    local slotFilter = Parameters[2] or ""
    if targetName == "" then
        Log("[inject] Usage: .inject <TargetRowName> [SlotIndex|SourceRowName]")
        Log("[inject] Example: .inject Weapon_SapperShovel 9mm")
        return true
    end
    ExecuteInGameThread(function()
        -- Get target FName userdata from a world actor
        local targetFName = nil
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        for _, item in ipairs(worldItems) do
            local ok, rn = pcall(function() return item["Item"]["RowName"]:ToString() end)
            if ok and rn == targetName then
                local fnOk, fn = pcall(function() return item["Item"]["RowName"] end)
                if fnOk and fn then targetFName = fn end
                break
            end
        end
        if not targetFName then
            Log("[inject] ERROR: '" .. targetName .. "' not found in world. Place it first.")
            return
        end
        Log("[inject] Got target FName from world actor.")

        -- Get inventory
        local inv = GetInventory()
        if not inv then Log("[inject] ERROR: No inventory") return end

        -- Attempt 1: direct FName-to-FName on inventory slot (if TArray readable)
        local attempt1Done = false
        local slots = nil
        pcall(function() slots = inv["InventorySlots"] end)
        local slotCount = 0
        if slots then pcall(function() slotCount = slots:Num() end) end
        if slots and slotCount > 0 then
            local targetSlotIdx = nil
            local slotIdxNum = tonumber(slotFilter)
            if slotIdxNum then
                targetSlotIdx = slotIdxNum
            else
                for i = 0, slotCount - 1 do
                    local rn = "?"
                    pcall(function() rn = slots[i]["Item"]["RowName"]:ToString() end)
                    if rn ~= "?" and rn ~= "None" and rn ~= "" then
                        if slotFilter == "" or rn:lower():find(slotFilter:lower(), 1, true) then
                            targetSlotIdx = i
                            Log("[inject] Found slot[" .. i .. "]: " .. rn)
                            break
                        end
                    end
                end
            end
            if targetSlotIdx ~= nil then
                local slot = slots[targetSlotIdx]
                local beforeRn = "?"
                pcall(function() beforeRn = slot["Item"]["RowName"]:ToString() end)
                Log("[inject] Slot[" .. targetSlotIdx .. "] before: " .. beforeRn)
                local ok1, err1 = pcall(function()
                    slot["Item"]["RowName"] = targetFName
                end)
                if ok1 then
                    local afterRn = "?"
                    pcall(function() afterRn = slot["Item"]["RowName"]:ToString() end)
                    Log("[inject] Slot[" .. targetSlotIdx .. "] after: " .. afterRn)
                    Log("[inject] Done (slot assign). Reopen inventory if UI not updated.")
                    attempt1Done = true
                else
                    Log("[inject] Slot assign failed: " .. tostring(err1))
                end
            else
                Log("[inject] No slot matching '" .. slotFilter .. "', trying fallback...")
            end
        else
            Log("[inject] InventorySlots not readable, trying world-actor fallback...")
        end

        if attempt1Done then return end

        -- Attempt 2: find the target actor in world and call Pickup directly
        Log("[inject] Calling Pickup on world actor: " .. targetName)
        local targetActor = nil
        for _, item in ipairs(worldItems) do
            local wok, wrn = pcall(function() return item["Item"]["RowName"]:ToString() end)
            if wok and wrn == targetName then
                targetActor = item
                break
            end
        end
        if not targetActor then
            Log("[inject] No world actor with RowName='" .. targetName .. "' found.")
            return
        end
        local pickOk, pickErr = pcall(function() targetActor:Pickup(inv) end)
        if not pickOk then
            Log("[inject] Pickup failed: " .. tostring(pickErr))
        else
            Log("[inject] Pickup called. Check inventory.")
        end
    end)
    return true
end)

-- Direct AttemptToAddItem call with a Lua-constructed FS_InvItem struct
-- Usage: .addraw <RowName> [amount]
RegisterConsoleCommandHandler(".addraw", function(FullCommand, Parameters)
    local targetName = Parameters[1] or ""
    local amount = tonumber(Parameters[2]) or 1
    if targetName == "" then
        Log("[addraw] Usage: .addraw <RowName> [amount]")
        return true
    end
    ExecuteInGameThread(function()
        local inv = GetInventory()
        if not inv then Log("[addraw] No inventory") return end

        -- Mangled field names from S_InvItem (discovered via hook diagnostics)
        local F_ID       = "ID_2_84C2CB8945979246059C568DCD463423"
        local F_Amount   = "Amount_5_62DB2267439500D86A52E0B2266494D2"
        local F_QBIndex  = "QuickBindIndex_16_7A1D8FC742EA4742106A33A874F67F34"
        local F_Rotated  = "Rotated_18_66B00C8648A7E3BEB56C4282929D015D"
        local F_UseAmt   = "UseAmount_21_73BF7A6447A384E099761EA48F7DB753"
        local F_InUse    = "InUse_23_430FC3BE41900570FBD4AA881817E89F"
        local F_Durab    = "Durability_30_E9AF67CA4E71F502EF4B18A440FA0385"
        local F_Decay    = "DecayTime_33_E35E189B4E5F129EEECA28AE05E99A93"

        local invItem = {
            [F_ID]       = FName(targetName),
            [F_Amount]   = amount,
            [F_QBIndex]  = -1,
            [F_Rotated]  = false,
            [F_UseAmt]   = 0,
            [F_InUse]    = false,
            [F_Durab]    = 100.0,
            [F_Decay]    = 0
        }

        -- arg[5]: another FS_InvItem (out)
        local outItem = {
            [F_ID]       = FName("None"),
            [F_Amount]   = 0,
            [F_QBIndex]  = -1,
            [F_Rotated]  = false,
            [F_UseAmt]   = 0,
            [F_InUse]    = false,
            [F_Durab]    = 0.0,
            [F_Decay]    = 0
        }
        -- arg[6]: FInventorySlot {InvComponent, Index}
        local F_InvComp = "InvComponent_5_A1D58E004822DA933B61B28C627EDF23"
        local F_Index   = "Index_4_ABD9C3F64229CF5D88D6FC8CCDD577B6"
        local slotRef = {
            [F_InvComp] = nil,
            [F_Index]   = -1
        }

        -- Out bool refs (args 2, 3, 4): RemoteUnrealParam — pass as {value} tables
        local ref2 = {true}
        local ref3 = {true}
        local ref4 = {false}

        Log("[addraw] Calling inv:AttemptToAddItem with " .. targetName .. " x" .. amount)
        local r1, r2, r3, r4, r5, r6 = nil, nil, nil, nil, nil, nil
        local ok, err = pcall(function()
            r1, r2, r3, r4, r5, r6 = inv:AttemptToAddItem(invItem, ref2, ref3, ref4, outItem, slotRef)
        end)
        if not ok then
            Log("[addraw] Call failed: " .. tostring(err))
        else
            Log("[addraw] Call OK. r1=" .. tostring(r1) .. " r2=" .. tostring(r2) .. " r3=" .. tostring(r3))
            Log("[addraw]         r4=" .. tostring(r4) .. " r5=" .. tostring(r5) .. " r6=" .. tostring(r6))
        end
    end)
    return true
end)

-- Proper item spawn using the game's own factory:
--   BP_GlobalInventoryManager_C:CreateNewItem -> fully-initialized FS_InvItem
--   (incl. MasterInventory ref for wearable slots / weapon mag / mag ammo)
-- Then hand the filled struct to BP_PlayerInventory_C:AttemptToAddItem.
-- Usage: .give2 <RowName> [amount]
RegisterConsoleCommandHandler(".give2", function(FullCommand, Parameters)
    local targetName = Parameters[1] or ""
    local amount = tonumber(Parameters[2]) or 1
    if targetName == "" then
        Log("[give2] Usage: .give2 <RowName> [amount]")
        return true
    end
    ExecuteInGameThread(function()
        local gims = FindAllOf("BP_GlobalInventoryManager_C")
        if not gims or #gims == 0 then Log("[give2] No BP_GlobalInventoryManager_C") return end
        local gim = gims[1]

        local inv = GetInventory()
        if not inv then Log("[give2] No inventory") return end

        -- FS_InvItem mangled field names
        local F_ID       = "ID_2_84C2CB8945979246059C568DCD463423"
        local F_Amount   = "Amount_5_62DB2267439500D86A52E0B2266494D2"
        local F_MasterI  = "MasterInventory_8_17FFB7D341FAF2689C1BABA12E3BA9F5"
        local F_QBIndex  = "QuickBindIndex_16_7A1D8FC742EA4742106A33A874F67F34"
        local F_Rotated  = "Rotated_18_66B00C8648A7E3BEB56C4282929D015D"
        local F_UseAmt   = "UseAmount_21_73BF7A6447A384E099761EA48F7DB753"
        local F_InUse    = "InUse_23_430FC3BE41900570FBD4AA881817E89F"
        local F_Durab    = "Durability_30_E9AF67CA4E71F502EF4B18A440FA0385"
        local F_Decay    = "DecayTime_33_E35E189B4E5F129EEECA28AE05E99A93"
        -- FInventorySlot fields
        local F_InvComp = "InvComponent_5_A1D58E004822DA933B61B28C627EDF23"
        local F_Index   = "Index_4_ABD9C3F64229CF5D88D6FC8CCDD577B6"

        -- Empty FS_InvItem the factory fills in (arg[8] of CreateNewItem)
        local outItem = {
            [F_ID]      = FName("None"),
            [F_Amount]  = 0,
            [F_MasterI] = nil,
            [F_QBIndex] = -1,
            [F_Rotated] = false,
            [F_UseAmt]  = 0,
            [F_InUse]   = false,
            [F_Durab]   = 0.0,
            [F_Decay]   = 0,
        }

        Log("[give2] CreateNewItem(" .. targetName .. " x" .. amount .. ")")
        -- Observed signature (FName, int, bool, bool, bool, bool, float, out FS_InvItem)
        local r1, r2, r3 = nil, nil, nil
        local okCall, errCall = pcall(function()
            r1, r2, r3 = gim:CreateNewItem(FName(targetName), amount, true, true, false, false, 0.0, outItem)
        end)
        if not okCall then
            Log("[give2] CreateNewItem failed: " .. tostring(errCall))
            return
        end
        Log("[give2] CreateNewItem returned r1=" .. tostring(r1) .. " r2=" .. tostring(r2) .. " r3=" .. tostring(r3))

        -- Pick whichever return is the filled struct. UE4SS sends out-params as
        -- extra return values in declaration order. r1 should be the FS_InvItem.
        local filled = r1
        -- Fallback: if returns are nil/non-struct, the Lua input table itself may have been mutated.
        if type(filled) ~= "userdata" then
            Log("[give2] r1 not userdata; falling back to mutated input table")
            filled = outItem
        end

        -- Diagnostic: print MasterInventory ref so we can confirm it got set
        local miStr = "<unreadable>"
        pcall(function()
            local mi = filled[F_MasterI]
            if mi then miStr = tostring(mi:GetFullName()) end
        end)
        Log("[give2] filled.MasterInventory = " .. miStr)

        -- Hand to AttemptToAddItem
        local out2 = {
            [F_ID]=FName("None"), [F_Amount]=0, [F_MasterI]=nil, [F_QBIndex]=-1,
            [F_Rotated]=false, [F_UseAmt]=0, [F_InUse]=false, [F_Durab]=0.0, [F_Decay]=0,
        }
        local slotRef = { [F_InvComp] = nil, [F_Index] = -1 }
        local ref2, ref3, ref4 = {true}, {true}, {false}

        local okAdd, errAdd = pcall(function()
            inv:AttemptToAddItem(filled, ref2, ref3, ref4, out2, slotRef)
        end)
        if okAdd then
            Log("[give2] AttemptToAddItem OK: " .. targetName .. " x" .. amount)
        else
            Log("[give2] AttemptToAddItem failed: " .. tostring(errAdd))
        end
    end)
    return true
end)

-- Give any item by RowName, spawning a temporary world actor if needed
-- Usage: .giveme <RowName>  e.g. .giveme Weapon_Pistol9mm
RegisterConsoleCommandHandler(".giveme", function(FullCommand, Parameters)
    local targetName = Parameters[1] or ""
    if targetName == "" then
        Log("[giveme] Usage: .giveme <RowName>")
        return true
    end
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("[giveme] ERROR: No player") return end
        local inv = GetInventory()
        if not inv then Log("[giveme] ERROR: No inventory") return end

        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}

        -- Fast path: item already in world
        for _, item in ipairs(worldItems) do
            local ok, rn = pcall(function() return item["Item"]["RowName"]:ToString() end)
            if ok and rn == targetName then
                local pickOk, pickErr = pcall(function() item:Pickup(inv) end)
                if pickOk then
                    Log("[giveme] Pickup (world actor) done.")
                else
                    Log("[giveme] Pickup failed: " .. tostring(pickErr))
                end
                return
            end
        end

        -- Item not in world: call AttemptToAddItem directly with crafted FS_InvItem
        Log("[giveme] Not in world. Calling AttemptToAddItem directly.")
        local F_ID       = "ID_2_84C2CB8945979246059C568DCD463423"
        local F_Amount   = "Amount_5_62DB2267439500D86A52E0B2266494D2"
        local F_QBIndex  = "QuickBindIndex_16_7A1D8FC742EA4742106A33A874F67F34"
        local F_Rotated  = "Rotated_18_66B00C8648A7E3BEB56C4282929D015D"
        local F_UseAmt   = "UseAmount_21_73BF7A6447A384E099761EA48F7DB753"
        local F_InUse    = "InUse_23_430FC3BE41900570FBD4AA881817E89F"
        local F_Durab    = "Durability_30_E9AF67CA4E71F502EF4B18A440FA0385"
        local F_Decay    = "DecayTime_33_E35E189B4E5F129EEECA28AE05E99A93"
        local F_InvComp  = "InvComponent_5_A1D58E004822DA933B61B28C627EDF23"
        local F_Index    = "Index_4_ABD9C3F64229CF5D88D6FC8CCDD577B6"

        local invItem = {
            [F_ID]=FName(targetName), [F_Amount]=1, [F_QBIndex]=-1,
            [F_Rotated]=false, [F_UseAmt]=0, [F_InUse]=false,
            [F_Durab]=100.0, [F_Decay]=0
        }
        local outItem = {
            [F_ID]=FName("None"), [F_Amount]=0, [F_QBIndex]=-1,
            [F_Rotated]=false, [F_UseAmt]=0, [F_InUse]=false,
            [F_Durab]=0.0, [F_Decay]=0
        }
        local slotRef = { [F_InvComp]=nil, [F_Index]=-1 }
        local ref2, ref3, ref4 = {true}, {true}, {false}

        local ok, err = pcall(function()
            inv:AttemptToAddItem(invItem, ref2, ref3, ref4, outItem, slotRef)
        end)
        if not ok then
            Log("[giveme] AttemptToAddItem failed: " .. tostring(err))
        else
            Log("[giveme] Added " .. targetName .. " x1")
        end
    end)
    return true
end)

-- Print memory addresses of world items and inventory slots for CE use
RegisterConsoleCommandHandler(".ceinfo", function(FullCommand, Parameters)
    local filter = Parameters[1] or ""
    local filterLower = filter:lower()
    ExecuteInGameThread(function()
        -- World items: print address + row name
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        Log("=== World Items (BP_StaticMasterItem_C) ===")
        for _, item in ipairs(worldItems) do
            local rn = "?"
            pcall(function() rn = item["Item"]["RowName"]:ToString() end)
            if filter == "" or rn:lower():find(filterLower, 1, true) then
                -- tostring gives "AActor: 0xADDRESS"
                local addr = tostring(item):match("0x%x+") or tostring(item)
                Log("  " .. rn .. " @ " .. addr)
            end
        end

        -- Player inventory: print address
        local inv = GetInventory()
        if inv then
            local invAddr = tostring(inv):match("0x%x+") or tostring(inv)
            Log("=== Player Inventory ===")
            Log("  Inventory component @ " .. invAddr)

            -- Print inventory slots with item data
            local slots = nil
            pcall(function() slots = inv["InventorySlots"] end)
            local slotCount = 0
            if slots then pcall(function() slotCount = slots:Num() end) end
            if slots and slotCount > 0 then
                Log("  InventorySlots found, length=" .. tostring(slotCount))
                for i = 0, math.min(slotCount - 1, 19) do
                    local slotRn = "?"
                    pcall(function() slotRn = slots[i]["Item"]["RowName"]:ToString() end)
                    if slotRn ~= "?" and slotRn ~= "None" and slotRn ~= "" then
                        Log("  Slot[" .. i .. "]: " .. slotRn)
                    end
                end
            else
                Log("  InventorySlots: could not read (try 'Items', 'Slots')")
                -- Try alternative names
                for _, name in ipairs({"Items", "Slots", "InvItems", "ItemSlots", "GridItems"}) do
                    local ok, v = pcall(function() return inv[name] end)
                    if ok and v ~= nil then
                        Log("  Found property '" .. name .. "': " .. tostring(v):sub(1,40))
                    end
                end
            end
        end
    end)
    return true
end)

-- Read inventory item IDs — calls GetName()/GetFullName() on UObject fields
RegisterConsoleCommandHandler(".invitems", function(FullCommand, Parameters)
    local limit = tonumber(Parameters[1]) or 5
    Log("Reading first " .. limit .. " inventory slots (UObject names)...")
    ExecuteInGameThread(function()
        local inv = GetInventory()
        if not inv then Log("Inventory not found!") return end
        local ok, arr = pcall(function() return inv["Items"] end)
        if not ok or not arr then Log("inv.Items not accessible") return end
        local count = 0
        pcall(function()
            for i = 0, limit - 1 do
                local slot = arr[i]
                if slot == nil then Log("  [" .. i .. "] nil — end of array"); break end
                local idFields = {"ID", "RowName", "ItemID", "Name"}
                for _, field in ipairs(idFields) do
                    local okf, val = pcall(function() return slot[field] end)
                    if okf and val then
                        -- Try FName ToString
                        local s1 = ""; pcall(function() s1 = val:ToString() end)
                        -- Try UObject GetName
                        local s2 = ""; pcall(function() s2 = val:GetName() end)
                        -- Try UObject GetFullName
                        local s3 = ""; pcall(function() s3 = val:GetFullName() end)
                        if s1 ~= "" or s2 ~= "" then
                            Log(string.format("  [%d] %s | FName=%s | GetName=%s", i, field, s1, s2))
                            if s3 ~= "" and s3 ~= s2 then Log("       full=" .. s3) end
                            count = count + 1
                        end
                    end
                end
            end
        end)
        Log("Done. " .. count .. " values read.")
    end)
    return true
end)

-- Dump valid item RowNames from live world item's DataTable (fallback to ParentTables)
RegisterConsoleCommandHandler(".itemrows", function(FullCommand, Parameters)
    local filter = Parameters[1] and Parameters[1]:lower() or nil
    ExecuteInGameThread(function()
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        if #worldItems == 0 then Log("[itemrows] No world items") return end
        local dt = nil
        for _, item in ipairs(worldItems) do
            pcall(function() dt = item["Item"]["DataTable"] end)
            if dt then break end
        end
        if not dt then Log("[itemrows] No DataTable from world items") return end
        Log("[itemrows] DataTable: " .. tostring(dt:GetFullName()))

        local dumped = false
        local function dumpTable(t, label)
            local ok, rows = pcall(function() return t:GetAllTableRowNames() end)
            if ok and rows and #rows > 0 then
                Log("[itemrows] " .. label .. ": " .. #rows .. " rows")
                local shown = 0
                for i = 1, #rows do
                    local rn = ""; pcall(function() rn = rows[i]:ToString() end)
                    if not filter or rn:lower():find(filter, 1, true) then
                        shown = shown + 1
                        if shown <= 100 then Log("  " .. rn) end
                    end
                end
                Log("[itemrows] Shown: " .. shown)
                dumped = true
            end
        end

        dumpTable(dt, "DataTable")
        if not dumped then
            -- CompositeDataTable fallback
            local ok, parents = pcall(function() return dt["ParentTables"] end)
            if ok and parents then
                pcall(function()
                    for i = 0, 20 do
                        local p = parents[i]
                        if not p then break end
                        local pname = ""; pcall(function() pname = p:GetName() end)
                        dumpTable(p, "Parent[" .. i .. "] " .. pname)
                    end
                end)
            end
        end
        if not dumped then Log("[itemrows] Could not enumerate rows") end
    end)
    return true
end)

-- Try CompositeDataTable.ParentTables to get sub-tables where GetAllTableRowNames works
RegisterConsoleCommandHandler(".dtrowsalt", function(FullCommand, Parameters)
    local filter = Parameters[1] and Parameters[1]:lower() or nil
    Log("Trying CompositeDataTable.ParentTables approach...")
    ExecuteInGameThread(function()
        local dt = GetMasterItemList()
        if not dt then Log("DataTable not found!") return end

        -- Try GetAllTableRowNames directly first (fresh reference)
        local ok1, rows1 = pcall(function() return dt:GetAllTableRowNames() end)
        if ok1 and rows1 and #rows1 > 0 then
            Log("GetAllTableRowNames WORKED! " .. #rows1 .. " rows:")
            for i = 1, math.min(50, #rows1) do
                local rn = ""
                pcall(function() rn = rows1[i]:ToString() end)
                if not filter or rn:lower():find(filter, 1, true) then
                    Log("  " .. rn)
                end
            end
            return
        end
        Log("Direct GetAllTableRowNames failed: " .. tostring(rows1))

        -- Try ParentTables on CompositeDataTable
        local ok2, parents = pcall(function() return dt["ParentTables"] end)
        if ok2 and parents then
            Log("ParentTables found, iterating...")
            pcall(function()
                for i = 0, 20 do
                    local parent = parents[i]
                    if parent == nil then break end
                    local pname = ""; pcall(function() pname = parent:GetName() end)
                    Log("  Parent[" .. i .. "]: " .. pname)
                    local ok3, rows = pcall(function() return parent:GetAllTableRowNames() end)
                    if ok3 and rows and #rows > 0 then
                        Log("  -> " .. #rows .. " rows!")
                        for j = 1, math.min(30, #rows) do
                            local rn = ""; pcall(function() rn = rows[j]:ToString() end)
                            if not filter or rn:lower():find(filter, 1, true) then
                                Log("    " .. rn)
                            end
                        end
                    else
                        Log("  -> GetAllTableRowNames failed: " .. tostring(rows))
                    end
                end
            end)
        else
            Log("ParentTables not accessible: " .. tostring(parents))
        end
    end)
    return true
end)

-- FS_InvItem / FInventorySlot mangled field names (verified via hook diagnostics)
local FS_ID       = "ID_2_84C2CB8945979246059C568DCD463423"
local FS_Amount   = "Amount_5_62DB2267439500D86A52E0B2266494D2"
local FS_MasterI  = "MasterInventory_8_17FFB7D341FAF2689C1BABA12E3BA9F5"
local FS_QBIndex  = "QuickBindIndex_16_7A1D8FC742EA4742106A33A874F67F34"
local FS_Rotated  = "Rotated_18_66B00C8648A7E3BEB56C4282929D015D"
local FS_UseAmt   = "UseAmount_21_73BF7A6447A384E099761EA48F7DB753"
local FS_InUse    = "InUse_23_430FC3BE41900570FBD4AA881817E89F"
local FS_Durab    = "Durability_30_E9AF67CA4E71F502EF4B18A440FA0385"
local FS_Decay    = "DecayTime_33_E35E189B4E5F129EEECA28AE05E99A93"
local FS_InvComp  = "InvComponent_5_A1D58E004822DA933B61B28C627EDF23"
local FS_Index    = "Index_4_ABD9C3F64229CF5D88D6FC8CCDD577B6"

local function _MakeEmptyInvItem()
    return {
        [FS_ID]      = FName("None"),
        [FS_Amount]  = 0,
        [FS_MasterI] = nil,
        [FS_QBIndex] = -1,
        [FS_Rotated] = false,
        [FS_UseAmt]  = 0,
        [FS_InUse]   = false,
        [FS_Durab]   = 0.0,
        [FS_Decay]   = 0,
    }
end

-- Build a fully-initialised FS_InvItem via BP_GlobalInventoryManager_C:CreateNewItem.
-- Returns the populated Lua table (with MasterInventory filled) or nil on failure.
local function FactoryCreateInvItem(rowName, amount)
    local gims = FindAllOf("BP_GlobalInventoryManager_C")
    if not gims or #gims == 0 then return nil end
    local gim = gims[1]
    local item = _MakeEmptyInvItem()
    local ok = pcall(function()
        -- Observed signature: (FName, int, bool, bool, bool, bool, float, out FS_InvItem)
        gim:CreateNewItem(FName(rowName), amount, true, true, false, false, 0.0, item)
    end)
    if not ok then return nil end
    -- Sanity check: factory should have written ID
    local gotName = nil
    pcall(function() gotName = item[FS_ID]:ToString() end)
    if not gotName or gotName == "None" or gotName == "" then return nil end
    return item
end

-- ============================================================
-- ITEM MENU - in-game item names, search, single spawn (v4.5)
-- ============================================================
-- One table instead of many locals: the main chunk is close to Lua's
-- 200-local limit. UI parts are defined after AddItemByRowName.
local ItemMenu = {
    rowToLabel = nil,   -- MasterItemList row name -> unique in-game name shown in the menu
    labelToRow = nil,   -- shown name -> row name
    menuRows = nil,     -- row names the game put in the menu's item list
    cheatMenu = nil,    -- live WD_CheatMenu widget
    cheatMenuPath = nil,
    combo = nil,        -- its item ComboBoxString
    appliedSig = nil,   -- signature of the option list we last wrote
    filterText = "",
    searchBox = nil,    -- EditableTextBox added next to the amount field
    searchName = "ModMenuItemSearch",
    searchPath = nil,
    searchFailed = false,
    lastBoxText = "",
    polling = false,
    pending = 0,        -- spawns whose list selection is still swapped; the list is left alone meanwhile
    lastClickAt = -100,
    lastTickErr = nil,
    NO_MATCH = "- no items match -",
}

-- FString/FText/FName/string -> Lua string (nil if not convertible)
function ItemMenu.Str(v)
    if type(v) == "string" then return v end
    if v == nil then return nil end
    local s = nil
    pcall(function() s = v:ToString() end)
    if type(s) == "string" then return s end
    return nil
end

function ItemMenu.IsValid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

-- "ClassName /Path/To.Object" -> "/Path/To.Object"
function ItemMenu.PathOf(obj)
    local fn = ""
    pcall(function() fn = obj:GetFullName() end)
    return fn:match("^%S+%s+(.+)$") or fn
end

-- Helper: add item by RowName.
-- Priority:
--   1. Factory path (CreateNewItem) — fills MasterInventory so wearables/weapons/mags work
--   2. World-actor Pickup — preserves runtime state of an existing world item
--   3. Bare AttemptToAddItem — last resort, item will spawn glitched until save/reload
local function AddItemByRowName(rowName, amount, inv)
    amount = amount or 1
    if inv == nil and Coop.Joined() then
        -- someone else's world: the host's game adds it to our inventory
        return Coop.Send("GIVE_" .. math.floor(amount) .. "_" .. rowName, rowName .. " x" .. amount)
    end
    inv = inv or GetInventory()
    if not inv then Log("[AddItem] No inventory") return false end

    -- Path 1: factory (preferred — produces fully-initialised items)
    local filled = FactoryCreateInvItem(rowName, amount)
    if filled then
        local out2 = _MakeEmptyInvItem()
        local slotRef = { [FS_InvComp] = nil, [FS_Index] = -1 }
        local okAdd = pcall(function()
            inv:AttemptToAddItem(filled, {true}, {true}, {false}, out2, slotRef)
        end)
        if okAdd then
            Log("[AddItem] Factory: " .. rowName .. " x" .. amount)
            return true
        end
        Log("[AddItem] Factory call succeeded but AttemptToAddItem failed — falling back")
    end

    -- Path 2: pick up an existing world actor (preserves its current state)
    local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
    local picked = 0
    for _, item in ipairs(worldItems) do
        if picked >= amount then break end
        local ok, rn = pcall(function() return item["Item"]["RowName"]:ToString() end)
        if ok and rn == rowName then
            local pickOk = pcall(function() item:Pickup(inv) end)
            if pickOk then picked = picked + 1 end
        end
    end
    if picked >= amount then
        Log("[AddItem] Pickup x" .. picked .. ": " .. rowName)
        return true
    end
    local remaining = amount - picked
    if picked > 0 then
        Log("[AddItem] Pickup x" .. picked .. ", " .. remaining .. " more via fallback")
    end

    -- Path 3: bare AttemptToAddItem (will produce a glitched item)
    local invItem = _MakeEmptyInvItem()
    invItem[FS_ID]     = FName(rowName)
    invItem[FS_Amount] = remaining
    invItem[FS_Durab]  = 100.0
    local outItem = _MakeEmptyInvItem()
    local slotRef = { [FS_InvComp] = nil, [FS_Index] = -1 }
    local ok, err = pcall(function()
        inv:AttemptToAddItem(invItem, {true}, {true}, {false}, outItem, slotRef)
    end)
    if ok then
        Log("[AddItem] Bare (item may be glitched): " .. rowName .. " x" .. remaining)
        return true
    end
    Log("[AddItem] FAILED: " .. tostring(err))
    return false
end

Coop.AddItem = AddItemByRowName

-- ---------- item names ----------

-- Fallback label from a row name: "Consumable_AntiRadPils" -> "Anti Rad Pils"
function ItemMenu.Prettify(rowName)
    local s = rowName:gsub("^[^_]+_", "", 1)
    s = s:gsub("_", " ")
    s = s:gsub("(%l)(%u)", "%1 %2")
    return s
end

-- The row struct's in-game name field. Blueprint struct fields are mangled
-- (Name_2_<GUID>), so it is found by type and base name. `forEachProperty`
-- walks the struct's properties.
function ItemMenu.FindNameField(forEachProperty)
    local best, bestScore = nil, 0
    local function consider(prop)
        local pname, ptype = "", ""
        pcall(function() pname = prop:GetFName():ToString() end)
        pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
        if ptype ~= "TextProperty" and ptype ~= "StrProperty" then return end
        local base = (pname:match("^(.-)_%d+_%x+$") or pname):lower()
        local score = 0
        if base == "name" or base == "itemname" or base == "displayname" then
            score = 3
        elseif base:find("name", 1, true) and not base:find("desc", 1, true) then
            score = 2
        end
        if score > 0 and ptype == "TextProperty" then score = score + 0.5 end
        if score > bestScore then best, bestScore = pname, score end
    end
    pcall(forEachProperty, consider)
    return best
end

-- Gives every row a unique label. Items sharing a name get their row number
-- ("Poster 3") or category ("Bandage (Resource)"); anything left gets "#2".
function ItemMenu.MakeUniqueLabels(names)
    local groups = {}
    for row, name in pairs(names) do
        local key = name:lower()
        groups[key] = groups[key] or {}
        table.insert(groups[key], row)
    end
    local labels = {}
    for _, rows in pairs(groups) do
        local unnumbered = 0
        for _, row in ipairs(rows) do
            if not row:match("_(%d+)$") then unnumbered = unnumbered + 1 end
        end
        for _, row in ipairs(rows) do
            local label = names[row]
            if #rows > 1 then
                local num = row:match("_(%d+)$")
                if num then
                    label = label .. " " .. num
                elseif unnumbered > 1 then
                    label = label .. " (" .. (row:match("^([^_]+)_") or row) .. ")"
                end
            end
            labels[row] = label
        end
    end
    local sortedRows = {}
    for row in pairs(labels) do table.insert(sortedRows, row) end
    table.sort(sortedRows)
    local rowToLabel, labelToRow, taken = {}, {}, {}
    for _, row in ipairs(sortedRows) do
        local label, k = labels[row], 2
        while taken[label:lower()] or label == ItemMenu.NO_MATCH do
            label = labels[row] .. " #" .. k
            k = k + 1
        end
        taken[label:lower()] = true
        rowToLabel[row], labelToRow[label] = label, row
    end
    return rowToLabel, labelToRow
end

function ItemMenu.BuildNames()
    if ItemMenu.rowToLabel then return true end
    local dt = GetMasterItemList()
    if not dt then return false end
    local field = ItemMenu.FindNameField(function(cb) dt.RowStruct:ForEachProperty(cb) end)
    if not field then
        local firstRow = nil
        pcall(function()
            dt:ForEachRow(function(_, rowData) firstRow = firstRow or rowData end)
        end)
        if firstRow then
            field = ItemMenu.FindNameField(function(cb) firstRow:ForEachProperty(cb) end)
        end
    end
    local names, fromField = {}, 0
    pcall(function()
        dt:ForEachRow(function(rowName, rowData)
            local row = ItemMenu.Str(rowName) or tostring(rowName)
            local name = nil
            if field then pcall(function() name = ItemMenu.Str(rowData[field]) end) end
            if name then name = name:match("^%s*(.-)%s*$") end
            if name and name ~= "" then
                fromField = fromField + 1
            else
                name = ItemMenu.Prettify(row)
            end
            names[row] = name
        end)
    end)
    if next(names) == nil then return false end
    ItemMenu.rowToLabel, ItemMenu.labelToRow = ItemMenu.MakeUniqueLabels(names)
    Log("[ItemMenu] Item names: " .. fromField .. " from the game (" .. tostring(field) .. "), "
        .. "the rest from their IDs")
    return true
end

function ItemMenu.LabelFor(rowName)
    return (ItemMenu.rowToLabel and ItemMenu.rowToLabel[rowName]) or rowName
end

-- Menu option (in-game name or raw row name) -> row name
function ItemMenu.ResolveRow(option)
    if type(option) ~= "string" or option == "" or option == "None" or option == "Empty"
       or option == ItemMenu.NO_MATCH or option:find("^BP_") then
        return nil
    end
    return (ItemMenu.labelToRow and ItemMenu.labelToRow[option]) or option
end

-- ---------- the menu's item list ----------

function ItemMenu.Options(combo)
    local list = {}
    pcall(function()
        for i = 0, combo:GetOptionCount() - 1 do
            local opt = ItemMenu.Str(combo:GetOptionAtIndex(i))
            if opt then table.insert(list, opt) end
        end
    end)
    return list
end

function ItemMenu.Selected(combo)
    local s = nil
    pcall(function() s = ItemMenu.Str(combo:GetSelectedOption()) end)
    return s
end

function ItemMenu.Signature(combo)
    local n, first, last = 0, "", ""
    pcall(function()
        n = combo:GetOptionCount()
        if n > 0 then
            first = ItemMenu.Str(combo:GetOptionAtIndex(0)) or ""
            last = ItemMenu.Str(combo:GetOptionAtIndex(n - 1)) or ""
        end
    end)
    return n .. "\31" .. first .. "\31" .. last
end

-- The item list is the menu combo whose options are MasterItemList rows
-- (the AI list holds BP_* class names).
function ItemMenu.IsItemCombo(combo)
    local opts = ItemMenu.Options(combo)
    for i = 1, math.min(#opts, 20) do
        local opt = opts[i]
        if opt == ItemMenu.NO_MATCH
           or (ItemMenu.rowToLabel and ItemMenu.rowToLabel[opt])
           or (ItemMenu.labelToRow and ItemMenu.labelToRow[opt]) then
            return true
        end
    end
    return false
end

-- Live WD_CheatMenu item ComboBoxString (cached while valid)
function ItemMenu.FindCombo()
    if ItemMenu.IsValid(ItemMenu.combo) then return ItemMenu.combo end
    ItemMenu.combo, ItemMenu.appliedSig = nil, nil
    if not ItemMenu.BuildNames() then return nil end
    local cm = GetCheatMenuWidget()
    local cmPath = ItemMenu.IsValid(cm) and ItemMenu.PathOf(cm) or nil
    for _, cb in ipairs(FindAllOf("ComboBoxString") or {}) do
        local fn = ""
        pcall(function() fn = cb:GetFullName() end)
        -- skip the class template (".._C:WidgetTree..") and other HUD instances
        if fn:find("WD_CheatMenu", 1, true) and not fn:find("WD_CheatMenu_C:WidgetTree", 1, true)
           and (cmPath == nil or fn:find(cmPath, 1, true)) and ItemMenu.IsItemCombo(cb) then
            if ItemMenu.cheatMenuPath ~= cmPath then
                -- new HUD (level load): its search box has to be made again
                ItemMenu.searchBox, ItemMenu.searchFailed, ItemMenu.lastBoxText = nil, false, ""
            end
            ItemMenu.combo, ItemMenu.cheatMenu, ItemMenu.cheatMenuPath = cb, cm, cmPath
            return cb
        end
    end
    return nil
end

-- Rewrites the item list: in-game names, sorted, filtered by `text`
-- (every word must appear in the name or the row ID). Returns the matching labels.
function ItemMenu.ApplyFilter(text)
    local combo = ItemMenu.FindCombo()
    if not combo or not ItemMenu.menuRows then return {} end
    ItemMenu.filterText = text or ""
    local terms = {}
    for t in ItemMenu.filterText:lower():gmatch("%S+") do table.insert(terms, t) end

    local labels = {}
    for _, row in ipairs(ItemMenu.menuRows) do
        local label = ItemMenu.LabelFor(row)
        local haystack = (label .. " " .. row):lower()
        local hit = true
        for _, t in ipairs(terms) do
            if not haystack:find(t, 1, true) then hit = false break end
        end
        if hit then table.insert(labels, label) end
    end
    table.sort(labels, function(a, b) return a:lower() < b:lower() end)

    local previousRow = ItemMenu.ResolveRow(ItemMenu.Selected(combo))
    pcall(function()
        combo:ClearOptions()
        if #labels == 0 then
            combo:AddOption(ItemMenu.NO_MATCH)
            combo:SetSelectedOption(ItemMenu.NO_MATCH)
            return
        end
        for _, label in ipairs(labels) do combo:AddOption(label) end
        -- searching picks the best match; otherwise keep what was selected
        local select = labels[1]
        if #terms == 0 and previousRow then
            local previousLabel = ItemMenu.LabelFor(previousRow)
            for _, label in ipairs(labels) do
                if label == previousLabel then select = label break end
            end
        end
        combo:SetSelectedOption(select)
    end)
    ItemMenu.appliedSig = ItemMenu.Signature(combo)
    return labels
end

-- Takes over the list whenever the game (re)fills it with row names.
function ItemMenu.EnsureLabels(combo)
    if ItemMenu.pending > 0 then return end
    if ItemMenu.Signature(combo) == ItemMenu.appliedSig then return end
    local rows, seen = {}, {}
    for _, row in ipairs(ItemMenu.menuRows or {}) do
        seen[row] = true
        table.insert(rows, row)
    end
    for _, opt in ipairs(ItemMenu.Options(combo)) do
        local row = ItemMenu.ResolveRow(opt)
        if row and not seen[row] then
            seen[row] = true
            table.insert(rows, row)
        end
    end
    -- Every item in the game's item table too, so items from newer patches
    -- show up even if the game's own list wasn't updated
    for row in pairs(ItemMenu.rowToLabel or {}) do
        if not seen[row] and row ~= "EmptyItem" then
            seen[row] = true
            table.insert(rows, row)
        end
    end
    if #rows == 0 then return end
    ItemMenu.menuRows = rows
    ItemMenu.ApplyFilter(ItemMenu.filterText)
end

-- ---------- search box ----------

-- Text setters take an FText; plain strings are the fallback for UE4SS
-- builds without the FText constructor.
function ItemMenu.SetBoxText(box, setter, text)
    local ok = pcall(function() box[setter](box, FText(text)) end)
    if not ok then pcall(function() box[setter](box, text) end) end
end

function ItemMenu.ClassName(obj)
    local name = ""
    pcall(function() name = obj:GetClass():GetFName():ToString() end)
    return name
end

-- The menu's amount field: an EditableTextBox of the live menu that isn't ours
function ItemMenu.IsAmountBoxName(fn)
    return fn:find("WD_CheatMenu", 1, true) and fn:find("_2147", 1, true)
        and not fn:find(ItemMenu.searchName, 1, true)
        and not (ItemMenu.searchPath and fn:find(ItemMenu.searchPath, 1, true))
end

function ItemMenu.FindAmountBox()
    for _, etb in ipairs(FindAllOf("EditableTextBox") or {}) do
        local fn = ""
        pcall(function() fn = etb:GetFullName() end)
        if ItemMenu.IsAmountBoxName(fn)
           and (not ItemMenu.cheatMenuPath or fn:find(ItemMenu.cheatMenuPath, 1, true)) then
            return etb
        end
    end
    return nil
end

-- A search box this menu already has (left over from before a mod reload)
function ItemMenu.FindExistingSearchBox()
    for _, etb in ipairs(FindAllOf("EditableTextBox") or {}) do
        local fn = ""
        pcall(function() fn = etb:GetFullName() end)
        if fn:find(ItemMenu.searchName, 1, true) and ItemMenu.IsValid(etb)
           and (not ItemMenu.cheatMenuPath or fn:find(ItemMenu.cheatMenuPath, 1, true)) then
            local parent = nil
            pcall(function() parent = etb:GetParent() end)
            if ItemMenu.IsValid(parent) then return etb end
        end
    end
    return nil
end

-- Layout of a VerticalBox slot, so a widget can be taken out and put back
function ItemMenu.ReadVBoxSlot(widget)
    local p = {}
    pcall(function()
        local pad = widget.Slot.Padding
        p.padding = { Left = pad.Left, Top = pad.Top, Right = pad.Right, Bottom = pad.Bottom }
    end)
    pcall(function()
        local size = widget.Slot.Size
        p.size = { SizeRule = size.SizeRule, Value = size.Value }
    end)
    pcall(function() p.hAlign = widget.Slot.HorizontalAlignment end)
    pcall(function() p.vAlign = widget.Slot.VerticalAlignment end)
    return p
end

function ItemMenu.ApplySlot(slot, p)
    if p.padding then pcall(function() slot:SetPadding(p.padding) end) end
    if p.size then pcall(function() slot:SetSize(p.size) end) end
    if p.hAlign ~= nil then pcall(function() slot:SetHorizontalAlignment(p.hAlign) end) end
    if p.vAlign ~= nil then pcall(function() slot:SetVerticalAlignment(p.vAlign) end) end
end

-- The item column is a VerticalBox (title, list, SPAWN, amount) with the
-- Time row right below it, so an extra row would overlap Time. Instead the
-- amount row becomes [amount | search]; the amount field is far wider than
-- a number needs.
function ItemMenu.PlaceNextToAmount(box, vbox, amountBox, outer)
    if ItemMenu.ClassName(vbox) ~= "VerticalBox" or not ItemMenu.IsValid(amountBox) then return false end
    local index = -1
    pcall(function() index = vbox:GetChildIndex(amountBox) end)
    if type(index) ~= "number" or index < 0 then return false end
    local rowClass = StaticFindObject("/Script/UMG.HorizontalBox")
    if not ItemMenu.IsValid(rowClass) then return false end
    local row = nil
    pcall(function() row = StaticConstructObject(rowClass, outer, FName(ItemMenu.searchName .. "Row")) end)
    if not ItemMenu.IsValid(row) then pcall(function() row = StaticConstructObject(rowClass, outer) end) end
    if not ItemMenu.IsValid(row) then return false end

    -- take the amount field and everything after it out, then rebuild in order
    local moved = {}
    for i = index, vbox:GetChildrenCount() - 1 do
        local child = vbox:GetChildAt(i)
        table.insert(moved, { widget = child, slot = ItemMenu.ReadVBoxSlot(child) })
    end
    local ok, err = pcall(function()
        for _, m in ipairs(moved) do vbox:RemoveChild(m.widget) end
        ItemMenu.ApplySlot(vbox:AddChildToVerticalBox(row), moved[1].slot)
        for i = 2, #moved do
            ItemMenu.ApplySlot(vbox:AddChildToVerticalBox(moved[i].widget), moved[i].slot)
        end
        local FILL, SIZE_FILL = 0, 1
        ItemMenu.ApplySlot(row:AddChildToHorizontalBox(amountBox),
            { size = { SizeRule = SIZE_FILL, Value = 0.3 }, hAlign = FILL, vAlign = FILL })
        ItemMenu.ApplySlot(row:AddChildToHorizontalBox(box),
            { size = { SizeRule = SIZE_FILL, Value = 0.7 }, hAlign = FILL, vAlign = FILL,
              padding = { Left = 6, Top = 0, Right = 0, Bottom = 0 } })
    end)
    if not ok then
        -- put the column back exactly as it was
        pcall(function() row:RemoveFromParent() end)
        for _, m in ipairs(moved) do pcall(function() m.widget:RemoveFromParent() end) end
        for _, m in ipairs(moved) do
            pcall(function() ItemMenu.ApplySlot(vbox:AddChildToVerticalBox(m.widget), m.slot) end)
        end
        error("rebuilding the amount row failed: " .. tostring(err))
    end
    Log("[ItemMenu] Search box added next to the amount field")
    return true
end

function ItemMenu.EnsureSearchBox(combo)
    if ItemMenu.IsValid(ItemMenu.searchBox) then return ItemMenu.searchBox end
    ItemMenu.searchBox = nil
    if ItemMenu.searchFailed then return nil end
    local existing = ItemMenu.FindExistingSearchBox()
    if existing then
        ItemMenu.searchBox, ItemMenu.searchPath, ItemMenu.lastBoxText = existing, ItemMenu.PathOf(existing), ""
        return existing
    end
    local ok, err = pcall(function()
        local cls = StaticFindObject("/Script/UMG.EditableTextBox")
        local parent = combo:GetParent()
        if not ItemMenu.IsValid(cls) or not ItemMenu.IsValid(parent) then
            error("no EditableTextBox class or item list parent")
        end
        local outer = nil
        pcall(function() outer = ItemMenu.cheatMenu.WidgetTree end)
        if not ItemMenu.IsValid(outer) then outer = parent end
        local box = nil
        pcall(function() box = StaticConstructObject(cls, outer, FName(ItemMenu.searchName)) end)
        if not ItemMenu.IsValid(box) then box = StaticConstructObject(cls, outer) end
        if not ItemMenu.IsValid(box) then error("StaticConstructObject failed") end
        ItemMenu.searchPath = ItemMenu.PathOf(box)
        -- default style: copying the amount field's style struct isn't safe through UE4SS
        local amountBox = ItemMenu.FindAmountBox()
        ItemMenu.SetBoxText(box, "SetHintText", "Search...")

        local parentClass = ItemMenu.ClassName(parent)
        if ItemMenu.PlaceNextToAmount(box, parent, amountBox, outer) then
            -- placed
        elseif parentClass == "VerticalBox" then
            error("amount field not found in the item column")
        elseif parentClass == "CanvasPanel" then
            -- same width as the item list, directly above it
            local slot = parent:AddChildToCanvas(box)
            local comboSlot = combo.Slot
            local pos, size = comboSlot:GetPosition(), comboSlot:GetSize()
            pcall(function()
                local a = comboSlot:GetAnchors()
                slot:SetAnchors({ Minimum = { X = a.Minimum.X, Y = a.Minimum.Y },
                                  Maximum = { X = a.Maximum.X, Y = a.Maximum.Y } })
            end)
            pcall(function()
                local al = comboSlot:GetAlignment()
                slot:SetAlignment({ X = al.X, Y = al.Y })
            end)
            slot:SetSize({ X = size.X, Y = size.Y })
            slot:SetPosition({ X = pos.X, Y = pos.Y - size.Y - 4 })
            pcall(function() slot:SetZOrder(100) end)
            Log(string.format("[ItemMenu] Search box added above the item list (list at %.0f,%.0f size %.0fx%.0f)",
                pos.X, pos.Y, size.X, size.Y))
        else
            parent:AddChild(box)
            Log("[ItemMenu] Search box added to the item list's " .. parentClass)
        end
        ItemMenu.searchBox = box
        ItemMenu.searchPath = ItemMenu.PathOf(box)
        ItemMenu.lastBoxText = ""
    end)
    if not ok then
        ItemMenu.searchFailed = true
        Log("[ItemMenu] Could not add the search box (" .. tostring(err) .. ")")
        Log("[ItemMenu] Search from the console instead: .find <name>")
    end
    return ItemMenu.searchBox
end

-- Runs every 250ms while the menu is open (game thread)
function ItemMenu.Tick()
    local combo = ItemMenu.FindCombo()
    if not combo then return end
    ItemMenu.EnsureLabels(combo)
    local box = ItemMenu.EnsureSearchBox(combo)
    if box and ItemMenu.pending == 0 then
        local text = nil
        pcall(function() text = ItemMenu.Str(box:GetText()) end)
        if text and text ~= ItemMenu.lastBoxText then
            ItemMenu.lastBoxText = text
            ItemMenu.ApplyFilter(text)
        end
    end
end

function ItemMenu.SafeTick()
    local ok, err = pcall(ItemMenu.Tick)
    if not ok and tostring(err) ~= ItemMenu.lastTickErr then
        ItemMenu.lastTickErr = tostring(err)
        Log("[ItemMenu] " .. tostring(err))
    end
end

-- ---------- modern look ----------
-- The menu is the game's own developer panel (stone frame, grey stock
-- buttons, black-on-black list). When it opens, its widgets are recoloured in
-- place: dark square panel, dark buttons with light text, a blue
-- SPAWN, readable list and fields. Nothing is added or moved, so every button
-- keeps working; anything the game refuses simply keeps its old look.
-- Set MenuStyle.enabled = false to keep the game's look.
local MenuStyle = {
    enabled = not (Coop.user and Coop.user.newLook == false),   -- config.lua: newLook = false for the game's colours
    donePath = nil,     -- cheat menu instance already styled
    searchDone = nil,   -- search box already styled
}
-- Steel blue on dark navy, like the Radiation Shield menu and the Mod Hub.
-- Unreal takes linear colours; the comments are the colours you see.
local MS_PANEL = { R = 0.006, G = 0.009, B = 0.015, A = 0.86 }   -- dark navy #121821, see-through
local MS_CLEAR = { R = 0, G = 0, B = 0, A = 0 }
local MS_SURFACE = { R = 0.018, G = 0.025, B = 0.037, A = 1 }   -- #252C36
local MS_SURFACE_HOVER = { R = 0.031, G = 0.043, B = 0.063, A = 1 }   -- #313A46
local MS_SURFACE_DOWN = { R = 0.011, G = 0.015, B = 0.023, A = 1 }
local MS_FIELD = { R = 0.004, G = 0.006, B = 0.009, A = 1 }   -- #0C1117
local MS_LINE = { R = 0.6, G = 0.7, B = 0.85, A = 0.10 }   -- faint outline
local MS_ACCENT = { R = 0.212, G = 0.445, B = 0.783, A = 1 }   -- steel blue #7FB2E5
local MS_ACCENT_HOVER = { R = 0.323, G = 0.552, B = 0.855, A = 1 }   -- #9AC4EE
local MS_ACCENT_DOWN = { R = 0.111, G = 0.287, B = 0.584, A = 1 }   -- #5E93C9
local MS_CHIP = { R = 0.651, G = 0.701, B = 0.768, A = 1 }   -- #D3DAE3: list buttons keep dark text
local MS_CHIP_HOVER = { R = 0.776, G = 0.815, B = 0.863, A = 1 }   -- #E4E9EF
local MS_WHITE = { R = 0.791, G = 0.831, B = 0.888, A = 1 }   -- cool white #E6EBF2
local MS_LABEL = { R = 0.491, G = 0.552, B = 0.637, A = 1 }   -- #BAC4D1
local MS_HEADING = { R = 0.205, G = 0.275, B = 0.381, A = 1 }   -- grey-blue #7D8FA6
local MS_MUTED = { R = 0.168, G = 0.212, B = 0.275, A = 1 }   -- #727F8F
local MS_INK = { R = 0.004, G = 0.006, B = 0.010, A = 1 }   -- dark text on blue

local function MsSetColor(target, c)
    target.R, target.G, target.B, target.A = c.R, c.G, c.B, c.A
end

local function MsSlateColor(slateColor, c)
    pcall(function() MsSetColor(slateColor.SpecifiedColor, c) end)
    pcall(function() slateColor.ColorUseRule = 0 end)   -- use the specified colour
end

-- Edits a brush where it lives: flat colour, rounded corners, optional outline
local function MsBrush(brush, color, radius, outline)
    if brush == nil then return end
    radius = 0   -- square look; kept as a switch should rounded corners come back
    pcall(function() brush.DrawAs = 4 end)              -- RoundedBox
    pcall(function()
        local o = brush.OutlineSettings
        o.RoundingType = 0
        local r = o.CornerRadii
        r.X, r.Y, r.Z, r.W = radius, radius, radius, radius
        o.Width = outline and 1.0 or 0.0
        if outline then MsSlateColor(o.Color, outline) end
    end)
    MsSlateColor(brush.TintColor, color)
end

local function MsClassName(w)
    local name = ""
    pcall(function() name = w:GetClass():GetFName():ToString() end)
    return name
end

local function MsText(w)
    local s = ""
    pcall(function() s = w:GetText():ToString() end)
    return s
end

local function MsFont(text, size, bold)
    pcall(function()
        local font = text.Font
        font.Size = size
        if bold ~= nil then font.TypefaceFontName = FName(bold and "Bold" or "Regular") end
        text:SetFont(font)
    end)
end

local function MsTextColor(text, c)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
    pcall(function() text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0 }) end)
end

local function MsButton(btn, primary)
    local style = btn.WidgetStyle
    if primary then
        MsBrush(style.Normal, MS_ACCENT, 8)
        MsBrush(style.Hovered, MS_ACCENT_HOVER, 8)
        MsBrush(style.Pressed, MS_ACCENT_DOWN, 8)
    else
        MsBrush(style.Normal, MS_SURFACE, 8, MS_LINE)
        MsBrush(style.Hovered, MS_SURFACE_HOVER, 8, MS_LINE)
        MsBrush(style.Pressed, MS_SURFACE_DOWN, 8, MS_ACCENT)
    end
    MsBrush(style.Disabled, MS_SURFACE_DOWN, 8)
    pcall(function() btn:SetBackgroundColor({ R = 1, G = 1, B = 1, A = 1 }) end)   -- no extra grey tint
    pcall(function() btn:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
end

local function MsCombo(combo)
    local style = combo.WidgetStyle
    pcall(function()
        local b = style.ComboButtonStyle.ButtonStyle
        MsBrush(b.Normal, MS_CHIP, 6)
        MsBrush(b.Hovered, MS_CHIP_HOVER, 6)
        MsBrush(b.Pressed, MS_CHIP, 6, MS_ACCENT)
    end)
    pcall(function() MsBrush(style.ComboButtonStyle.MenuBorderBrush, MS_FIELD, 8, MS_LINE) end)
    -- the drop-down rows: dark, light text, blue selection
    pcall(function()
        local rows = combo.ItemStyle
        for _, k in ipairs({ "EvenRowBackgroundBrush", "OddRowBackgroundBrush" }) do
            pcall(function() MsBrush(rows[k], MS_FIELD, 0) end)
        end
        for _, k in ipairs({ "EvenRowBackgroundHoveredBrush", "OddRowBackgroundHoveredBrush", "InactiveHoveredBrush" }) do
            pcall(function() MsBrush(rows[k], MS_SURFACE_HOVER, 4) end)
        end
        for _, k in ipairs({ "ActiveBrush", "ActiveHoveredBrush", "InactiveBrush", "SelectorFocusedBrush" }) do
            pcall(function() MsBrush(rows[k], MS_ACCENT, 4) end)
        end
        MsSlateColor(rows.TextColor, MS_LABEL)
        MsSlateColor(rows.SelectedTextColor, MS_INK)
    end)
    pcall(function()
        local bar = combo.ScrollBarStyle
        for _, k in ipairs({ "NormalThumbImage", "HoveredThumbImage", "DraggedThumbImage" }) do
            pcall(function() MsBrush(bar[k], MS_LINE, 3) end)
        end
        for _, k in ipairs({ "VerticalBackgroundImage", "VerticalTopSlotImage", "VerticalBottomSlotImage" }) do
            pcall(function() MsBrush(bar[k], MS_CLEAR, 0) end)
        end
    end)
    pcall(function() combo.Font.Size = 12 end)   -- used for rows made from now on
end

local function MsField(box)
    local style = box.WidgetStyle
    MsBrush(style.BackgroundImageNormal, MS_FIELD, 6, MS_LINE)
    MsBrush(style.BackgroundImageHovered, MS_FIELD, 6, MS_MUTED)
    MsBrush(style.BackgroundImageFocused, MS_FIELD, 6, MS_ACCENT)
    MsBrush(style.BackgroundImageReadOnly, MS_FIELD, 6)
    pcall(function() MsSlateColor(style.ForegroundColor, MS_WHITE) end)
    pcall(function() MsSlateColor(style.BackgroundColor, { R = 1, G = 1, B = 1, A = 1 }) end)
    pcall(function() MsSlateColor(style.TextStyle.ColorAndOpacity, MS_WHITE) end)
    pcall(function() box:SetForegroundColor(MS_WHITE) end)
end

local function MsSpin(spin)
    local style = spin.WidgetStyle
    MsBrush(style.BackgroundBrush, MS_FIELD, 6, MS_LINE)
    MsBrush(style.HoveredBackgroundBrush, MS_FIELD, 6, MS_MUTED)
    pcall(function() MsBrush(style.ActiveBackgroundBrush, MS_FIELD, 6, MS_ACCENT) end)
    MsBrush(style.ActiveFillBrush, { R = 0.212, G = 0.445, B = 0.783, A = 0.35 }, 6)
    pcall(function() MsBrush(style.HoveredFillBrush, { R = 0.212, G = 0.445, B = 0.783, A = 0.25 }, 6) end)
    MsBrush(style.InactiveFillBrush, MS_CLEAR, 6)
    pcall(function() MsSlateColor(style.ForegroundColor, MS_WHITE) end)
    pcall(function() spin:SetForegroundColor({ SpecifiedColor = MS_WHITE, ColorUseRule = 0 }) end)
end

-- Background pictures (the stone frame): the outermost becomes the dark
-- rounded panel, any inner ones go clear so the panel shows through.
local function MsBackground(w, outermost)
    local color = outermost and MS_PANEL or MS_CLEAR
    pcall(function() w:SetBrushFromTexture(nil) end)           -- flat colour where the game allows it
    if MsClassName(w) == "Border" then
        pcall(function() MsBrush(w.Background, color, 14, outermost and MS_LINE or nil) end)
        pcall(function() w:SetBrushColor(color) end)
    else
        pcall(function() MsBrush(w.Brush, color, 14, outermost and MS_LINE or nil) end)
        -- tints the texture too if it couldn't be removed: dark, not stone
        pcall(function() w:SetColorAndOpacity(color) end)
    end
end

function MenuStyle.Walk(w, inButton, counts, depth)
    if depth > 30 or not ItemMenu.IsValid(w) then return end
    local cls = MsClassName(w)
    if cls == "Button" then
        local label = ""
        pcall(function() label = MsText(w:GetChildAt(0)) end)
        local primary = label:upper() == "SPAWN"
        pcall(MsButton, w, primary)
        counts.buttons = counts.buttons + 1
        inButton = primary and "primary" or "button"
    elseif cls == "ComboBoxString" then
        pcall(MsCombo, w)
        counts.lists = counts.lists + 1
    elseif cls == "EditableTextBox" then
        pcall(MsField, w)
        counts.fields = counts.fields + 1
    elseif cls == "SpinBox" then
        pcall(MsSpin, w)
        counts.fields = counts.fields + 1
    elseif cls == "Image" or (cls == "Border" and not inButton) then
        pcall(MsBackground, w, counts.backgrounds == 0)
        counts.backgrounds = counts.backgrounds + 1
    elseif cls == "TextBlock" then
        local text = MsText(w)
        if inButton == "primary" then
            MsFont(w, 14, true)
            MsTextColor(w, MS_INK)
        elseif inButton then
            MsFont(w, 13, true)
            MsTextColor(w, MS_WHITE)
        elseif #text > 24 then          -- hints like "Scroll the mouse wheel ..."
            MsFont(w, 10, false)
            MsTextColor(w, MS_MUTED)
        else                            -- section labels: Spawn Item, Time, Weather ...
            MsFont(w, 13, true)
            MsTextColor(w, MS_LABEL)
        end
        counts.texts = counts.texts + 1
    end
    local n = 0
    pcall(function() n = w:GetChildrenCount() end)
    for i = 0, (tonumber(n) or 0) - 1 do
        local child = nil
        pcall(function() child = w:GetChildAt(i) end)
        if child then MenuStyle.Walk(child, inButton, counts, depth + 1) end
    end
end

-- Game thread. Styles the live menu once (and again after a level load
-- gives the HUD a new menu).
function MenuStyle.Apply()
    if not MenuStyle.enabled then return end
    local cm = GetCheatMenuWidget()
    if not ItemMenu.IsValid(cm) then return end
    local path = ItemMenu.PathOf(cm)
    if path == MenuStyle.donePath then return end
    MenuStyle.donePath = path
    local counts = { buttons = 0, lists = 0, fields = 0, texts = 0, backgrounds = 0 }
    local ok, err = pcall(function()
        MenuStyle.Walk(cm.WidgetTree.RootWidget, nil, counts, 0)
    end)
    if not ok then
        Log("[MenuStyle] " .. tostring(err))
        return
    end
    pcall(function() cm:InvalidateLayoutAndVolatility() end)
    Log(string.format("[MenuStyle] Menu restyled: %d buttons, %d lists, %d fields, %d texts, %d backgrounds",
        counts.buttons, counts.lists, counts.fields, counts.texts, counts.backgrounds))
end

-- .menudump: the menu's widgets, for layout work
function MenuStyle.Dump(w, depth)
    if depth > 30 or not ItemMenu.IsValid(w) then return end
    local cls = MsClassName(w)
    local name = ""
    pcall(function() name = w:GetFName():ToString() end)
    local text = cls == "TextBlock" and ("  \"" .. MsText(w) .. "\"") or ""
    Log("[MenuDump] " .. string.rep("  ", depth) .. cls .. " " .. name .. text)
    local n = 0
    pcall(function() n = w:GetChildrenCount() end)
    for i = 0, (tonumber(n) or 0) - 1 do
        local child = nil
        pcall(function() child = w:GetChildAt(i) end)
        if child then MenuStyle.Dump(child, depth + 1) end
    end
end

-- The search box can be added after the menu was styled
function MenuStyle.StyleSearchBox()
    if not MenuStyle.enabled or not ItemMenu.IsValid(ItemMenu.searchBox) then return end
    if ItemMenu.searchPath == MenuStyle.searchDone then return end
    MenuStyle.searchDone = ItemMenu.searchPath
    pcall(MsField, ItemMenu.searchBox)
end

RegisterConsoleCommandHandler(".menudump", function()
    ExecuteInGameThread(function()
        local cm = GetCheatMenuWidget()
        if not ItemMenu.IsValid(cm) then
            Log("[MenuDump] No menu yet - load into a world first")
            return
        end
        MenuStyle.Dump(cm.WidgetTree.RootWidget, 0)
    end)
    return true
end)

-- ---------- layout ----------
-- The game places its widgets by hand on a big stone frame, so labels and
-- fields overlap and the buttons float around. After styling, the same
-- widgets (not copies: their clicks, hooks and values stay the game's) are
-- moved into a tidy panel like the Radiation Shield menu:
--
--   Mod Menu                      (Backspace closes)
--   SPAWN ITEM    [ item list                       ]
--                 [ 1 ][ Search...       ][ Spawn ]
--   SPAWN ENEMY   [ enemy list          ][ Spawn ]
--   TIME          Time [ 0 ]  Day [ 1 ]  Month [ 1 ]
--                 [ Sunny ][ Rain ][ Thunder ]
--   EVENTS        [ Summon plane ][ Summon Grad ]
--                 [ Skip 1 emission ][ Skip 5 emissions ]
--   MOVEMENT      [ Fly ]  scroll the mouse wheel to change speed
--
-- Widgets it doesn't recognise go in an "Other" card, so nothing is lost.
-- If anything fails before the move, the game's layout is left as it was.
-- config.lua: newLayout = false keeps the game's layout
local MenuLayout = { enabled = not (Coop.user and Coop.user.newLayout == false), donePath = nil }
local ML_WIDTH = 500
local ML_CARD = { R = 1, G = 1, B = 1, A = 0 }   -- no box behind sections
local ML_PANEL = { R = 0.006, G = 0.009, B = 0.015, A = 0.86 }   -- dark navy #121821, see-through
local ML_BAND = { R = 0.212, G = 0.445, B = 0.783, A = 0.07 }   -- faint blue behind the title
local ML_LABELS = {   -- button texts as the game writes them -> as shown
    SPAWN = "Spawn", FLY = "Fly", SUNNY = "Sunny", RAIN = "Rain", THUNDER = "Thunder",
    ["SUMMON PLANE"] = "Summon plane", ["SUMMON GRAD"] = "Summon Grad",
    ["SKIP 1 EMISSION"] = "Skip 1 emission", ["SKIP 5 EMISSION"] = "Skip 5 emissions",
}

local function MlNew(tree, cls)
    local c = StaticFindObject("/Script/UMG." .. cls)
    if not ItemMenu.IsValid(c) then error(cls .. " class not found", 0) end
    local w = StaticConstructObject(c, tree)
    if not ItemMenu.IsValid(w) then error("could not create " .. cls, 0) end
    return w
end

local function MlSetText(text, s)
    if not pcall(function() text:SetText(FText(s)) end) then pcall(function() text:SetText(s) end) end
end

local function MlText(tree, s, size, color, bold, spacing)
    local t = MlNew(tree, "TextBlock")
    pcall(function() t.Font.Size = size end)
    if bold then pcall(function() t.Font.TypefaceFontName = FName("Bold") end) end
    if spacing then pcall(function() t.Font.LetterSpacing = spacing end) end
    MsTextColor(t, color)
    MlSetText(t, s)
    return t
end

local function MlPad(slot, l, t, r, b)
    pcall(function() slot:SetPadding({ Left = l, Top = t, Right = r, Bottom = b }) end)
    return slot
end
local function MlFill(slot, value)
    pcall(function() slot:SetSize({ SizeRule = 1, Value = value or 1.0 }) end)
    return slot
end
local function MlMiddle(slot) pcall(function() slot:SetVerticalAlignment(2) end) return slot end

local function MlBox(tree, w, h, child)
    local box = MlNew(tree, "SizeBox")
    if w then box:SetWidthOverride(w) end
    if h then box:SetHeightOverride(h) end
    if child then box:SetContent(child) end
    return box
end

-- Everything in the menu, sorted by what it is
function MenuLayout.Collect(root)
    local f = { buttons = {}, combos = {}, spins = {}, boxes = {}, texts = {}, backgrounds = {} }
    local function walk(w, depth)
        if depth > 30 or not ItemMenu.IsValid(w) then return end
        local cls = MsClassName(w)
        local item = { w = w, path = ItemMenu.PathOf(w), parent = "" }
        pcall(function() item.parent = ItemMenu.PathOf(w:GetParent()) end)
        if cls == "Button" then
            pcall(function() item.text = w:GetChildAt(0) end)
            item.label = item.text and MsText(item.text) or ""
            table.insert(f.buttons, item)
            return
        elseif cls == "ComboBoxString" then table.insert(f.combos, item) return
        elseif cls == "SpinBox" then table.insert(f.spins, item) return
        elseif cls == "EditableTextBox" then table.insert(f.boxes, item) return
        elseif cls == "TextBlock" then
            item.label = MsText(w)
            table.insert(f.texts, item)
            return
        elseif cls == "Image" or cls == "Border" then
            table.insert(f.backgrounds, item)
        end
        local n = 0
        pcall(function() n = w:GetChildrenCount() end)
        for i = 0, (tonumber(n) or 0) - 1 do
            local child = nil
            pcall(function() child = w:GetChildAt(i) end)
            if child then walk(child, depth + 1) end
        end
    end
    walk(root, 0)
    return f
end

-- Works out which widget is which. Returns the plan, or nil and why.
function MenuLayout.Plan(f)
    local p = { weather = {}, events = {}, other = {} }
    local itemPath = ItemMenu.IsValid(ItemMenu.combo) and ItemMenu.PathOf(ItemMenu.combo) or nil
    for _, c in ipairs(f.combos) do
        if c.path == itemPath or (not itemPath and not p.itemList) then p.itemList = c
        elseif not p.enemyList then p.enemyList = c
        else table.insert(p.other, c) end
    end
    if not p.itemList then return nil, "item list not found" end

    for _, b in ipairs(f.buttons) do
        local key = b.label:upper():gsub("^%s+", ""):gsub("%s+$", "")
        b.key = key
        if key == "SPAWN" then
            -- the item Spawn sits with the item list; the other is for enemies
            if not p.itemSpawn and b.parent == p.itemList.parent then p.itemSpawn = b
            else table.insert(p.other, b) end
        elseif key == "FLY" then p.fly = b
        elseif key == "SUNNY" or key == "RAIN" or key == "THUNDER" then table.insert(p.weather, b)
        elseif key:find("^SUMMON") or key:find("^SKIP") then table.insert(p.events, b)
        else table.insert(p.other, b) end
    end
    -- Spawn buttons not matched by their column: first is items, next enemies
    local rest = {}
    for _, b in ipairs(p.other) do
        if b.key == "SPAWN" and not p.itemSpawn then p.itemSpawn = b
        elseif b.key == "SPAWN" and not p.enemySpawn then p.enemySpawn = b
        else table.insert(rest, b) end
    end
    p.other = rest
    -- the enemy Spawn is the one left, whatever the column check said
    if p.enemyList and not p.enemySpawn then
        for i, b in ipairs(p.other) do
            if b.key == "SPAWN" then p.enemySpawn = table.remove(p.other, i) break end
        end
    end

    local searchPath = ItemMenu.searchPath
    local amount = ItemMenu.FindAmountBox()
    local amountPath = amount and ItemMenu.PathOf(amount) or nil
    for _, b in ipairs(f.boxes) do
        if b.path == searchPath then p.search = b
        elseif b.path == amountPath or not p.amount then p.amount = b
        else table.insert(p.other, b) end
    end

    -- Time / Day / Month: the label sharing the field's row, else tree order
    local defaults = { "Time", "Day", "Month" }
    p.spins = {}
    for i, s in ipairs(f.spins) do
        local name = defaults[i] or "Value"
        for _, t in ipairs(f.texts) do
            if t.parent == s.parent and #t.label > 0 and #t.label <= 12 then name = t.label end
        end
        s.name = name
        table.insert(p.spins, s)
    end
    for _, t in ipairs(f.texts) do
        if t.label:lower():find("mouse wheel", 1, true) then p.hint = t end
    end
    p.backgrounds = f.backgrounds
    return p
end

-- attach(panel) puts the new panel on screen before anything moves into it,
-- so a failure half way can't leave a widget somewhere invisible
function MenuLayout.Build(cm, p, attach)
    local tree = cm.WidgetTree
    local root = tree.RootWidget
    local L = {}

    -- panel
    L.panel = MlNew(tree, "Border")
    L.panel:SetBrushColor(ML_PANEL)
    MsBrush(L.panel.Background, { R = 1, G = 1, B = 1, A = 1 }, 14, MS_LINE)
    pcall(function() L.panel:SetPadding({ Left = 14, Top = 14, Right = 14, Bottom = 14 }) end)
    local width = MlNew(tree, "SizeBox")
    pcall(function() width:SetWidthOverride(ML_WIDTH) end)
    L.panel:SetContent(width)
    local column = MlNew(tree, "VerticalBox")
    width:SetContent(column)
    attach(L.panel)

    -- header: tinted band with the accent bar, title in capitals
    local band = MlNew(tree, "Border")
    band:SetBrushColor(ML_BAND)
    pcall(function() band:SetPadding({ Left = 0, Top = 10, Right = 12, Bottom = 10 }) end)
    column:AddChildToVerticalBox(band)
    local head = MlNew(tree, "HorizontalBox")
    band:SetContent(head)
    local bar = MlNew(tree, "Border")
    bar:SetBrushColor(MS_ACCENT)
    MlMiddle(head:AddChildToHorizontalBox(MlBox(tree, 3, 34, bar)))
    local titles = MlNew(tree, "VerticalBox")
    MlMiddle(MlFill(MlPad(head:AddChildToHorizontalBox(titles), 12, 0, 0, 0)))
    titles:AddChildToVerticalBox(MlText(tree, "MOD MENU", 17, { R = 1, G = 1, B = 1, A = 1 }, true, 120))
    titles:AddChildToVerticalBox(MlText(tree, "BACKSPACE TO CLOSE", 9, MS_HEADING, true, 200))

    local card
    local function Section(title)
        MlPad(column:AddChildToVerticalBox(MlText(tree, title, 9, MS_HEADING, true, 200)), 6, 14, 0, 6)
        local frame = MlNew(tree, "Border")
        frame:SetBrushColor(ML_CARD)
        MsBrush(frame.Background, { R = 1, G = 1, B = 1, A = 1 }, 10)
        pcall(function() frame:SetPadding({ Left = 10, Top = 10, Right = 10, Bottom = 10 }) end)
        column:AddChildToVerticalBox(frame)
        card = MlNew(tree, "VerticalBox")
        frame:SetContent(card)
    end
    -- one row of the card: items = { {item, width or nil (= share the rest)}, ... }
    local function Row(items, height)
        local row = MlNew(tree, "HorizontalBox")
        MlPad(card:AddChildToVerticalBox(row), 0, card:GetChildrenCount() > 1 and 8 or 0, 0, 0)
        for i, it in ipairs(items) do
            local holder = MlBox(tree, it[2], height)
            local slot = row:AddChildToHorizontalBox(holder)
            if not it[2] then MlFill(slot, it[3]) end
            MlMiddle(MlPad(slot, i > 1 and 8 or 0, 0, 0, 0))
            if it[1].w then
                it[1].w:RemoveFromParent()
                holder:SetContent(it[1].w)
                it[1].moved = true
            else
                holder:SetContent(it[1])   -- one of our own texts
            end
        end
        return row
    end
    local function Relabel(b)
        if b and b.text and ML_LABELS[b.key] then MlSetText(b.text, ML_LABELS[b.key]) end
    end

    Section("SPAWN ITEM")
    Row({ { p.itemList } }, 34)
    local spawnRow = {}
    if p.amount then table.insert(spawnRow, { p.amount, 64 }) end
    if p.search then table.insert(spawnRow, { p.search }) end
    if p.itemSpawn then table.insert(spawnRow, { p.itemSpawn, 104 }) end
    if #spawnRow > 0 then Row(spawnRow, 34) end
    Relabel(p.itemSpawn)

    if p.enemyList or p.enemySpawn then
        Section("SPAWN ENEMY")
        local r = {}
        if p.enemyList then table.insert(r, { p.enemyList }) end
        if p.enemySpawn then table.insert(r, { p.enemySpawn, 104 }) end
        Row(r, 34)
        Relabel(p.enemySpawn)
    end

    if #p.spins > 0 or #p.weather > 0 then
        Section("TIME AND WEATHER")
        if #p.spins > 0 then
            -- labels take only their own width, the fields share the rest
            local row = MlNew(tree, "HorizontalBox")
            MlPad(card:AddChildToVerticalBox(row), 0, 0, 0, 0)
            for i, s in ipairs(p.spins) do
                local label = MlText(tree, s.name, 12, MS_LABEL, true)
                MlMiddle(MlPad(row:AddChildToHorizontalBox(label), i > 1 and 14 or 0, 0, 8, 0))
                local holder = MlBox(tree, nil, 30)
                MlMiddle(MlFill(row:AddChildToHorizontalBox(holder)))
                s.w:RemoveFromParent()
                holder:SetContent(s.w)
                s.moved = true
            end
        end
        if #p.weather > 0 then
            local r = {}
            for _, b in ipairs(p.weather) do table.insert(r, { b }) Relabel(b) end
            Row(r, 32)
        end
    end

    if #p.events > 0 then
        Section("EVENTS")
        for i = 1, #p.events, 2 do
            local r = { { p.events[i] } }
            if p.events[i + 1] then table.insert(r, { p.events[i + 1] }) end
            for _, it in ipairs(r) do Relabel(it[1]) end
            Row(r, 32)
        end
    end

    if p.fly then
        Section("MOVEMENT")
        Relabel(p.fly)
        local r = { { p.fly, 120 } }
        if p.hint then
            MlSetText(p.hint.w, "Scroll the mouse wheel to change speed")
            table.insert(r, { p.hint })
        end
        Row(r, 32)
        if p.hint then
            MsFont(p.hint.w, 11, false)
            MsTextColor(p.hint.w, MS_MUTED)
        end
    end

    if #p.other > 0 then
        Section("OTHER")
        for i = 1, #p.other, 2 do
            local r = { { p.other[i] } }
            if p.other[i + 1] then table.insert(r, { p.other[i + 1] }) end
            Row(r, 32)
        end
    end
    return L
end

-- Moving the Time / Day / Month fields rebuilds them, and a rebuilt field
-- commits its value (0, 1, 1) - the game then sets 0:00 on the 1st. So the
-- weather manager's time and date values are saved before the move and any
-- the move changed are put back.
function MenuLayout.WeatherManager()
    local wm = nil
    pcall(function()
        local wms = FindAllOf("BP_MultiplayerDynamicWeatherManager_C")
        if wms and #wms > 0 and wms[1]:IsValid() then wm = wms[1] end
    end)
    return wm
end

local ML_NUMBER_PROPS = { FloatProperty = true, DoubleProperty = true, IntProperty = true, ByteProperty = true }
function MenuLayout.SaveClock()
    local wm = MenuLayout.WeatherManager()
    if not wm then return nil end
    local saved = {}
    pcall(function()
        local cls = wm:GetClass()
        for _ = 1, 10 do
            if not ItemMenu.IsValid(cls) then break end
            cls:ForEachProperty(function(prop)
                local name, kind = "", ""
                pcall(function() name = prop:GetFName():ToString() end)
                pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                local l = name:lower()
                if ML_NUMBER_PROPS[kind] and (l:find("time") or l:find("day") or l:find("month")
                    or l:find("date") or l:find("year") or l:find("season")) then
                    local v = nil
                    pcall(function() v = wm[name] end)
                    if type(v) == "number" then saved[name] = v end
                end
            end)
            local super = nil
            pcall(function() super = cls:GetSuperStruct() end)
            cls = super
        end
    end)
    return saved
end

function MenuLayout.RestoreClock(saved)
    if not saved then return end
    local wm = MenuLayout.WeatherManager()
    if not wm then return end
    local restored = {}
    for name, v in pairs(saved) do
        local now = nil
        pcall(function() now = wm[name] end)
        if type(now) == "number" and math.abs(now - v) > 1e-4 then
            pcall(function() wm[name] = v end)
            table.insert(restored, string.format("%s %.1f", name, v))
        end
    end
    if #restored == 0 then return end
    pcall(function() wm["Set Light Rotation"](wm) end)
    pcall(function() wm["Set Elements"](wm) end)
    table.sort(restored)
    Log("[MenuLayout] Moving the time fields reset the clock - put back: " .. table.concat(restored, ", "))
end

-- Game thread, after MenuStyle.Apply: once per menu instance
function MenuLayout.Apply()
    if not MenuLayout.enabled then return end
    local cm = GetCheatMenuWidget()
    if not ItemMenu.IsValid(cm) then return end
    local path = ItemMenu.PathOf(cm)
    if path == MenuLayout.donePath then return end
    MenuLayout.donePath = path

    local root, p, why, wrapper = nil, nil, nil, nil
    local ok, err = pcall(function()
        root = cm.WidgetTree.RootWidget
        -- the game wraps everything in its stone frame (a Border, maybe with more
        -- one-child wrappers): work in the first container holding several things
        for _ = 1, 6 do
            if root:GetChildrenCount() ~= 1 then break end
            if MsClassName(root) == "Border" and not wrapper then wrapper = root end
            root = root:GetChildAt(0)
        end
        if root:GetChildrenCount() < 1 then error("menu root " .. MsClassName(root) .. " holds nothing", 0) end
        p, why = MenuLayout.Plan(MenuLayout.Collect(root))
        if not p then error(why, 0) end
        -- every class we need, checked before anything moves
        for _, cls in ipairs({ "Border", "SizeBox", "VerticalBox", "HorizontalBox", "TextBlock" }) do
            if not ItemMenu.IsValid(StaticFindObject("/Script/UMG." .. cls)) then error(cls .. " class not found", 0) end
        end
    end)
    if not ok then
        Log("[MenuLayout] Keeping the game's layout (" .. tostring(err) .. ") - the menu's widgets follow:")
        pcall(MenuStyle.Dump, cm.WidgetTree.RootWidget, 0)
        return
    end

    -- remember where the frame was, to put the new panel there
    local frame = p.backgrounds[1]
    local geo = nil
    if wrapper then
        -- the frame holds the whole menu: the new panel goes in its top-left corner
        geo = { anchors = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } },
                alignment = { X = 0, Y = 0 }, position = { X = 0, Y = 0 } }
    end
    if not geo then pcall(function()
        local s = frame.w.Slot
        local a, al = s:GetAnchors(), s:GetAlignment()
        local pos = s:GetPosition()
        geo = { anchors = { Minimum = { X = a.Minimum.X, Y = a.Minimum.Y }, Maximum = { X = a.Minimum.X, Y = a.Minimum.Y } },
                alignment = { X = al.X, Y = al.Y }, position = { X = pos.X, Y = pos.Y } }
    end) end

    local panelPath = nil
    local function attach(panel)
        panelPath = ItemMenu.PathOf(panel)
        if MsClassName(root) ~= "CanvasPanel" then
            -- an Overlay or a box: the panel goes in its top-left corner
            local slot = root:AddChild(panel)
            pcall(function() slot:SetHorizontalAlignment(1) end)
            pcall(function() slot:SetVerticalAlignment(1) end)
            pcall(function() slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
            return
        end
        local slot = root:AddChildToCanvas(panel)
        pcall(function() slot:SetAutoSize(true) end)
        pcall(function() slot:SetZOrder(10) end)
        if geo then
            pcall(function() slot:SetAnchors(geo.anchors) end)
            pcall(function() slot:SetAlignment(geo.alignment) end)
            pcall(function() slot:SetPosition(geo.position) end)
        else
            pcall(function() slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }) end)
            pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
        end
    end

    local clock = MenuLayout.SaveClock()
    local built, err2 = pcall(MenuLayout.Build, cm, p, attach)
    MenuLayout.RestoreClock(clock)
    if not built then
        -- some widgets may already be in the new panel: show both rather than lose any
        Log("[MenuLayout] Layout failed part way (" .. tostring(err2) .. ") - nothing hidden")
        return
    end

    -- the old layout now only holds the frame, labels and empty boxes
    if wrapper then
        -- can't hide the frame (the new panel is inside it): make it see-through
        pcall(function() wrapper:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
        pcall(function() MsBrush(wrapper.Background, { R = 0, G = 0, B = 0, A = 0 }, 14) end)
        pcall(function() wrapper.Background.OutlineSettings.Width = 0.0 end)
        pcall(function() wrapper:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    end
    local n = 0
    pcall(function() n = root:GetChildrenCount() end)
    for i = 0, (tonumber(n) or 0) - 1 do
        pcall(function()
            local child = root:GetChildAt(i)
            if ItemMenu.PathOf(child) ~= panelPath then child:SetVisibility(1) end   -- collapsed
        end)
    end
    Log(string.format("[MenuLayout] Menu rearranged: %d buttons, %d fields, %d unrecognised kept under Other",
        #p.weather + #p.events + (p.fly and 1 or 0) + (p.itemSpawn and 1 or 0) + (p.enemySpawn and 1 or 0),
        #p.spins + (p.amount and 1 or 0) + (p.search and 1 or 0), #p.other))
end

OnCheatMenuShown = function()
    ItemMenu.SafeTick()
    MenuStyle.Apply()
    MenuStyle.StyleSearchBox()
    MenuLayout.Apply()
    if ItemMenu.polling then return end
    ItemMenu.polling = true
    LoopAsync(250, function()
        if not cheatMenuVisible then
            ItemMenu.polling = false
            return true
        end
        ExecuteInGameThread(function()
            ItemMenu.SafeTick()
            MenuStyle.StyleSearchBox()
        end)
        return false
    end)
end

-- ---------- spawning ----------

-- Amount field of the menu (the search box is an EditableTextBox too)
function ItemMenu.ReadAmount()
    local amount = 1
    for _, etb in ipairs(FindAllOf("EditableTextBox") or {}) do
        local fn = ""
        pcall(function() fn = etb:GetFullName() end)
        if ItemMenu.IsAmountBoxName(fn) then
            local txt = nil
            pcall(function() txt = etb:GetText():ToString() end)
            local n = tonumber(txt or "")
            if n and n >= 1 then amount = math.floor(n) end
        end
    end
    return amount
end

-- Old lookup, used when the item list can't be identified
function ItemMenu.LegacySelection()
    for _, cb in ipairs(FindAllOf("ComboBoxString") or {}) do
        local fname = ""
        pcall(function() fname = cb:GetFullName() end)
        if fname:find("WD_CheatMenu") then
            local s = ItemMenu.Selected(cb)
            if ItemMenu.ResolveRow(s) then return s end
        end
    end
    return nil
end

-- What the game's own Spawn code reads from the list for this click:
-- `option` (a row name) or nothing at all. Returns the undo.
function ItemMenu.TempSelect(combo, option, label)
    if not combo then return function() end end
    local added = false
    pcall(function()
        if option then
            if combo:FindOptionIndex(option) < 0 then
                combo:AddOption(option)
                added = true
            end
            combo:SetSelectedOption(option)
        else
            combo:ClearSelection()
        end
    end)
    return function()
        if not ItemMenu.IsValid(combo) then return end
        pcall(function()
            local current = ItemMenu.Selected(combo)
            if added then combo:RemoveOption(option) end
            if current == nil or current == "" or current == option then
                combo:SetSelectedOption(label)
            end
        end)
        ItemMenu.appliedSig = ItemMenu.Signature(combo)
    end
end

-- The menu's Spawn button runs the game's own spawn code as well as this
-- hook; both adding the item gave two of everything. Only one of them spawns:
--   game - the game's own spawn, handed the real row name (default)
--   mod  - the mod's factory spawn; the game's code is handed no selection
-- Nothing is counted: calling game functions with guessed parameters
-- (PlayerInventoryTotalItemAmount) crashed the game.
function ItemMenu.OnSpawnClicked()
    -- one click must never be handled twice
    local now = os.clock()
    if now - ItemMenu.lastClickAt < 0.15 then
        Log("[Spawn] duplicate click event ignored")
        return
    end
    ItemMenu.lastClickAt = now

    local combo = ItemMenu.FindCombo()
    local selected = combo and ItemMenu.Selected(combo) or ItemMenu.LegacySelection()
    local rowName = ItemMenu.ResolveRow(selected)
    if not rowName then
        Log("[Spawn] No item selected")
        return
    end
    local amount = ItemMenu.ReadAmount()
    local label = ItemMenu.LabelFor(rowName)

    local restore
    -- in someone else's world the host's Mod Menu adds it, unless .spawnmode game was chosen
    if _G.__SpawnMode == "mod" or (_G.__SpawnMode == nil and Coop.Joined()) then
        restore = ItemMenu.TempSelect(combo, nil, selected)
        Log("[Spawn] " .. label .. " x" .. amount .. " (mod spawn)")
        AddItemByRowName(rowName, amount)
    else
        -- the list shows in-game names; the game's spawn code needs the row name
        restore = ItemMenu.TempSelect(combo, rowName, selected)
        Log("[Spawn] " .. label .. " x" .. amount .. " (game spawn)")
    end
    -- the game's code may read the list a little after the click; show the
    -- in-game name again afterwards
    ItemMenu.pending = ItemMenu.pending + 1
    LoopAsync(1500, function()
        ExecuteInGameThread(function()
            ItemMenu.pending = ItemMenu.pending - 1
            restore()
        end)
        return true
    end)
end

RegisterConsoleCommandHandler(".find", function(FullCommand, Parameters)
    local text = table.concat(Parameters or {}, " ")
    ExecuteInGameThread(function()
        local combo = ItemMenu.FindCombo()
        if not combo then
            Log("[find] Item list not found - open the menu (.menu) in-game first")
            return
        end
        ItemMenu.EnsureLabels(combo)
        local box = ItemMenu.searchBox
        if ItemMenu.IsValid(box) then
            ItemMenu.SetBoxText(box, "SetText", text)
            pcall(function() ItemMenu.lastBoxText = ItemMenu.Str(box:GetText()) or ItemMenu.lastBoxText end)
        end
        local labels = ItemMenu.ApplyFilter(text)
        if text == "" then
            Log("[find] Filter cleared (" .. #labels .. " items)")
            return
        end
        Log("[find] " .. #labels .. " item(s) match '" .. text .. "'" .. (#labels > 0 and " - first one selected" or ""))
        for i = 1, math.min(#labels, 15) do
            Log("  " .. labels[i] .. "  [" .. tostring(ItemMenu.labelToRow and ItemMenu.labelToRow[labels[i]]) .. "]")
        end
        if #labels > 15 then Log("  ... and " .. (#labels - 15) .. " more") end
    end)
    return true
end)

RegisterConsoleCommandHandler(".spawnmode", function(FullCommand, Parameters)
    local m = string.lower((Parameters and Parameters[1]) or "")
    if m == "game" or m == "mod" then
        _G.__SpawnMode = m
        Log("[spawnmode] Menu Spawn button: " .. m)
    else
        Log("[spawnmode] Current: " .. (_G.__SpawnMode or "game"))
        Log("[spawnmode] .spawnmode game - the game's own spawn adds the item (default)")
        Log("[spawnmode] .spawnmode mod  - the mod adds the item instead")
        Log("[spawnmode] Not chosen: in someone else's world the host's Mod Menu adds it")
    end
    return true
end)

-- Persist hooks installed flag across reloads using a global
_G.__SpawnHooksInstalled = _G.__SpawnHooksInstalled or false

-- Install hook on the cheat menu Spawn button.
-- WD_CheatMenu_Button_157 = Spawn (named properly).
-- Reads ComboBox.GetSelectedOption() to get row name, then injects via AttemptToAddItem.
RegisterConsoleCommandHandler(".installspawn", function(FullCommand, Parameters)
    if _G.__SpawnHooksInstalled then
        Log("[installspawn] Already installed. Restart game to reinstall.")
        return true
    end

    local spawnEvent = "/Game/Blueprints/UIBlueprints/WD_CheatMenu.WD_CheatMenu_C:BndEvt__WD_CheatMenu_Button_157_K2Node_ComponentBoundEvent_10_OnButtonClickedEvent__DelegateSignature"

    local ok = pcall(function()
        RegisterHook(spawnEvent, function(self, ...)
            local cm = self:get()
            local rowName = nil
            pcall(function()
                local cb = cm["ComboBox"]
                if cb then rowName = cb:GetSelectedOption() end
            end)
            if not rowName or rowName == "" or rowName == "None" then
                Log("[SpawnHook] No item selected in ComboBox")
                return
            end
            -- Try reading the amount SpinBox; fall back to 1
            local amount = 1
            for _, sbName in ipairs({"SpinBox", "AmountSpinBox", "QuantitySpinBox"}) do
                local sb = nil
                pcall(function() sb = cm[sbName] end)
                if sb then
                    local v = nil
                    pcall(function() v = sb:GetValue() end)
                    if v and v > 0 then amount = math.floor(v); break end
                end
            end
            Log("[SpawnHook] Spawning: " .. rowName .. " x" .. amount)
            AddItemByRowName(rowName, amount)
        end)
    end)

    if ok then
        _G.__SpawnHooksInstalled = true
        Log("[installspawn] Hook installed on Spawn button. Open menu, pick item, click Spawn.")
    else
        Log("[installspawn] Hook failed")
    end
    return true
end)

-- Hook ALL cheat menu buttons. Each does spawn attempt + identifies itself.
-- Probe: list ALL widgets in WD_CheatMenu by class
RegisterConsoleCommandHandler(".menuwidgets", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        Log("[menuwidgets] Scanning WD_CheatMenu widgets...")
        local classes = {"EditableTextBox", "EditableText", "MultiLineEditableTextBox",
                         "SpinBox", "Slider", "TextBlock", "Button", "ComboBoxString",
                         "CheckBox"}
        for _, cls in ipairs(classes) do
            local objs = FindAllOf(cls) or {}
            local matches = {}
            for _, o in ipairs(objs) do
                local fn = ""
                pcall(function() fn = o:GetFullName() end)
                if fn:find("WD_CheatMenu") then
                    -- Try reading text/value
                    local v = nil
                    pcall(function() v = o:GetText() end)
                    if v then pcall(function() v = v:ToString() end) end
                    local vv = nil
                    pcall(function() vv = o:GetValue() end)
                    table.insert(matches, fn:sub(-50) .. " text=" .. tostring(v) .. " value=" .. tostring(vv))
                end
            end
            if #matches > 0 then
                Log("[menuwidgets] " .. cls .. " (" .. #matches .. "):")
                for _, m in ipairs(matches) do Log("  " .. m) end
            end
        end
    end)
    return true
end)

-- Quantity for menu Spawn button (UE4SS can't read live SpinBox value)
_G.__MenuSpawnQty = _G.__MenuSpawnQty or 1
RegisterConsoleCommandHandler(".qty", function(FullCommand, Parameters)
    local n = tonumber(Parameters[1])
    if not n or n < 1 then
        Log("[qty] Current: " .. _G.__MenuSpawnQty .. ". Usage: .qty <n>")
        return true
    end
    _G.__MenuSpawnQty = math.floor(n)
    Log("[qty] Menu spawn amount set to " .. _G.__MenuSpawnQty)
    return true
end)

-- Cache last spinbox values keyed by event name
_G.__SpinBoxValues = _G.__SpinBoxValues or {}

-- SpinBox hooks are installed from InstallCheatMenuHooks (below), which polls
-- until a WD_CheatMenu_C instance exists. Installing immediately at load
-- silently fails on cold game start (class not loaded yet) — that killed the
-- Time spinbox whenever the game was started fresh instead of hot-reloaded.
local spinPrefix = "/Game/Blueprints/UIBlueprints/WD_CheatMenu.WD_CheatMenu_C:"
local spinEvents = {
    ["0"]    = "BndEvt__UIVoiceChatDemo_SpinBox_0_K2Node_ComponentBoundEvent_0_OnSpinBoxValueChangedEvent__DelegateSignature",
    ["1"]    = "BndEvt__UIVoiceChatDemo_SpinBox_1_K2Node_ComponentBoundEvent_2_OnSpinBoxValueChangedEvent__DelegateSignature",
    ["main"] = "BndEvt__UIVoiceChatDemo_SpinBox_K2Node_ComponentBoundEvent_3_OnSpinBoxValueChangedEvent__DelegateSignature",
}
-- Re-resolve WeatherManager every call — NEVER cache (stale pointer crashes
-- on reload / level transition; that was the original time-SpinBox crash).
local function ResolveWeatherManager()
    local wm = nil
    pcall(function()
        local wms = FindAllOf("BP_MultiplayerDynamicWeatherManager_C")
        if wms and #wms > 0 and wms[1]:IsValid() then wm = wms[1] end
    end)
    return wm
end

-- Apply an hour (0-24). Calibrated in-game 2026-06-10 via .ctset:
-- Current Time 300/900/1500 -> clock 3:00/9:00/15:00, i.e. CT = hour * 100.
-- (Day/Night Length only pace how fast CT ticks; they do NOT scale the clock.)
local function ApplyTimeHour(hour)
    ExecuteInGameThread(function()
        if Coop.Joined() then Log("[TimeSpin] In someone else's world the host sets the time") return end
        local wm = ResolveWeatherManager()
        if not wm then Log("[TimeSpin] WeatherManager not found") return end
        pcall(function()
            wm["Current Time"] = hour * 100.0
            pcall(function() wm["Set Light Rotation"](wm) end)
            pcall(function() wm["Set Elements"](wm) end)
            Log(string.format("[TimeSpin] time set to hour %.0f", hour))
        end)
    end)
end

local function InstallSpinBoxHooks()
    local spinHookCount = 0
    for key, ev in pairs(spinEvents) do
    local spinOk = pcall(function()
        RegisterHook(spinPrefix .. ev, function(self, val)
            local v = nil
            pcall(function() v = val:get() end)
            if v and type(v) == "number" then
                _G.__SpinBoxValues[key] = v
                Log("[SpinChange] " .. key .. " = " .. tostring(v))

                -- SpinBox_0 = TIME field. Native Blueprint continuously applies
                -- the spinbox's RAW value as Current Time (clock = hour * 100,
                -- calibrated 2026-06-10), so one-shot corrections get overwritten.
                -- Instead, rewrite the spinbox itself: typing 1-24 becomes
                -- hour*100 and native's own pipeline applies it. Values > 24 are
                -- treated as already-raw and left alone. 0 is ignored (untouched
                -- spinbox commits on every button click; use .time 0 for midnight).
                if key == "0" and v > 0 and v <= 24 then
                    local target = v * 100.0
                    local boxes = FindAllOf("SpinBox") or {}
                    for _, sb in ipairs(boxes) do
                        local fn = ""
                        pcall(function() fn = sb:GetFullName() end)
                        if fn:find("WD_CheatMenu") and fn:find("SpinBox_0") then
                            pcall(function() sb:SetValue(target) end)
                            Log(string.format("[TimeSpin] hour %.0f -> spinbox %.0f", v, target))
                            break
                        end
                    end
                    -- Backup: also write Current Time directly after native settles
                    LoopAsync(1500, function()
                        ApplyTimeHour(v)
                        return true
                    end)
                end
            end
        end)
    end)
    if spinOk then spinHookCount = spinHookCount + 1 end
    end
    Log("[ModMenu] SpinBox hooks installed: " .. spinHookCount .. "/3")
    return spinHookCount > 0
end

-- Wait for WD_CheatMenu_C to load before installing hooks.
-- Cold game start: BP class doesn't exist yet, RegisterHook silently no-ops.
_G.__CheatMenuHooksDone = _G.__CheatMenuHooksDone or false

local function InstallCheatMenuHooks()
    if _G.__CheatMenuHooksDone then return true end
    -- Wait for an actual instance to exist — BP functions aren't loaded until instantiation
    local instances = FindAllOf("WD_CheatMenu_C") or {}
    if #instances == 0 then return false end

    Log("[ModMenu] WD_CheatMenu_C instance exists — installing menu hooks")
    InstallSpinBoxHooks()
    local prefix = "/Game/Blueprints/UIBlueprints/WD_CheatMenu.WD_CheatMenu_C:"
    -- Item SPAWN button = VoiceChat_Btn_0 (UIVoiceChatDemo_Button_0), confirmed
    -- in-game 2026-06-10 via candidate-hook logging. ONLY this button gets the
    -- item-spawn hook — the other 9 (Spawn AI, Fly, Summon Plane/Grad, weather,
    -- emissions) are native Blueprint behavior and must stay unhooked.
    local spawnCandidates = {
        ["VoiceChat_Btn_0"] = "BndEvt__UIVoiceChatDemo_Button_0_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature",
    }

    local function OnSpawnClicked(label, self)
        Log("[SpawnBtn:" .. label .. "] CLICKED")
        ItemMenu.OnSpawnClicked()
    end

    local hookCount = 0
    for label, evName in pairs(spawnCandidates) do
        local hookOk = pcall(function()
            RegisterHook(prefix .. evName, function(self, ...)
                OnSpawnClicked(label, self)
            end)
        end)
        if hookOk then hookCount = hookCount + 1 end
    end

    Log("[ModMenu] Spawn button hook installed: " .. hookCount .. "/1")

    -- Remaining menu buttons: log identity on click ([MenuBtn] lines map the
    -- physical buttons to events). The FLY button toggles ghost mode via
    -- _G.ToggleGhostMode (defined next to SetGhostMode; global because this
    -- hook installs lexically earlier in the file).
    local FLY_BTN_LABEL = "VoiceChat_Btn_171"  -- identified in-game 2026-06-11
    local otherButtons = {
        ["VoiceChat_Btn_1"]   = "BndEvt__UIVoiceChatDemo_Button_1_K2Node_ComponentBoundEvent_6_OnButtonClickedEvent__DelegateSignature",
        ["VoiceChat_Btn_2"]   = "BndEvt__UIVoiceChatDemo_Button_2_K2Node_ComponentBoundEvent_7_OnButtonClickedEvent__DelegateSignature",
        ["VoiceChat_Btn_5"]   = "BndEvt__UIVoiceChatDemo_Button_5_K2Node_ComponentBoundEvent_5_OnButtonClickedEvent__DelegateSignature",
        ["VoiceChat_Btn_85"]  = "BndEvt__UIVoiceChatDemo_Button_85_K2Node_ComponentBoundEvent_4_OnButtonClickedEvent__DelegateSignature",
        ["VoiceChat_Btn_171"] = "BndEvt__UIVoiceChatDemo_Button_171_K2Node_ComponentBoundEvent_8_OnButtonClickedEvent__DelegateSignature",
        ["CheatMenu_Btn_3"]   = "BndEvt__WD_CheatMenu_Button_3_K2Node_ComponentBoundEvent_11_OnButtonClickedEvent__DelegateSignature",
        ["CheatMenu_Btn_4"]   = "BndEvt__WD_CheatMenu_Button_4_K2Node_ComponentBoundEvent_12_OnButtonClickedEvent__DelegateSignature",
        ["CheatMenu_Btn_157"] = "BndEvt__WD_CheatMenu_Button_157_K2Node_ComponentBoundEvent_10_OnButtonClickedEvent__DelegateSignature",
    }
    for label, evName in pairs(otherButtons) do
        pcall(function()
            RegisterHook(prefix .. evName, function(self, ...)
                Log("[MenuBtn] " .. label .. " clicked")
                if label == FLY_BTN_LABEL and _G.ToggleGhostMode then
                    _G.ToggleGhostMode(true)
                end
            end)
        end)
    end

    -- Spawn AI button (VoiceChat_Btn / UIVoiceChatDemo_Button): its native
    -- Blueprint click chain also applies the Time SpinBox (stuck at 0.0), which
    -- resets game time to 0:00. Can't block Blueprint code from Lua, so capture
    -- the time before the click runs and restore it just after. WeatherManager is
    -- re-resolved every call — NEVER cache the pointer (stale on level change).
    local function GetWMForTimeGuard()
        local wm = nil
        pcall(function()
            local wms = FindAllOf("BP_MultiplayerDynamicWeatherManager_C")
            if wms and #wms > 0 and wms[1]:IsValid() then wm = wms[1] end
        end)
        return wm
    end

    local aiSpawnEvent = "BndEvt__UIVoiceChatDemo_Button_K2Node_ComponentBoundEvent_9_OnButtonClickedEvent__DelegateSignature"
    local aiHookOk = pcall(function()
        RegisterHook(prefix .. aiSpawnEvent, function(self, ...)
            -- Pre-hook: runs before the Blueprint body resets the time
            local saved = nil
            local wm = GetWMForTimeGuard()
            if wm then pcall(function() saved = wm["Current Time"] end) end
            if type(saved) ~= "number" then return end

            -- Per-AI spawn fixes. Read the combo selection once, then branch.
            pcall(function()
                if Coop.Joined() then return end   -- the host's game spawns them
                local sel = nil
                for _, cb in ipairs(FindAllOf("ComboBoxString") or {}) do
                    local fname = ""
                    pcall(function() fname = cb:GetFullName() end)
                    if fname:find("WD_CheatMenu") then
                        local s = nil
                        pcall(function() s = cb:GetSelectedOption() end)
                        if s ~= nil and type(s) ~= "string" then
                            pcall(function() s = s:ToString() end)
                        end
                        if type(s) == "string" and s:find("^BP_") then sel = s end
                    end
                end
                if not sel then return end
                local base = sel:gsub("_C$", "")
                Log("[AISpawnBtn] selection base = '" .. base .. "'")

                -- Case 1 — missing class: the selected name does not exist in shipped
                -- builds, so the game's native name-lookup spawn finds no class and
                -- silently no-ops. Force-load the real class and spawn it ourselves.
                --   "BP_Zombie" -> real asset is BP_ZombieSoilder
                local MissingClass = { ["BP_Zombie"] = "BP_ZombieSoilder" }
                local real = MissingClass[base]
                if real then
                    local cls = LoadBPClass("/Game/Blueprints/AI/" .. real)
                    if not cls then
                        Log("[AISpawnBtn] AI fix: could not load " .. real .. "_C")
                        return
                    end
                    local player = GetPlayerCharacter()
                    local loc = player and player:K2_GetActorLocation()
                    local world = player and player:GetWorld()
                    if loc and world then
                        pcall(function()
                            world:SpawnActor(cls,
                                { X = loc.X + 250, Y = loc.Y + 250, Z = loc.Z + 50 },
                                { Pitch = 0, Yaw = 0, Roll = 0 })
                        end)
                        Log("[AISpawnBtn] AI fix: spawned " .. real .. "_C")
                    end
                    return
                end

                -- Case 2 — sinks into floor: "BP_Izdushka" selects the real class
                -- BP_Izbushka, which the native spawn DOES create, but its pivot is
                -- centered so it lands half underground. Don't duplicate it — find
                -- the freshly spawned actor and teleport it up; gravity (it derives
                -- from BP_MasterAICharacter) settles it onto its legs.
                if base:lower():find("iz[bd]ushka") then
                    -- BP_Izbushka is a plain Actor (no movement component, no
                    -- gravity): the native spawn drops it at a wrong Z and it
                    -- never settles, so it sits half underground forever. Snap
                    -- any NEW instance to playerZ + 390 — calibrated in-game
                    -- (.izsnap): the actor root sits ~390 above the leg bottoms.
                    -- NOTE: never scan with ForEachUObject here — iterating the
                    -- full UObject array blocks the game thread ~30s (confirmed).
                    local pl = GetPlayerCharacter()
                    local ploc = pl and pl:K2_GetActorLocation()
                    if not ploc then return end
                    -- The native spawn lands ~1s+ after the click (it rides the
                    -- focus-loss commit) and UE recycles actor names, so a
                    -- before/after name diff is unreliable. Instead poll for
                    -- ~5s and snap ANY izbushka near the player whose Z is off
                    -- target — idempotent, so re-snapping old ones is harmless.
                    local attempts = 0
                    LoopAsync(600, function()
                        attempts = attempts + 1
                        if attempts > 8 then return true end
                        local n = attempts
                        ExecuteInGameThread(function()
                            pcall(function()
                                local objs = FindAllOf("BP_Izbushka_C") or {}
                                local snapped = 0
                                for _, o in ipairs(objs) do
                                    local loc = nil
                                    pcall(function() loc = o:K2_GetActorLocation() end)
                                    if loc then
                                        local dx, dy = loc.X - ploc.X, loc.Y - ploc.Y
                                        if (dx*dx + dy*dy) <= (3000*3000)
                                            and math.abs(loc.Z - (ploc.Z + 390)) > 30 then
                                            local rot = o:K2_GetActorRotation()
                                            o:K2_TeleportTo(
                                                { X = loc.X, Y = loc.Y, Z = ploc.Z + 390 }, rot)
                                            snapped = snapped + 1
                                        end
                                    end
                                end
                                Log(string.format(
                                    "[AISpawnBtn] izbushka check %d: count=%d snapped=%d",
                                    n, #objs, snapped))
                            end)
                        end)
                        return false
                    end)
                end
            end)

            -- One-shot delayed restore (LoopAsync returning true = stop after
            -- first tick). Native reset lands ~950ms after the click (it rides
            -- the SpinBox focus-loss commit), so wait 2s to land after it.
            LoopAsync(2000, function()
                ExecuteInGameThread(function()
                    local wm2 = GetWMForTimeGuard()
                    if not wm2 then return end
                    pcall(function()
                        wm2["Current Time"] = saved
                        pcall(function() wm2["Set Light Rotation"](wm2) end)
                        pcall(function() wm2["Set Elements"](wm2) end)
                        Log(string.format("[AISpawnBtn] time restored to %.1f", saved))
                    end)
                end)
                return true
            end)
        end)
    end)
    Log("[ModMenu] Spawn AI time guard " .. (aiHookOk and "installed" or "FAILED"))

    _G.__CheatMenuHooksDone = true
    return true
end

-- Try immediately (in case mod loads after game started), then poll every 2s until success
if not InstallCheatMenuHooks() then
    Log("[ModMenu] WD_CheatMenu_C not loaded yet — polling for it")
    LoopAsync(2000, function()
        if InstallCheatMenuHooks() then return true end  -- stop loop on success
        return false
    end)
end

-- Hook every WD_CheatMenu button click event with logging.
-- User: click each button once, identify which logs "Spawn" behavior.
local cheatMenuHooksInstalled = false
RegisterConsoleCommandHandler(".hookcheats", function(FullCommand, Parameters)
    if cheatMenuHooksInstalled then
        Log("[hookcheats] Already hooked. Restart game to re-hook.")
        return true
    end
    local prefix = "/Game/Blueprints/UIBlueprints/WD_CheatMenu.WD_CheatMenu_C:"
    local events = {
        "BndEvt__UIVoiceChatDemo_Button_0_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_1_K2Node_ComponentBoundEvent_6_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_2_K2Node_ComponentBoundEvent_7_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_5_K2Node_ComponentBoundEvent_5_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_85_K2Node_ComponentBoundEvent_4_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_171_K2Node_ComponentBoundEvent_8_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__UIVoiceChatDemo_Button_K2Node_ComponentBoundEvent_9_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__WD_CheatMenu_Button_157_K2Node_ComponentBoundEvent_10_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__WD_CheatMenu_Button_3_K2Node_ComponentBoundEvent_11_OnButtonClickedEvent__DelegateSignature",
        "BndEvt__WD_CheatMenu_Button_4_K2Node_ComponentBoundEvent_12_OnButtonClickedEvent__DelegateSignature",
    }
    local hooked = 0
    for _, ev in ipairs(events) do
        local shortName = ev:match("Button_?(%w*)_K2Node") or ev:match("Button_(%w+)") or "?"
        local fullPath = prefix .. ev
        local ok = pcall(function()
            RegisterHook(fullPath, function(self, ...)
                Log("[CHEAT-CLICK] Button: " .. shortName .. "  (event: " .. ev:sub(1, 60) .. "...)")
                -- Also try to read current ComboBox selection
                local cm = self:get()
                local sel = nil
                pcall(function() sel = cm["ComboBox"]:GetSelectedOption() end)
                if sel then Log("[CHEAT-CLICK]   ComboBox selected: " .. tostring(sel)) end
            end)
        end)
        if ok then hooked = hooked + 1 end
    end
    cheatMenuHooksInstalled = true
    Log("[hookcheats] Installed " .. hooked .. "/" .. #events .. " button hooks. Click buttons in menu to identify them.")
    return true
end)

-- Probe the cheat menu widget — find its class, functions, spawn behavior
RegisterConsoleCommandHandler(".probemenu", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local cm = GetCheatMenuWidget()
        if not cm then Log("[probemenu] No cheat menu loaded. Open game first.") return end

        Log("[probemenu] CheatMenu: " .. tostring(cm:GetFullName()))
        Log("[probemenu] Class: " .. tostring(cm:GetClass():GetFullName()))

        -- Iterate functions
        Log("[probemenu] --- Functions ---")
        local fcount = 0
        pcall(function()
            for fn in cm:GetClass():Functions() do
                fcount = fcount + 1
                local fname = "?"; pcall(function() fname = fn:GetName() end)
                Log("  " .. fname)
            end
        end)
        Log("[probemenu] Total functions: " .. fcount)

        -- Iterate properties
        Log("[probemenu] --- Properties ---")
        local pcount = 0
        pcall(function()
            for prop in cm:GetClass():Properties() do
                pcount = pcount + 1
                local pn = "?"; pcall(function() pn = prop:GetName() end)
                local pc = "?"; pcall(function() pc = prop:GetClass():GetName() end)
                Log("  " .. pn .. " [" .. pc .. "]")
            end
        end)
        Log("[probemenu] Total properties: " .. pcount)

        -- Try common widget properties
        Log("[probemenu] --- Common widget probes ---")
        for _, name in ipairs({
            "ItemList", "SpawnButton", "SelectedItem", "SelectedRow", "ItemDropdown",
            "WidgetTree", "Items", "ListView", "ScrollBox", "ComboBox",
            "OnSpawn", "OnClickSpawn", "BTN_Spawn", "Btn_Spawn", "Button_Spawn",
            "CurrentItem", "ActiveItem", "ItemNameText", "SelectedRowName",
        }) do
            local v = nil
            pcall(function() v = cm[name] end)
            if v ~= nil then
                Log("  [" .. name .. "] = " .. tostring(v):sub(1, 100))
            end
        end

        -- Also search all UFunction under any widget that smells like Cheat/Spawn
        Log("[probemenu] --- Functions matching 'CheatMenu' or 'WD_Cheat' ---")
        local matches = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                if name:find("^Function") and (name:find("CheatMenu") or name:find("WD_Cheat") or name:find("WBP_Cheat")) then
                    matches[name] = true
                end
            end
            return false
        end)
        local sorted = {}; for n, _ in pairs(matches) do table.insert(sorted, n) end
        table.sort(sorted)
        for _, n in ipairs(sorted) do Log("  " .. n) end
        Log("[probemenu] Total cheat funcs: " .. #sorted)
    end)
    return true
end)

-- Probe first spawner: try every plausible property name
RegisterConsoleCommandHandler(".probespawn", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local spawners = FindAllOf("BP_MasterItemSpawner_C") or {}
        if #spawners == 0 then Log("[probe] No spawners") return end
        local s = spawners[1]
        Log("[probe] First spawner: " .. tostring(s:GetFullName()))

        local candidates = {
            "Item", "SpawnList", "ItemData", "ItemToSpawn", "DefaultItem",
            "Items", "SpawnItem", "SpawnItems", "ItemList", "LootTable",
            "SpawnEntry", "ItemRowName", "RowName", "InvItem", "SGK InvItem",
            "SpawnedItem", "ItemClass", "WorldItem", "SpawnChance",
            "RandomSpawnList", "RandomItems", "PossibleSpawns", "SpawnableItems",
            "DT", "DataTable", "ItemTable", "ID", "Row", "Tag", "Class",
            "DefaultSceneRoot", "RootComponent", "InventoryComponent",
            "ItemRow", "ItemRowHandle", "Handle", "RowHandle",
            "SpawnRowName", "SpawnRow", "ItemName", "Name", "Identifier",
        }

        Log("[probe] Existing properties (non-nil):")
        for _, k in ipairs(candidates) do
            local v = nil
            pcall(function() v = s[k] end)
            if v ~= nil then
                local ts = tostring(v):sub(1, 80)
                Log("  [" .. k .. "] = " .. ts)
                -- Try drilling deeper
                for _, sub in ipairs({"RowName", "ID", "DataTableRowHandle", "Name", "Item"}) do
                    pcall(function()
                        local subv = v[sub]
                        if subv ~= nil then
                            local sts = tostring(subv):sub(1, 80)
                            local asStr = ""; pcall(function() asStr = subv:ToString() end)
                            Log("    ." .. sub .. " = " .. sts .. (asStr ~= "" and " | str=" .. asStr or ""))
                        end
                    end)
                end
            end
        end
    end)
    return true
end)

-- Read RowNames from BP_MasterItemSpawner_C.ItemSpawnList (TArray<FS_SpawnerList>)
-- FS_SpawnerList field is mangled: Item_2_9755B88A40573D1DF345B39A2BA7A1FD (FDataTableRowHandle)
RegisterConsoleCommandHandler(".dumpspawn", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        -- Relative to the ue4ss folder (same convention as bindings.txt)
        local outPath = "Mods/MISERYModMenu/items_world.txt"

        local rows = {}
        local f = io.open(outPath, "r")
        if f then
            for line in f:lines() do
                local t = line:match("^%s*(.-)%s*$")
                if t ~= "" and not t:find("^#") and not t:find("^=") then rows[t] = true end
            end
            f:close()
        end
        local oldCount = 0; for _ in pairs(rows) do oldCount = oldCount + 1 end

        -- Mangled FS_SpawnerList field name (from CXX dump)
        local F_SPAWN_ITEM = "Item_2_9755B88A40573D1DF345B39A2BA7A1FD"

        -- Scan ALL spawner subclasses
        local spawnerClasses = {
            "BP_MasterItemSpawner_C",
            "BP_ResourceItemSpawner_C",
            "BP_PoopItemSpawner_C",
            "BP_ArtifactSpawner_C",
        }

        local extracted = 0
        local totalSpawners = 0
        for _, cls in ipairs(spawnerClasses) do
            local spawners = FindAllOf(cls) or {}
            totalSpawners = totalSpawners + #spawners
            if #spawners > 0 then
                local clsExtracted = 0
                for _, s in ipairs(spawners) do
                    local arr = nil
                    pcall(function() arr = s["ItemSpawnList"] end)
                    if arr then
                        local n = 0
                        pcall(function() n = arr:Num() end)
                        for i = 0, n - 1 do
                            local entry = nil
                            pcall(function() entry = arr[i] end)
                            if entry then
                                -- Access mangled FDataTableRowHandle field
                                local handle = nil
                                pcall(function() handle = entry[F_SPAWN_ITEM] end)
                                if handle then
                                    local rn = nil
                                    pcall(function() rn = handle["RowName"]:ToString() end)
                                    if rn and rn ~= "" and rn ~= "None" then
                                        if not rows[rn] then
                                            rows[rn] = true
                                            extracted = extracted + 1
                                            clsExtracted = clsExtracted + 1
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- Also try PendingItem (single FS_SpawnerList)
                    local pending = nil
                    pcall(function() pending = s["PendingItem"] end)
                    if pending then
                        local handle = nil
                        pcall(function() handle = pending[F_SPAWN_ITEM] end)
                        if handle then
                            local rn = nil
                            pcall(function() rn = handle["RowName"]:ToString() end)
                            if rn and rn ~= "" and rn ~= "None" then
                                if not rows[rn] then
                                    rows[rn] = true
                                    extracted = extracted + 1
                                    clsExtracted = clsExtracted + 1
                                end
                            end
                        end
                    end
                end
                Log("[dumpspawn] " .. cls .. ": " .. #spawners .. " spawners, +" .. clsExtracted .. " rows")
            end
        end

        Log("[dumpspawn] Total +" .. extracted .. " new from " .. totalSpawners .. " spawners")

        local sorted = {}
        for rn, _ in pairs(rows) do table.insert(sorted, rn) end
        table.sort(sorted)

        local out = io.open(outPath, "w")
        if not out then Log("[dumpspawn] Write failed: " .. outPath); return end
        out:write("# MISERY Item Row Names (" .. #sorted .. " total)\n")
        out:write("# Usage: .addraw <RowName> [amount]\n")
        out:write(string.rep("=", 50) .. "\n")
        for _, rn in ipairs(sorted) do out:write(rn .. "\n") end
        out:close()
        Log("[dumpspawn] Wrote " .. #sorted .. " total to file")
    end)
    return true
end)

-- Dump RowNames from currently loaded world items. Appends to file across runs.
-- Walk the whole map and re-run to build a comprehensive list.
RegisterConsoleCommandHandler(".dumpworld", function(FullCommand, Parameters)
    Log("[dumpworld] Scanning world items and merging into file...")
    ExecuteInGameThread(function()
        -- Absolute path works regardless of CWD
        -- Relative to the ue4ss folder (same convention as bindings.txt)
        local outPath = "Mods/MISERYModMenu/items_world.txt"

        -- Load existing rows from file
        local existing = {}
        local f = io.open(outPath, "r")
        if f then
            for line in f:lines() do
                local trimmed = line:match("^%s*(.-)%s*$")
                if trimmed ~= "" and not trimmed:find("^#") and not trimmed:find("^=") then
                    existing[trimmed] = true
                end
            end
            f:close()
        end
        local oldCount = 0
        for _ in pairs(existing) do oldCount = oldCount + 1 end
        Log("[dumpworld] Existing entries in file: " .. oldCount)

        -- Scan multiple world-item classes
        local classes = {
            "BP_StaticMasterItem_C",
            "BP_SkeletalMasterItem_C",
            "BP_MasterHoldable_C",
            "BP_MasterItemInventory_C",
            "BP_MasterConsumable_C",
            "BP_MasterMeleeWeapon_C",
            "BP_MasterRangeWeapon_C",
            "BP_MasterAttachment_C",
            "BP_MasterClothingAttchment_C",
            "BP_MasterExplosiveThrowable_C",
            "BP_MasterThrowable_C",
            "BP_MasterResource_C",
            "BP_MasterInteractableResource_C",
        }
        -- Helper: try many access paths to find a RowName FName on item
        local function extractRowName(item)
            local rn = nil
            -- Path A: item.Item.RowName (StaticMasterItem)
            pcall(function() rn = item["Item"]["RowName"]:ToString() end)
            if rn and rn ~= "" and rn ~= "None" then return rn end
            -- Path B: item.RowName direct
            pcall(function() rn = item["RowName"]:ToString() end)
            if rn and rn ~= "" and rn ~= "None" then return rn end
            -- Path C: item.ItemData.RowName
            pcall(function() rn = item["ItemData"]["RowName"]:ToString() end)
            if rn and rn ~= "" and rn ~= "None" then return rn end
            -- Path D: item.InvItem.ID
            pcall(function() rn = item["InvItem"]["ID"]:ToString() end)
            if rn and rn ~= "" and rn ~= "None" then return rn end
            -- Path E: try all top-level properties for any FName that looks like RowName
            local found = nil
            pcall(function()
                item:ForEachProperty(function(prop)
                    local pn = prop:GetFName():ToString()
                    local pc = prop:GetClass():GetFName():ToString()
                    if pc == "StructProperty" then
                        local sv = nil
                        pcall(function() sv = item[pn] end)
                        if sv then
                            -- look inside for RowName
                            pcall(function()
                                sv:ForEachProperty(function(sp)
                                    local spn = sp:GetFName():ToString()
                                    if spn == "RowName" or spn == "ID" then
                                        local val = nil
                                        pcall(function() val = sv[spn]:ToString() end)
                                        if val and val ~= "" and val ~= "None" then
                                            found = val
                                        end
                                    end
                                end)
                            end)
                        end
                    end
                end)
            end)
            return found
        end

        local found = 0
        local sampleRows = {}  -- log first few for diagnostic
        for _, cls in ipairs(classes) do
            local objs = FindAllOf(cls) or {}
            if #objs > 0 then
                local added = 0
                local extracted = 0
                for _, item in ipairs(objs) do
                    local rn = extractRowName(item)
                    if rn then
                        extracted = extracted + 1
                        if not existing[rn] then
                            existing[rn] = true
                            added = added + 1
                            if #sampleRows < 20 then table.insert(sampleRows, rn) end
                        end
                        found = found + 1
                    end
                end
                Log("[dumpworld] " .. cls .. ": " .. #objs .. " objs, extracted=" .. extracted .. ", +" .. added .. " new")
            end
        end
        if #sampleRows > 0 then
            Log("[dumpworld] Sample new rows: " .. table.concat(sampleRows, ", "))
        end

        -- Also scan inventory slots
        local inv = GetInventory()
        if inv then
            local slots = nil
            pcall(function() slots = inv["InventorySlots"] end)
            local slotCount = 0
            if slots then pcall(function() slotCount = slots:Num() end) end
            local added = 0
            if slotCount > 0 then
                for i = 0, slotCount - 1 do
                    local rn = nil
                    pcall(function() rn = slots[i]["Item"]["RowName"]:ToString() end)
                    if rn and rn ~= "" and rn ~= "None" and rn ~= "?" then
                        if not existing[rn] then
                            existing[rn] = true
                            added = added + 1
                        end
                    end
                end
            end
            Log("[dumpworld] Inventory slots: " .. slotCount .. ", +" .. added .. " new")
        end

        -- Sort and write back
        local sorted = {}
        for rn, _ in pairs(existing) do table.insert(sorted, rn) end
        table.sort(sorted)

        local out = io.open(outPath, "w")
        if not out then Log("[dumpworld] Could not write " .. outPath) return end
        out:write("# MISERY Item Row Names (" .. #sorted .. " total)\n")
        out:write("# Usage: .addraw <RowName> [amount]\n")
        out:write("# Walk the map and re-run .dumpworld to add more\n")
        out:write(string.rep("=", 50) .. "\n")
        for _, rn in ipairs(sorted) do
            out:write(rn .. "\n")
        end
        out:close()
        local newCount = #sorted
        Log("[dumpworld] Wrote " .. newCount .. " total rows (" .. (newCount - oldCount) .. " new) to " .. outPath)
    end)
    return true
end)

-- Diagnostic: dump all properties + functions of MasterItemList
RegisterConsoleCommandHandler(".dtinspect", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local mil = StaticFindObject("/Game/SurvivalGameKitV2/Blueprints/Items/ItemList.ItemList")
        if not mil then Log("[dtinspect] ItemList not found") return end
        Log("[dtinspect] DataTable: " .. tostring(mil:GetFullName()))
        Log("[dtinspect] Class: " .. tostring(mil:GetClass():GetFullName()))

        Log("[dtinspect] --- Properties ---")
        local pcount = 0
        pcall(function()
            for prop in mil:GetClass():Properties() do
                pcount = pcount + 1
                local pn = "?"; pcall(function() pn = prop:GetName() end)
                local pc = "?"; pcall(function() pc = prop:GetClass():GetName() end)
                Log("  " .. pn .. " [" .. pc .. "]")
            end
        end)
        Log("[dtinspect] Total properties: " .. pcount)

        Log("[dtinspect] --- Functions ---")
        local fcount = 0
        pcall(function()
            for fn in mil:GetClass():Functions() do
                fcount = fcount + 1
                local fname = "?"; pcall(function() fname = fn:GetName() end)
                Log("  " .. fname)
            end
        end)
        Log("[dtinspect] Total functions: " .. fcount)

        -- Try common DataTable property names
        for _, pname in ipairs({"RowMap", "RowStruct", "Rows", "Data", "RowData", "Table", "RowsSerialize"}) do
            local v = nil
            local ok = pcall(function() v = mil[pname] end)
            Log("[dtinspect] Property " .. pname .. ": ok=" .. tostring(ok) .. " val=" .. tostring(v))
        end
    end)
    return true
end)

-- Dump all MasterItemList row names to a file for reference
RegisterConsoleCommandHandler(".dumpitems", function(FullCommand, Parameters)
    Log("[dumpitems] Dumping all item row names to file...")
    ExecuteInGameThread(function()
        local rows = {}
        local sources = {}

        local function collectRows(t, label)
            -- Approach A: GetAllTableRowNames (often fails with nullptr)
            local ok, result = pcall(function() return t:GetAllTableRowNames() end)
            if ok and result then
                local count = 0
                pcall(function() count = #result end)
                if count > 0 then
                    Log("[dumpitems] " .. label .. " GetAllTableRowNames -> " .. count)
                    for i = 1, count do
                        local rn = ""
                        pcall(function() rn = result[i]:ToString() end)
                        if rn ~= "" then rows[rn] = true end
                    end
                    table.insert(sources, label .. " (" .. count .. ")")
                    return true
                end
            end

            -- Approach B: iterate RowMap property (TMap<FName, void*>)
            local rm = nil
            pcall(function() rm = t["RowMap"] end)
            if rm then
                local before = 0
                for k, _ in pairs(rows) do before = before + 1 end
                local iterOk = pcall(function()
                    rm:ForEach(function(key, val)
                        local rn = ""
                        pcall(function() rn = key:get():ToString() end)
                        if rn ~= "" then rows[rn] = true end
                    end)
                end)
                if not iterOk then
                    -- Try alternative ForEachPair
                    pcall(function()
                        rm:ForEachPair(function(key, val)
                            local rn = ""
                            pcall(function() rn = key:ToString() end)
                            if rn ~= "" then rows[rn] = true end
                        end)
                    end)
                end
                local after = 0
                for k, _ in pairs(rows) do after = after + 1 end
                local added = after - before
                if added > 0 then
                    Log("[dumpitems] " .. label .. " RowMap iter -> +" .. added)
                    table.insert(sources, label .. ".RowMap (+" .. added .. ")")
                    return true
                end
            end

            -- Approach C: ForEachProperty on the row struct via RowStruct property (last resort, won't give row names)
            -- This only helps to confirm the DataTable is alive.

            return false
        end

        -- Try 1: MasterItemList CompositeDataTable direct
        local mil = nil
        pcall(function() mil = StaticFindObject("/Game/SurvivalGameKitV2/Blueprints/Items/MasterLists/MasterItemList.MasterItemList") end)
        if mil then
            Log("[dumpitems] Found MasterItemList: " .. tostring(mil:GetFullName()))
            collectRows(mil, "MasterItemList")
            -- Try ParentTables
            local ok, parents = pcall(function() return mil["ParentTables"] end)
            Log("[dumpitems] MasterItemList ParentTables: ok=" .. tostring(ok) .. " val=" .. tostring(parents))
            if ok and parents then
                for i = 0, 50 do
                    local p = nil
                    pcall(function() p = parents[i] end)
                    if not p then break end
                    local pname = ""; pcall(function() pname = p:GetName() end)
                    collectRows(p, "MasterItemList.Parent[" .. i .. "] " .. pname)
                end
            end
        else
            Log("[dumpitems] MasterItemList NOT found via StaticFindObject")
        end

        -- Try 2: ItemList.ItemList direct DataTable
        local il = nil
        pcall(function() il = StaticFindObject("/Game/SurvivalGameKitV2/Blueprints/Items/ItemList.ItemList") end)
        if il then
            Log("[dumpitems] Found ItemList: " .. tostring(il:GetFullName()))
            collectRows(il, "ItemList")
        else
            Log("[dumpitems] ItemList NOT found via StaticFindObject")
        end

        -- Try 3: Iterate all DataTables found by ForEachUObject
        Log("[dumpitems] Scanning all DataTable objects...")
        local dtCount = 0
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                if (name:find("^DataTable ") or name:find("^CompositeDataTable ")) and
                   (name:find("/Items/") or name:find("ItemList") or name:find("MasterItem")) then
                    dtCount = dtCount + 1
                    local short = name:match("([^.]+)%.[^%.]+$") or name
                    collectRows(obj, "Scan[" .. dtCount .. "] " .. short)
                end
            end
            return false
        end)
        Log("[dumpitems] Scanned " .. dtCount .. " item-related DataTables")

        -- Try 4: World items DataTable
        local worldItems = FindAllOf("BP_StaticMasterItem_C") or {}
        Log("[dumpitems] World items in scene: " .. #worldItems)
        for _, item in ipairs(worldItems) do
            local wdt = nil
            pcall(function() wdt = item["Item"]["DataTable"] end)
            if wdt then
                if collectRows(wdt, "WorldItem.DataTable") then break end
            end
        end

        local sorted = {}
        for rn, _ in pairs(rows) do table.insert(sorted, rn) end
        table.sort(sorted)

        if #sorted == 0 then
            Log("[dumpitems] No rows found. Game must be IN-GAME (not main menu), with player loaded.")
            return
        end

        local outPath = "Mods/MISERYModMenu/items_dump.txt"
        local f = io.open(outPath, "w")
        if not f then
            Log("[dumpitems] Could not open " .. outPath .. " for writing")
            return
        end
        f:write("MISERY Item Row Names (" .. #sorted .. " total)\n")
        f:write("Usage: .addraw <RowName> [amount]\n")
        f:write("Sources: " .. table.concat(sources, ", ") .. "\n")
        f:write(string.rep("=", 50) .. "\n\n")
        for _, rn in ipairs(sorted) do
            f:write(rn .. "\n")
        end
        f:close()
        Log("[dumpitems] Wrote " .. #sorted .. " rows to " .. outPath)
    end)
    return true
end)

-- List all UFunctions matching a class name pattern
RegisterConsoleCommandHandler(".listfuncs", function(FullCommand, Parameters)
    local filter = Parameters[1] or "SGKMasterCharacter"
    Log("UFunctions matching: " .. filter)
    local count = 0
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(name, "^Function") and string.find(name, filter, 1, true) then
            Log("  " .. name)
            count = count + 1
        end
        return false
    end)
    Log("Total: " .. count)
    return true
end)

-- Inspect UFunction parameter types
RegisterConsoleCommandHandler(".funcinfo", function(FullCommand, Parameters)
    local funcName = Parameters[1] or "ServerSpawnItemDebug"
    Log("Inspecting UFunction: " .. funcName)
    local found = 0
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(name, "^Function") and string.find(name, funcName, 1, true) then
            Log("  " .. name)
            local ok2, err = pcall(function()
                local n = 0
                for param in obj:Properties() do
                    n = n + 1
                    local pname = tostring(n)
                    pcall(function() pname = param:GetName() end)
                    local ptype = "?"
                    pcall(function() ptype = param:GetClass():GetName() end)
                    Log("    param[" .. n .. "]: " .. pname .. " [" .. ptype .. "]")
                end
                if n == 0 then Log("    (Properties() returned 0 entries)") end
            end)
            if not ok2 then Log("    Properties() ERR: " .. tostring(err)) end
            found = found + 1
        end
        return false
    end)
    Log("Found " .. found .. " matching function(s)")
    return true
end)

-- Hook AttemptToAddItem to log when an item is added
-- Always logs RowName. Verbose FS_InvItem dump (incl. nested struct fields like
-- MasterInventory, Magazine, Ammo) is gated by `.dumpinv on` to avoid flooding.
_G.__DumpInvItem = _G.__DumpInvItem or false

local function _FmtPropVal(struct, pname, ptypeStr)
    local val = nil
    pcall(function() val = struct[pname] end)
    if val == nil then return "nil" end
    if ptypeStr == "ObjectProperty" or ptypeStr == "ClassProperty"
       or ptypeStr == "SoftObjectProperty" or ptypeStr == "WeakObjectProperty"
       or ptypeStr == "InterfaceProperty" then
        local ok, fname = pcall(function() return val:GetFullName() end)
        if ok and fname and fname ~= "" then return fname end
        return tostring(val)
    end
    if ptypeStr == "NameProperty" then
        local ok, str = pcall(function() return val:ToString() end)
        if ok then return "FName(" .. str .. ")" end
        return tostring(val)
    end
    if ptypeStr == "StrProperty" or ptypeStr == "TextProperty" then
        local ok, str = pcall(function() return val:ToString() end)
        if ok then return '"' .. str .. '"' end
        return tostring(val)
    end
    return tostring(val)
end

local function _DumpStruct(struct, indent, depth)
    depth = depth or 0
    if depth > 4 then Log(indent .. "...(max depth)") return end
    local ok = pcall(function()
        struct:ForEachProperty(function(prop)
            local pname = "?"; pcall(function() pname = prop:GetFName():ToString() end)
            local ptypeStr = "?"; pcall(function() ptypeStr = prop:GetClass():GetFName():ToString() end)

            if ptypeStr == "StructProperty" then
                local sv = nil; pcall(function() sv = struct[pname] end)
                if sv then
                    Log(indent .. pname .. " <Struct>:")
                    _DumpStruct(sv, indent .. "  ", depth + 1)
                else
                    Log(indent .. pname .. " <Struct> = nil")
                end
            elseif ptypeStr == "ArrayProperty" then
                local arr = nil; pcall(function() arr = struct[pname] end)
                local lenStr = "?"
                local lenNum = nil
                pcall(function() lenNum = arr:Num(); lenStr = tostring(lenNum) end)
                Log(indent .. pname .. " <Array> len=" .. lenStr)
                if arr and lenNum and lenNum > 0 then
                    local first = nil; pcall(function() first = arr[0] end)
                    if first ~= nil then
                        local okDump = pcall(function() _DumpStruct(first, indent .. "  [0] ", depth + 1) end)
                        if not okDump then Log(indent .. "  [0] " .. tostring(first)) end
                    end
                end
            elseif ptypeStr == "MapProperty" or ptypeStr == "SetProperty" then
                Log(indent .. pname .. " <" .. ptypeStr .. "> (not dumped)")
            else
                Log(indent .. pname .. " [" .. ptypeStr .. "] = " .. _FmtPropVal(struct, pname, ptypeStr))
            end
        end)
    end)
    if not ok then Log(indent .. "(ForEachProperty failed)") end
end

pcall(function()
    RegisterHook("/Game/SurvivalGameKitV2/Components/BP_PlayerInventory.BP_PlayerInventory_C:AttemptToAddItem",
        function(self, ...)
            local args = {...}
            local rn = "?"
            local s = nil
            pcall(function() s = args[1]:get() end)
            if s then
                pcall(function()
                    s:ForEachProperty(function(prop)
                        local pname = prop:GetFName():ToString()
                        if prop:GetClass():GetFName():ToString() == "NameProperty" and pname:find("^ID") then
                            rn = s[pname]:ToString()
                        end
                    end)
                end)
            end
            Log("[HOOK] AttemptToAddItem: " .. rn)
            if _G.__DumpInvItem and s then
                Log("[HOOK] === FS_InvItem dump (" .. rn .. ") ===")
                _DumpStruct(s, "  ", 0)
                Log("[HOOK] === end dump ===")
            end
        end
    )
end)

-- ============================================================
-- GIM signature discovery hooks
-- Install hooks on the 4 candidate factory functions on BP_GlobalInventoryManager_C
-- so we can read each call's argc + per-arg type/value when the game fires them.
-- Gated by .gimspy on / off.
-- ============================================================
_G.__GimSpy = _G.__GimSpy or false
_G.__GimHooksInstalled = _G.__GimHooksInstalled or false

local function _GimLogArg(idx, arg)
    local tt = type(arg)
    if tt ~= "userdata" then
        Log(string.format("    arg[%d] (%s) = %s", idx, tt, tostring(arg)))
        return
    end
    -- userdata: try a few extraction paths
    local cls = "?"
    pcall(function() cls = arg:GetClass():GetFName():ToString() end)
    -- Try :get() if it's a RemoteUnrealParam
    local got = nil
    pcall(function() got = arg:get() end)
    if got ~= nil then
        local gotCls = "?"
        pcall(function() gotCls = got:GetClass():GetFName():ToString() end)
        -- Struct? dump fields
        local okFE = pcall(function()
            local fields = {}
            got:ForEachProperty(function(prop)
                local pname = prop:GetFName():ToString()
                local ptype = prop:GetClass():GetFName():ToString()
                table.insert(fields, pname .. "[" .. ptype .. "]")
            end)
            Log(string.format("    arg[%d] :get() (%s) fields=%d", idx, gotCls, #fields))
            for _, fn in ipairs(fields) do Log("      " .. fn) end
        end)
        if not okFE then
            local s = tostring(got)
            Log(string.format("    arg[%d] :get() (%s) val=%s", idx, gotCls, s))
        end
    else
        local s = tostring(arg)
        Log(string.format("    arg[%d] userdata (%s) tostring=%s", idx, cls, s:sub(1, 80)))
        -- Try GetFullName if it's a UObject ref
        local fn = ""
        pcall(function() fn = arg:GetFullName() end)
        if fn ~= "" then Log("      GetFullName=" .. fn) end
    end
end

local function _GimInstallHooks()
    if _G.__GimHooksInstalled then return end
    local paths = {
        "/Game/SurvivalGameKitV2/Blueprints/Other/BP_GlobalInventoryManager.BP_GlobalInventoryManager_C:CreateNewItem",
        "/Game/SurvivalGameKitV2/Blueprints/Other/BP_GlobalInventoryManager.BP_GlobalInventoryManager_C:CreateNewInventory",
        "/Game/SurvivalGameKitV2/Blueprints/Other/BP_GlobalInventoryManager.BP_GlobalInventoryManager_C:CreateNewWeaponInventory",
        "/Game/SurvivalGameKitV2/Blueprints/Other/BP_GlobalInventoryManager.BP_GlobalInventoryManager_C:InitializeGlobalInventory",
    }
    local installed = 0
    for _, path in ipairs(paths) do
        local ok, err = pcall(function()
            local short = path:match("([^/]+):([^/]+)$") or path
            -- Pre-call hook
            RegisterHook(path, function(self, ...)
                if not _G.__GimSpy then return end
                local args = {...}
                Log("[GIMSPY] >>> " .. short .. " argc=" .. #args)
                for i, a in ipairs(args) do _GimLogArg(i, a) end
            end,
            -- Post-call hook (return values)
            function(self, ...)
                if not _G.__GimSpy then return end
                local args = {...}
                Log("[GIMSPY] <<< " .. short .. " post argc=" .. #args)
                for i, a in ipairs(args) do _GimLogArg(i, a) end
            end)
            installed = installed + 1
        end)
        if not ok then
            Log("[GIMSPY] Install fail " .. path .. ": " .. tostring(err))
        end
    end
    _G.__GimHooksInstalled = (installed > 0)
    Log("[GIMSPY] Installed " .. installed .. "/" .. #paths .. " hooks")
end

RegisterConsoleCommandHandler(".gimspy", function(FullCommand, Parameters)
    local arg = string.lower(Parameters[1] or "")
    if arg == "on" or arg == "1" then
        _GimInstallHooks()
        _G.__GimSpy = true
        Log("[gimspy] ON. Trigger a loot spawn / container open / pickup to fire the factories.")
    elseif arg == "off" or arg == "0" then
        _G.__GimSpy = false
        Log("[gimspy] OFF.")
    else
        Log("[gimspy] State: " .. (_G.__GimSpy and "ON" or "OFF") .. " | Hooks installed: " .. tostring(_G.__GimHooksInstalled))
        Log("[gimspy] Usage: .gimspy on|off")
    end
    return true
end)

-- Inspect BP_GlobalInventoryManager_C — find UFunction that allocates a fresh
-- MasterInventory / WeaponInventory component (so spawned items can get the
-- per-instance inventory pointer needed for wearable slots / mag ammo / weapon mag).
RegisterConsoleCommandHandler(".gim", function(FullCommand, Parameters)
    local filter = string.lower(Parameters[1] or "")
    ExecuteInGameThread(function()
        local gims = FindAllOf("BP_GlobalInventoryManager_C")
        if not gims or #gims == 0 then
            Log("[gim] No BP_GlobalInventoryManager_C found")
            return
        end
        local gim = gims[1]
        Log("[gim] Instance: " .. tostring(gim:GetFullName()))

        -- Properties (look for arrays of inventory pools)
        Log("[gim] --- Properties ---")
        local propCount = 0
        pcall(function()
            for prop in gim:GetClass():Properties() do
                local pname = prop:GetFName():ToString()
                local ptype = "?"; pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
                if filter == "" or pname:lower():find(filter, 1, true) or ptype:lower():find(filter, 1, true) then
                    -- For array properties try to print length
                    local extra = ""
                    if ptype == "ArrayProperty" then
                        local arr = nil; pcall(function() arr = gim[pname] end)
                        if arr then
                            local n = "?"; pcall(function() n = tostring(arr:Num()) end)
                            extra = " len=" .. n
                        end
                    elseif ptype == "ObjectProperty" then
                        local v = nil; pcall(function() v = gim[pname] end)
                        if v then
                            local fn = ""; pcall(function() fn = v:GetFullName() end)
                            if fn ~= "" then extra = " -> " .. fn end
                        end
                    end
                    Log("  " .. pname .. " [" .. ptype .. "]" .. extra)
                    propCount = propCount + 1
                end
            end
        end)
        Log("[gim] " .. propCount .. " properties")

        -- Functions
        Log("[gim] --- Functions ---")
        local funcCount = 0
        pcall(function()
            for func in gim:GetClass():Functions() do
                local fname = func:GetFName():ToString()
                if filter == "" or fname:lower():find(filter, 1, true) then
                    Log("  " .. fname)
                    funcCount = funcCount + 1
                end
            end
        end)
        Log("[gim] " .. funcCount .. " functions")
    end)
    return true
end)

-- Dump every FName-style UFunction in the game that mentions Inventory + Add/Create/Spawn/Get
RegisterConsoleCommandHandler(".invspawnfuncs", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local funcs = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name and name:find("^Function") then
                local lower = name:lower()
                if (lower:find("inventory") or lower:find("masterinv") or lower:find("weaponinv"))
                   and (lower:find("create") or lower:find("add") or lower:find("spawn")
                        or lower:find("new") or lower:find("alloc") or lower:find("init")
                        or lower:find("get") or lower:find("make")) then
                    funcs[name] = true
                end
            end
            return false
        end)
        local sorted = {}
        for n,_ in pairs(funcs) do table.insert(sorted, n) end
        table.sort(sorted)
        for i, n in ipairs(sorted) do
            if i <= 80 then Log("  " .. n) end
        end
        Log("[invspawnfuncs] " .. #sorted .. " functions")
    end)
    return true
end)

-- Find loaded UObjects whose name contains a substring (diagnostic).
-- Usage: .findclass zombie  -> prints full names of matching objects (max 40).
RegisterConsoleCommandHandler(".findclass", function(FullCommand, Parameters)
    local needle = (Parameters[1] or ""):lower()
    if needle == "" then
        Log("[findclass] Usage: .findclass <substring>")
        return true
    end
    ExecuteInGameThread(function()
        local matches = {}
        ForEachUObject(function(obj)
            pcall(function()
                local short = obj:GetFName():ToString()
                if short:lower():find(needle, 1, true) then
                    table.insert(matches, obj:GetFullName())
                end
            end)
            return false
        end)
        table.sort(matches)
        for i, n in ipairs(matches) do
            if i <= 40 then Log("  " .. n) end
        end
        if #matches > 40 then Log("  ... (" .. (#matches - 40) .. " more)") end
        Log("[findclass] " .. #matches .. " objects match '" .. needle .. "'")
    end)
    return true
end)

-- Inspect spawned Izbushka instances: capsule size, mesh offset, controller,
-- movement mode. ".izdiag fix" also spawns a default AI controller for any
-- instance that has none (native menu spawn skips possession).
RegisterConsoleCommandHandler(".izdiag", function(FullCommand, Parameters)
    local doFix = (Parameters[1] or ""):lower() == "fix"
    ExecuteInGameThread(function()
        local objs = FindAllOf("BP_Izbushka_C") or {}
        Log("[izdiag] instances: " .. #objs .. (doFix and " (fix mode)" or ""))
        for i, o in ipairs(objs) do
            pcall(function()
                local loc = o:K2_GetActorLocation()
                Log(string.format("[izdiag] #%d %s at Z=%.1f", i, o:GetFullName(), loc.Z))
            end)
            pcall(function()
                local cls, chain = o:GetClass(), {}
                while cls and cls:IsValid() and #chain < 12 do
                    table.insert(chain, cls:GetFName():ToString())
                    cls = cls:GetSuperStruct()
                end
                Log("[izdiag]   class chain: " .. table.concat(chain, " <- "))
            end)
            pcall(function()
                local root = o.RootComponent
                Log("[izdiag]   root component: "
                    .. ((root and root:IsValid()) and root:GetFullName() or "NONE"))
            end)
            pcall(function()
                local acc = o.AIControllerClass
                Log("[izdiag]   AIControllerClass: "
                    .. ((acc and acc:IsValid()) and acc:GetFullName() or "NONE"))
                Log("[izdiag]   AutoPossessAI: " .. tostring(o.AutoPossessAI))
            end)
            local ok, err = pcall(function()
                local cap = o.CapsuleComponent
                if cap and cap:IsValid() then
                    Log(string.format("[izdiag]   capsule halfheight=%.1f radius=%.1f",
                        cap:GetScaledCapsuleHalfHeight(), cap:GetScaledCapsuleRadius()))
                else
                    Log("[izdiag]   capsule: nil/invalid")
                end
            end)
            if not ok then Log("[izdiag]   capsule ERR: " .. tostring(err)) end
            ok, err = pcall(function()
                local mesh = o.Mesh
                if mesh and mesh:IsValid() then
                    local rel = mesh.RelativeLocation
                    Log(string.format("[izdiag]   mesh relZ=%.1f relX=%.1f relY=%.1f",
                        rel.Z, rel.X, rel.Y))
                else
                    Log("[izdiag]   mesh: nil/invalid")
                end
            end)
            if not ok then Log("[izdiag]   mesh ERR: " .. tostring(err)) end
            pcall(function()
                local ctrl = o.Controller
                local has = ctrl and ctrl:IsValid()
                Log("[izdiag]   controller: " .. (has and ctrl:GetFullName() or "NONE"))
                if not has and doFix then
                    pcall(function() o:SpawnDefaultController() end)
                    local c2 = o.Controller
                    Log("[izdiag]   SpawnDefaultController -> "
                        .. ((c2 and c2:IsValid()) and c2:GetFullName() or "still NONE"))
                end
            end)
            ok, err = pcall(function()
                local cm = o.CharacterMovement
                if cm and cm:IsValid() then
                    Log(string.format("[izdiag]   movement mode=%s maxwalk=%.0f gravity=%.2f",
                        tostring(cm.MovementMode), cm.MaxWalkSpeed, cm.GravityScale))
                else
                    Log("[izdiag]   charmovement: nil/invalid")
                end
            end)
            if not ok then Log("[izdiag]   charmovement ERR: " .. tostring(err)) end
        end
        -- BP_Izbushka is a plain Actor: its skeletal mesh lives in a custom
        -- component, not Character.Mesh. Enumerate mesh components by owner name.
        for _, clsName in ipairs({ "SkeletalMeshComponent", "StaticMeshComponent" }) do
            pcall(function()
                for _, c in ipairs(FindAllOf(clsName) or {}) do
                    local fn = ""
                    pcall(function() fn = c:GetFullName() end)
                    if fn:lower():find("izbushka") then
                        local wz, rz = "?", "?"
                        pcall(function() wz = string.format("%.1f", c:K2_GetComponentLocation().Z) end)
                        pcall(function() rz = string.format("%.1f", c.RelativeLocation.Z) end)
                        Log(string.format("[izdiag] comp %s worldZ=%s relZ=%s", fn, wz, rz))
                    end
                end
            end)
        end
    end)
    return true
end)

-- Lift all spawned Izbushka actors by <dz> units (default 200). The BP is a
-- plain Actor (no movement component / gravity), so it never settles on its
-- own — nudge it until the legs clear the ground, then bake the offset into
-- the spawn fix.
-- Snap all Izbushka actors to playerZ + <offset> (default 400). Calibration
-- helper: stand on flat ground, tweak offset until the legs touch; that
-- constant becomes the spawn fix's Z offset.
RegisterConsoleCommandHandler(".izsnap", function(FullCommand, Parameters)
    local off = tonumber(Parameters[1] or "") or 400
    ExecuteInGameThread(function()
        local pl = GetPlayerCharacter()
        local ploc = pl and pl:K2_GetActorLocation()
        if not ploc then Log("[izsnap] no player") return end
        for _, o in ipairs(FindAllOf("BP_Izbushka_C") or {}) do
            pcall(function()
                local loc = o:K2_GetActorLocation()
                local rot = o:K2_GetActorRotation()
                o:K2_TeleportTo({ X = loc.X, Y = loc.Y, Z = ploc.Z + off }, rot)
                Log(string.format("[izsnap] %s Z -> %.1f (playerZ %.1f + %d)",
                    o:GetFullName(), ploc.Z + off, ploc.Z, off))
            end)
        end
    end)
    return true
end)

RegisterConsoleCommandHandler(".izlift", function(FullCommand, Parameters)
    local dz = tonumber(Parameters[1] or "") or 200
    ExecuteInGameThread(function()
        for _, o in ipairs(FindAllOf("BP_Izbushka_C") or {}) do
            pcall(function()
                local loc = o:K2_GetActorLocation()
                local rot = o:K2_GetActorRotation()
                o:K2_TeleportTo({ X = loc.X, Y = loc.Y, Z = loc.Z + dz }, rot)
                Log(string.format("[izlift] %s Z %.1f -> %.1f",
                    o:GetFullName(), loc.Z, loc.Z + dz))
            end)
        end
    end)
    return true
end)

-- Probe whether an asset exists at a path and try to force-load it (diagnostic).
-- Usage: .loadclass /Game/Blueprints/AI/BP_Zombie.BP_Zombie_C
RegisterConsoleCommandHandler(".loadclass", function(FullCommand, Parameters)
    local path = Parameters[1]
    if not path or path == "" then
        Log("[loadclass] Usage: .loadclass /Game/Path/Asset.Asset_C")
        return true
    end
    ExecuteInGameThread(function()
        -- Try several find paths for one package; report whichever resolves.
        local pkg = path:gsub("%.[%w_]+$", ""):gsub("_C$", "")  -- /Game/.../BP_X
        local asset = pkg:match("([%w_]+)$")                     -- BP_X
        local candidates = {
            path,                                  -- as given
            pkg .. "." .. asset .. "_C",           -- class object
            pkg .. "." .. asset,                   -- asset object
            pkg .. ".Default__" .. asset .. "_C",  -- CDO
        }
        local function probe(label)
            for _, p in ipairs(candidates) do
                local obj = nil
                pcall(function() obj = StaticFindObject(p) end)
                if obj and obj.IsValid and obj:IsValid() then
                    Log("[loadclass] " .. label .. ": FOUND " .. obj:GetFullName())
                    return true
                end
            end
            Log("[loadclass] " .. label .. ": none of " .. #candidates .. " paths resolved")
            return false
        end
        -- Reliable class detector: walk the WHOLE UObject array (same as
        -- .findclass) and look for the BlueprintGeneratedClass by exact FName.
        -- (FindAllOf returns INSTANCES of a class, not the class object, so it is
        -- the wrong tool for "is this class loaded".)
        local clsFName = asset .. "_C"
        local function classLoaded(label)
            local found = nil
            pcall(function()
                ForEachUObject(function(o)
                    if found then return false end
                    local n = ""
                    pcall(function() n = o:GetFName():ToString() end)
                    if n == clsFName then found = o end
                    return false
                end)
            end)
            Log("[loadclass] " .. label .. ": class '" .. clsFName .. "' "
                .. (found and ("LOADED -> " .. tostring(found:GetFullName())) or "not in array"))
            return found
        end
        Log("[loadclass] LoadAsset is a " .. type(LoadAsset))
        if classLoaded("pre-load") then return end
        -- Brute-force every LoadAsset argument form; scan after each.
        local forms = {
            pkg,                                   -- /Game/.../BP_X
            pkg .. "." .. asset,                   -- ...BP_X.BP_X
            pkg .. "." .. asset .. "_C",           -- ...BP_X.BP_X_C  (the class)
            pkg .. "." .. "Default__" .. asset .. "_C",
        }
        for _, f in ipairs(forms) do
            pcall(function() LoadAsset(f) end)
            if classLoaded("after LoadAsset('" .. f .. "')") then return end
        end
        -- Maybe async — recheck after 1s.
        LoopAsync(1000, function()
            ExecuteInGameThread(function() classLoaded("+1s") end)
            return true
        end)
    end)
    return true
end)

-- Toggle verbose FS_InvItem dump in the AttemptToAddItem hook
-- .invcheck [fix]: what the game thinks about the inventory's modifier keys.
-- For the bug where a dragged stack splits in half and Shift+click quick
-- move does nothing: the inventory's IsSplitKeyDown may stay on after a
-- missed key release. "fix" turns it off.
RegisterConsoleCommandHandler(".invcheck", function(FullCommand, Parameters)
    local fix = string.lower(tostring((Parameters and Parameters[1]) or "")) == "fix"
    ExecuteInGameThread(function()
        local inv, pc = GetInventory(), GetPlayerController()
        if not inv then Log("[invcheck] No inventory found - load into a world first") return end
        local split = nil
        pcall(function() split = inv.IsSplitKeyDown end)
        local held = {}
        for _, key in ipairs({ "LeftShift", "RightShift", "LeftControl", "LeftAlt" }) do
            local down = nil
            pcall(function() down = pc:IsInputKeyDown({ KeyName = FName(key) }) end)
            table.insert(held, key .. "=" .. tostring(down))
        end
        Log("[invcheck] IsSplitKeyDown=" .. tostring(split) .. "  keys held now: " .. table.concat(held, " "))
        -- the open containers' own rules: a count or weight limit or an item
        -- restriction makes the game refuse a whole stack (Shift+click) or
        -- take only part of it (drag)
        local D = {
            cells = "ContainerInventoryCells_13_269D7DB442A1056CD715DEA438F850A2",
            useWeight = "UseWeight_16_3F94FD134C121CE317A6D2A0C2938171",
            maxWeight = "MaxWeight_20_5CDB778F4D6FE3E65C8DD1A7E8722133",
            restriction = "ContainerRestrictionType_23_EC5805D64D1B1EF6093FA8B19DBF48C5",
            restrictionItems = "RestrictionItems_27_B3D5BDB6404ACC06A8D798BDB3047E0E",
            type = "ContainerType_33_C2D0977F47C071D4354A4BB1817475AD",
            useCount = "UseItemCountLimit_38_585327964096457C6B3EF697DA170C6F",
            countLimit = "ItemCountLimit_42_1BB0344A44E3DB354AC3DB9A4917C186",
        }
        -- the containers of what you're using now (the game keeps it as the
        -- inventory's InteractedActor: the workbench, a box...)
        local function Describe(label, cInv)
            local function get(f) local v = nil pcall(function() v = f() end) return tostring(v) end
            local d = nil
            pcall(function() d = cInv.InventoryDetails end)
            Log(string.format("[invcheck] %s: items %s, weight %s; cells %s, weight limit %s (%s), "
                .. "count limit %s (%s), restriction type %s (%s items), container type %s",
                label, get(function() return cInv.ItemCount end), get(function() return cInv.CurrentWeight end),
                get(function() return d[D.cells] end), get(function() return d[D.useWeight] end),
                get(function() return d[D.maxWeight] end), get(function() return d[D.useCount] end),
                get(function() return d[D.countLimit] end), get(function() return d[D.restriction] end),
                get(function() return d[D.restrictionItems]:GetArrayNum() end), get(function() return d[D.type] end)))
        end
        local actor = nil
        pcall(function() actor = inv.InteractedActor end)
        local shown = 0
        if actor and actor:IsValid() then
            local name = "?"
            pcall(function() name = actor:GetFName():ToString() end)
            local cls = StaticFindObject("/Game/SurvivalGameKitV2/Components/BP_MasterInventory.BP_MasterInventory_C")
            local function Each(comp)
                pcall(function() if type(comp) ~= "table" and comp.get then comp = comp:get() end end)
                if comp and comp:IsValid() then
                    shown = shown + 1
                    local cname = "?"
                    pcall(function() cname = comp:GetFName():ToString() end)
                    Describe(name .. " / " .. cname, comp)
                end
            end
            local list = nil
            pcall(function() list = actor:K2_GetComponentsByClass(cls) end)
            if type(list) == "table" then
                for _, c in pairs(list) do pcall(Each, c) end
            elseif list then
                pcall(function() list:ForEach(function(_, e) pcall(Each, e:get()) end) end)
            end
            if shown == 0 then Log("[invcheck] " .. name .. " has no container of its own") end
        else
            Log("[invcheck] Not using anything - open the workbench (or the box) and run .invcheck again")
        end
        if fix then
            local ok = pcall(function() inv.IsSplitKeyDown = false end)
            local after = nil
            pcall(function() after = inv.IsSplitKeyDown end)
            Log("[invcheck] fix: IsSplitKeyDown set to false (" .. (ok and "ok" or "failed") .. "), now " .. tostring(after))
        elseif split == true then
            Log("[invcheck] The game thinks the split key is held. .invcheck fix turns it off - then try dragging again")
        end
    end)
    return true
end)

-- .movecheck: what decides how fast you move, right now. For the bug where
-- sprinting sometimes is very slow: run it while it happens. The game sets
-- the speed from the inventory's MovementSpeeds (one per state), or the held
-- item's own MovementSpeeds when it has UseHoldableMovementSpeeds.
-- .movecheck watch: the same, twice a second for 30 s, so it catches the
-- slow sprint while it happens (typing .movecheck stops the character)
local moveWatch = { untilClock = 0, running = false }
local function MoveWatchLine()
    local inv, char = GetInventory(), GetPlayerCharacter()
    if not (inv and char) then return end
    local function get(f) local v = nil pcall(function() v = f() end) return v end
    local cm = get(function() return char.CharacterMovement end)
    local speed = get(function() local v = char:GetVelocity() return math.sqrt(v.X * v.X + v.Y * v.Y) end)
    local mode = get(function() return cm.MovementMode end)
    -- where you look up/down (the controller's and the camera's) and how long
    -- the movement input is: moving along a tilted view keeps only cos(pitch)
    -- of the speed (the slow sprint ran at exactly 0.707 of normal, 17 Oct)
    local pc = get(function() return char.Controller end)
    local function pitch(v) if type(v) ~= "number" then return "?" end if v > 180 then v = v - 360 end return string.format("%.0f", v) end
    local ctrlPitch = get(function() return pc.ControlRotation.Pitch end)
    local camPitch = get(function() return pc.PlayerCameraManager:GetCameraRotation().Pitch end)
    local input = get(function() local v = cm:GetLastInputVector() return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end)
    -- which movement keys are down, and the way you move compared with the
    -- way you face (0 = straight ahead, 90 = sideways): many games only let
    -- you sprint straight ahead, and moving diagonally keeps 0.707 of a speed
    local keys = ""
    for _, k in ipairs({ "W", "A", "S", "D" }) do
        local down = false
        pcall(function() down = pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if down then keys = keys .. k end
    end
    local heading = get(function()
        local v = char:GetVelocity()
        if math.sqrt(v.X * v.X + v.Y * v.Y) < 20 then return nil end
        local moveYaw = math.deg(math.atan(v.Y, v.X))
        local d = (moveYaw - pc.ControlRotation.Yaw) % 360
        if d > 180 then d = d - 360 end
        return d
    end)
    Log(string.format("[movewatch] state %s, sprint key %s, max speed %s, moving at %s, stamina %s, mode %s, crouched %s, "
        .. "look pitch ctrl %s cam %s, input %s, keys %s, moving %s deg from facing",
        tostring(get(function() return inv.CurrentCharacterState end)), tostring(get(function() return inv.SprintKeyDown end)),
        tostring(get(function() return math.floor(cm.MaxWalkSpeed) end)), tostring(speed and math.floor(speed) or "?"),
        tostring(get(function() return math.floor(inv.CurrentStamina) end)), tostring(mode),
        tostring(get(function() return char.bIsCrouched end)), pitch(ctrlPitch), pitch(camPitch),
        input and string.format("%.2f", input) or "?", keys ~= "" and keys or "-",
        heading and string.format("%.0f", heading) or "-"))
end

RegisterConsoleCommandHandler(".movecheck", function(FullCommand, Parameters)
    if string.lower(tostring((Parameters and Parameters[1]) or "")) == "watch" then
        moveWatch.untilClock = os.clock() + 30
        Log("[movewatch] Logging how you move twice a second for 30 s - sprint now, and keep going when it gets slow")
        if not moveWatch.running then
            moveWatch.running = true
            LoopAsync(500, function()
                if os.clock() > moveWatch.untilClock then
                    moveWatch.running = false
                    Log("[movewatch] Done")
                    return true
                end
                ExecuteInGameThread(function() pcall(MoveWatchLine) end)
                return false
            end)
        end
        return true
    end
    ExecuteInGameThread(function()
        local inv, char = GetInventory(), GetPlayerCharacter()
        if not (inv and char) then Log("[movecheck] Load into a world first") return end
        local function get(f) local v = nil pcall(function() v = f() end) return v end
        local enum = StaticFindObject("/Game/SurvivalGameKitV2/Blueprints/Other/Enum/E_CharacterState.E_CharacterState")
        local lib = StaticFindObject("/Script/Engine.Default__KismetNodeHelperLibrary")
        local function StateName(n)
            local name = get(function() return lib:GetEnumeratorUserFriendlyName(enum, n):ToString() end)
            return tostring(n) .. (name and ("=" .. name) or "")
        end
        local function Speeds(map)
            local parts = {}
            pcall(function()
                map:ForEach(function(k, v)
                    local key, value = k, v
                    pcall(function() key = k:get() end)
                    pcall(function() value = v:get() end)
                    table.insert(parts, StateName(key) .. ":" .. string.format("%.0f", tonumber(value) or -1))
                end)
            end)
            return #parts > 0 and table.concat(parts, " ") or "(couldn't read)"
        end
        local state = get(function() return inv.CurrentCharacterState end)
        local cm = get(function() return char.CharacterMovement end)
        local speedNow = get(function()
            local v = char:GetVelocity()
            return math.sqrt(v.X * v.X + v.Y * v.Y)
        end)
        Log(string.format("[movecheck] state %s, sprint key %s, stamina %s / %s, joined %s",
            state and StateName(state) or "?", tostring(get(function() return inv.SprintKeyDown end)),
            tostring(get(function() return math.floor(inv.CurrentStamina) end)),
            tostring(get(function() return math.floor(inv.MaxStamina) end)), tostring(Coop.Joined())))
        Log(string.format("[movecheck] max speed now %s, moving at %s, movement mode %s",
            tostring(get(function() return math.floor(cm.MaxWalkSpeed) end)),
            tostring(speedNow and math.floor(speedNow) or "?"), tostring(get(function() return cm.MovementMode end))))
        Log("[movecheck] speeds by state: " .. Speeds(get(function() return inv.MovementSpeeds end)))
        local held = get(function() return inv.NewHoldingItem end)
        if held and get(function() return held:IsValid() end) then
            local name = get(function() return held:GetFName():ToString() end) or "?"
            local own = get(function() return held.UseHoldableMovementSpeeds end)
            Log("[movecheck] holding " .. name .. ", its own speeds " .. tostring(own)
                .. (own and (": " .. Speeds(get(function() return held.MovementSpeeds end))) or ""))
        else
            Log("[movecheck] holding nothing")
        end
    end)
    return true
end)

RegisterConsoleCommandHandler(".dumpinv", function(FullCommand, Parameters)
    local arg = string.lower(Parameters[1] or "")
    if arg == "on" or arg == "1" or arg == "true" then
        _G.__DumpInvItem = true
        Log("[dumpinv] FS_InvItem dump ON. Pick up an item to see all fields.")
    elseif arg == "off" or arg == "0" or arg == "false" then
        _G.__DumpInvItem = false
        Log("[dumpinv] FS_InvItem dump OFF.")
    else
        Log("[dumpinv] State: " .. (_G.__DumpInvItem and "ON" or "OFF"))
        Log("[dumpinv] Usage: .dumpinv on|off")
    end
    return true
end)

-- Pick up loaded world items — calls Pickup/Interact on the item actor directly
RegisterConsoleCommandHandler(".pickup", function(FullCommand, Parameters)
    local filter = (Parameters[1] ~= "" and Parameters[1] ~= nil) and Parameters[1]:lower() or nil
    local maxCount = tonumber(Parameters[2]) or 5
    ExecuteInGameThread(function()
        local inv = GetInventory()
        local player = GetPlayerCharacter()
        if not inv then Log("No inventory found") return end

        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items or #items == 0 then
            Log("No items in current area. Walk to where items spawn first.")
            return
        end

        local picked = 0
        local total = 0
        for _, item in ipairs(items) do
            local rn = "?"
            pcall(function() rn = item["Item"]["RowName"]:ToString() end)
            local matches = not filter or rn:lower():find(filter, 1, true)
            if matches then
                total = total + 1
                if picked < maxCount then
                    local methods = {
                        {"item:Pickup(inv)",         function() item:Pickup(inv) end},
                        {"item:Interact(player)",    function() item:Interact(player) end},
                        {"item:Interact(inv)",       function() item:Interact(inv) end},
                        {"inv:ServerInteract(item)", function() inv:ServerInteract(item) end},
                        {"inv:ServerInteract(item,0)", function() inv:ServerInteract(item, 0) end},
                    }
                    local anyOk = false
                    for _, m in ipairs(methods) do
                        local ok, err = pcall(m[2])
                        if ok then
                            Log("Pickup OK [" .. m[1] .. "]: " .. rn)
                            picked = picked + 1
                            anyOk = true
                            break
                        else
                            Log("  [" .. m[1] .. "] ERR: " .. tostring(err):sub(1, 60))
                        end
                    end
                    if not anyOk then Log("All methods failed: " .. rn) end
                end
            end
        end

        Log("World items: " .. #items .. ", matched: " .. total .. ", picked: " .. picked)
    end)
    return true
end)

-- Query how many of a given item are in inventory
RegisterConsoleCommandHandler(".invcount", function(FullCommand, Parameters)
    local itemID = Parameters[1] or "Weapon_SmallAxe"
    ExecuteInGameThread(function()
        local inv = GetInventory()
        if not inv then Log("No inventory") return end
        local ok, result = pcall(function()
            return inv:PlayerInventoryTotalItemAmount(itemID)
        end)
        Log("Inv count [" .. itemID .. "]: " .. (ok and tostring(result) or "ERR: " .. tostring(result):sub(1,60)))
    end)
    return true
end)

-- Count world instances of a specific item by RowName (use before/after .give to detect world spawning)
RegisterConsoleCommandHandler(".countworld", function(FullCommand, Parameters)
    local itemID = Parameters[1] or "Weapon_SmallAxe"
    ExecuteInGameThread(function()
        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items then Log("World count [" .. itemID .. "]: 0") return end
        local count = 0
        for _, item in ipairs(items) do
            pcall(function()
                local rn = item["Item"]["RowName"]:ToString()
                if rn == itemID then count = count + 1 end
            end)
        end
        Log("World count [" .. itemID .. "]: " .. count .. " (of " .. #items .. " total world items)")
    end)
    return true
end)

-- Show player's actual Blueprint class and its parents
RegisterConsoleCommandHandler(".playerclass", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("No player") return end
        local cls = player:GetClass()
        local depth = 0
        while cls and not cls:IsNull() and depth < 8 do
            local ok, name = pcall(function() return cls:GetFullName() end)
            Log("  class[" .. depth .. "]: " .. (ok and name or "?"))
            depth = depth + 1
            local ok2, parent = pcall(function() return cls:GetSuperClass() end)
            if not ok2 or not parent or parent:IsNull() then break end
            cls = parent
        end
    end)
    return true
end)

-- List functions on BP_StaticMasterItem_C (world pickup items)
RegisterConsoleCommandHandler(".itemclassfuncs", function(FullCommand, Parameters)
    local filter = Parameters[1] or "StaticMasterItem"
    Log("Functions on: " .. filter)
    local count = 0
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name and string.find(name, "^Function") and string.find(name, filter, 1, true) then
            Log("  " .. name)
            count = count + 1
        end
        return false
    end)
    Log("Total: " .. count)
    return true
end)

-- Test ServerSpawnSupportUshanka — no params, hardcoded item, best Server RPC smoke test
RegisterConsoleCommandHandler(".ushanka", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("No player") return end
        local ok, err = pcall(function() player:ServerSpawnSupportUshanka() end)
        Log("ServerSpawnSupportUshanka: " .. (ok and "ok - check inventory AND ground near you!" or tostring(err):sub(1,80)))
    end)
    return true
end)

-- Find the DataTable's full UObject path for StaticFindObject lookup
RegisterConsoleCommandHandler(".dtpath", function(FullCommand, Parameters)
    local search = (Parameters[1] or "masteritem"):lower()
    Log("Searching DataTable paths containing: " .. search)
    local found = 0
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            local lower = string.lower(name)
            if (string.find(name, "DataTable") or string.find(name, "CompositeDataTable"))
               and string.find(lower, search) then
                Log("  " .. name)
                found = found + 1
            end
        end
        return false
    end)
    Log("Found " .. found .. " DataTable(s)")
    return true
end)

-- Try ServerSpawnItemDebug with alternate ID formats
RegisterConsoleCommandHandler(".givealt", function(FullCommand, Parameters)
    local base = Parameters[1]
    if not base then
        Log("Usage: .givealt BaseName")
        Log("Tries multiple ID format variants of the name.")
        return true
    end
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("Player not found!") return end
        local variants = {
            base,
            "BP_" .. base,
            "BP_" .. base .. "_C",
            base .. "_C",
            string.lower(base),
            string.upper(base),
        }
        for _, v in ipairs(variants) do
            local ok, err = pcall(function() player:ServerSpawnItemDebug(v, 1) end)
            Log("  " .. v .. " -> " .. (ok and "no error" or tostring(err):sub(1,40)))
        end
        Log("Check inventory after each — whichever gave an item is the right format.")
    end)
    return true
end)

-- Dump player character functions - find real item-give method names
RegisterConsoleCommandHandler(".charfuncs", function(FullCommand, Parameters)
    local filter = (Parameters[1] or ""):lower()
    Log("Listing player character functions" .. (filter ~= "" and (" (filter: " .. filter .. ")") or "") .. "...")
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("Player character not found!") return end
        local ok, err = pcall(function()
            local funcs = {}
            for func in player:GetClass():Functions() do
                local name = func:GetName()
                if name and (filter == "" or name:lower():find(filter, 1, true)) then
                    table.insert(funcs, name)
                end
            end
            table.sort(funcs)
            local shown = 0
            for _, name in ipairs(funcs) do
                if shown < 80 then Log("  " .. name) end
                shown = shown + 1
            end
            Log("Total: " .. shown .. " functions" .. (filter ~= "" and "" or " (use .charfuncs spawn/give/item to filter)"))
        end)
        if not ok then Log("Error: " .. tostring(err)) end
    end)
    return true
end)

-- Find the full class path for an item (tries WorldItem version first)
local function FindItemClassPath(itemID)
    local foundPath = nil
    local isWorldItem = false

    -- First try to find WorldItem version (BP_XXX_WI_C)
    local wiName = string.gsub(itemID, "_C$", "") .. "_WI"
    ForEachUObject(function(obj)
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then
            if string.find(name, "BlueprintGeneratedClass") and
               string.find(name, wiName .. "_C") then
                foundPath = string.match(name, "BlueprintGeneratedClass (.+)")
                isWorldItem = true
                return true
            end
        end
        return false
    end)

    -- If no WorldItem, try regular item
    if not foundPath then
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                if string.find(name, "BlueprintGeneratedClass") and
                   string.find(name, itemID .. "_C") then
                    foundPath = string.match(name, "BlueprintGeneratedClass (.+)")
                    return true
                end
            end
            return false
        end)
    end

    return foundPath, isWorldItem
end

-- Spawn item worker function
local function DoSpawnItem(itemID, amount)
    ExecuteInGameThread(function()
        -- Get player location for spawning
        local player = GetPlayerCharacter()
        if not player then
            Log("Player not found!")
            return
        end

        local loc = nil
        pcall(function()
            loc = player:K2_GetActorLocation()
        end)

        if not loc then
            Log("Could not get player location")
            return
        end

        -- Find the actual class path
        local classPath, isWorldItem = FindItemClassPath(itemID)

        -- Try to find BP_StaticMasterItem for spawning
        local masterItemClass = nil
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name and string.find(name, "BP_StaticMasterItem_C") and
               string.find(name, "BlueprintGeneratedClass") then
                masterItemClass = obj
                return true
            end
            return false
        end)

        local spawned = 0

        for i = 1, amount do
            local spawnLoc = {
                X = loc.X + (i * 100),
                Y = loc.Y + 200,
                Z = loc.Z + 50
            }
            local rot = { Pitch = 0, Yaw = 0, Roll = 0 }

            -- Method 1: Try spawning WorldItem version directly
            if isWorldItem and classPath then
                pcall(function()
                    local itemClass = StaticFindObject(classPath)
                    if itemClass then
                        local world = player:GetWorld()
                        if world then
                            local actor = world:SpawnActor(itemClass, spawnLoc, rot)
                            if actor then
                                spawned = spawned + 1
                                Log("Spawned WorldItem!")
                            end
                        end
                    end
                end)
            end

            -- Method 2: Try using MasterItemSpawner
            if spawned == 0 then
                pcall(function()
                    local spawners = FindAllOf("BP_MasterItemSpawner_C")
                    if spawners and #spawners > 0 then
                        local spawner = spawners[1]
                        -- Try to call spawn function
                        pcall(function() spawner:SpawnItem(itemID) end)
                        pcall(function() spawner:Spawn() end)
                        spawned = spawned + 1
                    end
                end)
            end

            -- Method 3: Clone existing world item
            if spawned == 0 then
                pcall(function()
                    local existingItems = FindAllOf("BP_StaticMasterItem_C")
                    if existingItems and #existingItems > 0 then
                        local template = existingItems[1]
                        local templateClass = template:GetClass()
                        if templateClass then
                            local world = player:GetWorld()
                            if world then
                                world:SpawnActor(templateClass, spawnLoc, rot)
                                spawned = spawned + 1
                            end
                        end
                    end
                end)
            end

            -- Method 4: Summon command
            if spawned == 0 then
                pcall(function()
                    ExecuteConsoleCommand("Summon " .. itemID .. "_C")
                end)
            end
        end

        if spawned > 0 then
            Log("Spawned! Check around you")
        else
            Log("Item spawn not available for: " .. itemID)
            Log("Use .menu for dev cheat menu item spawning")
        end
    end)
end

-- Cache items command
RegisterConsoleCommandHandler(".cacheitems", function(FullCommand, Parameters)
    Log("Building item cache...")
    ExecuteInGameThread(function()
        BuildItemCache()
        local count = 0
        if CachedItems then
            for _ in pairs(CachedItems) do count = count + 1 end
        end
        Log("Cached " .. count .. " items")
    end)
    return true
end)

-- Find item class path (debug)
RegisterConsoleCommandHandler(".finditem", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "ak")
    Log("Searching for item classes containing: " .. search)
    ExecuteInGameThread(function()
        local found = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                local lower = string.lower(name)
                if string.find(lower, search) and
                   (string.find(name, "BlueprintGeneratedClass") or string.find(name, "Class'")) and
                   string.find(lower, "item") then
                    table.insert(found, name)
                end
            end
            return false
        end)

        if #found == 0 then
            -- Try broader search
            ForEachUObject(function(obj)
                local ok, name = pcall(function() return obj:GetFullName() end)
                if ok and name then
                    local lower = string.lower(name)
                    if string.find(lower, search) and string.find(name, "BlueprintGeneratedClass") then
                        table.insert(found, name)
                    end
                end
                return false
            end)
        end

        for i, name in ipairs(found) do
            if i <= 15 then
                Log("  " .. name)
            end
        end
        Log("Found " .. #found .. " matching classes")
    end)
    return true
end)

-- Find WorldItem versions of items
RegisterConsoleCommandHandler(".findwi", function(FullCommand, Parameters)
    local search = string.lower(Parameters[1] or "")
    Log("Searching for WorldItems (_WI)...")
    ExecuteInGameThread(function()
        local found = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                if string.find(name, "BlueprintGeneratedClass") and string.find(name, "_WI") then
                    if search == "" or string.find(string.lower(name), search) then
                        local className = string.match(name, "(BP_[%w_]+_WI)_C")
                        if className then
                            found[className] = true
                        end
                    end
                end
            end
            return false
        end)

        local sorted = {}
        for name, _ in pairs(found) do
            table.insert(sorted, name)
        end
        table.sort(sorted)

        for i, name in ipairs(sorted) do
            if i <= 30 then
                Log("  " .. name)
            end
        end
        Log("Found " .. #sorted .. " WorldItems")
        Log("These can be spawned as pickups!")
    end)
    return true
end)

-- Find pickup/spawn related classes
RegisterConsoleCommandHandler(".findspawn", function(FullCommand, Parameters)
    Log("Searching for pickup/spawn related classes...")
    ExecuteInGameThread(function()
        local found = {}
        ForEachUObject(function(obj)
            local ok, name = pcall(function() return obj:GetFullName() end)
            if ok and name then
                local lower = string.lower(name)
                if string.find(name, "BlueprintGeneratedClass") and
                   (string.find(lower, "pickup") or string.find(lower, "drop") or
                    string.find(lower, "loot") or string.find(lower, "worlditem") or
                    string.find(lower, "spawnitem") or string.find(lower, "itemspawn")) then
                    table.insert(found, name)
                end
            end
            return false
        end)

        for i, name in ipairs(found) do
            if i <= 20 then
                Log("  " .. name)
            end
        end
        Log("Found " .. #found .. " pickup-related classes")
    end)
    return true
end)

-- Try to get cheat menu and list its functions
RegisterConsoleCommandHandler(".cheatfuncs", function(FullCommand, Parameters)
    Log("Looking for cheat menu functions...")
    ExecuteInGameThread(function()
        local cheatMenu = GetCheatMenuWidget()

        if cheatMenu then
            Log("Found cheat menu instance!")
            local count = 0
            pcall(function()
                for func in cheatMenu:GetClass():Functions() do
                    local fname = func:GetName()
                    if fname and #fname > 0 then
                        count = count + 1
                        if count <= 30 then
                            Log("  " .. fname)
                        end
                    end
                end
            end)
            Log("Total: " .. count .. " functions")
        else
            Log("Cheat menu not found - open it with .menu first?")
        end
    end)
    return true
end)

-- Spawn item with fuzzy matching
RegisterConsoleCommandHandler(".spawn", function(FullCommand, Parameters)
    local search = Parameters[1]
    local amount = tonumber(Parameters[2]) or 1

    if not search then
        Log("Usage: .spawn <item> [amount]")
        Log("Examples:")
        Log("  .spawn vodka      - spawns vodka")
        Log("  .spawn vod        - fuzzy matches vodka")
        Log("  .spawn bandage 5  - spawns 5 bandages")
        Log("Use .items [filter] to see available items")
        return true
    end

    -- Check if cache exists
    if not CachedItems then
        Log("Item cache not ready. Building now...")
        ExecuteInGameThread(function()
            BuildItemCache()
            local count = 0
            if CachedItems then
                for _ in pairs(CachedItems) do count = count + 1 end
            end
            Log("Cached " .. count .. " items. Try .spawn again")
        end)
        return true
    end

    -- Find matching items (no ForEachUObject here - cache already built)
    local matches = FindMatchingItems(search, 5)

    if not matches or #matches == 0 then
        Log("No items found matching: " .. search)
        Log("Use .items to see available items")
        return true
    end

    -- Use the best match
    local itemID = matches[1]

    -- Show what we matched (helpful feedback)
    if #matches > 1 then
        Log("Matched: " .. itemID)
        local otherMatches = {}
        for i = 2, math.min(4, #matches) do
            table.insert(otherMatches, matches[i])
        end
        if #otherMatches > 0 then
            Log("Other matches: " .. table.concat(otherMatches, ", "))
        end
    else
        Log("Spawning: " .. itemID .. " x" .. amount)
    end

    -- Call worker function
    DoSpawnItem(itemID, amount)

    return true
end)

-- Spawn enemy worker function
local function DoSpawnEnemy(enemyData, count)
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then
            Log("Player not found!")
            return
        end

        -- Get player location
        local loc = nil
        pcall(function()
            loc = player:K2_GetActorLocation()
        end)

        if not loc then
            Log("Could not get player location")
            return
        end

        -- Force-load the class (handles AIs not referenced by the level, e.g.
        -- BP_ZombieSoilder). StaticFindObject can't find these and a package-only
        -- LoadAsset no-ops — LoadBPClass uses the working full-path form.
        local baseName = string.gsub(enemyData.id, "_C$", "")
        local enemyClass = LoadBPClass("/Game/Blueprints/AI/" .. baseName)
        if not enemyClass then
            Log("Could not load class " .. enemyData.id .. " — asset path may differ")
            return
        end

        local world = player:GetWorld()
        if not world then
            Log("No world to spawn into")
            return
        end

        -- Spawn above ground (+300 default) so gravity-driven characters fall and
        -- settle on their feet. Non-gravity actors (plain-Actor BPs like Izbushka)
        -- never settle, so they carry an exact per-type zOffset instead.
        local zOff = enemyData.zOffset or 300
        local spawned = 0
        for i = 1, count do
            local spawnLoc = { X = loc.X + (i * 100), Y = loc.Y + 200, Z = loc.Z + zOff }
            local ok = pcall(function()
                world:SpawnActor(enemyClass, spawnLoc, {Pitch=0, Yaw=0, Roll=0})
            end)
            if ok then spawned = spawned + 1 end
        end

        if spawned > 0 then
            Log("Spawned " .. spawned .. " " .. enemyData.name .. "(s)!")
        else
            Log("Class loaded but SpawnActor failed for " .. enemyData.name)
        end
    end)
end

-- Spawn enemy with fuzzy matching
RegisterConsoleCommandHandler(".enemy", function(FullCommand, Parameters)
    pcall(function()
        local search = Parameters[1]
        local count = tonumber(Parameters[2]) or 1

        if not search then
            Log("Usage: .enemy <type> [count]")
            Log("Examples:")
            Log("  .enemy zombie     - spawns a zombie")
            Log("  .enemy ghoul 3    - spawns 3 ghouls")
            Log("  .enemy plague     - spawns plague doctor")
            Log("")
            Log("Available enemies:")
            for _, enemy in ipairs(EnemyTypes) do
                Log("  " .. enemy.aliases[1] .. " - " .. enemy.name)
            end
            return
        end

        local enemy = FindMatchingEnemy(search)

        if not enemy then
            Log("Unknown enemy: " .. search)
            Log("Use .enemy to see available types")
            return
        end

        Log("Spawning " .. count .. "x " .. enemy.name .. "...")

        -- Call worker function
        DoSpawnEnemy(enemy, count)
    end)
    return true
end)

-- Saved position for teleport
local savedPosition = nil

-- Save current position
RegisterConsoleCommandHandler(".savepos", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then
            Log("Player not found!")
            return
        end

        pcall(function()
            savedPosition = player:K2_GetActorLocation()
            Log("Position saved!")
            Log("  X: " .. math.floor(savedPosition.X))
            Log("  Y: " .. math.floor(savedPosition.Y))
            Log("  Z: " .. math.floor(savedPosition.Z))
        end)
    end)
    return true
end)

-- Load/teleport to saved position
RegisterConsoleCommandHandler(".loadpos", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        if not savedPosition then
            Log("No position saved! Use .savepos first")
            return
        end

        local player = GetPlayerCharacter()
        if not player then
            Log("Player not found!")
            return
        end

        pcall(function()
            player:K2_SetActorLocation(savedPosition, false, {}, true)
            Log("Teleported to saved position!")
        end)
    end)
    return true
end)

-- Infinite Stamina toggle
local infStaminaEnabled = false

local function StartStaminaLoop()
    LoopAsync(100, function()
        if not infStaminaEnabled then
            ExecuteInGameThread(function() Coop.Mode("INFSTAM", false) end)
            return true  -- Stop
        end

        ExecuteInGameThread(function()
            if Coop.Joined() then Coop.Mode("INFSTAM", true) return end
            local Inv = GetInventory()
            if Inv then
                pcall(function() Inv["IncreaseStamina"](Inv, 9999) end)
            end
        end)

        return false  -- Continue
    end)
end

RegisterConsoleCommandHandler(".infstam", function(FullCommand, Parameters)
    infStaminaEnabled = not infStaminaEnabled

    if infStaminaEnabled then
        Log("INFINITE STAMINA: ON")
        StartStaminaLoop()
    else
        Log("INFINITE STAMINA: OFF")
    end
    return true
end)

-- Get GlobalManager (now only used for FreezeTime/UnfreezeTime)
local function GetGlobalManager()
    local gm = nil
    pcall(function()
        local gms = FindAllOf("BP_GlobalManager_C")
        if gms and #gms > 0 then
            gm = gms[1]
        end
    end)
    return gm
end

-- Get WeatherManager for time/weather/season (moved here from GlobalManager after game update)
local function GetWeatherManager()
    local wm = nil
    pcall(function()
        local wms = FindAllOf("BP_MultiplayerDynamicWeatherManager_C")
        if wms and #wms > 0 then wm = wms[1] end
    end)
    return wm
end

-- Set Time of Day
RegisterConsoleCommandHandler(".time", function(FullCommand, Parameters)
    local time = tonumber(Parameters[1])
    if not time then
        Log("Usage: .time <hour>")
        Log("Example: .time 12 (noon)")
        Log("Example: .time 0 (midnight)")
        Log("Example: .time 6 (sunrise)")
        Log("Example: .time 18 (sunset)")
        return true
    end

    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("WeatherManager not found!") return end
        pcall(function()
            -- Calibrated 2026-06-10: Current Time = hour * 100 (clock is linear,
            -- 2400 units per day; Day/Night Length only pace the tick rate).
            local targetTime = time * 100.0
            wm["Current Time"] = targetTime
            Log(string.format("Set CurrentTime to %.1f (hour %d)", targetTime, time))
            pcall(function() wm["Set Light Rotation"](wm) end)
            pcall(function() wm["Set Elements"](wm) end)
        end)
    end)
    return true
end)

-- Write a raw Current Time value (same safe write the Spawn AI guard uses).
-- Calibration helper: .ctset 300 / 900 / 1500, report the clock after each.
RegisterConsoleCommandHandler(".ctset", function(FullCommand, Parameters)
    local v = tonumber(Parameters[1])
    if not v then Log("[ctset] Usage: .ctset <number>") return true end
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("[ctset] WeatherManager not found") return end
        pcall(function()
            wm["Current Time"] = v
            pcall(function() wm["Set Light Rotation"](wm) end)
            pcall(function() wm["Set Elements"](wm) end)
            Log(string.format("[ctset] Current Time = %.1f — note the clock now", v))
        end)
    end)
    return true
end)

-- DO NOT USE — property iteration hard-crashes this UE4SS build on the 4th
-- property regardless of filter (2026-06-10, two Fatal Errors). Kept for
-- reference only; prefer .wmget / .ctset.
-- Usage: .wmdump [filter]
RegisterConsoleCommandHandler(".wmdump", function(FullCommand, Parameters)
    Log("[wmdump] DISABLED — property iteration fatally crashes this UE4SS build.")
    Log("[wmdump] Use .wmget <name> or .ctset <value> instead.")
    if true then return true end
    local filter = string.lower(Parameters[1] or "")
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("[wmdump] WeatherManager not found") return end
        Log("[wmdump] " .. tostring(wm:GetFullName()))

        -- NAMES + TYPES ONLY. Reading values here crashed the game (native
        -- access violation on a delegate/struct property — pcall can't catch
        -- those). Use .wmget <name> to read one numeric property safely.
        local seen = {}
        local function emitProp(prop)
            local pname = nil
            pcall(function() pname = prop:GetFName():ToString() end)
            if not pname or seen[pname] then return end
            seen[pname] = true
            if filter ~= "" and not pname:lower():find(filter, 1, true) then return end
            local ptype = "?"
            pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
            Log("[wmdump] P [" .. ptype .. "] " .. pname)
        end

        -- Method 1: class ForEachProperty (walk super chain)
        local cls = nil
        pcall(function() cls = wm:GetClass() end)
        local c = cls
        local hops = 0
        while c and hops < 6 do
            pcall(function()
                c:ForEachProperty(function(prop)
                    pcall(function() emitProp(prop) end)
                end)
            end)
            local sc = nil
            pcall(function() sc = c:GetSuperStruct() end)
            c = sc
            hops = hops + 1
        end

        -- Method 2: Properties() iterator (used by .gim)
        pcall(function()
            for prop in cls:Properties() do
                pcall(function() emitProp(prop) end)
            end
        end)

        local nProps = 0
        for _ in pairs(seen) do nProps = nProps + 1 end
        Log("[wmdump] properties emitted: " .. nProps)

        -- Functions
        pcall(function()
            local fnSeen = {}
            local c2 = cls
            local h2 = 0
            while c2 and h2 < 6 do
                pcall(function()
                    c2:ForEachFunction(function(fn)
                        pcall(function()
                            local fname = fn:GetFName():ToString()
                            if not fnSeen[fname] then
                                fnSeen[fname] = true
                                if filter == "" or fname:lower():find(filter, 1, true) then
                                    Log("[wmdump] F " .. fname)
                                end
                            end
                        end)
                    end)
                end)
                local sc2 = nil
                pcall(function() sc2 = c2:GetSuperStruct() end)
                c2 = sc2
                h2 = h2 + 1
            end
        end)
        Log("[wmdump] done.")
    end)
    return true
end)

-- Read ONE WeatherManager property by exact name (numbers/bools/strings only).
-- Usage: .wmget <Property Name With Spaces>
RegisterConsoleCommandHandler(".wmget", function(FullCommand, Parameters)
    local pname = table.concat(Parameters, " ")
    if pname == "" then Log("[wmget] Usage: .wmget <property name>") return true end
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("[wmget] WeatherManager not found") return end
        local ok, v = pcall(function() return wm[pname] end)
        if not ok then Log("[wmget] read error: " .. tostring(v)) return end
        local t = type(v)
        if t == "number" or t == "boolean" or t == "string" or t == "nil" then
            Log("[wmget] " .. pname .. " = " .. tostring(v) .. " (" .. t .. ")")
        else
            Log("[wmget] " .. pname .. " is " .. t .. " (not printing — may be unsafe)")
        end
    end)
    return true
end)

-- Calibrate the Current Time <-> clock mapping. Logs Current Time, Day/Night
-- Length and the tick rate over 4s. Run it and note what the in-game clock
-- shows at the same moment.
RegisterConsoleCommandHandler(".timecal", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("[timecal] WeatherManager not found") return end
        local t1, dayLen, nightLen = nil, nil, nil
        pcall(function() t1 = wm["Current Time"] end)
        pcall(function() dayLen = wm["Day Length"] end)
        pcall(function() nightLen = wm["Night Length"] end)
        Log(string.format("[timecal] CurrentTime=%s DayLength=%s NightLength=%s",
            tostring(t1), tostring(dayLen), tostring(nightLen)))
        LoopAsync(4000, function()
            ExecuteInGameThread(function()
                local wm2 = GetWeatherManager()
                if not wm2 then return end
                local t2 = nil
                pcall(function() t2 = wm2["Current Time"] end)
                if type(t1) == "number" and type(t2) == "number" then
                    Log(string.format("[timecal] 4s later CurrentTime=%.3f (delta %.3f/s)", t2, (t2 - t1) / 4.0))
                end
                Log("[timecal] NOW note the in-game clock time and report it.")
            end)
            return true
        end)
    end)
    return true
end)

-- Diagnose which WeatherManager field actually drives the clock.
-- Usage: .timewatch, then within 12s commit the Time spinbox (or click Spawn AI).
-- Every numeric field that changes is logged old -> new (max 4 logs per field).
RegisterConsoleCommandHandler(".timewatch", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("[timewatch] WeatherManager not found") return end
        local snap, count = {}, 0
        pcall(function()
            for prop in wm:GetClass():Properties() do
                local pname = prop:GetFName():ToString()
                local ok, v = pcall(function() return wm[pname] end)
                if ok and type(v) == "number" then
                    snap[pname] = v
                    count = count + 1
                end
            end
        end)
        Log("[timewatch] Watching " .. count .. " numeric fields for 12s — commit the Time spinbox NOW.")
        local logged, ticks = {}, 0
        LoopAsync(500, function()
            ticks = ticks + 1
            ExecuteInGameThread(function()
                local wm2 = GetWeatherManager()
                if not wm2 then return end
                for pname, old in pairs(snap) do
                    local ok, v = pcall(function() return wm2[pname] end)
                    if ok and type(v) == "number" and v ~= old then
                        logged[pname] = (logged[pname] or 0) + 1
                        if logged[pname] <= 4 then
                            Log(string.format("[timewatch] %s: %.3f -> %.3f", pname, old, v))
                        elseif logged[pname] == 5 then
                            Log("[timewatch] " .. pname .. ": (keeps changing, muted)")
                        end
                        snap[pname] = v
                    end
                end
            end)
            if ticks >= 24 then Log("[timewatch] done.") end
            return ticks >= 24
        end)
    end)
    return true
end)

-- Weather control
RegisterConsoleCommandHandler(".weather", function(FullCommand, Parameters)
    local weather = Parameters[1]
    local speed = tonumber(Parameters[2]) or 1.0

    if not weather then
        Log("Usage: .weather <type> [speed]")
        Log("Types: sunny, rain, thunder (or an integer index)")
        Log("Example: .weather sunny")
        Log("Example: .weather rain 2")
        return true
    end

    -- Static fallback index map (0-based indices into Weathers array)
    local weatherMap = { sunny = 0, rain = 1, thunder = 2 }
    local weatherIndex = tonumber(weather)

    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("WeatherManager not found!") return end

        -- Try to resolve name via the live Weathers array first
        if not weatherIndex then
            local lowerWeather = weather:lower()
            pcall(function()
                local arr = wm["Weathers"]
                if arr then
                    for i = 0, #arr - 1 do
                        local entry = tostring(arr[i]):lower()
                        if string.find(entry, lowerWeather) then
                            weatherIndex = i
                            break
                        end
                    end
                end
            end)
            if not weatherIndex then
                weatherIndex = weatherMap[lowerWeather]
            end
        end

        if weatherIndex == nil then
            Log("Unknown weather type: " .. weather)
            Log("Try: sunny, rain, thunder, or a number")
            return
        end

        pcall(function()
            wm["Toggle Change Weather"](wm, weatherIndex, speed)
            Log("Weather changing to: " .. weather .. " (index " .. weatherIndex .. ")")
        end)
    end)
    return true
end)

-- Season control
RegisterConsoleCommandHandler(".season", function(FullCommand, Parameters)
    local season = Parameters[1]
    local speed = tonumber(Parameters[2]) or 1.0
    local duration = tonumber(Parameters[3]) or 0

    if not season then
        Log("Usage: .season <type> [speed] [duration]")
        Log("Types: spring, summer, autumn, winter")
        Log("Example: .season winter")
        Log("Example: .season summer 2")
        return true
    end

    -- E_Seasons enum: spring=0, summer=1, autumn=2, winter=3
    local seasonMap = { spring = 0, summer = 1, autumn = 2, fall = 2, winter = 3 }
    local seasonIndex = tonumber(season) or seasonMap[season:lower()]

    if seasonIndex == nil then
        Log("Unknown season: " .. season)
        Log("Use: spring, summer, autumn, winter")
        return true
    end

    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("WeatherManager not found!") return end
        pcall(function()
            wm["Toggle Season"](wm, seasonIndex, speed, duration)
            Log("Season changing to: " .. season .. " (enum " .. seasonIndex .. ")")
        end)
    end)
    return true
end)

-- Crosshair-direction flight: while ghost is on, redirect the horizontal
-- velocity the game's WASD input produces along the camera's full 3D look
-- direction (forward component gets the pitch; strafe stays horizontal).
-- Look up + press W = fly up. Runs at ~30Hz, stops when ghost turns off.
-- DO NOT raise to 16ms/60Hz: LoopAsync at that rate floods the game-thread
-- queue and hard-crashes inconsistently (tested 2026-06-11, two Fatal Errors).
local function StartGhostFlyLoop()
    LoopAsync(33, function()
        if not isFlying then return true end
        ExecuteInGameThread(function()
            pcall(function()
                local char = GetPlayerCharacter()
                if not char or not char:IsValid() then return end
                local mc = char.CharacterMovement
                local v = mc.Velocity
                local pc = GetPlayerController()
                if not pc then return end
                local rot = pc.ControlRotation
                local pitchDeg = rot.Pitch
                if pitchDeg > 180 then pitchDeg = pitchDeg - 360 end
                local yaw = math.rad(rot.Yaw)
                local pitch = math.rad(pitchDeg)
                local fx, fy = math.cos(yaw), math.sin(yaw)      -- yaw forward
                local rxv, ryv = -math.sin(yaw), math.cos(yaw)   -- yaw right
                local vF = v.X * fx + v.Y * fy                   -- forward speed
                local vR = v.X * rxv + v.Y * ryv                 -- strafe speed
                local cp, sp = math.cos(pitch), math.sin(pitch)
                mc.Velocity.X = cp * fx * vF + rxv * vR
                mc.Velocity.Y = cp * fy * vF + ryv * vR
                mc.Velocity.Z = sp * vF
            end)
        end)
        return false
    end)
end

-- Ghost/noclip: set the character's movement directly. The engine Ghost cheat
-- (ExecuteCheat) no-ops in this game. MOVE_Flying = 5, MOVE_Walking = 1.
local function SetGhostMode(enabled)
    local char = GetPlayerCharacter()
    if not char or not char:IsValid() then
        Log("GHOST: player character not found")
        return false
    end
    if enabled then
        pcall(function() char:SetActorEnableCollision(false) end)
        pcall(function()
            local mc = char.CharacterMovement
            mc.GravityScale = 0.0
            mc:SetMovementMode(5, 0)
        end)
        -- Engine cheat too, in case it helps (harmless if it no-ops)
        pcall(function() ExecuteCheat("Ghost") end)
        StartGhostFlyLoop()
    else
        pcall(function() ExecuteCheat("Walk") end)
        pcall(function() char:SetActorEnableCollision(true) end)
        pcall(function()
            local mc = char.CharacterMovement
            mc.GravityScale = 1.0
            mc:SetMovementMode(1, 0)
        end)
    end
    return true
end

-- Noclip (same as ghost but different name)
RegisterConsoleCommandHandler(".noclip", function(FullCommand, Parameters)
    _G.ToggleGhostMode()
    return true
end)

-- God Mode. ExecuteCheat("God") only sets engine bGodMode, which this game's
-- custom stat system ignores — damage goes through BP_PlayerInventory_C's
-- DecreaseHealth. So hook that: while god mode is on, refill health both
-- before the decrease runs (so no single hit can kill from full) and after
-- (so the bar never visibly drops). Only the LOCAL player's inventory.
_G.__GodNoDamage = _G.__GodNoDamage or false
_G.__GodHooksInstalled = _G.__GodHooksInstalled or false

local function GodHealLocal(self)
    local inv = nil
    pcall(function() inv = self:get() end)
    if not inv then return end
    if next(Coop.guests) ~= nil and Coop.HealGuest(inv) then return end   -- hosting: a player who asked
    if not _G.__GodNoDamage then return end
    -- MULTIPLAYER: heal ONLY the local player's inventory. If the local
    -- inventory can't be resolved, do nothing — never fall through to healing
    -- whoever happened to take damage (could be a friend or an NPC).
    local localInv = GetInventory()
    if not localInv then return end
    -- Userdata wrappers for the same UObject don't compare equal; match by name
    local a, b = "", "x"
    pcall(function() a = inv:GetFullName() end)
    pcall(function() b = localInv:GetFullName() end)
    if a ~= b then return end
    pcall(function() inv["IncreaseHealth"](inv, 9999) end)
end

local function InstallGodHooks()
    if _G.__GodHooksInstalled then return true end
    local ok = pcall(function()
        RegisterHook(
            "/Game/SurvivalGameKitV2/Components/BP_PlayerInventory.BP_PlayerInventory_C:DecreaseHealth",
            function(self, ...) GodHealLocal(self) end,
            function(self, ...) GodHealLocal(self) end)
    end)
    _G.__GodHooksInstalled = ok
    return ok
end

Coop.InstallGodHooks = InstallGodHooks

RegisterConsoleCommandHandler(".god", function(FullCommand, Parameters)
    isGodMode = not isGodMode
    _G.__GodNoDamage = isGodMode
    ExecuteInGameThread(function()
        if Coop.Joined() or not isGodMode then Coop.Mode("GOD", isGodMode) end
        pcall(function() ExecuteCheat("God") end)
        local hooked = InstallGodHooks()
        if hooked then
            Log("GOD MODE: " .. (isGodMode and "ON (no-damage hook active)" or "OFF"))
        else
            Log("GOD MODE: " .. (isGodMode and "ON" or "OFF") .. " — DecreaseHealth hook FAILED, engine God only.")
            Log("(If not working, try .instaheal)")
        end
    end)
    return true
end)

-- InstaHeal (Fake God Mode) - constantly heals player
local instaHealEnabled = false

-- The healing loop function
local function StartHealingLoop()
    LoopAsync(500, function()
        if not instaHealEnabled then
            ExecuteInGameThread(function() Coop.Mode("INSTAHEAL", false) end)
            return true  -- Stop the loop
        end

        ExecuteInGameThread(function()
            if Coop.Joined() then Coop.Mode("INSTAHEAL", true) return end
            local Inv = GetInventory()
            if Inv then
                pcall(function() Inv["IncreaseHealth"](Inv, 9999) end)
                pcall(function() Inv["IncreaseStamina"](Inv, 9999) end)
                pcall(function() Inv["IncreaseHunger"](Inv, 9999) end)
                pcall(function() Inv["IncreaseThirst"](Inv, 9999) end)
                pcall(function() Inv["DecreaseRadiation"](Inv, 9999) end)
                pcall(function() Inv["DecreaseInsanity"](Inv, 9999) end)
            end
        end)

        return false  -- Continue the loop
    end)
end

RegisterConsoleCommandHandler(".instaheal", function(FullCommand, Parameters)
    instaHealEnabled = not instaHealEnabled

    if instaHealEnabled then
        Log("INSTAHEAL: ON (healing every 0.5s)")
        StartHealingLoop()
    else
        Log("INSTAHEAL: OFF")
    end
    return true
end)

-- Quick alias
RegisterConsoleCommandHandler(".ih", function(FullCommand, Parameters)
    instaHealEnabled = not instaHealEnabled

    if instaHealEnabled then
        Log("INSTAHEAL: ON")
        StartHealingLoop()
    else
        Log("INSTAHEAL: OFF")
    end
    return true
end)

-- Global toggle so the menu FLY button hook (installed lexically earlier in
-- the file) can reach it.
-- Every way to ghost (.ghost, .noclip, the FLY button, keybinds) comes here.
-- On or off goes by whether the character really flies (the game's own FLY
-- button can start it without this mod knowing). In someone else's world it
-- can't be turned on (the host's game moves your character), but it can
-- always be turned off: 4.6.17 refused that too, and a player who got into
-- fly there couldn't get out.
local function GhostIsOn()
    if isFlying then return true end
    local mode = nil
    pcall(function() mode = GetPlayerCharacter().CharacterMovement.MovementMode end)
    return mode == 5   -- MOVE_Flying
end

-- The game's own FLY button doesn't make the character fly: it swaps you
-- into an admin camera (BP_SpectatorCamera_C) that keeps your character in
-- "As BP SGKMaster Character". Possessing only works on the host, so a player
-- who joined asks the host's Mod Menu (UNFLY). 4.6.18 looked only at the
-- character's movement and refused, and they were stuck in it.
local FLY_CAMERA = "BP_SpectatorCamera_C"
local function FlyCamera(pc)
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    local cls = ""
    pcall(function() cls = pawn:GetClass():GetFName():ToString() end)
    return cls == FLY_CAMERA and pawn or nil
end

-- On the host (or alone): pc back into its character, the camera removed
Coop.EndFlyCamera = function(pc)
    local cam = FlyCamera(pc)
    if not cam then return false end
    local char = nil
    pcall(function() char = cam["As BP SGKMaster Character"] end)
    if not Coop.Valid(char) then return false end
    local ok = pcall(function() pc:Possess(char) end)
    if not ok then return false end
    pcall(function()
        local mc = char.CharacterMovement
        mc.GravityScale = 1.0
        mc:SetMovementMode(1, 0)
    end)
    pcall(function() char:SetActorEnableCollision(true) end)
    pcall(function() cam:K2_DestroyActor() end)
    return true
end

-- fromButton: the game's FLY button, whose own code takes the host (or a
-- player alone) out of its camera by itself
_G.ToggleGhostMode = function(fromButton)
    ExecuteInGameThread(function()
        local pc = Coop.Controller()
        if pc and FlyCamera(pc) then
            if Coop.Joined() then
                Coop.Send("UNFLY", "your character back (out of the fly camera)")
            elseif not fromButton and Coop.EndFlyCamera(pc) then
                Log("FLY CAMERA: OFF (back in your character)")
            end
            return
        end
        local on = not GhostIsOn()
        if on and Coop.Refuse(".ghost") then return end
        isFlying = on
        if SetGhostMode(on) then
            Log("GHOST MODE: " .. (on and "ON" or "OFF"))
        else
            isFlying = not on
        end
    end)
end

-- Ghost Mode (noclip fly-through-walls)
RegisterConsoleCommandHandler(".ghost", function(FullCommand, Parameters)
    _G.ToggleGhostMode()
    return true
end)


-- Walk Mode (return to normal)
RegisterConsoleCommandHandler(".walk", function(FullCommand, Parameters)
    isFlying = false
    ExecuteInGameThread(function()
        SetGhostMode(false)
        Log("WALK MODE: ON")
    end)
    return true
end)

-- Teleport to crosshair
RegisterConsoleCommandHandler(".tp", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local method = ExecuteCheat("Teleport")
        Log("Teleported!")
    end)
    return true
end)

-- Slow motion
RegisterConsoleCommandHandler(".slomo", function(FullCommand, Parameters)
    local speed = tonumber(Parameters[1]) or 0.5
    ExecuteInGameThread(function()
        local method = ExecuteCheat("Slomo", speed)
        Log("SLOMO: " .. speed .. "x")
    end)
    return true
end)

-- Freeze time (uses BP_GlobalManager_C FreezeTime/UnfreezeTime)
local timeFrozen = false
RegisterConsoleCommandHandler(".freeze", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        local gm = GetGlobalManager()
        if gm then
            timeFrozen = not timeFrozen
            if timeFrozen then
                pcall(function() gm:FreezeTime() end)
                Log("FREEZE TIME: ON")
            else
                pcall(function() gm:UnfreezeTime() end)
                Log("FREEZE TIME: OFF")
            end
        else
            Log("GlobalManager not found!")
        end
    end)
    return true
end)

-- Damage target you're looking at
RegisterConsoleCommandHandler(".damage_target", function(FullCommand, Parameters)
    local amount = tonumber(Parameters[1]) or 100
    ExecuteInGameThread(function()
        ExecuteCheat("DamageTarget", amount)
        Log("Damaged target for " .. amount)
    end)
    return true
end)

-- Destroy all of a class
RegisterConsoleCommandHandler(".destroyall", function(FullCommand, Parameters)
    local className = Parameters[1]
    if not className then
        Log("Usage: .destroyall <ClassName>")
        Log("Example: .destroyall BP_Zombie_C")
        return true
    end
    ExecuteInGameThread(function()
        ExecuteCheat("DestroyAll", className)
        Log("DestroyAll " .. className)
    end)
    return true
end)

-- Destroy all pawns
RegisterConsoleCommandHandler(".destroypawns", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        ExecuteCheat("DestroyPawns")
        Log("All pawns destroyed!")
    end)
    return true
end)

-- Change player size
RegisterConsoleCommandHandler(".size", function(FullCommand, Parameters)
    local scale = tonumber(Parameters[1]) or 1.0
    ExecuteInGameThread(function()
        ExecuteCheat("ChangeSize", scale)
        Log("Size: " .. scale .. "x")
    end)
    return true
end)

-- Debug camera state
local debugCamEnabled = false

-- Find a live DebugCameraController (world state beats the local flag — the
-- flag desyncs if the cam was toggled by other means or the mod reloaded).
local function FindDebugCam()
    local found = nil
    pcall(function()
        local dccs = FindAllOf("DebugCameraController")
        if dccs then
            for _, dcc in ipairs(dccs) do
                local ok = false
                pcall(function() ok = dcc:IsValid() and dcc.OriginalControllerRef and dcc.OriginalControllerRef:IsValid() end)
                if ok then found = dcc break end
            end
        end
    end)
    return found
end

-- Shared exit routine with step-by-step diagnostics. The engine-correct exit
-- is ToggleDebugCamera on the DEBUG controller's own CheatManager; if the
-- debug controller has none, EnableCheats() spawns one first.
local function ExitDebugCam()
    local dcc = FindDebugCam()
    if not dcc then
        Log("[debugcam] no live DebugCameraController found")
        return false
    end

    local dcm = nil
    pcall(function() dcm = dcc.CheatManager end)
    local dcmValid = false
    pcall(function() dcmValid = dcm and dcm:IsValid() end)
    if not dcmValid then
        -- Shipping build: EnableCheats() won't create one. Construct it
        -- manually with the debug controller as outer (CheatManagerEnablerMod
        -- pattern). The engine exit code (ToggleDebugCamera) only works from a
        -- CheatManager that lives ON the debug controller, because the UPlayer
        -- to switch back is attached there.
        Log("[debugcam] constructing CheatManager on debug controller")
        pcall(function()
            local cmClass = StaticFindObject("/Script/Engine.CheatManager")
            if cmClass and cmClass:IsValid() then
                local newCM = StaticConstructObject(cmClass, dcc)
                if newCM and newCM:IsValid() then
                    dcc.CheatManager = newCM
                    dcm = newCM
                end
            end
        end)
        pcall(function() dcmValid = dcm and dcm:IsValid() end)
        Log("[debugcam] constructed CheatManager: " .. tostring(dcmValid))
    end

    if dcmValid then
        local ok, err = pcall(function() dcm:ToggleDebugCamera() end)
        Log("[debugcam] ToggleDebugCamera on debug controller: " .. (ok and "called" or ("ERROR " .. tostring(err))))
    end

    local function camGone()
        local gone = false
        pcall(function() gone = not dcc:IsValid() end)
        if not gone and FindDebugCam() == nil then gone = true end
        return gone
    end
    if camGone() then return true end

    -- DisableDebugCamera only acts if the CheatManager's DebugCameraControllerRef
    -- points at the debug controller. Enter and exit can resolve DIFFERENT
    -- CheatManagers in this game (multiple BP_SGKController), so the ref is often
    -- unset on the one we call. It's a plain UPROPERTY: set it ourselves first.
    local function tryDisable(cm, label)
        if not cm then return false end
        local valid = false
        pcall(function() valid = cm:IsValid() end)
        if not valid then return false end
        pcall(function() cm.DebugCameraControllerRef = dcc end)
        local ok, err = pcall(function() cm:DisableDebugCamera() end)
        Log("[debugcam] force-ref DisableDebugCamera via " .. label .. ": " .. (ok and "called" or ("ERROR " .. tostring(err))))
        return camGone()
    end

    local origCM = nil
    pcall(function() origCM = dcc.OriginalControllerRef.CheatManager end)
    if tryDisable(origCM, "originalPC") then return true end
    if tryDisable(GetCheatManager(), "GetCheatManager") then return true end

    Log("[debugcam] debug controller still alive after all methods")
    return false
end

-- Debug camera TOGGLE (same command enters and exits).
-- Debounced: the console sometimes delivers one submit to the handler twice
-- (~10-100ms apart), which exited and instantly re-entered the debug cam.
local lastDebugCamCmd = -10.0
RegisterConsoleCommandHandler(".debugcam", function(FullCommand, Parameters)
    local now = os.clock()
    if now - lastDebugCamCmd < 1.0 then return true end
    lastDebugCamCmd = now
    ExecuteInGameThread(function()
        local dcc = FindDebugCam()
        if not dcc and not debugCamEnabled then
            -- ENTER: deterministic enable (not blind toggle)
            local entered = false
            pcall(function()
                local cm = GetCheatManager()
                if cm then
                    local ok = pcall(function() cm:EnableDebugCamera() end)
                    if not ok then cm:ToggleDebugCamera() end
                    entered = true
                end
            end)
            if not entered then pcall(function() ExecuteCheat("ToggleDebugCamera") end) end
            debugCamEnabled = true
            Log("DEBUG CAM: ON (run .debugcam again to exit)")
        else
            -- EXIT via shared routine (see ExitDebugCam above)
            local ok = ExitDebugCam()
            debugCamEnabled = false
            Log(ok and "DEBUG CAM: OFF" or "DEBUG CAM: exit failed — check [debugcam] log lines")
        end
    end)
    return true
end)

-- Exit debug camera (multiple methods)
RegisterConsoleCommandHandler(".exitcam", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        Log("Trying to exit debug camera...")

        -- Preferred: shared engine-correct exit (same as .debugcam)
        if ExitDebugCam() then
            debugCamEnabled = false
            Log("DEBUG CAM: OFF")
            return
        end

        -- Method 1: Find DebugCameraController and call toggle ON IT
        pcall(function()
            local dccs = FindAllOf("DebugCameraController")
            if dccs and #dccs > 0 then
                Log("Found " .. #dccs .. " DebugCameraController(s)")
                for _, dcc in ipairs(dccs) do
                    pcall(function() dcc:ToggleDebugCamera() end)
                    pcall(function() dcc:DisableDebugCamera() end)
                    pcall(function() dcc:EnableCheats() end)
                    -- Get original pawn and possess it
                    pcall(function()
                        local origPawn = dcc.OriginalControllerRef
                        if origPawn then
                            origPawn:Possess(GetPlayerCharacter())
                        end
                    end)
                    pcall(function()
                        local origPlayer = dcc.OriginalPlayer
                        if origPlayer then
                            Log("Found OriginalPlayer ref")
                        end
                    end)
                end
            else
                Log("No DebugCameraController found")
            end
        end)

        -- Method 2: Console commands
        pcall(function() ExecuteConsoleCommand("ToggleDebugCamera") end)
        pcall(function() ExecuteConsoleCommand("DisableDebugCamera") end)
        pcall(function() ExecuteConsoleCommand("Camera Default") end)

        -- Method 3: Find original player controller and repossess
        pcall(function()
            local pcs = FindAllOf("BP_SGKController_C")
            local pawn = GetPlayerCharacter()
            if pcs and #pcs > 0 and pawn then
                Log("Found " .. #pcs .. " BP_SGKController(s)")
                pcs[1]:Possess(pawn)
            end
        end)

        -- Method 4: Destroy debug camera actors
        pcall(function()
            local dccs = FindAllOf("DebugCameraController")
            if dccs then
                for _, dcc in ipairs(dccs) do
                    dcc:K2_DestroyActor()
                end
                Log("Destroyed DebugCameraControllers")
            end
        end)

        pcall(function()
            local pawns = FindAllOf("DebugCameraPawn")
            if pawns then
                for _, p in ipairs(pawns) do
                    p:K2_DestroyActor()
                end
                Log("Destroyed DebugCameraPawns")
            end
        end)

        debugCamEnabled = false
        Log("Exit attempts done - if stuck use .restartlevel")
    end)
    return true
end)

-- Restart level (emergency exit from debug cam)
RegisterConsoleCommandHandler(".restartlevel", function(FullCommand, Parameters)
    ExecuteInGameThread(function()
        Log("Restarting level...")
        pcall(function()
            local pc = GetPlayerController()
            if pc then
                pc:RestartLevel()
            end
        end)
        pcall(function()
            ExecuteConsoleCommand("RestartLevel")
        end)
        debugCamEnabled = false
    end)
    return true
end)

-- Summon actor (spawn by class name)
RegisterConsoleCommandHandler(".summon", function(FullCommand, Parameters)
    local className = Parameters[1]
    if not className then
        Log("Usage: .summon <ClassName>")
        Log("Example: .summon BP_Zombie_C")
        return true
    end
    ExecuteInGameThread(function()
        ExecuteCheat("Summon", className)
        Log("Summoned: " .. className)
    end)
    return true
end)

-- Manually enable cheats
RegisterConsoleCommandHandler(".enablecheats", function(FullCommand, Parameters)
    Log("Enabling cheats...")
    ExecuteInGameThread(function()
        local pc = GetPlayerController()
        if not pc then
            Log("PlayerController not found!")
            return
        end

        -- Try all methods to enable cheats
        local methods = {}

        pcall(function()
            pc:EnableCheats()
            table.insert(methods, "EnableCheats()")
        end)

        pcall(function()
            pc.bCheatsEnabled = true
            table.insert(methods, "bCheatsEnabled")
        end)

        pcall(function()
            pc:AddCheats(true)
            table.insert(methods, "AddCheats()")
        end)

        pcall(function()
            ExecuteConsoleCommand("EnableCheats")
            table.insert(methods, "Console EnableCheats")
        end)

        if #methods > 0 then
            Log("Tried: " .. table.concat(methods, ", "))
            cheatsEnabled = true
        end

        -- Check if CheatManager exists now
        local cm = nil
        pcall(function() cm = pc.CheatManager end)
        if cm then
            Log("CheatManager: FOUND")
        else
            Log("CheatManager: NOT FOUND")
            Log("Cheats may not work in this game build")
        end
    end)
    return true
end)

-- List actual CheatManager functions (for debugging)
RegisterConsoleCommandHandler(".cmfuncs", function(FullCommand, Parameters)
    Log("Listing CheatManager functions...")
    ExecuteInGameThread(function()
        local cm = GetCheatManager()
        if not cm then
            Log("CheatManager not found! Run .enablecheats first")
            return
        end

        Log("=== CheatManager Functions ===")
        local funcs = {}
        pcall(function()
            for func in cm:GetClass():Functions() do
                local name = func:GetName()
                if name and #name > 0 then
                    table.insert(funcs, name)
                end
            end
        end)

        table.sort(funcs)
        for i, name in ipairs(funcs) do
            if i <= 50 then
                Log("  " .. name)
            end
        end
        if #funcs > 50 then
            Log("  ... and " .. (#funcs - 50) .. " more")
        end
        Log("Total: " .. #funcs .. " functions")
    end)
    return true
end)

-- List all cheat commands
RegisterConsoleCommandHandler(".cheats", function(FullCommand, Parameters)
    Log("=== MISERY Mod Menu v4.0 - All Commands ===")
    Log("")
    Log("GOD MODE:")
    Log("  .instaheal (.ih) - auto-heal all stats")
    Log("  .infstam         - infinite stamina")
    Log("  .god .ghost      - (may not work)")
    Log("")
    Log("WORLD CONTROL:")
    Log("  .time <hour>     - set time 0-24")
    Log("  .weather <type>  - sunny/rain/thunder")
    Log("  .season <type>   - spring/summer/autumn/winter")
    Log("  .slomo [x]       - slow motion (0.5)")
    Log("  .freeze          - freeze time")
    Log("  .size [x]        - change size")
    Log("")
    Log("TELEPORT:")
    Log("  .tp              - to crosshair")
    Log("  .savepos         - save position")
    Log("  .loadpos         - load position")
    Log("  .debugcam        - free camera")
    Log("  .exitcam         - exit camera")
    Log("  .restartlevel    - emergency exit")
    Log("")
    Log("SPAWN:")
    Log("  .enemy <type> [n]  - spawn enemies")
    Log("  .summon <class>    - spawn by class")
    Log("  .menu              - DEV MENU for items")
    Log("")
    Log("COMBAT:")
    Log("  .damage_target [n] - hurt target")
    Log("  .destroyall <class>")
    Log("  .destroypawns")
    Log("")
    Log("STATS:")
    Log("  .heal .stamina .feed .drink")
    Log("  .radcure .sanitycure .damage")
    Log("")
    Log("KEYBINDS: .bind .unbind .binds")
    Log("DEBUG: .search .bp .inspect .items")
    return true
end)

-- Try to access and show the built-in cheat menu
RegisterConsoleCommandHandler(".cheat", function(FullCommand, Parameters)
    Log("Looking for cheat menu widget...")
    ExecuteInGameThread(function()
        local cheatMenu = GetCheatMenuWidget()

        if cheatMenu then
            Log("Cheat menu found!")
            pcall(function()
                cheatMenu["SetVisibility"](cheatMenu, 0) -- Visible
                Log("Set visibility to Visible")
            end)
            pcall(function()
                cheatMenu["SetIsEnabled"](cheatMenu, true)
                Log("Set enabled")
            end)
            pcall(function()
                cheatMenu["AddToViewport"](cheatMenu, 100)
                Log("Added to viewport")
            end)
            pcall(function()
                cheatMenu["SetRenderOpacity"](cheatMenu, 1.0)
                Log("Set opacity to 1.0")
            end)
        else
            Log("Cheat menu not found - make sure you're in-game")
        end
    end)
    return true
end)

-- Auto-enable cheats when player spawns
local autoEnableDone = false

local function TryAutoEnableCheats()
    if autoEnableDone then return end

    local pc = GetPlayerController()
    if not pc then return end

    -- Enable cheats
    local success = EnableCheats()
    if success then
        autoEnableDone = true
        Log("[Auto] Cheats enabled!")
    end
end

-- Watch for player controller creation
pcall(function()
    NotifyOnNewObject("/Script/Engine.PlayerController", function(controller)
        -- Delay slightly to let game initialize
        LoopAsync(1000, function()
            -- game objects only on the game thread (timers run beside it)
            ExecuteInGameThread(function() pcall(TryAutoEnableCheats) end)
            return true  -- Run once
        end)
    end)
end)

-- Watch for inventory creation (means player is in-game)
pcall(function()
    NotifyOnNewObject("/Game/SurvivalGameKitV2/Components/BP_PlayerInventory.BP_PlayerInventory_C", function(inv)
        LoopAsync(500, function()
            ExecuteInGameThread(function()
                pcall(TryAutoEnableCheats)
                -- Also build item cache
                if not CachedItems then
                    BuildItemCache()
                    Log("[Auto] Item cache ready!")
                end
            end)
            return true
        end)
    end)
end)

-- Also try on game character spawn
pcall(function()
    NotifyOnNewObject("/Game/SurvivalGameKitV2/Blueprints/Characters/BP_SGKMasterCharacter.BP_SGKMasterCharacter_C", function(char)
        LoopAsync(500, function()
            ExecuteInGameThread(function() pcall(TryAutoEnableCheats) end)
            return true
        end)
    end)
end)

-- Fallback: every 5 seconds until cheats are enabled. Each look for the
-- player walks every object in the game, and at the main menu there is no
-- player to find, so with the watchers above it only runs once they have
-- found the player.
LoopAsync(5000, function()
    if autoEnableDone then
        return true  -- Stop checking
    end
    ExecuteInGameThread(function()
        if Coop.Valid(Coop.ctrl) or not HAS_NotifyOnNewObject then pcall(TryAutoEnableCheats) end
    end)
    return false  -- Keep checking
end)

-- ============================================================
-- CATCH-ALL HANDLER - Better feedback for unrecognized commands
-- ============================================================

-- This is a workaround: we register a handler that matches common typos
-- UE4SS doesn't have a true catch-all, so we register variations

-- Helper function to show "not recognized" with suggestions
local function ShowCommandNotRecognized(cmd)
    Log("Command not recognized: " .. cmd)
    local suggestions = FindSimilarCommands(cmd)
    if #suggestions > 0 then
        Log("Did you mean: " .. table.concat(suggestions, ", ") .. "?")
    else
        Log("Type .help for a list of commands")
    end
end

-- Register common typo patterns as handlers that redirect to help
local typoPatterns = {".heall", ".hel", ".healp", ".godmode", ".godmod", ".insta", ".inf", ".tele", ".teleport"}
for _, typo in ipairs(typoPatterns) do
    SafeRegisterCommand(typo, function(FullCommand, Parameters)
        ShowCommandNotRecognized(typo)
        return true
    end)
end

-- ============================================================
-- DIAGNOSTIC COMMAND - Helps users troubleshoot issues
-- ============================================================

SafeRegisterCommand(".diag", function(FullCommand, Parameters)
    Log("=== MISERY Mod Menu Diagnostics ===")
    Log("")

    -- API availability
    Log("API STATUS:")
    Log("  RegisterKeyBindAsync: " .. (HAS_RegisterKeyBindAsync and "OK" or "MISSING"))
    Log("  RegisterConsoleCommandHandler: " .. (HAS_RegisterConsoleCommandHandler and "OK" or "MISSING"))
    Log("  ExecuteInGameThread: " .. (HAS_ExecuteInGameThread and "OK" or "MISSING"))
    Log("  ForEachUObject: " .. (HAS_ForEachUObject and "OK" or "MISSING"))
    Log("  FindAllOf: " .. (HAS_FindAllOf and "OK" or "MISSING"))
    Log("  LoopAsync: " .. (HAS_LoopAsync and "OK" or "MISSING"))
    Log("")

    -- Key availability
    Log("KEY STATUS:")
    Log("  Key enum available: " .. (KeysAvailable and "YES" or "NO"))
    Log("  Keys mapped: " .. keyCount)
    Log("  Hotkeys bound: " .. boundHotkeys .. "/7")
    Log("")

    -- Screen info
    local width, height = GetViewportSize()
    local scale = GetUIScaleFactor()
    Log("SCREEN:")
    Log("  Resolution: " .. width .. "x" .. height)
    Log("  UI Scale: " .. string.format("%.2f", scale))
    Log("")

    -- Custom bindings
    local bindCount = 0
    for _ in pairs(customBindings) do bindCount = bindCount + 1 end
    Log("CUSTOM BINDINGS: " .. bindCount)
    Log("")

    -- Initialization errors
    if #InitErrors > 0 then
        Log("INIT ERRORS (" .. #InitErrors .. "):")
        for i, err in ipairs(InitErrors) do
            if i <= 10 then
                Log("  " .. err)
            end
        end
        if #InitErrors > 10 then
            Log("  ... and " .. (#InitErrors - 10) .. " more")
        end
    else
        Log("INIT ERRORS: None")
    end

    Log("")
    Log("=== End Diagnostics ===")
    return true
end)

-- .menu: opens / closes the cheat menu (also from the Mod Hub)
SafeRegisterCommand(".menu", function(FullCommand, Parameters)
    SafeExecuteInGameThread(function()
        local cheatMenu = GetCheatMenuWidget()

        if cheatMenu then
            cheatMenuVisible = not cheatMenuVisible
            if cheatMenuVisible then
                pcall(function() cheatMenu["SetVisibility"](cheatMenu, 0) end)
                pcall(function() cheatMenu["SetIsEnabled"](cheatMenu, true) end)
                ScaleWidgetForScreen(cheatMenu)
                SetCursorVisible(true)
                OnCheatMenuShown()
                Log("Cheat Menu: SHOWN (via .menu command)")
            else
                pcall(function() cheatMenu["SetVisibility"](cheatMenu, 1) end)
                SetCursorVisible(false)
                Log("Cheat Menu: HIDDEN")
            end
        else
            Log("Cheat menu not found!")
            Log("Make sure you're in-game first.")
        end
    end)
    return true
end)

-- Teleport world items with matching row name to player's feet (bypasses all inventory API)
RegisterConsoleCommandHandler(".fetchitem", function(FullCommand, Parameters)
    local target = Parameters[1]
    local wantCount = tonumber(Parameters[2]) or 1
    if not target then
        Log("Usage: .fetchitem <RowName> [count]")
        Log("Run .scanworld to find row names")
        return true
    end
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("Player not found!") return end
        local loc = nil
        pcall(function() loc = player:K2_GetActorLocation() end)
        if not loc then Log("Can't get player location!") return end

        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items or #items == 0 then
            Log("No world items found! Load into a level first.")
            return
        end

        local moved = 0
        for _, item in ipairs(items) do
            if moved >= wantCount then break end
            pcall(function()
                local ih = item["Item"]
                if ih then
                    local rn = ih["RowName"]
                    if rn and rn:ToString():lower() == target:lower() then
                        local dropLoc = {X = loc.X + (moved * 80), Y = loc.Y + 120, Z = loc.Z + 10}
                        item:K2_SetActorLocation(dropLoc, false, {}, true)
                        moved = moved + 1
                    end
                end
            end)
        end

        if moved > 0 then
            Log("Moved " .. moved .. "x " .. target .. " to your feet — pick it up!")
        else
            Log("No '" .. target .. "' found in world.")
            Log("Run .scanworld to see what's available.")
        end
    end)
    return true
end)

-- Spawn new BP_StaticMasterItem_C actor near player by cloning class from existing world item
RegisterConsoleCommandHandler(".dropitem", function(FullCommand, Parameters)
    local target = Parameters[1]
    local wantCount = tonumber(Parameters[2]) or 1
    if not target then
        Log("Usage: .dropitem <RowName> [count]")
        Log("Spawns a fresh copy of the item near you.")
        return true
    end
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if not player then Log("Player not found!") return end
        local loc = nil
        pcall(function() loc = player:K2_GetActorLocation() end)
        if not loc then Log("Can't get player location!") return end

        -- Find a source item with this row name to use as template
        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items or #items == 0 then
            Log("No world items to use as template!")
            return
        end

        local templateItem = nil
        for _, item in ipairs(items) do
            pcall(function()
                local ih = item["Item"]
                if ih then
                    local rn = ih["RowName"]
                    if rn and rn:ToString():lower() == target:lower() then
                        templateItem = item
                    end
                end
            end)
            if templateItem then break end
        end

        if not templateItem then
            Log("No template for '" .. target .. "' in world. Use .scanworld to check.")
            return
        end

        local world = nil
        pcall(function() world = player:GetWorld() end)
        if not world then Log("GetWorld() failed!") return end

        local itemClass = nil
        pcall(function() itemClass = templateItem:GetClass() end)
        if not itemClass then Log("GetClass() on template failed!") return end

        local spawned = 0
        for i = 1, wantCount do
            local ok, err = pcall(function()
                local spawnLoc = {X = loc.X + (i * 80), Y = loc.Y + 150, Z = loc.Z + 20}
                local rot = {Pitch = 0, Yaw = 0, Roll = 0}
                local newItem = world:SpawnActor(itemClass, spawnLoc, rot)
                if newItem then
                    -- Copy item data from template
                    pcall(function() newItem["Item"] = templateItem["Item"] end)
                    spawned = spawned + 1
                end
            end)
            if not ok then Log("SpawnActor failed: " .. tostring(err)) break end
        end

        if spawned > 0 then
            Log("Dropped " .. spawned .. "x " .. target .. " near you — go pick it up!")
        else
            Log("SpawnActor returned nil. World may not support it.")
        end
    end)
    return true
end)

-- Scan world items to discover real DataTable row names (FName fix: use :ToString())
RegisterConsoleCommandHandler(".scanworld", function(FullCommand, Parameters)
    local filter = Parameters[1] and Parameters[1]:lower() or nil
    Log("Scanning world for BP_StaticMasterItem_C instances...")
    ExecuteInGameThread(function()
        local items = FindAllOf("BP_StaticMasterItem_C")
        if not items or #items == 0 then
            Log("No BP_StaticMasterItem_C found!")
            Log("Load into a map with items first.")
            return
        end
        Log("Found " .. #items .. " world items. Reading row names...")
        local rowNames = {}
        local errors = 0
        for _, item in ipairs(items) do
            local ok, err = pcall(function()
                local itemHandle = item["Item"]
                if itemHandle then
                    local rn = itemHandle["RowName"]
                    if rn then
                        local name = rn:ToString()
                        if name and name ~= "" and name ~= "None" then
                            rowNames[name] = (rowNames[name] or 0) + 1
                        end
                    end
                end
            end)
            if not ok then errors = errors + 1 end
        end
        local sorted = {}
        for name, count in pairs(rowNames) do
            if not filter or name:lower():find(filter, 1, true) then
                table.insert(sorted, { name = name, count = count })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        if #sorted == 0 then
            Log("No row names found! (read errors: " .. errors .. ")")
            Log("Walk near world items and try again.")
        else
            Log("--- Item Row Names (" .. #sorted .. " unique" .. (filter and (", filter: " .. filter) or "") .. ") ---")
            for i, entry in ipairs(sorted) do
                if i <= 80 then
                    Log("  " .. entry.name .. " (x" .. entry.count .. " in world)")
                end
            end
            if #sorted > 80 then Log("  ... and " .. (#sorted - 80) .. " more") end
            Log("Use with: .give <RowName> [amount]")
        end
        if errors > 0 then Log("(" .. errors .. " items failed to read)") end
    end)
    return true
end)

-- Startup
Log("================================")
Log("  MISERY Mod Menu v4.6.23 Loaded!")
Log("================================")
Log("Cheats auto-enable on game start")
Log("")

-- Show key binding status
if boundHotkeys == 7 then
    Log("HOTKEYS: All " .. boundHotkeys .. " bound OK")
else
    Log("HOTKEYS: " .. boundHotkeys .. "/7 bound")
    if boundHotkeys < 7 then
        Log("  (Some keys unavailable)")
    end
end
Log("  F1-F7 - Quick stat adjustments")
Log("")
Log("QUICK START:")
Log("  .instaheal - God mode (auto-heal)")
Log("  .infstam   - Infinite stamina")
Log("  .time 12   - Set noon")
Log("  .menu      - Toggle the cheat menu (or from the Mod Hub: PageUp)")
Log("")

-- Show any initialization errors
if #InitErrors > 0 then
    Log("WARNINGS (" .. #InitErrors .. " issues):")
    for i = 1, math.min(3, #InitErrors) do
        Log("  - " .. InitErrors[i])
    end
    if #InitErrors > 3 then
        Log("  Type .diag for full report")
    end
    Log("")
end

Log("================================")
Log("  Type .help or .diag")
Log("================================")

-- Add more commands to bind system (after all functions are defined)
CommandHandlers["instaheal"] = function()
    instaHealEnabled = not instaHealEnabled
    if instaHealEnabled then
        Log("INSTAHEAL: ON")
        StartHealingLoop()
    else
        Log("INSTAHEAL: OFF")
    end
end

CommandHandlers["infstam"] = function()
    infStaminaEnabled = not infStaminaEnabled
    if infStaminaEnabled then
        Log("INFINITE STAMINA: ON")
        StartStaminaLoop()
    else
        Log("INFINITE STAMINA: OFF")
    end
end

CommandHandlers["savepos"] = function()
    ExecuteInGameThread(function()
        local player = GetPlayerCharacter()
        if player then
            pcall(function()
                savedPosition = player:K2_GetActorLocation()
                Log("Position saved!")
            end)
        end
    end)
end

CommandHandlers["loadpos"] = function()
    ExecuteInGameThread(function()
        if savedPosition then
            local player = GetPlayerCharacter()
            if player then
                pcall(function()
                    player:K2_SetActorLocation(savedPosition, false, {}, true)
                    Log("Teleported!")
                end)
            end
        else
            Log("No position saved!")
        end
    end)
end

CommandHandlers["tp"] = function()
    ExecuteInGameThread(function()
        ExecuteCheat("Teleport")
        Log("Teleported!")
    end)
end

CommandHandlers["slomo"] = function(speed)
    speed = tonumber(speed) or 0.5
    ExecuteInGameThread(function()
        ExecuteCheat("Slomo", speed)
        Log("SLOMO: " .. speed .. "x")
    end)
end

CommandHandlers["freeze"] = function()
    ExecuteInGameThread(function()
        local gm = GetGlobalManager()
        if gm then
            timeFrozen = not timeFrozen
            if timeFrozen then
                pcall(function() gm:FreezeTime() end)
                Log("FREEZE TIME: ON")
            else
                pcall(function() gm:UnfreezeTime() end)
                Log("FREEZE TIME: OFF")
            end
        else
            Log("GlobalManager not found!")
        end
    end)
end

CommandHandlers["debugcam"] = function()
    ExecuteInGameThread(function()
        local dcc = FindDebugCam()
        if dcc then
            local ok = ExitDebugCam()
            debugCamEnabled = false
            Log(ok and "DEBUG CAM: OFF" or "DEBUG CAM: exit failed")
        else
            local cm = GetCheatManager()
            if cm then
                pcall(function() cm:EnableDebugCamera() end)
                debugCamEnabled = true
                Log("DEBUG CAM: ON")
            end
        end
    end)
end

CommandHandlers["god"] = function()
    isGodMode = not isGodMode
    _G.__GodNoDamage = isGodMode
    ExecuteInGameThread(function()
        if Coop.Joined() or not isGodMode then Coop.Mode("GOD", isGodMode) end
        InstallGodHooks()
        Log("GOD MODE: " .. (isGodMode and "ON" or "OFF"))
    end)
end

CommandHandlers["ghost"] = function()
    _G.ToggleGhostMode()
end

CommandHandlers["walk"] = function()
    isFlying = false
    ExecuteInGameThread(function()
        SetGhostMode(false)
        Log("WALK MODE: ON")
    end)
end

CommandHandlers["time"] = function(hour)
    hour = tonumber(hour) or 12
    ExecuteInGameThread(function()
        local wm = GetWeatherManager()
        if not wm then Log("WeatherManager not found!") return end
        pcall(function()
            -- Calibrated 2026-06-10: Current Time = hour * 100
            wm["Current Time"] = hour * 100.0
            pcall(function() wm["Set Light Rotation"](wm) end)
            pcall(function() wm["Set Elements"](wm) end)
            Log("Time set to: " .. hour .. ":00")
        end)
    end)
end

CommandHandlers["destroypawns"] = function()
    ExecuteInGameThread(function()
        ExecuteCheat("DestroyPawns")
        Log("All pawns destroyed!")
    end)
end

-- Load saved bindings
LoadBindings()
