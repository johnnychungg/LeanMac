# Releasing

Versions follow SemVer (`MAJOR.MINOR.PATCH`). The single source of truth is `App/Bundle/Info.plist`:
`CFBundleShortVersionString` is the version and `CFBundleVersion` is an integer build number that only goes up.
Releases are built on the maintainer's Mac with the fixed signing identity, never ad-hoc.

## One-time setup
1. `Scripts/setup-signing-identity.sh` (the identity users' Accessibility permission is tied to; keep it for every release).
2. `Scripts/updater-keygen.sh`: creates the Ed25519 update key in your login keychain and prints the public key.
   Paste it into `UpdateConfig.publicKeyBase64` (`Sources/LeanDomain/Update/UpdateManifest.swift`), commit it, and ship a
   first release with it. **Back the key up**: without it no installed app can verify a later release.

## Every release
```bash
Scripts/release.sh 1.1.0
```
It runs all checks and tests, bumps the plist, writes `Docs/CHANGELOG.md` from the commit subjects since the last tag,
builds, refuses an ad-hoc signature, zips `LeanMac.app`, and writes and signs `dist/update.json`. It never commits, tags
or publishes. Then follow the commands it prints: commit, tag `vX.Y.Z`, push, and
`gh release create vX.Y.Z dist/LeanMac-X.Y.Z.zip dist/update.json dist/update.json.sig`.

The app finds the latest release through `releases/latest/download/update.json`, so a release is live for users as soon as it is
published (draft and pre-releases are not served). To pull a bad release, delete it or publish a newer one; versions never roll back.

## Notes
- The first download is quarantined by macOS ("unidentified developer": right-click, Open). Later updates installed by the
  app are not quarantined.
- If a release changes `leanmac-power`, bump `HELPER_VERSION` and `PrivilegedHelper.requiredVersion` together; the app asks
  the user to reinstall the helper.
- A manifest's `minimumSystemVersion` comes from `LSMinimumSystemVersion` in the plist.
