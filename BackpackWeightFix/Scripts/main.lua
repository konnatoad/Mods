------------------------------------------------------------
-- Backpack Weight Fix
------------------------------------------------------------
-- MISERY bug: after stacking and moving items around a lot, a container's
-- weight can get stuck - e.g. an EMPTY backpack showing 73/75 kg that won't
-- take items any more. This finds containers that hold nothing but still
-- report weight and sets their weight back to 0.
--
-- Runs every few seconds by itself; .fixweight runs it right now.
-- Close and reopen the inventory afterwards to see the new number.
------------------------------------------------------------
-- Config
------------------------------------------------------------
-- each check scans every object in the game on this UE4SS build, so not too often
local checkEverySeconds = 30
----------------------------------

local INVENTORY_CLASS = "BP_MasterInventory_C"
-- The container's running weight total is a Blueprint variable; these are
-- the names it is most likely to have. The first one that exists is used.
local WEIGHT_FIELDS = {
    "CurrentWeight", "TotalWeight", "InventoryWeight", "CurrentInventoryWeight",
    "ContainerWeight", "CurrentCarryWeight",
}

-- Containers owned by these aren't bags or boxes: the game's global inventory
-- manager reports weight with ItemCount 0 while in normal use (it kept rising
-- between checks), so resetting it would only fight the game.
local SKIP_OWNERS = { "GlobalInventoryManager" }

local weightField = nil
local warnedNoField = false

local function log(msg)
    print("[BackpackWeightFix] " .. tostring(msg) .. "\n")
end

local function ReadNumber(obj, field)
    local ok, value = pcall(function() return obj[field] end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function FindWeightField(inv)
    if weightField then return weightField end
    for _, name in ipairs(WEIGHT_FIELDS) do
        if ReadNumber(inv, name) then
            weightField = name
            log("Container weight is stored in '" .. name .. "'")
            return name
        end
    end
    return nil
end

local function OwnerName(inv)
    local name = "container"
    pcall(function() name = inv:GetOwner():GetFName():ToString() end)
    return name
end

local function IsSkipped(inv)
    local owner = OwnerName(inv)
    for _, part in ipairs(SKIP_OWNERS) do
        if owner:find(part, 1, true) then return true end
    end
    return false
end

local function Containers()
    local list = {}
    pcall(function()
        for _, inv in ipairs(FindAllOf(INVENTORY_CLASS) or {}) do
            if inv:IsValid() then list[#list + 1] = inv end
        end
    end)
    return list
end

-- Empty (ItemCount 0) but weight above 0 is always the bug: reset it.
local function FixStuckWeights(verbose)
    local fixed, empty = 0, 0
    local containers = Containers()
    for _, inv in ipairs(containers) do
        local field = FindWeightField(inv)
        if field and ReadNumber(inv, "ItemCount") == 0 and not IsSkipped(inv) then
            empty = empty + 1
            local weight = ReadNumber(inv, field)
            if weight and weight > 0.01 then
                if pcall(function() inv[field] = 0.0 end) then
                    fixed = fixed + 1
                    log(string.format("Reset stuck weight on empty %s: %.2f kg -> 0", OwnerName(inv), weight))
                end
            end
        end
    end
    if #containers > 0 and not weightField and not warnedNoField then
        warnedNoField = true
        log("Couldn't find where containers keep their weight. Empty your backpack, type .weightreport and send the output.")
    end
    if verbose then
        log(string.format("Checked %d containers (%d empty), fixed %d", #containers, empty, fixed))
    end
    return fixed
end

LoopAsync(checkEverySeconds * 1000, function()
    ExecuteInGameThread(function() FixStuckWeights(false) end)
    return false
end)

RegisterConsoleCommandHandler(".fixweight", function()
    ExecuteInGameThread(function() FixStuckWeights(true) end)
    return true
end)

-- For finding the weight variable if none of WEIGHT_FIELDS exists: lists the
-- weight-related numbers of empty containers (empty your backpack first).
-- Only the container class's own variables are listed (names, then values by
-- name) - walking parent classes crashed this UE4SS build for the mod menu.
RegisterConsoleCommandHandler(".weightreport", function()
    ExecuteInGameThread(function()
        local containers = Containers()
        log("Report: " .. #containers .. " containers (" .. INVENTORY_CLASS .. ")")
        if #containers == 0 then return end
        local names = {}
        pcall(function()
            containers[1]:GetClass():ForEachProperty(function(prop)
                local name, kind = "", ""
                pcall(function() name = prop:GetFName():ToString() end)
                pcall(function() kind = prop:GetClass():GetFName():ToString() end)
                -- every number variable: the weight one may not have "weight" in its name
                if (kind == "FloatProperty" or kind == "DoubleProperty" or kind == "IntProperty")
                   and #names < 40 then
                    names[#names + 1] = name
                end
            end)
        end)
        log("Number variables: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
        local shown = 0
        for _, inv in ipairs(containers) do
            if ReadNumber(inv, "ItemCount") == 0 or ReadNumber(inv, "ItemCount") == nil then
                local values = {}
                for _, name in ipairs(names) do
                    values[#values + 1] = name .. "=" .. tostring(ReadNumber(inv, name))
                end
                log("  " .. OwnerName(inv) .. ": ItemCount=" .. tostring(ReadNumber(inv, "ItemCount")) .. " " .. table.concat(values, " "))
                shown = shown + 1
                if shown >= 15 then break end
            end
        end
    end)
    return true
end)

log("Loaded. Checks every " .. checkEverySeconds .. "s; .fixweight to run now, .weightreport if it can't find the weight.")
