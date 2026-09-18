#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${CACHE_ROOT:-${ROOT_DIR}/.cache/sing-box}"
META_FILE="${META_FILE:-${ROOT_DIR}/.cache/sing-box.env}"
API_ROOT="https://api.github.com/repos/SagerNet/sing-box"

log() {
  printf '[sing-box] %s\n' "$*" >&2
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

need curl
need tar
need python3

# Optional offline/local override. GitHub Actions does not set this; it is useful for
# reproducible local testing or environments that already provide a sing-box binary.
if [[ -n "${SING_BOX_BIN_OVERRIDE:-}" ]]; then
  binary="${SING_BOX_BIN_OVERRIDE}"
  if [[ ! -x "$binary" ]]; then
    printf 'error: SING_BOX_BIN_OVERRIDE is not executable: %s\n' "$binary" >&2
    exit 1
  fi
  if [[ -z "${RULESET_VERSION_CURRENT_OVERRIDE:-}" ]]; then
    printf 'error: RULESET_VERSION_CURRENT_OVERRIDE is required with SING_BOX_BIN_OVERRIDE\n' >&2
    exit 1
  fi
  actual_version="$($binary version | sed -nE 's/^sing-box version[[:space:]]+([^[:space:]]+).*/\1/p' | head -n1)"
  if [[ -z "$actual_version" ]]; then
    printf 'error: override binary failed sing-box version check\n' >&2
    exit 1
  fi
  version="${SING_BOX_VERSION:-$actual_version}"
  version="${version#v}"
  tag="v${version}"
  current_ruleset_version="${RULESET_VERSION_CURRENT_OVERRIDE}"
  mkdir -p "$(dirname -- "$META_FILE")"
  {
    printf 'SING_BOX_VERSION=%q\n' "$version"
    printf 'SING_BOX_TAG=%q\n' "$tag"
    printf 'SING_BOX_BIN=%q\n' "$binary"
    printf 'SING_BOX_ASSET_URL=%q\n' 'local-override'
    printf 'SING_BOX_ASSET_DIGEST=%q\n' 'local-override'
    printf 'RULESET_VERSION_CURRENT=%q\n' "$current_ruleset_version"
  } > "$META_FILE"
  log "using local override: sing-box ${actual_version}, RuleSetVersionCurrent=${current_ruleset_version}"
  printf '%s\n' "$META_FILE"
  exit 0
fi

headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

mkdir -p "$CACHE_ROOT" "$(dirname -- "$META_FILE")"
release_json="$(mktemp)"
trap 'rm -f "$release_json"' EXIT

if [[ -n "${SING_BOX_VERSION:-}" ]]; then
  version="${SING_BOX_VERSION#v}"
  tag="v${version}"
  log "resolving pinned stable release ${tag}"
  curl -fsSL "${headers[@]}" "${API_ROOT}/releases/tags/${tag}" -o "$release_json"
else
  log 'resolving latest stable release from GitHub'
  curl -fsSL "${headers[@]}" "${API_ROOT}/releases/latest" -o "$release_json"
  tag="$(python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
tag = data.get('tag_name')
if not isinstance(tag, str) or not tag:
    raise SystemExit('release JSON has no tag_name')
print(tag)
PY
)"
  version="${tag#v}"
fi

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os_name" in
  linux) platform='linux' ;;
  darwin) platform='darwin' ;;
  *) printf 'error: unsupported local OS: %s\n' "$os_name" >&2; exit 1 ;;
esac

machine="$(uname -m)"
case "$machine" in
  x86_64|amd64) arch='amd64' ;;
  aarch64|arm64) arch='arm64' ;;
  *) printf 'error: unsupported local architecture: %s\n' "$machine" >&2; exit 1 ;;
esac

asset_info="$(python3 - "$release_json" "$version" "$platform" "$arch" <<'PY'
import json, sys
path, version, platform, arch = sys.argv[1:]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
assets = data.get('assets') or []
names = [
    f'sing-box-{version}-{platform}-{arch}.tar.gz',
    f'sing-box-{version}-{platform}-{arch}-glibc.tar.gz',
]
for wanted in names:
    for asset in assets:
        if asset.get('name') == wanted and asset.get('browser_download_url'):
            print(asset['browser_download_url'])
            print(asset.get('digest') or '')
            raise SystemExit(0)
raise SystemExit('no matching sing-box archive in release assets: ' + ', '.join(names))
PY
)"
asset_url="$(printf '%s\n' "$asset_info" | sed -n '1p')"
asset_digest="$(printf '%s\n' "$asset_info" | sed -n '2p')"

install_dir="${CACHE_ROOT}/${version}/${platform}-${arch}"
binary="${install_dir}/sing-box"
if [[ ! -x "$binary" ]]; then
  archive="$(mktemp)"
  extract_dir="$(mktemp -d)"
  trap 'rm -f "$release_json" "${archive:-}"; rm -rf "${extract_dir:-}"' EXIT
  log "downloading ${asset_url}"
  curl -fL --retry 3 --retry-all-errors "$asset_url" -o "$archive"
  if [[ "$asset_digest" == sha256:* ]]; then
    expected_sha256="${asset_digest#sha256:}"
    actual_sha256="$(python3 - "$archive" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
print(h.hexdigest())
PY
)"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
      printf 'error: release asset SHA-256 mismatch\n' >&2
      exit 1
    fi
    log 'verified release asset SHA-256 digest'
  fi
  tar -xzf "$archive" -C "$extract_dir"
  found="$(find "$extract_dir" -type f -name sing-box -perm -u+x -print -quit)"
  if [[ -z "$found" ]]; then
    printf 'error: sing-box binary not found in downloaded archive\n' >&2
    exit 1
  fi
  mkdir -p "$install_dir"
  install -m 0755 "$found" "$binary"
fi

rule_source_url="https://raw.githubusercontent.com/SagerNet/sing-box/${tag}/constant/rule.go"
rule_source="$(mktemp)"
trap 'rm -f "$release_json" "$rule_source" "${archive:-}"; rm -rf "${extract_dir:-}"' EXIT
curl -fsSL "$rule_source_url" -o "$rule_source"
current_ruleset_version="$(python3 - "$rule_source" <<'PY'
import re, sys
text = open(sys.argv[1], 'r', encoding='utf-8').read()
m = re.search(r'RuleSetVersionCurrent\s*=\s*RuleSetVersion(\d+)', text)
if m:
    print(m.group(1))
    raise SystemExit(0)
versions = [int(x) for x in re.findall(r'RuleSetVersion(\d+)', text)]
if not versions:
    raise SystemExit('could not determine RuleSetVersionCurrent')
print(max(versions))
PY
)"

actual_version="$($binary version | sed -nE 's/^sing-box version[[:space:]]+([^[:space:]]+).*/\1/p' | head -n1)"
if [[ -z "$actual_version" ]]; then
  printf 'error: downloaded sing-box failed version check\n' >&2
  exit 1
fi

{
  printf 'SING_BOX_VERSION=%q\n' "$version"
  printf 'SING_BOX_TAG=%q\n' "$tag"
  printf 'SING_BOX_BIN=%q\n' "$binary"
  printf 'SING_BOX_ASSET_URL=%q\n' "$asset_url"
  printf 'SING_BOX_ASSET_DIGEST=%q\n' "${asset_digest:-}"
  printf 'RULESET_VERSION_CURRENT=%q\n' "$current_ruleset_version"
} > "$META_FILE"

log "ready: sing-box ${actual_version}, RuleSetVersionCurrent=${current_ruleset_version}"
printf '%s\n' "$META_FILE"
