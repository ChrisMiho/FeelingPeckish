# FeelingPeckish

World of Warcraft: Forever addon (Lua 5.1, Interface 16001). When the
player's "Well Fed" food buff falls off it prints a silly message to the
player's own chat frame (never to a chat channel), then reminds them if they
have not eaten again (by default once, 60 s later). `/peckish` opens a small
settings window: quiet while dead or resting, and the reminder interval, count
or "until I eat". `/peckish on` and `/peckish off` toggle the addon. Settings
are saved in `FeelingPeckishDB`. One window, no other UI, no libraries.

## Spec

`PRD.md` is the spec. A change to behaviour is not done until `PRD.md` agrees
with the code.

## Commands

Run from the repo root. On Windows, `.sh` scripts need Git Bash.

| Task | Command |
|------|---------|
| Lint | `luacheck .` |
| Unit tests | `busted` |
| Build, zip and install into the game | `scripts/build.sh` |
| Build and zip only (no game install) | `scripts/build.sh --no-install` |

Lint and tests must pass before you call work done; CI runs both on every push.
The build output goes to `.release/` (git-ignored). `scripts/build.sh` only
works in a normal checkout: inside a git worktree the packager stops with
"No Git, SVN, or Hg checkout found". A feature branch in the main checkout
builds fine (the version is then `<tag>-<n>-g<hash>`).

## Layout

| Path | Purpose |
|------|---------|
| `FeelingPeckish.toc` | Load order and SavedVariables. Every new `src/` file must be listed here |
| `src/Phrases.lua` | The silly phrases and the picker (pure) |
| `src/Core.lua` | Pure decisions: settings defaults and normalisation, when to announce, the reminder series, command parsing, window greying rules |
| `src/Options.lua` | The settings window (game code): draft until Accept, calls `ns.getSettings` / `ns.applySettings` |
| `src/Init.lua` | WoW glue: events, the reminder timer, slash command, SavedVariables |
| `spec/` | busted tests, one `<Module>_spec.lua` per module |
| `scripts/` | Developer scripts (not shipped) |
| `docs/` | Design specs and plans (not shipped) |
| `.pkgmeta` | Packager config: files left out of the package |

## Code rules

- **Every file starts with `local addonName, ns = ...`** (or `local _, ns = ...`).
  Share code through `ns`, never through new globals.
- **Keep pure logic separate from game code.** Phrases, buff-state and settings
  decisions go in modules that call no WoW API and get busted tests. Code that
  touches frames, events, timers, chat output or the WoW API stays in
  `src/Init.lua` (or `src/Options.lua` for the settings window).
- **Test pure modules through `LoadAddonFile`** (from `spec/helper.lua`), which
  loads a file the way the game does: `LoadAddonFile("src/Phrases.lua").Phrases`.
- **Declare every WoW API you use** in `read_globals` in `.luacheckrc`, and every
  global you create in `globals`. That way lint catches typos in API names.
- **Messages go to the player's own chat frame only** (`DEFAULT_CHAT_FRAME`),
  never to a chat channel.
- **No libraries.** If one is ever needed, add it via `.pkgmeta` externals
  (pinned to a tag) and an `embeds.xml` listed in the `.toc`; never commit
  `Libs/` or copy library code into `src/`.
- Tabs for Lua indentation; see `.editorconfig`.
- Newly created files are left out of builds until they are `git add`ed.

## Things only a human can check

Anything that needs the game client. When a task depends on one of these,
finish the parts you can test, then list exactly what the user should try in
game and what they should expect to see. `PRD.md` section 4.3 is the full
list; for example:

- Eat food, wait for "Well Fed", then let it expire (or cancel it): one silly
  message appears in your chat frame, and nobody else sees it.
- With default settings, do not eat again: one reminder appears about 60 s
  later, and no more after it. Eat again before the 60 s are up: no reminder.
- `/peckish` opens the settings window. Escape, ✕ and Close discard changes;
  Accept saves them.
- Interval 30 s, count 3: three reminders 30 s apart, then silence.
- `/peckish off`, lose the buff: nothing is printed. `/peckish on` turns it back on.
- `/reload` (or log out and in): all settings are kept.

## Changes and releases

- Add a line under `## [Unreleased]` in `CHANGELOG.md` for each user-facing change.
- Releases are made by pushing a `v*` tag (see README). Do not tag or push
  unless asked.
