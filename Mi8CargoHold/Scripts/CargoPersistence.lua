-- Native save snapshots, isolated from the player's normal save files.
-- No UObject pointers or hand-reconstructed item definitions are serialized.
local M = {}
local STORAGE = "StorageSaveData_24_FDA24E9744FF3CB47A7F92A5FC4748AB"
local INVENTORY = "inventory_21_2A4A93F346C9C45611D2AABF0F17C7C7"
local COUNT = "ItemCount_8_A7235E3648E8A13D8EACAE98FDA7439A"
local function hex(value)
    return (value:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end
function M.slot_name(slot, level)
    assert(type(slot) == "string" and slot ~= "", "save slot is unknown")
    assert(type(level) == "string" and level ~= "", "save level is unknown")
    local name = "ChopperCargo_v1_" .. hex(slot) .. "_" .. hex(level)
    assert(#name < 220, "save slot/level name is too long for cargo storage")
    return name
end
local function each(array, callback)
    if type(array) == "table" then
        for _, value in ipairs(array) do callback(value) end
    else
        array:ForEach(function(_, value)
            local ok, resolved = pcall(function() return value:get() end)
            callback(ok and resolved or value)
        end)
    end
end
function M.record(snapshot)
    local records = {}
    each(snapshot.TempStorageSaveData, function(value) records[#records+1] = value end)
    if #records == 0 then
        each(snapshot.LevelSaveData, function(level)
            each(level[STORAGE], function(value) records[#records+1] = value end)
        end)
    end
    assert(#records == 1, "native serializer produced " .. #records .. " cargo records; expected exactly one")
    local record = records[1]
    assert(type(tonumber(record[COUNT])) == "number", "saved item count is unreadable")
    assert(tonumber(record[COUNT]) >= 0, "saved item count is negative")
    assert(record[INVENTORY] ~= nil, "saved inventory field is missing")
    -- Validate every serialized root item before handing it back to the game.
    each(record[INVENTORY], function(item)
        local amount = tonumber(item.Amount_5_996A80EC407913F0E5E0699BFE6C0A88)
        assert(amount and amount >= 0, "invalid saved item amount")
    end)
    return record
end
function M.new(d)
    local self = {ready=false, error=nil, scope=nil, pending=nil, busy=false}
    local function guarded(fn)
        local ok, result = pcall(fn)
        if not ok then
            self.error = tostring(result)
            d.log("Cargo save error: " .. self.error)
            return false
        end
        return true, result
    end
    local function load(name)
        local snapshot = d.load(name)
        assert(d.valid(snapshot), "unreadable cargo save: " .. name)
        M.record(snapshot)
        return snapshot
    end
    local function write(snapshot, name)
        assert(d.save(snapshot, name) == true, "write failed: " .. name)
        load(name) -- Verify native deserialization, not merely a successful call.
    end
    function self:reset()
        self.ready, self.scope, self.pending, self.error = false, nil, nil, nil
    end
    function self:restore(slot, level)
        self.ready = false
        return guarded(function()
            self.scope = M.slot_name(slot, level)
            if d.exists(self.scope) then
                d.restore(M.record(load(self.scope)))
                d.log("Cargo restored for save slot '" .. slot .. "'.")
            elseif d.exists(self.scope .. "_backup") or d.exists(self.scope .. "_pending") then
                error("cargo recovery files exist without a primary save; hold locked for recovery")
            else
                d.log("New cargo hold for save slot '" .. slot .. "'.")
            end
            -- Prove the native snapshot route now, before accepting player items.
            M.record(d.capture())
            self.ready = true
            self.error = nil
        end)
    end
    function self:prepare(slot, level)
        if self.busy or not self.ready then return false end
        self.pending = nil
        self.busy = true
        local ok = guarded(function()
            local target = M.slot_name(slot, level)
            local snapshot = d.capture()
            M.record(snapshot)
            write(snapshot, target .. "_pending")
            self.pending = target
        end)
        self.busy = false
        return ok
    end
    function self:complete(success)
        if self.busy or not self.pending then return false end
        local target = self.pending
        self.pending = nil
        if success ~= true then
            self.error = "game save failed or success was not confirmed; previous cargo save preserved"
            d.log(self.error)
            return false
        end
        self.busy = true
        local ok = guarded(function()
            local snapshot = load(target .. "_pending")
            if d.exists(target) then write(load(target), target .. "_backup") end
            write(snapshot, target)
            self.error = nil
            d.log("Cargo saved alongside the game: " .. target)
        end)
        self.busy = false
        return ok
    end
    return self
end
return M
