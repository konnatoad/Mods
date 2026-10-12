# Head Bob - Changelog

---

## 1.0.0 (2026-10-12)

### First Release
- `.headbob 50` sets the head bob to 50% of the game's own while walking and running (0 = none, up to 200)
- `.headbob walk 40` and `.headbob run 20` set them separately; `.headbob off`, `.headbob reset` (100%), `.headbob` shows the settings
- Saved to `settings.txt`
- Changes the strength each walking or running camera shake starts with; other shakes (hits, explosions) are left alone
- `.headbob scan` lists the camera shakes the game starts while you move and your character's bob-like settings, if the bob doesn't change
- Only your own view changes, so it works the same in co-op
