# Backpack Weight Fix - Changelog

---

## 1.2.0 (2026-10-12)

### Updating with git pull
- Your own settings go in `config.lua` (copy `config.example.lua`), not in `main.lua`, so `git pull` can always update the mod
- `checkEverySeconds` is at least 5

## 1.1.0 (2026-10-12)

### Co-op
- The host's game keeps every container, the joined players' backpacks too, so the host's copy fixes them for everyone
- In someone else's world the mod changes nothing (a change there would only be undone); `.fixweight` says so

## 1.0.1 (2026-10-12)

### Crash Fix
- Asking a container without an owner for the owner's name crashed the game; every link is checked first now, and such containers are still fixed

## 1.0.0 (2026-10-11)

### First Release
- Empty containers stuck with weight (like an empty backpack at 73/75 kg) go back to 0 every 30 s
- `.fixweight` runs it right now
- `.weightreport` lists the containers' number variables, for when the weight value can't be found
- The game's global inventory manager is left alone
