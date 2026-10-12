# Reticle Size - Changelog

---

## 1.0.0 (2026-10-12)

### First Release
- `.reticle 50` (or `.dot 50`) sets the crosshair dot to 50% of the game's size, from 10 to 400%; `.reticle reset` puts it back, `.reticle` shows it
- Saved to `settings.txt` and applied again after loading or respawning
- The dot is found among the HUD's widgets by its name (crosshair, reticle, dot) and scaled around its centre, so it stays in the middle
- `.reticle scan` lists the widgets it could be, if the dot doesn't change
- Only your own screen changes, so it works the same in co-op
