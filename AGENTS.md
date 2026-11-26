# AGENTS.md — LeanMac

A pure-Swift menu bar app for macOS 14+ (SwiftPM, AppKit, SwiftUI). The bundle ID stays `com.local.jmac` so granted
permissions are not lost; the app hides from the Dock (`LSUIElement`). GPLv3, aimed at community contributions.

## Layout (see ARCHITECTURE.md)
- `Sources/LeanDomain` (logic + ports; no AppKit/IOKit/Process), `LeanDesignSystem`, `LeanPlatform` (IOKit/Process/AppKit
  adapters), `LeanFeatures` (view models + views per feature), `App/Sources/LeanMac` (composition root: `AppContainer`),
  `Tests/*`, `LeanTestSupport` (fakes).
- Bundle: `App/Bundle` (Info.plist, icon, `Helper/`, `Localization/`). Scripts: `Scripts/`. Third-party: `ThirdParty/`.
- A new tab is registered in `Sources/LeanFeatures/Shell/FeatureRegistry.swift`.

## Build and checks
- `swift build -c release`; `./build.sh --no-run` packages `build/LeanMac.app` (`--dev` = contributor mode, no helper, no SMC
  writes); `./build.sh` installs into `/Applications` and launches it (it stops the running copy with `pkill`).
- `swift test` needs full Xcode (Swift Testing).
- Before finishing: `Scripts/check-architecture.sh`, `python3 Scripts/check-l10n.py`, `Scripts/check-license-header.sh`,
  `Scripts/test-helper.sh`.
- Sign with the fixed identity `JMac Self-Signed` (`Scripts/setup-signing-identity.sh`), never ad-hoc (the Accessibility
  permission would be lost on every build).
- Log: `~/Library/Logs/LeanMac/leanmac.log` (`appLog()`).

## Conventions
- New UI text, logs, names and comments are in English; visible strings go through `tr("English text")`, translations live
  in `App/Bundle/Localization/<code>.lproj`.
- Do not add to `Docs/architecture-allowlist.txt` (it may only shrink).
- Managers are `@MainActor`; never run heavy `Process`/shell work on the main thread.
- Keep `swift-tools-version: 5.9`. No network, no auto-update (ADR 0002).
- Privileged helper: build sudo commands only through `PrivilegedHelper.sudoCommand`; arguments go through
  `HelperCommand`/`ChargeLimit`. The helper paths and `requiredVersion` are locked by a test. Changing `leanmac-power`
  behavior means bumping `HELPER_VERSION` and `requiredVersion` together.
- Helper commands from `BatteryManager` go through its serial `helperQueue` so they cannot be reordered.
