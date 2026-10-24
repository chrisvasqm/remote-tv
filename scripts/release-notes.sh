#!/bin/sh
# Prints release notes in English and Spanish from the commits since the last
# vX.Y.Z tag (or since the first commit when there is none).
# Usage: scripts/release-notes.sh [<from-tag>] [<to-ref>]
#
# English comes from each commit's subject. Spanish comes from an "Es:" line in the
# commit body, so write one when committing; without it the English subject is used.
#   git commit -m "Add screen off" -m "Es: Agrega apagar la pantalla"
set -eu
cd "$(dirname "$0")/.."

to="${2:-HEAD}"
from="${1:-$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$to" 2>/dev/null || true)}"
range="${from:+$from..}$to"

# One record per commit: subject, a unit separator, then the body.
log=$(git log --no-merges --reverse --format='%s%x1f%b%x1e' "$range")

lines() {
    printf '%s' "$log" | awk -v lang="$1" 'BEGIN { RS = "\036"; FS = "\037" }
        {
            sub(/^\n+/, "", $1)
            if ($1 == "") next
            text = $1
            if (lang == "es") {
                n = split($2, body, "\n")
                for (i = 1; i <= n; i++) if (body[i] ~ /^Es: /) { text = substr(body[i], 5); break }
            }
            print "- " text
        }'
}

cat <<NOTES
## English

$(lines en)

## Español

$(lines es)
NOTES
