# Stack Them All - Changelog

---

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
