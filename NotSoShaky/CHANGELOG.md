# Not So Shaky - Changelog

---

## 1.0.4 (2026-10-14)

- Restarting this mod from the Mod Hub ("Restart changed mods") could crash the game: UE4SS removes a restarted mod's hooks on engine functions, but its hooks on the game's own functions stayed, still pointing into the old copy of the mod, and the next time the game ran one UE4SS crashed. They're now written down (`hooks.txt` in the mod's folder) and removed when the mod loads again in the same game session (shared `GameHooks` module)

## 1.0.3 (2026-10-12)

### Fixes
- Waits properly when the game hasn't loaded the controller or the camera shake yet, instead of stopping with an error
- Its log line says what it did: `[NotSoShaky] Softer hit camera shake applied`

## 1.0.2

- The original release by its author: a softer camera shake when you're hit
