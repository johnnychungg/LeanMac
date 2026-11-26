# Contributing to LeanMac

Thanks for helping! LeanMac is GPLv3; contributions are accepted under the same license (every source file carries an SPDX header).

## Build
```bash
swift build -c release        # compile only
./build.sh --no-run           # package build/LeanMac.app
./build.sh --dev --no-run     # contributor mode: no helper, no SMC writes
swift test                    # needs full Xcode (Swift Testing)
```
You do not need the `JMac Self-Signed` identity or the privileged helper to build and develop. Without a stable signing identity macOS will ask for Accessibility again after each build.

## Checks (run them before every pull request)
```bash
Scripts/check-architecture.sh
python3 Scripts/check-l10n.py
Scripts/check-license-header.sh
Scripts/test-helper.sh
```

## Add a feature in 6 steps (template: Caffeinate)
1. Put the logic and models in `Sources/LeanDomain/<Feature>/` (pure Swift, with tests in `Tests/LeanDomainTests`).
2. If it touches hardware, shell or the system, define a port in `Domain/Ports` and implement it in `Sources/LeanPlatform/<Feature>/`.
3. Add the view model and view in `Sources/LeanFeatures/<Feature>/`.
4. Register the tab or card (`FeatureRegistry.swift` for tabs).
5. Wrap every user-visible string in `tr("English text")` and add the Vietnamese translation to `App/Bundle/Localization/vi.lproj/Localizable.strings`; run `Scripts/check-l10n.py`.
6. Add tests using fakes from `LeanTestSupport`, then run all checks.

## Rules of the road
- English for UI, logs, identifiers and new comments.
- No network access and no auto-update (see `Docs/adr/0002-no-network.md`).
- Anything that reaches the privileged helper or writes the SMC needs a code-owner review (see `.github/CODEOWNERS`). Changing `App/Bundle/Helper/leanmac-power` also means bumping its `HELPER_VERSION` and `PrivilegedHelper.requiredVersion` together.
- Do not add to `Docs/architecture-allowlist.txt`; it may only shrink.

## Adding a language
Copy `App/Bundle/Localization/vi.lproj`, translate the values, and run `Scripts/check-l10n.py`. See `App/Bundle/Localization/README.md`.
