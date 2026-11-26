# LeanMac

A menu bar toolbox for macOS 14+ (Apple Silicon), written in plain Swift. The interface is English by default
with a Vietnamese translation (see `App/Bundle/Localization`).

Copyright (C) 2026 Johnny Chung. Licensed under GPL-3.0-only, see [LICENSE](LICENSE).

## Features
- Window snapping, moving windows between displays, a multi-row ⌘Tab switcher with thumbnails
- Finder cut/paste
- Charge limit (SMC), sleep guard, Bluetooth switched off when the lid is closed
- Temperature, CPU, RAM and GPU shown as separate items in the menu bar
- External display brightness (DDC), resolution and refresh rate
- Screenshots with annotations, cache/junk cleaner, large-file finder, app uninstaller (moves files to the Trash)

Deliberately left out because they are risky: fan control, process freezing, virtual displays / disconnecting
displays, clipboard history, mouse chords, hiding menu bar icons, disk speed tests.

The charge limit has a watchdog: if LeanMac is killed, the helper releases the lock by itself after about 30 seconds.

## Status and trust
This is an early community release. Please read these before installing:
- **Privileged helper.** The charge limit needs a small root helper (`/Library/PrivilegedHelperTools/com.local.leanmac.*`)
  plus a sudoers rule for one user. Installing it asks for your administrator password. Without it the app still runs
  (`./build.sh --dev` builds a contributor mode that never writes the SMC). Details: [Docs/SECURITY.md](Docs/SECURITY.md).
- **Private macOS interfaces.** A few features use undocumented APIs that may break on any macOS update; the list is in
  [Docs/third-party.md](Docs/third-party.md). They fail soft (the feature turns off).
- **Battery behavior changes** (charge limit, calibration) have been tested on a limited set of Macs. Try them while
  watching the battery, and report problems.
- **Display modes** are applied permanently (no automatic revert). If a resolution or refresh rate leaves the screen unusable,
  switch back in System Settings > Displays (use the keyboard or another display if the screen is unreadable).
- **Self-signed builds.** The app is not notarized. You build it yourself and sign it with a local identity.
- No network access, no telemetry, no auto-update.

## Build
```bash
./Scripts/setup-signing-identity.sh   # once; keeps the Accessibility permission across rebuilds
./build.sh --no-run                   # builds build/LeanMac.app
./build.sh --dev --no-run             # contributor mode: no helper, no SMC writes
./build.sh                            # builds, installs into /Applications and launches
swift test                            # needs full Xcode
```

Requirements: macOS 14+, Xcode (or the Command Line Tools), OpenSSL 3 (`brew install openssl`) for the signing script.
Logs go to `~/Library/Logs/LeanMac/leanmac.log`.

## Contributing
See [Docs/CONTRIBUTING.md](Docs/CONTRIBUTING.md), [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md), [Docs/SECURITY.md](Docs/SECURITY.md) and [Docs/CODE_OF_CONDUCT.md](Docs/CODE_OF_CONDUCT.md).
