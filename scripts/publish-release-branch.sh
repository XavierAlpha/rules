#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
PUBLISH_BRANCH="${PUBLISH_BRANCH:-release}"

if [[ ! -d "$DIST_DIR" || ! -f "$DIST_DIR/manifest.json" ]]; then
  printf 'error: build output not found in %s\n' "$DIST_DIR" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  printf 'error: publish script must run inside a git checkout\n' >&2
  exit 1
fi

publish_copy="$(mktemp -d)"
trap 'rm -rf "$publish_copy"' EXIT
cp -a "$DIST_DIR/." "$publish_copy/"
rm -f "$publish_copy/build-summary.md"

cd "$ROOT_DIR"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

temp_branch="__ruleset_publish_${GITHUB_RUN_ID:-local}_$RANDOM"
git checkout --orphan "$temp_branch"

find "$ROOT_DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$publish_copy/." "$ROOT_DIR/"

git add -A
git commit -m "build: sing-box rulesets ${GITHUB_SHA:-local}" >/dev/null
git push --force origin "HEAD:refs/heads/${PUBLISH_BRANCH}"
printf 'published generated files to branch %s\n' "$PUBLISH_BRANCH"
