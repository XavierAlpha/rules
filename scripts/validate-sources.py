#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def validate_file(path: Path, current_version: int | None) -> list[str]:
    errors: list[str] = []
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        return [f"invalid JSON: {exc}"]

    if not isinstance(data, dict):
        return ["top level must be a JSON object"]

    rules = data.get("rules")
    if not isinstance(rules, list):
        errors.append('required field "rules" must be an array')
    else:
        for i, rule in enumerate(rules):
            if not isinstance(rule, dict):
                errors.append(f"rules[{i}] must be an object")
                if len(errors) >= 20:
                    errors.append("too many errors; remaining rule checks skipped")
                    break

    version = data.get("version")
    if version is not None:
        if isinstance(version, bool) or not isinstance(version, int):
            errors.append('field "version" must be an integer when present')
        elif version < 1:
            errors.append('field "version" must be >= 1')
        elif current_version is not None and version > current_version:
            errors.append(
                f"source version {version} is newer than current sing-box rule-set version {current_version}"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate sing-box source-format rule-set JSON files")
    parser.add_argument("rules_dir", nargs="?", default="rules")
    parser.add_argument("--current-version", type=int)
    args = parser.parse_args()

    root = Path(args.rules_dir)
    if not root.is_dir():
        print(f"error: rules directory not found: {root}", file=sys.stderr)
        return 2

    files = sorted(p for p in root.rglob("*.json") if p.is_file())
    if not files:
        print(f"error: no .json files found under {root}", file=sys.stderr)
        return 2

    failed = False
    for path in files:
        errors = validate_file(path, args.current_version)
        if errors:
            failed = True
            for error in errors:
                print(f"ERROR {path}: {error}", file=sys.stderr)
        else:
            print(f"OK    {path}")

    if failed:
        return 1
    print(f"validated {len(files)} rule-set source file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
