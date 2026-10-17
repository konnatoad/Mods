# Chest Sort - Changelog

---

## 1.3.0 (2026-10-17)

- Sorted by what the items are first: each kind gets its own rows (weapons, magazines, ammo, grenades and other holdables, medicine, food, drink, equipment, artifacts, resources...), then by size within the kind. 1.2.0 sorted only by size, so ammo boxes and grenades of the same size ended up mixed. The kind is the start of the game's item ID (Ammo_..., Holdable_...). A smaller container shares rows between sizes of a kind, and one too small for that shares rows between kinds (still in kind order)

## 1.2.0 (2026-10-17)

- Items are turned to lie flat (wider than tall), so they line up in even rows: a 1x2 item becomes 2x1 and shares the rows of the other 1-high items. `rotate = false` in config.lua keeps every item turned the way it is. If the game turns items differently than expected, the mod notices on the first move, adjusts, and if that doesn't work either it stops turning items

## 1.1.0 (2026-10-17)

- Neat rows instead of a jumble: each shape gets its own rows (all 1x1 items in the top rows, then the 2x1 ones, then 1x2, 3x1 ...), filled left to right, the same kind together. 1.0.0 put each item into the first gap it fitted, which mixed shapes and left ragged rows. A smaller container gets one set of rows per height instead (1x1, 2x1, 3x1 share the top rows, then the 2-high items, then 3-high); one too full for either still packs the old way

## 1.0.0 (2026-10-17)

- With a container open (the inventory screen), S sorts it: the smallest items first, so 1-slot items fill the top rows, then 2-slot items, then 3-slot and so on; items of the same kind end up next to each other, bigger stacks first
- Every move is the game's own "move item" (the same as dragging an item), so the game checks each one and nothing is lost, and it works in someone else's world too (the host's game does the moves). A few moves a second; the container is read again before each one
- A container that's too full to move big items about: the biggest items stay where they are and the rest is sorted around them. Completely full (no free cell): left as it is, and the log says so
- `.sort` does the same from the console, `.sort stop` stops it, `.sort check` logs what the mod sees in the open container and where each item would go (changes nothing)
- `key` and `moveDelayMs` in config.lua
