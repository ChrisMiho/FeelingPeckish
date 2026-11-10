# FeelingPeckish — Product requirements

Status: v0.1.0 released (2026-11-10) for in-game testing (section 4.3).

## 1. What it is

A tiny joke addon for World of Warcraft: Forever. When your food buff
("Well Fed") falls off, it prints a silly message in your own chat frame. If
you still have not eaten a minute later, it nags you once more. That is all.

Target client: WoW Forever (`_forever_` install, Interface 16001, modern
retail API such as `C_UnitAuras` and `C_Timer`). Lua 5.1.

## 2. Goals and non-goals

Goals
- Notice the moment Well Fed falls off and say something funny about it.
- Remind the player once, 60 seconds later, if they still have not eaten.
- Stay out of the way: no UI, no messages when it would be silly or annoying.
- One on/off switch that survives `/reload` and logout.

Non-goals
- Sending anything to a chat channel. No `/s`, `/e`, party, raid, guild or
  whisper. Messages go only to the player's own chat frame. Addons cannot
  auto-post to say or yell outside instances anyway, and the joke is for the
  player, not their neighbours.
- Any window, minimap button, options panel or settings beyond on/off.
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
  `UnitBuff` if the client lacks it. If an aura name is a hidden "secret"
  value (`issecretvalue`, possible in combat on newer clients), the state is
  unknown and nothing is decided until the next readable change.
- v1 limitation: matching is by English name, so non-English clients will not
  detect the buff. A later version may match by spell ID list or icon.

### 3.2 Suppression

A message (falloff or reminder) is skipped when any of these is true at the
moment it would print:

| Condition | API | Reason |
|-----------|-----|--------|
| Addon is off | `FeelingPeckishDB.enabled == false` | Player asked for quiet |
| Dead or ghost | `UnitIsDeadOrGhost("player")` | Buffs drop on death; not funny |
| Resting | `IsResting()` | In a city or inn you are probably about to eat |

### 3.3 Reminder

- On a falloff (buff lost while the addon is on), arm a single reminder
  60 seconds later with `C_Timer.NewTimer`, **even if the falloff message
  itself was suppressed** for being dead or resting. The reminder checks the
  conditions when it fires, so a player who dies, releases and runs out of
  town without eating still gets nagged.
- When the reminder fires: if the player still has no Well Fed and no
  suppression applies, print one reminder message. Otherwise do nothing.
- Exactly one reminder per falloff. It never repeats.
- Cancel the pending reminder when the buff comes back, when the addon is
  turned off, or when a new falloff re-arms it (only one timer exists at a
  time).

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
| `/peckish off` | Disable, save, cancel any pending reminder | `FeelingPeckish: off. Starve in peace.` |
| `/peckish` or anything else | Nothing changes | Current state (on/off) and usage: `/peckish on`, `/peckish off` |

Arguments are trimmed and case-insensitive.

### 3.7 Saved settings

- SavedVariables: `FeelingPeckishDB = { enabled = true }`.
- Created with defaults on `ADDON_LOADED` for this addon if missing; unknown or
  missing fields fall back to the default (on).

## 4. Engineering

### 4.1 File layout

| File | Role |
|------|------|
| `FeelingPeckish.toc` | Interface 16001, `## SavedVariables: FeelingPeckishDB`, loads the files below in order |
| `src/Phrases.lua` | The 50 phrases and the no-repeat random picker. Pure; the random source is injectable for tests |
| `src/Core.lua` | Pure state logic. Given buff present/absent, dead, resting, enabled and the previous state, returns what to print and whether to arm or cancel the reminder. No WoW API calls |
| `src/Init.lua` | Thin glue: event frame, `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD`, `UNIT_AURA`, `C_Timer`, slash command, SavedVariables, printing |
| `spec/` | busted tests for `Phrases` and `Core` |

Every file starts with `local addonName, ns = ...` and shares through `ns`.
No globals except `FeelingPeckishDB` and the `SLASH_FEELINGPECKISH1` /
`SlashCmdList.FEELINGPECKISH` pair the slash command needs.

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
2. Stay unfed for 60 s: exactly one `Still peckish:` reminder.
3. Lose the buff, eat again within 60 s: no reminder.
4. Lose the buff in a city or inn: no falloff message; leave town before 60 s
   is up and the reminder appears; stay and it does not.
5. Die with the buff: no message; still dead or a ghost at 60 s: no reminder.
6. `/reload` or log in without the buff: nothing prints.
7. `/peckish off`, `/reload`, lose the buff: silent. `/peckish on` restores it.
8. `/peckish off` while a reminder is pending: the reminder never fires.
9. Watch several falloffs: no phrase repeats back-to-back.
10. Log in or `/reload`: one `loaded` line with the version and on/off state;
    zoning through a loading screen does not print it again.

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
| v0.1.0 | Everything in sections 3 to 5 |

Later ideas (not committed)
- Match Well Fed by spell ID or icon so non-English clients work.
- A configurable reminder delay.
- An optional sound with the falloff message.
- Seasonal phrase packs.
