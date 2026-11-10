# Settings window — design

Date: 2026-11-10. Status: approved by the user in brainstorming.

## Why

v0.1.0 works, but its rules about when it speaks are invisible. It stays quiet
while you are dead or resting, and it reminds you exactly once after 60 s, and
the player can neither see nor change any of that. This change puts those
rules in a small settings window so players can see them and tune them. It
also expands the reminder into a configurable series.

## Goals

- Typing `/peckish` on its own opens a small settings window.
- Every rule that decides when the addon speaks is a toggle or slider there.
- The reminder can repeat: a chosen number of times, or until the player eats.
- The defaults reproduce v0.1.0 behaviour exactly. Upgrading changes nothing
  until the player changes a setting.

## Non-goals

- A minimap button, an Interface → AddOns options panel entry, or profiles.
- Editing the phrases, changing the message colour, or sending to chat channels
  (still never, see PRD section 2).
- Libraries. The window is built from plain `CreateFrame` and Blizzard templates.

## Anti-goals (it fails if…)

- Anyone upgrading from 0.1.0 notices a behaviour change without opening the window.
- Settings change before the player presses Accept.
- The window leaks globals other than the frame name it needs, or taints anything.

## Commands

| Command | Effect |
|---------|--------|
| `/peckish on` | As today: enable, save, print confirmation |
| `/peckish off` | As today: disable, save, cancel pending reminders, print confirmation |
| `/peckish` (empty or whitespace) | Open the settings window (toggle it closed if already open) |
| anything else | As today: print status and usage, which now also mentions `/peckish` opens settings |

`Core.parseCommand` gains an `"open"` result for the empty argument.

## The window

The mockup the user approved is `.superpowers/brainstorm/1911-1794347849/content/settings-window.html`
(local, git-ignored). Top to bottom:

- Title "FeelingPeckish" and a close ✕.
- [x] **Snack alerts on**
- Header **Stay quiet while**
  - [x] **Dead or a ghost**
  - [x] **Resting (city or inn)**
- Header **Reminders**
  - [x] **Send reminders**
  - Slider **Every**: 30 s to 10 min, step 30 s, value shown as "1 min", "2 min 30 s", "30 s".
  - Slider **How many**: 1 to 10, step 1.
  - [ ] **Keep reminding until I eat**. When ticked, the "How many" slider is greyed out and disabled.
  - When "Send reminders" is unticked, the two sliders and the "until I eat" box are greyed out.
- Buttons **Accept** and **Close**, bottom right.

Behaviour:

- Opening the window loads the saved settings into the controls. Edits are a
  draft until **Accept** is pressed.
- **Accept** saves the draft to `FeelingPeckishDB`, applies it and closes the window.
- **Close**, ✕ and Escape discard the draft and close without asking. Escape
  works by adding the frame name to `UISpecialFrames`.
- The window looks like a standard game dialog, is movable by dragging, and is
  clamped to the screen. Its position is not saved (builder's call; do not save it).
- It can be opened in combat. It only uses plain frames and touches no protected API.
- If `/peckish on` or `/peckish off` runs while the window is open, the
  "Snack alerts on" box updates to match.

## Settings (`FeelingPeckishDB`)

| Key | Type | Default | Valid |
|-----|------|---------|-------|
| `enabled` | boolean | `true` | existing key, kept as is |
| `quietWhenDead` | boolean | `true` | |
| `quietWhenResting` | boolean | `true` | |
| `remindersOn` | boolean | `true` | |
| `reminderInterval` | number (seconds) | `60` | 30–600, multiple of 30 |
| `reminderCount` | number | `1` | 1–10 integer |
| `remindUntilFed` | boolean | `false` | |

On `ADDON_LOADED`, every missing or invalid field falls back to its default.
Numbers out of range or off-step are clamped or rounded to the nearest valid
value. This is pure logic (`Core.normalizeSettings` or similar) and gets unit tests.

## Rules

- **Falloff message**: printed when enabled, and not (dead and `quietWhenDead`),
  and not (resting and `quietWhenResting`). The same `canSpeak` rule gates reminders.
- **Reminder series**: on a falloff while enabled and `remindersOn`, the first
  reminder is scheduled `reminderInterval` seconds later, even if the falloff
  message itself was quiet. This matches today.
- Each time a reminder comes due:
  - If the buff is back, the series ends silently. (Normally it was already
    cancelled when the buff came back.)
  - Otherwise, if `canSpeak`, print `Still peckish: <phrase>`. If not, skip it silently.
  - Either way the reminder **counts** toward `reminderCount`. That reproduces
    v0.1.0, where a single skipped reminder meant no reminder.
  - If `remindUntilFed`, or fewer than `reminderCount` reminders have come due,
    schedule the next one `reminderInterval` seconds later. Otherwise the series ends.
- The series is cancelled when the buff returns, when the addon is turned off
  (by command or by Accept), when a new falloff restarts it, or when Accept turns
  `remindersOn` off. Only one series and one timer exist at a time.
- Accept while a series is running: the next reminder already scheduled keeps
  its time. Later ones use the new interval, count and until-fed settings. If the
  new count is already used up, the series ends after the reminder that is
  pending. (This was approved in conversation as "applies from the next
  reminder on". The builder may instead reschedule the pending timer, provided
  it is documented in the PRD.)
- Loading screens, login and `/reload` still only set a baseline and never
  start a series. A `/reload` drops any running series, as it does today.

## Code layout (follows CLAUDE.md)

- `src/Core.lua` (pure, tested): settings defaults and normalisation, `canSpeak`
  using the quiet toggles, the reminder-series decisions (whether to arm on
  falloff, and what to do when a reminder comes due: print, schedule another,
  stop), `parseCommand` returning `"open"`.
- `src/Options.lua` (new, game code): builds the window lazily on first open,
  holds the draft, and calls back into `Init.lua` via `ns` to save and apply.
  Add it to `FeelingPeckish.toc` after `Core.lua` and before `Init.lua` (or
  after it, whichever way the `ns` wiring needs). It must be `git add`ed, or
  builds leave it out.
- `src/Init.lua`: reads settings from the DB, owns the timer, and runs the
  series using Core's decisions.
- `.luacheckrc`: declare every new WoW API or global used (`UISpecialFrames`,
  `UIParent`, template-related globals, and so on) and the window's global frame name.
- `spec/Core_spec.lua`: tests for normalisation, quiet toggles, every series
  path (count reached, until-fed, skipped-but-counted, cancel on buff/off/Accept),
  and `parseCommand("")` → `"open"`.

## Builder's calls

- Template choice: check which Blizzard templates exist on Interface 16001.
  The likely ones are `BasicFrameTemplateWithInset` or `ButtonFrameTemplate`,
  `UICheckButtonTemplate`, `UIPanelButtonTemplate`, and `OptionsSliderTemplate`
  or `MinimalSliderWithSteppersTemplate`. Fall back to plain textures if needed.
- Exact pixel layout, fonts and spacing, staying close to the mockup.
- The global frame name (e.g. `FeelingPeckishOptionsFrame`).
- The new wording of the usage line.

## Docs to update in the same change

- `PRD.md`: remove the "no options panel / settings beyond on/off" non-goal,
  update goals ("remind once" → configurable), sections 3.2, 3.3, 3.6 and 3.7,
  file layout 4.1, and the in-game test list.
- `CHANGELOG.md`: lines under `## [Unreleased]` for the window, the
  quiet-toggle settings and the repeating reminders.
- `README.md`: mention `/peckish` opens settings, if it documents commands.

## In-game checks (human only)

List these for the user when done, together with the existing ones in CLAUDE.md:

1. `/peckish` opens the window with v0.1.0 defaults. Escape, ✕ and Close
   discard changes. Accept saves and closes.
2. Untick "Resting", Accept, lose Well Fed in a city: the message prints.
3. Interval 30 s, count 3: three reminders 30 s apart, then silence.
4. "Until I eat" ticked: reminders keep coming until you eat, then stop.
5. Untick "Send reminders": only the falloff message prints.
6. `/reload`: all settings are kept. `/peckish off` with the window open unticks the box.
