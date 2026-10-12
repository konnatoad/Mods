# Mod Hub - Changelog

---

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
