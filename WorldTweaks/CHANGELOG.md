# World Tweaks - Changelog

---

## 1.1.0 (2026-10-12)

### Co-op
- Day/night length and season belong to the host's world: in someone else's world the mod asks the host's World Tweaks for its numbers and uses those, so both games' clocks run at the same speed
- A host without World Tweaks: after 3 s the log says so and the game's own day length is kept
- Darker nights still uses your own setting (it only changes how your sky looks)

## 1.0.0 (2026-10-11)

### First Release
- Day/night length, season and darker nights in one config; replaces DayLengthTweaks and the Darker Nights pak (`777_DarkerNights_P`)
- Settings are applied up to 30 s after loading, once the weather manager exists, and again after a respawn
- A forced season is set once per world, so respawning doesn't restart the change
- Darker nights writes the night sky light into the weather table, found by the fields' readable names so a game update that renames them still works
- `.worldinfo` shows the day/night settings; `.weatherdump` writes every weather preset to a file
