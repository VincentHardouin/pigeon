#!/bin/sh
# Compares the CWA files our progress contract mirrors (document digest, payload, kosync API)
# with the versions pinned in .github/upstream.lock. Exits 1 and lists the changed files on drift.
# Usage: upstream-check.sh [--update]   (--update pins the current upstream versions)
set -e
REPO=crocodilestick/Calibre-Web-Automated
LOCK=$(dirname "$0")/../upstream.lock

TREE=$(gh api "repos/$REPO/git/trees/main?recursive=1" --jq '.tree[] | select(.type == "blob") | "\(.sha) \(.path)"')
CURRENT=$(cut -d' ' -f2 "$LOCK" | while read -r path; do
    echo "$TREE" | grep " $path\$" || echo "missing $path"
done)

if [ "$1" = --update ]; then
    echo "$CURRENT" > "$LOCK"
    exit 0
fi

CHANGED=$(echo "$CURRENT" | diff "$LOCK" - | sed -n 's/^> [^ ]* //p')
[ -z "$CHANGED" ] && { echo "No drift."; exit 0; }
for path in $CHANGED; do
    echo "- [$path](https://github.com/$REPO/commits/main/$path)"
done
exit 1
