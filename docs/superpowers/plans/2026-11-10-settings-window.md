# Settings window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/peckish` opens a settings window exposing the quiet rules and a configurable reminder series; defaults reproduce v0.1.0 exactly.

**Architecture:** All decisions (settings normalisation, `canSpeak`, arming, what to do when a reminder comes due, slider label text, which controls are greyed) are pure functions in `src/Core.lua`, tested with busted. `src/Init.lua` owns `FeelingPeckishDB`, the single timer and the slash command and acts on Core's decisions. `src/Options.lua` (new) builds the window lazily, keeps a draft, and calls `ns.getSettings()` / `ns.applySettings(draft)` that Init defines.

**Tech Stack:** Lua 5.1, WoW API (Interface 16001), busted, luacheck.

**Spec:** `docs/superpowers/specs/2026-11-10-settings-window-design.md`

## Global Constraints

- Every file starts with `local addonName, ns = ...` or `local _, ns = ...`; share through `ns`, no new globals except the frame name `FeelingPeckishOptionsFrame`.
- Messages only via `DEFAULT_CHAT_FRAME:AddMessage`, never a chat channel.
- No libraries. Window is plain `CreateFrame` + Blizzard templates.
- Defaults: `enabled=true, quietWhenDead=true, quietWhenResting=true, remindersOn=true, reminderInterval=60, reminderCount=1, remindUntilFed=false`.
- `reminderInterval` valid 30–600, multiple of 30. `reminderCount` valid 1–10 integer.
- Tabs for indentation. Every WoW API used goes in `.luacheckrc` `read_globals`.
- `luacheck .` and `busted` pass after every task. Run them from PowerShell (they are not on Git Bash's PATH).

## Review Focus

1. A 0.1.0 save `{ enabled = false }` → keeps `enabled = false`, every new key gets its default (Task 1 test `upgrades a 0.1.0 save`).
2. Garbage numbers in the DB: string `"60"`, `45`, `0`, `9999`, NaN, count `2.5`, `-3` → default for non-numbers/NaN, otherwise clamp then round to nearest step, ties up (Task 1 tests `clamps and rounds numbers`, `replaces non-numbers and NaN`).
3. Accept lowers `reminderCount` below the reminders already due mid-series → the pending reminder still fires, then the series ends (Task 1 test `ends after the pending reminder when the new count is used up`).
4. Buff state unreadable (`hasBuff == nil`) when a reminder comes due → skipped silently but counted, series continues per count (Task 1 test `skips but counts when buffs cannot be read`).
5. `/peckish on|off` while the window is open with an edited draft → only the "Snack alerts on" box changes; other draft edits survive (Task 3, manual check, listed in final in-game checks).

---

### Task 1: Core — settings, quiet toggles, reminder series, parseCommand

**Files:**
- Modify: `src/Core.lua`
- Test: `spec/Core_spec.lua`

**Interfaces:**
- Produces (all on `ns.Core`):
  - `Core.DEFAULTS` — table with the seven defaults above. Callers must not mutate it.
  - `Core.normalizeSettings(db) -> table` — if `db` is not a table, start from `{}`. Fills/fixes every key of `DEFAULTS` in place and returns the same table. Booleans: non-boolean → default. Numbers: non-number or NaN → default; else clamp to range, then round to nearest step (interval step 30, count step 1), ties round up. Unknown keys are left alone.
  - `Core.canSpeak(state, settings) -> boolean` — `state = { dead, resting }`; true iff `settings.enabled` and not (`state.dead` and `settings.quietWhenDead`) and not (`state.resting` and `settings.quietWhenResting`).
  - `Core.onAuraChange(tracker, state, settings) -> { announce, arm, cancel }` — `state = { hasBuff, dead, resting }`. Same as today except: `arm` is true on falloff only when `settings.enabled and settings.remindersOn`; `announce` on falloff when `Core.canSpeak(state, settings)` (independent of `remindersOn`).
  - `Core.keepsSeries(settings) -> boolean` — `settings.enabled and settings.remindersOn`. Init cancels the series when this is false (on `/peckish off` and on Accept).
  - `Core.newSeries() -> { due = 0 }`.
  - `Core.reminderDue(series, state, settings) -> { print, again }` — increments `series.due` first. If `state.hasBuff == true` or not `Core.keepsSeries(settings)`: `{ print=false, again=false }`. Otherwise `print = state.hasBuff == false and Core.canSpeak(state, settings)`, `again = settings.remindUntilFed or series.due < settings.reminderCount`.
  - `Core.formatInterval(seconds) -> string` — `30`→`"30 s"`, `60`→`"1 min"`, `150`→`"2 min 30 s"`, `600`→`"10 min"`.
  - `Core.controlStates(draft) -> { interval, count, untilFed }` booleans meaning "enabled": `interval = untilFed = draft.remindersOn`, `count = draft.remindersOn and not draft.remindUntilFed`.
  - `Core.parseCommand(msg)` — `nil`, `""` or whitespace → `"open"`; `on`/`off` (trimmed, case-insensitive) → that; anything else → `"status"`.
  - Remove `Core.REMINDER_DELAY` and `Core.shouldRemind` (replaced by `reminderDue`). `newTracker`, `baseline`, `reset`, `loadedMessage` unchanged.

- [ ] **Step 1: Write the failing tests** in `spec/Core_spec.lua`. Replace the `ctx` helper with `state(over)` (defaults `{ hasBuff=false, dead=false, resting=false }`) and `settings(over)` (a copy of `Core.DEFAULTS` with overrides). Port the existing `onAuraChange` tests to `(tracker, state, settings)`; "addon is off" uses `settings({ enabled = false })`. Delete the `shouldRemind` block. Add:

```lua
describe("normalizeSettings", function()
	it("returns all defaults for nil or a non-table", function()
		assert.same(Core.DEFAULTS, Core.normalizeSettings(nil))
		assert.same(Core.DEFAULTS, Core.normalizeSettings("x"))
	end)
	it("upgrades a 0.1.0 save", function()
		local db = { enabled = false }
		local out = Core.normalizeSettings(db)
		assert.equal(db, out) -- same table, fixed in place
		assert.is_false(out.enabled)
		assert.is_true(out.quietWhenDead); assert.is_true(out.quietWhenResting)
		assert.is_true(out.remindersOn); assert.is_false(out.remindUntilFed)
		assert.equal(60, out.reminderInterval); assert.equal(1, out.reminderCount)
	end)
	it("clamps and rounds numbers", function()
		local n = function(i, c) return Core.normalizeSettings({ reminderInterval = i, reminderCount = c }) end
		assert.equal(60, n(45, 1).reminderInterval)   -- tie rounds up
		assert.equal(30, n(44, 1).reminderInterval)
		assert.equal(30, n(0, 1).reminderInterval)
		assert.equal(600, n(9999, 1).reminderInterval)
		assert.equal(3, n(60, 2.5).reminderCount)
		assert.equal(1, n(60, -3).reminderCount)
		assert.equal(10, n(60, 99).reminderCount)
	end)
	it("replaces non-numbers and NaN", function()
		local out = Core.normalizeSettings({ reminderInterval = "60", reminderCount = 0/0, quietWhenDead = "no" })
		assert.equal(60, out.reminderInterval); assert.equal(1, out.reminderCount)
		assert.is_true(out.quietWhenDead)
	end)
	it("does not let callers mutate DEFAULTS through the result", function()
		Core.normalizeSettings(nil).reminderCount = 7
		assert.equal(1, Core.DEFAULTS.reminderCount)
	end)
end)
```

`canSpeak`: true by default; false when dead / resting / off; true when dead with `quietWhenDead=false`; true when resting with `quietWhenResting=false`.

`onAuraChange` additions: falloff with `remindersOn=false` → `{ announce=true, arm=false, cancel=false }`; falloff while resting with `quietWhenResting=false` → `announce=true`.

`reminderDue` (fresh `Core.newSeries()` each):
- `reproduces v0.1.0 with defaults`: first due → `{ print=true, again=false }`.
- `skips but counts when dead or resting`: defaults, `state({ dead=true })` → `{ print=false, again=false }`, `series.due == 1`.
- `skips but counts when buffs cannot be read`: `hasBuff=nil`, count 2 → `{ print=false, again=true }`.
- `stops silently when fed again`: `hasBuff=true`, count 3 → `{ print=false, again=false }`.
- `runs reminderCount times`: count 3 → `again` is true, true, false.
- `keeps going until fed`: `remindUntilFed=true`, count 1 → `again` true on dues 1..20.
- `stops when the addon or reminders are off`: `enabled=false` and separately `remindersOn=false` → `{ print=false, again=false }`.
- `ends after the pending reminder when the new count is used up`: count 5, two dues, then settings count 1 → third due `{ print=true, again=false }`.

`keepsSeries`: true for defaults, false with `enabled=false`, false with `remindersOn=false`.

`formatInterval`: the four values above plus `90`→`"1 min 30 s"`.

`controlStates`: defaults → all true; `remindUntilFed=true` → `count=false`, others true; `remindersOn=false` → all false.

`parseCommand`: `""`, `nil`, `"   "` → `"open"`; `"toggle"` → `"status"`; existing on/off cases kept.

- [ ] **Step 2: Run `busted` — expect failures** (missing functions, changed signatures).
- [ ] **Step 3: Implement the Interfaces above in `src/Core.lua`.** Keep the header comment style; update it to point at PRD section 3. `normalizeSettings` iterates `DEFAULTS` with a small per-key spec table `{ min, max, step }` for the two numbers. Rounding: `math.floor(x / step + 0.5) * step` after clamping.
- [ ] **Step 4: Run `busted` and `luacheck .` — expect all pass.** (Init.lua will still call removed functions; luacheck does not catch that — Task 2 fixes it. Do not touch Init.lua here.)
- [ ] **Step 5: Commit** `git add src/Core.lua spec/Core_spec.lua; git commit -m "Core: settings, quiet toggles and reminder series decisions"`

### Task 2: Init — settings in the DB, reminder series, slash command

**Files:**
- Modify: `src/Init.lua`, `.luacheckrc` (only if a new API is used)

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces on `ns`: `ns.getSettings() -> table` (the normalised `FeelingPeckishDB`, or a normalised fresh table before `ADDON_LOADED`); `ns.applySettings(draft)` (copies every key of `Core.DEFAULTS` from draft into `FeelingPeckishDB`, normalises, cancels the series if `not Core.keepsSeries(settings)`; prints nothing). Consumes from Task 3 at call time only: `ns.Options.Toggle()` and `ns.Options.SyncEnabled(enabled)`; guard with `if ns.Options then`.

- [ ] **Step 1: ADDON_LOADED** — `FeelingPeckishDB = Core.normalizeSettings(FeelingPeckishDB)`.
- [ ] **Step 2: Context** — `context()` returns `{ hasBuff, dead, resting }`; `isEnabled()` becomes `ns.getSettings().enabled`. `checkAuras` calls `Core.onAuraChange(tracker, context(), ns.getSettings())`.
- [ ] **Step 3: Series** — module locals `reminder` (timer) and `series`. `cancelSeries()` cancels the timer and clears both. `armSeries()` = `cancelSeries()`, `series = Core.newSeries()`, `scheduleReminder()`. `scheduleReminder()` = `C_Timer.NewTimer(ns.getSettings().reminderInterval, onReminderDue)`. `onReminderDue` sets `reminder = nil`, calls `Core.reminderDue(series, context(), ns.getSettings())`, prints `REMINDER_PREFIX .. pickPhrase()` if `print`, schedules again if `again`, else `series = nil`. `result.cancel` → `cancelSeries()`, `result.arm` → `armSeries()`. Accept leaves a pending timer alone (later reminders read the new settings).
- [ ] **Step 4: Slash** — `"open"` → `ns.Options.Toggle()`; `"on"`/`"off"` as today (off uses `cancelSeries()`), then `ns.Options.SyncEnabled(enabled)`; `"status"` prints `"<on|off>. Usage: /peckish opens settings, /peckish on, /peckish off"`.
- [ ] **Step 5: Verify** — PowerShell: `luacheck .; busted`. Expect 0 warnings, all pass. Also `rg "shouldRemind|REMINDER_DELAY" src` → no hits.
- [ ] **Step 6: Commit** `git commit -am "Init: settings DB, reminder series and /peckish opens settings"`

### Task 3: Options window

**Files:**
- Create: `src/Options.lua`
- Modify: `FeelingPeckish.toc` (add `src\Options.lua` after `src\Core.lua`, before `src\Init.lua`), `.luacheckrc`

**Interfaces:**
- Consumes: `ns.Core.formatInterval`, `ns.Core.controlStates`, `ns.Core.DEFAULTS` (key list), `ns.getSettings()`, `ns.applySettings(draft)` (both resolved at call time, they are defined later in load order).
- Produces: `ns.Options = { Toggle = fn(), SyncEnabled = fn(enabled) }`.

Decisions:
- Frame: `CreateFrame("Frame", "FeelingPeckishOptionsFrame", UIParent, "BasicFrameTemplateWithInset")`, built on first `Toggle()`. ~300×380, `DIALOG` strata, centred, `SetMovable`, `EnableMouse`, `RegisterForDrag("LeftButton")` with `StartMoving`/`StopMovingOrSizing`, `SetClampedToScreen(true)`. Title "FeelingPeckish" in the template's title area (`frame.TitleText` if present, else own font string). The template's `CloseButton` is the ✕. `tinsert(UISpecialFrames, "FeelingPeckishOptionsFrame")` once. Position not saved.
- Checkboxes: `UICheckButtonTemplate` with own `GameFontHighlight` label font string (don't rely on the template's `.Text`/`.text`). Section headers in `GameFontNormal`.
- Sliders: plain `CreateFrame("Slider", nil, frame)` horizontal, thumb `Interface\Buttons\UI-SliderBar-Button-Horizontal`, a thin background texture, `SetObeyStepOnDrag(true)` when the method exists; Every 30–600 step 30, How many 1–10 step 1; value label right of the name, via `Core.formatInterval` for Every and plain number for How many. No slider template (OptionsSliderTemplate is not reliably present).
- Draft: `OnShow` copies `ns.getSettings()` (keys of `Core.DEFAULTS`) into a fresh draft and sets every control. Controls write only into the draft. `OnHide` drops nothing explicitly — the next `OnShow` rebuilds the draft, which is how Close/✕/Escape discard.
- Greying: after any change, apply `Core.controlStates(draft)`: disabled control → `:Disable()` on check buttons, `:EnableMouse(false)` + `:SetAlpha(0.4)` on sliders, label colour grey (0.5,0.5,0.5) vs normal (1,1,1).
- Buttons: `UIPanelButtonTemplate` "Accept" and "Close", bottom right, ~90×22. Accept → `ns.applySettings(draft)` then `frame:Hide()`. Close → `frame:Hide()`.
- `Toggle()` → build if needed, then show or hide. `SyncEnabled(enabled)` → if the frame exists and is shown, set `draft.enabled` and the box only.
- No protected API, no `SetPropagateKeyboardInput`, no combat checks needed.

- [ ] **Step 1: Write `src/Options.lua`** per the decisions above, header `local _, ns = ...`.
- [ ] **Step 2: Add to `.toc`; `git add src/Options.lua`.**
- [ ] **Step 3: `.luacheckrc`** — `globals` gains `FeelingPeckishOptionsFrame`; `read_globals` gains `UIParent`, `UISpecialFrames`, `tinsert` (or use `table.insert` and skip it) and any other global the file reads.
- [ ] **Step 4: Verify** — PowerShell `luacheck .; busted`: 0 warnings, all pass.
- [ ] **Step 5: Commit** `git commit -m "Options: settings window"`

### Task 4: Docs

**Files:** Modify `PRD.md`, `CHANGELOG.md`, `README.md`

- [ ] **Step 1: PRD.md** — status line mentions the unreleased settings window; section 1 and goals: reminder is configurable (default once after 60 s); remove the "options panel / settings beyond on/off" non-goal, replace "no UI" with "one small settings window, nothing else"; non-goals add minimap button, Interface options entry, profiles, editing phrases. 3.2: table driven by the toggles. 3.3: series rules from the design's "Rules" section, including counted skips, until-fed, cancel rules, and that Accept keeps the pending reminder's time and applies the new settings from the next one on. New 3.8 "Settings window" with the layout and behaviour from the design. 3.6: `/peckish` opens/closes the window, new usage line. 3.7: full settings table with defaults and valid ranges, normalisation rule. 4.1: add `src/Options.lua`; globals list adds `FeelingPeckishOptionsFrame`. 4.3: add the six design checks. Roadmap: drop "A configurable reminder delay" from later ideas.
- [ ] **Step 2: CHANGELOG.md** under `## [Unreleased]`: settings window via `/peckish`; quiet-while-dead / quiet-while-resting toggles; repeating reminders (interval, count, until you eat); defaults unchanged from 0.1.0.
- [ ] **Step 3: README.md** — intro "no UI" → "one small settings window"; commands table adds `/peckish` → opens settings; layout unchanged.
- [ ] **Step 4: Verify** `luacheck .; busted` still pass; commit `git commit -am "Docs: settings window in PRD, changelog and README"`.
