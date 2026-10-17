# Chest Sort - Changelog

---

## 1.0.0 (2026-10-17)

- With a container open (the inventory screen), S sorts it: the smallest items first, so 1-slot items fill the top rows, then 2-slot items, then 3-slot and so on; items of the same kind end up next to each other, bigger stacks first
- Every move is the game's own "move item" (the same as dragging an item), so the game checks each one and nothing is lost, and it works in someone else's world too (the host's game does the moves). A few moves a second; the container is read again before each one
- A container that's too full to move big items about: the biggest items stay where they are and the rest is sorted around them. Completely full (no free cell): left as it is, and the log says so
- `.sort` does the same from the console, `.sort stop` stops it, `.sort check` logs what the mod sees in the open container and where each item would go (changes nothing)
- `key` and `moveDelayMs` in config.lua
