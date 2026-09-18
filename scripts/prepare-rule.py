#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a temporary source-format JSON using the current sing-box rule-set version"
    )
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--current-version", type=int, required=True)
    args = parser.parse_args()

    src = Path(args.input)
    dst = Path(args.output)
    with src.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        raise SystemExit(f"invalid sing-box rule-set source: {src}")

    old_version = data.get("version")
    if old_version is not None:
        if isinstance(old_version, bool) or not isinstance(old_version, int) or old_version < 1:
            raise SystemExit(f"invalid source version in {src}: {old_version!r}")
        if old_version > args.current_version:
            raise SystemExit(
                f"source version {old_version} is newer than compiler rule-set version {args.current_version}: {src}"
            )

    data["version"] = args.current_version
    dst.parent.mkdir(parents=True, exist_ok=True)
    with dst.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
