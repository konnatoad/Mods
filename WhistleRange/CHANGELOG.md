# Whistle Range - Changelog

---

## 1.0.0 (2026-10-12)

### First Release
- In co-op, players who joined now get whistles from as far away as the host does
- The host's game only sends a player's character (and its whistle) to a joined player while it's within Unreal's network range of them, 150 m by default. This mod widens that range for player characters only
- Only the host needs it; joined players' copies do nothing
- `rangeMeters` in `config.lua` sets the range (0 = no limit, the default)
- `.whistle` shows the range and the players it's applied to; `.whistle scan` lists everything named like a whistle, for the log
