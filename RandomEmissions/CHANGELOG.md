# Random Emissions - Changelog

---

## 1.1.0 (2026-10-12)

### Co-op
- Only the host's copy picks the random emission times (the host's game runs the emissions)
- When the host's siren starts, players who joined are told and their siren plays too
- In someone else's world the mod never changes the timer or plays the siren by itself

## 1.0.1 (2026-10-11)

### No More Piling Up
- The level-change hook and the per-frame loop are set up once instead of on every load and respawn, where they piled up

## Original

- Emissions at random times (every 1800-3600 s) with a siren 120-300 s before, by the original author
