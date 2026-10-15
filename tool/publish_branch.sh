#!/usr/bin/env bash
# Force-pushes the contents of a folder to an orphan branch so CI results
# (APK, reports, screenshots) can be fetched with plain git.
set -e
SRC="$1"; BRANCH="$2"
TMP=$(mktemp -d)
cp -r "$SRC"/. "$TMP"/ 2>/dev/null || true
cd "$TMP"
git init -q -b "$BRANCH"
git config user.name "formflow-ci"
git config user.email "formflow-ci@users.noreply.github.com"
git add -A
git commit -qm "CI results for ${GITHUB_SHA:-local}" || git commit -q --allow-empty -m "empty"
git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
echo "published to $BRANCH"
