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
--   .sort repair         cells marked as taken by an item that isn't there
--                        become free again (the host's game: run it as the host)
------------------------------------------------------------
local VERSION = "1.5.4"
local MOD_DIR = "./ue4ss/Mods/ChestSort/"

local function log(msg) print("[ChestSort] " .. tostring(msg) .. "\n") end

-- Hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("ChestSort")

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
-- Items are turned to lie flat (wider than tall) so they line up in even
-- rows; false: every item keeps the way it's turned now
local ROTATE = cfg.rotate ~= false
-- Shift+click (quick move) of a stack from your inventory into the open
-- container: when the game doesn't move it (its own bug with stacks), the
-- mod moves the whole stack itself. false: off
local QUICK_MOVE_FIX = cfg.quickMoveFix ~= false

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

-- The container of an actor: its inventory component with the most cells
local function ContainerOf(actor)
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
    return best
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
    local best = ContainerOf(actor)
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
        item.cw, item.ch = item.w, item.h   -- its shape now (w, h become the planned shape)
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
-- What kind of item it is: the start of its ID (Ammo_9mm -> Ammo,
-- Holdable_RGD5 -> Holdable). Kinds go in this order; others after them
local KIND_ORDER = { "Weapon", "Magazine", "Ammo", "Attachment", "Holdable", "Consumable", "Food", "Drink", "Equipment",
                     "Artifact", "Resource", "Plant", "BuildPart", "Object", "Misc" }
local KIND_ALIAS = { CUTWeapon = "Weapon" }
local KIND_RANK = {}
for i, k in ipairs(KIND_ORDER) do KIND_RANK[k] = i end
local function KindOf(id)
    local k = tostring(id):match("^([^_]+)_") or "Misc"
    return KIND_ALIAS[k] or k
end

local function Order(items)
    local list = {}
    for _, it in ipairs(items) do
        it.kind = KindOf(it.id)
        it.kindRank = KIND_RANK[it.kind] or 100
        table.insert(list, it)
    end
    table.sort(list, function(a, b)
        if a.kindRank ~= b.kindRank then return a.kindRank < b.kindRank end
        if a.kind ~= b.kind then return a.kind < b.kind end
        local aa, ba = a.w * a.h, b.w * b.h
        if aa ~= ba then return aa < ba end
        if a.h ~= b.h then return a.h < b.h end
        if a.id ~= b.id then return a.id < b.id end
        if a.amount ~= b.amount then return a.amount > b.amount end
        if a.w ~= b.w then return a.w < b.w end
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
    -- Each item keeps the way it's turned; only if the container is too
    -- full for that are tall items turned flat (wider than tall) to fit
    local function shapes(flat)
        for _, it in ipairs(grid.items) do
            local w, h = it.cw, it.ch
            if flat and h > w and not (pin and w * h > pin) then w, h = h, w end
            it.w, it.h = w, h
        end
    end
    shapes(false)
    local order = Order(grid.items)
    -- Neat rows: each "shelf" holds one height of item, filled left to right
    -- row by row; the next height starts a new shelf below. Smallest first,
    -- so 1-cell items fill the top rows, then 2-cell, then 3-cell...
    -- mode: "shape" a shelf per kind of item (ammo, grenades, food...) and
    -- shape; "height" a shelf per kind and height (1x1, 2x1, 3x1 of a kind
    -- share rows); "mixed" a shelf per height only, the kinds in order within
    -- it: fewer half-empty rows each, for containers too small for the one before
    local function shelves(mode)
        local byHeight = mode ~= "shape"
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
        if byHeight then
            table.sort(list, function(a, b)
                if a.h ~= b.h then return a.h < b.h end
                return false
            end)
            -- (table.sort isn't stable: keep the sorted order within a height)
            local rank = {}
            for i, it in ipairs(order) do rank[it] = i end
            table.sort(list, function(a, b)
                if mode == "height" and a.kindRank ~= b.kindRank then return a.kindRank < b.kindRank end
                if mode == "height" and a.kind ~= b.kind then return a.kind < b.kind end
                if a.h ~= b.h then return a.h < b.h end
                return rank[a] < rank[b]
            end)
        end
        local cols = grid.cols
        local top, x, shelfH, shape = 0, 0, nil, nil
        for _, it in ipairs(list) do
            local key = (mode == "mixed" and "" or it.kind .. "|") .. (byHeight and tostring(it.h) or (it.w .. "x" .. it.h))
            if shape ~= key then
                -- a new shape: a new shelf (below whatever the last one used)
                if shelfH then top, x = top + shelfH, 0 end
                shelfH, shape = it.h, key
            end
            while not it.target do
                if x + it.w > cols then top, x = top + shelfH, 0 end
                local idx = top * cols + x
                if idx >= grid.cells then return false end
                if Fits(grid, idx, it.w, it.h, taken) then
                    it.target = idx
                    Mark(grid, idx, it.w, it.h, taken, true)
                    x = x + it.w
                else
                    x = x + 1
                end
            end
        end
        return true
    end
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
    local function any()
        return shelves("shape") or shelves("height") or shelves("mixed") or try(false) or try(true)
    end
    local fits = any()
    if not fits and ROTATE and not grid.noRotate then
        shapes(true)
        order = Order(grid.items)
        fits = any()
    end
    if fits then
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
local function ParkingSpot(grid, item, order, k, strict, avoid)
    local taken = {}   -- (over its own cells only if the game allows that, see Step)
    for i, o in pairs(grid.owner) do
        if o ~= item or not grid.selfOk then taken[i] = true end
    end
    for i in pairs(avoid or {}) do taken[i] = true end
    -- (a place being cleared for another item stays free for it)
    local room = grid.room
    if room and room.owner ~= item.id .. "@" .. item.root then
        for i in pairs(room.cells) do taken[i] = true end
    end
    local due = {}     -- cell -> the lowest order number whose target covers it
    for j = 1, #order do
        local o = order[j]
        if o.root ~= o.target or o.cw ~= o.w or j == k then
            for r = o.target // grid.cols, o.target // grid.cols + o.h - 1 do
                for c = o.target % grid.cols, o.target % grid.cols + o.w - 1 do
                    local i = r * grid.cols + c
                    if not due[i] or j < due[i] then due[i] = j end
                end
            end
        end
    end
    -- in its planned shape first (a tall item turned flat may fit where it
    -- doesn't standing), else as it is now
    local shapes = { { item.w, item.h } }
    if item.w ~= item.cw then table.insert(shapes, { item.cw, item.ch }) end
    for _, shape in ipairs(shapes) do
        local w, h = shape[1], shape[2]
        local best, bestScore = nil, -1
        for idx = 0, grid.cells - 1 do
            if Fits(grid, idx, w, h, taken) and not (idx == item.root and w == item.cw) then
                local score, overK = math.huge, false
                for r = idx // grid.cols, idx // grid.cols + h - 1 do
                    for c = idx % grid.cols, idx % grid.cols + w - 1 do
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
        if best then return best, w ~= item.cw end
    end
    return nil
end

-- Is w x h at idx free for item? Its own cells count as free when the game
-- allows moving an item partly over where it is (grid.selfOk). Returns
-- free, overItself
local function AreaFree(grid, idx, w, h, item)
    local overSelf = false
    for r = idx // grid.cols, idx // grid.cols + h - 1 do
        for c = idx % grid.cols, idx % grid.cols + w - 1 do
            local o = grid.owner[r * grid.cols + c]
            if o then
                if o == item and grid.selfOk then overSelf = true else return false end
            end
        end
    end
    return true, overSelf
end

-- Does w x h at idx overlap item's cells?
local function OverItself(grid, idx, w, h, item)
    for r = idx // grid.cols, idx // grid.cols + h - 1 do
        for c = idx % grid.cols, idx % grid.cols + w - 1 do
            if grid.owner[r * grid.cols + c] == item then return true end
        end
    end
    return false
end

-- The next move: { from, to, item, why } or nil, why.
-- 1. any item whose place is free goes straight there (smallest first);
-- 2. else something in the way of the first item still to place is parked
--    where it's least in the way (or the item itself, when only it is there)
local function NextMove(grid, order)
    local pending = {}
    for k, it in ipairs(order) do
        if it.root ~= it.target or it.cw ~= it.w then table.insert(pending, k) end
    end
    if #pending == 0 then return nil, "done" end
    -- a place cleared for an item only matters while the same item waits for room
    local first = order[pending[1]]
    if grid.room and grid.room.forK ~= first.id .. "@" .. first.target then grid.room = nil end
    local function inRoom(idx, w, h, item)
        local room = grid.room
        if not room or room.owner == item.id .. "@" .. item.root then return false end
        for r = idx // grid.cols, idx // grid.cols + h - 1 do
            for c = idx % grid.cols, idx % grid.cols + w - 1 do
                if room.cells[r * grid.cols + c] then return true end
            end
        end
        return false
    end
    for _, k in ipairs(pending) do
        local it = order[k]
        -- (free of everything: an item turning onto its own cells may be refused)
        local free, overSelf = AreaFree(grid, it.target, it.w, it.h, it)
        if free and inRoom(it.target, it.w, it.h, it) then free = false end
        if free then
            return { from = it.root, to = it.target, item = it, turn = it.cw ~= it.w, overSelf = overSelf }
        end
    end
    -- nothing can go straight: make room.
    -- Only the first item still to place gets room made (the ones before it
    -- are in their places and never move again): each thing in its way goes
    -- anywhere free that's not over its place, least in the way of the rest
    -- first. So every item is placed after a few moves and nothing can keep
    -- swapping (1.3.0 and older gave up on mostly empty containers and left
    -- the big items where they were)
    local k = pending[1]
    local it = order[k]
    local blockers, seen = {}, {}
    for r = it.target // grid.cols, it.target // grid.cols + it.h - 1 do
        for c = it.target % grid.cols, it.target % grid.cols + it.w - 1 do
            local o = grid.owner[r * grid.cols + c]
            if o and not seen[o] then seen[o] = true table.insert(blockers, o) end
        end
    end
    local function park(b, to, turn)
        local w, h = b.cw, b.ch
        if turn then w, h = b.ch, b.cw end
        return { from = b.root, to = to, item = b, turn = turn, overSelf = OverItself(grid, to, w, h, b) }
    end
    for _, strict in ipairs({ true, false }) do
        for _, b in ipairs(blockers) do
            local to, turn = ParkingSpot(grid, b, order, k, strict)
            if to then return park(b, to, turn) end
        end
    end
    -- Nothing in the way can go anywhere (two big items each over the
    -- other's place, no free room): the item itself moves aside, but only
    -- where that lets something in the way move next (else they'd swap back
    -- and forth)
    if not seen[it] then
        local to, turn = ParkingSpot(grid, it, order, k, false)
        if to then
            local w, h = it.cw, it.ch
            if turn then w, h = it.ch, it.cw end
            local saved = {}
            for i, o in pairs(grid.owner) do if o == it then saved[i] = true grid.owner[i] = nil end end
            for r = to // grid.cols, to // grid.cols + h - 1 do
                for c = to % grid.cols, to % grid.cols + w - 1 do grid.owner[r * grid.cols + c] = it end
            end
            local helps = false
            for _, b in ipairs(blockers) do
                if ParkingSpot(grid, b, order, k, false) then helps = true break end
            end
            for i, o in pairs(grid.owner) do if o == it then grid.owner[i] = nil end end
            for i in pairs(saved) do grid.owner[i] = it end
            if helps then return park(it, to, turn) end
        end
    end
    -- Still stuck: clear a place for something in the way by moving smaller
    -- items out of it first (the place with the fewest cells to clear; the
    -- items already sorted, the item being placed and its place untouched)
    local placed = {}
    for j = 1, k - 1 do placed[order[j]] = true end
    local inTarget = {}
    Mark(grid, it.target, it.w, it.h, inTarget, true)
    local best = nil
    for _, b in ipairs(blockers) do
        if b ~= it then
            local shapes = { { b.w, b.h } }
            if b.w ~= b.cw then table.insert(shapes, { b.cw, b.ch }) end
            for _, shape in ipairs(shapes) do
                local w, h = shape[1], shape[2]
                for idx = 0, grid.cells - 1 do
                    local r0, c0 = idx // grid.cols, idx % grid.cols
                    if c0 + w <= grid.cols and (r0 + h - 1) * grid.cols + c0 + w - 1 < grid.cells then
                        local ok, occupants, cost, seenO = true, {}, 0, {}
                        for r = r0, r0 + h - 1 do
                            for c = c0, c0 + w - 1 do
                                local i = r * grid.cols + c
                                local o = grid.owner[i]
                                if grid.blocked[i] or inTarget[i] or o == b or o == it or (o and placed[o]) then ok = false end
                                if ok and o and not seenO[o] then
                                    seenO[o] = true
                                    table.insert(occupants, o)
                                    cost = cost + o.cw * o.ch
                                end
                            end
                        end
                        if ok and #occupants > 0 and (not best or cost < best.cost) then
                            best = { cost = cost, occupants = occupants, idx = idx, w = w, h = h, b = b }
                        end
                    end
                end
            end
        end
    end
    if best then
        local avoid = {}
        Mark(grid, best.idx, best.w, best.h, avoid, true)
        local cells = {}
        for i in pairs(avoid) do cells[i] = true end
        Mark(grid, it.target, it.w, it.h, avoid, true)
        for _, o in ipairs(best.occupants) do
            local to, turn = ParkingSpot(grid, o, order, k, false, avoid)
            if to then
                local m = park(o, to, turn)
                m.room = { cells = cells, owner = best.b.id .. "@" .. best.b.root, forK = it.id .. "@" .. it.target }
                return m
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
    -- did the last move leave the item turned the way it should? The game's
    -- "turned" flag on a move could be the new state or "turn it": the first
    -- move that comes out wrong switches to the other reading, a second one
    -- stops turning items
    local e = s.expect
    if e then
        local it = grid.owner[e.to]
        if it and it.root == e.to then
            s.expect = nil
            if it.cw ~= e.w and it.cw == e.h and it.ch == e.w then
                if not s.toggleTried then
                    s.toggle, s.toggleTried = not s.toggle, true
                    log("(the game turns items on a move when told to: switched to that)")
                else
                    s.noRotate = true
                    log("Turning items doesn't work as expected here - they keep the way they're turned")
                end
            end
        end
    end
    grid.noRotate = s.noRotate
    -- Never partly over itself: 1.4.0 did that, and a fridge was left with
    -- cells still marked as taken by an item that had moved away (17 Oct)
    grid.selfOk = false
    grid.room = s.room
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
            s.room = move and move.room or grid.room
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
    local from, to, what = move.from, move.to, move.item
    -- turned after the move: as now, or the other way when it's to be turned
    local turned = what.rotated
    if move.turn then turned = not turned end
    local rot = turned
    if s.toggle then rot = move.turn == true end
    local endW, endH = what.cw, what.ch
    if move.turn then endW, endH = what.ch, what.cw end
    local key = from .. ">" .. to
    if key == s.lastMove then
        s.same = s.same + 1
        if s.same >= 6 then
            if move.overSelf and not s.noSelfOverlap then
                -- the game doesn't move an item partly over itself: not again
                s.noSelfOverlap, s.lastMove, s.same = true, nil, 0
                log("(the game won't move an item partly over where it is: going around that)")
                return
            end
            -- a turned item refused when only moved: the game may read the
            -- "turned" flag as "turn it" (the item wouldn't fit turned). Tried
            -- once; refused again means that wasn't it
            if what.rotated and not move.turn and not s.toggleTried and not s.noRotate then
                s.toggleTried, s.toggle, s.lastMove, s.same, s.toggleFlip = true, not s.toggle, nil, 0, key
                return
            end
            if s.toggleFlip == key then s.toggle = not s.toggle end
            Finish("The game refused moving " .. what.id .. " from " .. from .. " to " .. to .. " - stopped")
            return
        end
        return   -- the last move may still be on its way (the host's game does it)
    end
    s.lastMove, s.same = key, 0
    local ok, err = Move(s.player, s.inv, from, to, rot)
    if not ok then Finish("Moving failed: " .. tostring(err)) return end
    if not s.noRotate then s.expect = { to = to, w = endW, h = endH } end
    s.moved = s.moved + 1
end

local function Start()
    if sorting then log("Already sorting (.sort stop stops it)") return end
    local player, inv, why = OpenContainer()
    if not inv then log("Nothing to sort: " .. tostring(why)) return end
    local grid, bad = ReadGrid(inv)
    if not grid then
        log("Can't sort " .. NameOf(inv) .. ": " .. bad
            .. (bad:find("isn't there", 1, true) and " - .sort repair (as the host) frees those cells" or ""))
        return
    end
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

-- .sort repair: cells marked as taken by an item that isn't there (their
-- item's top-left cell isn't that item any more) become empty again, like
-- the container's other empty cells.
-- In co-op each player's game keeps its own copy of an open container's
-- cells (the host's game sends them), so a joined player's copy can be broken
-- while the host's is fine, or both: a joined player's .sort repair fixes its
-- own copy and asks the host's Chest Sort to fix the host's and send it again.

-- Fixes inv's broken cells. Returns the broken cells, how many were freed
-- (read back to check the change stuck)
local function RepairCells(inv)
    local arr = inv.Inventory
    local n = 0
    pcall(function() n = arr:GetArrayNum() end)
    local occ, root = {}, {}
    local emptyRoot = nil   -- what an empty cell holds as its top-left cell
    for i = 1, n do
        pcall(function()
            local slot = arr[i]
            occ[i - 1] = slot[F.occupied] == true
            root[i - 1] = slot[F.rootIndex]
            if not occ[i - 1] and emptyRoot == nil then emptyRoot = slot[F.rootIndex] end
        end)
    end
    local bad = {}
    for idx = 0, n - 1 do
        local r = root[idx]
        if occ[idx] and not (type(r) == "number" and occ[r] and root[r] == r) then table.insert(bad, idx) end
    end
    local fixed = 0
    for _, idx in ipairs(bad) do
        pcall(function()
            local slot = arr[idx + 1]
            slot[F.occupied] = false
            slot[F.rootIndex] = emptyRoot or -1
            local it = slot[F.item]
            it[F.id] = FName("None")
            it[F.amount] = 0
        end)
        local now = true
        pcall(function() now = arr[idx + 1][F.occupied] end)
        if now == false then fixed = fixed + 1 end
    end
    return bad, fixed
end

local function Joined()
    local pc = LocalController()
    local joined = false
    pcall(function() joined = pc:HasAuthority() == false end)
    return joined, pc
end

local function Repair()
    local _, inv, why = OpenContainer()
    if not inv then log("Nothing open: " .. tostring(why)) return end
    local joined, pc = Joined()
    local bad, fixed = RepairCells(inv)
    if #bad == 0 then
        log(NameOf(inv) .. ": no broken cells" .. (joined and " in your copy" or ""))
    else
        log(string.format("%s: freed %d of %d cell(s) taken by an item that isn't there (%s)%s", NameOf(inv), fixed, #bad,
            table.concat(bad, ", "), joined and " in your copy" or ""))
    end
    if joined then
        local ok = pcall(function() pc:ServerNotifyLoadedWorld(FName("CHESTSORT_REPAIR")) end)
        log(ok and "Asked the host's Chest Sort to fix its copy and send it again (the host needs 1.4.2)"
            or "Couldn't ask the host")
    else
        pcall(function() inv:UpdateAllPlayersRootItems(true, {}) end)
    end
    if #bad > 0 then log("Close the container and open it again") end
end

-- Hosting: a joined player's .sort repair. Their open container is fixed
-- here and sent to them again; the answer shows in their console
local function OnPlayerAsks(selfParam, nameParam)
    local name = ""
    pcall(function() name = nameParam:get():ToString() end)
    if name ~= "CHESTSORT_REPAIR" then return end
    local pc = nil
    pcall(function() pc = selfParam:get() end)
    if not Valid(pc) then return end
    local isLocal, authority = true, false
    pcall(function() isLocal = pc:IsLocalController() end)
    pcall(function() authority = pc:HasAuthority() end)
    if isLocal or not authority then return end
    ExecuteInGameThread(function()
        local player, actor, inv = nil, nil, nil
        pcall(function() player = pc.Character.PlayerInventory end)
        pcall(function() actor = player.InteractedActor end)
        if Valid(actor) then inv = ContainerOf(actor) end
        local text
        if not inv then
            text = "[ChestSort] The host's game doesn't see a container open for you #CS:none"
        else
            local bad, fixed = RepairCells(inv)
            pcall(function() inv:ServerUpdateItemSlots(player) end)
            pcall(function() inv:UpdateAllPlayersRootItems(true, {}) end)
            text = string.format("[ChestSort] Host: %d broken cell(s) in its copy, %d freed; sent it to you again #CS:ok", #bad, fixed)
            log(string.format("A player's repair: %s, %d broken cell(s), %d freed", NameOf(inv), #bad, fixed))
        end
        pcall(function() pc:ClientMessage(text, FName("None"), 0.0) end)
    end)
end
pcall(RegisterHook, "/Script/Engine.PlayerController:ServerNotifyLoadedWorld", OnPlayerAsks)

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
-- Quick move fix: Shift+click on a stack in your inventory
------------------------------------------------------------
-- The game's quick move does nothing for many stacks (100 wood into the
-- workbench; its own bug, host or not). The click is seen on the item's
-- icon, and the mod moves the whole stack into the first free place in the
-- open container with the game's own move (the same as dragging it there).
local ICON_CLASS = "/Game/SurvivalGameKitV2/Blueprints/Widgets/BP_InventoryItemIcon.BP_InventoryItemIcon_C"
local quick = { hooked = false }

local function KeyDown(pc, name)
    local down = false
    pcall(function() down = pc:IsInputKeyDown({ KeyName = FName(name) }) end)
    return down == true
end

local function QuickMoveCheck(player, src, dst, root, id, amount)
    if not (Valid(player) and Valid(src) and Valid(dst)) then return end
    local sg = ReadGrid(src)
    if not sg then return end
    local it = sg.owner[root]
    -- moved (or changed) by the game: nothing to do
    if not it or it.root ~= root or it.id ~= id or it.amount ~= amount then return end
    local dg, why = ReadGrid(dst)
    if not dg then log("Quick move: can't read the container (" .. tostring(why) .. ")") return end
    local taken = {}
    for i in pairs(dg.owner) do taken[i] = true end
    local shapes = { { it.cw, it.ch, it.rotated } }
    if ROTATE and it.cw ~= it.ch then table.insert(shapes, { it.ch, it.cw, not it.rotated }) end
    for _, shape in ipairs(shapes) do
        for idx = 0, dg.cells - 1 do
            if Fits(dg, idx, shape[1], shape[2], taken) then
                local ok, err = pcall(function()
                    player:ServerMoveItem({ [F.slotInv] = src, [F.slotIndex] = root },
                        { [F.slotInv] = dst, [F.slotIndex] = idx }, shape[3], false, 0)
                end)
                quick.moves = (quick.moves or 0) + 1
                if quick.moves <= 5 or not ok then
                    log(string.format("Quick move: %s x%s %s", id, tostring(amount),
                        ok and ("to cell " .. idx) or ("failed: " .. tostring(err))))
                end
                return
            end
        end
    end
    log("Quick move: no free room for " .. id .. " in the container")
end

local function OnIconClicked(selfParam)
    if not QUICK_MOVE_FIX or sorting then return end
    local icon = nil
    pcall(function() icon = selfParam:get() end)
    if not Valid(icon) then return end
    local pc = LocalController()
    if not pc then return end
    -- the quick move key (Shift): the game's own flag. With the inventory
    -- screen open the player's input doesn't see keys (1.5.0 asked it, so the
    -- fix never ran)
    local player, dst, why = OpenContainer()
    local held = false
    pcall(function() held = player.QuickMoveKeyDown == true end)
    if not held then held = KeyDown(pc, "LeftShift") or KeyDown(pc, "RightShift") end
    quick.clicks = (quick.clicks or 0) + 1
    local function skip(reason)
        if quick.clicks <= 5 then log("Quick move: click " .. quick.clicks .. " skipped: " .. reason) end
    end
    if not held then return skip("Shift isn't held") end
    if not (player and dst) then return skip(tostring(why)) end
    local src, idx = nil, nil
    -- the icon's container (GetInventory gives a copy of its cells instead)
    pcall(function() src = icon.GridInven end)
    pcall(function() idx = icon.ItemIndex end)
    if not Valid(src) or type(idx) ~= "number" then return skip("couldn't tell which item (" .. tostring(idx) .. ")") end
    -- only from your side into the open container (the other way works)
    local same = false
    pcall(function() same = src:GetAddress() == dst:GetAddress() end)
    if same then return end
    local sg, bad = ReadGrid(src)
    local it = sg and sg.owner[idx]
    if not it then return skip("no item at cell " .. idx .. " of " .. NameOf(src) .. (bad and (" (" .. bad .. ")") or "")) end
    if quick.clicks <= 5 then log("Quick move: watching " .. it.id .. " x" .. tostring(it.amount)) end
    local root, id, amount = it.root, it.id, it.amount
    -- right away (on the next frame): 1.5.x waited half a second to see
    -- whether the game moved it, which felt slow. If the game moves it too,
    -- whichever move comes second finds the cell empty and does nothing
    ExecuteInGameThread(function() pcall(QuickMoveCheck, player, src, dst, root, id, amount) end)
end

local function HookIcons()
    if quick.hooked or not QUICK_MOVE_FIX then return quick.hooked end
    local fn = nil
    pcall(function() fn = StaticFindObject(ICON_CLASS .. ":OnMouseButtonDown") end)
    if not Valid(fn) then return false end
    quick.hooked = pcall(RegisterHook, ICON_CLASS .. ":OnMouseButtonDown", OnIconClicked)
    if quick.hooked then log("Quick move fix on (Shift+click stacks into a container)") end
    return quick.hooked
end
-- the icon's Blueprint loads with the inventory screen: looked for until then
ExecuteInGameThread(function() pcall(HookIcons) end)
LoopAsync(3000, function()
    if quick.hooked or not QUICK_MOVE_FIX then return true end
    ExecuteInGameThread(function() pcall(HookIcons) end)
    return false
end)

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
            elseif a == "repair" then Repair()
            else Start() end
        end)
        if not ok then log("Error: " .. tostring(err)) end
    end)
    return true
end)

log("Loaded v" .. VERSION .. ": open a container and press " .. SORT_KEY .. " to sort it (.sort check shows what it sees)")
