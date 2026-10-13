# World Tweaks - Changelog

---

## 1.3.1 (2026-10-13)

- Season setting paused again, as in 1.2.2: Toggle Season with the game's own speed and duration (1.3.0) froze the game right after setting the season. Until it's known what Toggle Season's values mean, World Tweaks doesn't change the season

## 1.3.0 (2026-10-13)

### Season Setting Back
- `season` works again. The seasons cycled because the game's Toggle Season was given the mod menu's speed 1.0 and duration 0: a season lasting no time at all. It now gets the game's own transition speed and season duration (60 and 180), so the season changes like the game changes it
- Joined players get the host's season again

## 1.2.2 (2026-10-13)

### Season Setting Paused
- Setting a season mid-game made the seasons cycle quickly (summer, autumn, ...): the game's Toggle Season was called with the mod menu's values (speed 1.0, duration 0), and one of them doesn't mean what it was taken for
- Until that's known, World Tweaks doesn't change the season at all (also not the host's season for joined players); the log says so when `season` is set
- `.worldinfo` now lists what Toggle Season takes (its parameter names and types) and more of the weather system's season values, to set it up properly

## 1.2.1 (2026-10-13)

- Changing a setting (in the Mod Hub's Settings, or `config.lua`) and restarting the mod in a world now applies it straight away; before, nothing happened until the next load or respawn

## 1.2.0 (2026-10-12)

### Updating with git pull
- Your own settings go in `config.lua` (copy `config.example.lua`), not in `main.lua`, so `git pull` can always update the mod
- `nightSkyLight = false` keeps the game's night sky

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
