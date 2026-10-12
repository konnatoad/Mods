# Field Of View - Changelog

---

## 1.0.0 (2026-10-12)

### First Release
- `.fov 95` sets the field of view in degrees (60-120); `.fov reset` goes back to the game's own, `.fov` shows it
- Saved to `settings.txt`
- Aiming still zooms in: the view is only changed while it's at the game's normal field of view
- Character settings that hold the normal field of view follow yours, so the view comes back from aiming at your value
- `.fov scan` lists your character's cameras and field-of-view settings, if the view doesn't change
- Only your own view changes, so it works the same in co-op
