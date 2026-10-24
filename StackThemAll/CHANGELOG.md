# Stack Them All - Changelog

---

## 1.4.0 (2026-10-24)

### Game Updates No Longer Undone
- Every item's weight, size, food values, durability and container size in `scripts\stackConfig.lua` were applied as the game had them when the file was made (May for most items), so a game update that changed an item (the anniversary update's new weapons and equipment) was undone. Now a value you never changed follows the game: the game's values are saved for each game version (`scripts\gameValues.lua`), and an entry still holding the old version's value gets the new one, in game and in `stackConfig.lua`
- Values you changed yourself are still applied, and stack sizes work as before
- The log lists what changed (`Game update: Weapon_AK74 weight 3.07 -> 3.4`)
- If the mod is updated with `.reloadmods` in a world, the game's values can't be read until the game is restarted (the log says so)
- MISERY's anniversary update added 33 items (7.62x25 ammo, attachments, new equipment and resources); they were added to `stackConfig.lua` with stack sizes on the first launch

## 1.3.4 (2026-10-17)

- A crash when a world loads or closes (joining, the host restarting or leaving): the retries while waiting for items to load ran on a background thread and searched every item in the world from there, which crashes UE4SS when it meets an object being deleted. They run on the game thread now

## 1.3.3 (2026-10-13)

### Category Sizes Now Apply to Every Item
- A category's stack size in `config.lua` (or the Mod Hub's Settings) only reached items added by later game updates: every item already in `scripts\stackConfig.lua` kept the size written there. Now it applies to every item of the category
- Items whose own size was set on purpose keep it: money (`Resource_Rubles = 250`), and anything you changed in `stackConfig.lua` to something other than its category's built-in size
- `stackConfig.lua` is still written with the built-in sizes, so changing a category again later keeps working

## 1.3.2 (2026-10-13)

- `config.example.lua` lists every category's stack size (Ammo, Food, Drink, Consumable, Resource, Plant, Object, BuildPart, Artifact) and the sorting option, not just two examples, so the Mod Hub's Settings page shows all of them

## 1.3.1 (2026-10-13)

- Restarting the mod in a world (`.reloadmods`, or the Mod Hub after a settings change) applies the stack sizes straight away; before, only the next load did

## 1.3.0 (2026-10-12)

### Updating with git pull
- Your own category stack sizes go in `config.lua` (copy `config.example.lua`) instead of `scripts\stackThemAllConfig.lua`, so `git pull` can always update the mod
- `scripts\stackConfig.lua` is yours and no longer comes with the mod: the first launch makes it from `scripts\stackConfig.default.lua` (the old file, renamed), and later launches add items from game updates to it

## 1.2.0 (2026-10-11)

### New Items Are Added Automatically
- At launch, items added by game updates are appended to `stackConfig.lua` with their category's stack size; your entries are never touched
- Money stacks to 250

### Fixes
- Values missing from an entry keep the game's value
- `onlyStacksChanges` and `aphapeticallySorted` work
- Sets itself up once instead of retrying constantly: it used to write about 1,400 log lines in 12 minutes at the main menu

### Co-op
- Every player needs it with the same stack settings

## 1.1.0

- The original release by its author
