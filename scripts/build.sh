#!/usr/bin/env bash
# Build the addon exactly as a release would, then:
#   1. zip it as .release/FeelingPeckish-<version>.zip (one FeelingPeckish/
#      folder inside, ready to unzip into Interface\AddOns), and
#   2. install it into your game's AddOns folder.
#
# Usage (Git Bash):  scripts/build.sh            build, zip, install
#                    scripts/build.sh --no-install   build and zip only
#
# The AddOns folder defaults to the standard Forever install. Override it with
# the WOW_ADDONS_DIR environment variable.
set -euo pipefail

PACKAGER_VERSION="v2.6.1" # keep in step with .github/workflows/release.yml
ADDON="FeelingPeckish"
DEFAULT_ADDONS_DIR="/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"

install=1
for arg in "$@"; do
	case "$arg" in
		--no-install) install=0 ;;
		*) echo "Unknown option: $arg" >&2; exit 2 ;;
	esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# --- Packager (pinned) -------------------------------------------------------
mkdir -p .release
packager=".release/release.sh"
if [ ! -f "$packager" ] || [ "$(cat .release/.packager-version 2>/dev/null)" != "$PACKAGER_VERSION" ]; then
	echo "Downloading packager $PACKAGER_VERSION"
	curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_VERSION/release.sh" -o "$packager"
	echo "$PACKAGER_VERSION" > .release/.packager-version
fi

# The packager skips files git does not know about. Edits to tracked files are
# included; brand-new files need "git add" first.
untracked="$(git ls-files --others --exclude-standard)"
if [ -n "$untracked" ]; then
	echo "Warning: these new files are NOT in the build until you git add them:"
	echo "$untracked" | sed 's/^/  /'
fi

# -d: no upload. -z: we zip ourselves below, since Git Bash has no zip tool.
echo "Packaging..."
bash "$packager" -d -z > .release/packager.log 2>&1 || {
	cat .release/packager.log
	echo "Packaging failed" >&2
	exit 1
}

pkg=".release/$ADDON"
version="$(sed -n 's/^## Version: *//p' "$pkg/$ADDON.toc" | tr -d '\r')"
[ -n "$version" ] || { echo "Could not read version from $pkg/$ADDON.toc" >&2; exit 1; }

# --- Zip ---------------------------------------------------------------------
zipfile=".release/$ADDON-$version.zip"
rm -f "$zipfile"
if command -v zip > /dev/null 2>&1; then
	(cd .release && zip -qr "$(basename "$zipfile")" "$ADDON")
elif [ -x /c/Windows/System32/tar.exe ]; then
	# Windows' own tar (bsdtar) writes standard zip files with -a
	/c/Windows/System32/tar.exe -a -c -f "$zipfile" -C .release "$ADDON"
else
	echo "No zip tool found (need zip, or Windows tar.exe)" >&2
	exit 1
fi
echo "Zip:     $root/$zipfile"

# --- Install -----------------------------------------------------------------
if [ "$install" -eq 1 ]; then
	addons_dir="${WOW_ADDONS_DIR:-$DEFAULT_ADDONS_DIR}"
	if [ ! -d "$addons_dir" ]; then
		echo "AddOns folder not found: $addons_dir" >&2
		echo "Set WOW_ADDONS_DIR, or use --no-install." >&2
		exit 1
	fi
	target="$addons_dir/$ADDON"
	if [ -L "$target" ]; then
		echo "Refusing to install: $target is a link. Remove the link first." >&2
		exit 1
	fi
	rm -rf "$target"
	cp -r "$pkg" "$target"
	echo "Install: $target"
	echo "In game, type /reload to load the new build."
fi

echo "Built $ADDON $version"
