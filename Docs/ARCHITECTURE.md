# Architecture

LeanMac is a menu bar app split into four SwiftPM libraries and one executable. The split is enforced by `Scripts/check-architecture.sh`.

| Target | May import | Contains |
|---|---|---|
| `LeanDomain` | Foundation, CoreGraphics, Combine | Models, pure logic, **Ports** (protocols), localization, logging. No `Process`, AppKit or IOKit. |
| `LeanDesignSystem` | SwiftUI, AppKit | `Theme` tokens and `J*` controls. |
| `LeanPlatform` | Domain, IOKit, AppKit, Process | Adapters that implement the ports (IOKit battery reader, sudo helper gateway, shell runner, notifications...). |
| `LeanFeatures` | Domain, DesignSystem | View models and views, one folder per feature. Platform/IOKit imports are allowed only for files listed in `Docs/architecture-allowlist.txt` (a debt list that may only shrink). |
| `LeanMac` (App) | everything | Composition root: `AppContainer` installs the real adapters, `AppDelegate` owns the status item and popover. |
| `LeanTestSupport` | Domain | Fakes (`FakeShellRunner`, `FakeBatteryServices`) for tests. |

```
LeanMac (App) ──► LeanFeatures ──► LeanDesignSystem
      │                │
      ├──► LeanPlatform └──► LeanDomain
      └──────────────────────────► LeanDomain
```

## Rules
1. Domain never depends on anything but Foundation/CoreGraphics/Combine.
2. Hardware, shell and privileged access go through a port in `Domain/Ports`, implemented in `Platform`.
3. The only place that builds a `sudo` command line is `PrivilegedHelper.sudoCommand`. Helper arguments are typed (`HelperCommand`, `ChargeLimit`).
4. Tabs are registered in `Features/Shell/FeatureRegistry.swift`.
5. User-visible strings and log lines are English source text through `tr("…")`; translations live in `App/Bundle/Localization/<code>.lproj`.

## Known debt (tracked, not hidden)
- Features still importing Platform/IOKit: see the allowlist.
- Most features still use `.shared` singletons; `FeatureContext` is the seam meant to replace them.
- `ThermalManager` opens AppleSMC directly.
- Some code comments are still Vietnamese.

## Dev mode
`LEANMAC_DEV=1` (or `./build.sh --dev`) makes the helper gateway, charge ceiling and Bluetooth read-only so contributors can run the app without the privileged helper or writing to the SMC.
