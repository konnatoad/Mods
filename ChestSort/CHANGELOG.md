# Chest Sort - Changelog

---

## 1.6.1 (2026-10-24)

- Each group is one block now: it starts on a new row and all its items fill in from there, every size together. Before, each size of a group started its own row, so a group like mutant parts broke into separate rows (small hands, Chuvirla fists, heads) with gaps between them and looked like several groups

## 1.6.0 (2026-10-24)

- Finer groups: loot the game files under one "Resource" kind is now split into money, mutant parts (Chuvirla hands, zombie hands, ghoul parts, mutant carcasses...), animal parts (boar and deer heads, dog tails, animal carcasses...), gun parts, broken gear and junk. Junk is everything the junk trader buys, read from the game's own trader data, so new junk items join it by themselves. Medical items, food and drink are each their own group, and tools (grenades, flashlights) come after equipment
- Groups go: weapons, magazines, ammo, attachments, medical, food, drink, equipment, tools, artifacts, money, mutant parts, animal parts, gun parts, broken gear, junk, materials, plants, build parts, the rest
- Within a group, items of the same size go from the most valuable to the least (what a trader pays for one, from the game's item data)
- `.sort check` shows each item's group and value, and which trader it took as the junk trader

 (2026-10-24)

- Dragging a stack in your inventory moved only half of it, every time: the game's split key can get stuck on after a missed key release (its own bug; the Mod Menu's `.invcheck fix` turned it off by hand). Now clicking an item with no Ctrl, Alt or Shift really held turns a stuck split key off before the drag, and the log says when it did. `splitFix = false` in `config.lua` turns this off

## 1.5.4 (2026-10-24)

- MISERY's anniversary update: weapon attachments (camouflage now, scopes and silencers later) get their own group, right after ammo

## 1.5.3 (2026-10-18)

- Shift+click moves the stack right away: it waited half a second to see whether the game moved it first, which felt slow. If the game moves it too, the second move finds the cell empty and does nothing

## 1.5.2 (2026-10-18)

- The Shift+click fix couldn't tell which container a clicked item is in (the icon's GetInventory gives a copy of the cells, not the container): it uses the icon's own container now

## 1.5.1 (2026-10-18)

- The Shift+click fix never ran: with the inventory screen open the player's input doesn't see keys, so Shift never counted as held. It now uses the game's own quick-move key flag. The first few clicks log why one was skipped, if it was

## 1.5.0 (2026-10-18)

- Quick move fix: Shift+click on a stack in your inventory with a container open (like 100 wood into the workbench) did nothing - the game's own bug, host or not. When the game doesn't move it, the mod moves the whole stack into the first free place in the container half a second later, with the game's own move (the same as dragging it there), so it works in co-op too. `quickMoveFix = false` in config.lua turns it off

## 1.4.2 (2026-10-17)

- `.sort repair` works for a joined player too. In co-op each player's game keeps its own copy of an open container's cells (the host's game sends them), so the broken cells may be only in the joined player's copy, or in the host's too. A joined player's `.sort repair` now frees them in its own copy and asks the host's Chest Sort (1.4.2) to free them in the host's and send the container again; the host's answer shows in the console. The log says whether each change stuck

## 1.4.1 (2026-10-17)

- A fridge was left with cells still marked as taken by an item that wasn't there (unusable). Most likely from 1.4.0 moving an item partly over where it was: the game clears an item's old cells after filling the new ones. Items are never moved partly over themselves any more (big items still get room made the other ways)
- `.sort repair`: frees cells taken by an item that isn't there. Only the host's game can change a container, so the host opens it and runs it; a joined player sees what's wrong

## 1.4.0 (2026-10-17)

- Big items are sorted too: two big items each over the other's place (the flour and sugar sacks) made 1.3.0 give up and leave every big item where it was, with gaps everywhere. Now an item can be moved partly over where it is, the item itself steps aside when that frees the way, and smaller items are moved out of a spot to make room for a big one. If the game refuses moving an item partly over itself, the mod notices and goes around it
- Items keep the way they're turned; tall items are only turned flat when the container is too full to sort them as they are (1.2.0 turned every one)
- Pressing S on a sorted container changes nothing (it moved the big items again each time)

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
