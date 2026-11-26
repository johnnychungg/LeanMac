# ADR 0004: Update check with user-confirmed install

Status: accepted (supersedes the "no network" part of ADR 0002)

## Decision
LeanMac may contact GitHub for one purpose: to learn whether a newer release exists, and, after the user presses
"Install", to download it. Nothing else may use the network.

- **Check:** at most once a day (one check shortly after launch, one when the popover opens; no repeating timer).
  Turn it off in Settings > Updates. It sends no identifiers, only a generic User-Agent, over HTTPS to `github.com`
  and the release asset hosts (every redirect is checked against that allowlist).
- **Trust:** each release publishes `update.json` and `update.json.sig`. The signature is Ed25519 over the exact manifest
  bytes; the public key is compiled into the app (`UpdateConfig.publicKeyBase64`). The private key stays in the
  maintainer's keychain and never in this repository. An empty key switches the updater off.
- **Policy:** a manifest is accepted only if its signature is valid, its version is strictly newer than the running
  one (no rollback), the minimum macOS is met, and its URLs point into this repository's release path.
- **Install (user level, never root, never the privileged helper):** download into a private cache folder, check the
  SHA-256 from the manifest, unpack, then require that the new bundle has our bundle ID, the announced version, and
  passes `SecStaticCodeCheckValidity` against the RUNNING app's designated requirement. For our self-signed
  identity that pins the maintainer's certificate, so a bundle signed by anyone else is refused, and the Accessibility
  permission, which is tied to the same requirement, survives.
- **Swap:** a static script (arguments only, no interpolation) waits for this process to exit, moves the old bundle
  aside, copies the new one, launches it, and restores the old bundle if the copy fails.
- **Fallback to "open the release page":** the app is not in a writable folder, runs from a quarantined
  (translocated) location, or the identity differs (for example a build made from source).
- Contributor builds (`LEANMAC_DEV=1`) never check or install.

## Consequences
- A small, new attack surface: the manifest parser, the downloader and the swap script. The parser, the install policy and the
  manager are covered by tests; the downloader's redirect delegate and the full swap on real hardware are checked by hand.
- Quitting for the swap runs the normal quit path, which briefly releases the charge limit until the new copy starts.
- Losing the signing key means installed apps can no longer verify a release; keep a backup.
- Builds from before this feature must be updated once by hand.
- Releases must be built on the maintainer's Mac with the fixed identity; they cannot come from a CI runner unless
  the certificate and the key are stored as CI secrets (a deliberate, separate decision).
