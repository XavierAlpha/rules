# Contributing

1. Add or edit source-format JSON under `rules/`.
2. Run `./scripts/validate-sources.py rules` for a fast structural check.
3. Run `./scripts/build.sh` for a full compile/decompile verification.
4. Commit only source and project files; generated `dist/` output is published by GitHub Actions.
