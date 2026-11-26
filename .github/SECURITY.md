# Security policy

## Reporting
Please report vulnerabilities privately (GitHub private vulnerability reporting / Security Advisories on this repository) rather than in public issues. Expect an acknowledgement within a few days.

## Threat model
LeanMac runs as the logged-in user. Its only network code is the update check (see below); there is no telemetry. The only elevated component is the privileged helper:

- `/Library/PrivilegedHelperTools/com.local.leanmac.power` and `.smc`, invoked through a sudoers rule (`/etc/sudoers.d/leanmac_power`) limited to a single user.
- Arguments reach the helper only through the typed `HelperCommand` (charge limit is clamped to 20...100). `PrivilegedHelper.sudoCommand` is the single place a sudo line is built; `Scripts/check-architecture.sh` and the unit tests enforce this.
- Installation is explicit and user-initiated (`install-helper.sh`). The privileged payload (`smc`, `leanmac-power`, `install-helper.sh`) is read into memory by the app and passed inline (base64) inside the administrator-prompt command, then unpacked by root into a fresh `mktemp -d`; no user-writable staging folder exists, so it cannot be swapped between check and use. This closes the race against an unmodified app; a same-user attacker who rewrites the user-owned app bundle before install remains out of scope; a version check (`requiredVersion`) forces reinstall after helper changes.

Out of scope: an attacker who already has code execution as the same user, or root.

## Hardening checklist for contributors
- Never interpolate untrusted strings into a command; use argv arrays (`Shell.runner.execute`).
- Validate every new helper argument and add a test in `PrivilegedHelperTests`.

## Updates
- The app downloads an update only after you press Install. The release manifest (`update.json`) must carry a valid Ed25519
  signature (`update.json.sig`) made with the maintainer's key, whose public half is compiled into the app. A downloaded
  zip must match the SHA-256 in that manifest, and the unpacked app must satisfy the designated requirement of the running
  app (same signing identity), so a tampered or foreign build is refused. Older versions are never offered.
- The updater never runs as root and never touches the privileged helper. If the helper changes, the existing version check
  asks you to reinstall it.
- Out of scope: a compromise of the maintainer's Mac, signing key or GitHub account.
- Report a flaw in this chain privately, as described above.
