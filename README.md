# FeelingPeckish

A World of Warcraft: Forever addon that notices when your "Well Fed" food buff
runs out and prints a silly message in your own chat frame, plus one reminder
60 seconds later if you still have not eaten. Only you see the messages;
nothing is ever sent to a chat channel. No UI, no libraries.

Status: v0.1.0, first release for in-game testing. See [PRD.md](PRD.md) for the design.

## Commands

| Command | What it does |
|---------|--------------|
| `/peckish on` | Turn the messages on |
| `/peckish off` | Turn the messages off |

The setting is saved per account in `FeelingPeckishDB`.

## Install (players)

1. Download the latest `FeelingPeckish-<version>-forever.zip` from the
   [Releases](../../releases) page.
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up
   with `...\AddOns\FeelingPeckish\FeelingPeckish.toc`.
3. Restart the game or type `/reload`.

Use the Releases zip rather than GitHub's "Code > Download ZIP" button: the
release has the version stamped in and leaves out the development files.

## Development

### Tools

- Git and the GitHub CLI
- VS Code with the extensions in `.vscode/extensions.json`
- LuaJIT and LuaRocks (Lua 5.1, same as the game)
- `luarocks install luacheck` and `luarocks install busted`
- Git Bash (comes with Git for Windows) for the scripts in `scripts/`

### Build

In VS Code press `Ctrl+Shift+B` (task "Build and install"), or from Git Bash:

```bash
scripts/build.sh
```

Each build runs the same packager as a release, then:

1. writes `.release/FeelingPeckish-<version>.zip`, which holds one
   `FeelingPeckish` folder to unzip into `Interface\AddOns`, and
2. replaces `Interface\AddOns\FeelingPeckish` in your game with the build.
   Type `/reload` in game to load it.

`scripts/build.sh --no-install` (task "Build zip only") skips step 2. If your
game is not in the default folder, set `WOW_ADDONS_DIR` to your `AddOns` path.

The version is the git tag on a tagged commit, or the short commit hash
otherwise. New files must be `git add`ed before they appear in a build; the
script warns about any that are not.

### Everyday checks

```bash
luacheck .
busted
```

In VS Code these are the "Lint and test" task. CI runs the same two commands on
every push and pull request.

### Layout

| Path | What it is |
|------|------------|
| `FeelingPeckish.toc` | Addon manifest: load order, version, SavedVariables |
| `src/` | Addon code. Pure logic files have no WoW API calls and are unit tested |
| `spec/` | busted unit tests |
| `scripts/` | Developer scripts (not shipped) |
| `.pkgmeta` | Packager config: files to leave out of the zip |

### Releasing

1. Move the `Unreleased` notes in `CHANGELOG.md` under a new version heading.
2. Commit, then tag and push:

   ```bash
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin main --follow-tags
   ```

3. The Release workflow builds the zip and attaches it to a GitHub release.

## Licence

MIT. See [LICENSE](LICENSE).
