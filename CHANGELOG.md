# Changelog

All notable changes to this addon are listed here.
Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.1] - 2026-11-11

- Fix: no more "Auras cannot be accessed when secret while tainted by
  'FeelingPeckish'" Lua errors (seen in combat). While buffs are hidden the
  addon now just waits for the next change it can read.

## [0.2.0] - 2026-11-10

- A small settings window: type `/peckish` to open it.
- Toggles to stay quiet while dead or while resting.
- Repeating reminders: choose the interval and how many, or keep reminding
  until you eat.
- Defaults are unchanged from 0.1.0: nothing differs until you change a setting.

## [0.1.0] - 2026-11-10

- Project setup: build, lint, test and release tooling.
- A silly message in your chat frame when your Well Fed buff falls off, and one
  reminder 60 seconds later if you have not eaten. Quiet while dead or resting.
- `/peckish on` and `/peckish off`, saved between sessions.
- A "loaded" line in chat at login showing the version and whether alerts are on.
