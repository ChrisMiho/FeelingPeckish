# FeelingPeckish — Product requirements

Status: v0.2.0 released (2026-11-10), adding the settings window (sections 3.2,
3.3, 3.6 to 3.8). See section 4.3 for in-game testing.

## 1. What it is

A tiny joke addon for World of Warcraft: Forever. When your food buff
("Well Fed") falls off, it prints a silly message in your own chat frame. If
you still have not eaten a minute later, it nags you once more. The reminder
is configurable in one small settings window: how often, how many times, or
until you eat. That is all.

Target client: WoW Forever (`_forever_` install, Interface 16001, modern
retail API such as `C_UnitAuras` and `C_Timer`). Lua 5.1.

## 2. Goals and non-goals

Goals
- Notice the moment Well Fed falls off and say something funny about it.
- Remind the player if they still have not eaten. By default: once, 60
  seconds later. The player can change the interval and the count, or repeat
  until they eat.
- Stay out of the way: one small settings window and nothing else, no messages
  when it would be silly or annoying.
- Every rule that decides when the addon speaks is a toggle or slider in that
  window. The defaults behave exactly like v0.1.0.
- Settings, including the on/off switch, survive `/reload` and logout.

Non-goals
- Sending anything to a chat channel. No `/s`, `/e`, party, raid, guild or
  whisper. Messages go only to the player's own chat frame. Addons cannot
  auto-post to say or yell outside instances anyway, and the joke is for the
  player, not their neighbours.
- A minimap button, an Interface options entry, profiles, or any window other
  than the one settings window.
- Editing the phrases or changing the message colour.
- Libraries or dependencies (no Ace, no LibStub).
- Telling the player which food to eat, or tracking other buffs.

## 3. Behaviour

### 3.1 Detecting the food buff

- The player "has the buff" when any helpful aura on unit `player` is named
  exactly `Well Fed`.
- Listen to `UNIT_AURA` for unit `"player"` only. On each event, one frame
  later (`C_Timer.After(0)`, so the dead state has settled after a death and
  a burst of events is handled once), rescan the player's helpful buffs and
  compare with the last known state.
- Only the transition **had it -> lost it** triggers a falloff. Logging in,
  `/reload` or zoning without the buff never prints anything.
- On `PLAYER_ENTERING_WORLD` (login, `/reload` and every loading screen)
  record the current state as the starting point without printing.
- On `PLAYER_LEAVING_WORLD` forget the state, so a loading screen that
  briefly reports no buffs only sets a new baseline.
- Buffs are read with `C_UnitAuras.GetAuraDataByIndex`, falling back to
  `UnitBuff` if the client lacks it. Newer clients can hide auras as "secret"
  (possible in combat): `GetAuraDataByIndex` then raises an error for addon
  code, or an aura name is a secret value (`issecretvalue`). Either way the
  error is caught (no error popup), the state is unknown and nothing is
  decided until the next readable change.
- v1 limitation: matching is by English name, so non-English clients will not
  detect the buff. A later version may match by spell ID list or icon.

### 3.2 Suppression

A message (falloff or reminder) is skipped when any of these is true at the
moment it would print. The two quiet rules are toggles (section 3.7), both on
by default:

| Condition | API | Setting | Reason |
|-----------|-----|---------|--------|
| Addon is off | `FeelingPeckishDB.enabled == false` | `enabled` | Player asked for quiet |
| Dead or ghost | `UnitIsDeadOrGhost("player")` | `quietWhenDead` | Buffs drop on death; not funny |
| Resting | `IsResting()` | `quietWhenResting` | In a city or inn you are probably about to eat |

A quiet toggle that is unticked removes that row: the message prints even
while dead (or resting).

### 3.3 Reminders

Reminders form a series. With the default settings the series is one
reminder 60 seconds after the falloff, exactly as in v0.1.0.

- On a falloff (buff lost while the addon is on and `remindersOn`), start a
  series: the first reminder is due `reminderInterval` seconds later, using
  `C_Timer.NewTimer`, **even if the falloff message itself was suppressed**
  for being dead or resting. Each reminder checks the conditions when it
  comes due, so a player who dies, releases and runs out of town without
  eating still gets nagged.
- Each time a reminder comes due:
  - If the player has Well Fed again, the series ends silently.
  - Otherwise, if no suppression applies, print `Still peckish: <phrase>`.
    If one applies, skip the message silently.
  - Either way it counts toward `reminderCount`. A skipped reminder is not
    made up later. (With one reminder, that is v0.1.0: one skipped reminder
    means no reminder.)
  - If `remindUntilFed` is on, or fewer than `reminderCount` reminders have
    come due, schedule the next one `reminderInterval` seconds later.
    Otherwise the series ends.
  - If the buff state cannot be read at that moment (hidden "secret" aura
    names), nothing is printed, but the reminder still counts.
- Cancel the series when the buff comes back, when the addon is turned off
  (by command or by Accept), when a new falloff restarts it, or when Accept
  turns `remindersOn` off. Only one series and one timer exist at a time.
- Accept while a series is running (section 3.8): the pending reminder keeps
  its time. Later reminders use the new interval, count and until-fed
  settings. If the new count is already used up, the series ends after the
  pending reminder. Accept turning the addon or reminders off cancels the
  series.
- Loading screens, login and `/reload` only set a baseline and never start a
  series. A `/reload` drops any running series.

### 3.4 Messages

- Printed with `DEFAULT_CHAT_FRAME:AddMessage`, prefixed with a coloured tag,
  e.g. `|cffffa500FeelingPeckish:|r <phrase>`.
- Falloff: `FeelingPeckish: <phrase>`.
- Reminder: `FeelingPeckish: Still peckish: <phrase>`.
- Both draw from the same 50-phrase pool (section 5), chosen at random, never
  the same phrase twice in a row (the picker remembers the last index and
  rerolls or skips it).

### 3.5 Loaded message

Once per login or `/reload` (`PLAYER_LOGIN`, not every loading screen), print
one line so the player knows the addon is running, with the version from the
`.toc` and the current state:

- On: `FeelingPeckish: loaded v0.1.0. Snack alerts are on. /peckish off to mute.`
- Off: `FeelingPeckish: loaded v0.1.0. Snack alerts are off. /peckish on to arm them.`

It prints even when the addon is off. In a dev build the version is the
commit hash.

### 3.6 Commands

| Command | Effect | Confirmation printed |
|---------|--------|----------------------|
| `/peckish on` | Enable, save | `FeelingPeckish: on. Snack alerts armed.` |
| `/peckish off` | Disable, save, cancel any running reminder series | `FeelingPeckish: off. Starve in peace.` |
| `/peckish` (empty or only spaces) | Open the settings window, or close it if it is open | None |
| anything else | Nothing changes | `FeelingPeckish: <on or off>. Usage: /peckish opens settings, /peckish on, /peckish off` |

Arguments are trimmed and case-insensitive. If the settings window is open
when `/peckish on` or `/peckish off` runs, its "Snack alerts on" box updates
to match.

### 3.7 Saved settings

SavedVariables: `FeelingPeckishDB`. Defaults reproduce v0.1.0.

| Key | Type | Default | Valid |
|-----|------|---------|-------|
| `enabled` | boolean | `true` | |
| `quietWhenDead` | boolean | `true` | |
| `quietWhenResting` | boolean | `true` | |
| `remindersOn` | boolean | `true` | |
| `reminderInterval` | number (seconds) | `60` | 30 to 600, multiple of 30 |
| `reminderCount` | number | `1` | 1 to 10, whole number |
| `remindUntilFed` | boolean | `false` | |

On `ADDON_LOADED` for this addon every field is normalised:

- Missing or invalid (wrong type) falls back to the default.
- A number is clamped to its range, then rounded to the nearest valid step
  (ties round up).
- A non-number, or NaN, falls back to the default.
- Unknown extra keys are left alone.

Settings change only when the player presses Accept (section 3.8) or runs
`/peckish on` or `/peckish off`.

### 3.8 Settings window

Opened by `/peckish`. Built plain (`CreateFrame` and Blizzard templates, no
libraries), on first open. Top to bottom:

- Title "FeelingPeckish" and a close box.
- Tick box **Snack alerts on** (`enabled`).
- Header **Stay quiet while**: tick boxes **Dead or a ghost**
  (`quietWhenDead`) and **Resting (city or inn)** (`quietWhenResting`).
- Header **Reminders**:
  - Tick box **Send reminders** (`remindersOn`).
  - Slider **Every**: 30 s to 10 min in 30 s steps, shown as "30 s",
    "1 min", "2 min 30 s".
  - Slider **How many**: 1 to 10.
  - Tick box **Keep reminding until I eat** (`remindUntilFed`). When ticked,
    the "How many" slider is greyed out and disabled.
  - When "Send reminders" is unticked, both sliders and the "until I eat" box
    are greyed out and disabled.
- Buttons **Accept** and **Close**, bottom right.

Behaviour:

- Opening loads the saved settings into the controls. Edits are a draft.
  Nothing changes until **Accept**.
- **Accept** saves the draft to `FeelingPeckishDB`, applies it and closes the
  window. Series rules are in section 3.3.
- **Close**, the close box and Escape (the frame is in `UISpecialFrames`)
  discard the draft and close without asking.
- It looks like a standard game dialog, is movable by dragging and is
  clamped to the screen. Its position is not saved.
- It can be opened in combat: it uses only plain frames and no protected API.

## 4. Engineering

### 4.1 File layout

| File | Role |
|------|------|
| `FeelingPeckish.toc` | Interface 16001, `## SavedVariables: FeelingPeckishDB`, loads the files below in order |
| `src/Phrases.lua` | The 50 phrases and the no-repeat random picker. Pure; the random source is injectable for tests |
| `src/Core.lua` | Pure logic. Settings defaults and normalisation, the quiet rules, the reminder-series decisions (arm on falloff; print, repeat or stop when a reminder is due), control greying, interval text and `/peckish` argument parsing. No WoW API calls |
| `src/Options.lua` | Game code: the settings window. Builds it on first open, holds the draft, calls `ns.applySettings` on Accept. Loaded after `Core.lua`, before `Init.lua` |
| `src/Init.lua` | Thin glue: event frame, `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD`, `UNIT_AURA`, `C_Timer`, slash command, SavedVariables, printing |
| `spec/` | busted tests for `Phrases` and `Core` |

Load order in the `.toc`: `Phrases`, `Core`, `Options`, `Init`.

Every file starts with `local addonName, ns = ...` (or `local _, ns = ...`)
and shares through `ns`. No globals except `FeelingPeckishDB`, the
`SLASH_FEELINGPECKISH1` / `SlashCmdList.FEELINGPECKISH` pair the slash
command needs, and the settings window's frame name
`FeelingPeckishOptionsFrame`. (Named Blizzard templates also create child
globals with that prefix, such as the frame's close button.)

### 4.2 Tooling and release

- luacheck and busted, run in CI on GitHub Actions for every push and PR.
- `scripts/build.sh` runs the BigWigsMods packager, writes the zip to
  `.release/`, and installs into
  `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\FeelingPeckish`.
- Releases: push a `v*` tag; the Release workflow attaches the zip to a GitHub
  release.
- Repo: github.com/ChrisMiho/FeelingPeckish (public, MIT).

### 4.3 What only a human can test in game

1. Eat food, get Well Fed, then right-click the buff off (fastest) or wait it
   out: a falloff message appears in your chat frame only.
2. With default settings, stay unfed for 60 s: exactly one `Still peckish:`
   reminder, and no more after it.
3. Lose the buff, eat again within 60 s: no reminder.
4. With default settings, lose the buff in a city or inn: no falloff message;
   leave town before 60 s is up and the reminder appears; stay and it does not.
5. With default settings, die with the buff: no message; still dead or a
   ghost at 60 s: no reminder.
6. `/reload` or log in without the buff: nothing prints.
7. `/peckish off`, `/reload`, lose the buff: silent. `/peckish on` restores it.
8. `/peckish off` while a reminder is pending: the reminder never fires.
9. Watch several falloffs: no phrase repeats back-to-back.
10. Log in or `/reload`: one `loaded` line with the version and on/off state;
    zoning through a loading screen does not print it again.
11. `/peckish` opens the window with the v0.1.0 defaults. Escape, the close
    box and Close discard changes. Accept saves and closes.
12. Untick "Resting", Accept, lose Well Fed in a city: the message prints.
13. Set the interval to 30 s and the count to 3, Accept: three reminders 30 s
    apart, then silence.
14. Tick "Keep reminding until I eat": reminders keep coming until you eat,
    then stop.
15. Untick "Send reminders": only the falloff message prints.
16. `/reload`: all settings are kept. `/peckish off` with the window open
    unticks "Snack alerts on".

## 5. Phrases

Exactly 50. Keep them short (under about 70 characters), PG and original.
Add or swap freely later, but keep the count and keep them unique.

1. Your Well Fed just wandered off. Probably to find a snack.
2. Buff gone. Stomach now filing a formal complaint.
3. The food buff has left the building. Bring cheese.
4. Your tummy rumbled loud enough to pull the next pack.
5. Well Fed? More like Well Faded. Eat something.
6. A murloc heard your stomach and replied: Mrglglgl.
7. Snack o'clock. The clock is never wrong.
8. You are now at 0% snack. Please recharge.
9. Your stomach has entered combat.
10. Somewhere, a mage is conjuring bread you are not eating.
11. Your buff expired. So did your patience. Eat.
12. Feast time? Feast time. Someone drop a fish feast.
13. Hunger debuff applied. Duration: until you eat.
14. That growl wasn't a worgen. That was you.
15. Your inner gnome demands a sandwich.
16. Warning: snack reserves critically low.
17. Your stomach just rolled Need on everything.
18. No buff, no glory. Find a picnic.
19. Even the Defias take a lunch break. Just saying.
20. Your belly is casting Rumble. It cannot be interrupted.
21. Peckish detected. Deploy the cheese wheel.
22. A wild hunger appears! It's super effective.
23. The bread is calling. Answer the bread.
24. Your Well Fed buff has respawned... somewhere else.
25. Out of food buff. Into snack territory.
26. Stomach aggro lost. Pull it back with pie.
27. Grumble grumble. That's Common for "feed me."
28. Your stats are fine. Your snack stats are not.
29. Have you tried eating it? The food. Eat the food.
30. The innkeeper would be very disappointed in you.
31. Hungry like a murloc at a fish market.
32. Even conjured muffins look tempting right now.
33. Your belly just started its own guild. It's called Hungry.
34. Sit down. Unpack. Eat a mutton chop.
35. Time to raid the fridge. Need, not greed.
36. Your belly bar is empty. No addon can fill it.
37. Pro tip: food goes in the face.
38. Your stomach just whispered you. It said "rude."
39. Running on empty. Running on snacks would be better.
40. The cheese misses you. Go say hi.
41. Snack break! Doctor's orders. The doctor is a pandaren.
42. Your Well Fed fell off. Pick it up with a fork.
43. Feeling peckish? You look peckish. Eat a cracker.
44. Your hunger has reached raid-wipe levels.
45. Tasty fish? Spiced bread? Literally anything? Go.
46. A goblin would sell you lunch right now. At a markup.
47. Remember snacks? Snacks remember you.
48. Your stomach is now louder than the raid leader.
49. Buff down! Repeat, buff down! Requesting crumbs!
50. Somebody pass the Moonberry Juice and a sandwich.

Note: phrases 27 and 38 contain double quotes; escape them or use single-quoted
Lua strings.

## 6. Roadmap

| Version | Adds |
|---------|------|
| v0.1.0 | The original behaviour: one on/off switch and a single reminder after 60 s |
| v0.2.0 | Settings window, quiet toggles, repeating reminders |

Later ideas (not committed)
- Match Well Fed by spell ID or icon so non-English clients work.
- An optional sound with the falloff message.
- Seasonal phrase packs.
