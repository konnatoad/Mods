# Radiation Shield - Changelog

---

## 1.6.5 (2026-10-14)

- Below 100%, radiation built up faster with the shield on than without it (100% worked). 1.6.4 removed the radiation that gets past the shield by writing the radiation value directly, but the game keeps more radiation bookkeeping behind that value and pulled it back up, harder the bigger the gap. It now uses the game's own way of lowering radiation (DecreaseRadiation, like the mod menu), so the rest follows
- `.radshield scan` writes every radiation-like number and function on your stats to the log, in case radiation still behaves oddly

## 1.6.4 (2026-10-14)

### Co-op: Radiation Getting Past the Shield
- Some radiation reached players without passing the point where the shield cuts it. The host's readout showed the shield removing all of the incoming radiation, yet radiation still rose (+4.9 /s); a joined player with the shield on rose +14.5 /s
- Now, once a second, the host checks every player whose shield is on (the host's own and joined players'): whatever rose beyond what the shield let through is cut by the same percentage, so at 100% none of it stays, however the game added it. The log says once when this happens ("Radiation also rises outside the shield's hook ...")
- It writes the radiation value directly instead of calling a game function every second (game functions called from a timer froze the game before)
- Radiation going down (anti-rad drugs) is never touched, and nothing changes while the shield is off

### Joined Player's Readout
- A joined player's game never sees radiation come in (the host adds it), so the readout showed "Incoming: +0.00 /s" and "Shield removes: -0.00 /s" while radiation rose. It now says "Incoming: counted by the host" and "Shield: on, the host applies it", next to the actual change

## 1.6.3 (2026-10-13)

- Its timer is a 1 s background tick again: the game-thread timer (LoopInGameThreadWithDelay) of the previous version, used by several mods at once, froze the game during normal play

## 1.6.2 (2026-10-13)

- Its timer now runs on the game thread (like the Mi-8 Cargo Hold's, which never froze). Background timers that hand their work to the game thread could leave UE4SS waiting forever when mods were restarted, freezing the game

## 1.6.1 (2026-10-12)

### Fix
- Back in your own world after playing in someone else's, the shield kept the last host's strength until you switched it off and on; now it goes back to your own straight away

## 1.6.0 (2026-10-12)

### New Look
- The settings menu and the badge are square, see-through dark navy panels with soft steel-blue highlights (like the Mod Hub and the PageUp menu)
- Warnings such as DISABLED BY HOST are soft amber, so they stand out

### Restarting
- Works with the Mod Hub's `.reloadmods`: a restarted copy removes the menu and badge the previous copy left on screen

## 1.5.0 (2026-10-12)

### The Host Sets the Strength
- In co-op the host's **Less radiation** applies to every shield in the host's world; the host's answer carries it, and the badge shows it
- When the host changes it, shields that are on follow straight away
- Your own saved percentage is kept for when you host

### Joined Players' Menu
- In someone else's world `.radmenu` only has Shield, Live readout, Badge, Badge position and Toggle key, and shows the host's percentage under the title
- `.radshield 75` is refused there (`.radshield on/off` works)
- The menu rebuilds itself when you go from hosting to joining or back

## 1.4.1 (2026-10-12)

### Crash Fix
- The game could crash inside UE4SS's game-thread queue: the badge's 80 ms animation timer is gone (the badge is static and hides itself with a one-off timer)
- HOME is debounced (0.4 s), so a held key no longer floods the game with toggles

## 1.4.0 (2026-10-12)

### Redesigned Menu
- Cards for Shield, Co-op, Display and Startup, switches for on/off settings and a slider for the strength
- Crash guards around every widget the menu creates

### Co-op Requests That Work
- A joined player's game asks the host through `ServerNotifyLoadedWorld` (the obvious choice, `ServerCheat`, doesn't exist in the game's shipping build); the host answers with a line in the player's console
- No answer within 3 s: the badge shows HOST HAS NO SHIELD MOD

## 1.3.0 (2026-10-12)

### Individual Co-op Shields
- Every player's shield is their own: HOME protects only the player who pressed it
- The host decides whether players who joined may use theirs (**Others can use it**); switching it off turns their shields off, and their badge shows DISABLED BY HOST

## 1.2.0 (2026-10-11)

### Settings Menu
- `.radmenu` opens a settings menu: Shield, Less radiation, Live readout, Badge, Badge position, Shield on at start and Toggle key
- Live readout: your radiation, what comes in per second, what the shield removes, the actual change and the time until maximum
- Every change is saved to `settings.txt`
- Co-op protection: the shield never changes other players' radiation

## 1.1.0 (2026-10-11)

### Meter and Strength
- `.radmeter` measures a hot spot; run it again for the suggested reduction (for 30, 60, 120 or 300 s)
- `.radshield 75` sets the shield to 75% less radiation and switches it on (saved)

## 1.0.0 (2026-10-11)

### First Release
- HOME switches the shield: less radiation while it's on, for bunker hot spots
- On-screen badge
- Checks after loading that the reduction really happens, and switches to taking radiation back if the game ignores the smaller amount
