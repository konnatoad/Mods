# Mod Hub - Changelog

---

## 1.4.23 (2026-10-24)

- Chest Sort's text mentions its new groups (food, medical, mutant parts, animal parts, junk, money...) and that it puts the most valuable first

## 1.4.22 (2026-10-24)

- Restarting mods doesn't restart Stack Them All any more; the log says to restart the game for it instead. Restarting it in a world froze the host's game (UE4SS stopped it half way). It changes the game's item list, which only a fresh game start puts back to the game's own values, so a restart in a world couldn't fully update it anyway

## 1.4.21 (2026-10-24)

- Chest Sort's page mentions its stuck split key fix

## 1.4.20 (2026-10-24)

- Stack Them All's page: stacks are never smaller than the game's own (money stacks to 1000 since the anniversary update)

## 1.4.19 (2026-10-24)

- Stack Them All's page says it keeps item changes from game updates

## 1.4.18 (2026-10-18)

- Chest Sort's page mentions its Shift+click fix

## 1.4.17 (2026-10-17)

- Chest Sort's page lists `.sort repair`

## 1.4.16 (2026-10-17)

- Lists the new Chest Sort mod

## 1.4.15 (2026-10-17)

- Lists the new Sound Fixes mod

## 1.4.14 (2026-10-17)

- A mod's page jumped down to its first button, so on a long page the commands listed above it were out of view. With the first row selected the page now stays at the top; moving down scrolls as before

## 1.4.13 (2026-10-14)

- Lists the experimental YouTube TV mod and its `.tv` commands

## 1.4.12 (2026-10-14)

- PageUp opens and closes the hub, like `.mods` (the Mod Menu used to take PageUp for its cheat menu; open that with `.menu`, or from the Mod Menu's page here)
- The Mod Menu's page no longer lists PageUp; the Mod Hub's own page lists PageUp and Backspace

## 1.4.11 (2026-10-14)

- Backspace goes back one level: from a changelog or settings page to the mod's page, from a mod's page to the list, and closes the menu from the list. The key hints show it (`.mods` still opens and closes it)

## 1.4.10 (2026-10-14)

- Lists Radiation Shield's new `.radshield scan`

## 1.4.9 (2026-10-13)

- View Debug is in the list, with its commands (`.view hud` included)

## 1.4.8 (2026-10-13)

- No more "Restart all mods" (and `.reloadmods all`): restarting every mod at once isn't needed. "Restart changed mods" (`.reloadmods`) restarts the ones whose script changed, and each mod's page has "Restart this mod" (`.reloadmods <Name>`)

## 1.4.6 (2026-10-13)

- Field Of View is gone from the list: the mod was removed (calling the game's functions every second, it froze the game when mods were restarted)

## 1.4.5 (2026-10-13)

### Restarts Wait for the Inventory
- Restarting mods while the inventory was open froze the game: its screen keeps calling functions that mods hook while UE4SS is removing those hooks
- With the inventory (or another mouse-driven screen, like the PageUp menu) open, the hub now says "Close the inventory..." and restarts the mods as soon as it's closed. After 60 s it gives up and says so

## 1.4.4 (2026-10-13)

### No More Hang on Restart
- "Restart all mods" sometimes hung the game while the Mod Menu was being stopped. The hub restarted mods from the game thread; stopping a mod waits for it, and a mod with timers (the Mod Menu) can be waiting at that moment to hand work to the game thread, so each waited for the other forever
- Mods are now restarted from a background task, which leaves the game thread free; the menu shows "Restarting..." and then the result. The hub restarts itself last, as before
- Starting another restart while one is running is turned down ("Already restarting mods")

## 1.4.3 (2026-10-13)

- Reticle Size's page: its new colour and alpha commands

## 1.4.2 (2026-10-13)

- Field Of View's page: its new range (60-130) and how it works

## 1.4.1 (2026-10-13)

- Mods with settings say SETTINGS next to their name in the list, so it's clear which pages have a Settings button (CHANGED still shows instead when a mod has changed)

## 1.4.0 (2026-10-12)

### Settings Page
- Mods with a `config.example.lua` get a **Settings** button on their page: every setting with its description, the value you have now, and the defaults left plain while changed values are highlighted
- Left / Right change the chosen setting (on / off, numbers in steps that fit them, text from its listed choices); Enter switches it or puts the default back
- Saved straight away to the mod's `config.lua`, your own file that `git pull` never touches. A new `config.lua` starts as a copy of the example; an existing one keeps everything else you wrote in it
- A row restarts the mod so the new values take effect; a `config.lua` with a mistake in it is pointed out

### New Mods
- Knows Field Of View, Survival Stats and Whistle Range: their descriptions and commands

## 1.3.3 (2026-10-12)

- Stack Them All's page points to its new `config.lua`

## 1.3.2 (2026-10-12)

- Knows the new Reticle Size mod: its description and `.reticle` commands

## 1.3.1 (2026-10-12)

- Knows the new Head Bob mod: its description and `.headbob` commands

## 1.3.0 (2026-10-12)

### Changelog Pages
- One page per version, never split; Up/Down scroll it, Right shows the next older version, Left the newer one (or goes back from the newest), Enter goes back
- The status line names the versions Left and Right lead to, and the key hints change to match

### Markdown
- Tables become key / description rows, without the | and --- marks
- Numbered lists keep their numbers, nested points are indented, a **bold** line on its own is a heading, code blocks show as plain text, links show their text
- Lines of a paragraph that were wrapped in the file are joined again

### Scrolling and Wrapping
- Every page of the hub scrolls when it's taller than the screen allows; the chosen row stays in view
- The hub breaks long lines itself: Unreal never breaks before a word starting with "." (like .summon), so lines full of commands ran off the panel

## 1.2.0 (2026-10-12)

### Changelogs
- Each mod's page has a **Changelog** button (with the latest version next to it) that shows the mod's `CHANGELOG.md`, newest first, a page at a time
- Left goes back to the mod's page

### Other Changes
- Steel blue on dark navy, like the other menus
- The mods' descriptions say how each one works in co-op

## 1.1.0 (2026-10-12)

### Restarts Itself Too
- The hub shows when its own script has changed and restarts itself (last, after the other mods), closing its menu first
- Square, see-through look

## 1.0.0 (2026-10-12)

### First Release
- `.mods` lists the loaded mods; each mod's page shows its hotkeys and console commands, and opens the mod's own menu if it has one
- `.reloadmods` restarts the mods whose `main.lua` changed since they loaded (`.reloadmods all`, or `.reloadmods <Name>`), without restarting the game
