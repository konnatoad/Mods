-- This file is used to store the stack size for items in the game.

-- This are the IDs tha should only have 1 stack at maximum, because it could cause bugs if you stack multiple
-- of them together, pottentially causing you to lose items or have them disappear, or even cause crashes.
-- Doesn't mean that they wont show at the config file, only that you don't have a quick stack configuration for them.

-- EmptyItem
-- CUTWeapon_AKS74U
-- Equipment
-- Holdable
-- Magazine
-- Misc
-- Weapon

-- Every item's category is the start of its ID before the first "_" (Food_Apple -> Food). Items get the
-- <Category>_StackSize below; categories without one keep the game's own stack values.
-- If a game update adds a new category, it shows in UE4SS.log as "keeps game stack values" and you can
-- add e.g. Tool_StackSize = 100 here, then delete its entries from stackConfig.lua so they get regenerated.

-- Items the game adds in updates are appended to stackConfig.lua automatically on the next launch.

-- onlyStacksChanges = true applies only stackSize/allowStack from stackConfig.lua and leaves weight, size,
-- container, consumable and durability values as the current game version has them.

local stackThemAllConfig = {
    aphapeticallySorted = true,
    onlyStacksChanges = false,
    Ammo_StackSize = 1000,
    Artifact_StackSize = 100,
    BuildPart_StackSize = 100,
    Consumable_StackSize = 100,
    Resource_StackSize = 100,
    Food_StackSize = 100,
    Drink_StackSize = 100,
    Plant_StackSize = 100,
    Object_StackSize = 100,
}

return stackThemAllConfig