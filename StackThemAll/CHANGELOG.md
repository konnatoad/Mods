# Stack Them All - Changelog

---

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
