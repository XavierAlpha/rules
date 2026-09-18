#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import html
import json
import os
from pathlib import Path
import shutil
import sys
from urllib.parse import quote
import zipfile
from datetime import datetime, timezone


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def srs_format_version(path: Path) -> int:
    with path.open("rb") as f:
        header = f.read(4)
    if len(header) != 4 or header[:3] != b"SRS":
        raise SystemExit(f"invalid sing-box SRS header: {path}")
    return header[3]


def url_path(path: str) -> str:
    return "/".join(quote(part) for part in path.split("/"))


def raw_url(repo: str, branch: str, path: str) -> str | None:
    if not repo:
        return None
    return f"https://raw.githubusercontent.com/{repo}/{quote(branch, safe='')}/{url_path(path)}"


def zip_paths(output: Path, base: Path, paths: list[Path]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(paths):
            if path.is_file():
                zf.write(path, path.relative_to(base).as_posix())


def main() -> int:
    root = Path(os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[1]))
    dist = Path(os.environ.get("DIST_DIR", root / "dist"))
    if not dist.is_absolute():
        dist = root / dist
    source_dir = dist / "source"
    srs_dir = dist / "srs"

    version = os.environ["SING_BOX_VERSION"]
    tag = os.environ.get("SING_BOX_TAG", f"v{version}")
    ruleset_version = int(os.environ["RULESET_VERSION_CURRENT"])
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    commit = os.environ.get("GITHUB_SHA", "")
    publish_branch = os.environ.get("PUBLISH_BRANCH", "release")
    asset_url = os.environ.get("SING_BOX_ASSET_URL", "")
    asset_digest = os.environ.get("SING_BOX_ASSET_DIGEST", "")
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    entries: list[dict] = []
    for source in sorted(source_dir.rglob("*.json")):
        rel = source.relative_to(source_dir)
        srs = srs_dir / rel.with_suffix(".srs")
        if not srs.is_file():
            raise SystemExit(f"missing SRS output for {source}: {srs}")
        try:
            data = json.loads(source.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"cannot read source metadata from {source}: {exc}") from exc

        source_path = (Path("source") / rel).as_posix()
        srs_path = (Path("srs") / rel.with_suffix(".srs")).as_posix()
        entries.append(
            {
                "name": rel.with_suffix("").as_posix(),
                "source_path": source_path,
                "srs_path": srs_path,
                "source_version": data.get("version"),
                "compiler_rule_set_version_current": ruleset_version,
                "requested_source_version_for_compile": ruleset_version,
                "srs_format_version": srs_format_version(srs),
                "rule_objects": len(data.get("rules", [])) if isinstance(data.get("rules"), list) else None,
                "source_size": source.stat().st_size,
                "srs_size": srs.stat().st_size,
                "source_sha256": sha256(source),
                "srs_sha256": sha256(srs),
                "source_url": raw_url(repo, publish_branch, source_path),
                "srs_url": raw_url(repo, publish_branch, srs_path),
            }
        )

    manifest = {
        "schema": 1,
        "generated_at": generated_at,
        "repository": repo or None,
        "commit": commit or None,
        "publish_branch": publish_branch,
        "sing_box": {
            "version": version,
            "tag": tag,
            "rule_set_version_current": ruleset_version,
            "asset_url": asset_url or None,
            "asset_digest": asset_digest or None,
        },
        "policy": {
            "source_files_preserved_unchanged": True,
            "temporary_compile_copy_upgraded_to_current_rule_set_version": True,
            "official_compiler_may_downgrade_srs_to_lowest_compatible_format_version": True,
        },
        "count": len(entries),
        "files": entries,
        "downloads": {
            "source_zip": "downloads/rules-source.zip",
            "srs_zip": "downloads/rules-srs.zip",
            "complete_zip": "downloads/rules-complete.zip",
        },
    }
    manifest_path = dist / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    readme_lines = [
        "# Generated sing-box rule sets",
        "",
        f"- Generated: `{generated_at}`",
        f"- sing-box: `{version}`",
        f"- RuleSetVersionCurrent: `{ruleset_version}`",
        f"- Source files: `{len(entries)}`",
        "",
        "The JSON under `source/` is copied byte-for-byte from the repository input. The `.srs` files under `srs/` are compiled by the latest selected sing-box from temporary copies upgraded to RuleSetVersionCurrent. sing-box may write a lower SRS format version when the rules do not require newer fields; the actual version is recorded below and in manifest.json.",
        "",
        "## Files",
        "",
        "| Rule set | Source JSON | Binary SRS | SRS format | SHA256 (SRS) |",
        "|---|---|---|---:|---|",
    ]
    for item in entries:
        source_link = item["source_url"] or item["source_path"]
        srs_link = item["srs_url"] or item["srs_path"]
        readme_lines.append(
            f"| `{item['name']}` | [JSON]({source_link}) | [SRS]({srs_link}) | v{item['srs_format_version']} | `{item['srs_sha256']}` |"
        )
    readme_lines += [
        "",
        "## Bundles",
        "",
        "- `downloads/rules-source.zip` — all original JSON source files",
        "- `downloads/rules-srs.zip` — all compiled SRS files",
        "- `downloads/rules-complete.zip` — source, SRS and metadata",
        "- `SHA256SUMS` — checksums for published files",
        "",
    ]
    (dist / "README.md").write_text("\n".join(readme_lines), encoding="utf-8")

    rows = []
    for item in entries:
        rows.append(
            "<tr>"
            f"<td><code>{html.escape(item['name'])}</code></td>"
            f"<td><a href=\"{html.escape(item['source_path'])}\">JSON</a></td>"
            f"<td><a href=\"{html.escape(item['srs_path'])}\">SRS</a></td>"
            f"<td>v{item['srs_format_version']}</td>"
            f"<td>{item['source_size']}</td>"
            f"<td>{item['srs_size']}</td>"
            "</tr>"
        )
    index = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>sing-box rule sets</title>
<style>
body{{font-family:system-ui,-apple-system,sans-serif;max-width:1080px;margin:40px auto;padding:0 20px;line-height:1.5}}table{{border-collapse:collapse;width:100%}}th,td{{border-bottom:1px solid #ddd;padding:10px;text-align:left}}code{{word-break:break-all}}.meta{{color:#555}}a{{text-decoration:none}}
</style>
</head>
<body>
<h1>sing-box rule sets</h1>
<p class="meta">Generated {html.escape(generated_at)} with sing-box {html.escape(version)} · RuleSetVersionCurrent {ruleset_version}</p>
<p><a href="downloads/rules-source.zip">Source ZIP</a> · <a href="downloads/rules-srs.zip">SRS ZIP</a> · <a href="downloads/rules-complete.zip">Complete ZIP</a> · <a href="manifest.json">manifest.json</a> · <a href="SHA256SUMS">SHA256SUMS</a></p>
<table><thead><tr><th>Rule set</th><th>Source</th><th>SRS</th><th>SRS format</th><th>JSON bytes</th><th>SRS bytes</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
</body>
</html>
"""
    (dist / "index.html").write_text(index, encoding="utf-8")
    (dist / ".nojekyll").write_text("", encoding="utf-8")

    downloads = dist / "downloads"
    if downloads.exists():
        shutil.rmtree(downloads)
    downloads.mkdir(parents=True)
    source_files = [p for p in source_dir.rglob("*") if p.is_file()]
    srs_files = [p for p in srs_dir.rglob("*") if p.is_file()]
    zip_paths(downloads / "rules-source.zip", dist, source_files)
    zip_paths(downloads / "rules-srs.zip", dist, srs_files)
    complete_paths = source_files + srs_files + [manifest_path, dist / "README.md", dist / "index.html"]
    zip_paths(downloads / "rules-complete.zip", dist, complete_paths)

    checksum_targets = [
        p
        for p in dist.rglob("*")
        if p.is_file() and p.name != "SHA256SUMS" and p.name != "build-summary.md"
    ]
    checksum_lines = [f"{sha256(p)}  {p.relative_to(dist).as_posix()}" for p in sorted(checksum_targets)]
    (dist / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

    summary = [
        "## sing-box ruleset build",
        "",
        f"- sing-box: **{version}**",
        f"- RuleSetVersionCurrent: **{ruleset_version}**",
        f"- Compiled rule sets: **{len(entries)}**",
        f"- Generated: `{generated_at}`",
        "",
        "| Rule set | Source version | SRS format | SRS bytes |",
        "|---|---:|---:|---:|",
    ]
    for item in entries:
        summary.append(
            f"| `{item['name']}` | `{item['source_version']}` | `v{item['srs_format_version']}` | {item['srs_size']} |"
        )
    (dist / "build-summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")

    print(f"generated metadata and bundles for {len(entries)} rule set(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
