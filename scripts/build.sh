#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="${RULES_DIR:-${ROOT_DIR}/rules}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
TMP_DIR="${TMP_DIR:-${ROOT_DIR}/.tmp/build}"
PUBLISH_BRANCH="${PUBLISH_BRANCH:-release}"
export PROJECT_ROOT="$ROOT_DIR" RULES_DIR DIST_DIR PUBLISH_BRANCH

log() {
  printf '[build] %s\n' "$*"
}

if [[ ! -d "$RULES_DIR" ]]; then
  printf 'error: rules directory not found: %s\n' "$RULES_DIR" >&2
  exit 1
fi

rm -rf "$DIST_DIR" "$TMP_DIR"
mkdir -p "$DIST_DIR/source" "$DIST_DIR/srs" "$TMP_DIR/normalized" "$TMP_DIR/verify"

meta_file="$(bash "$ROOT_DIR/scripts/install-sing-box.sh")"
# shellcheck disable=SC1090
source "$meta_file"
export SING_BOX_VERSION SING_BOX_TAG SING_BOX_BIN SING_BOX_ASSET_URL SING_BOX_ASSET_DIGEST RULESET_VERSION_CURRENT

log "validating source files against RuleSetVersionCurrent=${RULESET_VERSION_CURRENT}"
python3 "$ROOT_DIR/scripts/validate-sources.py" "$RULES_DIR" --current-version "$RULESET_VERSION_CURRENT"

count=0
while IFS= read -r -d '' input; do
  rel="${input#${RULES_DIR}/}"
  if [[ "$rel" == "$input" ]]; then
    printf 'error: could not derive relative path for %s\n' "$input" >&2
    exit 1
  fi
  stem="${rel%.json}"
  source_out="$DIST_DIR/source/$rel"
  srs_out="$DIST_DIR/srs/${stem}.srs"
  normalized="$TMP_DIR/normalized/$rel"
  verify_json="$TMP_DIR/verify/${stem}.json"

  mkdir -p "$(dirname -- "$source_out")" "$(dirname -- "$srs_out")" "$(dirname -- "$normalized")" "$(dirname -- "$verify_json")"
  cp -p "$input" "$source_out"

  python3 "$ROOT_DIR/scripts/prepare-rule.py" "$input" "$normalized" --current-version "$RULESET_VERSION_CURRENT"
  log "compile $rel -> srs/${stem}.srs"
  "$SING_BOX_BIN" rule-set compile --output "$srs_out" "$normalized"
  test -s "$srs_out"

  # Verify that the generated binary is readable by the same latest stable compiler.
  "$SING_BOX_BIN" rule-set decompile --output "$verify_json" "$srs_out" >/dev/null
  python3 -m json.tool "$verify_json" >/dev/null
  count=$((count + 1))
done < <(find "$RULES_DIR" -type f -name '*.json' -print0)

if [[ "$count" -eq 0 ]]; then
  printf 'error: no JSON rule-set sources found under %s\n' "$RULES_DIR" >&2
  exit 1
fi

log "generating manifest, download bundles and checksums"
python3 "$ROOT_DIR/scripts/generate-metadata.py"
log "done: ${count} rule set(s), sing-box ${SING_BOX_VERSION}, compiler RuleSetVersionCurrent=${RULESET_VERSION_CURRENT}"
