------------------------------------------------------------
-- Chest Sort
------------------------------------------------------------
-- With a chest (or any container) open, press S: its items are sorted, the
-- smallest first: 1-slot items fill the top rows, then 2-slot items, then
-- 3-slot and so on. Items of the same kind end up next to each other.
--
-- Every move is the game's own "move item" (the same as dragging an item
-- with the mouse, done by the host's game), so the game checks each one and
-- nothing can be lost, and it works in someone else's world too. The moves
-- go one at a time, a few per second; the chest is read again before each
-- one, so whatever the game did is what the next move starts from.
--
--   S (inventory open)   sort the open container
--   .sort                the same, from the console
--   .sort stop           stop a sort that's running
--   .sort check          what the mod sees in the open container (changes nothing)
------------------------------------------------------------
local VERSION = "1.0.0"
local MOD_DIR = "./ue4ss/Mods/ChestSort/"

local function log(msg) print("[ChestSort] " .. tostring(msg) .. "\n") end

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
local SORT_KEY = type(cfg.key) == "string" and cfg.key:upper() or "S"
local MOVE_MS = math.max(60, tonumber(cfg.moveDelayMs) or 120)   -- between moves (each goes to the host's game)

-- The game's struct fields (Blueprint names carry their GUIDs)
local F = {
    occupied = "Occupied_7_0F396F8C4E8A3B8E24C3BF9D4E366AAC",
    rootIndex = "RootIndex_4_31C49987405FF01267287D9E3381FC5E",
    selfIndex = "SelfIndex_2_277281E743D41F5A7B4963B58ABB6819",
    item = "Item_10_95D912F14C7740665FD844AF7EA87327",
    blocked = "Blocked_22_0B9BF07643B17CAA9644048ED6E763D9",
    id = "ID_2_84C2CB8945979246059C568DCD463423",
    amount = "Amount_5_62DB2267439500D86A52E0B2266494D2",
    rotated = "Rotated_18_66B00C8648A7E3BEB56C4282929D015D",
    columns = "ContainerColumns_14_F97E5A5744D6545EC3C5FD967C512BF1",
    slotInv = "InvComponent_5_A1D58E004822DA933B61B28C627EDF23",
    slotIndex = "Index_4_ABD9C3F64229CF5D88D6FC8CCDD577B6",
}
local INVENTORY_CLASS = "/Game/SurvivalGameKitV2/Components/BP_MasterInventory.BP_MasterInventory_C"

local function Valid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function NameOf(obj)
    local name = "?"
    pcall(function() name = obj:GetFName():ToString() end)
    return name
end

------------------------------------------------------------
-- What's open
------------------------------------------------------------
local function LocalController()
    local pc = nil
    pcall(function()
        for _, c in ipairs(FindAllOf("BP_SGKController_C") or {}) do
            if Valid(c) and c:IsLocalController() then pc = c return end
        end
    end)
    return pc
end

-- Your inventory component (it does the moves) and the open container's,
-- or nil, why. The container is the one of the thing you're using (the
-- game's InteractedActor) with the most cells.
local function OpenContainer()
    local pc = LocalController()
    if not pc then return nil, nil, "no player" end
    local player = nil
    pcall(function() player = pc.Character.PlayerInventory end)
    if not Valid(player) then return nil, nil, "no player inventory" end
    local actor = nil
    pcall(function() actor = player.InteractedActor end)
    if not Valid(actor) then return player, nil, "no container open" end
    local best, bestCells = nil, -1
    local cls = StaticFindObject(INVENTORY_CLASS)
    local function consider(comp)
        pcall(function() if comp.get then comp = comp:get() end end)
        if not Valid(comp) then return end
        local n = 0
        pcall(function() n = comp.Inventory:GetArrayNum() end)
        if n > bestCells then best, bestCells = comp, n end
    end
    local list = nil
    pcall(function() list = actor:K2_GetComponentsByClass(cls) end)
    if type(list) == "table" then
        for _, c in pairs(list) do consider(c) end
    elseif list then
        pcall(function() list:ForEach(function(_, e) consider(e:get()) end) end)
    end
    if not best then return player, nil, NameOf(actor) .. " has no container" end
    return player, best
end

------------------------------------------------------------
-- The grid: read it, plan the sorted layout
------------------------------------------------------------
-- { cells, cols, blocked = {[i]=true}, owner = {[i]=item}, items = { {root, w, h, id, amount, rotated, cells} } }
-- or nil, why. Cell indexes are 0-based like the game's, row by row.
local function ReadGrid(inv)
    local cols = nil
    pcall(function() cols = inv.InventoryDetails[F.columns] end)
    if type(cols) ~= "number" or cols < 1 then return nil, "couldn't read its columns" end
    local arr = inv.Inventory
    local n = 0
    pcall(function() n = arr:GetArrayNum() end)
    if n < 1 then return nil, "it has no cells" end
    local grid = { cells = n, cols = cols, blocked = {}, owner = {}, items = {} }
    local byRoot, rootOf = {}, {}
    for i = 1, n do
        local idx = i - 1
        local ok, err = pcall(function()
            local slot = arr[i]
            if slot[F.blocked] then grid.blocked[idx] = true end
            if slot[F.occupied] then
                local root = slot[F.rootIndex]
                rootOf[idx] = root
                if root == idx then
                    local it = slot[F.item]
                    byRoot[idx] = { root = idx, id = it[F.id]:ToString(), amount = it[F.amount],
                                    rotated = it[F.rotated] == true, cells = {} }
                end
            end
        end)
        if not ok then return nil, "couldn't read cell " .. idx .. ": " .. tostring(err) end
    end
    for idx, root in pairs(rootOf) do
        local item = byRoot[root]
        if not item then return nil, "cell " .. idx .. " belongs to an item at " .. tostring(root) .. " that isn't there" end
        table.insert(item.cells, idx)
        grid.owner[idx] = item
    end
    for _, item in pairs(byRoot) do
        local minR, maxR, minC, maxC = math.huge, -1, math.huge, -1
        for _, c in ipairs(item.cells) do
            local r, col = c // cols, c % cols
            minR, maxR = math.min(minR, r), math.max(maxR, r)
            minC, maxC = math.min(minC, col), math.max(maxC, col)
        end
        item.w, item.h = maxC - minC + 1, maxR - minR + 1
        -- the item's cells must be a filled rectangle with the root at its top left
        if item.w * item.h ~= #item.cells or item.root ~= minR * cols + minC then
            return nil, item.id .. " at " .. item.root .. " isn't laid out as expected (" .. #item.cells
                .. " cells in " .. item.w .. "x" .. item.h .. ")"
        end
        table.insert(grid.items, item)
    end
    return grid
end

-- Do w x h cells fit with their top left at idx? taken: idx -> true
local function Fits(grid, idx, w, h, taken)
    local cols = grid.cols
    local r0, c0 = idx // cols, idx % cols
    if c0 + w > cols then return false end
    for r = r0, r0 + h - 1 do
        for c = c0, c0 + w - 1 do
            local i = r * cols + c
            if i >= grid.cells or grid.blocked[i] or taken[i] then return false end
        end
    end
    return true
end

local function Mark(grid, idx, w, h, taken, value)
    for r = idx // grid.cols, idx // grid.cols + h - 1 do
        for c = idx % grid.cols, idx % grid.cols + w - 1 do taken[r * grid.cols + c] = value end
    end
end

-- The sorted order: smallest first, the same kind together, bigger stacks first
local function Order(items)
    local list = {}
    for _, it in ipairs(items) do table.insert(list, it) end
    table.sort(list, function(a, b)
        local aa, ba = a.w * a.h, b.w * b.h
        if aa ~= ba then return aa < ba end
        if a.h ~= b.h then return a.h < b.h end
        if a.id ~= b.id then return a.id < b.id end
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.root < b.root
    end)
    return list
end

-- How full a sort is tried: level 1 sorts everything; each next level
-- leaves the biggest items still sorted where they are and sorts the rest
-- around them (a full container has no room to move big items about; with
-- a single free cell the 1-cell items can still be sorted). Returns the
-- "pin" of each level: items bigger than it stay (false: none)
local function Levels(grid)
    local areas, seen = {}, {}
    for _, it in ipairs(grid.items) do
        local a = it.w * it.h
        if not seen[a] then seen[a] = true table.insert(areas, a) end
    end
    table.sort(areas, function(a, b) return a > b end)
    local levels = { false }
    for i = 2, #areas do table.insert(levels, areas[i]) end
    return levels
end

-- Where each item goes: the first place it fits, row by row, in sorted
-- order. If that doesn't pack (a fairly full container), the big ones go to
-- the bottom first (last place they fit) and the small ones fill the top.
-- Returns the ordered list (each with .target) or nil if it doesn't fit
-- pin: items bigger than this many cells stay where they are (nil: none)
local function Plan(grid, pin)
    local order = Order(grid.items)
    local function try(bigFromBottom)
        local taken = {}
        local list = {}
        for _, it in ipairs(order) do
            it.target = nil
            if pin and it.w * it.h > pin then
                it.target = it.root
                Mark(grid, it.root, it.w, it.h, taken, true)
            else
                table.insert(list, it)
            end
        end
        if bigFromBottom then
            table.sort(list, function(a, b)
                if a.w * a.h ~= b.w * b.h then return a.w * a.h > b.w * b.h end
                return a.id < b.id
            end)
        end
        for _, it in ipairs(list) do
            local big = bigFromBottom and it.w * it.h > 1
            local first, last, step = 0, grid.cells - 1, 1
            if big then first, last, step = grid.cells - 1, 0, -1 end
            for idx = first, last, step do
                if Fits(grid, idx, it.w, it.h, taken) then
                    it.target = idx
                    Mark(grid, idx, it.w, it.h, taken, true)
                    break
                end
            end
            if not it.target then return false end
        end
        return true
    end
    if try(false) or try(true) then
        -- (the small ones of the second packing went in after the big ones:
        -- the moves still go smallest first)
        -- Identical items (same kind, amount, shape) can take each other's
        -- places: one already in a place of its kind stays, so they never
        -- swap back and forth
        local groups = {}
        for _, it in ipairs(order) do
            local key = it.id .. "|" .. tostring(it.amount) .. "|" .. it.w .. "x" .. it.h
            groups[key] = groups[key] or {}
            table.insert(groups[key], it)
        end
        for _, list in pairs(groups) do
            if #list > 1 then
                local free, wants = {}, {}
                for _, it in ipairs(list) do free[it.target] = true end
                for _, it in ipairs(list) do
                    if free[it.root] then it.target, free[it.root] = it.root, nil else table.insert(wants, it) end
                end
                local left = {}
                for t in pairs(free) do table.insert(left, t) end
                table.sort(left)
                for i, it in ipairs(wants) do it.target = left[i] end
            end
        end
        return order
    end
    return nil
end

------------------------------------------------------------
-- Sorting: one move at a time
------------------------------------------------------------
local sorting = nil   -- { player, inv, invName, steps, maxSteps, lastMove, same, moved }

local function Move(player, inv, from, to, rotated)
    local ok, err = pcall(function()
        player:ServerMoveItem({ [F.slotInv] = inv, [F.slotIndex] = from }, { [F.slotInv] = inv, [F.slotIndex] = to },
            rotated, false, 0)
    end)
    return ok, err
end

-- A free place for item where it's least in the way: outside every target
-- still to fill if there is one, else over the targets that are filled
-- last; never over the target of order[k] (the one being made room for).
-- strict: only spots outside the targets of order[1..k]
local function ParkingSpot(grid, item, order, k, strict)
    local taken = {}   -- (not over its own cells either: a move onto itself may be refused)
    for i in pairs(grid.owner) do taken[i] = true end
    local due = {}     -- cell -> the lowest order number whose target covers it
    for j = 1, #order do
        local o = order[j]
        if o.root ~= o.target or j == k then
            for r = o.target // grid.cols, o.target // grid.cols + o.h - 1 do
                for c = o.target % grid.cols, o.target % grid.cols + o.w - 1 do
                    local i = r * grid.cols + c
                    if not due[i] or j < due[i] then due[i] = j end
                end
            end
        end
    end
    local best, bestScore = nil, -1
    for idx = 0, grid.cells - 1 do
        if Fits(grid, idx, item.w, item.h, taken) then
            local score, overK = math.huge, false
            for r = idx // grid.cols, idx // grid.cols + item.h - 1 do
                for c = idx % grid.cols, idx % grid.cols + item.w - 1 do
                    local d = due[r * grid.cols + c]
                    if d then
                        if d < score then score = d end
                        if d == k then overK = true end
                    end
                end
            end
            local allowed = not overK and (not strict or score > k)
            if allowed and score > bestScore then
                best, bestScore = idx, score
                if score == math.huge then break end
            end
        end
    end
    return best
end

-- Is w x h at idx free of everything (item itself included)?
local function AreaFree(grid, idx, w, h)
    for r = idx // grid.cols, idx // grid.cols + h - 1 do
        for c = idx % grid.cols, idx % grid.cols + w - 1 do
            if grid.owner[r * grid.cols + c] then return false end
        end
    end
    return true
end

-- The next move: { from, to, item, why } or nil, why.
-- 1. any item whose place is free goes straight there (smallest first);
-- 2. else something in the way of the first item still to place is parked
--    where it's least in the way (or the item itself, when only it is there)
local function NextMove(grid, order)
    local pending = {}
    for k, it in ipairs(order) do
        if it.root ~= it.target then table.insert(pending, k) end
    end
    if #pending == 0 then return nil, "done" end
    for _, k in ipairs(pending) do
        local it = order[k]
        if AreaFree(grid, it.target, it.w, it.h) then return { from = it.root, to = it.target, item = it } end
    end
    -- nothing can go straight: make room, trying the earliest items first.
    -- Never parked over the place of an earlier item still to place: two
    -- items could then keep swapping
    for _, strict in ipairs({ true }) do
        for _, k in ipairs(pending) do
            local it = order[k]
            local blockers, seen = {}, {}
            for r = it.target // grid.cols, it.target // grid.cols + it.h - 1 do
                for c = it.target % grid.cols, it.target % grid.cols + it.w - 1 do
                    local o = grid.owner[r * grid.cols + c]
                    if o and not seen[o] then seen[o] = true table.insert(blockers, o) end
                end
            end
            for _, b in ipairs(blockers) do
                local to = ParkingSpot(grid, b, order, k, strict)
                if to then return { from = b.root, to = to, item = b } end
            end
        end
    end
    return nil, "stuck"
end

local function Finish(msg)
    if sorting then log(msg .. " (" .. sorting.moved .. " moves)") end
    sorting = nil
end

local function Step()
    local s = sorting
    if not s then return end
    if not (Valid(s.inv) and Valid(s.player)) then Finish("The container is gone - stopped") return end
    -- closed meanwhile: stop
    local actorNow = nil
    pcall(function() actorNow = s.player.InteractedActor end)
    if not Valid(actorNow) then Finish("Container closed - stopped") return end
    local grid, why = ReadGrid(s.inv)
    if not grid then Finish("Stopped: " .. why) return end
    local levels = Levels(grid)
    local order, move, why
    while true do
        local pin = levels[s.level]
        if pin == nil then
            Finish("No free room left to move things around - stopped part way (free a few cells and press "
                .. SORT_KEY .. " again)")
            return
        end
        order = Plan(grid, pin or nil)
        if order then
            move, why = NextMove(grid, order)
            if move or why == "done" then break end
        end
        s.level = s.level + 1   -- not enough room: the next biggest items stay put
        if levels[s.level] then
            log(string.format("Not enough free room to move everything: items of more than %d cells stay where they are",
                levels[s.level]))
        end
    end
    if not move then
        Finish("Sorted " .. s.invName .. ": " .. #order .. " items" .. (s.level > 1 and " (the biggest left in place)" or ""))
        return
    end
    s.steps = s.steps + 1
    if s.steps > s.maxSteps then Finish("Stopped after " .. s.maxSteps .. " moves - it didn't settle") return end
    local from, to, what, rot = move.from, move.to, move.item, move.item.rotated
    local key = from .. ">" .. to
    if key == s.lastMove then
        s.same = s.same + 1
        if s.same >= 6 then Finish("The game refused moving " .. what.id .. " from " .. from .. " to " .. to .. " - stopped") return end
        return   -- the last move may still be on its way (the host's game does it)
    end
    s.lastMove, s.same = key, 0
    local ok, err = Move(s.player, s.inv, from, to, rot)
    if not ok then Finish("Moving failed: " .. tostring(err)) return end
    s.moved = s.moved + 1
end

local function Start()
    if sorting then log("Already sorting (.sort stop stops it)") return end
    local player, inv, why = OpenContainer()
    if not inv then log("Nothing to sort: " .. tostring(why)) return end
    local grid, bad = ReadGrid(inv)
    if not grid then log("Can't sort " .. NameOf(inv) .. ": " .. bad) return end
    if #grid.items == 0 then log("It's empty") return end
    sorting = { player = player, inv = inv, invName = NameOf(inv), steps = 0, maxSteps = #grid.items * 10 + 50,
                lastMove = nil, same = 0, moved = 0, level = 1 }
    log(string.format("Sorting %s: %d items in %d cells (%d columns)", sorting.invName, #grid.items, grid.cells, grid.cols))
    LoopAsync(MOVE_MS, function()
        if not sorting then return true end
        ExecuteInGameThread(function()
            local ok, err = pcall(Step)
            if not ok then Finish("Error: " .. tostring(err)) end
        end)
        return false
    end)
end

local function Check()
    local player, inv, why = OpenContainer()
    if not inv then log("Nothing open: " .. tostring(why)) return end
    local grid, bad = ReadGrid(inv)
    if not grid then log(NameOf(inv) .. ": can't read it: " .. bad) return end
    local blocked = 0
    for _ in pairs(grid.blocked) do blocked = blocked + 1 end
    log(string.format("%s: %d cells, %d columns, %d blocked, %d items", NameOf(inv), grid.cells, grid.cols, blocked, #grid.items))
    -- the plan for a full sort (only the first step: a full container may
    -- end up leaving its biggest items in place)
    local order = Plan(grid, nil)
    for _, it in ipairs(order or Order(grid.items)) do
        log(string.format("  %-34s x%-4s %dx%d%s at %d -> %s", it.id, tostring(it.amount), it.w, it.h,
            it.rotated and " (turned)" or "", it.root, tostring(it.target)))
    end
    if not order then log("  sorted it doesn't pack - S sorts the smaller items around the biggest") end
end

------------------------------------------------------------
-- Keys and commands
------------------------------------------------------------
-- S only while a container is open with the mouse pointer shown (the
-- inventory screen): S is also walking backwards
local function InventoryScreenOpen()
    local pc = LocalController()
    if not pc then return false end
    local shown = false
    pcall(function() shown = pc.bShowMouseCursor == true end)
    return shown
end

if Key and Key[SORT_KEY] then
    RegisterKeyBind(Key[SORT_KEY], function()
        ExecuteInGameThread(function()
            if sorting or not InventoryScreenOpen() then return end
            local _, inv = OpenContainer()
            if inv then pcall(Start) end
        end)
    end)
else
    log("key '" .. SORT_KEY .. "' isn't a key UE4SS knows - use .sort")
end

RegisterConsoleCommandHandler(".sort", function(FullCommand, Parameters)
    local a = string.lower(tostring((Parameters and Parameters[1]) or ""))
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if a == "stop" then
                if sorting then Finish("Stopped") else log("Not sorting") end
            elseif a == "check" then Check()
            else Start() end
        end)
        if not ok then log("Error: " .. tostring(err)) end
    end)
    return true
end)

log("Loaded v" .. VERSION .. ": open a container and press " .. SORT_KEY .. " to sort it (.sort check shows what it sees)")
