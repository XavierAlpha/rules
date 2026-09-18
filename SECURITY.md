# Security notes

The default workflow resolves sing-box from the official `SagerNet/sing-box` GitHub Releases API and uses only the latest non-prerelease release returned by `/releases/latest`.

When the GitHub release API exposes a `sha256:` digest for the selected archive, the installer verifies that digest before extraction. It then checks `sing-box version`. Every generated SRS is decompiled again by the same sing-box binary, and all published files receive SHA-256 checksums.

For stricter supply-chain control, set `SING_BOX_VERSION` to a specific release and pin third-party GitHub Actions to immutable commit SHAs according to your own repository policy.
