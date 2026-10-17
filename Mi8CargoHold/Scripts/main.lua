-- Mi8CargoHold (originally "ChopperStorage", Mi-8 Cargo Hold 1.0.1): turns the
-- decorative Mi-8 wreck (SM_Mi8_Broken_Chopper, a plain StaticMeshActor) into
-- a large storage container by attaching an invisible BP_CabinetWorld_C proxy to it.
--
--   Automatically creates the hold after a host save is ready.
--   Opens through the normal in-game Enter interaction at the wreck.
--
-- The player's build component and build menu are never used. Automatic host
-- creation and native cargo snapshots are coordinated at the end of this file.
-- Players joining a host who also runs this mod get the host's hold (see
-- client_ensure); the host's game keeps and saves the items.

-- Its hooks on the game's Blueprint functions are undone when the mod is
-- restarted (Mod Hub), so they can't run into the old copy: shared/GameHooks
local RegisterHook = require("GameHooks").ForMod("Mi8CargoHold")

local UEHelpers = require("UEHelpers")
local CargoPersistence = require("CargoPersistence")

local WRECK_MESH_NAME = "sm_mi8_broken_chopper"
-- Last scanned wreck location, used only to explain a failed lookup.
local WRECK_X, WRECK_Y, WRECK_Z = 20605.9, 29400.5, -42.0

local WORLD_CONTAINER_CLASS = "BP_CabinetWorld_C"
local WORLD_CONTAINER_CLASS_PATH = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/Furniture/WorldObect/Furniture/BP_CabinetWorld.BP_CabinetWorld_C"

-- Blueprint hook targets. For Blueprint functions UE4SS runs the Lua callback
-- after the function body, so widgets and out values are already populated.
local WIDGETS = "/Game/SurvivalGameKitV2/Blueprints/Widgets/"
local ITEM_NAME_INIT = WIDGETS .. "BP_ItemName.BP_ItemName_C:InitializeName"
local HUD_UPDATE_TEXT = WIDGETS .. "BP_InventoryHUD.BP_InventoryHUD_C:GetText"
local MENU_CLASS = WIDGETS .. "BP_InteractionContextMenu.BP_InteractionContextMenu_C"
local ENTRY_UPDATE_TEXT = WIDGETS .. "BP_InteractContextMenuEntry.BP_InteractContextMenuEntry_C:UpdateText"
local CONTAINER_WINDOW_CREATE = WIDGETS .. "BP_InventoryHUD.BP_InventoryHUD_C:CreateContainerWindow"
local STORAGE_CAN_PICKUP = "/Game/SurvivalGameKitV2/Blueprints/BuildParts/BP_MasterStorageBuildPart.BP_MasterStorageBuildPart_C:CanPickup"

-- Half-extents (cm) of the invisible interaction box around the fuselage.
local BOX_X, BOX_Y, BOX_Z = 700.0, 220.0, 180.0
-- Proxy actor scale; box extents are divided by it so the final volume
-- matches the half-extents above.
local CHOPPER_SCALE_X, CHOPPER_SCALE_Y, CHOPPER_SCALE_Z = 14.0, 5.5, 4.0

-- 1000 cells in 6 columns fits the native container window; the rest of the
-- grid is reached with its scroll bar.
local CONTAINER_CELLS = 1000
local CONTAINER_COLUMNS = 6
local CONTAINER_NAME = "Mi-8 Cargo Hold"
local ENTER_LABEL = "Enter"

-- Set either to false to fall back to the cabinet's native menu or pickup
-- logic if a game update breaks these hooks. The prompt title rename stays.
local ENABLE_ENTER_MENU = true
local ENABLE_PICKUP_GUARD = true

local DETAILS_FIELDS = {
    name = "ContainerName_12_EE9C9F0B4A29370B9E8EF09A188E8C15",
    cells = "ContainerInventoryCells_13_269D7DB442A1056CD715DEA438F850A2",
    columns = "ContainerColumns_14_F97E5A5744D6545EC3C5FD967C512BF1",
    can_contain = "CanContainItems_9_25B233D543AED7B2D8CF249BD72C953A",
    item_count_limit = "UseItemCountLimit_38_585327964096457C6B3EF697DA170C6F",
    weight = "UseWeight_16_3F94FD134C121CE317A6D2A0C2938171",
}
local ACTION_NAME_FIELD = "ActionName_15_19BA14C540FCFDAA9B8F29A403079514"
local ACTION_TYPE_FIELD = "WorldActions_14_09EA4A134331DF405C8B59A59F4D242C"

local ECR_IGNORE, ECR_BLOCK = 0, 2
local ECC_VISIBILITY, ECC_GAME_TRACE_1 = 3, 14
-- WorldDynamic, Pawn, Camera, PhysicsBody, Vehicle, Destructible: the hidden,
-- 14x-scaled cabinet must not block players, the camera or dropped items.
-- Trace channels are left alone so the interaction prompt keeps working.
local PASS_THROUGH_CHANNELS = {1, 2, 4, 5, 6, 7}
local SLATE_COLLAPSED = 1

local function log(msg)
    print("[Mi8CargoHold] " .. tostring(msg) .. "\n")
end

local logged_once = {}
local function log_once(key, msg)
    if not logged_once[key] then
        logged_once[key] = true
        log(msg)
    end
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

-- Hook parameters arrive as RemoteUnrealParam wrappers; object handles are
-- used as-is. UE4SS documents type() on every wrapper, so this never asks an
-- object for a member it does not have.
local function as_object(value)
    if value == nil then return nil end
    local ok_type, kind = pcall(function() return value:type() end)
    if ok_type and (kind == "RemoteUnrealParam" or kind == "LocalUnrealParam") then
        local ok_get, inner = pcall(function() return value:get() end)
        value = ok_get and inner or nil
    end
    return is_valid(value) and value or nil
end

local function address_of(object)
    if object == nil then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    return ok and address or nil
end

local function same_object(first, second)
    if not is_valid(first) or not is_valid(second) then return false end
    local address = address_of(first)
    return address ~= nil and address == address_of(second)
end

local function defer(delay_ms, callback)
    pcall(ExecuteInGameThreadWithDelay, delay_ms, function()
        local ok, err = pcall(callback)
        if not ok then log("Deferred callback failed: " .. tostring(err)) end
    end)
end

local function log_transform(actor, label)
    local ok_loc, loc = pcall(function() return actor:K2_GetActorLocation() end)
    local ok_scale, scale = pcall(function() return actor:GetActorScale3D() end)
    log(label .. " location=" .. (ok_loc and string.format("%.1f,%.1f,%.1f", loc.X, loc.Y, loc.Z) or "read failed")
        .. " scale=" .. (ok_scale and string.format("%.1f,%.1f,%.1f", scale.X, scale.Y, scale.Z) or "read failed"))
end

------------------------------------------------------------------------------
-- Active proxy
------------------------------------------------------------------------------

local active_actor = nil
local active_address = nil
local active_hitbox = nil

local function set_active(proxy, hitbox)
    active_actor = proxy
    active_hitbox = hitbox
    active_address = address_of(proxy)
end

-- True when the object is the live Mi-8 proxy. Comparing addresses keeps this
-- cheap enough for hooks that fire whenever the player looks at something.
local function is_cargo_proxy(object)
    if active_address == nil or object == nil then return false end
    if not is_valid(active_actor) then
        set_active(nil, nil)
        return false
    end
    return address_of(object) == active_address
end

------------------------------------------------------------------------------
-- Capacity
------------------------------------------------------------------------------

-- Blueprint struct members only answer to their mangled names; the clean
-- aliases silently accept writes without changing anything.
local function set_details_value(details, field, value, label)
    local ok_write = pcall(function() details[field] = value end)
    local ok_read, read_back = pcall(function() return details[field] end)
    local matches = ok_write and ok_read and tostring(read_back) == tostring(value)
    log(string.format("  %s: wrote %s, read back %s%s", label, tostring(value),
        ok_read and tostring(read_back) or "unavailable", matches and "" or " (MISMATCH)"))
    return matches
end

local function set_details_text(details, field, text, label)
    local ok_write = pcall(function() details[field] = FText(text) end)
    local ok_read, read_back = pcall(function() return details[field]:ToString() end)
    log(string.format("  %s: wrote '%s', read back '%s'", label, text, ok_read and tostring(read_back) or "unavailable"))
    return ok_write and ok_read and tostring(read_back) == text
end

local function configure_capacity(proxy)
    local ok_inventory, inventory = pcall(function() return proxy.BP_MasterInventory end)
    if not ok_inventory or not is_valid(inventory) then
        log("No valid BP_MasterInventory on the proxy; capacity unchanged.")
        return nil
    end
    local ok_details, details = pcall(function() return inventory.InventoryDetails end)
    if not ok_details or not details then
        log("Could not read InventoryDetails; capacity unchanged.")
        return inventory
    end
    log("Configuring capacity:")
    set_details_text(details, DETAILS_FIELDS.name, CONTAINER_NAME, "container name")
    set_details_value(details, DETAILS_FIELDS.cells, CONTAINER_CELLS, "cells")
    set_details_value(details, DETAILS_FIELDS.columns, CONTAINER_COLUMNS, "columns")
    set_details_value(details, DETAILS_FIELDS.can_contain, true, "can contain items")
    set_details_value(details, DETAILS_FIELDS.item_count_limit, false, "item count limit")
    set_details_value(details, DETAILS_FIELDS.weight, false, "weight limit")
    return inventory
end

-- A new world cabinet can roll its normal random loot. The hold must start
-- empty: mark random items as already spawned, clear the donor contents and
-- rebuild the 1000-cell grid. Only ever called on a freshly spawned proxy.
local function reset_fresh_inventory(inventory)
    pcall(function() inventory.HasRandomItemsSpawned = true end)
    local ok_clear, clear_err = pcall(function() inventory:ClearInventoryItems() end)
    local ok_construct, construct_err = pcall(function() inventory:ConstructSlots() end)
    local ok_count, slot_count = pcall(function() return #inventory.Inventory end)
    log(string.format("Fresh hold: cleared=%s rebuilt=%s slots=%s%s",
        tostring(ok_clear), tostring(ok_construct), ok_count and tostring(slot_count) or "?",
        (ok_clear and ok_construct) and "" or (" (" .. tostring(clear_err or construct_err) .. ")")))
end

------------------------------------------------------------------------------
-- Wreck and proxy creation
------------------------------------------------------------------------------

local function is_wreck_mesh(component)
    local ok, matched = pcall(function()
        if not is_valid(component) then return false end
        local mesh = component.StaticMesh
        if not is_valid(mesh) then return false end
        return string.lower(tostring(mesh:GetFullName())):find(WRECK_MESH_NAME, 1, true) ~= nil
    end)
    return ok and matched == true
end

-- The wreck actor, not the old coordinates, controls where the hold goes. If
-- the mesh is not loaded, fail closed rather than spawn an orphan.
-- Where the wreck stands, kept once it has been found (a position, not the
-- object, which the game may delete)
local wreck_location, wreck_address = nil, nil
local first_miss = nil   -- hosting: when a saved hold was first not found (since the last load)
-- The mesh's own place: in a generated level the wreck mesh can belong to a
-- big level actor whose own location is somewhere else entirely
local function remember_wreck(actor, component)
    wreck_address = address_of(actor)
    pcall(function()
        local l = component:K2_GetComponentLocation()
        wreck_location = { X = l.X, Y = l.Y, Z = l.Z }
    end)
    if not wreck_location then
        pcall(function()
            local l = actor:K2_GetActorLocation()
            wreck_location = { X = l.X, Y = l.Y, Z = l.Z }
        end)
    end
    return actor
end

local function find_wreck_actor()
    local ok_actors, actors = pcall(FindAllOf, "StaticMeshActor")
    local actor_count = 0
    if ok_actors and type(actors) == "table" then
        for _, raw in pairs(actors) do
            actor_count = actor_count + 1
            local actor = as_object(raw)
            local ok_component, component = pcall(function() return actor and actor.StaticMeshComponent end)
            if ok_component and is_wreck_mesh(component) then
                return remember_wreck(actor, component), component
            end
        end
    end
    -- Generated-level actors can expose the mesh component without appearing
    -- under the StaticMeshActor query; find the component and use its owner.
    local ok_components, components = pcall(FindAllOf, "StaticMeshComponent")
    local component_count = 0
    if ok_components and type(components) == "table" then
        for _, raw in pairs(components) do
            component_count = component_count + 1
            local component = as_object(raw)
            if is_wreck_mesh(component) then
                local ok_owner, owner = pcall(function() return component:GetOwner() end)
                if ok_owner and is_valid(owner) then
                    return remember_wreck(owner, component), component
                end
            end
        end
    end
    log(string.format("Mi-8 wreck not found (StaticMeshActor=%d, StaticMeshComponent=%d).", actor_count, component_count))
    local ok_player, position = pcall(function()
        return UEHelpers.GetPlayerController().Pawn:K2_GetActorLocation()
    end)
    if ok_player and position then
        local dx, dy, dz = position.X - WRECK_X, position.Y - WRECK_Y, position.Z - WRECK_Z
        log(string.format("Player is %.0f cm from the last known Mi-8 location; the wreck may be streamed out.",
            math.sqrt(dx * dx + dy * dy + dz * dz)))
    end
    return nil, nil
end

local function attach_proxy_to_wreck(proxy, wreck, wreck_component)
    local ok, result = pcall(function()
        proxy:SetOwner(wreck)
        -- SnapToTarget location and rotation, KeepWorld scale, no welding.
        return proxy:K2_AttachToComponent(wreck_component, FName("None"), 2, 2, 1, false)
    end)
    -- A successful Blueprint bool return can surface as true or nil; only an
    -- explicit false or an exception is a failure.
    return ok and result ~= false
end

local function find_storage_proxy_class()
    local ok_scan, instances = pcall(FindAllOf, WORLD_CONTAINER_CLASS)
    if ok_scan and type(instances) == "table" then
        for _, raw in pairs(instances) do
            local instance = as_object(raw)
            local ok_class, class = pcall(function() return instance and instance:GetClass() end)
            if ok_class and is_valid(class) then
                return class, "loaded world cabinet"
            end
        end
    end
    -- No cabinet streamed in yet: load the exact cabinet Blueprint. Never
    -- substitute the build-part storage class; finishing that spawn crashed.
    local ok_library, library = pcall(UEHelpers.GetKismetSystemLibrary)
    if ok_library and is_valid(library) then
        local ok_load, loaded = pcall(function() return library:LoadClassAsset_Blocking(WORLD_CONTAINER_CLASS_PATH) end)
        if ok_load and is_valid(loaded) then
            return loaded, "world cabinet asset"
        end
        log("World cabinet asset could not be loaded: " .. tostring(loaded))
    end
    return nil, nil
end

-- The donor cabinet must contribute no collision at all. Its dedicated child
-- box is created afterward and is the sole query-only interaction surface.
-- This prevents the invisible scaled cabinet (including BuildCollision) from
-- becoming an invisible platform above the Mi-8.
local function prepare_cabinet_components(proxy)
    local hidden, disabled_collision, total = 0, 0, 0
    local ok_list, components = pcall(function()
        return proxy:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))
    end)
    if ok_list and type(components) == "table" then
        for _, raw in pairs(components) do
            local component = as_object(raw)
            if component then
                total = total + 1
                if pcall(function() component:SetVisibility(false, false) end) then
                    hidden = hidden + 1
                end
                local ok_collision = pcall(function()
                    component:SetCollisionEnabled(0) -- NoCollision
                end)
                if ok_collision then
                    disabled_collision = disabled_collision + 1
                end
            end
        end
    end
    return hidden, disabled_collision, total
end

-- Query-only box around the fuselage that the player's interaction trace can
-- hit. It ignores every channel except Visibility and the game's interaction
-- trace channel, so it never blocks movement.
local function create_interaction_hitbox(proxy, math_lib)
    local ok_class, box_class = pcall(StaticFindObject, "/Script/Engine.BoxComponent")
    if not ok_class or not is_valid(box_class) then
        return nil, "BoxComponent class was unavailable"
    end
    local ok_add, box = pcall(function()
        local relative = math_lib:MakeTransform(math_lib:MakeVector(0.0, 0.0, 0.0),
            math_lib:MakeRotator(0.0, 0.0, 0.0), math_lib:MakeVector(1.0, 1.0, 1.0))
        return proxy:AddComponentByClass(box_class, false, relative, false)
    end)
    if not ok_add or not is_valid(box) then
        return nil, "AddComponentByClass failed: " .. tostring(box)
    end
    local ok_configure, configure_err = pcall(function()
        -- Extents are local; the proxy's scale is applied on top.
        box:SetBoxExtent(math_lib:MakeVector(BOX_X / CHOPPER_SCALE_X, BOX_Y / CHOPPER_SCALE_Y, BOX_Z / CHOPPER_SCALE_Z), true)
        box:SetGenerateOverlapEvents(false)
        box:SetCollisionEnabled(1) -- QueryOnly
        box:SetCollisionResponseToAllChannels(ECR_IGNORE)
        box:SetCollisionResponseToChannel(ECC_VISIBILITY, ECR_BLOCK)
        -- The player's InteractionTraceChannel is TraceTypeQuery3, the first
        -- game trace channel.
        box:SetCollisionResponseToChannel(ECC_GAME_TRACE_1, ECR_BLOCK)
    end)
    if not ok_configure then
        pcall(function() box:DestroyComponent() end)
        return nil, "interaction box setup failed: " .. tostring(configure_err)
    end
    return box, nil
end

-- A BP_CabinetWorld_C is a normal SGK build-part class. The game therefore
-- reconstructs it as a real world actor when it sees one in the normal save.
-- On that load UE does not preserve our runtime-only component visibility or
-- its attachment consistently. Recognise only our unusually scaled cabinet,
-- then reclaim it before the player can interact with it as furniture.
local function is_cargo_scale(candidate)
    local ok, scale = pcall(function() return candidate:GetActorScale3D() end)
    if not ok or not scale then return false end
    return math.abs(scale.X - CHOPPER_SCALE_X) < 0.05
        and math.abs(scale.Y - CHOPPER_SCALE_Y) < 0.05
        and math.abs(scale.Z - CHOPPER_SCALE_Z) < 0.05
end

local function is_near_wreck(candidate, wreck)
    local ok, candidate_location, wreck_location = pcall(function()
        return candidate:K2_GetActorLocation(), wreck:K2_GetActorLocation()
    end)
    if not ok or not candidate_location or not wreck_location then return false end
    local x, y, z = candidate_location.X - wreck_location.X,
        candidate_location.Y - wreck_location.Y, candidate_location.Z - wreck_location.Z
    -- The huge cabinet in a legacy save can be offset above the rotor; this
    -- radius is deliberately far smaller than the distance to normal furniture.
    return x*x + y*y + z*z < 2500 * 2500
end

local function find_saved_proxy(wreck)
    local ok_scan, instances = pcall(FindAllOf, WORLD_CONTAINER_CLASS)
    if not ok_scan or type(instances) ~= "table" then return nil end
    local scaled_candidate = nil
    for _, raw in pairs(instances) do
        local candidate = as_object(raw)
        local ok_parent, parent = pcall(function() return candidate and candidate:GetAttachParentActor() end)
        if ok_parent and same_object(parent, wreck) then
            return candidate
        end
        -- A loaded save can lose its attachment. Never claim an ordinary
        -- cabinet: require both our distinctive scale and wreck proximity.
        if candidate and is_cargo_scale(candidate) and is_near_wreck(candidate, wreck) then
            scaled_candidate = candidate
        end
    end
    return scaled_candidate
end

-- Reapply every runtime-only property after SGK reconstructs the saved actor.
-- This deliberately does not clear or rebuild its inventory: the cargo sidecar
-- is loaded immediately afterward and is the authoritative item state.
local function reclaim_saved_proxy(proxy, wreck, wreck_component)
    local ok_math, math_lib = pcall(UEHelpers.GetKismetMathLibrary)
    if not ok_math or not is_valid(math_lib) then return nil end
    if not attach_proxy_to_wreck(proxy, wreck, wreck_component) then
        log("Saved Cargo Hold could not reattach to the Mi-8; leaving it disabled.")
        pcall(function() proxy:SetActorEnableCollision(false) end)
        return nil
    end
    pcall(function()
        proxy:SetActorScale3D(math_lib:MakeVector(CHOPPER_SCALE_X, CHOPPER_SCALE_Y, CHOPPER_SCALE_Z))
        proxy:SetActorHiddenInGame(false)
    end)
    local hidden, disabled_collision, total = prepare_cabinet_components(proxy)
    if hidden == 0 then
        log("Saved Cargo Hold visuals could not be hidden; leaving it disabled.")
        pcall(function() proxy:SetActorEnableCollision(false) end)
        return nil
    end
    local hitbox, hitbox_error = create_interaction_hitbox(proxy, math_lib)
    local inventory = configure_capacity(proxy)
    if inventory then
        pcall(function() inventory.UseDestructionBag = false end)
        pcall(function() inventory.ShouldSpawnBag = false end)
    end
    pcall(function() proxy.AllowDamage = false end)
    pcall(function() proxy:SetActorEnableCollision(true) end)
    set_active(proxy, hitbox)
    log(string.format("Reclaimed saved Cargo Hold: hidden=%d/%d collision-disabled=%d/%d interaction box=%s.",
        hidden, total, disabled_collision, total,
        hitbox and string.format("%.0fx%.0fx%.0f cm", BOX_X, BOX_Y, BOX_Z) or ("unavailable: " .. tostring(hitbox_error))))
    return proxy
end

local function spawn_cargo_hold(wreck, wreck_component)
    local ok_world, world = pcall(UEHelpers.GetWorld)
    local ok_math, math_lib = pcall(UEHelpers.GetKismetMathLibrary)
    local ok_statics, statics = pcall(UEHelpers.GetGameplayStatics)
    if not (ok_world and is_valid(world) and ok_math and is_valid(math_lib) and ok_statics and is_valid(statics)) then
        log("World or engine libraries unavailable; no Cargo Hold created.")
        return nil
    end
    local storage_class, class_source = find_storage_proxy_class()
    if not storage_class then
        log("No " .. WORLD_CONTAINER_CLASS .. " class is available; no Cargo Hold created.")
        return nil
    end
    local ok_transform, transform = pcall(function()
        return math_lib:MakeTransform(wreck:K2_GetActorLocation(), wreck:K2_GetActorRotation(),
            math_lib:MakeVector(1.0, 1.0, 1.0))
    end)
    if not ok_transform or not transform then
        log("Could not read the Mi-8 transform; no Cargo Hold created.")
        return nil
    end

    -- Deferred spawn owned by the wreck; AlwaysSpawn so the wreck's own
    -- collision cannot reject it.
    local ok_begin, proxy = pcall(function()
        return statics:BeginDeferredActorSpawnFromClass(world, storage_class, transform, 1, wreck, 0)
    end)
    if not ok_begin or not is_valid(proxy) then
        log("BeginDeferredActorSpawnFromClass failed: " .. tostring(proxy))
        return nil
    end
    local ok_finish, finished = pcall(function() return statics:FinishSpawningActor(proxy, transform, 0) end)
    if not ok_finish or not is_valid(finished) then
        log("FinishSpawningActor failed: " .. tostring(finished))
        pcall(function() proxy:K2_DestroyActor() end)
        return nil
    end
    proxy = finished
    -- Attachment is the gate: never leave an unattached cabinet in the world.
    if not attach_proxy_to_wreck(proxy, wreck, wreck_component) then
        log("The Cargo Hold could not attach to the Mi-8 and was removed.")
        pcall(function() proxy:K2_DestroyActor() end)
        return nil
    end

    local scaled = pcall(function()
        proxy:SetActorScale3D(math_lib:MakeVector(CHOPPER_SCALE_X, CHOPPER_SCALE_Y, CHOPPER_SCALE_Z))
    end)
    -- The actor itself stays "visible" so interaction code does not skip it;
    -- only its components are hidden.
    pcall(function() proxy:SetActorHiddenInGame(false) end)
    local hidden, disabled_collision, total = prepare_cabinet_components(proxy)
    if hidden == 0 then
        log("Could not hide the cabinet's visuals; the Cargo Hold was removed.")
        pcall(function() proxy:K2_DestroyActor() end)
        return nil
    end
    pcall(function() proxy:SetActorEnableCollision(true) end)
    local hitbox, hitbox_error = create_interaction_hitbox(proxy, math_lib)
    local inventory = configure_capacity(proxy)
    if inventory then
        pcall(function() inventory.UseDestructionBag = false end)
        pcall(function() inventory.ShouldSpawnBag = false end)
        reset_fresh_inventory(inventory)
    end
    pcall(function() proxy.AllowDamage = false end)

    set_active(proxy, hitbox)
    log(string.format("Cargo Hold ready (%s): scaled=%s hidden=%d/%d collision-disabled=%d/%d interaction box=%s.",
        class_source, tostring(scaled), hidden, total, disabled_collision, total,
        hitbox and string.format("%.0fx%.0fx%.0f cm", BOX_X, BOX_Y, BOX_Z) or ("unavailable: " .. tostring(hitbox_error))))
    log_transform(proxy, "Cargo Hold transform:")
    return proxy
end

-- Returns the proxy, the wreck's mesh component, and whether it was just created.
local function ensure_cargo_hold()
    local wreck, wreck_component = find_wreck_actor()
    if not wreck then return nil end
    if is_valid(active_actor) then
        local ok_parent, parent = pcall(function() return active_actor:GetAttachParentActor() end)
        if ok_parent and same_object(parent, wreck) then
            return active_actor, wreck_component, false
        end
    end
    set_active(nil, nil)
    -- After a Lua mod reload the hold still exists but this script forgot it.
    local existing = find_saved_proxy(wreck)
    if existing then
        local reclaimed = reclaim_saved_proxy(existing, wreck, wreck_component)
        if reclaimed then
            log("Reclaimed the saved Cargo Hold and hid its cabinet mesh.")
            return reclaimed, wreck_component, false
        end
        return nil
    end
    -- No saved hold yet. After a load or a return from an expedition the game
    -- may still be restoring it from the save: a fresh one made now left the
    -- restored one standing beside it, a giant cabinet (1.1.3). Make one only
    -- once none has shown up for 10 s.
    local now = os.time()
    if not first_miss then first_miss = now end
    if now - first_miss < 10 then return nil end
    local proxy = spawn_cargo_hold(wreck, wreck_component)
    return proxy, wreck_component, proxy ~= nil
end

-- Hosting: other cargo-sized cabinets at the wreck besides the live hold are
-- extra copies (a saved one the game restored after a fresh hold was made).
-- They're removed without a loot bag: the cargo file is what holds the items,
-- the hold's own is loaded from it.
local function remove_duplicate_holds()
    if not is_valid(active_actor) then return 0 end
    local wreck_at = wreck_location
    local ok_scan, instances = pcall(FindAllOf, WORLD_CONTAINER_CLASS)
    if not ok_scan or type(instances) ~= "table" then return 0 end
    local removed = 0
    for _, raw in pairs(instances) do
        local candidate = as_object(raw)
        if candidate and is_valid(candidate) and address_of(candidate) ~= active_address then
            local ok_parent, parent = pcall(function() return candidate:GetAttachParentActor() end)
            local attached = ok_parent and wreck_address ~= nil and address_of(parent) == wreck_address
            local near = false
            if wreck_at and is_cargo_scale(candidate) then
                local ok, l = pcall(function() return candidate:K2_GetActorLocation() end)
                if ok and l then
                    local x, y, z = l.X - wreck_at.X, l.Y - wreck_at.Y, l.Z - wreck_at.Z
                    near = x * x + y * y + z * z < 2500 * 2500
                end
            end
            if attached or near then
                pcall(function() candidate.BP_MasterInventory.UseDestructionBag = false end)
                pcall(function() candidate.BP_MasterInventory.ShouldSpawnBag = false end)
                if pcall(function() candidate:K2_DestroyActor() end) then removed = removed + 1 end
            end
        end
    end
    if removed > 0 then
        log(string.format("Removed %d extra copy(ies) of the Cargo Hold at the Mi-8 (a saved one restored beside the live one).", removed))
    end
    return removed
end

------------------------------------------------------------------------------
-- Container window
------------------------------------------------------------------------------

local styled_window_address = nil
local function style_cargo_window()
    if not is_valid(active_actor) then return end
    local ok_inventory, target = pcall(function() return active_actor.BP_MasterInventory end)
    local target_address = ok_inventory and address_of(target) or nil
    if not target_address then return end
    local ok_windows, windows = pcall(FindAllOf, "BP_ContainerWindow_C")
    if not ok_windows or type(windows) ~= "table" then return end
    for _, raw in pairs(windows) do
        local window = as_object(raw)
        local ok_owner, window_inventory = pcall(function() return window and window.InventoryComponent end)
        local window_address = address_of(window)
        if ok_owner and address_of(window_inventory) == target_address and window_address ~= styled_window_address then
            local ok_style, style_err = pcall(function()
                local title = window.InventoryName
                if is_valid(title) then title:SetText(FText(CONTAINER_NAME)) end
                -- Keep the native grid; only make its scroll box clip to the
                -- frame so the 6-column / 1000-cell grid scrolls vertically.
                local scroll = window.InvGridScrollBox
                if is_valid(scroll) then
                    scroll:SetClipping(1) -- ClipToBounds
                    scroll:SetAllowOverscroll(false)
                    scroll:SetConsumeMouseWheel(1)
                    scroll:SetAnimateWheelScrolling(true)
                    scroll:SetWheelScrollMultiplier(1.0)
                    scroll:SetAlwaysShowScrollbar(true)
                    scroll:SetScrollbarVisibility(0) -- Visible
                end
                local slot = window.ParentSlot
                if is_valid(slot) then
                    slot:SetAutoSize(false)
                    slot:SetSize(UEHelpers.GetKismetMathLibrary():MakeVector2D(680, 620))
                end
            end)
            if ok_style then
                styled_window_address = window_address
                log_once("window-styled", "Cargo Hold window uses a clipped 6-column scroll view.")
            else
                log("Cargo Hold window styling unavailable: " .. tostring(style_err))
            end
            return
        end
    end
end

------------------------------------------------------------------------------
-- Interaction menu: title "Mi-8 Cargo Hold", a single "Enter" action
------------------------------------------------------------------------------

local function widget_text(widget, field)
    local ok, text = pcall(function()
        local block = widget[field]
        if not is_valid(block) then return nil end
        return block:GetText():ToString()
    end)
    if ok and text ~= nil then return tostring(text) end
    return nil
end

local function describe_entry(entry, position)
    local info = {entry = entry, address = address_of(entry), position = position, action_name = "", texts = {}}
    pcall(function() info.action_name = tostring(entry.Action[ACTION_NAME_FIELD]:ToString()) end)
    pcall(function() info.action_type = tonumber(entry.Action[ACTION_TYPE_FIELD]) end)
    pcall(function() info.index = tonumber(entry.Index) end)
    info.texts.TextBlock = widget_text(entry, "TextBlock")
    info.texts.TextBlock_86 = widget_text(entry, "TextBlock_86")
    local haystack = string.lower(table.concat({info.action_name, info.texts.TextBlock or "", info.texts.TextBlock_86 or ""}, " "))
    info.is_pickup = haystack:find("pick", 1, true) ~= nil
    info.is_open = not info.is_pickup
        and (haystack:find("open", 1, true) ~= nil or haystack:find(string.lower(ENTER_LABEL), 1, true) ~= nil)
    info.has_text = (haystack:gsub("%s", "")) ~= ""
    return info
end

local function context_menu_entries(menu)
    local entries = {}
    local ok_box, box = pcall(function() return menu.ContextVerticalBox end)
    if not ok_box or not is_valid(box) then return entries end
    local ok_count, count = pcall(function() return box:GetChildrenCount() end)
    if not ok_count or type(count) ~= "number" then return entries end
    for child_index = 0, count - 1 do
        local ok_child, child = pcall(function() return box:GetChildAt(child_index) end)
        if ok_child and is_valid(child) then
            entries[#entries + 1] = describe_entry(child, child_index)
        end
    end
    return entries
end

-- The kept entry's action text becomes "Enter"; any "Cabinet" wording on it
-- becomes the hold's name.
local function relabel_entry(info)
    local wanted = string.lower(info.action_name or "")
    for _, field in ipairs({"TextBlock", "TextBlock_86"}) do
        local text = info.texts[field]
        if text and text ~= "" then
            local lowered = string.lower(text)
            local replacement = nil
            if (wanted ~= "" and lowered:find(wanted, 1, true)) or lowered:find("open", 1, true) then
                replacement = ENTER_LABEL
            elseif lowered:find("cabinet", 1, true) then
                replacement = CONTAINER_NAME
            end
            if replacement and text ~= replacement then
                pcall(function() info.entry[field]:SetText(FText(replacement)) end)
            end
        end
    end
end

-- Entries we collapsed, with their prior visibility, so a widget the game
-- reuses for another object can be given back its normal state.
local collapsed_entries = {}
local keep_entry_address = nil

local function collapse_entry(info)
    if not info.address then return false end
    if not collapsed_entries[info.address] then
        local ok_visibility, visibility = pcall(function() return info.entry:GetVisibility() end)
        collapsed_entries[info.address] = {entry = info.entry, visibility = ok_visibility and tonumber(visibility) or 0}
    end
    return pcall(function() info.entry:SetVisibility(SLATE_COLLAPSED) end)
end

local function uncollapse_entry(address)
    local saved = collapsed_entries[address]
    collapsed_entries[address] = nil
    if saved and is_valid(saved.entry) then
        pcall(function() saved.entry:SetVisibility(saved.visibility) end)
    end
end

local function restore_reused_entries()
    for address, saved in pairs(collapsed_entries) do
        if not is_valid(saved.entry) then
            collapsed_entries[address] = nil
        else
            local ok_actor, actor = pcall(function() return saved.entry.Actor end)
            if ok_actor and not is_cargo_proxy(actor) then
                uncollapse_entry(address)
            end
        end
    end
end

local function menu_targets_cargo(menu, look_at_actor)
    if is_cargo_proxy(look_at_actor) then return true end
    for _, field in ipairs({"LastLookAtActor", "LastActor"}) do
        local ok, actor = pcall(function() return menu[field] end)
        if ok and is_cargo_proxy(actor) then return true end
    end
    return false
end

-- Keep only the open action, relabel it "Enter", and pin the selection to it
-- so the mouse wheel cannot move onto the hidden "Pick up" entry.
local function apply_cargo_menu(menu)
    local entries = context_menu_entries(menu)
    if #entries == 0 then return end
    local keep = nil
    for _, info in ipairs(entries) do
        if info.is_open then keep = info; break end
    end
    if not keep then
        for _, info in ipairs(entries) do
            if not info.is_pickup and info.has_text then keep = info; break end
        end
    end
    local collapsed = 0
    for _, info in ipairs(entries) do
        if info ~= keep and collapse_entry(info) then
            collapsed = collapsed + 1
        end
    end
    keep_entry_address = keep and keep.address or nil
    if keep then
        if collapsed_entries[keep.address] then
            uncollapse_entry(keep.address)
        end
        relabel_entry(keep)
        pcall(function() menu.SelectedEntryIndex = keep.index or keep.position end)
        for _, info in ipairs(entries) do
            pcall(function() info.entry:EntrySelected(info == keep) end)
        end
    end
    log_once("menu-applied", string.format("Mi-8 menu: kept '%s' as '%s', collapsed %d of %d entries.",
        keep and (keep.action_name ~= "" and keep.action_name or tostring(keep.texts.TextBlock)) or "none",
        ENTER_LABEL, collapsed, #entries))
end

local hooks_registered = false
local retained_hooks = {}
local prompt_stats = {init = 0, hud = 0, writes = 0, failures = 0}

-- Correct the text synchronously after the native Blueprint update. Delaying
-- this write lets the native Cabinet text reach a rendered frame (flicker).
-- Resolve LastActor afresh: HUD widgets are reused for ordinary containers.
local function refresh_cargo_prompt_title(widget, target, source)
    if not is_valid(widget) then return end
    if target == nil then
        local ok_target, current_target = pcall(function() return widget.LastActor end)
        if not ok_target then return end
        target = as_object(current_target)
    end
    if not is_cargo_proxy(target) then return end
    local ok_block, block = pcall(function() return widget.TextBlock_86 end)
    if not ok_block or not is_valid(block) then return end
    local ok_current, current = pcall(function() return block:GetText():ToString() end)
    if ok_current and tostring(current) == CONTAINER_NAME then return end
    local ok_set = pcall(function() block:SetText(FText(CONTAINER_NAME)) end)
    if not ok_set then prompt_stats.failures = prompt_stats.failures + 1; return end
    prompt_stats.writes = prompt_stats.writes + 1
    local ok_read, shown = pcall(function() return block:GetText():ToString() end)
    if ok_read and tostring(shown) == CONTAINER_NAME then
        log_once("title-" .. source, "Prompt title read-back verified after " .. source .. ": " .. CONTAINER_NAME)
    else
        prompt_stats.failures = prompt_stats.failures + 1
    end
end

local function hook(path, callback, label)
    retained_hooks[#retained_hooks + 1] = callback
    local ok, err = pcall(RegisterHook, path, callback)
    if ok then
        log("Hooked " .. label .. ".")
    else
        log(label .. " hook unavailable: " .. tostring(err))
    end
    return ok
end

local function register_interaction_hooks()
    if hooks_registered then return end
    hooks_registered = true

    hook(ITEM_NAME_INIT, function(self, look_at_actor)
        if active_address == nil then return end
        prompt_stats.init = prompt_stats.init + 1
        local widget = as_object(self)
        local target = as_object(look_at_actor)
        if not widget or not is_cargo_proxy(target) then return end
        refresh_cargo_prompt_title(widget, target, "InitializeName")
    end, "synchronous Cargo Hold title after InitializeName")

    -- The parent HUD exposes another text update in the game dump. Correct
    -- its child before returning to the caller, without timers or world scans.
    hook(HUD_UPDATE_TEXT, function(self)
        if active_address == nil then return end
        prompt_stats.hud = prompt_stats.hud + 1
        local hud = as_object(self)
        if not hud then return end
        local ok_widget, widget = pcall(function() return hud.BP_ItemName end)
        if ok_widget then refresh_cargo_prompt_title(as_object(widget), nil, "HUD.GetText") end
    end, "synchronous Cargo Hold title after HUD.GetText")

    hook(CONTAINER_WINDOW_CREATE, function()
        if active_address ~= nil then defer(250, style_cargo_window) end
    end, "container window layout for the Mi-8 Cargo Hold")

    if ENABLE_ENTER_MENU then
        local function on_menu_changed(self, look_at_actor)
            local menu = as_object(self)
            if not menu then return end
            if next(collapsed_entries) ~= nil then
                restore_reused_entries()
            end
            if active_address ~= nil and menu_targets_cargo(menu, as_object(look_at_actor)) then
                apply_cargo_menu(menu)
            end
        end
        for _, function_name in ipairs({"InitializeContextMenu", "PopulateMenu", "UpEntrySelect", "DownEntrySelect", "ResetEntrySelect"}) do
            hook(MENU_CLASS .. ":" .. function_name, on_menu_changed, "interaction menu " .. function_name)
        end
        -- Entries refresh their text on a timer; keep "Enter" and the hidden
        -- entries in place when that happens.
        hook(ENTRY_UPDATE_TEXT, function(self)
            if active_address == nil or keep_entry_address == nil then return end
            local entry = as_object(self)
            local ok_actor, actor = pcall(function() return entry and entry.Actor end)
            if not ok_actor or not is_cargo_proxy(actor) then return end
            local info = describe_entry(entry, 0)
            if info.address == keep_entry_address then
                relabel_entry(info)
            else
                collapse_entry(info)
            end
        end, "interaction entry text refresh")
    end

    if ENABLE_PICKUP_GUARD then
        -- Runs after CanPickup, so the caller reads this value: the hold can
        -- never be picked up and destroyed. Only a plain bool is written.
        hook(STORAGE_CAN_PICKUP, function(self, _target, allow)
            if active_address == nil or not is_cargo_proxy(as_object(self)) then return end
            if pcall(function() allow:set(false) end) then
                log_once("pickup-guard", "Blocked a pickup of the Mi-8 Cargo Hold.")
            end
        end, "pickup guard for the Mi-8 Cargo Hold")
    end
end

local lifecycle_ensure
------------------------------------------------------------------------------
-- Host lifecycle and cargo saves. Idle ticks use cached objects/scalar reads.
------------------------------------------------------------------------------
local session = {controller=nil, system=nil, key=nil, stable=0, next_scan=0,
    delay=2, component=nil, lost=false, paused=false, save_hooks=false}
local function read(object, field)
    local ok, value = pcall(function() return object[field] end)
    if ok then return value end
    return nil
end
local function value(param)
    local ok, result = pcall(function() return param:get() end)
    if ok then return result end
    return param
end
local function text_value(param)
    param = value(param)
    if type(param) == "string" then return param end
    local ok, result = pcall(function() return param:ToString() end)
    return ok and tostring(result) or ""
end
local function statics() return UEHelpers.GetGameplayStatics() end
local persistence = CargoPersistence.new({
    log=log, valid=is_valid,
    exists=function(name) return statics():DoesSaveGameExist(name, 0) == true end,
    load=function(name) return statics():LoadGameFromSlot(name, 0) end,
    save=function(snapshot, name) return statics():SaveGameToSlot(snapshot, name, 0) end,
    capture=function()
        assert(is_valid(active_actor), "cargo actor is unavailable")
        local inventory = active_actor.BP_MasterInventory
        local template = session.system.SaveGameData
        if not is_valid(template) then template = session.system.LoadedSaveGameData end
        assert(is_valid(template), "native save class is unavailable")
        local snapshot = statics():CreateSaveGameObject(template:GetClass())
        assert(is_valid(snapshot), "native snapshot allocation failed")
        inventory:SaveComponentData(snapshot)
        local record = CargoPersistence.record(snapshot)
        assert(tonumber(record.ItemCount_8_A7235E3648E8A13D8EACAE98FDA7439A)
            == tonumber(inventory.ItemCount), "native snapshot item count differs from cargo")
        return snapshot
    end,
    restore=function(record)
        local inventory = active_actor.BP_MasterInventory
        inventory:LoadInventoryData(record)
        assert(tonumber(inventory.ItemCount)
            == tonumber(record.ItemCount_8_A7235E3648E8A13D8EACAE98FDA7439A),
            "restored item count differs from cargo save")
    end,
})

local function cargo_save_target(object, slot)
    if persistence.busy or not persistence.ready or session.paused then return false end
    if not is_valid(session.system) or read(session.system, "Loading") ~= false then return false end
    if not same_object(as_object(object), read(session.system, "SaveGameData")) then return false end
    local native_name = text_value(slot)
    if native_name == "" or native_name:sub(1,15) == "ChopperCargo_v1_" then return false end
    -- SGK may add a level/path suffix to its physical save filename. Scope
    -- cargo by its logical destination slot, the same field used on reload.
    local name = text_value(read(session.system, "SavingSlot"))
    if name == "" then name = session.slot end
    return persistence:prepare(name, session.level)
end

-- Names of the save system's Completed_<GUID> events (Blueprint async-node
-- completions). Names only: walking property lists can crash this UE4SS build.
local function find_save_completions(system_class)
    local names = {}
    pcall(function()
        system_class:ForEachFunction(function(fn)
            local name = ""
            pcall(function() name = fn:GetFName():ToString() end)
            if name:find("^Completed_%x+$") then names[#names + 1] = name end
        end)
    end)
    return names
end

local function install_save_hooks()
    if session.save_hooks then return end
    session.save_hooks = true
    -- Native hook post callbacks receive the original return value second.
    -- Private snapshot writes are excluded by persistence.busy and object ID.
    local pre = function(_, object, slot)
        if not persistence.busy then cargo_save_target(object, slot) end
    end
    local post = function(_, success, object)
        if not persistence.busy and same_object(as_object(object), read(session.system, "SaveGameData")) then
            persistence:complete(value(success) == true)
        end
    end
    retained_hooks[#retained_hooks+1] = pre
    retained_hooks[#retained_hooks+1] = post
    local ok, err = pcall(RegisterHook, "/Script/Engine.GameplayStatics:SaveGameToSlot", pre, post)
    if not ok then log("Cargo synchronous save hook unavailable: " .. tostring(err)) end
    session.sync_hook = ok
    local async_pre = function(_, _world, object, slot)
        if not persistence.busy then cargo_save_target(object, slot) end
    end
    retained_hooks[#retained_hooks+1] = async_pre
    local async_ok = pcall(RegisterHook, "/Script/Engine.AsyncActionHandleSaveGame:AsyncSaveGameToSlot", async_pre)
    local class_path = session.system:GetClass():GetFullName():match("^%S+ (.+)$")
    assert(class_path, "native save-system class path unavailable")
    local on_completed = function(self, object, success)
        if same_object(as_object(self), session.system)
            and same_object(as_object(object), read(session.system, "SaveGameData")) then
            persistence:complete(value(success) == true)
        end
    end
    -- The completion event is generated by the Blueprint compiler and named
    -- Completed_<GUID>; the GUID can change whenever the game rebuilds
    -- BP_SaveSystem, and a missing hook pauses the whole mod. Use the 1.0.1
    -- name while it exists; otherwise hook every Completed_<GUID> event. That
    -- is safe because on_completed only acts on this save system's own
    -- SaveGameData while a cargo save is pending.
    local completion_ok = hook(class_path .. ":Completed_A03379DA470360706C4BD1BF93C92FA9", on_completed,
        "Cargo native async-save completion")
    if not completion_ok then
        for _, name in ipairs(find_save_completions(session.system:GetClass())) do
            if hook(class_path .. ":" .. name, on_completed, "Cargo native async-save completion " .. name) then
                completion_ok = true
            end
        end
    end
    session.async_hook = async_ok and completion_ok
    session.load_hook = hook(class_path .. ":LoadSave", function(self)
        if same_object(as_object(self), session.system) then
            session.load_transition = true
            session.paused = true
        end
    end, "Cargo save-slot load boundary")
end

local function suspend_cargo()
    if is_valid(active_actor) then pcall(function() active_actor:SetActorEnableCollision(false) end) end
end

local CLIENT = {}   -- current_session's marker for "someone else's world"

local function current_session(now)
    if not is_valid(session.controller) then
        if now < (session.controller_retry or 0) then return nil end
        session.controller_retry = now + 5
        local ok, controller = pcall(UEHelpers.GetPlayerController)
        session.controller = ok and controller or nil
    end
    local pawn = read(session.controller, "Pawn")
    if not is_valid(pawn) then
        if now >= (session.controller_retry or 0) then session.controller = nil end
        return nil
    end
    local ok_host, host = pcall(function() return pawn:HasAuthority() end)
    if not ok_host or host ~= true then
        return nil, CLIENT
    end
    if not is_valid(session.system) then
        if now < (session.system_retry or 0) then return nil end
        session.system_retry = now + 5
        local ok, system = pcall(FindFirstOf, "BP_SaveSystem_C")
        session.system = ok and system or nil
        if not is_valid(session.system) then
            session.system_misses = (session.system_misses or 0) + 1
            if session.system_misses == 6 then
                log("BP_SaveSystem_C still not found after 30s in a world; a game update may have renamed it.")
            end
        end
    end
    if is_valid(session.system) and read(session.system, "Loading") == true then
        session.load_transition = true
    end
    if not is_valid(session.system) or read(session.system, "Loading") ~= false
        or read(session.system, "FirstLoadDone") ~= true then return nil end
    local slot, level = text_value(read(session.system, "SlotName")), text_value(read(session.system, "SaveLevel"))
    if slot == "" or level == "" then
        log_once("no-slot", "The game reports no save slot for this world yet (slot='" .. slot .. "', level='"
            .. level .. "'); the Cargo Hold waits until it does, because cargo is saved per slot.")
        return nil
    end
    local key = tostring(address_of(session.system)) .. "|" .. slot .. "|" .. level
    return key, slot, level
end

------------------------------------------------------------------------------
-- Joining someone else's world
------------------------------------------------------------------------------
-- The host's mod creates and saves the hold; it reaches this player as an
-- ordinary replicated cabinet, still showing as a giant cabinet over the
-- wreck. Here it is only made to look and open like the hold on this screen:
-- hidden mesh, walk-through, the same interaction box, name and grid. Items
-- live on the host, so nothing is created, cleared or saved here.
local client = { next_scan = 0, delay = 5 }

-- The host's hold reaches this game only while this player is near it (the
-- game sends far-away objects to nobody). So once the wreck's place is known,
-- there's no looking while far from it, and near it only the world cabinets
-- are looked through, not every mesh in the world: in a dense area that full
-- search (find_wreck_actor) every minute was a noticeable hitch.
local CLIENT_SEARCH_RADIUS = 20000   -- cm; the game sends objects up to about 150 m
local function distance_to(location)
    local ok, position = pcall(function() return read(session.controller, "Pawn"):K2_GetActorLocation() end)
    if not ok or not position then return nil end
    local x, y, z = position.X - location.X, position.Y - location.Y, position.Z - location.Z
    return math.sqrt(x * x + y * y + z * z)
end

local function find_proxy_near(location)
    local ok_scan, instances = pcall(FindAllOf, WORLD_CONTAINER_CLASS)
    if not ok_scan or type(instances) ~= "table" then return nil end
    for _, raw in pairs(instances) do
        local candidate = as_object(raw)
        -- attached to the wreck: it's the hold
        local ok_parent, parent = pcall(function() return candidate and candidate:GetAttachParentActor() end)
        if ok_parent and wreck_address and address_of(parent) == wreck_address then return candidate end
        if candidate and is_cargo_scale(candidate) then
            local ok, l = pcall(function() return candidate:K2_GetActorLocation() end)
            if ok and l then
                local x, y, z = l.X - location.X, l.Y - location.Y, l.Z - location.Z
                if x * x + y * y + z * z < 2500 * 2500 then return candidate end
            end
        end
    end
    return nil
end

-- A world cabinet was just made in this game (the host's hold arrives as a
-- cabinet when the player walks near): look for the hold 2 s later, once its
-- place and size have arrived too
pcall(NotifyOnNewObject, WORLD_CONTAINER_CLASS_PATH, function()
    client.next_scan = math.min(client.next_scan, os.time() + 2)
    client.delay = 5
    session.dedupe_at = os.time() + 3   -- hosting: a late-restored copy of the hold?
end)

local function client_ensure(now, manual)
    if is_valid(active_actor) then return active_actor end
    if active_address then
        -- the host reloaded or left: look again soon
        set_active(nil, nil)
        client.next_scan, client.delay = now + 2, 5
    end
    if now < client.next_scan and not manual then return nil end
    local proxy = nil
    if wreck_location then
        local distance = distance_to(wreck_location)
        if distance and distance > CLIENT_SEARCH_RADIUS and not manual then
            client.next_scan, client.delay = now + 5, 5   -- far away: only the distance, every 5 s
            return nil
        end
        -- near the wreck: looked for less and less often (each look still walks
        -- every object), up to every 30 s; a cabinet appearing in this game
        -- (the host's hold arriving as the player walks near) brings the next
        -- look forward to 2 s later (see the NotifyOnNewObject below)
        client.next_scan = now + client.delay
        client.delay = math.min(30, client.delay * 2)
        proxy = find_proxy_near(wreck_location)
    else
        client.next_scan = now + client.delay
        client.delay = math.min(60, client.delay * 2)
        local wreck = find_wreck_actor()
        if not wreck then return nil end
        proxy = find_saved_proxy(wreck)
    end
    if not proxy then
        log_once("client-waiting", "In someone else's world: no Cargo Hold from the host yet. "
            .. "The host needs Mi8CargoHold installed too; still looking.")
        return nil
    end
    local ok_math, math_lib = pcall(UEHelpers.GetKismetMathLibrary)
    if not ok_math or not is_valid(math_lib) then return nil end
    local hidden, _, total = prepare_cabinet_components(proxy)
    local hitbox, hitbox_error = create_interaction_hitbox(proxy, math_lib)
    configure_capacity(proxy)
    pcall(function() proxy:SetActorEnableCollision(true) end)
    set_active(proxy, hitbox)
    register_interaction_hooks()
    client.delay = 5
    log(string.format("Joined the host's Cargo Hold: hidden=%d/%d interaction box=%s. Use Enter at the Mi-8; "
        .. "the host's game saves the cargo.", hidden, total,
        hitbox and "ok" or ("unavailable: " .. tostring(hitbox_error))))
    return proxy
end

lifecycle_ensure = function(manual)
    local now = os.time()
    local key, slot, level = current_session(now)
    if slot == CLIENT then return client_ensure(now, manual) end
    if not key then
        session.stable = 0
        session.paused = true
        suspend_cargo()
        if manual then log("Cargo waiting for a loaded host save (Loading=false, FirstLoadDone=true).") end
        return nil
    end
    local was_paused = session.paused
    if key ~= session.key or session.load_transition then
        -- A loaded save, including reloading the same slot, resets the cargo
        -- to that save's snapshot. Unsaved session contents must not carry over.
        if session.key and is_valid(active_actor) then
            pcall(function() active_actor.BP_MasterInventory.UseDestructionBag = false end)
            pcall(function() active_actor.BP_MasterInventory.ShouldSpawnBag = false end)
            pcall(function() active_actor:K2_DestroyActor() end)
        end
        set_active(nil, nil)
        persistence:reset()
        session.key, session.slot, session.level = key, slot, level
        session.paused, session.lost, session.component = false, false, nil
        session.load_transition = false
        first_miss = nil
        session.stable, session.next_scan, session.delay = now, now + 5, 2
    end
    session.paused = false
    if persistence.ready and is_valid(active_actor) then
        if was_paused then active_actor:SetActorEnableCollision(true) end
        if session.dedupe_at and now >= session.dedupe_at then
            session.dedupe_at = nil
            remove_duplicate_holds()
        end
        return active_actor, session.component
    end
    if session.lost or persistence.error then
        if manual then log("Cargo locked: " .. tostring(persistence.error or "actor lost during session; reload the save to recover saved cargo")) end
        return nil
    end
    if session.component and not is_valid(active_actor) then
        session.lost = true
        suspend_cargo()
        log("Cargo actor unloaded during the session; refusing to replace it with an empty hold. Reload to restore saved cargo.")
        return nil
    end
    if now < session.next_scan then return nil end
    install_save_hooks()
    if not session.sync_hook or not session.async_hook or not session.load_hook then
        persistence.error = string.format("native save hooks are unavailable (save=%s async save=%s load=%s); "
            .. "automatic cargo creation is paused", tostring(session.sync_hook == true),
            tostring(session.async_hook == true), tostring(session.load_hook == true))
        log(persistence.error)
        return nil
    end
    local proxy, component = ensure_cargo_hold()
    if not proxy then
        session.next_scan = now + session.delay
        session.delay = math.min(30, session.delay * 2)
        return nil
    end
    session.component = component
    proxy:SetActorEnableCollision(false)
    register_interaction_hooks()
    persistence:restore(slot, level)
    if persistence.ready then
        proxy:SetActorEnableCollision(true)
        log("Cargo Hold ready automatically; use Enter. Native save/reload support active for '" .. slot .. "'.")
        -- copies already standing (from saves made while 1.1.3 or older doubled
        -- the hold), and again shortly in case one is still being restored
        remove_duplicate_holds()
        session.dedupe_at = now + 5
        return proxy, component
    end
    log("Cargo interaction locked because persistence validation failed; see UE4SS.log for details.")
end
local lifecycle_tick = function()
    local ok, err = pcall(lifecycle_ensure, false)
    if not ok then
        suspend_cargo()
        persistence.ready = false
        persistence.error = tostring(err)
        log_once("lifecycle-error", "Cargo lifecycle failed: " .. tostring(err))
    end
end
-- One retained heartbeat. With a live hold this reads only cached references.
local lifecycle_timer_ok = pcall(LoopInGameThreadWithDelay, 1000, lifecycle_tick)
if not lifecycle_timer_ok then log("Cargo automatic timer unavailable; automatic setup cannot start.") end
log("Loaded cargo lifecycle v1. Automatic host creation after save readiness; use Enter at the Mi-8. Save normally to save cargo. "
    .. "Joining players use the host's hold (both need this mod).")
