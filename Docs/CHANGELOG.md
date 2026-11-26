# Changelog

## 1.1.7 - 2026-11-26

- Display tuning (Hardware > Displays): matches the UI size on every display to the built-in screen, picks each display's best refresh rate, and applies the result only after you confirm, with an automatic revert after 15 seconds.
- Appearance: Auto now switches at once, and the header logo follows Light and Dark.
- Updates: the card shows the version only, and its buttons no longer squeeze the message.
- Charge-locked notice: shown once per lock instead of on every launch.
- Monitor: the network row is labelled "Network".
- The popover no longer shows its arrow.

## 1.1.0 - 2026-11-26

- Fan row: say the fans are stopped instead of showing 0 rpm
- Header: drop the battery/lock chip
- Header: drop the temperature chip (the Monitor tab already shows it)
- Header: keep the app name and version on one line
- Monitor: show fan speeds; header: colored logo and version; single-line update row; helper row shows installed state only and offers a newer helper
- Cleaner: hide macOS-owned cache and log folders instead of listing them locked
- Fix Appearance label wrapping, localize the last sleep report, show app version for the helper
- Show the app version and build in Settings > Updates
- Provision the update signing public key
- Add versioning and a signed, user-confirmed update flow
- Move CONTRIBUTING, SECURITY and CODE_OF_CONDUCT into .github/
- Move community docs into Docs/ and CODEOWNERS into .github/
- Restructure AGENTS.md into standard sections
- Add CLAUDE.md that imports AGENTS.md
- Initial public release of LeanMac

