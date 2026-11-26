# Changelog

## 1.1.4 - 2026-11-26

- Monitor: label the network row Network
- Displays: add a display check that matches UI size and refresh rate, with confirm and auto-revert; hide the popover arrow

## 1.1.3 - 2026-11-26

- Appearance: resolve Auto to a concrete scheme at once and redraw the header logo for the chosen scheme
- Updates card: keep Install and Skip on the message row; only error buttons go below

## 1.1.2 - 2026-11-26

- README: add Monitor and Displays screenshots; debug hook for the hardware sub-tab
- README: describe the app, add screenshots, install and trust sections
- Updates card: give the buttons their own row so messages are not squeezed

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

