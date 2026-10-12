# Reticle Size - Changelog

---

## 1.0.2 (2026-10-12)

### Performance
- After a load it looks for the crosshair 5 times (1, 3, 6, 10 and 20 s), not every second for 20 s; each look walks through every object in the game

## 1.0.1 (2026-10-12)

### Fix
- "dot" only counts as a word of its own (Dot, CenterDot, Aim_Dot), so widgets like an "AntidoteIcon" are never scaled

## 1.0.0 (2026-10-12)

### First Release
- `.reticle 50` (or `.dot 50`) sets the crosshair dot to 50% of the game's size, from 10 to 400%; `.reticle reset` puts it back, `.reticle` shows it
- Saved to `settings.txt` and applied again after loading or respawning
- The dot is found among the HUD's widgets by its name (crosshair, reticle, dot) and scaled around its centre, so it stays in the middle
- `.reticle scan` lists the widgets it could be, if the dot doesn't change
- Only your own screen changes, so it works the same in co-op
