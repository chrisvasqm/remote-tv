#!/bin/sh
# Builds RemoteTV, tags it and publishes a GitHub release with English and
# Spanish notes made from the commits since the previous tag.
# Usage: scripts/release.sh v1.2.3      (run on an up-to-date, clean main)
set -eu
cd "$(dirname "$0")/.."

tag="${1:-}"
if ! printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "usage: scripts/release.sh vMAJOR.MINOR.PATCH (for example v0.1.0)" >&2
    exit 2
fi
if [ "$(git branch --show-current)" != main ]; then echo "Release from main." >&2; exit 1; fi
if [ -n "$(git status --porcelain)" ]; then echo "Commit or stash your changes first." >&2; exit 1; fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then echo "$tag already exists." >&2; exit 1; fi
git fetch -q origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then echo "main is not in sync with origin." >&2; exit 1; fi

notes="build/release-notes.md"
zip="build/RemoteTV-$tag.zip"
mkdir -p build
scripts/release-notes.sh > "$notes"

VERSION="${tag#v}" scripts/bundle.sh
rm -f "$zip"
ditto -c -k --keepParent build/RemoteTV.app "$zip"

git tag -a "$tag" -m "RemoteTV $tag"
git push -q origin "$tag"
gh release create "$tag" "$zip" --title "RemoteTV $tag" --notes-file "$notes"
