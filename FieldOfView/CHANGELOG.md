# Field Of View - Changelog

---

## 1.1.0 (2026-10-13)

### Smooth Aiming
- Aiming with a wider field of view jumped back to the game's own view first and then zoomed in. Every field of view the game gives your camera is now scaled by yours / the game's: the normal view is yours, and aiming zooms in smoothly from it and back
- Aiming zooms in by the same proportion as before (aiming at 55 with the game's 90 becomes 67 with your 110)
- Character settings are no longer changed (their scaled values would have been scaled twice)
- Changing `.fov` mid-aim keeps the zoom; `.fov scan` says how many of the game's view changes were scaled

## 1.0.0 (2026-10-12)

### First Release
- `.fov 95` sets the field of view in degrees (60-120); `.fov reset` goes back to the game's own, `.fov` shows it
- Saved to `settings.txt`
- Aiming still zooms in: the view is only changed while it's at the game's normal field of view
- Character settings that hold the normal field of view follow yours, so the view comes back from aiming at your value
- `.fov scan` lists your character's cameras and field-of-view settings, if the view doesn't change
- Only your own view changes, so it works the same in co-op
