# Changelog

All notable changes to LeanMac. Versions follow [Semantic Versioning](https://semver.org); every release is signed, see [releasing.md](releasing.md).

## 1.1.8 - 2026-11-26

### Added
- **Six interface languages.** Settings > Language is now a dropdown with English, Tiếng Việt, 日本語, 简体中文, 한국어 and Español, including the macOS permission prompts. Translations are new and welcome for native-speaker review.

### Changed
- The language row, README and translation guide list the new languages.

## 1.1.7 - 2026-11-26

### Added
- **Display tuning** (Hardware > Displays). Compares your displays by UI points per inch, matches them to the built-in screen, picks each display's best refresh rate and flags modes that macOS resizes. Applying changes asks you to confirm and goes back automatically after 15 seconds, so a bad mode can never trap you.
- **Appearance**: Auto, Light and Dark now take effect immediately, and the header logo follows the chosen scheme.

### Changed
- Updates card shows just the version, and its buttons no longer squeeze the message.
- The "Charge locked at N%" notification appears once per lock, not on every launch (at least 12 hours apart).
- The network row in Monitor is labelled "Network".
- The popover no longer shows the arrow that pointed at the menu bar icon.

## 1.1.0 - 2026-11-26

First public release.

### Added
- **Signed updates.** LeanMac tells you when a new version exists, and downloads and installs it only after you press Install. The update manifest is signed, the download is checked against its SHA-256 and the app's code signature, and downgrades are refused.
- **Fan speeds** in the Monitor tab (read only; fans are never controlled). Idle fans show "Idle, fans stopped".
- The header shows the colored logo and the app version.
- The helper row in Settings shows Installed, Update needed or Not installed, and a newer helper is detected and offered automatically.

### Changed
- Cleaner lists only what it can clean; folders owned by macOS are hidden instead of shown locked.
- The "Last sleep" report follows the interface language.
- The Appearance label no longer wraps.
