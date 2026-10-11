ModName, ModVersion = "Stack Them All", "1.2.0"
local stackThemAllConfig = require("stackThemAllConfig")
local UEHelpers = require("UEHelpers")
local io = require("io")
local enablesLogs = true

local configPath = "./ue4ss/Mods/StackThemAll/scripts/stackConfig.lua"
local masterItemListPath = "/Game/SurvivalGameKitV2/Blueprints/Items/MasterLists/MasterItemList.MasterItemList"
local loadedStackConfig = nil

local function log(Message)
    local SMessage = tostring(Message) or "nil"
    print("STACK THEM ALL: " .. SMessage .. "\n")
end

local function debugLog(Message)
    if enablesLogs then
        local SMessage = tostring(Message) or "nil"
        print("STACK THEM ALL DEBUG LOG: " .. SMessage .. "\n")
    else
        return
    end
end

-- The category is the row name prefix before the first "_" (Food_Apple -> Food), and its stack size
-- comes from <Category>_StackSize in stackThemAllConfig.lua. Categories without one (Weapon, Equipment,
-- Magazine, Holdable, ...) return nil and keep the game's own stack values.
local function category_stack_size(rowName)
    local category = string.match(rowName, "^([^_]+)_")
    if not category then return nil end
    return stackThemAllConfig[category .. "_StackSize"]
end

local function read_item_rows(masterItemList)
    local itemListTable = {}
    masterItemList:ForEachRow(function(rowName, rowData)
        table.insert(itemListTable, {rowName = tostring(rowName), rowData = rowData})
    end)

    if stackThemAllConfig.aphapeticallySorted ~= false then
        table.sort(itemListTable, function(a, b) return a.rowName < b.rowName end)
    end
    return itemListTable
end

local function format_config_entry(rowName, rowData)
    local lines = {}
    local function write(text) table.insert(lines, text) end

    write("stackConfig[\"" .. rowName .. "\"] = {\n")

    local stackSize = category_stack_size(rowName)
    if stackSize then
        write("    stackSize = " .. stackSize .. ",\n")
        write("    allowStack = true,\n")
    else
        write("    stackSize = ".. tostring(rowData.MaxStack_18_C57243124FFDE0AB28797AA6F2C1E5F5) ..",\n")
        write("    allowStack = ".. tostring(rowData.AllowStacking_48_02CFD0D74B05709E8E432E824709C714) ..",\n")
    end

    write("    weight = " .. tostring(rowData.Weight_7_794436A247BB7BC85C7BF3BC8B1D13BA) .. ",\n")
    write("    width = " .. tostring(rowData.Width_12_AF2CA71343924568731BA285FA9ABEA0) .. ",\n")
    write("    height = " .. tostring(rowData.Height_10_E54E86E64E73A3ACD86E358532FC6061) .. ",\n")

    if rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852.CanContainItems_9_25B233D543AED7B2D8CF249BD72C953A then
        write("    canContainItems = true,\n")
        write("    containerInventoryCells = " .. tostring(rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852.ContainerInventoryCells_13_269D7DB442A1056CD715DEA438F850A2) .. ",\n")
        write("    containerColumns = " .. tostring(rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852.ContainerColumns_14_F97E5A5744D6545EC3C5FD967C512BF1) .. ",\n")
        write("    useWeight = " .. tostring(rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852.UseWeight_16_3F94FD134C121CE317A6D2A0C2938171) .. ",\n")
        write("    maxWeight = " .. tostring(rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852.MaxWeight_20_5CDB778F4D6FE3E65C8DD1A7E8722133) .. ",\n")
    end
    if rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.CanConsume_1_F33B573C44E7F10E734CE98A8F8B397B then
        write("    canConsume = true,\n")
        write("    healthRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Health_4_58F2B2E648683BE1B8D783B5F9DE5F26) .. ",\n")
        write("    hungerRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Hunger_9_0D90519F43945DD23F8A98A10994E8C6) .. ",\n")
        write("    thirstRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Thirst_10_D9ED71A24C1DAC5DFF4104823F0A5337) .. ",\n")
        write("    staminaRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Stamina_12_C4F7061C4ECC1EC288DC08B8F0EB32DD) .. ",\n")
        write("    radiationRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Radiation_67_D31CAFB144A016D3CA18EAA9BC483FC1) .. ",\n")
        write("    insanityRestore = " .. tostring(rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1.Insanity_70_2DC4A05F4C467A170F3092B4AE0647AC) .. ",\n")
    end
    if rowData.DurabilityDetails_90_B75E4B1C4EDEECACC047149CE7D922F6.UseDurability_1_13FF8AEC41F8FB8A7E973CA195D0CDF8 then
        write("    useDurability = true,\n")
        write("    maxDurability = " .. tostring(rowData.DurabilityDetails_90_B75E4B1C4EDEECACC047149CE7D922F6.MaxDurability_4_2937EBF8401931EACB7C5C932B3CB4FC) .. ",\n")
        write("    destroyItemAt0Durability = " .. tostring(rowData.DurabilityDetails_90_B75E4B1C4EDEECACC047149CE7D922F6.DestroyItemAt0Durability_8_0941EB874C13F33FB68492B0414CEB9F) .. ",\n")
    end

    write("}\n\n")
    return table.concat(lines)
end

local function create_config_file(masterItemList)
    local file = io.open(configPath, "w+")
    if not file then
        log("Failed to open stack config file for writing.")
        return
    end
    file:write("-- This file was generated by Stack Them All mod.\n")
    file:write("-- Generated on " .. os.date("%Y-%m-%d %H:%M:%S") .. ".\n")
    file:write("-- THIS FILE CAN BE DELETED OR RENAMED FOR A NEW UPDATED ONE TO BE GENERATED.\n\n")

    file:write("local stackConfig = {}\n\n")

    for _, row in ipairs(read_item_rows(masterItemList)) do
        file:write(format_config_entry(row.rowName, row.rowData))
    end

    file:write("return stackConfig")

    file:flush()
    file:close()
end

-- Appends items that the game added after stackConfig.lua was generated, keeping every existing
-- entry (and any edits made to it) untouched.
local function add_new_items_to_config(masterItemList, stackConfig)
    local newItems = {}
    for _, row in ipairs(read_item_rows(masterItemList)) do
        if stackConfig[row.rowName] == nil then
            table.insert(newItems, row)
        end
    end
    if #newItems == 0 then
        log("No new items found, stack config is up to date.")
        return false
    end

    local file = io.open(configPath, "r")
    if not file then
        log("Failed to open stack config file for reading.")
        return false
    end
    local content = file:read("*a")
    file:close()

    -- New entries go right before the final "return stackConfig".
    local returnAt, searchFrom = nil, 1
    while true do
        local found = string.find(content, "return stackConfig", searchFrom, true)
        if not found then break end
        returnAt, searchFrom = found, found + 1
    end
    if not returnAt then
        log("Stack config file has no \"return stackConfig\" line, not adding new items.")
        return false
    end

    local entries = {"-- Items added by Stack Them All " .. ModVersion .. " on " .. os.date("%Y-%m-%d %H:%M:%S") .. ".\n\n"}
    for _, row in ipairs(newItems) do
        table.insert(entries, format_config_entry(row.rowName, row.rowData))
        if category_stack_size(row.rowName) then
            log("Added new item: " .. row.rowName)
        else
            log("Added new item: " .. row.rowName .. " (no _StackSize for its category, keeps game stack values)")
        end
    end

    file = io.open(configPath, "w+")
    if not file then
        log("Failed to open stack config file for writing.")
        return false
    end
    file:write(string.sub(content, 1, returnAt - 1) .. table.concat(entries) .. string.sub(content, returnAt))
    file:flush()
    file:close()

    log("Added " .. #newItems .. " new item(s) to the stack config.")
    return true
end

local function load_stack_config()
    local ok, stackConfig = pcall(dofile, configPath)
    if not ok then
        log("Failed to load stack config file: " .. tostring(stackConfig))
        return nil
    end
    if type(stackConfig) ~= "table" then
        log("Stack config file did not return a table.")
        return nil
    end
    return stackConfig
end

-- Values missing from an entry are left as the game has them.
local function set_field(struct, fieldName, value)
    if value ~= nil then
        struct[fieldName] = value
    end
end

local function startup_lists_modification(masterItemList, stackConfig)
    masterItemList:ForEachRow(function(rowName, rowData)
        local itemConfig = stackConfig[tostring(rowName)]
        if not itemConfig then return false end

        set_field(rowData, "MaxStack_18_C57243124FFDE0AB28797AA6F2C1E5F5", itemConfig.stackSize)
        set_field(rowData, "AllowStacking_48_02CFD0D74B05709E8E432E824709C714", itemConfig.allowStack)
        if stackThemAllConfig.onlyStacksChanges then return false end

        set_field(rowData, "Weight_7_794436A247BB7BC85C7BF3BC8B1D13BA", itemConfig.weight)
        set_field(rowData, "Width_12_AF2CA71343924568731BA285FA9ABEA0", itemConfig.width)
        set_field(rowData, "Height_10_E54E86E64E73A3ACD86E358532FC6061", itemConfig.height)


        local containerDetails = rowData.ContainerDetails_59_DA2434FE4D9CB983040BE3B6CDDD8852
        if containerDetails.CanContainItems_9_25B233D543AED7B2D8CF249BD72C953A then
            set_field(containerDetails, "CanContainItems_9_25B233D543AED7B2D8CF249BD72C953A", itemConfig.canContainItems)
            set_field(containerDetails, "ContainerInventoryCells_13_269D7DB442A1056CD715DEA438F850A2", itemConfig.containerInventoryCells)
            set_field(containerDetails, "ContainerColumns_14_F97E5A5744D6545EC3C5FD967C512BF1", itemConfig.containerColumns)
            set_field(containerDetails, "UseWeight_16_3F94FD134C121CE317A6D2A0C2938171", itemConfig.useWeight)
            set_field(containerDetails, "MaxWeight_20_5CDB778F4D6FE3E65C8DD1A7E8722133", itemConfig.maxWeight)
        end

        local consumableDetails = rowData.ConsumableDetails_77_3E970B0D497E2A71D3B074A210E6F3F1
        if consumableDetails.CanConsume_1_F33B573C44E7F10E734CE98A8F8B397B then
            set_field(consumableDetails, "CanConsume_1_F33B573C44E7F10E734CE98A8F8B397B", itemConfig.canConsume)
            set_field(consumableDetails, "Health_4_58F2B2E648683BE1B8D783B5F9DE5F26", itemConfig.healthRestore)
            set_field(consumableDetails, "Hunger_9_0D90519F43945DD23F8A98A10994E8C6", itemConfig.hungerRestore)
            set_field(consumableDetails, "Thirst_10_D9ED71A24C1DAC5DFF4104823F0A5337", itemConfig.thirstRestore)
            set_field(consumableDetails, "Stamina_12_C4F7061C4ECC1EC288DC08B8F0EB32DD", itemConfig.staminaRestore)
            set_field(consumableDetails, "Radiation_67_D31CAFB144A016D3CA18EAA9BC483FC1", itemConfig.radiationRestore)
            set_field(consumableDetails, "Insanity_70_2DC4A05F4C467A170F3092B4AE0647AC", itemConfig.insanityRestore)
        end

        local durabilityDetails = rowData.DurabilityDetails_90_B75E4B1C4EDEECACC047149CE7D922F6
        if durabilityDetails.UseDurability_1_13FF8AEC41F8FB8A7E973CA195D0CDF8 then
            set_field(durabilityDetails, "UseDurability_1_13FF8AEC41F8FB8A7E973CA195D0CDF8", itemConfig.useDurability)
            set_field(durabilityDetails, "MaxDurability_4_2937EBF8401931EACB7C5C932B3CB4FC", itemConfig.maxDurability)
            set_field(durabilityDetails, "DestroyItemAt0Durability_8_0941EB874C13F33FB68492B0414CEB9F", itemConfig.destroyItemAt0Durability)
        end
    end)
    return true
end

local function modifingLoadedItems()
    local alreadyLoadedItems = FindAllOf("BP_StaticMasterItem_C")
    if not alreadyLoadedItems then return false end
    for __, loadedItems in pairs(alreadyLoadedItems) do
        local fullName = loadedItems:GetFullName()
        if string.find(fullName, "BP_StaticMasterItem_C") then
            loadedItems.RefreshItem = true
            return true
        end
    end
end

-- Only one setup runs at a time. ClientRestart fires several times per load
-- and again on every respawn; each used to start its own setup that re-ran
-- everything every 2s until world items existed (~1400 times in 12 minutes
-- at the main menu).
local isInitRunning = false
local isReapplyNeeded = false

-- Waits quietly (a check every 2s) for items in the world, then refreshes them.
local function refresh_loaded_items(isFirstTry)
    if isReapplyNeeded then
        -- a ClientRestart came in while waiting: apply the stack sizes again, as it always did
        isReapplyNeeded = false
        local masterItemList = StaticFindObject(masterItemListPath)
        if masterItemList and masterItemList:IsValid() and loadedStackConfig
           and startup_lists_modification(masterItemList, loadedStackConfig) then
            log("Master list modification completed successfully.")
        end
    end
    if modifingLoadedItems() then
        isInitRunning = false
        return
    end
    if isFirstTry then
        log("No items in the world yet, waiting for them to load...")
    end
    ExecuteWithDelay(2000, function() refresh_loaded_items(false) end)
end

local function try_init()
    log("Initializing stack config...")

    local masterItemList = StaticFindObject(masterItemListPath)
    if not masterItemList or not masterItemList:IsValid() then
        log("Waiting for Master Item List...")
        ExecuteWithDelay(2000, try_init)
        return
    end

    -- The file is read and checked for new items once per game session; the
    -- retries below (every 2s until items are loaded) reuse it.
    local stackConfig = loadedStackConfig
    if not stackConfig then
        local tryReadFile = io.open(configPath, "r")
        if tryReadFile then
            log("Stack config file already exists, checking for new items.")
            tryReadFile:close()
        else
            log("Stack config file does not exist, generating new one.")
            create_config_file(masterItemList)
        end

        stackConfig = load_stack_config()
        if not stackConfig then
            log("Fix the stack config file or delete it so a new one is generated.")
            isInitRunning = false
            return
        end

        if add_new_items_to_config(masterItemList, stackConfig) then
            stackConfig = load_stack_config()
            if not stackConfig then
                isInitRunning = false
                return
            end
        end
        loadedStackConfig = stackConfig
    end

    isReapplyNeeded = false  -- restarts that came in before this point are covered here
    if startup_lists_modification(masterItemList, stackConfig) then
        log("Master list modification completed successfully.")
    else
        log("Master list modification failed or is not implemented.")
        ExecuteWithDelay(2000, try_init)
        return
    end

    refresh_loaded_items(true)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
    log("ClientRestart fired")
    if isInitRunning then
        isReapplyNeeded = true
        return
    end
    isInitRunning = true
    ExecuteWithDelay(3000, try_init)
end)
