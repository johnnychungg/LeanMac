# AGENTS.md

Instructions for coding agents (and humans) working on LeanMac, a pure-Swift menu bar app for macOS 14+.
This file stays at the repository root because agent tools look for it there. `CLAUDE.md` only imports it.
Human-oriented docs: [README.md](README.md), [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md), [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md), [.github/SECURITY.md](.github/SECURITY.md).

## Project overview
- SwiftPM, `swift-tools-version: 5.9` (do not raise it), AppKit + SwiftUI, GPL-3.0-only, every source file has an SPDX header.
- Bundle ID stays `com.local.jmac` so granted permissions are not lost. The app hides from the Dock (`LSUIElement`).
- The only network code is the update check (`Docs/adr/0004-update-check.md`); do not add other networking without a new ADR.
  Releases: `Scripts/release.sh X.Y.Z` (see `Docs/releasing.md`); the version lives in `App/Bundle/Info.plist` only.

## Layout
- `Sources/LeanDomain`: logic and ports. No AppKit, IOKit or `Process`.
- `Sources/LeanDesignSystem`: shared UI components.
- `Sources/LeanPlatform`: adapters for IOKit, `Process`, AppKit.
- `Sources/LeanFeatures`: view models and views per feature. New tabs are registered in `Shell/FeatureRegistry.swift`.
- `App/Sources/LeanMac`: composition root (`AppContainer`). `App/Bundle`: Info.plist, icon, `Helper/`, `Localization/`.
- `Tests/*` (`LeanTestSupport` holds the fakes), `Scripts/`, `ThirdParty/`.

## Setup and build
```bash
swift build -c release        # compile
./build.sh --no-run           # package build/LeanMac.app
./build.sh --dev --no-run     # contributor mode: no helper, no SMC writes
./build.sh                    # install into /Applications and launch (stops the running copy with pkill)
```
Sign with the fixed identity `JMac Self-Signed` (`Scripts/setup-signing-identity.sh`), never ad-hoc, or the Accessibility
permission is lost on every build. Log file: `~/Library/Logs/LeanMac/leanmac.log` (`appLog()`).

## Testing and checks
Run all of these before finishing a change:
```bash
swift test                              # needs full Xcode (Swift Testing)
Scripts/check-architecture.sh
python3 Scripts/check-l10n.py
Scripts/check-license-header.sh
Scripts/test-helper.sh
```

## Code style
- New UI text, logs, identifiers and comments are in English. Visible strings go through `tr("English text")`; translations live
  in `App/Bundle/Localization/<code>.lproj`.
- Follow the Swift API Design Guidelines: UpperCamelCase types and files, lowerCamelCase members.
- Managers are `@MainActor`. Never run heavy `Process` or shell work on the main thread.
- Do not add to `Docs/architecture-allowlist.txt`; it may only shrink.

## Privileged helper (security-sensitive)
- Build sudo commands only through `PrivilegedHelper.sudoCommand`; arguments go through `HelperCommand` / `ChargeLimit`.
- Helper paths and `requiredVersion` are locked by a test. Changing the behavior of `App/Bundle/Helper/leanmac-power` means
  bumping `HELPER_VERSION` and `PrivilegedHelper.requiredVersion` together (comment-only edits do not).
- `BatteryManager` sends helper commands through its serial `helperQueue` so they cannot be reordered; never block that queue on the main thread.
- Never write to a predictable path under `/tmp` as root. The installer receives its payload inline (`HelperInstallCommand`).

## Commits and pull requests
- Small, focused changes with a clear message. Do not commit build output, `.audit/`, keys or certificates.
- Anything touching the helper, the SMC or the installer needs a review from the code owner (`.github/CODEOWNERS`).
